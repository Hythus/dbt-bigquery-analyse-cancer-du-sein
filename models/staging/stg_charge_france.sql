{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'charge_france') }}

),

cleaned as (

    select
        trim(territoire) as territoire,
        cast(annee as int64) as annee,
        trim(libelle_patho) as libelle_pathologie,
        trim(famille_tumeur) as famille_tumeur,
        cast(nb_sejours as int64) as nb_sejours_total,
        cast(nb_sejours_moins_24h as int64) as nb_sejours_moins_24h,
        cast(sej_moins_24h_programmes as int64) as nb_sejours_moins_24h_programmes,
        cast(sej_moins_24h_autres as int64) as nb_sejours_moins_24h_autres,
        cast(sej_1j as int64) as nb_sejours_1j,
        cast(sej_2j as int64) as nb_sejours_2j,
        cast(sej_3j as int64) as nb_sejours_3j,
        cast(sej_4j as int64) as nb_sejours_4j,
        cast(sej_5j as int64) as nb_sejours_5j,
        cast(sej_6j as int64) as nb_sejours_6j,
        cast(sej_7j as int64) as nb_sejours_7j,
        cast(sej_8j as int64) as nb_sejours_8j,
        cast(sej_9j as int64) as nb_sejours_9j,
        cast(sej_10_19j as int64) as nb_sejours_10_19j,
        cast(sej_20_29j as int64) as nb_sejours_20_29j,
        cast(sej_30j_plus as int64) as nb_sejours_30j_plus,
        cast(part_ambulatoire as float64) as part_ambulatoire,
        cast(nb_journees_estimees as float64) as nb_journees_estimees

    from source
    qualify row_number() over (
        partition by trim(territoire), annee, trim(libelle_patho), trim(famille_tumeur)
        order by nb_sejours desc
    ) = 1

)

select * from cleaned

