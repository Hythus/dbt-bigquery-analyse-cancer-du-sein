{{ config(materialized='table') }}

with dep_sein as (

    select
        annee,
        statut_cancer,
        categorie_depense as categorie_depense_cnam,
        poste_depense,
        secteur_hospitalier,
        montant_depense_euros,
        nb_patients_pathologie as nb_patientes_pathologie,
        nb_patients_recourant_poste as nb_patientes_recourant_poste
    from {{ ref('stg_depenses_onco') }}
    where localisation_cancer = 'Cancer du sein de la femme'
      and annee between 2015 and 2024

),

totaux_onco as (

    select
        annee,
        sum(montant_depense_euros) as total_annuel_oncologie_cnam_euros
    from {{ ref('stg_depenses_onco') }}
    where annee between 2015 and 2024
    group by 1

),

totaux_sein as (

    select
        annee,
        sum(montant_depense_euros) as total_annuel_cancer_sein_euros
    from dep_sein
    group by 1

),

-- Référentiels macroéconomiques annuels 2015-2024 :
-- 1) Total toutes pathologies Cartographie Cnam (API data.ameli.fr / depenses : patho_niv1 = 'Total consommants tous régimes', dep_niv_2 = 'Total des dépenses remboursées')
-- 2) ONDAM exécuté / constaté LFSS-PLACSS (dont 247,1 Md€ en 2022)
macro_ref as (

    select *
    from unnest([
        struct(2015 as annee, 152713458598 as total_annuel_cartographie_cnam_euros, 181700000000 as ondam_annuel_euros),
        struct(2016, 156710278860, 185200000000),
        struct(2017, 160752783551, 190700000000),
        struct(2018, 164178819961, 195200000000),
        struct(2019, 168021386937, 200300000000),
        struct(2020, 167958135909, 219500000000),
        struct(2021, 186939955562, 239500000000),
        struct(2022, 193764233127, 247100000000),
        struct(2023, 202228965106, 247800000000),
        struct(2024, 212579415223, 256900000000)
    ])

),

enriched as (

    select
        d.annee,
        d.statut_cancer,
        case
            when d.poste_depense in ('Ville - médicaments', 'Hôpital - liste en sus MCO') then 1
            when d.categorie_depense_cnam = 'Hospitalisations (tous secteurs)' then 2
            when d.categorie_depense_cnam = 'Soins de ville' then 3
            else 4
        end as ordre_pole_4,
        case
            when d.poste_depense in ('Ville - médicaments', 'Hôpital - liste en sus MCO') then 'Médicaments (Ville & Liste en sus MCO)'
            when d.categorie_depense_cnam = 'Hospitalisations (tous secteurs)' then 'Hospitalisations (Séjours MCO, HAD, SSR, ACE)'
            when d.categorie_depense_cnam = 'Soins de ville' then 'Soins de ville (Consultations, transports, paramédical, biologie)'
            else 'Prestations en espèces (IJ maladie & Invalidité)'
        end as pole_depense_4,
        d.categorie_depense_cnam,
        d.poste_depense,
        d.secteur_hospitalier,
        cast(d.montant_depense_euros as int64) as montant_depense_euros,
        round(cast(d.montant_depense_euros as float64) / 1000000.0, 2) as montant_depense_millions_euros,
        cast(d.nb_patientes_pathologie as int64) as nb_patientes_pathologie,
        cast(d.nb_patientes_recourant_poste as int64) as nb_patientes_recourant_poste,
        round(safe_divide(cast(d.nb_patientes_recourant_poste as float64) * 100.0, nullif(cast(d.nb_patientes_pathologie as float64), 0.0)), 2) as taux_recours_poste_pct,
        round(safe_divide(cast(d.montant_depense_euros as float64), nullif(cast(d.nb_patientes_recourant_poste as float64), 0.0)), 2) as cout_moyen_par_patiente_recourante_euros,
        cast(first_value(d.montant_depense_euros) over (
            partition by d.statut_cancer, d.poste_depense, d.secteur_hospitalier
            order by d.annee
        ) as int64) as montant_poste_base_2015_euros,
        round(safe_divide(
            cast(d.montant_depense_euros as float64) * 100.0,
            nullif(cast(first_value(d.montant_depense_euros) over (
                partition by d.statut_cancer, d.poste_depense, d.secteur_hospitalier
                order by d.annee
            ) as float64), 0.0)
        ), 1) as indice_evolution_base_100_2015,
        round((power(safe_divide(
            cast(max(case when d.annee = 2024 then d.montant_depense_euros end) over (
                partition by d.statut_cancer, d.poste_depense, d.secteur_hospitalier
            ) as float64),
            nullif(cast(first_value(d.montant_depense_euros) over (
                partition by d.statut_cancer, d.poste_depense, d.secteur_hospitalier
                order by d.annee
            ) as float64), 0.0)
        ), 1.0 / 9.0) - 1.0) * 100.0, 2) as tcac_2015_2024_pct,
        cast(ts.total_annuel_cancer_sein_euros as int64) as total_annuel_cancer_sein_euros,
        round(safe_divide(cast(d.montant_depense_euros as float64) * 100.0, cast(ts.total_annuel_cancer_sein_euros as float64)), 2) as part_poste_dans_cancer_sein_pct,
        cast(to_.total_annuel_oncologie_cnam_euros as int64) as total_annuel_oncologie_cnam_euros,
        round(safe_divide(cast(d.montant_depense_euros as float64) * 100.0, cast(to_.total_annuel_oncologie_cnam_euros as float64)), 2) as part_poste_dans_oncologie_cnam_pct,
        round(safe_divide(cast(ts.total_annuel_cancer_sein_euros as float64) * 100.0, cast(to_.total_annuel_oncologie_cnam_euros as float64)), 2) as part_cancer_sein_dans_oncologie_cnam_pct,
        cast(m.total_annuel_cartographie_cnam_euros as int64) as total_annuel_cartographie_cnam_euros,
        round(safe_divide(cast(ts.total_annuel_cancer_sein_euros as float64) * 100.0, cast(m.total_annuel_cartographie_cnam_euros as float64)), 2) as part_cancer_sein_dans_cartographie_cnam_pct,
        cast(m.ondam_annuel_euros as int64) as ondam_annuel_euros,
        round(safe_divide(cast(ts.total_annuel_cancer_sein_euros as float64) * 100.0, cast(m.ondam_annuel_euros as float64)), 2) as part_cancer_sein_dans_ondam_pct
    from dep_sein d
    inner join totaux_sein ts
      on d.annee = ts.annee
    inner join totaux_onco to_
      on d.annee = to_.annee
    inner join macro_ref m
      on d.annee = m.annee

)

select
    to_hex(sha256(to_json_string(struct(
        annee, statut_cancer, poste_depense, secteur_hospitalier
    )))) as id_mart_depense_poste,
    *
from enriched
