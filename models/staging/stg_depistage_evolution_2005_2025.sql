{{ config(materialized='view') }}

with source as (

    select * from {{ source('depistage', 'France_Participation_Evolution_2005_2025') }}

),

filtered as (

    select *
    from source
    where localisation is not null
      and trim(localisation) != ''
      and not regexp_contains(trim(localisation), r'^[0-9]\s')
      and lower(localisation) not like '%source%'

),

normalized as (

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

        {% for yr in range(2005, 2026) %}
        {% if yr == 2007 %}
        cast(nullif(trim(cast(population_insee_cible_annee_2007 as string)), 'ND') as float64) as population_cible_{{ yr }},
        cast(nullif(trim(cast(nombre_de_femmes_depistees_annee_2007 as string)), 'ND') as float64) as nb_femmes_depistees_{{ yr }},
        cast(nullif(trim(cast(taux_de_participation_insee_standardise_annee_2007 as string)), 'ND') as float64) as taux_participation_std_pct_{{ yr }}{% if not loop.last %},{% endif %}
        {% else %}
        cast(population_insee_cible_annee_{{ yr }} as int64) as population_cible_{{ yr }},
        cast(nombre_de_femmes_depistees_annee_{{ yr }} as int64) as nb_femmes_depistees_{{ yr }},
        cast(taux_de_participation_insee_standardise_annee_{{ yr }} as float64) as taux_participation_std_pct_{{ yr }}{% if not loop.last %},{% endif %}
        {% endif %}
        {% endfor %}

    from filtered

),

unpivoted as (

    {% for yr in range(2005, 2026) %}
    select
        nom_zone_geographique,
        type_zone_geographique,
        {{ yr }} as annee,
        cast(population_cible_{{ yr }} as int64) as population_cible,
        cast(nb_femmes_depistees_{{ yr }} as int64) as nb_femmes_depistees,
        cast(taux_participation_std_pct_{{ yr }} as float64) as taux_participation_std_pct
    from normalized
    {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

cleaned as (

    select *
    from unpivoted
    qualify row_number() over (
        partition by nom_zone_geographique, type_zone_geographique, annee
        order by population_cible desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        nom_zone_geographique, type_zone_geographique, annee
    )))) as id_depistage_evolution,
    *
from cleaned

