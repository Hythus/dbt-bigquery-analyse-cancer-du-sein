{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'pop_regions_age') }}

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
        trim(sexe) as code_sexe,
        case trim(sexe)
            when 'F' then 'Femmes'
            when 'H' then 'Hommes'
            when 'E' then 'Ensemble'
            else trim(sexe)
        end as sexe,
        trim(age_libelle) as tranche_age,
        cast(age_min as int64) as age_min,
        cast(age_max as int64) as age_max,
        cast(population as int64) as population,
        coalesce(cast(resultats_precoces as boolean), false) as is_resultat_precoce

    from source
    qualify row_number() over (
        partition by annee, region_code, sexe, age_libelle
        order by population desc
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, code_sexe, tranche_age
    )))) as id_pop_region_age,
    *
from cleaned

