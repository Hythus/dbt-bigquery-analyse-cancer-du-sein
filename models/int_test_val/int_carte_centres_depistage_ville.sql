with nb_centre_ville as (

    select
        code_region,
        max(nom_region) as nom_region,
        code_departement,
        max(nom_departement) as nom_departement,
        ville,
        count(nom_centre_radiologie) as nb_centre
    from {{ ref('stg_centres_radiologie') }}
    group by code_region, code_departement, ville

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

pop_region as (

    select
        annee,
        code_region,
        sum(population) as population_regionale
    from {{ ref('stg_pop_regions_age') }}
    where code_sexe = 'E'
    group by 1, 2

),

-- Superficies officielles INSEE/IGN des régions françaises en km²
superficie as (

    select code_region, superficie_km2
    from unnest([
        struct('01' as code_region, 1628.4 as superficie_km2),
        struct('02', 1128.0),
        struct('03', 83533.9),
        struct('04', 2503.7),
        struct('06', 374.0),
        struct('11', 12011.0),
        struct('24', 39151.0),
        struct('27', 47784.0),
        struct('28', 29907.0),
        struct('32', 31806.0),
        struct('44', 57441.0),
        struct('52', 32082.0),
        struct('53', 27208.0),
        struct('75', 84036.0),
        struct('76', 72724.0),
        struct('84', 69711.0),
        struct('93', 31400.0),
        struct('94', 8680.0)
    ])

),

joined as (

    select
        p.periode_biennale,
        p.annee_fin_periode,
        nb.code_region,
        nb.nom_region,
        nb.code_departement,
        nb.nom_departement,
        nb.ville,
        concat(nb.ville, ', ', nb.nom_departement, ', France') as localisation_complete,
        cast(nb.nb_centre as int64) as nb_centre,
        cast(sum(nb.nb_centre) over (partition by p.periode_biennale, nb.code_region) as int64) as nb_centres_total_region,
        p.moy_taux_std_participation,
        cast(pr.population_regionale as int64) as population_regionale,
        s.superficie_km2 as superficie_region_km2,
        round(safe_divide(pr.population_regionale, s.superficie_km2), 1) as densite_population_hab_km2,
        round(safe_divide(
            sum(nb.nb_centre) over (partition by p.periode_biennale, nb.code_region) * 100000,
            pr.population_regionale
        ), 2) as densite_centres_region_pour_100k_hab
    from nb_centre_ville nb
    inner join participation p
      on nb.code_region = p.code_region
    left join pop_region pr
      on nb.code_region = pr.code_region
     and p.annee_fin_periode = pr.annee
    left join superficie s
      on nb.code_region = s.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        periode_biennale, code_region, code_departement, ville
    )))) as id_carte_centre_ville,
    *
from joined
