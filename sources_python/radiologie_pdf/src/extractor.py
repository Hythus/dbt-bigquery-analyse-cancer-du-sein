"""Local geometry-based PDF -> df_raw and df_clean. No networking."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import logging
from pathlib import Path
import re
import pandas as pd
import pymupdf as fitz
from .layout_analyzer import analyze_page
from .geography import load_reference, identify_department, assign
from .normalizer import text, city, key
from .deduplicator import deduplicate
from .exporter import export, CLEAN_COLUMNS

POSTAL = re.compile(r'^(\d{5})\s+(.+)$')
DOCTOR = re.compile(r'^Dr\(s\)\s*:', re.I)
ADDRESS_START = re.compile(r"^(?:\d+[\s,.-]|RUE\b|AV(?:ENUE|E)?[ .,-]|B(?:OULEVAR|L)V?D\b|BD\b|ROUTE\b|RTE\b|PLACE\b|PL[ .]|ALL[EÉ]E\b|CHEMIN\b|CH[ .]|COURS\b|QUAI\b|IMPASSE\b|IMP[ .]|BP\s?\d|CS\s?\d|RN\s?\d|RD\s?\d|ZI\b|ZA[C]?\b|ZC\b|ZONE\b|LIEU[ -]DIT\b|QUARTIER\b|ROND[ -]POINT\b|MAIL\b|MONT[EÉ]E\b|CENTRE COMMERCIAL\b|CCR\b|R[EÉ]SIDENCE\b|RES[ .]|IMMEUBLE\b|BAT(?:IMENT)?[ .-]|ENTR[EÉ]E\b|VILLA\b|POLE SANTE-\d)", re.I)
ADDRESS_IN_LINE = re.compile(r'\b\d+\s+(?:BIS\s+|TER\s+)?(?:RUE|AV(?:ENUE)?|BD|BOULEVARD|ROUTE|RTE|CHEMIN|IMPASSE|ALL[EÉ]E|PLACE)\b', re.I)
PHONE_LINE = re.compile(r'^(?:\+?\d[\d .,()/+-]{7,})$')
PRACTITIONER_NAME = re.compile(r'^(?:DR\b|DRS\b|DOCTEUR\b|DOCTEURS\b|M[.]\s|MME\b)', re.I)
RAW_COLUMNS = ['record_id','departement','code_departement','departement_rubrique','nom_centre','adresse',
               'code_postal','ville','telephone','radiologues','page_source','colonne_source','bloc_source',
               'source_pdf','date_document','statut_extraction','motifs_extraction','texte_bloc_original','bbox','mots_coordonnees']

def split_identity(lines):
    """Preserve all identity lines; return ambiguity rather than guess an uncertain split."""
    if len(lines) < 2:
        return (' '.join(lines), '', 'adresse_absente')
    if len(lines) == 2:
        return lines[0], lines[1], ''
    for i,line in enumerate(lines[1:],1):
        if ADDRESS_START.search(line) or ADDRESS_IN_LINE.search(line) or re.match(r'^(?:\d+[A-Z]\s|\d+ER\s|BVD\b|HALL\b|SITE DE\b|CHAMP DE\b|KERIO$|LES RIVIERES$|ESPACE\b|CARREFOUR\b)', line, re.I) or re.search(r'\b(?:\d+\s+IMP\b|ROND POINT\b| - AVENUE\b)', line, re.I):
            return ' '.join(lines[:i]), ' '.join(lines[i:]), ''
    # Last address line is retained, but this split must be reviewed.
    return ' '.join(lines[:-1]), lines[-1], 'separation_nom_adresse_ambigue'

def parse_block(block, page_number, department, code, stamp, source, digest):
    lines=[line['text'].strip() for line in block['lines'] if line['text'].strip()]
    reasons=[]
    postal_positions=[i for i,line in enumerate(lines) if POSTAL.fullmatch(line)]
    doctor_positions=[i for i,line in enumerate(lines) if DOCTOR.match(line)]
    if len(postal_positions)!=1:
        reasons.append('nombre_lignes_postales_' + str(len(postal_positions)))
    if len(doctor_positions)!=1:
        reasons.append('nombre_listes_radiologues_' + str(len(doctor_positions)))
    postal_index=postal_positions[0] if postal_positions else len(lines)
    doctor_index=doctor_positions[0] if doctor_positions else len(lines)
    before=lines[:postal_index]
    name,address,ambiguity=split_identity(before)
    if ambiguity:
        reasons.append(ambiguity)
    postal=POSTAL.fullmatch(lines[postal_index]) if postal_positions else None
    postcode, town=(postal.group(1),postal.group(2)) if postal else ('','')
    after_postal=lines[postal_index+1:doctor_index] if postal_positions else []
    # Town may wrap before the telephone; preserve every continuation.
    first_phone=next((i for i,line in enumerate(after_postal) if PHONE_LINE.fullmatch(line)),len(after_postal))
    if first_phone:
        town=' '.join([town]+after_postal[:first_phone])
    telephone=' | '.join(after_postal[first_phone:])
    doctors=' '.join(lines[doctor_index:]) if doctor_positions else ''
    doctors=DOCTOR.sub('',doctors).strip()
    if block['mixed_columns']:
        reasons.append('melange_geometrique_colonnes')
    if not name:
        reasons.append('nom_absent')
    if not town:
        reasons.append('ville_absente')
    if re.search(r'NE PARTICIPE PLUS|FERMETURE|NON AGREE|NON AGRÉÉ', ' '.join(before), re.I):
        reasons.append('retrait_ou_fermeture_explicitement_mentionne')
    if key(name) == key(town):
        reasons.append('nom_etablissement_non_identifiable_ville_seule')
    if PRACTITIONER_NAME.match(name):
        reasons.append('nom_praticien_individuel')
    return dict(record_id=f'p{page_number:03d}-b{block["block_id"]:03d}',
                departement=department,code_departement=code,departement_rubrique=department,
                nom_centre=name,adresse=address,code_postal=postcode,ville=town,telephone=telephone,
                radiologues=doctors,page_source=page_number,colonne_source=block['column'],bloc_source=block['block_id'],
                source_pdf=str(source),date_document=stamp,statut_extraction='ok' if not reasons else 'a_verifier',
                motifs_extraction='|'.join(reasons),texte_bloc_original=block['text'],
                bbox=json.dumps(block['bbox']),mots_coordonnees=json.dumps(block['words'],ensure_ascii=False))

def build_clean(raw, reference):
    processed=raw.copy(deep=True)
    if processed.empty:
        return pd.DataFrame({c:pd.Series(dtype='string') for c in CLEAN_COLUMNS}), processed, processed, [], []
    processed['nom_centre']=processed['nom_centre'].map(text)
    processed['adresse']=processed['adresse'].map(text)
    processed['ville']=processed['ville'].map(city)
    assigned=[assign(text(r.code_departement),text(r.code_postal),reference) for r in processed.itertuples()]
    processed['Code_region']=[a[0] for a in assigned]
    processed['Region']=[a[1] for a in assigned]
    processed['code_departement']=[a[2] for a in assigned]
    processed['motif_geographie']=[a[3] for a in assigned]
    reasons=[]
    for r in processed.itertuples():
        rr=[s for s in [text(r.motifs_extraction),text(r.motif_geographie)] if s]
        if not text(r.nom_centre): rr.append('nom_absent')
        if not text(r.ville): rr.append('ville_absente')
        if not text(r.Code_region): rr.append('region_absente')
        if PRACTITIONER_NAME.match(text(r.nom_centre)): rr.append('nom_praticien_individuel')
        reasons.append('|'.join(dict.fromkeys(rr)))
    processed['motif_controle']=reasons
    review=processed.loc[processed['motif_controle']!=''].copy()
    accepted=processed.loc[processed['motif_controle']==''].copy()
    accepted,merge_log,potential=deduplicate(accepted)
    # Keep likely duplicates out of the clean set until identity is established.
    ambiguous={p[k] for p in potential if p['decision']=='non_fusionne_a_verifier' for k in ['id_1','id_2']}
    uncertain=accepted.loc[accepted['record_id'].isin(ambiguous)].copy()
    if not uncertain.empty:
        uncertain['motif_controle']='doublon_potentiel_non_resolu'
        review=pd.concat([review,uncertain],ignore_index=True)
    accepted=accepted.loc[~accepted['record_id'].isin(ambiguous)].copy()
    accepted['Nom du centre']=accepted['nom_centre']
    accepted['Ville']=accepted['ville']
    clean=accepted[CLEAN_COLUMNS].astype('string').sort_values(['Region','Ville','Nom du centre'],kind='stable').reset_index(drop=True)
    review_reasons=dict(zip(review['record_id'],review['motif_controle']))
    processed['motif_controle']=[review_reasons.get(r.record_id,r.motif_controle) for r in processed.itertuples()]
    processed['decision']='retenu'
    processed.loc[processed['record_id'].isin(review['record_id']),'decision']='a_verifier_ou_exclu'
    processed.loc[processed['record_id'].isin([r['id_doublon'] for r in merge_log]),'decision']='doublon_exact_fusionne'
    return clean,review,processed,merge_log,potential

def extract_centers(input_pdf, output=None, debug=False):
    source=Path(input_pdf).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    output=Path(output) if output else source.parent/'output'
    output.mkdir(parents=True,exist_ok=True)
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    reference=load_reference()
    records,pages,archive=[],[],[]
    with fitz.open(source) as pdf:
        for n,page in enumerate(pdf,1):
            blocks,audit,all_blocks=analyze_page(page,n)
            department,code=identify_department(audit['titre'],reference)
            stamp=''
            if audit['date_document']:
                stamp=datetime.strptime(audit['date_document'],'%d/%m/%Y').date().isoformat()
            for block in blocks:
                row=parse_block(block,n,department,code,stamp,source,digest)
                if audit['statut']!='ok':
                    row['statut_extraction']='a_verifier'
                    row['motifs_extraction']+='|controle_page_invalide'
                records.append(row)
            audit['departement']=department
            audit['code_departement']=code
            audit['lignes_extraites']=len(blocks)
            pages.append(audit)
            archive.append(dict(page=n,width=page.rect.width,height=page.rect.height,blocks=all_blocks))
            logging.debug('Page %s: %s; %s blocs; ancres %s',n,department,len(blocks),audit['ancres_x'])
            if debug and n in {1,6,23,34,38,80,94,104,113,117}:
                folder=output/'debug'
                folder.mkdir(exist_ok=True)
                page.get_pixmap(dpi=110).save(folder/f'page_{n:03d}.png')
    raw=pd.DataFrame(records,columns=RAW_COLUMNS)
    for c in raw.columns:
        raw[c]=raw[c].astype('Int64' if c in ['page_source','colonne_source','bloc_source'] else 'string')
    raw=raw.replace({'':pd.NA})
    clean,review,processed,merge_log,potential=build_clean(raw,reference)
    identified=set(text(c) for c in processed['code_departement'] if text(c) in reference)
    absent=sorted(c for c,r in reference.items() if r['type_territoire']=='departement' and c not in identified)
    report=dict(source_pdf=str(source),sha256=digest,date_execution=datetime.now(timezone.utc).isoformat(),
                dates_document=sorted(raw['date_document'].dropna().unique().tolist()),
                pages_total=len(pages),pages_traitees=len(pages),pages_en_anomalie=[r['page_source'] for r in pages if r['statut']!='ok'],
                lignes_df_raw=len(raw),lignes_df_clean=len(clean),doublons_exacts_supprimes=len(merge_log),
                paires_ressemblantes=len(potential),
                paires_doublons_potentiels=sum(p['decision']=='non_fusionne_a_verifier' for p in potential),
                paires_sites_distincts=sum(p['decision']=='sites_distincts_numeros_differents' for p in potential),
                centres_a_verifier=len(review), motifs_controle={str(k):int(v) for k,v in review['motif_controle'].value_counts().items()},
                departements_identifies=len(identified),departements_df_clean=int(processed.loc[processed['decision']=='retenu','code_departement'].nunique()),regions_identifiees=int(clean['Code_region'].nunique()),
                lignes_exclues=len(raw)-len(clean),repartition_par_region={str(k):int(v) for k,v in clean.groupby('Region').size().items()},
                departements_absents=absent,territoires_hors_france=int((processed['motif_geographie']=='hors_france_monaco').sum()),
                conservation_mots_complete=all(r['mots_non_affectes']==0 and r['mots_affectes_plusieurs_fois']==0 for r in pages),
                blocs_geometriquement_melanges=sum(r['blocs_melanges'] for r in pages),
                portee='Presence dans les listes du PDF date; agrement actuel non verifie',
                note='Les sites dont la distinction est ambigue restent dans centres_a_verifier. La colonne finale ne permet pas de distinguer deux sites homonymes de la meme ville: les adresses restent dans df_processed.',
                referentiel='COG INSEE 2026 local, provenance dans data/geography_sources.json')
    export(output,raw,clean,review,potential,pages,report,merge_log,processed)
    (output/'texte_pages_integral.json').write_text(json.dumps(archive,ensure_ascii=False),encoding='utf-8')
    logging.info('Pages=%s, df_raw=%s, df_clean=%s, a verifier=%s',len(pages),raw.shape,clean.shape,len(review))
    return raw,clean

def main():
    parser=argparse.ArgumentParser(description='Extraction locale geometrique des centres de radiologie')
    parser.add_argument('--input',required=True)
    parser.add_argument('--output')
    parser.add_argument('--debug',action='store_true')
    args=parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,format='%(levelname)s %(message)s')
    extract_centers(args.input,args.output,args.debug)

if __name__=='__main__':
    main()
