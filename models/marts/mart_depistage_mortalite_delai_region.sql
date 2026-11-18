{{ config(materialized='table') }}

with regions as (

    select
        code_region,
        libelle_region as nom_region,
        zone_geographique
    from {{ ref('dim_regions') }}

),

superficie as (

    select code_region, superficie_km2
    from unnest([
        struct('01' as code_region, 1628.4 as superficie_km2),
        struct('02', 1128.0),
        struct('03', 83533.9),
        struct('04', 2503.7),
        struct('06', 374.0),
        struct('11', 12011.0),
        struct('24', 39151.0),
        struct('27', 47784.0),
        struct('28', 29907.0),
        struct('32', 31806.0),
        struct('44', 57441.0),
        struct('52', 32082.0),
        struct('53', 27208.0),
        struct('75', 84036.0),
        struct('76', 72724.0),
        struct('84', 69711.0),
        struct('93', 31400.0),
        struct('94', 8680.0)
    ])

),

depistage_historique as (

    select
        r.code_region,
        e.annee as annee_depistage,
        e.population_cible as population_cible_insee_50_74_lag,
        e.nb_femmes_depistees as nb_femmes_depistees_lag,
        round(e.taux_participation_std_pct, 2) as taux_participation_std_lag_pct,
        round(avg(e.taux_participation_std_pct) over (
            partition by r.code_region
            order by e.annee
            rows between 1 preceding and 1 following
        ), 2) as taux_participation_moy_3ans_lag_pct
    from {{ ref('stg_depistage_evolution_2005_2025') }} e
    inner join regions r
      on case
            when e.nom_zone_geographique = 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else e.nom_zone_geographique
         end = r.nom_region
    where e.type_zone_geographique = 'Région'
      and e.taux_participation_std_pct is not null

),

delais as (

    select delai_annees, ordre_delai, libelle_delai
    from unnest([
        struct(0 as delai_annees, 1 as ordre_delai, 'Lag 0 an (même année)' as libelle_delai),
        struct(3, 2, 'Lag 3 ans (t-3)'),
        struct(5, 3, 'Lag 5 ans (t-5)'),
        struct(7, 4, 'Lag 7 ans (t-7)'),
        struct(9, 5, 'Lag 9 ans (t-9)')
    ])

),

mortalite_std as (

    select
        annee,
        code_region,
        nom_region,
        nb_deces_sein_femmes,
        population_femmes_insee,
        taux_mortalite_brut_100k,
        taux_mortalite_std_tous_ages_100k,
        taux_mortalite_std_50_74_100k,
        taux_mortalite_std_65_84_100k,
        taux_mortalite_std_75_plus_100k
    from {{ ref('mart_mortalite_std_distribution_region') }}

),

pop_totale_t as (

    select
        annee,
        code_region,
        sum(population) as population_regionale_t
    from {{ ref('stg_pop_regions_age') }}
    where code_sexe = 'E'
      and annee between 2014 and 2024
    group by 1, 2

),

pop_cible_t as (

    select
        annee,
        code_region,
        population_femmes_50_74_ans as femmes_50_74_t
    from {{ ref('stg_pop_cible_regions') }}
    where annee between 2014 and 2024

),

centres as (

    select
        code_region,
        count(nom_centre_radiologie) as nb_centres_region
    from {{ ref('stg_centres_radiologie') }}
    group by 1

),

prevalence_ameli_t as (

    select
        annee,
        code_region,
        cast(max(population_regionale) as int64) as population_assurees_ameli_t,
        round(max(taux_prevalence_pct), 3) as prevalence_active_sein_pct_t
    from {{ ref('stg_effectifs_region') }}
    where code_pathologie = 'CAN_SEI_ACT'
      and annee between 2014 and 2024
    group by 1, 2

),

joined as (

    select
        m.annee as annee_mortalite,
        m.annee - d.delai_annees as annee_depistage,
        d.delai_annees,
        d.libelle_delai,
        d.ordre_delai,
        m.code_region,
        m.nom_region,
        dep.population_cible_insee_50_74_lag,
        dep.nb_femmes_depistees_lag,
        dep.taux_participation_std_lag_pct,
        dep.taux_participation_moy_3ans_lag_pct,
        m.nb_deces_sein_femmes,
        m.taux_mortalite_brut_100k,
        m.taux_mortalite_std_tous_ages_100k,
        m.taux_mortalite_std_50_74_100k,
        m.taux_mortalite_std_65_84_100k,
        m.taux_mortalite_std_75_plus_100k,
        r.zone_geographique,
        round(safe_divide(pt.population_regionale_t, s.superficie_km2), 1) as densite_population_hab_km2,
        case
            when safe_divide(pt.population_regionale_t, s.superficie_km2) < 80 then 'Faible (< 80 hab/km²)'
            when safe_divide(pt.population_regionale_t, s.superficie_km2) <= 150 then 'Intermédiaire (80-150 hab/km²)'
            else 'Forte (> 150 hab/km²)'
        end as profil_densite,
        cast(coalesce(c.nb_centres_region, 0) as int64) as nb_centres_region,
        round(safe_divide(coalesce(c.nb_centres_region, 0) * 100000.0, pc.femmes_50_74_t), 2) as nb_centres_pour_100k_femmes_50_74,
        'Inventaire statique PDF 2022-2023 (1 571 centres)' as millesime_inventaire_centres,
        m.population_femmes_insee as population_femmes_insee_t,
        am.population_assurees_ameli_t,
        am.prevalence_active_sein_pct_t
    from mortalite_std m
    cross join delais d
    inner join depistage_historique dep
      on m.code_region = dep.code_region
     and (m.annee - d.delai_annees) = dep.annee_depistage
    inner join regions r
      on m.code_region = r.code_region
    left join pop_totale_t pt
      on m.annee = pt.annee
     and m.code_region = pt.code_region
    left join pop_cible_t pc
      on m.annee = pc.annee
     and m.code_region = pc.code_region
    left join superficie s
      on m.code_region = s.code_region
    left join centres c
      on m.code_region = c.code_region
    left join prevalence_ameli_t am
      on m.annee = am.annee
     and m.code_region = am.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee_mortalite, code_region, delai_annees
    )))) as id_mart_depistage_delai,
    *
from joined
