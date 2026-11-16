with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

pop_cible as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(femmes_total as int64) as femmes_total,
        cast(femmes_50_74 as int64) as femmes_50_74
    from {{ source('data_clean', 'pop_cible_regions') }}
    where annee between 2015 and 2022

),

depistage_unpivoted as (

    {% for yr in range(2015, 2023) %}
    select
        {{ yr }} as annee,
        case trim(localisation)
            when 'Ile-de-France' then 'Île-de-France'
            when 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else trim(localisation)
        end as nom_region,
        safe_cast(nombre_de_femmes_depistees_annee_{{ yr }} as int64) as nb_femmes_depistees,
        round(safe_cast(taux_de_participation_insee_standardise_annee_{{ yr }} as float64), 2) as taux_participation_std_pct
    from {{ source('data_clean', 'Participation_depistage_2005-2025') }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

depistage_region as (

    select
        d.annee,
        r.code_region,
        d.nb_femmes_depistees,
        d.taux_participation_std_pct
    from depistage_unpivoted d
    inner join regions r
      on d.nom_region = r.nom_region

),

effectifs_sein_region as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(max(population) as int64) as population_assurees_ameli,
        cast(max(case when top = 'CAN_SEI_ACT' then nb_patients end) as int64) as nb_patientes_actives_sein,
        cast(max(case when top = 'CAN_SEI_SUR' then nb_patients end) as int64) as nb_patientes_surveillance_sein,
        cast(sum(nb_patients) as int64) as nb_patientes_total_sein,
        round(max(case when top = 'CAN_SEI_ACT' then cast(prevalence_pct as float64) end), 3) as prevalence_active_pct,
        round(max(case when top = 'CAN_SEI_SUR' then cast(prevalence_pct as float64) end), 3) as prevalence_surveillance_pct,
        round(sum(cast(prevalence_pct as float64)), 3) as prevalence_totale_pct
    from {{ source('data_clean', 'effectifs_region') }}
    where top in ('CAN_SEI_ACT', 'CAN_SEI_SUR')
      and annee between 2015 and 2022
    group by 1, 2

),

mortalite_sein_effectifs as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(sum(deces) as int64) as nb_deces_sein_femmes
    from {{ source('data_clean', 'effectif_mortalite_sein_region') }}
    where sexe = 'Femmes'
      and annee between 2015 and 2022
    group by 1, 2

),

mortalite_toutes_causes as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(sum(deces) as int64) as nb_deces_toutes_causes_femmes
    from {{ source('data_clean', 'effectif_mortalite_region') }}
    where sexe = 'Femmes'
      and annee between 2015 and 2022
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
        round(safe_divide(cast(ms.nb_deces_sein_femmes as float64) * 100000.0, cast(pc.femmes_total as float64)), 2) as taux_brut_mortalite_sein_pour_100k
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

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mart_correlation_region,
    *
from joined
