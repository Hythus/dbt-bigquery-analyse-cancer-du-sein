{{ config(materialized='view') }}

with source as (

    select * from {{ source('depistage', 'France_Participation_AGE_2024_2025') }}

),

filtered as (

    select *
    from source
    where localisation is not null
      and trim(localisation) != ''
      and not regexp_contains(trim(localisation), r'^[0-9]\s')
      and lower(localisation) not like '%source%'

),

cleaned as (

    select
        case
            when trim(localisation) = 'France entière' then 'National'
            when starts_with(trim(localisation), '.') then 'Département'
            else 'Région'
        end as type_zone_geographique,

        case
            when regexp_replace(trim(localisation), r'^[.\s]+', '') = 'Auvergne et Rhône-Alpes' then 'Auvergne-Rhône-Alpes'
            when regexp_replace(trim(localisation), r'^[.\s]+', '') = 'Bourgogne et Franche-Comté' then 'Bourgogne-Franche-Comté'
            when regexp_replace(trim(localisation), r'^[.\s]+', '') = 'Nouvelle Aquitaine' then 'Nouvelle-Aquitaine'
            when regexp_replace(trim(localisation), r'^[.\s]+', '') = 'Ile-de-France' then 'Île-de-France'
            else regexp_replace(trim(localisation), r'^[.\s]+', '')
        end as nom_zone_geographique,

        cast(population_insee_cible_50_74_ans as int64) as population_cible_50_74_ans,
        cast(nombre_de_femmes_depistees_50_74_ans as int64) as nb_femmes_depistees_50_74_ans,
        cast(taux_de_participation_insee_brut_pct_50_74_ans as float64) as taux_participation_brut_pct_50_74_ans,
        cast(taux_de_participation_insee_standardise_pct_50_74_ans as float64) as taux_participation_std_pct_50_74_ans,

        cast(population_insee_cible_50_54_ans as int64) as population_cible_50_54_ans,
        cast(nombre_de_femmes_depistees_50_54_ans as int64) as nb_femmes_depistees_50_54_ans,
        cast(taux_de_participation_insee_brut_pct_50_54_ans as float64) as taux_participation_brut_pct_50_54_ans,

        cast(population_insee_cible_55_59_ans as int64) as population_cible_55_59_ans,
        cast(nombre_de_femmes_depistees_55_59_ans as int64) as nb_femmes_depistees_55_59_ans,
        cast(taux_de_participation_insee_brut_pct_55_59_ans as float64) as taux_participation_brut_pct_55_59_ans,

        cast(population_insee_cible_60_64_ans as int64) as population_cible_60_64_ans,
        cast(nombre_de_femmes_depistees_60_64_ans as int64) as nb_femmes_depistees_60_64_ans,
        cast(taux_de_participation_insee_brut_pct_60_64_ans as float64) as taux_participation_brut_pct_60_64_ans,

        cast(population_insee_cible_65_69_ans as int64) as population_cible_65_69_ans,
        cast(nombre_de_femmes_depistees_65_69_ans as int64) as nb_femmes_depistees_65_69_ans,
        cast(taux_de_participation_insee_brut_pct_65_69_ans as float64) as taux_participation_brut_pct_65_69_ans,

        cast(population_insee_cible_70_74_ans as int64) as population_cible_70_74_ans,
        cast(nombre_de_femmes_depistees_70_74_ans as int64) as nb_femmes_depistees_70_74_ans,
        cast(taux_de_participation_insee_brut_pct_70_74_ans as float64) as taux_participation_brut_pct_70_74_ans

    from filtered
    qualify row_number() over (
        partition by regexp_replace(trim(localisation), r'^[.\s]+', '')
        order by population_insee_cible_50_74_ans desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        nom_zone_geographique, type_zone_geographique
    )))) as id_depistage_zone,
    *
from cleaned

