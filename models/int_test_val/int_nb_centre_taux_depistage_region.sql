with nb_centre_region as (

    select
        code_region,
        max(nom_region) as nom_region,
        count(nom_centre_radiologie) as nb_centre
    from {{ ref('stg_centres_radiologie') }}
    group by 1

),

participation as (

    select
        code_region,
        periode_biennale,
        annee_fin_periode,
        round(avg(taux_participation_std_pct), 2) as moy_taux_std_participation
    from {{ ref('stg_depistage_taux_standardise_2016_2025') }}
    group by 1, 2, 3

),

joined as (

    select
        p.periode_biennale,
        p.annee_fin_periode,
        nb.code_region,
        nb.nom_region,
        cast(nb.nb_centre as int64) as nb_centre,
        p.moy_taux_std_participation
    from nb_centre_region nb
    inner join participation p
      on nb.code_region = p.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        periode_biennale, code_region
    )))) as id_centre_taux_depistage,
    *
from joined
