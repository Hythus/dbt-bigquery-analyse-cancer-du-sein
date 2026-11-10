{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'depenses_patho') }}

),

cleaned as (

    select
        trim(id_depense) as id_depense,
        trim(cle_annee_top) as cle_annee_pathologie,
        cast(annee as int64) as annee,
        trim(top) as code_pathologie,
        trim(pathologie) as libelle_pathologie,
        trim(poste_niveau_1) as categorie_depense,
        trim(poste) as poste_depense,
        cast(montant as int64) as montant_depense_euros,
        cast(nb_patients_france as int64) as nb_patients_pathologie,
        cast(n_recourant_au_poste as int64) as nb_patients_recourant_poste

    from source
    qualify row_number() over (
        partition by trim(id_depense)
        order by montant desc
    ) = 1

)

select * from cleaned

