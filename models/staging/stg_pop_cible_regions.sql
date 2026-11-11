{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'pop_cible_regions') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(region_code as string)), 2, '0') as code_region,
        case
            when trim(region) = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when trim(region) = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when trim(region) = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            when trim(region) = 'Ile-de-France' then 'Île-de-France'
            else trim(region)
        end as nom_region,
        trim(zone) as zone_geographique,
        cast(femmes_50_74 as int64) as population_femmes_50_74_ans,
        cast(femmes_total as int64) as population_femmes_total,
        cast(part_cible_pct as float64) as part_cible_pct

    from source
    qualify row_number() over (
        partition by annee, region_code
        order by femmes_total desc
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_pop_cible_region,
    *
from cleaned

