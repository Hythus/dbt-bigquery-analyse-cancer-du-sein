{{ config(materialized='view') }}

with source as (

    select * from {{ source('data_brute', 'incidence_france') }}

),

cleaned as (

    select
        cast(annee as int64) as annee,
        case
            when sexe is false then 'Femmes'
            when sexe is true then 'Hommes'
            else null
        end as sexe,
        cast(personnes_annees as float64) as nb_personnes_annees,
        cast(cas as int64) as nb_nouveaux_cas,
        cast(cas_ic_inf as int64) as nb_nouveaux_cas_ic_inf,
        cast(cas_ic_sup as int64) as nb_nouveaux_cas_ic_sup,
        cast(taux_brut as float64) as taux_incidence_brut,
        cast(taux_brut_ic_inf as float64) as taux_incidence_brut_ic_inf,
        cast(taux_brut_ic_sup as float64) as taux_incidence_brut_ic_sup,
        cast(taux_std_europe as float64) as taux_incidence_std_europe,
        cast(taux_std_europe_ic_inf as float64) as taux_incidence_std_europe_ic_inf,
        cast(taux_std_europe_ic_sup as float64) as taux_incidence_std_europe_ic_sup,
        cast(taux_std_monde as float64) as taux_incidence_std_monde,
        cast(taux_std_monde_ic_inf as float64) as taux_incidence_std_monde_ic_inf,
        cast(taux_std_monde_ic_sup as float64) as taux_incidence_std_monde_ic_sup,
        cast(premiere_annee_estimation as int64) as premiere_annee_estimation

    from source
    qualify row_number() over (
        partition by annee, sexe
        order by cas desc
    ) = 1

)

select * from cleaned

