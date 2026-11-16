import json
from pathlib import Path
import pandas as pd

CLEAN_COLUMNS = ['Code_region', 'Region', 'Nom du centre', 'Ville']

def write_csv(frame, path):
    temp = path.with_suffix('.tmp')
    frame.to_csv(temp, index=False, sep=';', encoding='utf-8-sig')
    temp.replace(path)

def export(output, raw, clean, review, potential, pages, report, merge_log, processed):
    output=Path(output)
    output.mkdir(parents=True,exist_ok=True)
    assert list(clean.columns)==CLEAN_COLUMNS
    for name, frame in [('df_raw',raw),('df_clean',clean),('centres_a_verifier',review),
                         ('doublons_potentiels',pd.DataFrame(potential,columns=['id_1','id_2','page_1','page_2','nom_1','nom_2','adresse_1','adresse_2','ville','score_nom','score_adresse','decision'])),
                         ('controle_pages',pd.DataFrame(pages)),('df_processed',processed),
                         ('fusions_exactes',pd.DataFrame(merge_log,columns=['id_garde','id_doublon','raison']))]:
        write_csv(frame,output/f'{name}.csv')
    temp=output/'df_clean.tmp.xlsx'
    with pd.ExcelWriter(temp,engine='openpyxl') as writer:
        clean.to_excel(writer,index=False,sheet_name='Centres')
        ws=writer.sheets['Centres']
        ws.freeze_panes='A2'
        ws.auto_filter.ref=ws.dimensions
        for c in ws['A'][1:]:
            c.number_format='@'
        for col,width in [('A',16),('B',34),('C',80),('D',35)]:
            ws.column_dimensions[col].width=width
    temp.replace(output/'df_clean.xlsx')
    (output/'rapport_qualite.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
