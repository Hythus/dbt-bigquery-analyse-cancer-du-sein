{{ config(materialized='view') }}

with source as (

    select * from {{ source('depistage', 'Taux_Standadise_Depistage_Dep_Region_2016_2025') }}

),

cleaned as (

    select
        trim(Annee) as periode_biennale,
        cast(split(trim(Annee), '-')[safe_offset(1)] as int64) as annee_fin_periode,
        lpad(trim(code_dep), 2, '0') as code_departement,
        trim(Departement) as nom_departement,
        lpad(trim(cast(code_reg as string)), 2, '0') as code_region,
        case
            when trim(libelle_region) in ('Auvergne et Rhône-Alpes', 'Auvergne-Rhône-Alpes') then 'Auvergne-Rhône-Alpes'
            when trim(libelle_region) in ('Bourgogne et Franche-Comté', 'Bourgogne-Franche-Comté') then 'Bourgogne-Franche-Comté'
            when trim(libelle_region) in ('Nouvelle Aquitaine', 'Nouvelle-Aquitaine') then 'Nouvelle-Aquitaine'
            when trim(libelle_region) in ('Ile-de-France', 'Île-de-France') then 'Île-de-France'
            else trim(libelle_region)
        end as nom_region,
        cast(tx_part_insee_std as float64) as taux_participation_std_pct

    from source
    qualify row_number() over (
        partition by trim(Annee), lpad(trim(code_dep), 2, '0')
        order by tx_part_insee_std desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        periode_biennale, code_departement
    )))) as id_depistage_taux_std,
    *
from cleaned

