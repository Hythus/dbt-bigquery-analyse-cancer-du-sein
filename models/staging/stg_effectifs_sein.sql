{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'effectifs_sein') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        case
            when trim(type_cancer_sein) is not null then trim(type_cancer_sein)
            when trim(cle) = 'CAN_SEI_CAT' then 'Cancer du sein de la femme (tous statuts)'
            when trim(cle) = 'CAN_SEI_ACT' then 'Cancer du sein de la femme actif'
            when trim(cle) = 'CAN_SEI_SUR' then 'Cancer du sein de la femme sous surveillance'
            else trim(cle)
        end as libelle_type_cancer,
        trim(cle) as code_type_cancer,
        trim(cla_age_5) as tranche_age,
        lpad(trim(cast(region_code as string)), 2, '0') as code_region,
        lpad(trim(dept), 2, '0') as code_departement,
        trim(sexe) as sexe,
        cast(`Niveau prioritaire` as int64) as niveau_prioritaire,
        cast(Ntop as float64) as nb_cas_pris_en_charge,
        cast(Npop as int64) as population_reference,
        cast(prev as float64) as taux_prevalence,
        cast(tri as float64) as ordre_tri

    from source
    qualify row_number() over (
        partition by annee, cle, cla_age_5, region_code, dept, sexe, `Niveau prioritaire`
        order by Ntop desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_type_cancer, tranche_age, code_region, code_departement, sexe, niveau_prioritaire
    )))) as id_effectif_sein,
    *
from cleaned
