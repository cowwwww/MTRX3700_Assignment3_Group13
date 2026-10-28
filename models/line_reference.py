"""Calculate expected results for the three-row line detector using standard Python.

Input CSV columns: frame,x,y,gray. Each row records one valid pixel.
Missing, repeated or out-of-order pixels make the frame invalid.
Set the frame size, threshold and line colour on the command line.
The included examples use generated pixels. Record where real captures came from.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def features(pixels, width=32, height=16, threshold=96, dark=True):
    expected = [(x, y) for y in range(height) for x in range(width)]
    good = [(x, y) for x, y, _ in pixels] == expected
    rows = []
    for row_y in (height // 4, height // 2, 3 * (height // 4)):
        selected = [x for x, y, v in pixels if y == row_y and
                    (v < threshold if dark else v > threshold)]
        # Count separate groups of neighbouring pixels directly from the input data.
        runs = sum(i == 0 or x != selected[i-1] + 1 for i, x in enumerate(selected))
        count = len(selected)
        rows.append(dict(count=count, centroid=sum(selected)//count if count else 0,
                         valid=good and 2 <= count <= width//2 and runs == 1,
                         junction=good and (runs > 1 or count > width//2)))
    return dict(frame_good=good, rows=rows)


def replay(path, width, height, threshold, dark):
    frames = defaultdict(list)
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            frames[int(row["frame"])].append(tuple(int(row[k]) for k in ("x", "y", "gray")))
    return {str(k): features(v, width, height, threshold, dark) for k, v in frames.items()}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("csv", type=Path)
    p.add_argument("--width", type=int, default=32)
    p.add_argument("--height", type=int, default=16)
    p.add_argument("--threshold", type=int, default=96)
    p.add_argument("--bright", action="store_true")
    a = p.parse_args()
    print(json.dumps(replay(a.csv, a.width, a.height, a.threshold, not a.bright), indent=2))
