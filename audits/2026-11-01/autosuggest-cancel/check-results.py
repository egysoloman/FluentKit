import json
from pathlib import Path
root=Path(__file__).resolve().parent
reports={}
for stage in ['before','after']:
    rows=json.loads((root/stage/'results.json').read_text())
    errors=[]
    assert len(rows)==40
    for row in rows:
        case=f"{row['rtl']}/{row['change']}/{row['command']}"
        enter=row['command']=='enter'
        cancel=row['command']=='escape' or (not enter and row['popupBefore'])
        expected='Pear' if row['change']=='external' else 'Ap' if cancel else 'Apple'
        checks={'preview':row['preview']=='Apple', 'text':row['text']==expected,'field':row['field']==expected,
            'closed':not row['popupAfter'], 'clearSkipped':not row['clearTabStop'], 'querySkipped':not row['queryTabStop']}
        if enter:
            checks.update(submitted=row['submitted']==expected,
                submittedID=row['submittedID']==('1' if row['change']=='stable' else 'nil'))
        else:
            checks['noSubmit']=row['submitted']==''
        if row['command'] in ['tab','backtab']: checks['focusAfter']=row['focusAfter']
        errors += [f'{case}: {key}' for key,ok in checks.items() if not ok]
    reports[stage]={'states':len(rows),'errors':errors,'errorCount':len(errors)}
(root/'comparison.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps({stage:{'states':v['states'],'errorCount':v['errorCount']} for stage,v in reports.items()},indent=2))
assert reports['before']['errorCount']>0
assert reports['after']['errorCount']==0
