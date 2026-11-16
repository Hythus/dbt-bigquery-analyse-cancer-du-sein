with dep_part as (

    select
        annee_fin_periode as annee,
        code_region,
        round(avg(taux_participation_std_pct), 2) as taux_participation_depistage_std_pct
    from {{ ref('stg_depistage_taux_standardise_2016_2025') }}
    group by 1, 2

),

dep_ind as (

    select
        annee,
        code_region,
        max(case when code_indicateur = 'NC01' and tranche_age = 'Total 50-74 ans' then taux_ou_valeur_tous_rangs end) as nb_cancers_detectes_depistage,
        max(case when code_indicateur = 'NC04' and tranche_age = 'Total 50-74 ans' then taux_ou_valeur_tous_rangs end) as nb_cancers_in_situ,
        max(case when code_indicateur = 'NC08' and tranche_age = 'Total 50-74 ans' then taux_ou_valeur_tous_rangs end) as nb_cancers_inf_ou_egal_10mm,
        max(case when code_indicateur = 'PC04' and tranche_age = 'Total 50-74 ans' then taux_ou_valeur_tous_rangs end) as part_cancers_in_situ_pct,
        max(case when code_indicateur = 'PC08' and tranche_age = 'Total 50-74 ans' then taux_ou_valeur_tous_rangs end) as part_cancers_inf_ou_egal_10mm_pct,
        max(case when code_indicateur = 'TC01' and tranche_age in ('50-74 ans (standardisé)', '50-74 ans (brut)') then taux_ou_valeur_tous_rangs end) as taux_cancers_detectes_pour_1000_femmes
    from {{ ref('stg_depistage_indicateurs_cancers_regions') }}
    group by 1, 2

),

hosp as (

    select
        annee,
        code_region,
        dms_jours,
        nb_sejours_sein,
        nb_sejours_inf_ou_egal_7j,
        nb_sejours_sup_7j,
        nb_sejours_moins_24h,
        nb_patientes,
        round(safe_divide(nb_sejours_inf_ou_egal_7j * 100, nb_sejours_sein), 2) as part_sejours_courts_pct,
        round(safe_divide(nb_sejours_moins_24h * 100, nb_sejours_sein), 2) as part_sejours_ambulatoires_pct
    from {{ ref('int_charge_hospitaliere_sein') }}

),

mort as (

    select
        annee,
        code_region,
        sum(nb_deces) as nb_deces_sein,
        round(avg(taux_mortalite_std_age_pour_100000), 2) as taux_mortalite_std_moyen_pour_100000
    from {{ ref('stg_mortalite_region') }}
    where sexe = 'Femmes'
    group by 1, 2

),

regions as (

    select distinct
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

annees as (

    select distinct annee
    from unnest(generate_array(2016, 2024)) as annee

),

spine as (

    select
        a.annee,
        r.code_region,
        r.nom_region
    from annees a
    cross join regions r

),

joined as (

    select
        s.annee,
        s.code_region,
        s.nom_region,

        -- Axe 1 : Dépistage organisé (participation & détection précoce)
        dp.taux_participation_depistage_std_pct,
        cast(di.nb_cancers_detectes_depistage as int64) as nb_cancers_detectes_depistage,
        cast(di.nb_cancers_in_situ as int64) as nb_cancers_in_situ,
        cast(di.nb_cancers_inf_ou_egal_10mm as int64) as nb_cancers_inf_ou_egal_10mm,
        di.part_cancers_in_situ_pct,
        di.part_cancers_inf_ou_egal_10mm_pct,
        di.taux_cancers_detectes_pour_1000_femmes,

        -- Axe 2 : Prise en charge hospitalière & sévérité des séjours
        h.dms_jours,
        cast(h.nb_sejours_sein as int64) as nb_sejours_sein,
        cast(h.nb_sejours_inf_ou_egal_7j as int64) as nb_sejours_inf_ou_egal_7j,
        cast(h.nb_sejours_sup_7j as int64) as nb_sejours_sup_7j,
        cast(h.nb_sejours_moins_24h as int64) as nb_sejours_moins_24h,
        cast(h.nb_patientes as int64) as nb_patientes,
        h.part_sejours_courts_pct,
        h.part_sejours_ambulatoires_pct,

        -- Axe 3 : Mortalité
        cast(m.nb_deces_sein as int64) as nb_deces_sein,
        m.taux_mortalite_std_moyen_pour_100000

    from spine s
    left join dep_part dp
      on s.annee = dp.annee
     and s.code_region = dp.code_region
    left join dep_ind di
      on s.annee = di.annee
     and s.code_region = di.code_region
    left join hosp h
      on s.annee = h.annee
     and s.code_region = h.code_region
    left join mort m
      on s.annee = m.annee
     and s.code_region = m.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_impact_depistage,
    *
from joined

