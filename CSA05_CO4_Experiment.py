"""Python 3 block simulator. Run: python3 CSA05_CO4_Experiment.py
No third-party packages. Output results.csv, structure.csv, upi.csv and validation.json.
Records are (TxnID, AccountNo, Branch, TxnTime); omitted payload reserves 200 bytes.
No OS/disk timing is claimed. Each logical page access uses Disk.read/write.
"""
import bisect, csv, json, math, random, time, platform
from pathlib import Path
CAP=20; FAN=293
class Disk:
 def __init__(self): self.blocks=[]; self.r=self.w=self.splits=0
 def read(self,i): self.r+=1; return self.blocks[i]
 def write(self,i,b): self.w+=1; self.blocks[i]=b
 def alloc(self,b): self.blocks.append(b); self.w+=1; return len(self.blocks)-1
 def reset(self): self.r=self.w=0
class Heap:
 def __init__(self,rows):
  self.d=Disk()
  for i in range(0,len(rows),CAP): self.d.alloc(list(rows[i:i+CAP]))
 def eq(self,k):
  for i in range(len(self.d.blocks)):
   for r in self.d.read(i):
    if r is not None and r[0]==k:return r
 def ran(self,a,b): return [r for i in range(len(self.d.blocks)) for r in self.d.read(i) if r is not None and a<=r[0]<=b]
 def nonkey(self,f,v): return [r for i in range(len(self.d.blocks)) for r in self.d.read(i) if r is not None and r[f]==v]
 def insert(self,r):
  if self.eq(r[0]) is not None: raise ValueError('duplicate')
  if not self.d.blocks or len(self.d.blocks[-1])==CAP:self.d.alloc([r])
  else:
   i=len(self.d.blocks)-1;b=self.d.read(i);b.append(r);self.d.write(i,b)
 def delete(self,k):
  for i in range(len(self.d.blocks)):
   b=self.d.read(i)
   for j,r in enumerate(b):
    if r is not None and r[0]==k:b[j]=None;self.d.write(i,b);return True
  return False
 def stats(self):return dict(blocks=len(self.d.blocks),height=0,overflow=0,directory_bytes=0,splits=0,util=sum(sum(r is not None for r in b) for b in self.d.blocks)/(max(1,len(self.d.blocks))*CAP),index_blocks=0)
class Hash:
 def __init__(self,rows):
  self.d=Disk();self.m=max(1,math.ceil(len(rows)/(0.8*CAP)))
  for _ in range(self.m):self.d.alloc({'rows':[],'next':None})
  for r in rows:self.insert(r)
 def h(self,k):return ((k*11400714819323198485)&((1<<64)-1))%self.m
 def eq(self,k):
  i=self.h(k)
  while i is not None:
   b=self.d.read(i)
   for r in b['rows']:
    if r is not None and r[0]==k:return r
   i=b['next']
 def insert(self,r):
  i=self.h(r[0]);free=None
  while True:
   b=self.d.read(i)
   if any(x is not None and x[0]==r[0] for x in b['rows']):raise ValueError('duplicate')
   if free is None and (None in b['rows'] or len(b['rows'])<CAP):free=i
   if b['next'] is None:break
   i=b['next']
  if free is not None:
   b=self.d.read(free)
   if None in b['rows']:b['rows'][b['rows'].index(None)]=r
   else:b['rows'].append(r)
   self.d.write(free,b)
  else:
   new=self.d.alloc({'rows':[r],'next':None});b['next']=new;self.d.write(i,b)
 def ran(self,a,b):return [r for i in range(len(self.d.blocks)) for r in self.d.read(i)['rows'] if r is not None and a<=r[0]<=b]
 def nonkey(self,f,v):return [r for i in range(len(self.d.blocks)) for r in self.d.read(i)['rows'] if r is not None and r[f]==v]
 def delete(self,k):
  i=self.h(k)
  while i is not None:
   b=self.d.read(i)
   for j,r in enumerate(b['rows']):
    if r is not None and r[0]==k:b['rows'][j]=None;self.d.write(i,b);return True
   i=b['next']
  return False
 def stats(self):
  n=sum(sum(r is not None for r in b['rows']) for b in self.d.blocks)
  return dict(blocks=len(self.d.blocks),height=0,overflow=len(self.d.blocks)-self.m,directory_bytes=0,splits=0,util=n/(len(self.d.blocks)*CAP),index_blocks=0)
class Tree:
 """Clustered B+ tree; 20 records/leaf, 293 children/internal node.
 Bulk leaves at 13/20 fill. Deletion is a tombstone; periodic rebuild reclaims it.
 Routing keys retain original fence values. No uncounted lookup map or page cache.
 """
 def __init__(self,rows):
  self.d=Disk();ordered=sorted(rows);leaves=[]
  count=math.ceil(len(ordered)/13);offset=0
  for j in range(count):
   size=len(ordered)//count+(j<len(ordered)%count);chunk=ordered[offset:offset+size];offset+=size
   leaves.append(self.d.alloc({'leaf':True,'keys':[r[0] for r in chunk],'rows':list(chunk),'next':None}))
  if not leaves:leaves=[self.d.alloc({'leaf':True,'keys':[],'rows':[],'next':None})]
  for a,b in zip(leaves,leaves[1:]):p=self.d.read(a);p['next']=b;self.d.write(a,p)
  # fence keys available from the sorted input during bottom-up bulk loading
  level=[(i,self.d.blocks[i]['keys'][0] if self.d.blocks[i]['keys'] else -1) for i in leaves]
  while len(level)>1:
   new=[]
   groups=math.ceil(len(level)/FAN);offset=0
   for j in range(groups):
    size=len(level)//groups+(j<len(level)%groups);g=level[offset:offset+size];offset+=size;p=self.d.alloc({'leaf':False,'keys':[k for _,k in g[1:]],'children':[i for i,_ in g]});new.append((p,g[0][1]))
   level=new
  self.root=level[0][0]
 def locate(self,k):
  path=[];i=self.root
  while True:
   p=self.d.read(i)
   if p['leaf']:return i,p,path
   j=bisect.bisect_right(p['keys'],k);path.append((i,p,j));i=p['children'][j]
 def eq(self,k):
  _,p,_=self.locate(k);j=bisect.bisect_left(p['keys'],k)
  return p['rows'][j] if j<len(p['keys']) and p['keys'][j]==k else None
 def ran(self,a,b):
  _,p,_=self.locate(a);out=[]
  while True:
   for k,r in zip(p['keys'],p['rows']):
    if k>b:return out
    if k>=a and r is not None:out.append(r)
   if p['next'] is None:return out
   p=self.d.read(p['next'])
 def nonkey(self,f,v):
  _,p,_=self.locate(-(1<<100));out=[]
  while True:
   out.extend(r for r in p['rows'] if r is not None and r[f]==v)
   if p['next'] is None:return out
   p=self.d.read(p['next'])
 def insert(self,r):
  i,p,path=self.locate(r[0]);j=bisect.bisect_left(p['keys'],r[0])
  if j<len(p['keys']) and p['keys'][j]==r[0]:
   if p['rows'][j] is not None:raise ValueError('duplicate')
   p['rows'][j]=r;self.d.write(i,p);return
  p['keys'].insert(j,r[0]);p['rows'].insert(j,r)
  if len(p['keys'])<=CAP:self.d.write(i,p);return
  mid=len(p['keys'])//2;right={'leaf':True,'keys':p['keys'][mid:],'rows':p['rows'][mid:],'next':p['next']};sep=right['keys'][0]
  q=self.d.alloc(right);p['keys']=p['keys'][:mid];p['rows']=p['rows'][:mid];p['next']=q;self.d.write(i,p);self.d.splits+=1
  while path:
   pi,parent,j=path.pop();parent['keys'].insert(j,sep);parent['children'].insert(j+1,q)
   if len(parent['children'])<=FAN:self.d.write(pi,parent);return
   mid=len(parent['keys'])//2;sep=parent['keys'][mid]
   q=self.d.alloc({'leaf':False,'keys':parent['keys'][mid+1:],'children':parent['children'][mid+1:]})
   parent['keys']=parent['keys'][:mid];parent['children']=parent['children'][:mid+1];self.d.write(pi,parent);self.d.splits+=1;i=pi
  self.root=self.d.alloc({'leaf':False,'keys':[sep],'children':[i,q]})
 def delete(self,k):
  i,p,_=self.locate(k);j=bisect.bisect_left(p['keys'],k)
  if j==len(p['keys']) or p['keys'][j]!=k or p['rows'][j] is None:return False
  p['rows'][j]=None;self.d.write(i,p);return True
 def stats(self):
  leaves=[p for p in self.d.blocks if p['leaf']];h=1;p=self.d.blocks[self.root]
  while not p['leaf']:h+=1;p=self.d.blocks[p['children'][0]]
  n=sum(sum(r is not None for r in p['rows']) for p in leaves)
  return dict(blocks=len(self.d.blocks),height=h,overflow=0,directory_bytes=0,splits=self.d.splits,util=n/(len(leaves)*CAP),index_blocks=len(self.d.blocks)-len(leaves))
def measure(s,op,func,count):
 s.d.reset();t=time.perf_counter();func();elapsed=time.perf_counter()-t
 return dict(op=op,reads=s.d.r/count,writes=s.d.w/count,ms=1000*elapsed/count)
def validate():
 rng=random.Random(17);keys=list(range(1,301));rng.shuffle(keys)
 for C in [Heap,Hash,Tree]:
  s=C([]);oracle={}
  for k in keys:r=(k,k%7,k%3,k);s.insert(r);oracle[k]=r
  for k in range(302):assert s.eq(k)==oracle.get(k)
  for a,b in [(1,1),(0,400),(299,400),(7,46),(6,5)]:assert sorted(s.ran(a,b))==sorted(r for k,r in oracle.items() if a<=k<=b)
  assert sorted(s.nonkey(1,2))==sorted(r for r in oracle.values() if r[1]==2)
  try:s.insert((10,0,0,0));raise AssertionError('duplicate accepted')
  except ValueError:pass
  for k in keys:assert s.delete(k);oracle.pop(k);assert s.eq(k) is None
  assert s.ran(0,400)==[] and not s.delete(301)
  s.insert((10,0,0,0));assert s.eq(10)==(10,0,0,0)
 # adversarial hash collision and multi-level B+ internal splits
 s=Hash([])
 for k in range(200):s.insert((k,0,0,k))
 assert s.stats()['overflow']==9
 s=Tree([])
 for k in range(12000):s.insert((k,0,0,k))
 assert s.stats()['height']>=3 and len(s.ran(0,11999))==12000
 return {'status':'PASS','checks':'all three strategies: 300 shuffled insertions, all equality results, five ranges, non-key query, duplicate rejection, every deletion, empty/last-key/reinsert; hash collision chain; B+ internal split','python':platform.python_version(),'seed':17}
def main():
 out=Path(__file__).resolve().parent;rng=random.Random(4813);results=[];structures=[]
 validation=validate()
 for n in [1000,10000,100000,1000000]:
  rows=[(k,k%50000,k%100,k) for k in range(1,n+1)];hits=rng.sample(range(1,n+1),8);starts=[1,max(1,n//2),max(1,n-1999)]
  for C in [Heap,Hash,Tree]:
   t=time.perf_counter();s=C(rows);buildms=1000*(time.perf_counter()-t);buildr,buildw=s.d.r,s.d.w
   st=s.stats();structures.append(dict(n=n,strategy=C.__name__,build_reads=buildr,build_writes=buildw,build_ms=buildms,**st))
   def equality():
    for k in hits:assert s.eq(k)==rows[k-1]
   def ranges():
    for a in starts:assert sorted(s.ran(a,min(n,a+1999)))==rows[a-1:min(n,a+1999)]
   def nonkeys():
    for f,v in [(1,7),(2,4)]:assert sorted(s.nonkey(f,v))==[r for r in rows if r[f]==v]
   for op,fn,c in [('equality_hit',equality,8),('equality_miss',lambda:assert_none(s.eq(n+999)),1),('range_2000',ranges,3),('nonkey_scan',nonkeys,2)]:results.append(dict(n=n,strategy=C.__name__,**measure(s,op,fn,c)))
   def inserts():
    for k in range(n+1,n+21):s.insert((k,k%50000,k%100,k))
   results.append(dict(n=n,strategy=C.__name__,**measure(s,'insert',inserts,20)))
   def deletes():
    for k in hits[:4]:assert s.delete(k)
   results.append(dict(n=n,strategy=C.__name__,**measure(s,'delete',deletes,4)))
   print(n,C.__name__,st,flush=True)
 upi=[];n=1000000
 # Gateway keys are unique pseudorandom unsigned 64-bit integers (disjoint streams).
 keyset=set()
 while len(keyset)<n+200000:keyset.add(rng.getrandbits(64))
 allkeys=list(keyset);rng.shuffle(allkeys);initial=allkeys[:n];new=allkeys[n:]
 rows=[(k,i%50000,i%100,i) for i,k in enumerate(initial)]
 for C in [Hash,Tree]:
  s=C(rows);before=s.stats();splits=s.d.splits
  def insert_upi():
   for i,k in enumerate(new):s.insert((k,i%50000,i%100,n+i))
  m=measure(s,'random_insert_200000',insert_upi,len(new));after=s.stats()
  for i,k in enumerate(new[:20]):assert s.eq(k)==(k,i%50000,i%100,n+i)
  assert sorted(s.ran(min(new[:3]),max(new[:3])))==sorted(r for r in rows+[(k,i%50000,i%100,n+i) for i,k in enumerate(new)] if min(new[:3])<=r[0]<=max(new[:3]))
  upi.append(dict(strategy=C.__name__,**m,new_splits=s.d.splits-splits,blocks_before=before['blocks'],blocks_after=after['blocks'],overflow=after['overflow'],height=after['height'],util=after['util']))
 # Compact gateway hash index: 8-byte key + 8-byte record pointer = 16 bytes.
 # Data pages are appended in complete batches of 20; index checks uniqueness.
 global CAP
 CAP=255
 idx=Hash([(r[0],r[3],0,0) for r in rows]);data=Disk()
 for j in range(0,n,20):data.alloc(rows[j:j+20])
 before_blocks=len(idx.d.blocks)+len(data.blocks);idx.d.reset();data.reset()
 t=time.perf_counter();batch=[]
 for i,k in enumerate(new):
  idx.insert((k,n+i,0,0));batch.append((k,i%50000,i%100,n+i))
  if len(batch)==20:data.alloc(batch);batch=[]
 if batch:data.alloc(batch)
 elapsed=time.perf_counter()-t
 assert not batch or len(batch)<20
 upi.append(dict(strategy='HybridBatch',op='random_insert_200000',reads=(idx.d.r+data.r)/200000,writes=(idx.d.w+data.w)/200000,ms=1000*elapsed/200000,new_splits=0,blocks_before=before_blocks,blocks_after=len(idx.d.blocks)+len(data.blocks),overflow=len(idx.d.blocks)-idx.m,height=0,util=1200000/(len(data.blocks)*20)))
 for i,k in enumerate(new[:20]):assert idx.eq(k)[1]==n+i
 for r in rows[:20]:assert idx.eq(r[0])[1]==r[3]
 CAP=20
 for name,data in [('results',results),('structure',structures),('upi',upi)]:
  with open(out/(name+'.csv'),'w',newline='') as f:w=csv.DictWriter(f,fieldnames=list(data[0]));w.writeheader();w.writerows(data)
 (out/'validation.json').write_text(json.dumps(validation,indent=2));print('VALIDATION PASS',flush=True)
def assert_none(v):assert v is None
if __name__=='__main__':main()
