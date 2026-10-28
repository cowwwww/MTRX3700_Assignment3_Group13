"""Native Windows adapter regression and whole-board lint; no hardware access."""
import os,sys,subprocess,json,hashlib,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEPS=Path(os.environ.get('MTRX_DEPS',str(ROOT.parents[2]/'.deps')))
VR=DEPS/'verilator';ZIG=DEPS/'ziglang/zig.exe'
OUT=ROOT/'build/board_checks';OUT.mkdir(parents=True,exist_ok=True)
EVID=ROOT/'docs/evidence/board';EVID.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['VERILATOR_ROOT']=VR.as_posix()
env['ZIG_GLOBAL_CACHE_DIR']=str(OUT/'zig_global');env['ZIG_LOCAL_CACHE_DIR']=str(OUT/'zig_local')
env['TMP']=env['TEMP']=str(OUT/'tmp');(OUT/'tmp').mkdir(exist_ok=True)
start=time.monotonic()
def run(args,name):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,env=env,capture_output=True,text=True,errors='replace',timeout=240)
 (EVID/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
 if p.returncode: print((p.stdout+p.stderr)[-12000:]);raise RuntimeError(name+' failed')
 print(name+': PASS',flush=True);return p.stdout.strip()
vr=VR/'bin/verilator_bin.exe'
version=run([vr,'--version'],'simulator_version')
rtl=sorted((ROOT/'rtl').rglob('*.sv'))
board=sorted((ROOT/'board/rtl').glob('*.sv'))
vendor=[ROOT/'vendor/course_hwtest'/p for p in ['camera/rtl/video_pll.sv','camera/rtl/clock_divider.sv','camera/rtl/ov7670_config.sv','camera/rtl/i2c_master.sv','sonar/rtl/sonar_pll.sv','sonar/rtl/sonar_range.sv','ir/rtl/nec_decoder.sv']]
run([vr,'--lint-only','--timing','-Wno-fatal','--top-module','robot_board',*rtl,*board,*vendor],'board_lint')
obj=OUT/'obj';obj.mkdir(exist_ok=True)
run([vr,'--cc','--assert','--top-module','board_adapters_top','--Mdir',obj,*rtl,*board,ROOT/'board/tb/board_adapters_top.sv'],'adapter_verilate')
exe=OUT/'board_tests.exe'
run([ZIG,'c++','-std=c++17','-O1','-DVL_TIME_CONTEXT','-I'+str(obj),'-I'+str(VR/'include'),'-I'+str(VR/'include/vltstd'),*sorted(obj.glob('*.cpp')),VR/'include/verilated.cpp',VR/'include/verilated_threads.cpp',ROOT/'board/tb/test_board.cpp','-o',exe],'adapter_link')
result=run([exe],'adapter_tests')
hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl+board+vendor+list((ROOT/'board/tb').glob('*'))}
(EVID/'board_checks.json').write_text(json.dumps({'status':'PASS','simulator':version,'seconds':time.monotonic()-start,'result':result,'hardware_tested':False,'source_sha256':hashes},indent=2))
