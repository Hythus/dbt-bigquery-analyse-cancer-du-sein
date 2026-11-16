"""Reconstruct each text block from positioned lines and words; never flatten columns."""
from statistics import median
import re

def _lines(block):
    return [{'text': ''.join(s['text'] for s in line['spans']), 'bbox': list(line['bbox']),
             'sizes': [s['size'] for s in line['spans']]} for line in sorted(block['lines'], key=lambda l: (l['bbox'][1], l['bbox'][0]))]

def analyze_page(page, page_number):
    blocks = []
    all_words = page.get_text('words')
    dictionary = page.get_text('dict')
    for b in dictionary['blocks']:
        if b.get('type') != 0:
            continue
        lines = _lines(b)
        words = [list(w) for w in all_words if w[0] >= b['bbox'][0] - .1 and w[1] >= b['bbox'][1] - .1 and w[2] <= b['bbox'][2] + .1 and w[3] <= b['bbox'][3] + .1]
        content = '\n'.join(l['text'] for l in lines)
        blocks.append(dict(block_id=b['number'], bbox=list(b['bbox']), lines=lines, words=words, text=content))
    titles = [b for b in blocks if b['text'].startswith('Liste des radiologues')]
    dates = [b for b in blocks if re.fullmatch(r'\d{2}/\d{2}/\d{4}', b['text'].strip())]
    title = titles[0]['text'] if len(titles) == 1 else ''
    body = [b for b in blocks if b not in titles and b not in dates]
    # Detect column anchors afresh on every page; widths and starts vary.
    clusters = []
    for x in sorted(b['bbox'][0] for b in body):
        if clusters and abs(x - median(clusters[-1])) <= 8:
            clusters[-1].append(x)
        else:
            clusters.append([x])
    anchors = [median(c) for c in clusters]
    for b in body:
        c = min(range(len(anchors)), key=lambda i: abs(anchors[i] - b['bbox'][0]))
        b['column'] = c + 1
        # Word/line origin jumps reveal any block crossing columns.
        starts = [l['bbox'][0] for l in b['lines']]
        b['mixed_columns'] = any(abs(x - anchors[c]) > 25 for x in starts)
        b['word_count'] = len(b['words'])
    body.sort(key=lambda b: (b['bbox'][1], b['bbox'][0]))
    memberships = [sum(w[0] >= b['bbox'][0] - .1 and w[1] >= b['bbox'][1] - .1 and w[2] <= b['bbox'][2] + .1 and w[3] <= b['bbox'][3] + .1 for b in blocks) for w in all_words]
    words_accounted = sum(memberships)
    missing_words = sum(n == 0 for n in memberships)
    multiply_assigned = sum(n > 1 for n in memberships)
    audit = dict(page_source=page_number, titre=title, date_document=dates[0]['text'] if len(dates)==1 else '',
                 nombre_colonnes=len(anchors), ancres_x=anchors, blocs_etablissements=len(body),
                 marqueurs_radiologues=sum(b['text'].count('Dr(s):') for b in body),
                 mots_pdf=len(all_words), mots_conserves=words_accounted,
                 mots_non_affectes=missing_words, mots_affectes_plusieurs_fois=multiply_assigned,
                 blocs_melanges=sum(b['mixed_columns'] for b in body),
                 statut='ok' if title and body and missing_words==0 and multiply_assigned==0 and sum(b['text'].count('Dr(s):') for b in body)==len(body) and len(anchors)<=3 and not any(b['mixed_columns'] for b in body) else 'a_verifier')
    return body, audit, blocks
