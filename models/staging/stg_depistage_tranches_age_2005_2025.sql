{{ config(materialized='view') }}

with source as (

    select * from {{ source('depistage', 'TAUX_PARTICIPATION_INSEE_BRUT_TRANCHES_AGE_2005_2025') }}

),

filtered as (

    select *
    from source
    where localisation is not null
      and trim(localisation) != ''
      and not regexp_contains(trim(localisation), r'^[0-9]\s')
      and lower(localisation) not like '%source%'
      and tranche_d_age is not null
      and trim(tranche_d_age) != ''
      and trim(tranche_d_age) != 'nan'

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

        trim(tranche_d_age) as tranche_age,

        {% for y1 in range(2005, 2025) %}
        {% set y2 = y1 + 1 %}
        cast(taux_de_participation_{{ y1 }}_{{ y2 }} as float64) as taux_participation_brut_pct_{{ y1 }}_{{ y2 }}{% if not loop.last %},{% endif %}
        {% endfor %}

    from filtered

),

unpivoted as (

    {% for y1 in range(2005, 2025) %}
    {% set y2 = y1 + 1 %}
    select
        nom_zone_geographique,
        type_zone_geographique,
        tranche_age,
        '{{ y1 }}-{{ y2 }}' as periode_biennale,
        {{ y2 }} as annee_fin_periode,
        taux_participation_brut_pct_{{ y1 }}_{{ y2 }} as taux_participation_brut_pct
    from normalized
    {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

cleaned as (

    select *
    from unpivoted
    qualify row_number() over (
        partition by nom_zone_geographique, type_zone_geographique, tranche_age, periode_biennale
        order by taux_participation_brut_pct desc nulls last
    ) = 1

)

select
    to_hex(sha256(to_json_string(struct(
        nom_zone_geographique, type_zone_geographique, tranche_age, periode_biennale
    )))) as id_depistage_tranche_age,
    *
from cleaned

