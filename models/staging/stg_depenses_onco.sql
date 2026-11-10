{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'depenses_onco') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        trim(localisation) as localisation_cancer,
        trim(statut) as statut_cancer,
        trim(dep_niv_1) as categorie_depense,
        trim(type_depense) as poste_depense,
        trim(secteur) as secteur_hospitalier,
        cast(montant as int64) as montant_depense_euros,
        cast(nb_patients_pathologie as int64) as nb_patients_pathologie,
        cast(n_recourant_au_poste as int64) as nb_patients_recourant_poste,
        cast(montant_moy as int64) as montant_moyen_par_patient_euros

    from source
    qualify row_number() over (
        partition by annee, trim(localisation), trim(statut), trim(dep_niv_1), trim(type_depense), trim(secteur)
        order by montant desc
    ) = 1

)

select * from cleaned

