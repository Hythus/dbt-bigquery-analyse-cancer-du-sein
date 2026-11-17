{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'effectifs_cancers_age_region') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        lpad(trim(cast(code_region as string)), 2, '0') as code_region,
        trim(top) as code_pathologie,
        coalesce(nullif(trim(patho_niv2), ''), 'Tous cancers') as localisation_cancer,
        case
            when trim(top) like '%_ACT' then 'Actif'
            when trim(top) like '%_SUR' then 'Sous surveillance'
            else 'Ensemble'
        end as statut_cancer,
        case
            when trim(cla_age_5) = '95et+' then '95+'
            else trim(cla_age_5)
        end as code_tranche_age_5,
        case
            when lower(trim(libelle_sexe)) = 'femmes' then 'Femmes'
            when lower(trim(libelle_sexe)) = 'hommes' then 'Hommes'
            else 'Tous sexes'
        end as sexe,
        cast(ntop as int64) as nb_patients,
        cast(npop as int64) as population_assuree,
        cast(prev as float64) as taux_prevalence_pct

    from source
    qualify row_number() over (
        partition by annee, code_region, trim(top), trim(cla_age_5), trim(sexe)
        order by ntop desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, code_pathologie, code_tranche_age_5, sexe
    )))) as id_effectif_cancer_age_region,
    *
from cleaned
