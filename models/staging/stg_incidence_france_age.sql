{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'incidence_france_age') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        case
            when sexe is false then 'Femmes'
            when sexe is true then 'Hommes'
            else null
        end as sexe,
        trim(age_libelle) as tranche_age,
        cast(age_min as int64) as age_min,
        cast(age_max as int64) as age_max,
        cast(poids_europe as float64) as poids_standardisation_europe,
        cast(poids_monde as float64) as poids_standardisation_monde,
        cast(personnes_annees as float64) as nb_personnes_annees,
        cast(cas as int64) as nb_nouveaux_cas,
        cast(cas_ic_inf as int64) as nb_nouveaux_cas_ic_inf,
        cast(cas_ic_sup as int64) as nb_nouveaux_cas_ic_sup,
        cast(taux_brut as float64) as taux_incidence_brut,
        cast(taux_brut_ic_inf as float64) as taux_incidence_brut_ic_inf,
        cast(taux_brut_ic_sup as float64) as taux_incidence_brut_ic_sup

    from source
    qualify row_number() over (
        partition by annee, sexe, trim(age_libelle)
        order by cas desc
    ) = 1

)

select * from cleaned

