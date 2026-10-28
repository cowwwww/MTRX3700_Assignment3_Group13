"""Validate final evidence before packaging; does not program hardware."""
from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'docs/evidence/board'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
core=json.loads((ROOT/'build/test_results.json').read_text())
board=json.loads((E/'board_checks.json').read_text())
for result in (core,board):
 assert result['status']=='PASS'
 for name,digest in result['source_sha256'].items():assert sha(ROOT/name)==digest,name
shutil.copy2(ROOT/'build/test_results.json',E/'core_regression.json')
(E/'core_logs').mkdir(exist_ok=True)
for p in (ROOT/'build').glob('*.log'):shutil.copy2(p,E/'core_logs'/p.name)
vendor=json.loads((ROOT/'vendor/COURSE_SOURCE_HASHES.json').read_text())
for name,digest in vendor.items():assert sha(ROOT/'vendor/course_hwtest'/name)==digest,name
v1=Path(r'E:\USYD\USYD_2-2\MTRX3700\ASSIGNMENT3\WORK\V1\MTRX3700_Robot_v1\MTRX3700_Robot_v1')
preserved={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').rglob('*.sv')}
for name,digest in preserved.items():assert sha(v1/name)==digest,name
qdir=ROOT/'board/quartus';outputs=qdir/'output_files'
summary=(outputs/'robot_board.sta.summary').read_text()
slacks=[float(s) for s in re.findall(r'^Slack\s*:\s*(-?[\d.]+)',summary,re.M)]
assert slacks and min(slacks)>0
fit=(outputs/'robot_board.fit.summary').read_text()
assert 'Total virtual pins : 0' in fit and 'Successful' in fit
log=(E/'quartus_compile.log').read_text(errors='replace')
assert 'Full Compilation was successful. 0 errors' in log and 'Critical Warning' not in log
qsf=(qdir/'robot_board.qsf').read_text()
assert 'VIRTUAL_PIN' not in qsf
official=(ROOT/'vendor/course_hwtest/hwtest/quartus/hwtest.qsf').read_text().splitlines()
locations=[s for s in qsf.splitlines() if s.startswith('set_location_assignment')]
assert len(locations)==133 and all(s in official for s in locations)
compiled=[ROOT/p for p in re.findall(r'SYSTEMVERILOG_FILE ../../(.+)',qsf)]
compiled += [qdir/'robot_board.qsf',qdir/'robot_board.qpf',qdir/'robot_board.sdc']
warning_codes={}
for code in re.findall(r'^Warning \((\d+)\)',log,re.M):warning_codes[code]=warning_codes.get(code,0)+1
audit={'status':'PASS','date':'2026-10-22','hardware_programmed':False,'hardware_tested':False,
 'original_v1_rtl_preserved':preserved,'official_vendor_files_verified':len(vendor),
 'physical_locations_equal_official':len(locations),'virtual_pins':0,
 'timing_summary_all_slacks_positive':True,'minimum_all_checks_ns':min(slacks),
 'sof_sha256':sha(outputs/'robot_board.sof'),'warnings_by_code':warning_codes,
 'compiled_source_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in compiled}}
(E/'release_audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in audit.items() if k not in ('original_v1_rtl_preserved','compiled_source_sha256')},indent=2))
