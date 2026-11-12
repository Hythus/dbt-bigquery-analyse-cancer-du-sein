with charge as (

    select
        annee,
        case
            when trim(nom_region) in ('Centre-Val de Loire', 'Centre-Val-de-Loire') then 'Centre-Val-de-Loire'
            else trim(nom_region)
        end as nom_region,
        libelle_pathologie,
        nb_sejours_total,
        nb_sejours_moins_24h,
        (nb_sejours_1j + nb_sejours_2j + nb_sejours_3j + nb_sejours_4j + nb_sejours_5j + nb_sejours_6j + nb_sejours_7j) as nb_sejours_inf_ou_egal_7j,
        (nb_sejours_8j + nb_sejours_9j + nb_sejours_10_19j + nb_sejours_20_29j + nb_sejours_30j_plus) as nb_sejours_sup_7j
    from {{ ref('stg_charge_region') }}

),

dms as (

    select
        annee,
        case
            when trim(nom_region) in ('Centre-Val de Loire', 'Centre-Val-de-Loire') then 'Centre-Val-de-Loire'
            else trim(nom_region)
        end as nom_region,
        libelle_pathologie,
        duree_moyenne_sejour_jours as dms
    from {{ ref('stg_dms_region') }}

),

regions as (

    select distinct
        nom_region,
        code_region
    from {{ ref('stg_pop_cible_regions') }}

),

total_onco as (

    select
        annee,
        nom_region,
        sum(nb_sejours_total) as nb_sejours_total_onco
    from charge
    group by 1, 2

),

joined as (

    select
        c.annee,
        r.code_region,
        c.nom_region as libelle_region,
        c.libelle_pathologie as pathologie,
        round(cast(d.dms as float64), 2) as dms,
        cast(c.nb_sejours_moins_24h as int64) as nb_sejours_moins_24h,
        cast(c.nb_sejours_inf_ou_egal_7j as int64) as nb_sejours_inf_ou_egal_7j,
        cast(c.nb_sejours_sup_7j as int64) as nb_sejours_sup_7j,
        cast(c.nb_sejours_total as int64) as nbre_hospitalisation,
        round(safe_divide(c.nb_sejours_total, t.nb_sejours_total_onco), 4) as ratio_cancer_sein_patho_onco

    from charge c
    left join dms d
      on c.annee = d.annee
     and c.nom_region = d.nom_region
     and c.libelle_pathologie = d.libelle_pathologie
    left join regions r
      on c.nom_region = r.nom_region
    left join total_onco t
      on c.annee = t.annee
     and c.nom_region = t.nom_region
    where c.libelle_pathologie = 'Tumeur maligne du sein'

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_charge_hospitaliere,
    *
from joined

