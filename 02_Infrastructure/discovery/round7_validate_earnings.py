# Round 7 — earnings-revision @ horizon 리드 정밀검증 (Round6: ESBR/ESCR 최근 t2.1, 대형주)
#   ① placebo(랜덤 composite t분포 대비 백분위=다중검정) ② horizon scan(1/3/6/12 — 1M死/장기生?)
#   ③ sub-window(21-23 vs 24-26 안정) ④ earnings family 확장. capital-grade 여부 판정.
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round7_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")
np.random.seed(7)
pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]; pan[fcols]=pan[fcols].fillna(0.0)
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"]); rd["lr"]=np.log1p(rd["Ret"].clip(-0.99))
mret=rd.sort_values(["Ticker","Date"]).groupby(["Ticker","ym"])["lr"].sum().reset_index().sort_values(["Ticker","ym"])
def fwdH(s,H):
    a=s.values;o=np.full(len(a),np.nan)
    for i in range(len(a)):
        if i+H<len(a): o[i]=np.expm1(a[i+1:i+1+H].sum())
    return o
for H in (1,3,6,12): mret[f"F{H}"]=mret.groupby("Ticker")["lr"].transform(lambda s:pd.Series(fwdH(s,H),index=s.index))
df=pan.merge(mret[["Ticker","ym"]+[f"F{H}" for H in(1,3,6,12)]],on=["Ticker","ym"],how="left")
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc]); bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum()); idxb=list(bmlr.index)
def bmfwdH(t,H):
    if t not in idxb: return np.nan
    i=idxb.index(t); return np.expm1(bmlr.iloc[i+1:i+1+H].sum()) if i+1+H<=len(idxb) else np.nan
months=sorted(df["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
Fmat=df[fcols].values; ymarr=df["ym"].values; tkv=df["Ticker"].values; fi={f:j for j,f in enumerate(fcols)}
def bt(widx, H, lo="2021-01", hi="2026-12"):
    w=np.zeros(len(fcols));
    for j in widx: w[j]=1.0
    dec=[m for m in OOS if midx[m]%H==0]; rec=[]; prev=set()
    for t in dec:
        te=np.where(ymarr==t)[0]
        if len(te)<25: continue
        sig=Fmat[te]@w; idx=np.argpartition(-sig,min(25,len(sig)-1))[:25]; sel=set(tkv[te][idx])
        gross=np.nanmean(df[f"F{H}"].values[te][idx]); to=2*(25-len(sel&prev))/25 if prev else 1.0
        rec.append((t,gross-to*0.0015,bmfwdH(t,H))); prev=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm"]).dropna()
    x=r[(r["ym"]>=lo)&(r["ym"]<=hi)]
    if len(x)<4: return (np.nan,np.nan,0)
    a=x["net"].values-x["bm"].values; return (a.mean()/a.std()*np.sqrt(12/H), a.mean()/a.std()*np.sqrt(len(a)), len(a))

EARN=[f for f in ["C04_ESBR","C05_ESCR"] if f in fi]
EARNB=[f for f in ["C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings"] if f in fi]
ew=[fi[f] for f in EARN]; ewb=[fi[f] for f in EARNB]
log(f"=== Round 7 earnings-revision @ horizon 검증 ===")
log(f"EARN(narrow)={EARN} | EARNB(broad)={EARNB}")

log("\n① horizon scan (earnings narrow, 최근 21-26)")
for H in (1,3,6,12):
    ir,t,n=bt(ew,H); log(f"  H{H:>2}: IR {ir:+.2f} t {t:+.2f} n{n}")
log("   (1M死/장기生 패턴이면 horizon-shift 리드 확증)")

log("\n② placebo 다중검정 (H3, 랜덤 2-factor composite 300개 vs earnings)")
e_ir,e_t,_=bt(ew,3);
pl=[]
for _ in range(300):
    j=list(np.random.choice(len(fcols),2,replace=False)); ir,t,n=bt(j,3)
    if not np.isnan(t): pl.append(t)
pl=np.array(pl); pct=(pl<e_t).mean()*100
log(f"  earnings H3 t={e_t:+.2f} | placebo t 분포 mean {pl.mean():+.2f} sd {pl.std():.2f} 95%ile {np.percentile(pl,95):+.2f} | earnings 백분위 {pct:.1f}%")
log(f"   (earnings 백분위>97.5%이면 다중검정 통과)")

log("\n③ sub-window 안정성 (earnings narrow H3)")
for lo,hi,tag in [("2021-01","2023-06","21~23.5"),("2023-07","2026-12","23.5~26")]:
    ir,t,n=bt(ew,3,lo,hi); log(f"  {tag}: IR {ir:+.2f} t {t:+.2f} n{n}")

log("\n④ earnings family 확장 (broad, 최근)")
for H in (3,6):
    ir,t,n=bt(ewb,H); log(f"  broad H{H}: IR {ir:+.2f} t {t:+.2f} n{n}")
log("\n⑤ book 비교: score_eff(1M)는 earnings 포함. 3-6M earnings가 추가가치인지 = score_eff H1 vs earnings H3/6 최근")
for nm,widx,H in [("score_eff~","",1)]:
    pass
# score_eff 자체는 가중합 아님 → 직접: score_eff 신호로 H1/H3 최근
def bt_scoreeff(H):
    dec=[m for m in OOS if midx[m]%H==0]; rec=[]; prev=set()
    sev=df["score_eff"].values
    for t in dec:
        te=np.where(ymarr==t)[0]
        if len(te)<25: continue
        sig=sev[te]; idx=np.argpartition(-sig,min(25,len(sig)-1))[:25]; sel=set(tkv[te][idx])
        gross=np.nanmean(df[f"F{H}"].values[te][idx]); to=2*(25-len(sel&prev))/25 if prev else 1.0
        rec.append((t,gross-to*0.0015,bmfwdH(t,H))); prev=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm"]).dropna(); x=r[r["ym"]>="2021-01"]
    a=x["net"].values-x["bm"].values; return a.mean()/a.std()*np.sqrt(12/H), a.mean()/a.std()*np.sqrt(len(a))
for H in (1,3,6): ir,t=bt_scoreeff(H); log(f"  score_eff H{H}: IR {ir:+.2f} t {t:+.2f}")
log("\n판정: earnings 다중검정 백분위>97.5% + horizon 1M<장기 + sub-window 둘다양수 + score_eff 대비 우위 → capital 후보. 아니면 noise/regime.")
log("=== done ===")
