with dep_nat as (

    select
        annee,
        localisation_cancer,
        statut_cancer,
        categorie_depense,
        max(nb_patients_pathologie) as nb_patients_france_officiel,
        sum(montant_depense_euros) as montant_national_euros
    from {{ ref('stg_depenses_onco') }}
    where annee between 2018 and 2024
    group by 1, 2, 3, 4

),

eff_reg as (

    select
        annee,
        code_region,
        nom_region,
        case
            when code_pathologie in ('CAN_SEI_ACT', 'CAN_SEI_SUR') then 'Cancer du sein de la femme'
            when code_pathologie in ('CAN_BPU_ACT', 'CAN_BPU_SUR') then 'Cancer bronchopulmonaire'
            when code_pathologie in ('CAN_CRE_ACT', 'CAN_CRE_SUR') then 'Cancer colorectal'
            when code_pathologie in ('CAN_PRO_ACT', 'CAN_PRO_SUR') then 'Cancer de la prostate'
            when code_pathologie in ('CAN_AUT_ACT', 'CAN_AUT_SUR') then 'Autres cancers'
        end as localisation_cancer,
        case
            when code_pathologie like '%_ACT' then 'Actif'
            when code_pathologie like '%_SUR' then 'Sous surveillance'
        end as statut_cancer,
        nb_patients as nb_patients_region
    from {{ ref('stg_effectifs_region') }}
    where annee between 2018 and 2024

),

dep_ventilees as (

    select
        d.annee,
        e.code_region,
        e.nom_region,
        d.localisation_cancer,
        d.statut_cancer,
        d.categorie_depense,
        d.montant_national_euros,
        e.nb_patients_region,
        d.nb_patients_france_officiel,
        safe_divide(e.nb_patients_region, d.nb_patients_france_officiel) as part_regionale,
        d.montant_national_euros * safe_divide(e.nb_patients_region, d.nb_patients_france_officiel) as montant_regional_sous_patho
    from dep_nat d
    inner join eff_reg e
      on d.annee = e.annee
     and d.localisation_cancer = e.localisation_cancer
     and d.statut_cancer = e.statut_cancer

),

aggr_par_patho as (

    select
        annee,
        code_region,
        nom_region,
        localisation_cancer,
        categorie_depense,
        round(sum(montant_regional_sous_patho), 2) as montant_regional_euros
    from dep_ventilees
    group by 1, 2, 3, 4, 5

),

total_onco_reg as (

    select
        annee,
        code_region,
        nom_region,
        categorie_depense,
        round(sum(montant_regional_euros), 2) as montant_total_onco_regional
    from aggr_par_patho
    group by 1, 2, 3, 4

),

patientes_sein as (

    select
        annee,
        code_region,
        sum(nb_patients_region) as nb_patientes
    from eff_reg
    where localisation_cancer = 'Cancer du sein de la femme'
    group by 1, 2

),

joined as (

    select
        s.annee,
        s.code_region,
        s.nom_region as libelle_region,
        s.localisation_cancer as pathologie,
        s.categorie_depense as type_de_depense,
        s.montant_regional_euros as montant_euros,
        s.montant_regional_euros as montant_sein_euros,
        t.montant_total_onco_regional as montant_onco_total_euros,
        round(safe_divide(s.montant_regional_euros, t.montant_total_onco_regional), 4) as ratio_cancer_sein_patho_onco,
        cast(p.nb_patientes as int64) as nb_patientes,
        round(safe_divide(s.montant_regional_euros, p.nb_patientes), 2) as cout_moyen_par_patiente_euros

    from aggr_par_patho s
    inner join total_onco_reg t
      on s.annee = t.annee
     and s.code_region = t.code_region
     and s.nom_region = t.nom_region
     and s.categorie_depense = t.categorie_depense
    left join patientes_sein p
      on s.annee = p.annee
     and s.code_region = p.code_region
    where s.localisation_cancer = 'Cancer du sein de la femme'

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region, type_de_depense
    )))) as id_depense_regionale,
    *
from joined
