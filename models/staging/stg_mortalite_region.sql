{{ config(materialized='view') }}

with source as (

    select * from {{ source('mortalite', 'mortalite_region') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        lpad(cast(code_region as string), 2, '0') as code_region,
        trim(region) as nom_region,
        trim(sexe) as sexe,
        trim(classe_age_3) as tranche_age,
        cast(effectif_deces as int64) as nb_deces,
        cast(taux_standardise_age_pour_100000 as float64) as taux_mortalite_std_age_pour_100000,
        trim(population_reference_standardisation) as population_reference_standardisation,
        case lower(trim(donnees_provisoires))
            when 'oui' then true
            when 'non' then false
            else null
        end as donnees_provisoires
    from source

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, sexe, tranche_age, population_reference_standardisation
    )))) as id_mortalite,
    *
from cleaned
