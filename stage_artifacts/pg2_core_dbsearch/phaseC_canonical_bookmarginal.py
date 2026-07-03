"""
PG2 core DB-wide search — Phase C: canonical PORT_t + book-marginal for top survivors.

For each selected integrated-core variant:
  1. canonical_screen_bt (R contract, NW lag-3) full + recent PORT_t  [authoritative screen]
  2. book-marginal: apply incumbent noLayer4 overlay cash-gate to (integrated - base) active delta,
     compute book IR delta vs incumbent 1.416.  active-basis (§6). Same method as 7f battery.
"""
import pandas as pd, numpy as np, json, os, sys, warnings, subprocess, shutil, glob
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"; PANEL=CACHE+"/discovery/explore_panel.parquet"
RECENT_LO="2021-01"; TOP_N=25
BOOK=ROOT+"/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
INCUMBENT_IR=1.416

reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
panel=pd.read_parquet(PANEL)

# ---- selected variants (distinct mechanisms; from phaseB survivors) ----
VARIANTS=[
    ("M17_Low_52w",0.5),("M17_Low_52w",1.0),
    ("M05_Trended_Mom",1.0),
    ("D09_Dimson_Beta",0.5),("D09_Dimson_Beta",0.25),
    ("D04_Downside_Beta",1.0),
    ("D23_Info_Ratio",1.0),
    ("R15_Sortino",1.0),
]
dirn={f:(-1.0 if reg.get(f,{}).get("direction")=="lower_better" else 1.0) for f,_ in VARIANTS}

def zcs(col):
    d=panel[["ym"]].copy(); d["v"]=col
    return d.groupby("ym")["v"].transform(lambda s:(s-s.mean())/(s.std()+1e-9)).values
core_z=zcs(panel["score_eff"].values)

# ---------- proxy active series (for book-marginal overlay) ----------
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas()
bc=[c for c in ("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum()); bmidx=list(bmlr.index)
def bm_fwd1(t):
    if t not in bmidx: return np.nan
    i=bmidx.index(t); return np.expm1(bmlr.iloc[i+1:i+2].sum()) if i+2<=len(bmidx) else np.nan
months=sorted(panel["ym"].unique()); OOS=months[60:]
ymarr=panel["ym"].values; tk=panel["Ticker"].values; F1=panel["F1"].values
bmv={t:bm_fwd1(t) for t in OOS}
def active_series(sig,lo=None,hi=None):
    out={}; prev=set()
    for t in OOS:
        if lo and t<lo: continue
        if hi and t>hi: continue
        te=np.where(ymarr==t)[0]
        if len(te)<TOP_N: continue
        s=sig[te]; ok=~np.isnan(s)
        if ok.sum()<TOP_N: continue
        idx=te[ok][np.argpartition(-s[ok],min(TOP_N,ok.sum()-1))[:TOP_N]]; sel=set(tk[idx])
        gross=np.nanmean(F1[idx]); to=2*(TOP_N-len(sel&prev))/TOP_N if prev else 1.0
        b=bmv.get(t,np.nan)
        if not np.isnan(gross) and not np.isnan(b): out[t]=(gross-to*0.0015)-b
        prev=sel
    return out
base_act=pd.Series(active_series(core_z))

# ---------- incumbent overlay cash-gate (realized_ym offset -1 vs bm date) ----------
pr=pd.read_csv(BOOK+"/03_period_returns.csv")
pr["ym"]=(pd.to_datetime(pr["date"])-pd.offsets.MonthBegin(1)).dt.strftime("%Y-%m")  # realized_ym = date month -1 (memory)
gate=pr.set_index("ym")["cash_weight"].to_dict()  # cash fraction; invested = 1-cash
def book_ir_from_delta(delta_series):
    """apply overlay invested-fraction gate to alpha active delta -> book-level IR delta.
    book_active_delta_t = (1-cash_t) * alpha_active_delta_t (regime scaler on active exposure)."""
    d=delta_series.dropna()
    gd=np.array([(1.0-gate.get(t,0.0))*v for t,v in d.items()])
    gd=gd[~np.isnan(gd)]
    if len(gd)<12 or gd.std()==0: return np.nan
    return gd.mean()/gd.std()*np.sqrt(12)

# ---------- R canonical bridge ----------
def _rscript():
    for c in [shutil.which("Rscript"),"C:/Program Files/R/R-4.5.2/bin/Rscript.exe"]:
        if c and os.path.exists(c): return c
    hits=glob.glob("C:/Program Files/R/R-*/bin/Rscript.exe")
    if hits: return hits[0]
    raise RuntimeError("Rscript not found")
def canonical(sig,lo=None,hi=None):
    """monthly-marking canonical_screen_bt, NW lag-3. returns port_t, IR, net_sr, n."""
    d=panel[["ym","Ticker","F1"]].copy(); d["sig"]=sig
    sub=d.dropna(subset=["sig","F1"]).copy()
    sub=sub[sub["ym"].isin(OOS)]
    if lo: sub=sub[sub["ym"]>=lo]
    if hi: sub=sub[sub["ym"]<=hi]
    if sub["ym"].nunique()<6: return None
    def ym2d(y): return y+"-01"
    scores=sub[["ym","Ticker","sig"]].rename(columns={"sig":"score"}); scores["Date"]=scores["ym"].map(ym2d); scores=scores[["Date","Ticker","score"]]
    rets=sub[["ym","Ticker","F1"]].rename(columns={"F1":"Ret_1m"}); rets["Date"]=rets["ym"].map(ym2d); rets=rets[["Date","Ticker","Ret_1m"]]
    byms=sorted(sub["ym"].unique()); bench=pd.DataFrame({"ym":byms}); bench["BM_Ret"]=[bm_fwd1(t) for t in byms]
    bench=bench.dropna(subset=["BM_Ret"]); bench["Date"]=bench["ym"].map(ym2d); bench=bench[["Date","BM_Ret"]]
    sd=OUT+"/_canon_scratch"; os.makedirs(sd,exist_ok=True)
    scores.to_parquet(sd+"/cs_scores.parquet",index=False); rets.to_parquet(sd+"/cs_returns.parquet",index=False); bench.to_parquet(sd+"/cs_bench.parquet",index=False)
    wrapper=(ROOT+"/02_Infrastructure/discovery/run_canonical_screen.R").replace("\\","/")
    env={**os.environ,"QM_ROOT":ROOT,"CS_SCRATCH":sd.replace("\\","/"),"CS_TOPN":str(TOP_N),"CS_PPY":"12"}
    try: subprocess.run([_rscript(),"-e",f"source('{wrapper}')"],env=env,check=True,capture_output=True,text=True,timeout=300)
    except Exception as e: print("  [canon] R fail",str(e)[:150]); return None
    rf=sd+"/cs_result.json"
    if not os.path.exists(rf): return None
    r=json.load(open(rf,encoding="utf-8"))
    if r.get("error"): print("  [canon]",r["error"][:120]); return None
    return {"port_t":r.get("portfolio_alpha_t_nw_lag3"),"IR":r.get("information_ratio"),
            "net_sr":r.get("net_sr"),"n":r.get("n_months"),"turnover":r.get("turnover_annual")}

# ---------- base canonical ----------
print("=== BASE core (score_eff) canonical ===")
b_full=canonical(core_z); b_rec=canonical(core_z,lo=RECENT_LO)
print(f"  full: port_t={b_full['port_t'] if b_full else None} IR={round(b_full['IR'],3) if b_full else None} | recent: port_t={b_rec['port_t'] if b_rec else None}")

rows=[]
for f,w in VARIANTS:
    fz=zcs(panel[f].values)*dirn[f]
    sig=np.nan_to_num(core_z,nan=0.0)+w*np.nan_to_num(fz,nan=0.0)
    cf=canonical(sig); cr=canonical(sig,lo=RECENT_LO)
    # book-marginal: overlay gate on (integrated - base) proxy active delta
    var_act=pd.Series(active_series(sig))
    common=base_act.index.intersection(var_act.index)
    delta=var_act[common]-base_act[common]
    book_var_ir=book_ir_from_delta(var_act[common])
    book_base_ir=book_ir_from_delta(base_act[common])
    dbook=(book_var_ir-book_base_ir) if (not np.isnan(book_var_ir) and not np.isnan(book_base_ir)) else np.nan
    row={"factor":f,"w":w,
         "canon_full_port_t":cf["port_t"] if cf else None,"canon_full_IR":round(cf["IR"],3) if cf else None,
         "canon_recent_port_t":cr["port_t"] if cr else None,
         "d_full_port_t":round((cf["port_t"]-b_full["port_t"]),2) if (cf and b_full) else None,
         "d_recent_port_t":round((cr["port_t"]-b_rec["port_t"]),2) if (cr and b_rec) else None,
         "canon_turnover":cf["turnover"] if cf else None,
         "proxy_book_var_IR":round(book_var_ir,4) if not np.isnan(book_var_ir) else None,
         "proxy_book_base_IR":round(book_base_ir,4) if not np.isnan(book_base_ir) else None,
         "proxy_book_dIR":round(dbook,4) if not np.isnan(dbook) else None}
    rows.append(row)
    print(f"  {f} w{w}: canon full t={row['canon_full_port_t']} (d {row['d_full_port_t']}) recent t={row['canon_recent_port_t']} (d {row['d_recent_port_t']}) | book_dIR={row['proxy_book_dIR']}")

res=pd.DataFrame(rows)
res.to_csv(OUT+"/phaseC_canonical_bookmarginal.csv",index=False)
out={"base_canon_full_port_t":b_full["port_t"] if b_full else None,
     "base_canon_full_IR":round(b_full["IR"],3) if b_full else None,
     "base_canon_recent_port_t":b_rec["port_t"] if b_rec else None,
     "incumbent_book_IR":INCUMBENT_IR,
     "book_marginal_threshold":0.05,
     "variants":rows}
json.dump(out,open(OUT+"/phaseC_result.json","w"),indent=2)
print("\n[done] -> phaseC_canonical_bookmarginal.csv + phaseC_result.json")
