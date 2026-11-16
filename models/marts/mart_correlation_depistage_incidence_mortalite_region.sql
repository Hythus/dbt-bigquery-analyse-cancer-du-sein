with regions as (

    select
        code_region,
        libelle_region as nom_region,
        zone_geographique
    from {{ ref('dim_regions') }}

),

pop_cible as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(femmes_total as int64) as femmes_total,
        cast(femmes_50_74 as int64) as femmes_50_74
    from {{ source('data_clean', 'pop_cible_regions') }}
    where annee between 2014 and 2022

),

depistage_unpivoted as (

    {% for yr in range(2014, 2023) %}
    select
        {{ yr }} as annee,
        case trim(localisation)
            when 'Ile-de-France' then 'Île-de-France'
            when 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else trim(localisation)
        end as nom_region,
        safe_cast(population_insee_cible_annee_{{ yr }} as int64) as population_cible_depistage,
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
        d.population_cible_depistage,
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
        cast(sum(case when top = 'CAN_SEI_ACT' then nb_patients else 0 end) as int64) as nb_patientes_actives_sein,
        cast(sum(case when top = 'CAN_SEI_SUR' then nb_patients else 0 end) as int64) as nb_patientes_surveillance_sein,
        cast(sum(nb_patients) as int64) as nb_patientes_total_sein
    from {{ source('data_clean', 'effectifs_region') }}
    where top in ('CAN_SEI_ACT', 'CAN_SEI_SUR')
      and annee between 2014 and 2022
    group by 1, 2

),

inc_region as (

    select
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        round(cast(taux_incidence as float64), 2) as taux_incidence_ref_region_2007_2016
    from {{ source('data_clean', 'incidence_region') }}

),

inc_france as (

    select
        cast(annee as int64) as annee,
        cast(cas as int64) as nb_nouveaux_cas_france,
        round(cast(taux_std_monde as float64), 2) as taux_incidence_std_monde_france
    from {{ source('data_clean', 'incidence_france') }}
    where annee between 2014 and 2022

),

mortalite_sein_effectifs as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(sum(deces) as int64) as nb_deces_sein_femmes,
        cast(sum(case when classe_age in ('25-34', '35-44', '45-54', '55-64') then deces else 0 end) as int64) as nb_deces_sein_moins_65_ans
    from {{ source('data_clean', 'effectif_mortalite_sein_region') }}
    where sexe = 'Femmes'
      and annee between 2014 and 2022
    group by 1, 2

),

mortalite_toutes_causes as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        cast(sum(deces) as int64) as nb_deces_toutes_causes_femmes
    from {{ source('data_clean', 'effectif_mortalite_region') }}
    where sexe = 'Femmes'
      and annee between 2014 and 2022
    group by 1, 2

),

mortalite_taux_std as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        max(case when classe_age = 'Moins de 65 ans' then cast(taux_standardise_age_pour_100000 as float64) end) as taux_mortalite_std_moins_65_ans,
        max(case when classe_age = 'Entre 65 et 84 ans' then cast(taux_standardise_age_pour_100000 as float64) end) as taux_mortalite_std_65_84_ans,
        max(case when classe_age = '85 ans et plus' then cast(taux_standardise_age_pour_100000 as float64) end) as taux_mortalite_std_85_ans_plus
    from {{ source('data_clean', 'taux_mortalite_sein_region') }}
    where sexe = 'Femmes'
      and annee between 2014 and 2022
    group by 1, 2

),

joined as (

    select
        pc.annee,
        pc.code_region,
        r.nom_region,
        r.zone_geographique,
        pc.femmes_total,
        pc.femmes_50_74,
        dep.population_cible_depistage,
        dep.nb_femmes_depistees,
        dep.taux_participation_std_pct,
        eff.nb_patientes_actives_sein,
        eff.nb_patientes_surveillance_sein,
        eff.nb_patientes_total_sein,
        ir.taux_incidence_ref_region_2007_2016,
        infr.taux_incidence_std_monde_france,
        infr.nb_nouveaux_cas_france,
        ms.nb_deces_sein_femmes,
        ms.nb_deces_sein_moins_65_ans,
        mtc.nb_deces_toutes_causes_femmes,
        mts.taux_mortalite_std_moins_65_ans,
        mts.taux_mortalite_std_65_84_ans,
        mts.taux_mortalite_std_85_ans_plus
    from pop_cible pc
    inner join regions r
      on pc.code_region = r.code_region
    left join depistage_region dep
      on pc.annee = dep.annee
     and pc.code_region = dep.code_region
    left join effectifs_sein_region eff
      on pc.annee = eff.annee
     and pc.code_region = eff.code_region
    left join inc_region ir
      on pc.code_region = ir.code_region
    left join inc_france infr
      on pc.annee = infr.annee
    left join mortalite_sein_effectifs ms
      on pc.annee = ms.annee
     and pc.code_region = ms.code_region
    left join mortalite_toutes_causes mtc
      on pc.annee = mtc.annee
     and pc.code_region = mtc.code_region
    left join mortalite_taux_std mts
      on pc.annee = mts.annee
     and pc.code_region = mts.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mart_correlation_region,
    *
from joined
