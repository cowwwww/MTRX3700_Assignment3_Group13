"""Generate repeatable test pixels and expected results. These are not hardware recordings."""
import importlib.util
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("line_reference", ROOT/"models/line_reference.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def generate(output):
    rng = random.Random(3700)
    cases = []
    for case in range(36):
        dark = case % 2 == 0
        threshold = (64, 96, 128)[case % 3]
        centers = [rng.randrange(3, 29) for _ in range(3)]
        widths = [rng.choice([0, 1, 2, 3, 7, 16, 17, 32]) for _ in range(3)]
        pixels = []
        for y in range(16):
            for x in range(32):
                row = (4, 8, 12).index(y) if y in (4, 8, 12) else -1
                selected = row >= 0 and centers[row]-widths[row]//2 <= x < centers[row]+(widths[row]+1)//2
                if case >= 24 and row >= 0:
                    selected = x in (2, 3, 4, 18, 19, 20) if case % 3 else rng.random() < .3
                v = (threshold-1 if dark else threshold+1) if selected else threshold
                pixels.append((x, y, v))
        cases.append((dark, threshold, pixels, reference.features(pixels, threshold=threshold, dark=dark)))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="ascii", newline="\n") as f:
        f.write(f"{len(cases)}\n")
        for dark, threshold, pixels, result in cases:
            packed = lambda field, bits: sum(int(row[field]) << (i*bits) for i,row in enumerate(result["rows"]))
            f.write(f'{int(dark)} {threshold} {int(result["frame_good"])} {packed("valid",1)} '
                    f'{packed("junction",1)} {packed("centroid",5)} {packed("count",6)}\n')
            f.write(" ".join(str(v) for _, _, v in pixels)+"\n")
    return len(cases)


if __name__ == "__main__":
    print(f"PASS generated {generate(ROOT/'build/vision_vectors.txt')} synthetic reference cases")
