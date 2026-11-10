{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'incidence_region') }}

),

cleaned as (

    select
        lpad(cast(region_code as string), 2, '0') as code_region,
        case
            when trim(region) = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when trim(region) = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when trim(region) = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            else trim(region)
        end as nom_region,
        trim(zone) as zone_geographique,
        case
            when sexe is false then 'Femmes'
            when sexe is true then 'Hommes'
            else null
        end as sexe,
        cast(annee_debut_incidence as int64) as annee_debut_incidence,
        cast(annee_fin_incidence as int64) as annee_fin_incidence,
        cast(annee_debut_mortalite as int64) as annee_debut_mortalite,
        cast(annee_fin_mortalite as int64) as annee_fin_mortalite,
        cast(taux_incidence as float64) as taux_incidence,
        cast(taux_incidence_ic_inf as float64) as taux_incidence_ic_inf,
        cast(taux_incidence_ic_sup as float64) as taux_incidence_ic_sup,
        cast(taux_mortalite as float64) as taux_mortalite,
        cast(taux_mortalite_ic_inf as float64) as taux_mortalite_ic_inf,
        cast(taux_mortalite_ic_sup as float64) as taux_mortalite_ic_sup

    from source
    qualify row_number() over (
        partition by region_code, sexe
        order by taux_incidence desc
    ) = 1

)

select * from cleaned

