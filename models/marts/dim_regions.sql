with raw_regions as (

    select distinct
        code_region,
        nom_region as libelle_region,
        zone_geographique
    from {{ ref('stg_pop_cible_regions') }}

),

final as (

    select
        code_region,
        libelle_region,
        zone_geographique,
        case when zone_geographique = 'Hexagone' then true else false end as est_metropole,
        case code_region
            when '01' then 'FR-GP'
            when '02' then 'FR-MQ'
            when '03' then 'FR-GF'
            when '04' then 'FR-RE'
            when '06' then 'FR-YT'
            when '11' then 'FR-IDF'
            when '24' then 'FR-CVL'
            when '27' then 'FR-BFC'
            when '28' then 'FR-NOR'
            when '32' then 'FR-HDF'
            when '44' then 'FR-GES'
            when '52' then 'FR-PDL'
            when '53' then 'FR-BRE'
            when '75' then 'FR-NAQ'
            when '76' then 'FR-OCC'
            when '84' then 'FR-ARA'
            when '93' then 'FR-PAC'
            when '94' then 'FR-COR'
        end as code_iso_region,
        case code_region
            when '01' then 'Basse-Terre'
            when '02' then 'Fort-de-France'
            when '03' then 'Cayenne'
            when '04' then 'Saint-Denis'
            when '06' then 'Mamoudzou'
            when '11' then 'Paris'
            when '24' then 'Orléans'
            when '27' then 'Dijon'
            when '28' then 'Rouen'
            when '32' then 'Lille'
            when '44' then 'Strasbourg'
            when '52' then 'Nantes'
            when '53' then 'Rennes'
            when '75' then 'Bordeaux'
            when '76' then 'Toulouse'
            when '84' then 'Lyon'
            when '93' then 'Marseille'
            when '94' then 'Ajaccio'
        end as chef_lieu_region

    from raw_regions

)

select
    to_hex(sha256(to_json_string(struct(code_region)))) as id_region,
    *
from final
order by code_region
