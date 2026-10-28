"""Build and run the Verilator tests.

Standard: python3 tools/run_tests.py (Verilator 5.050 and a C++ compiler on PATH).
Windows fallback: --native-root PATH --zig PATH --allow-version-mismatch.
A different simulator version does not meet the exact-version requirement.
The script does not install tools, change global settings or edit the source RTL.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from generate_vectors import generate
from test_replay import test as test_replay
from test_motion_replay import test as test_motion_replay

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
START = time.monotonic()


def run(cmd, log, env=None, timeout=180, expected_failure=False):
    remaining = 295 - (time.monotonic() - START)
    if remaining <= 0:
        raise RuntimeError("regression exceeded 295 second budget")
    p = subprocess.run([str(x) for x in cmd], cwd=ROOT, env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       errors="replace", timeout=min(timeout, remaining))
    log.write_text(p.stdout, encoding="utf-8")
    if p.returncode and not expected_failure:
        print(p.stdout[-14000:])
        raise RuntimeError(f"command failed ({p.returncode}): {cmd[0]}; {log}")
    return p


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-root", type=Path)
    parser.add_argument("--zig", type=Path)
    parser.add_argument("--allow-version-mismatch", action="store_true")
    parser.add_argument("--skip-mutation", action="store_true", help="development only; not an R6 run")
    a = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    # Remove the old result before running tests so a failed run cannot
    # leave behind a PASS result from an earlier run.
    (BUILD/"test_results.json").unlink(missing_ok=True)
    env = os.environ.copy()
    (BUILD/"tmp").mkdir(exist_ok=True)
    env["TMP"] = env["TEMP"] = str(BUILD/"tmp")
    if a.native_root:
        verilator = a.native_root / "bin/verilator_bin.exe"
        env["VERILATOR_ROOT"] = a.native_root.as_posix()
        if not a.zig:
            raise RuntimeError("native Windows mode requires --zig path to zig.exe")
        env["ZIG_GLOBAL_CACHE_DIR"] = str(BUILD / "zig_global")
        env["ZIG_LOCAL_CACHE_DIR"] = str(BUILD / "zig_local")
    else:
        verilator = shutil.which("verilator")
        if not verilator:
            raise RuntimeError("Verilator 5.050 not on PATH. See README for explicit local fallback.")
    version = run([verilator, "--version"], BUILD / "version.log", env).stdout.strip()
    compliant_version = bool(re.search(r"Verilator\s+5\.050\b", version))
    if not compliant_version and not a.allow_version_mismatch:
        raise RuntimeError(f"Required Verilator 5.050, got {version!r}. Local fallback needs explicit --allow-version-mismatch.")
    print("Simulator:", version, flush=True)
    if not compliant_version:
        print("LOCAL DEVELOPMENT RUN: does not certify R6 Verilator 5.050", flush=True)
    generate(BUILD / "vision_vectors.txt")
    test_replay(BUILD / "replay_selftest")
    test_motion_replay(BUILD / "motion_replay_selftest")
    sources = sorted((ROOT / "rtl").rglob("*.sv"))
    fixture = [ROOT / "tb/mock_motor_packet.sv", ROOT / "tb/verification_top.sv"]
    original_hash = hashlib.sha256((ROOT / "rtl/motor/motion_control.sv").read_bytes()).hexdigest()

    def compile_test(label, rtl, top="verification_top", bench="test_main.cpp", extras=None):
        obj = BUILD / label
        obj.mkdir(exist_ok=True)
        prefix = "V"+top
        testbench = ROOT/"tb"/bench
        command = [verilator, "--cc", "--assert", "--top-module", top,
                   "--Mdir", obj, "--prefix", prefix, *rtl, *(fixture if extras is None else extras)]
        if not a.native_root:
            command += ["--exe", testbench, "--build", "-j", "2", "-CFLAGS", "-std=c++17"]
        run(command, BUILD / f"{label}_compile.log", env)
        if a.native_root:
            exe = obj / "robot_tests.exe"
            run([a.zig, "c++", "-std=c++17", "-O1", "-DVL_TIME_CONTEXT",
                 "-I"+str(obj), "-I"+str(a.native_root/"include"), "-I"+str(a.native_root/"include/vltstd"),
                 *sorted(obj.glob("*.cpp")), a.native_root/"include/verilated.cpp",
                 a.native_root/"include/verilated_threads.cpp", testbench, "-o", exe],
                BUILD/f"{label}_link.log", env)
        else:
            exe = obj / prefix
        return exe

    # Check the default frame size separately from the smaller module tests.
    run([verilator, "--lint-only", "--assert", "--top-module", "robot_core", *sources], BUILD/"full_size_lint.log", env)
    run([verilator, "--lint-only", "--assert", "--top-module", "robot_camera_system", *sources], BUILD/"camera_full_size_lint.log", env)
    run([verilator, "--lint-only", "--assert", "--top-module", "camera_debug_display", *sources], BUILD/"video_full_size_lint.log", env)
    run([verilator, "--lint-only", "--assert", "--top-module", "robot_system", *sources], BUILD/"system_full_size_lint.log", env)
    positive = compile_test("positive", sources)
    result = run([positive, BUILD/"vision_vectors.txt"], BUILD/"positive.log", env)
    if "ALL TESTS PASSED" not in result.stdout:
        raise RuntimeError("positive test lacks completion marker")
    print(result.stdout, end="", flush=True)
    full_size = compile_test("full_size", sources, "robot_system", "test_full_size.cpp", [])
    motion_replay = BUILD/"motion_replay"
    motion_replay.mkdir(exist_ok=True)
    full_result = run([full_size, motion_replay], BUILD/"full_size_positive.log", env)
    if "FULL SIZE TESTS PASSED" not in full_result.stdout:
        raise RuntimeError("full-size test lacks completion marker")
    print(full_result.stdout, end="", flush=True)
    replay_result = run([sys.executable, ROOT/"tools/compare_motion_replay.py",
                         "--pixels", motion_replay/"synthetic_pixels.csv",
                         "--results", motion_replay/"synthetic_motion.csv"], BUILD/"motion_replay.log", env)
    print(replay_result.stdout, end="", flush=True)
    translation = compile_test("translation", sources, "image_translation_sad", "test_image_translation.cpp", [])
    translation_result = run([translation], BUILD/"translation_positive.log", env)
    if "IMAGE TRANSLATION TESTS PASSED" not in translation_result.stdout:
        raise RuntimeError("image translation test lacks completion marker")
    print(translation_result.stdout, end="", flush=True)
    camera_motion = compile_test("camera_motion", sources, "camera_motion", "test_camera_motion.cpp",
                                 ["-GW=96", "-GH=64", "-GN=8", "-GR=2", "-GFRAME_TIMEOUT=20000"])
    motion_run = run([camera_motion], BUILD/"camera_motion.log", env)
    if "CAMERA MOTION TESTS PASSED" not in motion_run.stdout:
        raise RuntimeError("camera motion test lacks completion marker")
    print(motion_run.stdout, end="", flush=True)
    overload = compile_test("camera_overload", sources, "camera_motion", "test_camera_motion.cpp",
                            ["-GW=96", "-GH=64", "-GN=16", "-GR=2", "-GROI_X=0", "-GROI_Y=0", "-GFRAME_TIMEOUT=30000"])
    overload_run = run([overload, "overload"], BUILD/"camera_overload.log", env)
    if "CAMERA OVERLOAD TESTS PASSED" not in overload_run.stdout:
        raise RuntimeError("camera overload test lacks completion marker")
    print(overload_run.stdout, end="", flush=True)
    motion_status = compile_test("motion_result", sources, "motion_result", "test_motion_result.cpp",
                                 ["-GTOTAL_WIDTH=8", "-GTIMEOUT_CYCLES=16"])
    status_run = run([motion_status], BUILD/"motion_result.log", env)
    if "MOTION RESULT TESTS PASSED" not in status_run.stdout:
        raise RuntimeError("motion result test lacks completion marker")
    print(status_run.stdout, end="", flush=True)
    caught = False
    if not a.skip_mutation:
        mutation = BUILD / "mutation_motion_control.sv"
        original = (ROOT/"rtl/motor/motion_control.sv").read_text(encoding="utf-8")
        needle = "left=inhibit ? 16'sd0"
        if original.count(needle) != 1:
            raise RuntimeError("mutation location changed; review injection")
        mutation.write_text(original.replace(needle, "left=inhibit ? 16'sd1"), encoding="utf-8")
        mutated_sources = [mutation if p.name == "motion_control.sv" else p for p in sources]
        negative = compile_test("negative", mutated_sources)
        fail = run([negative, BUILD/"vision_vectors.txt"], BUILD/"negative.log", env, expected_failure=True)
        caught = fail.returncode != 0 and "CHECK FAILED: motor inhibit zero" in fail.stdout
        if not caught:
            raise RuntimeError("mutation did not fail on the intended assertion")
        print("CAUGHT deliberately broken motion_control: nonzero inhibited left motor", flush=True)
    if hashlib.sha256((ROOT/"rtl/motor/motion_control.sv").read_bytes()).hexdigest() != original_hash:
        raise RuntimeError("production source changed during mutation")
    elapsed = time.monotonic() - START
    report = dict(status="PASS", seconds=round(elapsed, 3), version=version,
                  verilator_5050=compliant_version, mutation_caught=caught,
                  r6_automated_gate=compliant_version and caught and elapsed < 300,
                  hardware_tested=False, synthetic_golden_frames=36, full_size_raw_frames=7,
                  vga_scan_positions_checked=420000,
                  synthetic_translation_offsets_checked=81, streaming_translation_offsets_checked=25,
                  motion_result_checks=True,
                  source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sources+fixture+[ROOT/"tb/test_main.cpp", ROOT/"tb/test_full_size.cpp", ROOT/"tb/test_image_translation.cpp",
                                                     ROOT/"tb/test_camera_motion.cpp", ROOT/"tb/test_motion_result.cpp"]
                                 +sorted((ROOT/"tools").glob("*.py"))+sorted((ROOT/"models").glob("*.py"))
                                 +[ROOT/"run_all_tests.sh"]})
    (BUILD/"test_results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"PASS regression completed in {elapsed:.2f}s; R6 exact-version gate={report['r6_automated_gate']}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
        print(f"FAIL {e}", file=sys.stderr)
        sys.exit(1)
