"""Run with Python 3.9+ to print deterministic model measurements."""
import csv
import math
import random
import sys
from collections import defaultdict, deque
from graphlib import TopologicalSorter
from statistics import mean

POOLS = tuple(range(12))
INITIAL = 10000

def workload(size, skew):
    rng = random.Random(4813 + size)
    rows = []
    original = []
    for i in range(size):
        if i % 20 == 19:
            rows.append(('report', i, ()))
        elif i % 10 == 9:
            rows.append(original[-1])
        else:
            a, b = rng.sample(POOLS[:-1] if skew else POOLS, 2)
            if skew and rng.random() < .81:
                if rng.randrange(2):
                    a = POOLS[-1]
                else:
                    b = POOLS[-1]
            row = ('move', i, (a, b))
            original.append(row)
            rows.append(row)
    return rows

def run(rows, mode, limit):
    db = defaultdict(int, {p: INITIAL for p in POOLS})
    inbox = deque(range(len(rows)))
    active, history, finished = {}, [], set()
    owners = defaultdict(set)
    rt, wt = defaultdict(int), defaultdict(int)
    clock = stamp = retries = cycles = blocking = admission = 0
    failures = defaultdict(int)
    ends = []
    reports = []
    def start(i):
        nonlocal stamp
        stamp += 1
        kind, key, pair = rows[i]
        keys = POOLS if kind == 'report' else (12 + key,) + pair
        active[i] = dict(ts=stamp, keys=keys, reads={}, index=0, wait=set(), ops=[])
    def release(i):
        for key in active[i]['reads']:
            owners[key].discard(i)
        del active[i]
    while len(ends) < len(rows):
        while inbox and len(active) < limit:
            if any(failures[j] >= 3 for j in active) or (active and failures[inbox[0]] >= 3):
                break
            start(inbox.popleft())
        admission += len(inbox)
        clock += 1
        for turn, i in enumerate(list(active)):
            t = active[i]
            kind, key, pair = rows[i]
            ts = t['ts']
            vals = t['reads']
            def abort():
                nonlocal retries
                release(i)
                failures[i] += 1
                inbox.append(i)
                retries += 1
            if t['index'] < len(t['keys']):
                k = t['keys'][t['index']]
                if mode == 'lock':
                    holders = {j for j in owners[k] if kind == 'move' or rows[j][0] == 'move'}
                    t['wait'] = holders
                    if holders:
                        blocking += 1
                        stack = list(holders)
                        seen = set()
                        while stack:
                            j = stack.pop()
                            if j == i:
                                cycles += 1
                                abort()
                                break
                            if j in active and j not in seen:
                                seen.add(j)
                                other = active[j]
                                if other['wait']:
                                    pending = other['keys'][other['index']]
                                    stack.extend(other['wait'] & owners[pending])
                        continue
                    owners[k].add(i)
                if mode == 'to' and ts < wt[k]:
                    abort()
                    continue
                rt[k] = max(rt[k], ts)
                vals[k] = db[k]
                t['ops'].append(('r', k, clock * (limit + 1) + turn, i))
                t['index'] += 1
                if kind == 'move' and k == 12 + key and vals[k]:
                    t['index'] = len(t['keys'])
                continue
            writes = {}
            if kind == 'move' and not vals[12 + key]:
                a, b = pair
                assert vals[a] >= 1
                writes = {a: vals[a]-1, b: vals[b]+1, 12+key: 1}
            if mode == 'to' and any(ts < max(rt[k], wt[k]) for k in writes):
                abort()
                continue
            if kind == 'report':
                reports.append(sum(vals.values()))
            for k, value in writes.items():
                db[k] = value
                wt[k] = ts if mode == 'to' else clock
                t['ops'].append(('w', k, clock * (limit + 1) + turn, i))
            history.extend(t['ops'])
            finished.add(i)
            ends.append(clock)
            release(i)
    graph = {i:set() for i in finished}
    readers = defaultdict(set)
    last = {}
    for op,k,when,i in sorted(history,key=lambda x:(x[2],x[3])):
        if k in last and last[k] != i:
            graph[i].add(last[k])
        if op == 'w':
            graph[i].update(readers[k]-{i})
            readers[k].clear()
            last[k] = i
        else:
            readers[k].add(i)
    from graphlib import CycleError
    try:
        tuple(TopologicalSorter(graph).static_order())
        acyclic = True
    except CycleError:
        acyclic = False
    expected = [INITIAL]*len(POOLS)
    seen = set()
    for kind,key,pair in rows:
        if kind == 'move' and key not in seen:
            seen.add(key)
            a,b = pair
            expected[a] -= 1
            expected[b] += 1
    correct = all(db[k]==expected[k] for k in POOLS) and all(db[12+k]==1 for k in seen)
    safe = correct and all(s==INITIAL*len(POOLS) for s in reports) and acyclic
    if mode != 'none':
        assert safe
    return [round(1000*len(rows)/clock,1),round(mean(ends),1),sorted(ends)[math.ceil(.95*len(ends))-1],retries,cycles,blocking,admission,int(safe)]

def crash_test(deferred):
    disk = [100,60,40]
    log = [(1,0,100,90),(1,1,60,70),('commit',1),(2,1,70,65),(2,2,40,45)]
    winners = {e[1] for e in log if e[0]=='commit'}
    updates = [e for e in log if len(e)==4]
    if not deferred:
        for tx,k,old,new in updates:
            disk[k]=new
    redo = undo = 0
    for tx,k,old,new in updates:
        if tx in winners:
            disk[k]=new
            redo+=1
    if not deferred:
        for tx,k,old,new in reversed(updates):
            if tx not in winners:
                disk[k]=old
                undo+=1
    assert disk==[90,70,40]
    return disk,redo,undo

if __name__=='__main__':
    for deferred in (True,False):
        print('Deferred' if deferred else 'Immediate',crash_test(deferred),file=sys.stderr)
    out=csv.writer(sys.stdout)
    out.writerow('n skew mode cap throughput mean p95 retries cycles blocked queued safe'.split())
    for n in (10,50,200,1000):
        for skew in (False,True):
            rows=workload(n,skew)
            for mode,cap in [('serial',1),('lock',8),('lock',2),('to',8),('none',8)]:
                out.writerow([n,int(skew),mode,cap]+run(rows,mode,cap))
