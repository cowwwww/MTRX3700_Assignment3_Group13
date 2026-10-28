"""Check that the motion replay tool accepts correct data and catches bad data."""
import csv
from compare_motion_replay import compare


def test(folder):
    folder.mkdir(parents=True,exist_ok=True)
    pixels=folder/'pixels.csv'
    results=folder/'results.csv'
    # A fixed pseudo-random texture makes the zero-shift match unique.
    values=[]
    seed=3700
    for _ in range(16*16):
        seed=(1664525*seed+1013904223)&0xffffffff
        values.append(seed>>24)
    with pixels.open('w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['frame','x','y','gray'])
        for frame in [65535,0,1]:
            for i,v in enumerate(values):writer.writerow([frame,i%16,i//16,v])
    # For identical frames the best score and shift are independently known.
    # Work out only the second score and patch contrast from direct array slices.
    patch=[values[y*16+x] for y in range(5,9) for x in range(5,9)]
    alternatives=[]
    for dy in [-1,0,1]:
        for dx in [-1,0,1]:
            if dx or dy:
                alternatives.append(sum(abs(patch[y*4+x]-values[(y+5+dy)*16+x+5+dx])
                                        for y in range(4) for x in range(4)))
    fields=['reference_id','current_id','dx','dy','best_sad','second_sad','contrast','boundary','accepted']
    rows=[[65535,0,0,0,0,min(alternatives),max(patch)-min(patch),0,1],
          [0,1,0,0,0,min(alternatives),max(patch)-min(patch),0,1]]
    def write(data):
        with results.open('w',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(fields);writer.writerows(data)
    def run(**kwargs):
        return compare(pixels,results,16,16,4,1,4,4,min_margin=1,**kwargs)
    def fails():
        try:run()
        except ValueError:return
        raise AssertionError('bad motion replay was accepted')
    write(rows);assert run()==(2,0)
    bad=[r[:] for r in rows];bad[0][2]=1;write(bad);fails()
    write([rows[0],rows[0]]);fails()
    write(rows[::-1]);fails()
    write(rows[:1]);fails();assert run(allow_skipped_pairs=True)==(1,1)
    write([]);fails()
    write(rows)
    with pixels.open('a') as stream:stream.write('1,15,15,0\n')
    fails()
    print('PASS motion replay: correct pairs, ID wrap, mismatch, duplicate, order, missing pairs and bad pixels')
