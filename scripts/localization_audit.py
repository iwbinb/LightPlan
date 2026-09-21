#!/usr/bin/env python3
"""Audit String Catalog completeness and known dynamic key families. No network required."""
from pathlib import Path
import json, re, sys
ROOT = Path(__file__).resolve().parents[1]
LANGS = ['en','zh-Hans','zh-Hant','ja','ko','de','fr','th','pt-PT']
p = ROOT/'ios/Shared/Localizable.xcstrings'
catalog = json.loads(p.read_text())
if '--update' in sys.argv:
    for line in (ROOT/'localization/release-additions.tsv').read_text().splitlines():
        key, *values = line.split('\t')
        assert len(values)==len(LANGS),key
        catalog['strings'][key] = {'extractionState':'manual','comment':'Product localization. Language review is tracked separately in the release checklist.','localizations':{lang:{'stringUnit':{'state':'translated','value':value}} for lang,value in zip(LANGS,values)}}
    p.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
errors=[]
for key,entry in catalog['strings'].items():
    for lang in LANGS:
        value=entry.get('localizations',{}).get(lang,{}).get('stringUnit',{}).get('value')
        if not isinstance(value,str) or not value.strip() or value==key:errors.append(f'{key}: missing {lang}')
keys=set()
for path in (ROOT/'ios').rglob('*.swift'):
    text=path.read_text()
    for match in re.finditer(r'(?:L10n\.text|KeyText)\("([a-zA-Z0-9.]+)"\)',text): keys.add(match.group(1))
    # String constants used as error/status/navigation keys, ignoring SF Symbols.
    for match in re.finditer(r'"((?:error|notice|settings|purchase|backup|plan|place|privacy|legal|help)\.[A-Za-z0-9]+)"',text):keys.add(match.group(1))
keys.update(f'{prefix}.p{i}' for prefix in ['help','privacy','legal'] for i in range(1,5))
keys.update('event.'+x for x in ['astronomicalDawn','nauticalDawn','blueMorningStart','goldenMorningStart','sunrise','goldenMorningEnd','goldenEveningStart','sunset','goldenEveningEnd','blueEveningEnd','nauticalDusk','astronomicalDusk','moonrise','moonset'])
keys.update('target.'+x for x in ['sunrise','sunset','goldenMorning','goldenEvening','blueEvening'])
for key in sorted(keys-set(catalog['strings'])):errors.append('Missing catalog key: '+key)
report={'catalogKeys':len(catalog['strings']),'languages':LANGS,'translations':len(catalog['strings'])*len(LANGS),'errors':errors,'reviewStatus':'Automated completeness only; not a claim of native-speaker review.'}
(ROOT/'tests/reports').mkdir(parents=True,exist_ok=True)
(ROOT/'tests/reports/localization.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
sys.exit(bool(errors))
