{{ config(materialized='view') }}

{% set standard_regions = [
    ('AuRA', '84', 'Auvergne-Rhône-Alpes'),
    ('BFC', '27', 'Bourgogne-Franche-Comté'),
    ('Bretagne', '53', 'Bretagne'),
    ('CVdL', '24', 'Centre-Val-de-Loire'),
    ('GE', '44', 'Grand Est'),
    ('Guadeloupe', '01', 'Guadeloupe'),
    ('HdF', '32', 'Hauts-de-France'),
    ('IdF', '11', 'Île-de-France'),
    ('Martinique', '02', 'Martinique'),
    ('Normandie', '28', 'Normandie'),
    ('Occitanie', '76', 'Occitanie'),
    ('PACA', '93', "Provence-Alpes-Côte d'Azur"),
    ('PdL', '52', 'Pays de la Loire'),
    ('Reunion', '04', 'La Réunion')
] %}

{% set years = range(2008, 2021) %}

with unioned as (

{% for tag, code, nom in standard_regions %}
    {% set col_ind = '`Nombre de cancers`' if tag == 'Reunion' else '`Nombre cancers`' %}
    {% for y in years %}
    select
        '{{ code }}' as code_region,
        '{{ nom | replace("'", "\\'") }}' as nom_region,
        trim(split(cast({{ col_ind }} as string), ' - ')[safe_offset(0)]) as code_indicateur,
        trim(split(cast({{ col_ind }} as string), ' - ')[safe_offset(1)]) as libelle_indicateur,
        trim(`Tranches d'âge`) as tranche_age,
        {{ y }} as annee,
        safe_cast(`Dépistage initial sans antécédent de mammographie {{ y }}` as float64) as taux_ou_valeur_initial_sans_ant_mammo,
        safe_cast(`Dépistage initial avec antécédent de mammographie {{ y }}` as float64) as taux_ou_valeur_initial_avec_ant_mammo,
        safe_cast(`Dépistages subséquents {{ y }}` as float64) as taux_ou_valeur_subsequents,
        safe_cast(`Tous rangs {{ y }}` as float64) as taux_ou_valeur_tous_rangs
    from {{ source('depistage', 'indicateurs_evolution_' ~ tag ~ '_2008-2020_Cancers') }}
    where {{ col_ind }} is not null
      and trim({{ col_ind }}) not in ('Nombre cancers', 'Nombre de cancers', '')
      and `Tranches d'âge` is not null
      and trim(`Tranches d'âge`) not in ("Tranches d'âge", '')

    union all
    {% endfor %}
{% endfor %}

{# Guyane headers special mapping #}
{% for y in years %}
    {% set i = y - 2008 %}
    select
        '03' as code_region,
        'Guyane' as nom_region,
        trim(split(string_field_0, ' - ')[safe_offset(0)]) as code_indicateur,
        trim(split(string_field_0, ' - ')[safe_offset(1)]) as libelle_indicateur,
        trim(string_field_1) as tranche_age,
        {{ y }} as annee,
        safe_cast(string_field_{{ 2 + 4 * i }} as float64) as taux_ou_valeur_initial_sans_ant_mammo,
        safe_cast(string_field_{{ 3 + 4 * i }} as float64) as taux_ou_valeur_initial_avec_ant_mammo,
        safe_cast(string_field_{{ 4 + 4 * i }} as float64) as taux_ou_valeur_subsequents,
        safe_cast(string_field_{{ 5 + 4 * i }} as float64) as taux_ou_valeur_tous_rangs
    from {{ source('depistage', 'indicateurs_evolution_Guyane_2008-2020_Cancers') }}
    where string_field_0 is not null
      and trim(string_field_0) not in ('Nombre cancers', 'Nombre de cancers', '')
      and string_field_1 is not null
      and trim(string_field_1) not in ("Tranches d'âge", '')
    {% if not loop.last %}
    union all
    {% endif %}
{% endfor %}

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, code_indicateur, tranche_age
    )))) as id_indicateur_depistage,
    *
from unioned
