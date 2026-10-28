"""Use generated data to check replay loading and error detection."""
import csv
from pathlib import Path
from compare_replay import compare


def test(root):
    root.mkdir(parents=True, exist_ok=True)
    pixels, rtl = root/"synthetic_pixels.csv", root/"synthetic_rtl_features.csv"
    with pixels.open("w", newline="", encoding="ascii") as f:
        w = csv.writer(f)
        w.writerow(["frame", "x", "y", "gray"])
        for y in range(8):
            for x in range(8):
                w.writerow([1,x,y,20 if x in (1,2) else 220])
    fields = "frame frame_good row_valid junction far_x mid_x near_x far_count mid_count near_count".split()
    values = [1,1,7,0,1,1,1,2,2,2]
    def write(rows):
        with rtl.open("w", newline="", encoding="ascii") as f:
            w = csv.writer(f);w.writerow(fields);w.writerows(rows)
    write([values])
    assert compare(pixels, rtl,8,8,96,True)==1
    for wrong in ([values[:-1]+[3]], [values, values], []):
        write(wrong)
        try:
            compare(pixels,rtl,8,8,96,True)
        except ValueError:
            pass
        else:
            raise AssertionError("replay comparator accepted corrupt/missing/duplicate features")
    write([values])
    print("PASS replay comparator: positive, mismatch, duplicate and missing frame")


if __name__ == "__main__":
    test(Path(__file__).resolve().parents[1]/"build/replay_selftest")
