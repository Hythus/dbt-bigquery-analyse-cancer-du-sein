with deces_sein as (

    select
        annee_deces as annee,
        code_region,
        max(nom_region) as nom_region,
        sum(nb_deces) as nb_deces_sein,
        sum(case when tranche_age_10 in ('45-54', '55-64', '65-74') then nb_deces else 0 end) as nb_deces_sein_45_74
    from {{ ref('stg_effectif_mortalite_region') }}
    where cause_initiale_deces = '2.1.10 Tumeur maligne du sein'
      and sexe = 'Femmes'
    group by 1, 2

),

deces_toutes_causes as (

    select
        annee_deces as annee,
        code_region,
        sum(nb_deces) as nb_deces_toutes_causes_femmes
    from {{ ref('stg_effectif_mortalite_toutescauses_region') }}
    where cause_initiale_deces = 'Toutes causes'
      and sexe = 'Femmes'
    group by 1, 2

),

mortalite_std as (

    select
        annee,
        code_region,
        sum(case when tranche_age = 'Moins de 65 ans' then nb_deces end) as nb_deces_sein_moins_65,
        sum(case when tranche_age = 'Entre 65 et 84 ans' then nb_deces end) as nb_deces_sein_65_84,
        sum(case when tranche_age = '85 ans et plus' then nb_deces end) as nb_deces_sein_85_plus,
        max(case when tranche_age = 'Moins de 65 ans' then taux_mortalite_std_age_pour_100000 end) as taux_std_moins_65_pour_100000,
        max(case when tranche_age = 'Entre 65 et 84 ans' then taux_mortalite_std_age_pour_100000 end) as taux_std_65_84_pour_100000,
        max(case when tranche_age = '85 ans et plus' then taux_mortalite_std_age_pour_100000 end) as taux_std_85_plus_pour_100000,
        round(avg(taux_mortalite_std_age_pour_100000), 2) as taux_mortalite_std_moyen_pour_100000
    from {{ ref('stg_mortalite_region') }}
    where sexe = 'Femmes'
    group by 1, 2

),

population as (

    select
        annee,
        code_region,
        population_femmes_total,
        population_femmes_50_74_ans
    from {{ ref('stg_pop_cible_regions') }}

),

joined as (

    select
        s.annee,
        s.code_region,
        s.nom_region,

        -- Composantes brutes (numérateurs / dénominateurs pour Power BI DAX)
        cast(s.nb_deces_sein as int64) as nb_deces_sein,
        cast(s.nb_deces_sein_45_74 as int64) as nb_deces_sein_45_74,
        cast(m.nb_deces_sein_moins_65 as int64) as nb_deces_sein_moins_65,
        cast(m.nb_deces_sein_65_84 as int64) as nb_deces_sein_65_84,
        cast(m.nb_deces_sein_85_plus as int64) as nb_deces_sein_85_plus,
        cast(tc.nb_deces_toutes_causes_femmes as int64) as nb_deces_toutes_causes_femmes,
        cast(p.population_femmes_total as int64) as population_femmes_total,
        cast(p.population_femmes_50_74_ans as int64) as population_femmes_50_74_ans,

        -- Ratios et indicateurs précalculés
        round(safe_divide(s.nb_deces_sein, tc.nb_deces_toutes_causes_femmes), 4) as part_cancer_sein_mortalite_totale,
        round(safe_divide(s.nb_deces_sein * 100000, p.population_femmes_total), 2) as taux_brut_mortalite_pour_100k_femmes,
        round(safe_divide(s.nb_deces_sein_45_74 * 100000, p.population_femmes_50_74_ans), 2) as taux_brut_50_74_pour_100k_femmes,

        -- Taux standardisés par tranche d'âge
        round(m.taux_std_moins_65_pour_100000, 2) as taux_std_moins_65_pour_100000,
        round(m.taux_std_65_84_pour_100000, 2) as taux_std_65_84_pour_100000,
        round(m.taux_std_85_plus_pour_100000, 2) as taux_std_85_plus_pour_100000,
        m.taux_mortalite_std_moyen_pour_100000

    from deces_sein s
    left join deces_toutes_causes tc
      on s.annee = tc.annee
     and s.code_region = tc.code_region
    left join mortalite_std m
      on s.annee = m.annee
     and s.code_region = m.code_region
    left join population p
      on s.annee = p.annee
     and s.code_region = p.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mortalite_territoriale,
    *
from joined
