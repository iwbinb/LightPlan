#!/usr/bin/env python3
"""Optional independent QA oracle. Swiss Ephemeris is NOT an app dependency or redistributed.
Regenerates numeric fixtures, compares the Swift baseline, and records actual errors.
"""
from pathlib import Path
import json, datetime as dt, math, random, subprocess, sys
P=Path(__file__).resolve().parents[1]
try:
 import swisseph as swe
except ImportError:
 sys.exit('Optional reference dependency swisseph is missing. Use frozen Swift tests instead; this is NOT a passed oracle run.')
exe=P/'packages/LightPlanCore/.build/debug/lightplan-cli'
if not exe.exists():
 subprocess.run(['swift','build','--package-path',str(P/'packages/LightPlanCore')],check=True)
rng=random.Random(17092026)
coordinates=[(24.4478,118.0679),(40.7128,-74.006),(51.5074,-.1278),(35.6762,139.6503),(37.5665,126.978),(52.52,13.405),(48.8566,2.3522),(13.7563,100.5018),(38.7223,-9.1393),(-23.55,-46.63),(-33.8688,151.2093),(69.6492,18.9553),(-43.95,-176.56),(27.7172,85.324),(1.87,-157.43),(89,0),(-89,0),(0,0)]
dates=['1900-06-21T12:00:00+00:00','1950-01-15T04:00:00+00:00','2000-01-01T12:00:00+00:00','2024-02-29T18:30:00+00:00','2026-03-08T07:30:00+00:00','2026-06-21T12:00:00+00:00','2026-09-17T09:30:00+00:00','2026-11-01T06:30:00+00:00','2026-12-21T12:00:00+00:00','2050-04-15T20:00:00+00:00','2100-08-11T23:00:00+00:00']
rows=[];expected=[]
for lat,lon in coordinates:
 for text in dates:
  when=dt.datetime.fromisoformat(text);ts=when.timestamp();jd=ts/86400+2440587.5
  swe.set_topo(lon,lat,0)
  for body,code in [('sun',swe.SUN),('moon',swe.MOON)]:
   eq,flags=swe.calc_ut(jd,code,swe.FLG_MOSEPH|swe.FLG_EQUATORIAL|swe.FLG_TOPOCTR)
   az,alt,apparent=swe.azalt(jd,swe.EQU2HOR,(lon,lat,0),1013.25,15,eq[:3])
   row={'body':body,'timestamp':ts,'latitude':lat,'longitude':lon}
   rows.append(row);expected.append({'azimuth':(az+180)%360,'altitude':alt})
run=subprocess.run([str(exe),'positions'],input=json.dumps(rows),text=True,capture_output=True,check=True)
actual=json.loads(run.stdout)
def separation(a,b):
 r=math.pi/180
 c=math.sin(a['altitude']*r)*math.sin(b['altitude']*r)+math.cos(a['altitude']*r)*math.cos(b['altitude']*r)*math.cos((a['azimuth']-b['azimuth'])*r)
 return math.acos(min(1,max(-1,c)))/r
fixtures=[];errors={'sun':[],'moon':[]}
for row,exp,act in zip(rows,expected,actual):
 err=separation(exp,act);errors[row['body']].append(err)
 fixtures.append({**row,'expectedAzimuth':exp['azimuth'],'expectedAltitude':exp['altitude'],'maxSeparation':0.08 if row['body']=='sun' else 0.30})
result={'date':dt.datetime.now(dt.timezone.utc).isoformat(),'oracle':f'Swiss Ephemeris {swe.version} / Moshier, topocentric, sea level, geometric altitude','provenance':'https://www.astro.com/swisseph/swephprg.htm','count':len(fixtures),'bodyResults':{},'limitations':['Sparse sampled comparisons are not a global error bound.','No weather, terrain, building obstruction, or device compass measurement is tested.','Near-zenith azimuth is ill-conditioned: angular separation is used.','Reference dependency not included in package or linked into iOS.']}
for body,errs in errors.items():
 limit=.08 if body=='sun' else .3
 result['bodyResults'][body]={'samples':len(errs),'maxAngularErrorDegrees':max(errs),'meanAngularErrorDegrees':sum(errs)/len(errs),'limitDegrees':limit,'passed':all(e<=limit for e in errs)}
for dest in ['packages/LightPlanCore/Tests/LightPlanCoreTests/Fixtures/positions.json']:
 (P/dest).write_text(json.dumps(fixtures,indent=2))
(P/'tests/reports/astronomy_oracle.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
if not all(v['passed'] for v in result['bodyResults'].values()):sys.exit(1)
