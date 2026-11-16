import re
import unicodedata
import pandas as pd

def text(value):
    if value is None or value is pd.NA:
        return ''
    s = unicodedata.normalize('NFKC', str(value))
    s = s.translate(str.maketrans({'\u2019': "'", '\u02bc': "'", '\u2018': "'", '\u00ad': '', '\u200b': '', '\ufffd': ''}))
    return re.sub(r'\s+', ' ', s).strip()

def key(value):
    return re.sub(r'[^A-Z0-9]', '', unicodedata.normalize('NFKD', text(value)).encode('ascii', 'ignore').decode().upper())

def city(value):
    s = text(value).upper()
    s = re.sub(r'\s+CEDEX(?:\s+\d+)?$', '', s)
    s = re.sub(r'(?<!\w)ST(?=[ -])', 'SAINT', s)
    s = re.sub(r'(?<!\w)STE(?=[ -])', 'SAINTE', s)
    return re.sub(r'\s*[-\u2013\u2014]\s*', '-', s)

def city_key(value):
    return key(city(value))
