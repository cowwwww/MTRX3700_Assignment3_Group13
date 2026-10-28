"""Compare recorded RTL results with results calculated from the input pixels.

Pixels CSV: frame,x,y,gray. RTL CSV: frame,frame_good,row_valid,junction,
far_x,mid_x,near_x,far_count,mid_count,near_count. Use decimal integers.
Reject missing, repeated or extra RTL frames. Record the data source separately.
"""
import argparse
import csv
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("reference", ROOT/"models/line_reference.py")
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


def compare(pixels, rtl, width, height, threshold, dark):
    expected = model.replay(pixels, width, height, threshold, dark)
    seen = set()
    with open(rtl, newline="", encoding="utf-8") as f:
        for raw in csv.DictReader(f):
            row = {key:int(value) for key,value in raw.items()}
            key = str(row["frame"])
            if key in seen or key not in expected:
                raise ValueError(f"duplicate or unexpected RTL frame {key}")
            seen.add(key)
            ref = expected[key]
            fields = dict(frame_good=int(ref["frame_good"]),
                          row_valid=sum(int(v["valid"])<<i for i,v in enumerate(ref["rows"])),
                          junction=sum(int(v["junction"])<<i for i,v in enumerate(ref["rows"])))
            for label, result in zip(("far", "mid", "near"), ref["rows"]):
                fields[label+"_x"] = result["centroid"]
                fields[label+"_count"] = result["count"]
            for field, value in fields.items():
                if row[field] != value:
                    raise ValueError(f"frame {key} {field}: RTL={row[field]}, reference={value}")
    if seen != set(expected):
        raise ValueError(f"missing RTL frames: {sorted(set(expected)-seen)}")
    if not seen:
        raise ValueError("empty replay is not evidence")
    return len(seen)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--pixels", type=Path, required=True)
    p.add_argument("--rtl", type=Path, required=True)
    p.add_argument("--width", type=int, default=320)
    p.add_argument("--height", type=int, default=240)
    p.add_argument("--threshold", type=int, default=96)
    p.add_argument("--bright", action="store_true")
    a = p.parse_args()
    try:
        n = compare(a.pixels, a.rtl, a.width, a.height, a.threshold, not a.bright)
        print(f"PASS {n} replay frames; provenance must be supplied separately")
    except (ValueError, KeyError, OSError) as e:
        p.exit(1, f"FAIL {e}\n")
