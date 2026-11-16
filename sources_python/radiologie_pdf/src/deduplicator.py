import re
from collections import defaultdict
from itertools import combinations
from rapidfuzz.fuzz import ratio
from .normalizer import key, city_key

def deduplicate(frame):
    """Merge only identical detailed site identity; fuzzy matches are review-only."""
    keep, seen, log = [], {}, []
    for idx, r in frame.iterrows():
        identity = (str(r['code_departement']), key(r['nom_centre']), key(r['adresse']), str(r['code_postal']), city_key(r['ville']))
        if all(identity) and identity in seen:
            log.append(dict(id_garde=seen[identity], id_doublon=r['record_id'], raison='identite_complete_identique'))
        else:
            seen[identity] = r['record_id']
            keep.append(idx)
    result = frame.loc[keep].copy()
    potential = []
    groups = defaultdict(list)
    for _, row in result.iterrows():
        groups[(str(row['code_departement']), city_key(row['ville']))].append(row)
    for group in groups.values():
        for left,right in combinations(group,2):
            name_score = ratio(key(left['nom_centre']), key(right['nom_centre']))
            addr_score = ratio(key(left['adresse']), key(right['adresse']))
            same_address = key(left['adresse']) == key(right['adresse'])
            # Similar name alone is not enough: a shared city can have many distinct sites.
            if (name_score >= 88 and addr_score >= 75) or (same_address and name_score >= 60):
                number_left=re.match(r'^(\d+)', str(left['adresse']))
                number_right=re.match(r'^(\d+)', str(right['adresse']))
                distinct=bool(number_left and number_right and number_left[1] != number_right[1])
                potential.append(dict(id_1=left['record_id'], id_2=right['record_id'], page_1=int(left['page_source']), page_2=int(right['page_source']),
                                      nom_1=left['nom_centre'], nom_2=right['nom_centre'], adresse_1=left['adresse'], adresse_2=right['adresse'],
                                      ville=left['ville'], score_nom=round(name_score,1), score_adresse=round(addr_score,1), decision='sites_distincts_numeros_differents' if distinct else 'non_fusionne_a_verifier'))
    return result, log, potential
