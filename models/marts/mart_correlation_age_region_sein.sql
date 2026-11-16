with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

pop_age as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        trim(tranche_age_5) as code_tranche_age_5,
        cast(population as int64) as population_femmes,
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
    from {{ source('data_clean', 'pop_regions_age') }}
    where sexe = 'F'
      and age_min >= 25
      and annee between 2015 and 2022

),

pop_age_avec_part as (

    select
        *,
        coalesce(
            safe_divide(
                cast(population_femmes as float64),
                cast(sum(population_femmes) over (partition by annee, code_region, code_tranche_10) as float64)
            ),
            case when code_tranche_10 = '95p' then 1.0 else 0.5 end
        ) as part_pop_dans_tranche_10
    from pop_age

),

taux_brut_depistage_unpivoted as (

    {% for yr in range(2015, 2023) %}
    {% set prev_yr = yr - 1 %}
    select
        {{ yr }} as annee,
        case trim(localisation)
            when 'Ile-de-France' then 'Île-de-France'
            when 'Centre-Val de Loire' then 'Centre-Val-de-Loire'
            else trim(localisation)
        end as nom_region,
        trim(replace(tranche_d_age, ' ans', '')) as code_tranche_age_5,
        round(safe_cast(taux_de_participation_{{ prev_yr }}_{{ yr }} as float64), 2) as taux_participation_brut_tranche_pct
    from {{ source('data_clean', 'Taux_brut_participation_2005-2025') }}
    where trim(tranche_d_age) in ('50-54 ans', '55-59 ans', '60-64 ans', '65-69 ans', '70-74 ans')
    {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

taux_brut_depistage as (

    select
        t.annee,
        r.code_region,
        t.code_tranche_age_5,
        t.taux_participation_brut_tranche_pct
    from taux_brut_depistage_unpivoted t
    inner join regions r
      on t.nom_region = r.nom_region

),

effectifs_sein_age as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        trim(tranche_age_5) as code_tranche_age_5,
        cast(max(population) as int64) as population_assurees_ameli,
        cast(max(case when type_cancer_sein = 'Cancer du sein de la femme actif' then nb_patients end) as int64) as nb_patientes_actives_sein,
        cast(max(case when type_cancer_sein = 'Cancer du sein de la femme sous surveillance' then nb_patients end) as int64) as nb_patientes_surveillance_sein,
        cast(max(case when type_cancer_sein is null then nb_patients end) as int64) as nb_patientes_total_sein,
        round(max(case when type_cancer_sein = 'Cancer du sein de la femme actif' then cast(prevalence_pct as float64) end), 3) as prevalence_active_pct,
        round(max(case when type_cancer_sein = 'Cancer du sein de la femme sous surveillance' then cast(prevalence_pct as float64) end), 3) as prevalence_surveillance_pct,
        round(max(case when type_cancer_sein is null then cast(prevalence_pct as float64) end), 3) as prevalence_totale_pct
    from {{ source('data_clean', 'effectifs_sein') }}
    where sexe = 'FEMMES'
      and annee between 2015 and 2022
    group by 1, 2, 3

),

mortalite_sein_10 as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        trim(classe_age) as code_tranche_10,
        cast(deces as float64) as deces_sein_10
    from {{ source('data_clean', 'effectif_mortalite_sein_region') }}
    where sexe = 'Femmes'
      and annee between 2015 and 2022

),

mortalite_tc_10 as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        trim(classe_age) as code_tranche_10,
        cast(deces as float64) as deces_tc_10
    from {{ source('data_clean', 'effectif_mortalite_region') }}
    where sexe = 'Femmes'
      and annee between 2015 and 2022

),

joined as (

    select
        p.annee,
        p.code_region,
        p.code_tranche_age_5,
        p.population_femmes,
        tb.taux_participation_brut_tranche_pct,
        eff.population_assurees_ameli,
        eff.nb_patientes_actives_sein,
        eff.nb_patientes_surveillance_sein,
        eff.nb_patientes_total_sein,
        eff.prevalence_active_pct,
        eff.prevalence_surveillance_pct,
        eff.prevalence_totale_pct,
        round(ms.deces_sein_10 * p.part_pop_dans_tranche_10, 2) as nb_deces_sein_femmes,
        round(mtc.deces_tc_10 * p.part_pop_dans_tranche_10, 2) as nb_deces_toutes_causes_femmes
    from pop_age_avec_part p
    inner join regions r
      on p.code_region = r.code_region
    left join taux_brut_depistage tb
      on p.annee = tb.annee
     and p.code_region = tb.code_region
     and p.code_tranche_age_5 = tb.code_tranche_age_5
    left join effectifs_sein_age eff
      on p.annee = eff.annee
     and p.code_region = eff.code_region
     and p.code_tranche_age_5 = eff.code_tranche_age_5
    left join mortalite_sein_10 ms
      on p.annee = ms.annee
     and p.code_region = ms.code_region
     and p.code_tranche_10 = ms.code_tranche_10
    left join mortalite_tc_10 mtc
      on p.annee = mtc.annee
     and p.code_region = mtc.code_region
     and p.code_tranche_10 = mtc.code_tranche_10

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, code_tranche_age_5
    )))) as id_mart_correlation_age_region,
    *
from joined
