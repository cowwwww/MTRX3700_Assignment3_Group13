"""Check recorded image shifts against a separate Python SAD calculation.

Pixels CSV: frame,x,y,gray. Record every valid pixel of each complete frame.
Results CSV: reference_id,current_id,dx,dy,best_sad,second_sad,contrast,boundary,accepted.
Use signed decimal dx/dy. Sample accepted one camera clock after result_valid;
all other result fields stay stable until the next result. Frame IDs must match
camera_motion's SOF counter. Split long recordings before a frame ID repeats.
Use the same patch position and match limits as the RTL parameters.
This checks image shifts only. It does not convert them to robot travel.
"""
import argparse
import csv
from pathlib import Path


def expected(previous, current, width, n, radius, roi_x, roi_y,
             max_mean_error=20, min_margin=512, min_contrast=32):
    reference = [previous[(roi_y+radius+y)*width+roi_x+radius+x]
                 for y in range(n) for x in range(n)]
    scores = []
    for dy in range(-radius, radius+1):
        for dx in range(-radius, radius+1):
            score = sum(abs(reference[y*n+x] -
                            current[(roi_y+radius+y+dy)*width+roi_x+radius+x+dx])
                        for y in range(n) for x in range(n))
            scores.append((score, dx, dy))
    # A stable sort keeps the RTL's first-match order when scores are equal.
    scores.sort(key=lambda item: item[0])
    best, dx, dy = scores[0]
    second = scores[1][0]
    contrast = max(reference)-min(reference)
    boundary = abs(dx)==radius or abs(dy)==radius
    accepted = (best<=n*n*max_mean_error and second-best>=min_margin and
                contrast>=min_contrast and not boundary)
    return dict(dx=dx, dy=dy, best_sad=best, second_sad=second,
                contrast=contrast, boundary=int(boundary), accepted=int(accepted))


def compare(pixels, results, width=320, height=240, n=16, radius=4,
            roi_x=None, roi_y=None, max_mean_error=20, min_margin=512,
            min_contrast=32, allow_skipped_pairs=False):
    size=n+2*radius
    roi_x=(width-size)//2 if roi_x is None else roi_x
    roi_y=3*height//4-size//2 if roi_y is None else roi_y
    if (n<2 or radius<1 or roi_x<0 or roi_y<0 or
            roi_x+size>width or roi_y+size>height):
        raise ValueError("patch does not fit inside the frame")
    frames={}
    last=None
    with open(pixels, newline="", encoding="utf-8") as stream:
        for raw in csv.DictReader(stream):
            frame,x,y,gray=(int(raw[k]) for k in ("frame","x","y","gray"))
            if not 0<=frame<=65535 or not 0<=gray<=255:
                raise ValueError("frame ID or gray value out of range")
            if frame!=last:
                if frame in frames:
                    raise ValueError("repeated or interleaved frame ID")
                frames[frame]=[]
                last=frame
            index=len(frames[frame])
            if index>=width*height or (x,y)!=(index%width,index//width):
                raise ValueError(f"frame {frame}: pixels missing, repeated or out of order")
            frames[frame].append(gray)
    if len(frames)<2 or any(len(f)!=width*height for f in frames.values()):
        raise ValueError("need at least two complete frames")
    ids=list(frames)
    pairs=list(zip(ids,ids[1:]))
    if any(b!=((a+1)&65535) for a,b in pairs):
        raise ValueError("capture frame IDs are not consecutive; record a continuous section")
    seen=set()
    last_pair_index=-1
    with open(results, newline="", encoding="utf-8") as stream:
        for raw in csv.DictReader(stream):
            row={k:int(v) for k,v in raw.items()}
            pair=(row['reference_id'],row['current_id'])
            if pair not in pairs or pair in seen:
                raise ValueError("unexpected or repeated result pair")
            index=pairs.index(pair)
            if index<=last_pair_index:
                raise ValueError("result pairs out of order")
            last_pair_index=index
            seen.add(pair)
            ref=expected(frames[pair[0]],frames[pair[1]],width,n,radius,roi_x,roi_y,
                         max_mean_error,min_margin,min_contrast)
            for field,value in ref.items():
                if row[field]!=value:
                    raise ValueError(f"pair {pair}, {field}: RTL={row[field]}, expected={value}")
    if not seen:
        raise ValueError("no results to compare")
    skipped=len(pairs)-len(seen)
    if skipped and not allow_skipped_pairs:
        raise ValueError(f"{skipped} frame pairs have no result")
    return len(seen),skipped


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pixels',type=Path,required=True)
    parser.add_argument('--results',type=Path,required=True)
    for name,default in [('width',320),('height',240),('n',16),('radius',4),
                         ('roi-x',None),('roi-y',None),('max-mean-error',20),
                         ('min-margin',512),('min-contrast',32)]:
        parser.add_argument('--'+name,type=int,default=default)
    parser.add_argument('--allow-skipped-pairs',action='store_true',
                        help='compare available pairs and report missing ones explicitly')
    args=parser.parse_args()
    try:
        checked,skipped=compare(**vars(args))
        print(f'PASS: {checked} image-shift pairs checked; {skipped} pairs skipped. No metric odometry claim.')
    except (ValueError,KeyError,OSError) as exc:
        parser.exit(1,f'FAIL: {exc}\n')
