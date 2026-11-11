{{ config(materialized='view') }}

with source as (

    select * from {{ source('depistage', 'France_Participation_AGE_2022_2023') }}

),

filtered as (

    select *
    from source
    where Localisation is not null
      and trim(Localisation) != ''
      and not regexp_contains(trim(Localisation), r'^[0-9]\s')
      and lower(Localisation) not like '%source%'

),

cleaned as (

    select
        case
            when trim(Localisation) = 'France entière' then 'National'
            when trim(Localisation) in (
                'Auvergne-Rhône-Alpes', 'Auvergne et Rhône-Alpes',
                'Bourgogne-Franche-Comté', 'Bourgogne et Franche-Comté',
                'Bretagne', 'Centre-Val de Loire', 'Centre-Val-de-Loire',
                'Corse', 'Grand Est', 'Hauts-de-France', 'Île-de-France', 'Ile-de-France',
                'Normandie', 'Nouvelle-Aquitaine', 'Nouvelle Aquitaine',
                'Occitanie', 'Pays de la Loire', "Provence-Alpes-Côte d'Azur", "Provence-Alpes-Côte d’Azur",
                'Guadeloupe', 'Martinique', 'Guyane', 'La Réunion', 'Mayotte'
            ) then 'Région'
            else 'Département'
        end as type_zone_geographique,

        case
            when trim(Localisation) in ('Auvergne et Rhône-Alpes', 'Auvergne-Rhône-Alpes') then 'Auvergne-Rhône-Alpes'
            when trim(Localisation) in ('Bourgogne et Franche-Comté', 'Bourgogne-Franche-Comté') then 'Bourgogne-Franche-Comté'
            when trim(Localisation) in ('Nouvelle Aquitaine', 'Nouvelle-Aquitaine') then 'Nouvelle-Aquitaine'
            when trim(Localisation) in ('Ile-de-France', 'Île-de-France') then 'Île-de-France'
            when trim(Localisation) like 'Provence-Alpes-Côte%' then "Provence-Alpes-Côte d'Azur"
            when trim(Localisation) in ('Centre-Val de Loire', 'Centre-Val-de-Loire') then 'Centre-Val-de-Loire'
            else trim(Localisation)
        end as nom_zone_geographique,

        cast(Population_cible_50_74 as int64) as population_cible_50_74_ans,
        cast(Femmes_depistees_50_74 as int64) as nb_femmes_depistees_50_74_ans,
        cast(Taux_participation_brut_50_74_pct as float64) as taux_participation_brut_pct_50_74_ans,
        cast(Taux_participation_standardise_50_74_pct as float64) as taux_participation_std_pct_50_74_ans,

        cast(Population_cible_50_54 as int64) as population_cible_50_54_ans,
        cast(Femmes_depistees_50_54 as int64) as nb_femmes_depistees_50_54_ans,
        cast(Taux_participation_brut_50_54_pct as float64) as taux_participation_brut_pct_50_54_ans,

        cast(Population_cible_55_59 as int64) as population_cible_55_59_ans,
        cast(Femmes_depistees_55_59 as int64) as nb_femmes_depistees_55_59_ans,
        cast(Taux_participation_brut_55_59_pct as float64) as taux_participation_brut_pct_55_59_ans,

        cast(Population_cible_60_64 as int64) as population_cible_60_64_ans,
        cast(Femmes_depistees_60_64 as int64) as nb_femmes_depistees_60_64_ans,
        cast(Taux_participation_brut_60_64_pct as float64) as taux_participation_brut_pct_60_64_ans,

        cast(Population_cible_65_69 as int64) as population_cible_65_69_ans,
        cast(Femmes_depistees_65_69 as int64) as nb_femmes_depistees_65_69_ans,
        cast(Taux_participation_brut_65_69_pct as float64) as taux_participation_brut_pct_65_69_ans,

        cast(Population_cible_70_74 as int64) as population_cible_70_74_ans,
        cast(Femmes_depistees_70_74 as int64) as nb_femmes_depistees_70_74_ans,
        cast(Taux_participation_brut_70_74_pct as float64) as taux_participation_brut_pct_70_74_ans

    from filtered
    qualify row_number() over (
        partition by trim(Localisation)
        order by Population_cible_50_74 desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        nom_zone_geographique, type_zone_geographique
    )))) as id_depistage_zone,
    *
from cleaned

