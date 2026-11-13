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

pop_cible as (

    select
        annee,
        code_region,
        population_femmes_50_74_ans as femmes_50_74,
        population_femmes_total as femmes_total
    from {{ ref('stg_pop_cible_regions') }}

),

joined as (

    select
        p.periode_biennale,
        p.annee_fin_periode,
        nb.code_region,
        nb.nom_region,
        cast(nb.nb_centre as int64) as nb_centre,
        cast(pop.femmes_50_74 as int64) as femmes_50_74,
        cast(pop.femmes_total as int64) as femmes_total,
        p.moy_taux_std_participation,
        cast(round(pop.femmes_50_74 * (p.moy_taux_std_participation / 100.0)) as int64) as nb_femmes_participantes_estime,
        cast(pop.femmes_50_74 - round(pop.femmes_50_74 * (p.moy_taux_std_participation / 100.0)) as int64) as nb_femmes_non_participantes_estime,
        cast(round(safe_divide(pop.femmes_50_74, nb.nb_centre)) as int64) as nb_femmes_50_74_par_centre
    from nb_centre_region nb
    inner join participation p
      on nb.code_region = p.code_region
    left join pop_cible pop
      on nb.code_region = pop.code_region
     and p.annee_fin_periode = pop.annee

)

select
    to_hex(sha256(to_json_string(struct(
        periode_biennale, code_region
    )))) as id_centre_taux_depistage,
    *
from joined
