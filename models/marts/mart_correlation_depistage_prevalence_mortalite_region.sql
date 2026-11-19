{{ config(materialized='table') }}

with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

pop_cible as (

    select
        annee,
        code_region,
        cast(population_femmes_total as int64) as femmes_total,
        cast(population_femmes_50_74_ans as int64) as femmes_50_74
    from {{ ref('stg_pop_cible_regions') }}
    where annee between 2015 and 2024

),

depistage_region as (

    select
        e.annee,
        r.code_region,
        cast(e.nb_femmes_depistees as int64) as nb_femmes_depistees,
        round(e.taux_participation_std_pct, 2) as taux_participation_std_pct
    from {{ ref('stg_depistage_evolution_2005_2025') }} e
    inner join regions r
      on case
            when e.nom_zone_geographique = 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else e.nom_zone_geographique
         end = r.nom_region
    where e.type_zone_geographique = 'Région'
      and e.annee between 2015 and 2024

),

effectifs_sein_region as (

    select
        annee,
        code_region,
        cast(max(population_regionale) as int64) as population_assurees_ameli,
        cast(coalesce(max(case when code_pathologie = 'CAN_SEI_ACT' then nb_patients end), 0) as int64) as nb_patientes_actives_sein,
        cast(coalesce(max(case when code_pathologie = 'CAN_SEI_SUR' then nb_patients end), 0) as int64) as nb_patientes_surveillance_sein,
        cast(
            coalesce(max(case when code_pathologie = 'CAN_SEI_ACT' then nb_patients end), 0)
            + coalesce(max(case when code_pathologie = 'CAN_SEI_SUR' then nb_patients end), 0)
            as int64
        ) as nb_patientes_total_sein,
        round(coalesce(max(case when code_pathologie = 'CAN_SEI_ACT' then taux_prevalence_pct end), 0.0), 3) as prevalence_active_pct,
        round(coalesce(max(case when code_pathologie = 'CAN_SEI_SUR' then taux_prevalence_pct end), 0.0), 3) as prevalence_surveillance_pct,
        round(
            coalesce(max(case when code_pathologie = 'CAN_SEI_ACT' then taux_prevalence_pct end), 0.0)
            + coalesce(max(case when code_pathologie = 'CAN_SEI_SUR' then taux_prevalence_pct end), 0.0),
            3
        ) as prevalence_totale_pct
    from {{ ref('stg_effectifs_region') }}
    where code_pathologie in ('CAN_SEI_ACT', 'CAN_SEI_SUR')
      and annee between 2015 and 2024
    group by 1, 2

),

mortalite_sein_effectifs as (

    select
        annee_deces as annee,
        code_region,
        cast(sum(nb_deces) as int64) as nb_deces_sein_femmes
    from {{ ref('stg_effectif_mortalite_region') }}
    where cause_initiale_deces = '2.1.10 Tumeur maligne du sein'
      and sexe = 'Femmes'
      and annee_deces between 2015 and 2024
    group by 1, 2

),

mortalite_toutes_causes as (

    select
        annee_deces as annee,
        code_region,
        cast(sum(nb_deces) as int64) as nb_deces_toutes_causes_femmes
    from {{ ref('stg_effectif_mortalite_toutescauses_region') }}
    where cause_initiale_deces = 'Toutes causes'
      and sexe = 'Femmes'
      and annee_deces between 2015 and 2024
    group by 1, 2

),

mortalite_par_groupe_depistage as (

    select
        m.annee,
        m.code_region,
        round(sum(case when a.ordre_groupe_depistage = 1 then m.nb_deces_sein_femmes else 0 end), 2) as nb_deces_sein_moins_50_ans,
        round(sum(case when a.ordre_groupe_depistage = 2 then m.nb_deces_sein_femmes else 0 end), 2) as nb_deces_sein_50_74_ans,
        round(sum(case when a.ordre_groupe_depistage = 3 then m.nb_deces_sein_femmes else 0 end), 2) as nb_deces_sein_75_ans_plus
    from {{ ref('mart_correlation_age_region_sein') }} m
    inner join {{ ref('dim_tranches_age') }} a
      on m.code_tranche_age_5 = a.code_tranche_age_5
    group by 1, 2

),

mortalite_std as (

    select
        annee,
        code_region,
        taux_mortalite_std_tous_ages_100k as taux_mortalite_std_sein_pour_100k,
        taux_mortalite_std_50_74_100k as taux_mortalite_std_50_74_sein_pour_100k
    from {{ ref('mart_mortalite_std_distribution_region') }}
    where annee between 2015 and 2024

),

joined as (

    select
        pc.annee,
        pc.code_region,
        pc.femmes_total,
        pc.femmes_50_74,
        dep.nb_femmes_depistees,
        dep.taux_participation_std_pct,
        eff.population_assurees_ameli,
        eff.nb_patientes_actives_sein,
        eff.nb_patientes_surveillance_sein,
        eff.nb_patientes_total_sein,
        eff.prevalence_active_pct,
        eff.prevalence_surveillance_pct,
        eff.prevalence_totale_pct,
        ms.nb_deces_sein_femmes,
        mtc.nb_deces_toutes_causes_femmes,
        mgd.nb_deces_sein_moins_50_ans,
        mgd.nb_deces_sein_50_74_ans,
        mgd.nb_deces_sein_75_ans_plus,
        round(safe_divide(cast(ms.nb_deces_sein_femmes as float64) * 100000.0, cast(pc.femmes_total as float64)), 2) as taux_brut_mortalite_sein_pour_100k,
        mstd.taux_mortalite_std_sein_pour_100k,
        mstd.taux_mortalite_std_50_74_sein_pour_100k,
        round(safe_divide(cast(ms.nb_deces_sein_femmes as float64) * 100.0, cast(nullif(mtc.nb_deces_toutes_causes_femmes, 0) as float64)), 2) as part_deces_sein_dans_toutes_causes_pct,
        round(safe_divide(cast(ms.nb_deces_sein_femmes as float64) * 100.0, cast(nullif(eff.nb_patientes_actives_sein, 0) as float64)), 2) as ratio_deces_patientes_actives_pct
    from pop_cible pc
    inner join regions r
      on pc.code_region = r.code_region
    left join depistage_region dep
      on pc.annee = dep.annee
     and pc.code_region = dep.code_region
    left join effectifs_sein_region eff
      on pc.annee = eff.annee
     and pc.code_region = eff.code_region
    left join mortalite_sein_effectifs ms
      on pc.annee = ms.annee
     and pc.code_region = ms.code_region
    left join mortalite_toutes_causes mtc
      on pc.annee = mtc.annee
     and pc.code_region = mtc.code_region
    left join mortalite_par_groupe_depistage mgd
      on pc.annee = mgd.annee
     and pc.code_region = mgd.code_region
    left join mortalite_std mstd
      on pc.annee = mstd.annee
     and pc.code_region = mstd.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mart_correlation_region,
    *
from joined
