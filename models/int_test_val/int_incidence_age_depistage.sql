with detail as (

    select
        annee,
        tranche_age,
        'Tranche quinquennale' as niveau_agregation,
        case
            when age_max < 50 then '20-49 ans (hors dépistage)'
            when age_min >= 50 and age_max <= 74 then '50-74 ans (cible dépistage)'
            else '75 ans et plus (post dépistage)'
        end as groupe_depistage,
        case when age_min >= 50 and age_max <= 74 then true else false end as est_cible_depistage_organise,
        age_min,
        age_max,
        case tranche_age
            when '20-24 ans' then 1
            when '25-29 ans' then 2
            when '30-34 ans' then 3
            when '35-39 ans' then 4
            when '40-44 ans' then 5
            when '45-49 ans' then 6
            when '50-54 ans' then 7
            when '55-59 ans' then 8
            when '60-64 ans' then 9
            when '65-69 ans' then 10
            when '70-74 ans' then 11
            when '75-79 ans' then 12
            when '80-84 ans' then 13
            when '85 ans et plus' then 14
        end as ordre_affichage,
        nb_nouveaux_cas,
        nb_personnes_annees,
        round(taux_incidence_brut, 2) as taux_incidence_brut,
        round(taux_incidence_brut_ic_inf, 2) as taux_incidence_ic_inf,
        round(taux_incidence_brut_ic_sup, 2) as taux_incidence_ic_sup
    from {{ ref('stg_incidence_france_age') }}
    -- Nettoyage métier : exclusion des tranches < 20 ans (incidence quasi nulle représentant moins de 0.05% des cas)
    where age_min >= 20

),

macro as (

    select
        annee,
        groupe_depistage as tranche_age,
        'Groupe dépistage' as niveau_agregation,
        groupe_depistage,
        est_cible_depistage_organise,
        min(age_min) as age_min,
        max(age_max) as age_max,
        case groupe_depistage
            when '20-49 ans (hors dépistage)' then 101
            when '50-74 ans (cible dépistage)' then 102
            when '75 ans et plus (post dépistage)' then 103
        end as ordre_affichage,
        sum(nb_nouveaux_cas) as nb_nouveaux_cas,
        sum(nb_personnes_annees) as nb_personnes_annees,
        round(safe_divide(sum(nb_nouveaux_cas) * 100000, sum(nb_personnes_annees)), 2) as taux_incidence_brut,
        cast(null as float64) as taux_incidence_ic_inf,
        cast(null as float64) as taux_incidence_ic_sup
    from detail
    group by 1, 2, 4, 5, 8

),

national as (

    select
        annee,
        'Ensemble des 20 ans et plus' as tranche_age,
        'Total national' as niveau_agregation,
        'Total national' as groupe_depistage,
        false as est_cible_depistage_organise,
        20 as age_min,
        cast(null as int64) as age_max,
        200 as ordre_affichage,
        sum(nb_nouveaux_cas) as nb_nouveaux_cas,
        sum(nb_personnes_annees) as nb_personnes_annees,
        round(safe_divide(sum(nb_nouveaux_cas) * 100000, sum(nb_personnes_annees)), 2) as taux_incidence_brut,
        cast(null as float64) as taux_incidence_ic_inf,
        cast(null as float64) as taux_incidence_ic_sup
    from detail
    group by 1

),

unioned as (

    select * from detail
    union all
    select * from macro
    union all
    select * from national

),

totaux_annee as (

    select
        annee,
        sum(nb_nouveaux_cas) as total_cas_annee
    from detail
    group by 1

),

precalcs as (

    select
        u.*,
        t.total_cas_annee,
        round(safe_divide(u.nb_nouveaux_cas * 100, t.total_cas_annee), 2) as part_cas_annee_pct,

        -- Taux de référence 1990 (début de série) et 2004 (généralisation du dépistage en France)
        first_value(u.taux_incidence_brut) over (
            partition by u.niveau_agregation, u.tranche_age order by u.annee
        ) as taux_base_1990,

        max(case when u.annee = 2004 then u.taux_incidence_brut end) over (
            partition by u.niveau_agregation, u.tranche_age
        ) as taux_base_2004,

        lag(u.taux_incidence_brut) over (
            partition by u.niveau_agregation, u.tranche_age order by u.annee
        ) as taux_annee_precedente

    from unioned u
    left join totaux_annee t
      on u.annee = t.annee

),

final as (

    select
        annee,
        tranche_age,
        niveau_agregation,
        groupe_depistage,
        est_cible_depistage_organise,
        age_min,
        age_max,
        ordre_affichage,

        -- Composantes brutes (femmes >= 20 ans)
        cast(nb_nouveaux_cas as int64) as nb_nouveaux_cas,
        round(nb_personnes_annees, 1) as nb_personnes_annees,
        cast(total_cas_annee as int64) as total_cas_annee,

        -- Taux et intervalles de confiance
        taux_incidence_brut,
        taux_incidence_ic_inf,
        taux_incidence_ic_sup,
        part_cas_annee_pct,

        -- Indices d'évolution temporelle
        round(safe_divide(taux_incidence_brut * 100, taux_base_1990), 1) as indice_base_1990,
        round(safe_divide(taux_incidence_brut * 100, taux_base_2004), 1) as indice_base_2004,
        round(safe_divide((taux_incidence_brut - taux_base_1990) * 100, taux_base_1990), 1) as evolution_pct_depuis_1990,
        round(safe_divide((taux_incidence_brut - taux_base_2004) * 100, taux_base_2004), 1) as evolution_pct_depuis_2004,
        round(safe_divide((taux_incidence_brut - taux_annee_precedente) * 100, taux_annee_precedente), 2) as evolution_annuelle_pct

    from precalcs

)

select
    to_hex(sha256(to_json_string(struct(
        annee, tranche_age, niveau_agregation
    )))) as id_incidence_age,
    *
from final
