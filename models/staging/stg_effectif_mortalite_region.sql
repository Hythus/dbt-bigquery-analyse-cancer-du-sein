{{ config(materialized='view') }}

with source as (

    select * from {{ source('mortalite', 'effectif_mortalite_region') }}

),

cleaned as (

    select
        cast(annee_de_deces as int64) as annee_deces,
        lpad(trim(cast(region_de_domicile as string)), 2, '0') as code_region,
        case
            when trim(regdom_libelle) in ('Auvergne et Rhône-Alpes', 'Auvergne-Rhône-Alpes') then 'Auvergne-Rhône-Alpes'
            when trim(regdom_libelle) in ('Bourgogne et Franche-Comté', 'Bourgogne-Franche-Comté') then 'Bourgogne-Franche-Comté'
            when trim(regdom_libelle) in ('Nouvelle Aquitaine', 'Nouvelle-Aquitaine') then 'Nouvelle-Aquitaine'
            when trim(regdom_libelle) in ('Ile-de-France', 'Île-de-France') then 'Île-de-France'
            else trim(regdom_libelle)
        end as nom_region,
        trim(classe_d_age_de_10_ans) as tranche_age_10,
        trim(sexe) as sexe,
        trim(cause_initiale_de_deces) as cause_initiale_deces,
        trim(indicateur) as indicateur,
        cast(valeur as int64) as nb_deces

    from source
    qualify row_number() over (
        partition by annee_de_deces, region_de_domicile, classe_d_age_de_10_ans, sexe, cause_initiale_de_deces, indicateur
        order by valeur desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        annee_deces, code_region, tranche_age_10, sexe, cause_initiale_deces, indicateur
    )))) as id_effectif_mortalite,
    *
from cleaned

