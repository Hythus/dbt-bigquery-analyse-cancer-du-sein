{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'df_radiologie_final') }}

),

cleaned as (

    select
        lpad(trim(cast(Code_region as string)), 2, '0') as code_region,
        case
            when trim(Region) = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when trim(Region) = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when trim(Region) = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            else trim(Region)
        end as nom_region,
        lpad(trim(cast(code_departement as string)), 2, '0') as code_departement,
        trim(departement) as nom_departement,
        trim(nom_centre) as nom_centre_radiologie,
        trim(ville) as ville

    from source
    qualify row_number() over (
        partition by trim(nom_centre), trim(ville), trim(code_departement)
        order by trim(nom_centre)
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        nom_centre_radiologie, ville, code_departement
    )))) as id_centre_radiologie,
    *
from cleaned

