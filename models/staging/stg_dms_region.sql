{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'dms_region') }}

),

cleaned as (

    select
        case
            when trim(nom_region) = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when trim(nom_region) = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when trim(nom_region) = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            else trim(nom_region)
        end as nom_region,
        cast(annee as int64) as annee,
        trim(libelle_patho) as libelle_pathologie,
        trim(famille_tumeur) as famille_tumeur,
        cast(nb_sejours_24h_plus as int64) as nb_sejours_24h_plus,
        cast(dms_jours as float64) as duree_moyenne_sejour_jours

    from source
    qualify row_number() over (
        partition by trim(nom_region), annee, trim(libelle_patho), trim(famille_tumeur)
        order by nb_sejours_24h_plus desc nulls last
    ) = 1

)

select * from cleaned

