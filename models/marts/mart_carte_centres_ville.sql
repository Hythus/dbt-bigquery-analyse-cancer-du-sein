with centres_ville as (

    select
        code_region,
        max(nom_region) as nom_region,
        code_departement,
        max(nom_departement) as nom_departement,
        ville,
        case
            when code_region = '04'
                then concat(
                    regexp_replace(regexp_replace(ville, r'^ST[\s-]+', 'SAINT-'), r'^STE[\s-]+', 'SAINTE-'),
                    ', Réunion'
                )
            when code_region in ('01', '02', '03', '06')
                then concat(
                    regexp_replace(regexp_replace(ville, r'^ST[\s-]+', 'SAINT-'), r'^STE[\s-]+', 'SAINTE-'),
                    ', ',
                    max(nom_departement)
                )
            else concat(
                regexp_replace(regexp_replace(ville, r'^ST[\s-]+', 'SAINT-'), r'^STE[\s-]+', 'SAINTE-'),
                ', ',
                max(nom_departement),
                ', France'
            )
        end as localisation_complete,
        cast(count(nom_centre_radiologie) as int64) as nb_centres
    from {{ ref('stg_centres_radiologie') }}
    group by code_region, code_departement, ville

)

select
    to_hex(sha256(to_json_string(struct(
        code_region, code_departement, ville
    )))) as id_mart_carte_ville,
    *
from centres_ville

