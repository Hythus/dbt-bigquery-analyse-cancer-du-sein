-- Le staging doit conserver toutes les lignes et des mesures non négatives.
with counts as (
    select
        (select count(*) from {{ source('mortalite', 'mortalite_region') }}) as source_count,
        (select count(*) from {{ ref('stg_mortalite_region') }}) as staging_count
)

select 'nombre_lignes' as anomalie
from counts
where source_count != staging_count

union all

select 'mesure_negative_ou_code_region_invalide' as anomalie
from {{ ref('stg_mortalite_region') }}
where nb_deces < 0
    or taux_mortalite_std_age_pour_100000 < 0
    or not regexp_contains(code_region, r'^\d{2}$')
