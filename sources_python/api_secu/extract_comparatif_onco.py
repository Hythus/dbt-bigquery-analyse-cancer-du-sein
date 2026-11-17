"""Extraction Open Data CépiDc (mortalité tumeurs 2014-2024) & Ameli (effectifs cancers par âge/région 2015-2024)
et chargement dans BigQuery (`cancer-du-sein-513216.Data_brute`).
"""

import os
from pathlib import Path

import pandas as pd
import requests
from google.cloud import bigquery

PROJECT_ID = "cancer-du-sein-513216"
DATASET_ID = "Data_brute"
OUT_DIR = Path(__file__).resolve().parent
DEFAULT_CREDS = Path(r"C:\Users\Deval\Documents\data bird\Projet\cancer-du-sein-513216-f2aa37ec2318.json")

if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ and DEFAULT_CREDS.exists():
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(DEFAULT_CREDS)


def fetch_cepidc_mortalite_tumeurs() -> pd.DataFrame:
    """Interroge l'API Open Data CépiDc pour les chapitres '2. Tumeurs' et '2.1 Tumeurs malignes' (2014-2024)."""
    base = "https://opendata-cepidc.inserm.fr/bcmd/r/"
    geos_resp = requests.get(f"{base}codes_geo", params={"scale": "regdom_nouv"}, timeout=30)
    geos_resp.raise_for_status()
    geos_json = geos_resp.json()
    geo_map = {v["label"].strip(): str(v["code"]).strip().zfill(2) for v in geos_json.values()}

    rows = []
    for yr in range(2014, 2025):
        resp = requests.get(
            f"{base}mortalityQuery",
            params={
                "measures": "raw_number_of_death",
                "standpop": "None",
                "from": yr,
                "to": yr,
                "year_info": "true",
                "sex[]": ["1", "2", "12"],
                "code[]": ["2.", "2.1"],
                "age_info": "true",
                "age_class": "10_years_age_group",
                "age_filter": "false",
                "agregration_1_24": "true",
                "geo_class": "regdom_nouv",
                "lang": "fr-FR",
            },
            timeout=60,
        )
        resp.raise_for_status()
        data = resp.json()
        if not isinstance(data, list):
            raise RuntimeError(f"Réponse CépiDc inattendue pour {yr}: {data}")
        rows.extend(data)

    df_raw = pd.DataFrame(rows)
    df = pd.DataFrame(
        {
            "annee_de_deces": pd.to_numeric(df_raw["adc"], errors="raise").astype("int64"),
            "region_de_domicile": df_raw["regdom_nouv"].astype(str).str.strip().map(geo_map),
            "regdom_libelle": df_raw["regdom_nouv"].astype(str).str.strip(),
            "classe_d_age_de_10_ans": df_raw["cl_age10"].astype(str).str.strip(),
            "sexe": df_raw["sexe"].astype(str).str.strip(),
            "cause_initiale_de_deces": df_raw["cause_of_death"].astype(str).str.strip(),
            "indicateur": "Effectifs de décès",
            "valeur": pd.to_numeric(df_raw["sum_dc"], errors="coerce").astype("Int64"),
        }
    )
    if df["region_de_domicile"].isna().any():
        missing = df.loc[df["region_de_domicile"].isna(), "regdom_libelle"].unique().tolist()
        raise ValueError(f"Régions CépiDc non mappées: {missing}")
    return df


def fetch_ameli_effectifs_cancers() -> pd.DataFrame:
    """Interroge l'API d'export Ameli (`effectifs`) pour tous les cancers au niveau régional et par âge quinquennal."""
    url = "https://data.ameli.fr/api/explore/v2.1/catalog/datasets/effectifs/exports/json"
    where = 'patho_niv1 = "Cancers" AND dept = "999" AND region != "99"'
    resp = requests.get(url, params={"where": where}, timeout=120)
    resp.raise_for_status()
    records = resp.json()
    if not isinstance(records, list) or not records:
        raise RuntimeError(f"Réponse Ameli vide ou inattendue ({len(records) if isinstance(records, list) else type(records)})")

    df_raw = pd.DataFrame(records)
    df = pd.DataFrame(
        {
            "annee": df_raw["annee"].astype(str).str.slice(0, 4).astype("int64"),
            "code_region": df_raw["region"].astype(str).str.strip().str.zfill(2),
            "top": df_raw["top"].astype(str).str.strip(),
            "patho_niv2": df_raw["patho_niv2"].astype("string").str.strip(),
            "patho_niv3": df_raw["patho_niv3"].astype("string").str.strip(),
            "cla_age_5": df_raw["cla_age_5"].astype(str).str.strip(),
            "libelle_classe_age": df_raw["libelle_classe_age"].astype(str).str.strip(),
            "sexe": df_raw["sexe"].astype(str).str.strip(),
            "libelle_sexe": df_raw["libelle_sexe"].astype(str).str.strip(),
            "ntop": pd.to_numeric(df_raw["ntop"], errors="coerce").astype("Int64"),
            "npop": pd.to_numeric(df_raw["npop"], errors="coerce").astype("Int64"),
            "prev": pd.to_numeric(df_raw["prev"], errors="coerce").astype("float64"),
        }
    )
    return df


def load_to_bigquery(client: bigquery.Client, df: pd.DataFrame, table_name: str, schema: list[bigquery.SchemaField]) -> None:
    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    table = client.get_table(table_id)
    print(f"BigQuery chargé : {table.full_table_id} ({table.num_rows:,} lignes)")


def main() -> None:
    client = bigquery.Client(project=PROJECT_ID)

    print("1. Extraction CépiDc (mortalité tumeurs 2014-2024)...")
    df_mort = fetch_cepidc_mortalite_tumeurs()
    mort_csv = OUT_DIR / "df_mortalite_tumeurs_region.csv"
    df_mort.to_csv(mort_csv, sep=";", decimal=",", index=False, encoding="utf-8-sig")
    print(f"   CSV écrit : {mort_csv} ({len(df_mort):,} lignes)")

    schema_mort = [
        bigquery.SchemaField("annee_de_deces", "INT64"),
        bigquery.SchemaField("region_de_domicile", "STRING"),
        bigquery.SchemaField("regdom_libelle", "STRING"),
        bigquery.SchemaField("classe_d_age_de_10_ans", "STRING"),
        bigquery.SchemaField("sexe", "STRING"),
        bigquery.SchemaField("cause_initiale_de_deces", "STRING"),
        bigquery.SchemaField("indicateur", "STRING"),
        bigquery.SchemaField("valeur", "INT64"),
    ]
    load_to_bigquery(client, df_mort, "effectif_mortalite_tumeurs_region", schema_mort)

    print("2. Extraction Ameli (effectifs cancers par âge et région 2015-2024)...")
    df_ameli = fetch_ameli_effectifs_cancers()
    ameli_csv = OUT_DIR / "df_effectifs_cancers_age_region.csv"
    df_ameli.to_csv(ameli_csv, sep=";", decimal=",", index=False, encoding="utf-8-sig")
    print(f"   CSV écrit : {ameli_csv} ({len(df_ameli):,} lignes)")

    schema_ameli = [
        bigquery.SchemaField("annee", "INT64"),
        bigquery.SchemaField("code_region", "STRING"),
        bigquery.SchemaField("top", "STRING"),
        bigquery.SchemaField("patho_niv2", "STRING"),
        bigquery.SchemaField("patho_niv3", "STRING"),
        bigquery.SchemaField("cla_age_5", "STRING"),
        bigquery.SchemaField("libelle_classe_age", "STRING"),
        bigquery.SchemaField("sexe", "STRING"),
        bigquery.SchemaField("libelle_sexe", "STRING"),
        bigquery.SchemaField("ntop", "INT64"),
        bigquery.SchemaField("npop", "INT64"),
        bigquery.SchemaField("prev", "FLOAT64"),
    ]
    load_to_bigquery(client, df_ameli, "effectifs_cancers_age_region", schema_ameli)


if __name__ == "__main__":
    main()
