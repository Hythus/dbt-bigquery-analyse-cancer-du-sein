# Projet dbt - Analyse Épidémiologique et Médico-Économique du Cancer du Sein

Projet dbt (**data build tool**) connecté à **Google BigQuery** (`cancer-du-sein-513216`) dédié au traitement, à la modélisation et à l'analyse des données d'oncologie, de dépistage, d'hospitalisation et de dépenses de santé en France.

---

## 1. Architecture Générale du Projet

Le projet adopte les principes de l'**Analytics Engineering** en séparant rigoureusement les couches de données :

```
[ Sources BigQuery : Data_brute, depistage, mortalite ]
                         │
                         ▼
   [ Staging Layer (Vues) : stg_projet_cancer ]
   • Standardisation, typage, déduplication, clés surrogate SHA-256
   • Persistance des descriptions de colonnes (persist_docs)
                         │
                         ▼
 [ Intermediate Layer (Tables) : int_projet_cancer ]
   • int_charge_hospitaliere_sein (Activité, DMS, composantes DAX)
   • int_depenses_regionales_sein (Prorata patientes, coût moyen)
                         │
                         ▼
   [ Marts Layer (Tables) : mart_projet_cancer ]
   • dim_regions (Dimension partagée 18 régions pour Power BI)
```

### Configuration des Datasets BigQuery

Grâce à la macro personnalisée [`macros/generate_schema_name.sql`](macros/generate_schema_name.sql), les modèles sont acheminés directement vers leurs jeux de données respectifs sans préfixe par défaut :

* **Couche Staging** : dataset `stg_projet_cancer` (matérialisation : `view`).
* **Couche Intermediate** : dataset `int_projet_cancer` (matérialisation : `table`).
* **Couche Marts** : dataset `mart_projet_cancer` (matérialisation : `table`).
* **Persistance des métadonnées (`persist_docs`)** : activée dans `dbt_project.yml` (`relation: true`, `columns: true`), ce qui injecte automatiquement les descriptions de chaque colonne directement dans le dictionnaire de données et l'interface de BigQuery.

---

## 2. Couche Staging (`models/staging/`) - 22 Modèles

La couche staging isole les tables brutes, applique un renommage métier homogène (snake_case) et garantit la qualité par typage strict et clés primaires synthétiques.

### 2.1. Principes de Transformation et de Nettoyage

1. **Normalisation géographique des régions** :
   * Harmonisation des libellés hétérogènes entre ministères et agences :
     * `'Auvergne et Rhône-Alpes'` $\rightarrow$ `'Auvergne-Rhône-Alpes'`
     * `'Bourgogne et Franche-Comté'` $\rightarrow$ `'Bourgogne-Franche-Comté'`
     * `'Nouvelle Aquitaine'` $\rightarrow$ `'Nouvelle-Aquitaine'`
     * `'Centre-Val de Loire'` / `'Centre-Val-de-Loire'` $\rightarrow$ `'Centre-Val-de-Loire'`
     * Variantes typographiques (apostrophes courbes `’` $\rightarrow$ `'`) pour `'Provence-Alpes-Côte d\'Azur'`.
   * Standardisation des codes régionaux et départementaux au format ISO/Insee à 2 caractères avec zéro initial (`lpad(..., 2, '0')`).

2. **Génération des clés surrogate (Surrogate Keys)** :
   * Chaque modèle génère une clé primaire hachée via `to_hex(sha256(to_json_string(struct(...))))`. Cette empreinte garantit l'unicité sans dépendre de clés auto-incrémentées.

3. **Déduplication défensive (`QUALIFY ROW_NUMBER()`)** :
   * Afin de parer aux doublons éventuels des tables sources brutes (ex: doublons observés sur les taux standardisés de dépistage), une fenêtre analytique `QUALIFY ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ... DESC) = 1` est appliquée systématiquement.

4. **Résolution des valeurs manquantes et codifications** :
   * `stg_effectifs_sein` : la modalité brute `CAN_SEI_CAT` ne disposant pas de libellé en source a été formellement complétée en `'Cancer du sein de la femme (tous statuts)'`.
   * `stg_pop_regions_age` : décodage du code sexe (`E` $\rightarrow$ `'Ensemble'`, `F` $\rightarrow$ `'Femmes'`, `H` $\rightarrow$ `'Hommes'`) tout en conservant le code original `code_sexe`.
   * Conversion booléenne explicite des drapeaux textuels (`'oui'`/`'non'` $\rightarrow$ `TRUE`/`FALSE`).

### 2.2. Répertoire des Modèles Staging

| Dataset Source | Modèle Staging | Description |
| :--- | :--- | :--- |
| `Data_brute` | `stg_charge_france` | Séjours hospitaliers par pathologie et durée au niveau national. |
| `Data_brute` | `stg_charge_region` | Séjours hospitaliers régionaux détaillés (1j à 30j+). |
| `Data_brute` | `stg_depenses_onco` | Dépenses de santé Assurance Maladie par cancer, statut et secteur. |
| `Data_brute` | `stg_depenses_patho` | Dépenses de santé détaillées par code pathologie TOP. |
| `Data_brute` | `stg_centres_radiologie` | Annuaire national des centres de mammographie et radiologie. |
| `Data_brute` | `stg_dms_france` | Durée moyenne de séjour (DMS) nationale en oncologie. |
| `Data_brute` | `stg_dms_region` | Durée moyenne de séjour (DMS) régionale par pathologie. |
| `Data_brute` | `stg_effectifs_region` | Effectifs de patients et prévalence régionale (cartographie TOP). |
| `Data_brute` | `stg_effectifs_sein` | Patientes cancer du sein par département, âge (quinquennal) et statut. |
| `Data_brute` | `stg_incidence_france` | Incidence historique nationale (taux bruts, standardisés Europe/Monde). |
| `Data_brute` | `stg_incidence_france_age`| Incidence nationale détaillée par classe d'âge. |
| `Data_brute` | `stg_incidence_region` | Incidence et mortalité estimées par région. |
| `Data_brute` | `stg_pop_cible_regions` | Population cible féminine 50-74 ans et part régionale (1975-2026). |
| `Data_brute` | `stg_pop_regions_age` | Démographie Insee détaillée par sexe, région et âge (1975-2026). |
| `depistage` | `stg_depistage_age_2021_2022` | Participation au dépistage organisé par tranche d'âge 2021-2022. |
| `depistage` | `stg_depistage_age_2022_2023` | Participation au dépistage organisé par tranche d'âge 2022-2023. |
| `depistage` | `stg_depistage_age_2024_2025` | Participation au dépistage organisé par tranche d'âge 2024-2025. |
| `depistage` | `stg_depistage_evolution_2005_2025` | Évolution chronologique annuelle du dépistage (format long unpivoted). |
| `depistage` | `stg_depistage_tranches_age_2005_2025` | Suivi biennal par tranche d'âge Insee (2005-2025). |
| `depistage` | `stg_depistage_taux_standardise_2016_2025` | Taux standardisés Insee par département et région. |
| `mortalite` | `stg_mortalite_region` | Taux standardisés de mortalité régionale par classe d'âge. |
| `mortalite` | `stg_effectif_mortalite_region` | Dénombrement annuel des décès par région, âge (10 ans) et cause. |

---

## 3. Couche Intermediate (`models/intermediate/`) - 2 Tables Métier

Les modèles intermédiaires croisent les données hospitalières, épidémiologiques et financières pour produire des indicateurs prêts pour l'analyse et la dataviz.

### 3.1. `int_charge_hospitaliere_sein` : Activité Hospitalière et DMS

Ce modèle regroupe la charge de soins, la durée de séjour et les effectifs de patientes pour le cancer du sein par région et année (période commune 2018-2024, 126 observations).

#### Choix de Modélisation et Règles de Gestion :
* **Filtrage nosologique strict** : sélection exclusive de la modalité `'Tumeur maligne du sein'` (excluant les tumeurs bénignes).
* **Découpage des séjours selon les seuils cliniques** :
  * `nb_sejours_moins_24h` : prises en charge ambulatoires ou sans nuitée.
  * `nb_sejours_inf_ou_egal_7j` : séjours courts cumulés de 1 à 7 jours inclus :
    $$\text{Séjours} \le 7\text{j} = \sum_{k=1}^{7} \text{nb\_sejours\_}k\text{j}$$
  * `nb_sejours_sup_7j` : séjours longs cumulés strictement supérieurs à 7 jours :
    $$\text{Séjours} > 7\text{j} = \text{nb\_sejours\_8j} + \text{nb\_sejours\_9j} + \text{nb\_sejours\_10\_19j} + \text{nb\_sejours\_20\_29j} + \text{nb\_sejours\_30j\_plus}$$
* **Volumétrie totale** : `nbre_hospitalisation` reprend le nombre total de séjours (`nb_sejours_total`).
* **Durée Moyenne de Séjour (`dms_jours`)** : jointure avec `stg_dms_region` et arrondi à 2 décimales (unité : jours).
* **Composantes brutes DAX pour Power BI** :
  * `nb_sejours_sein` : numérateur brut d'hospitalisations pour cancer du sein.
  * `nb_sejours_onco_total` : dénominateur brut d'hospitalisations oncologiques de la région.
  * `ratio_cancer_sein_patho_onco` : ratio précalculé à la ligne.
* **Consolidation patientes et intensité de soins** :
  * `nb_patientes` : effectif régional de patientes atteintes (`CAN_SEI_ACT` + `CAN_SEI_SUR`).
  * `taux_sejours_par_patiente` = $\frac{\text{nb\_sejours\_sein}}{\text{nb\_patientes}}$ (nombre moyen de séjours hospitaliers par patiente).

---

### 3.2. `int_depenses_regionales_sein` : Ventilation Proratisée des Coûts

Ce modèle reconstruit les dépenses d'Assurance Maladie pour le cancer du sein au niveau régional par grande catégorie de soins sur la période commune (2018-2024, 378 observations : 18 régions $\times$ 7 années $\times$ 3 catégories).

#### Problématique Métier :
Les données financières brutes de l'Assurance Maladie (`stg_depenses_onco`) ne sont disponibles qu'à l'**échelon national (France entière)**, tandis que la répartition épidémiologique des patientes (`stg_effectifs_region`) est renseignée par région.

#### Méthode de Ventilation Retenue :
1. **Dénominateur officiel France entière** :
   * L'effectif national de référence utilisé est le champ officiel `nb_patients_pathologie` présent dans `stg_depenses_onco` (garantissant la cohérence avec le budget global national).
2. **Ventilation granulaire par sous-pathologie (Actif vs Surveillance)** :
   * Le comportement de prise en charge différant grandement entre les phases de traitement actif et de surveillance post-traitement, le prorata est appliqué **séparément** avant agrégation :
     * **Phase active** :
       $$\text{Prorata}_{\text{Actif}} = \frac{\text{Patientes régionales } (\text{CAN\_SEI\_ACT})}{\text{Total officiel France } (\text{Actif})}$$
     * **Phase sous surveillance** :
       $$\text{Prorata}_{\text{Surveillance}} = \frac{\text{Patientes régionales } (\text{CAN\_SEI\_SUR})}{\text{Total officiel France } (\text{Surveillance})}$$
3. **Calcul du montant régionalisé (`montant_euros`)** :
   $$\text{Montant Régional (euros)} = \sum_{\text{statut}} \left( \text{Montant National}_{\text{statut, catégorie}} \times \text{Prorata}_{\text{statut}} \right)$$
4. **Agrégation par Grande Catégorie** :
   * Les postes fins sont regroupés sous les 3 catégories officielles :
     * `Hospitalisations (tous secteurs)`
     * `Soins de ville`
     * `Prestations en espèces` (indemnités journalières, etc.)
5. **Composantes brutes DAX pour Power BI** :
   * `montant_sein_euros` : numérateur brut des dépenses régionales de cancer du sein.
   * `montant_onco_total_euros` : dénominateur brut de l'ensemble des dépenses oncologiques régionales pour la même catégorie de soins.
   * `ratio_cancer_sein_patho_onco` : ratio précalculé à la ligne.
6. **Consolidation médico-économique par patiente** :
   * `nb_patientes` : effectif régionalisé total pour le cancer du sein.
   * `cout_moyen_par_patiente_euros` = $\frac{\text{montant\_euros}}{\text{nb\_patientes}}$ (dépense moyenne par patiente pour ce poste de soins).

---

## 4. Couche Marts (`models/marts/`) - Modèle en Étoile Power BI

La couche marts expose les dimensions conformes destinées à structurer le modèle relationnel dans Power BI sans créer de relations Many-to-Many.

### 4.1. `dim_regions` : Dimension Partagée des Régions

Ce modèle référence les **18 régions administratives françaises** (13 régions métropolitaines et 5 DROM) et sert d'axe d'analyse unique pour les tables de faits hospitalières et financières :

* **Clé primaire** : `code_region` (code Insee sur 2 caractères : `'01'`, `'11'`, `'84'`, etc.) et `id_region` (hachage SHA-256).
* **Attributs géographiques** :
  * `libelle_region` : nom officiel harmonisé de la région.
  * `zone_geographique` : `'Hexagone'` ou `'Outre-mer'`.
  * `est_metropole` : booléen (`TRUE`/`FALSE`) permettant de filtrer instantanément la métropole dans Power BI.
  * `code_iso_region` : code normalisé ISO 3166-2:FR (`'FR-IDF'`, `'FR-ARA'`, `'FR-PAC'`, etc.) reconnu nativement par les cartes choroplèthes et visuels Azure Maps / Shape Map dans Power BI.
  * `chef_lieu_region` : préfecture de région / chef-lieu administratif.

### 4.2. Schéma en Étoile dans Power BI

```
                    ┌─────────────────────────┐
                    │       dim_regions       │
                    │   (mart_projet_cancer)  │
                    │  code_region (PK / 1:N) │
                    └────────────┬────────────┘
                                 │
         ┌───────────────────────┴───────────────────────┐
         │                                               │
         ▼                                               ▼
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│   int_charge_hospitaliere_sein  │   │  int_depenses_regionales_sein   │
│       (int_projet_cancer)       │   │       (int_projet_cancer)       │
│  code_region (FK), annee, ...   │   │ code_region (FK), annee, type.. │
└─────────────────────────────────┘   └─────────────────────────────────┘
```
*(Note : la dimension calendrier `dim_calendrier` sera générée directement via Power Query / DAX dans Power BI).*

---

## 5. Tests de Données et Validation de Qualité

Le projet intègre **164 tests dbt** exécutés lors de chaque build :

* **Unicité (`unique`)** : vérifiée sur toutes les clés primaires et synthétiques SHA-256 (`id_region`, `code_region`, `code_iso_region`, `id_charge_hospitaliere`, `id_depense_regionale`, etc.).
* **Complétude (`not_null`)** : appliqué sur toutes les dimensions clés (années, codes région, montants, libellés).
* **Conformité des domaines (`accepted_values`)** :
  * Codes sexe : `['E', 'F', 'H']` / Libellés : `['Ensemble', 'Femmes', 'Hommes']`.
  * Zones géographiques : `['Hexagone', 'Outre-mer']`.
  * Types de zones : `['National', 'Région', 'Département']`.
  * Catégories de dépenses et tranches d'âge.

---

## 6. Guide d'Exécution

### Activer l'environnement virtuel
```powershell
# Windows PowerShell
Set-Location -Path "C:\dev\dbt-workspace\mon_projet"
& "C:\dev\dbt-workspace\.venv\Scripts\Activate.ps1"
```

### Commandes usuelles
```powershell
# Vérifier la connexion BigQuery
dbt debug

# Construire uniquement la couche staging
dbt build --select staging

# Construire uniquement les tables intermédiaires
dbt build --select intermediate

# Exécuter l'ensemble des modèles et tests du projet
dbt build
```
