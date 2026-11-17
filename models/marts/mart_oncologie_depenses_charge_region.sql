with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

dep_nat as (

    select
        annee,
        localisation_cancer,
        statut_cancer,
        max(nb_patients_pathologie) as nb_patients_france_officiel,
        sum(montant_depense_euros) as montant_national_euros
    from {{ ref('stg_depenses_onco') }}
    where annee between 2018 and 2024
      and categorie_depense in (
          'Hospitalisations (tous secteurs)',
          'Soins de ville',
          'Prestations en espèces'
      )
      and poste_depense not like 'TOTAL%'
      and statut_cancer in ('Actif', 'Sous surveillance')
      and localisation_cancer in (
          'Cancer du sein de la femme',
          'Cancer colorectal',
          'Cancer bronchopulmonaire',
          'Cancer de la prostate',
          'Autres cancers'
      )
    group by 1, 2, 3

),

eff_reg as (

    select
        annee,
        code_region,
        case
            when code_pathologie in ('CAN_SEI_ACT', 'CAN_SEI_SUR') then 'Cancer du sein de la femme'
            when code_pathologie in ('CAN_CRE_ACT', 'CAN_CRE_SUR') then 'Cancer colorectal'
            when code_pathologie in ('CAN_BPU_ACT', 'CAN_BPU_SUR') then 'Cancer bronchopulmonaire'
            when code_pathologie in ('CAN_PRO_ACT', 'CAN_PRO_SUR') then 'Cancer de la prostate'
            when code_pathologie in ('CAN_AUT_ACT', 'CAN_AUT_SUR') then 'Autres cancers'
        end as localisation_cancer,
        case
            when code_pathologie like '%_ACT' then 'Actif'
            when code_pathologie like '%_SUR' then 'Sous surveillance'
        end as statut_cancer,
        -- Remplace NULL (secret statistique < 11 à Mayotte) par 0 pour conserver un total non nul
        coalesce(nb_patients, 0) as nb_patients_region
    from {{ ref('stg_effectifs_region') }}
    where annee between 2018 and 2024
      and code_pathologie in (
          'CAN_SEI_ACT', 'CAN_SEI_SUR',
          'CAN_CRE_ACT', 'CAN_CRE_SUR',
          'CAN_BPU_ACT', 'CAN_BPU_SUR',
          'CAN_PRO_ACT', 'CAN_PRO_SUR',
          'CAN_AUT_ACT', 'CAN_AUT_SUR'
      )

),

depenses_et_effectifs as (

    select
        d.annee,
        e.code_region,
        d.localisation_cancer as specialite_oncologique,
        cast(sum(e.nb_patients_region) as int64) as nb_patients_ameli,
        round(
            sum(
                cast(d.montant_national_euros as float64)
                * safe_divide(cast(e.nb_patients_region as float64), cast(d.nb_patients_france_officiel as float64))
            ),
            2
        ) as depense_totale_euros
    from dep_nat d
    inner join eff_reg e
      on d.annee = e.annee
     and d.localisation_cancer = e.localisation_cancer
     and d.statut_cancer = e.statut_cancer
    group by 1, 2, 3

),

charge_5_specialites as (

    select
        c.annee,
        r.code_region,
        case trim(c.libelle_pathologie)
            when 'Tumeur maligne du sein' then 'Cancer du sein de la femme'
            when 'Tumeurs malignes colo-rectales' then 'Cancer colorectal'
            when 'T.M. trachée_bronches_poumon' then 'Cancer bronchopulmonaire'
            when 'Tumeur maligne de la prostate' then 'Cancer de la prostate'
            else 'Autres cancers'
        end as specialite_oncologique,
        cast(sum(coalesce(c.nb_sejours_total, 0)) as int64) as nb_sejours_total,
        cast(sum(coalesce(c.nb_sejours_moins_24h, 0)) as int64) as nb_sejours_ambulatoire_moins_24h,
        cast(
            sum(coalesce(c.nb_sejours_total, 0) - coalesce(c.nb_sejours_moins_24h, 0))
            as int64
        ) as nb_sejours_24h_plus,
        round(sum(coalesce(cast(c.nb_journees_estimees as float64), 0.0)), 2) as nb_journees_estimees
    from {{ ref('stg_charge_region') }} c
    inner join regions r
      on case
            when trim(c.nom_region) in ('Centre-Val de Loire', 'Centre-Val-de-Loire') then 'Centre-Val-de-Loire'
            else trim(c.nom_region)
         end = r.nom_region
    where c.annee between 2018 and 2024
      and c.famille_tumeur = 'Maligne'
    group by 1, 2, 3

),

joined as (

    select
        d.annee,
        d.code_region,
        d.specialite_oncologique,
        case d.specialite_oncologique
            when 'Cancer du sein de la femme' then 1
            when 'Cancer colorectal' then 2
            when 'Cancer bronchopulmonaire' then 3
            when 'Cancer de la prostate' then 4
            when 'Autres cancers' then 5
        end as ordre_specialite,
        (d.specialite_oncologique = 'Cancer du sein de la femme') as est_cancer_sein,
        d.nb_patients_ameli,
        d.depense_totale_euros,
        c.nb_sejours_total,
        c.nb_sejours_ambulatoire_moins_24h,
        c.nb_sejours_24h_plus,
        c.nb_journees_estimees
    from depenses_et_effectifs d
    inner join charge_5_specialites c
      on d.annee = c.annee
     and d.code_region = c.code_region
     and d.specialite_oncologique = c.specialite_oncologique

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, specialite_oncologique
    )))) as id_mart_onco_depenses_charge,
    *
from joined
