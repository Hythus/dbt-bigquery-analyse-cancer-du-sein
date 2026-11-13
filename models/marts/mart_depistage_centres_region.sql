with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

nb_centre_region as (

    select
        code_region,
        count(nom_centre_radiologie) as nb_centres_region
    from {{ ref('stg_centres_radiologie') }}
    group by 1

),

participation_2014_2022 as (

    select
        r.code_region,
        r.nom_region,
        e.annee,
        round(e.taux_participation_std_pct, 2) as taux_participation_std_pct
    from {{ ref('stg_depistage_evolution_2005_2025') }} e
    inner join regions r
      on case
            when e.nom_zone_geographique = 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else e.nom_zone_geographique
         end = r.nom_region
    where e.annee between 2014 and 2022
      and e.taux_participation_std_pct is not null

),

pop_cible as (

    select
        annee,
        code_region,
        population_femmes_50_74_ans as femmes_50_74,
        population_femmes_total as femmes_total
    from {{ ref('stg_pop_cible_regions') }}
    where annee between 2014 and 2022

),

pop_region as (

    select
        annee,
        code_region,
        sum(population) as population_regionale
    from {{ ref('stg_pop_regions_age') }}
    where code_sexe = 'E'
      and annee between 2014 and 2022
    group by 1, 2

),

-- Superficies officielles INSEE/IGN des régions françaises en km²
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

joined as (

    select
        p.annee,
        p.annee = 2022 as est_derniere_annee,
        p.code_region,
        p.nom_region,
        cast(nb.nb_centres_region as int64) as nb_centres_region,
        cast(pr.population_regionale as int64) as population_regionale,
        s.superficie_km2 as superficie_region_km2,
        round(safe_divide(pr.population_regionale, s.superficie_km2), 1) as densite_population_hab_km2,
        cast(pop.femmes_total as int64) as femmes_total,
        cast(pop.femmes_50_74 as int64) as femmes_50_74,
        p.taux_participation_std_pct,
        cast(round(pop.femmes_50_74 * (p.taux_participation_std_pct / 100.0)) as int64) as nb_femmes_participantes_estime,
        cast(pop.femmes_50_74 - round(pop.femmes_50_74 * (p.taux_participation_std_pct / 100.0)) as int64) as nb_femmes_non_participantes_estime,
        cast(round(safe_divide(pop.femmes_50_74, nb.nb_centres_region)) as int64) as nb_femmes_50_74_par_centre,
        round(safe_divide(nb.nb_centres_region * 100000, pop.femmes_50_74), 2) as nb_centres_pour_100k_femmes_50_74,
        round(safe_divide(nb.nb_centres_region * 100000, pr.population_regionale), 2) as densite_centres_pour_100k_hab
    from participation_2014_2022 p
    inner join nb_centre_region nb
      on p.code_region = nb.code_region
    left join pop_cible pop
      on p.code_region = pop.code_region
     and p.annee = pop.annee
    left join pop_region pr
      on p.code_region = pr.code_region
     and p.annee = pr.annee
    left join superficie s
      on p.code_region = s.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mart_depistage_region,
    *
from joined

