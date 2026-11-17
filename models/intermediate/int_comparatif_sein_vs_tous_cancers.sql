with annees as (

    select distinct annee
    from {{ ref('stg_pop_regions_age') }}
    where annee between 2015 and 2024

),

regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

ages as (

    select
        code_tranche_age_5,
        age_min,
        ordre_tranche_age,
        groupe_depistage,
        est_cible_depistage,
        case
            when age_min between 25 and 34 then '25-34'
            when age_min between 35 and 44 then '35-44'
            when age_min between 45 and 54 then '45-54'
            when age_min between 55 and 64 then '55-64'
            when age_min between 65 and 74 then '65-74'
            when age_min between 75 and 84 then '75-84'
            when age_min between 85 and 94 then '85-94'
            else '95p'
        end as code_tranche_10
    from {{ ref('dim_tranches_age') }}

),

grille as (

    select
        an.annee,
        r.code_region,
        r.nom_region,
        a.code_tranche_age_5,
        a.ordre_tranche_age,
        a.groupe_depistage,
        a.est_cible_depistage,
        a.code_tranche_10
    from annees an
    cross join regions r
    cross join ages a

),

pop_age as (

    select
        annee,
        code_region,
        case
            when age_min = 95 then '95+'
            else replace(tranche_age, ' ans', '')
        end as code_tranche_age_5,
        max(case when code_sexe = 'F' then population end) as population_femmes,
        max(case when code_sexe = 'E' then population end) as population_totale
    from {{ ref('stg_pop_regions_age') }}
    where annee between 2015 and 2024
      and age_min >= 25
      and code_sexe in ('F', 'E')
    group by 1, 2, 3

),

pop_avec_parts as (

    select
        g.*,
        p.population_femmes,
        p.population_totale,
        coalesce(
            safe_divide(
                cast(p.population_femmes as float64),
                cast(sum(p.population_femmes) over (partition by g.annee, g.code_region, g.code_tranche_10) as float64)
            ),
            case when g.code_tranche_10 = '95p' then 1.0 else 0.5 end
        ) as part_pop_femmes_dans_tranche_10,
        coalesce(
            safe_divide(
                cast(p.population_totale as float64),
                cast(sum(p.population_totale) over (partition by g.annee, g.code_region, g.code_tranche_10) as float64)
            ),
            case when g.code_tranche_10 = '95p' then 1.0 else 0.5 end
        ) as part_pop_totale_dans_tranche_10
    from grille g
    inner join pop_age p
      on g.annee = p.annee
     and g.code_region = p.code_region
     and g.code_tranche_age_5 = p.code_tranche_age_5

),

mortalite_sein_10 as (

    select
        annee_deces as annee,
        code_region,
        tranche_age_10 as code_tranche_10,
        cast(nb_deces as float64) as deces_sein_10
    from {{ ref('stg_effectif_mortalite_region') }}
    where annee_deces between 2015 and 2024
      and sexe = 'Femmes'
      and cause_initiale_deces = '2.1.10 Tumeur maligne du sein'

),

mortalite_tumeurs_10 as (

    select
        annee_deces as annee,
        code_region,
        tranche_age_10 as code_tranche_10,
        cast(max(case when sexe = 'Tous sexes' then nb_deces end) as float64) as deces_tous_cancers_10,
        cast(max(case when sexe = 'Femmes' then nb_deces end) as float64) as deces_tous_cancers_femmes_10
    from {{ ref('stg_effectif_mortalite_tumeurs_region') }}
    where annee_deces between 2015 and 2024
      and cause_initiale_deces = '2.1 Tumeurs malignes'
      and sexe in ('Tous sexes', 'Femmes')
    group by 1, 2, 3

),

effectifs_actifs_age as (

    select
        annee,
        code_region,
        code_tranche_age_5,
        coalesce(
            max(case when code_pathologie = 'CAN_SEI_ACT' and sexe = 'Femmes' then nb_patients end),
            0
        ) as nb_patients_actifs_sein,
        coalesce(
            sum(case when sexe = 'Femmes' then nb_patients end),
            0
        ) as nb_patients_actifs_tous_cancers_femmes,
        coalesce(
            sum(case when sexe = 'Tous sexes' then nb_patients end),
            0
        ) as nb_patients_actifs_tous_cancers
    from {{ ref('stg_effectifs_cancers_age_region') }}
    where annee between 2015 and 2024
      and statut_cancer = 'Actif'
      and code_pathologie in ('CAN_SEI_ACT', 'CAN_BPU_ACT', 'CAN_CRE_ACT', 'CAN_PRO_ACT', 'CAN_AUT_ACT')
      and code_tranche_age_5 != 'tsage'
    group by 1, 2, 3

),

joined as (

    select
        p.annee,
        p.code_region,
        p.nom_region,
        p.code_tranche_age_5,
        p.ordre_tranche_age,
        p.groupe_depistage,
        p.est_cible_depistage,
        cast(p.population_femmes as int64) as population_femmes,
        cast(p.population_totale as int64) as population_totale,
        round(coalesce(ms.deces_sein_10, 0.0) * p.part_pop_femmes_dans_tranche_10, 2) as nb_deces_sein,
        round(coalesce(mt.deces_tous_cancers_10, 0.0) * p.part_pop_totale_dans_tranche_10, 2) as nb_deces_tous_cancers,
        round(coalesce(mt.deces_tous_cancers_femmes_10, 0.0) * p.part_pop_femmes_dans_tranche_10, 2) as nb_deces_tous_cancers_femmes,
        cast(coalesce(eff.nb_patients_actifs_sein, 0) as int64) as nb_patients_actifs_sein,
        cast(coalesce(eff.nb_patients_actifs_tous_cancers, 0) as int64) as nb_patients_actifs_tous_cancers,
        cast(coalesce(eff.nb_patients_actifs_tous_cancers_femmes, 0) as int64) as nb_patients_actifs_tous_cancers_femmes
    from pop_avec_parts p
    left join mortalite_sein_10 ms
      on p.annee = ms.annee
     and p.code_region = ms.code_region
     and p.code_tranche_10 = ms.code_tranche_10
    left join mortalite_tumeurs_10 mt
      on p.annee = mt.annee
     and p.code_region = mt.code_region
     and p.code_tranche_10 = mt.code_tranche_10
    left join effectifs_actifs_age eff
      on p.annee = eff.annee
     and p.code_region = eff.code_region
     and p.code_tranche_age_5 = eff.code_tranche_age_5

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, code_tranche_age_5
    )))) as id_comparatif_sein_onco,
    *
from joined
