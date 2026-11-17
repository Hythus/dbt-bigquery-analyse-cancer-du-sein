{{ config(materialized='table') }}

with base as (

    select
        annee,
        code_region,
        code_tranche_age_5 as tranche_age,
        population_femmes,
        population_totale,
        nb_deces_sein,
        nb_deces_tous_cancers,
        nb_deces_tous_cancers_femmes,
        round(safe_divide(nb_deces_sein * 100000.0, cast(population_femmes as float64)), 2) as taux_mortalite_sein_100k,
        round(safe_divide(nb_deces_tous_cancers * 100000.0, cast(population_totale as float64)), 2) as taux_mortalite_tous_cancers_100k,
        round(safe_divide(nb_deces_tous_cancers_femmes * 100000.0, cast(population_femmes as float64)), 2) as taux_mortalite_tous_cancers_femmes_100k,
        nb_patients_actifs_sein,
        nb_patients_actifs_tous_cancers,
        nb_patients_actifs_tous_cancers_femmes,
        round(safe_divide(nb_deces_sein * 100.0, nullif(cast(nb_patients_actifs_sein as float64), 0.0)), 2) as ratio_deces_actifs_sein_pct,
        round(safe_divide(nb_deces_tous_cancers * 100.0, nullif(cast(nb_patients_actifs_tous_cancers as float64), 0.0)), 2) as ratio_deces_actifs_tous_cancers_pct,
        round(safe_divide(nb_deces_tous_cancers_femmes * 100.0, nullif(cast(nb_patients_actifs_tous_cancers_femmes as float64), 0.0)), 2) as ratio_deces_actifs_tous_cancers_femmes_pct
    from {{ ref('int_comparatif_sein_vs_tous_cancers') }}

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, tranche_age
    )))) as id_mart_comparatif_sein_onco,
    *
from base
