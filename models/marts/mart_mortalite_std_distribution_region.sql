{{ config(materialized='table') }}

with regions as (

    select
        code_region,
        libelle_region as nom_region
    from {{ ref('dim_regions') }}

),

pop_decennal as (

    select
        annee,
        code_region,
        case
            when age_min < 15 then '0-14'
            when age_min between 15 and 24 then '15-24'
            when age_min between 25 and 34 then '25-34'
            when age_min between 35 and 44 then '35-44'
            when age_min between 45 and 54 then '45-54'
            when age_min between 55 and 64 then '55-64'
            when age_min between 65 and 74 then '65-74'
            when age_min between 75 and 84 then '75-84'
            when age_min between 85 and 94 then '85-94'
            else '95+'
        end as tranche_10,
        sum(population) as pop_femmes,
        sum(case when age_min between 50 and 54 then population else 0 end) as pop_50_54_dans_45_54
    from {{ ref('stg_pop_regions_age') }}
    where code_sexe = 'F'
      and annee between 2014 and 2024
    group by 1, 2, 3

),

pop_nat_2022 as (

    select
        tranche_10,
        sum(pop_femmes) as pop_ref_femmes,
        sum(pop_50_54_dans_45_54) as pop_ref_50_54
    from pop_decennal
    where annee = 2022
    group by 1

),

pop_ref_2022 as (

    select
        tranche_10,
        pop_ref_femmes,
        safe_divide(pop_ref_femmes, sum(pop_ref_femmes) over ()) as weight_tous_ages,
        safe_divide(
            case when tranche_10 in ('0-14', '15-24', '25-34', '35-44', '45-54', '55-64') then pop_ref_femmes else 0 end,
            sum(case when tranche_10 in ('0-14', '15-24', '25-34', '35-44', '45-54', '55-64') then pop_ref_femmes else 0 end) over ()
        ) as weight_moins_65,
        safe_divide(
            case when tranche_10 in ('65-74', '75-84') then pop_ref_femmes else 0 end,
            sum(case when tranche_10 in ('65-74', '75-84') then pop_ref_femmes else 0 end) over ()
        ) as weight_65_84,
        safe_divide(
            case when tranche_10 in ('75-84', '85-94', '95+') then pop_ref_femmes else 0 end,
            sum(case when tranche_10 in ('75-84', '85-94', '95+') then pop_ref_femmes else 0 end) over ()
        ) as weight_75_plus,
        safe_divide(
            case
                when tranche_10 = '45-54' then pop_ref_50_54
                when tranche_10 in ('55-64', '65-74') then pop_ref_femmes
                else 0
            end,
            sum(
                case
                    when tranche_10 = '45-54' then pop_ref_50_54
                    when tranche_10 in ('55-64', '65-74') then pop_ref_femmes
                    else 0
                end
            ) over ()
        ) as weight_50_74
    from pop_nat_2022

),

mort_decennal as (

    select
        annee_deces as annee,
        code_region,
        case trim(tranche_age_10)
            when '95 ans et plus' then '95+'
            when '95p' then '95+'
            else regexp_replace(trim(tranche_age_10), r'\s*ans$', '')
        end as tranche_10,
        sum(nb_deces) as nb_deces
    from {{ ref('stg_effectif_mortalite_region') }}
    where cause_initiale_deces = '2.1.10 Tumeur maligne du sein'
      and sexe = 'Femmes'
      and annee_deces between 2014 and 2024
    group by 1, 2, 3

),

taux_age_region as (

    select
        p.annee,
        p.code_region,
        p.tranche_10,
        p.pop_femmes,
        p.pop_50_54_dans_45_54,
        coalesce(m.nb_deces, 0) as nb_deces,
        safe_divide(cast(coalesce(m.nb_deces, 0) as float64) * 100000.0, cast(p.pop_femmes as float64)) as taux_age_100k,
        safe_divide(cast(coalesce(m.nb_deces, 0) as float64) * 100000.0, cast(p.pop_femmes as float64)) as taux_age_50_74_100k,
        ref.weight_tous_ages,
        ref.weight_moins_65,
        ref.weight_50_74,
        ref.weight_65_84,
        ref.weight_75_plus
    from pop_decennal p
    left join mort_decennal m
      on p.annee = m.annee
     and p.code_region = m.code_region
     and p.tranche_10 = m.tranche_10
    inner join pop_ref_2022 ref
      on p.tranche_10 = ref.tranche_10

),

region_annuel as (

    select
        t.annee,
        t.code_region,
        r.nom_region,
        t.annee between 2014 and 2022 as est_periode_2014_2022,
        cast(sum(t.nb_deces) as int64) as nb_deces_sein_femmes,
        cast(sum(t.pop_femmes) as int64) as population_femmes_insee,
        round(safe_divide(sum(t.nb_deces) * 100000.0, sum(t.pop_femmes)), 2) as taux_mortalite_brut_100k,
        round(sum(t.taux_age_100k * t.weight_tous_ages), 2) as taux_mortalite_std_tous_ages_100k,
        round(sum(t.taux_age_100k * t.weight_moins_65), 2) as taux_mortalite_std_moins_65_100k,
        round(sum(coalesce(t.taux_age_50_74_100k, 0.0) * t.weight_50_74), 2) as taux_mortalite_std_50_74_100k,
        round(sum(t.taux_age_100k * t.weight_65_84), 2) as taux_mortalite_std_65_84_100k,
        round(sum(t.taux_age_100k * t.weight_75_plus), 2) as taux_mortalite_std_75_plus_100k
    from taux_age_region t
    inner join regions r
      on t.code_region = r.code_region
    group by 1, 2, 3, 4

),

france_annuel as (

    select
        t.annee,
        t.tranche_10,
        sum(t.pop_femmes) as pop_f_fr,
        sum(t.nb_deces) as deces_fr,
        any_value(t.weight_tous_ages) as weight_tous_ages
    from taux_age_region t
    group by 1, 2

),

france_tsm as (

    select
        annee,
        round(sum(safe_divide(deces_fr * 100000.0, pop_f_fr) * weight_tous_ages), 2) as taux_mortalite_std_france_100k
    from france_annuel
    group by 1

),

dist_2014_2022 as (

    select distinct
        code_region,
        round(avg(taux_mortalite_std_tous_ages_100k) over (partition by code_region), 2) as moyenne_std_2014_2022,
        round(stddev_samp(taux_mortalite_std_tous_ages_100k) over (partition by code_region), 2) as ecart_type_std_2014_2022,
        round(min(taux_mortalite_std_tous_ages_100k) over (partition by code_region), 2) as min_std_2014_2022,
        round(percentile_cont(taux_mortalite_std_tous_ages_100k, 0.25) over (partition by code_region), 2) as q1_std_2014_2022,
        round(percentile_cont(taux_mortalite_std_tous_ages_100k, 0.50) over (partition by code_region), 2) as mediane_std_2014_2022,
        round(percentile_cont(taux_mortalite_std_tous_ages_100k, 0.75) over (partition by code_region), 2) as q3_std_2014_2022,
        round(max(taux_mortalite_std_tous_ages_100k) over (partition by code_region), 2) as max_std_2014_2022
    from region_annuel
    where est_periode_2014_2022

),

dist_ranked as (

    select
        *,
        round(q3_std_2014_2022 - q1_std_2014_2022, 2) as iqr_std_2014_2022,
        cast(dense_rank() over (order by mediane_std_2014_2022 desc) as int64) as rang_median_2014_2022
    from dist_2014_2022

),

-- Tests non paramétriques exacts (2014-2022) : Friedman global (k = 18 régions, n = 9 ans) + Wilcoxon signé vs France
wilcoxon_stats as (

    select *
    from unnest([
        struct('01' as code_region, 3.0 as wilcoxon_stat_vs_france, 0.019531 as wilcoxon_p_value_brute, 0.156250 as wilcoxon_p_value_holm, 'Sous-mortalité significative (p brute < 0,05)' as statut_wilcoxon_region),
        struct('02', 1.0, 0.007812, 0.093750, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('03', 1.0, 0.007812, 0.093750, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('04', 0.0, 0.003906, 0.070312, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('06', 14.0, 0.359375, 1.000000, 'Non significatif vs France'),
        struct('11', 19.0, 0.734375, 1.000000, 'Non significatif vs France'),
        struct('24', 2.0, 0.011719, 0.117188, 'Surmortalité significative (p brute < 0,05)'),
        struct('27', 14.0, 0.359375, 1.000000, 'Non significatif vs France'),
        struct('28', 0.0, 0.003906, 0.070312, 'Surmortalité significative (p brute < 0,05)'),
        struct('32', 0.0, 0.003906, 0.070312, 'Surmortalité significative (p brute < 0,05)'),
        struct('44', 11.0, 0.203125, 1.000000, 'Non significatif vs France'),
        struct('52', 21.0, 0.910156, 1.000000, 'Non significatif vs France'),
        struct('53', 6.0, 0.054688, 0.328125, 'Non significatif vs France'),
        struct('75', 0.0, 0.003906, 0.070312, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('76', 0.0, 0.003906, 0.070312, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('84', 2.0, 0.011719, 0.117188, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('93', 0.0, 0.003906, 0.070312, 'Sous-mortalité significative (p brute < 0,05)'),
        struct('94', 4.0, 0.027344, 0.191406, 'Sous-mortalité significative (p brute < 0,05)')
    ])

),

joined as (

    select
        ra.annee,
        ra.code_region,
        ra.nom_region,
        ra.est_periode_2014_2022,
        ra.nb_deces_sein_femmes,
        ra.population_femmes_insee,
        ra.taux_mortalite_brut_100k,
        ra.taux_mortalite_std_tous_ages_100k,
        ra.taux_mortalite_std_moins_65_100k,
        ra.taux_mortalite_std_50_74_100k,
        ra.taux_mortalite_std_65_84_100k,
        ra.taux_mortalite_std_75_plus_100k,
        ft.taux_mortalite_std_france_100k,
        round(ra.taux_mortalite_std_tous_ages_100k - ft.taux_mortalite_std_france_100k, 2) as ecart_std_vs_france_100k,
        cast(dense_rank() over (partition by ra.annee order by ra.taux_mortalite_std_tous_ages_100k desc) as int64) as rang_annuel_region,
        dr.moyenne_std_2014_2022,
        dr.ecart_type_std_2014_2022,
        dr.min_std_2014_2022,
        dr.q1_std_2014_2022,
        dr.mediane_std_2014_2022,
        dr.q3_std_2014_2022,
        dr.max_std_2014_2022,
        dr.iqr_std_2014_2022,
        dr.rang_median_2014_2022,
        98.33 as friedman_chi2_global,
        1.81e-13 as friedman_p_value_global,
        ws.wilcoxon_stat_vs_france,
        ws.wilcoxon_p_value_brute,
        ws.wilcoxon_p_value_holm,
        ws.statut_wilcoxon_region
    from region_annuel ra
    inner join france_tsm ft
      on ra.annee = ft.annee
    inner join dist_ranked dr
      on ra.code_region = dr.code_region
    inner join wilcoxon_stats ws
      on ra.code_region = ws.code_region

)

select
    to_hex(sha256(to_json_string(struct(
        annee, code_region
    )))) as id_mart_mortalite_std_region,
    *
from joined
