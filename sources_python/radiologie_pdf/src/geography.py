import json
from pathlib import Path
from .normalizer import key

REFERENCE = Path(__file__).resolve().parents[1] / 'data' / 'geography.json'

def load_reference():
    data = json.loads(REFERENCE.read_text(encoding='utf-8'))
    return {str(code): {**row, 'code_departement': str(row['code_departement']), 'code_region': str(row['code_region'])} for code, row in data.items()}

def identify_department(title, reference):
    label = title.split('agréés', 1)[-1].strip()
    if key(label) == 'CORSE':
        return 'Corse', '20'
    if key(label) == 'MONACO':
        return 'Monaco', 'MC'
    matches = [(r['departement'], c) for c, r in reference.items() if key(r['departement']) == key(label)]
    return matches[0] if len(matches) == 1 else (label, '')

def assign(code, postal, reference):
    code, postal = str(code or ''), str(postal or '')
    if code == 'MC' or postal.startswith('980'):
        return '', '', code, 'hors_france_monaco'
    if code == '20':
        # Corsican postcodes do not constitute an INSEE commune/departement mapping.
        # These explicit, unambiguous prefixes occur in the supplied PDF.
        if postal.startswith('200') or postal in {'20110', '20137'}:
            code = '2A'
        elif postal.startswith(('202', '206')):
            code = '2B'
        else:
            return '94', 'Corse', '', 'departement_corse_ambigu'
    if code not in reference or not reference[code]['code_region']:
        return '', '', code, 'geographie_non_identifiee'
    row = reference[code]
    inferred = postal[:3] if postal.startswith(('97','98')) else postal[:2]
    if code not in {'2A','2B'} and postal and inferred != code:
        return row['code_region'], row['region'], code, 'code_postal_departement_incoherent'
    return row['code_region'], row['region'], code, ''
