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
    where annee between 2018 and 2024

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
    where annee between 2018 and 2024

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

patientes as (

    select
        annee,
        code_region,
        sum(nb_patients) as nb_patientes
    from {{ ref('stg_effectifs_region') }}
    where code_pathologie in ('CAN_SEI_ACT', 'CAN_SEI_SUR')
      and annee between 2018 and 2024
    group by 1, 2

),

joined as (

    select
        c.annee,
        r.code_region,
        c.nom_region as libelle_region,
        c.libelle_pathologie as pathologie,
        round(cast(d.dms as float64), 2) as dms_jours,
        cast(c.nb_sejours_moins_24h as int64) as nb_sejours_moins_24h,
        cast(c.nb_sejours_inf_ou_egal_7j as int64) as nb_sejours_inf_ou_egal_7j,
        cast(c.nb_sejours_sup_7j as int64) as nb_sejours_sup_7j,
        cast(c.nb_sejours_total as int64) as nbre_hospitalisation,
        cast(c.nb_sejours_total as int64) as nb_sejours_sein,
        cast(t.nb_sejours_total_onco as int64) as nb_sejours_onco_total,
        round(safe_divide(c.nb_sejours_total, t.nb_sejours_total_onco), 4) as ratio_cancer_sein_patho_onco,
        cast(p.nb_patientes as int64) as nb_patientes,
        round(safe_divide(c.nb_sejours_total, p.nb_patientes), 4) as taux_sejours_par_patiente

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
    left join patientes p
      on c.annee = p.annee
     and r.code_region = p.code_region
    where c.libelle_pathologie = 'Tumeur maligne du sein'

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_charge_hospitaliere,
    *
from joined
