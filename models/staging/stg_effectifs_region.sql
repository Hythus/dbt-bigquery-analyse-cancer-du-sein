{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'effectifs_region') }}

),

cleaned as (

    select
        trim(id_effectif) as id_effectif,
        trim(cle_annee_top) as cle_annee_pathologie,
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        case
            when trim(nom_region) = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when trim(nom_region) = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when trim(nom_region) = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            else trim(nom_region)
        end as nom_region,
        trim(top) as code_pathologie,
        trim(pathologie) as libelle_pathologie,
        cast(nb_patients as int64) as nb_patients,
        cast(population as int64) as population_regionale,
        cast(prevalence_pct as float64) as taux_prevalence_pct

    from source
    qualify row_number() over (
        partition by trim(id_effectif)
        order by nb_patients desc nulls last
    ) = 1

)

select * from cleaned

