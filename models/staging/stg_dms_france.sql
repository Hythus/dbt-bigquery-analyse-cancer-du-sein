{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'dms_france') }}

),

cleaned as (

    select
        trim(territoire) as territoire,
        cast(annee as int64) as annee,
        trim(libelle_patho) as libelle_pathologie,
        trim(famille_tumeur) as famille_tumeur,
        cast(nb_sejours_24h_plus as int64) as nb_sejours_24h_plus,
        cast(dms_jours as float64) as duree_moyenne_sejour_jours

    from source
    qualify row_number() over (
        partition by trim(territoire), annee, trim(libelle_patho), trim(famille_tumeur)
        order by nb_sejours_24h_plus desc
    ) = 1

)

select * from cleaned

