# 반론자 재집계(읽기 전용 · 2026-10-04) — 원장·로그·산출물 기술통계만. 판정 아님(진단).
import json,csv,os,collections,statistics as st
R='C:/Users/99922/OneDrive/Quant_Module_Moltbot/'
d=json.load(open(R+'06_Registry/reinforce_ledger_l1.json',encoding='utf-8'))
def f(x):
  try: return float(x)
  except: return None
VER={'consumed','consumed_absence','possible'}
C=[]
for e in d['entries']:
  for a in e['attempts']:
    mr=a.get('measurement_regime'); reg=mr.get('regime') if isinstance(mr,dict) else mr
    if str(reg).startswith('close_t1'): C.append((e,a))
print('[1] close_t1 cells',len(C),collections.Counter(a.get('grade') for e,a in C))
th=dict(port_t=2.95,net_sharpe=0.8,cagr=0.16,calmar=0.64,oos_retention=0.7)
per=collections.Counter(); hist=collections.Counter(); noOOS=0
for e,a in C:
  es=a.get('essence') or {}
  ok={k:(f(es.get(k)) is not None and f(es.get(k))>=v) for k,v in th.items()}
  ok['dsr']=f(es.get('dsr')) is not None and f(es.get('dsr'))>=0.5
  for k,v in ok.items(): per[k]+=v
  hist[sum(ok[k] for k in th)]+=1
  noOOS+= ok['port_t'] and ok['net_sharpe'] and ok['cagr'] and ok['calmar'] and ok['dsr']
print('[2] per-condition',dict(per),'hist5',sorted(hist.items()),'A_if_OOS_dropped(가정·제안아님)',noOOS)
held=lambda a: any(isinstance(x,dict) and x.get('verdict') in VER for x in (a.get('vintage_flags') or []))
U=[(e,a) for e,a in C if not held(a)]
print('[3] unheld',len(U),collections.Counter(a.get('grade') for e,a in U),'maxPT',max(f(a['essence'].get('port_t')) for e,a in U),'maxCalmar',max(f(a['essence'].get('calmar')) for e,a in U),'DSR>=.5',sum((f(a['essence'].get('dsr')) or 0)>=.5 for e,a in U))
blk=collections.defaultdict(list)
for e,a in C:
  m=f((a.get('essence') or {}).get('mdd'))
  if m is not None: blk[(a['essence'].get('block') or '?')].append(m)
print('[4] MDD median by block',{k:round(st.median(v),3) for k,v in sorted(blk.items())})
ep=collections.Counter(); bdd=[]
for e,a in C:
  rows=list(csv.DictReader(open(os.path.join(a['artifacts'],'09_drawdowns.csv'),encoding='utf-8')))
  r0=min(rows,key=lambda r: float(r['drawdown_depth'])); y=int(r0['trough_date'][:4])
  ep['2008-09' if y in(2008,2009) else '2018-20' if 2018<=y<=2020 else '2024-26' if y>=2024 else 'other']+=1
  bdd.append(float(r0['benchmark_drawdown_depth']))
print('[5] MDD trough episode',ep.most_common(),'K200 dd over cell MDD window median',round(st.median(bdd),3))
nav=[float(r['benchmark_nav']) for r in csv.DictReader(open(R+'stage_artifacts/replication/20260925_225912_38420/05_benchmark_returns.csv',encoding='utf-8'))]
pk=nav[0];mdd=0
for x in nav: pk=max(pk,x); mdd=max(mdd,1-x/pk)
cg=nav[-1]**(252/len(nav))-1
print('[6] K200 2005-04..2026-09 MDD %.3f CAGR %.3f Calmar %.3f'%(mdd,cg,cg/mdd))
pkB=collections.Counter(); 
for e,a in C:
  if a.get('grade')=='B': pkB[str(e.get('paper_key'))[:60]]+=1
print('[7] B by paper_key',pkB.most_common(5))
fv=collections.Counter()
for line in open(R+'.cache/reinforce_auto_log.jsonl',encoding='utf-8'):
  try: j=json.loads(line)
  except: continue
  if j.get('event')=='fidelity_audit_verdict': fv[j.get('verdict')]+=1
print('[8] fidelity_audit_verdict',dict(fv))
