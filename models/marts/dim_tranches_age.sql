with distinct_tranches as (

    select distinct
        trim(tranche_age_5) as code_tranche_age_5,
        cast(age_min as int64) as age_min,
        cast(age_max as int64) as age_max
    from {{ source('data_clean', 'pop_regions_age') }}
    where sexe = 'F'
      and age_min >= 25

),

enriched as (

    select
        to_hex(sha256(to_json_string(struct(
            code_tranche_age_5
        )))) as id_tranche_age,
        code_tranche_age_5,
        case
            when code_tranche_age_5 = '95+' then '95 ans et plus'
            else concat(code_tranche_age_5, ' ans')
        end as libelle_tranche_age_5,
        cast(dense_rank() over (order by age_min) as int64) as ordre_tranche_age,
        age_min,
        age_max,
        case
            when age_min between 25 and 34 then '25-34 ans'
            when age_min between 35 and 44 then '35-44 ans'
            when age_min between 45 and 54 then '45-54 ans'
            when age_min between 55 and 64 then '55-64 ans'
            when age_min between 65 and 74 then '65-74 ans'
            when age_min between 75 and 84 then '75-84 ans'
            when age_min between 85 and 94 then '85-94 ans'
            else '95 ans et plus'
        end as tranche_age_10,
        case
            when age_min < 50 then 'Moins de 50 ans (hors dépistage)'
            when age_min between 50 and 74 then '50-74 ans (cible dépistage)'
            else '75 ans et plus (post-dépistage)'
        end as groupe_depistage,
        case
            when age_min < 50 then 1
            when age_min between 50 and 74 then 2
            else 3
        end as ordre_groupe_depistage,
        age_min between 50 and 74 as est_cible_depistage
    from distinct_tranches

)

select *
from enriched
order by ordre_tranche_age
