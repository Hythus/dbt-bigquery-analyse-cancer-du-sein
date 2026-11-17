with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

dep_nat as (

    select
        annee,
        localisation_cancer as famille_ameli,
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
          'Cancer bronchopulmonaire',
          'Cancer de la prostate',
          'Cancer colorectal',
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
            when code_pathologie in ('CAN_BPU_ACT', 'CAN_BPU_SUR') then 'Cancer bronchopulmonaire'
            when code_pathologie in ('CAN_PRO_ACT', 'CAN_PRO_SUR') then 'Cancer de la prostate'
            when code_pathologie in ('CAN_CRE_ACT', 'CAN_CRE_SUR') then 'Cancer colorectal'
            when code_pathologie in ('CAN_AUT_ACT', 'CAN_AUT_SUR') then 'Autres cancers'
        end as famille_ameli,
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
          'CAN_BPU_ACT', 'CAN_BPU_SUR',
          'CAN_PRO_ACT', 'CAN_PRO_SUR',
          'CAN_CRE_ACT', 'CAN_CRE_SUR',
          'CAN_AUT_ACT', 'CAN_AUT_SUR'
      )

),

depenses_et_effectifs_5 as (

    select
        d.annee,
        e.code_region,
        d.famille_ameli,
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
     and d.famille_ameli = e.famille_ameli
     and d.statut_cancer = e.statut_cancer
    group by 1, 2, 3

),

charge_mapped as (

    select
        c.annee,
        r.code_region,
        case
            when trim(c.libelle_pathologie) = 'Tumeur maligne du sein'
                then 'Cancer du sein de la femme'
            when trim(c.libelle_pathologie) = 'T.M. trachée_bronches_poumon'
                then 'Cancer bronchopulmonaire'
            when trim(c.libelle_pathologie) = 'Tumeur maligne de la prostate'
                then 'Cancer de la prostate'
            when trim(c.libelle_pathologie) = 'Tumeurs malignes colo-rectales'
                then 'Cancer colorectal'
            when trim(c.libelle_pathologie) = 'Tumeurs malignes secondaires'
                then 'Métastases (secondaires)'
            when trim(c.libelle_pathologie) in (
                'Tumeur maligne du pancréas',
                'T.M.foie et voies biliaires intrahép',
                'Tumeur maligne de l\'estomac',
                'Tumeur maligne de l\'oesophage'
            ) then 'Autres digestifs (pancréas, foie, estomac, œsophage)'
            when trim(c.libelle_pathologie) = 'Tumeur maligne de la vessie'
                then 'Cancer de la vessie'
            when trim(c.libelle_pathologie) in ('Leucémies', 'T.M. système nerveux central')
                then 'Hématologie (leucémies) & SNC'
            when trim(c.libelle_pathologie) in (
                'T.M. lèvre _bouche_pharynx',
                'Tumeur maligne du larynx',
                'Tumeur maligne de l\'utérus',
                'Mélanome malin de la peau',
                'Tumeur maligne de la thyroïde'
            ) then 'ORL, Utérus, Peau & Thyroïde'
            else 'Autres cancers (non détaillés)'
        end as specialite_oncologique,
        coalesce(c.nb_sejours_total, 0) as nb_sejours_total,
        coalesce(c.nb_sejours_moins_24h, 0) as nb_sejours_moins_24h,
        coalesce(cast(c.nb_journees_estimees as float64), 0.0) as nb_journees_estimees
    from {{ ref('stg_charge_region') }} c
    inner join regions r
      on case
            when trim(c.nom_region) in ('Centre-Val de Loire', 'Centre-Val-de-Loire') then 'Centre-Val-de-Loire'
            else trim(c.nom_region)
         end = r.nom_region
    where c.annee between 2018 and 2024
      and c.famille_tumeur = 'Maligne'

),

charge_10_specialites as (

    select
        annee,
        code_region,
        specialite_oncologique,
        case specialite_oncologique
            when 'Cancer du sein de la femme' then 'Cancer du sein de la femme'
            when 'Cancer bronchopulmonaire' then 'Cancer bronchopulmonaire'
            when 'Cancer de la prostate' then 'Cancer de la prostate'
            when 'Cancer colorectal' then 'Cancer colorectal'
            else 'Autres cancers'
        end as famille_ameli,
        case specialite_oncologique
            when 'Cancer du sein de la femme' then 1
            when 'Cancer bronchopulmonaire' then 2
            when 'Cancer de la prostate' then 3
            when 'Cancer colorectal' then 4
            when 'Métastases (secondaires)' then 5
            when 'Autres digestifs (pancréas, foie, estomac, œsophage)' then 6
            when 'Cancer de la vessie' then 7
            when 'Hématologie (leucémies) & SNC' then 8
            when 'ORL, Utérus, Peau & Thyroïde' then 9
            when 'Autres cancers (non détaillés)' then 10
        end as ordre_specialite,
        cast(sum(nb_sejours_total) as int64) as nb_sejours_total,
        cast(sum(nb_sejours_moins_24h) as int64) as nb_sejours_ambulatoire_moins_24h,
        cast(sum(nb_sejours_total - nb_sejours_moins_24h) as int64) as nb_sejours_24h_plus,
        round(sum(nb_journees_estimees), 2) as nb_journees_estimees
    from charge_mapped
    group by 1, 2, 3, 4, 5

),

charge_with_weights as (

    select
        *,
        safe_divide(
            cast(nb_sejours_total as float64),
            cast(
                sum(case when famille_ameli = 'Autres cancers' then nb_sejours_total else 0 end)
                over (partition by annee, code_region)
                as float64
            )
        ) as poids_dans_autres
    from charge_10_specialites

),

joined as (

    select
        c.annee,
        c.code_region,
        c.specialite_oncologique,
        c.ordre_specialite,
        (c.specialite_oncologique = 'Cancer du sein de la femme') as est_cancer_sein,
        case
            when c.famille_ameli != 'Autres cancers' then d.nb_patients_ameli
            else cast(round(cast(d.nb_patients_ameli as float64) * c.poids_dans_autres) as int64)
        end as nb_patients_ameli,
        case
            when c.famille_ameli != 'Autres cancers' then d.depense_totale_euros
            else round(d.depense_totale_euros * c.poids_dans_autres, 2)
        end as depense_totale_euros,
        c.nb_sejours_total,
        c.nb_sejours_ambulatoire_moins_24h,
        c.nb_sejours_24h_plus,
        c.nb_journees_estimees
    from charge_with_weights c
    inner join depenses_et_effectifs_5 d
      on c.annee = d.annee
     and c.code_region = d.code_region
     and c.famille_ameli = d.famille_ameli

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, specialite_oncologique
    )))) as id_mart_onco_depenses_charge,
    *
from joined
