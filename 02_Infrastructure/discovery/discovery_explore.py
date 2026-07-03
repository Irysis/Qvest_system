"""
discovery_explore.py — Factor DB 활용 탐색 *단일 엔트리* (제품화; 스킬 factor-db-discovery SOT)

round1~8 ad-hoc 스크립트를 통합: 축(family × horizon × method)을 인자로 받아
  패널 → net long-only 백테 → 게이트(full/recent/sub PORT_t · turnover · szPct · placebo) → 후보 플래그.
발굴≠생산(P7): pre-C13 factor Z를 소비. 산출은 발굴 전용 — 자본은 governor 수동(admit 아님).

CLI:
  python discovery_explore.py --families earnings,value,idiovol,liquidity,momentum,quality,all \
      --horizons 1,3,6,12 --method composite [--placebo] [--top_n 25]
  python discovery_explore.py --validate C05_ESCR      # 신규 팩터 검증(score_eff 대비 증분)
API:
  from discovery_explore import explore, validate_factor
"""
import pandas as pd, numpy as np, os, json, argparse, warnings, subprocess, shutil
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT=os.environ.get("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
os.makedirs(OUT,exist_ok=True)
HORIZONS_ALL=(1,3,6,12); RECENT_LO="2021-01"

# ---------- 패널 (factors pre-C13 + score_eff + fwd_1/3/6/12 + Size). 캐시 ----------
def ensure_panel():
    p=OUT+"/explore_panel.parquet"
    if os.path.exists(p): return pd.read_parquet(p)
    base=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")  # factors+score_eff+fwd_1m
    rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Ret","Size"]).to_pandas()
    rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd=rd.dropna(subset=["Ret"]); rd["lr"]=np.log1p(rd["Ret"].clip(-0.99))
    m=rd.sort_values(["Ticker","Date"]).groupby(["Ticker","ym"]).agg(lr=("lr","sum"),Size=("Size","last")).reset_index().sort_values(["Ticker","ym"])
    def fH(s,H):
        a=s.values;o=np.full(len(a),np.nan)
        for i in range(len(a)):
            if i+H<len(a): o[i]=np.expm1(a[i+1:i+1+H].sum())
        return o
    for H in HORIZONS_ALL: m[f"F{H}"]=m.groupby("Ticker")["lr"].transform(lambda s:pd.Series(fH(s,H),index=s.index))
    panel=base.merge(m[["Ticker","ym","Size"]+[f"F{H}" for H in HORIZONS_ALL]],on=["Ticker","ym"],how="left")
    panel.to_parquet(p,index=False); return panel

# ---------- 벤치 forward + 팩터 families(registry category) + 방향 ----------
def bm_fwd_map():
    bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
    bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc]); lr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum()); idx=list(lr.index)
    def f(t,H):
        if t not in idx: return np.nan
        i=idx.index(t); return np.expm1(lr.iloc[i+1:i+1+H].sum()) if i+1+H<=len(idx) else np.nan
    return f
def load_families(fcols):
    reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
    cat={}; dirn={}
    for fid,meta in (reg.items() if isinstance(reg,dict) else []):
        if fid not in fcols: continue
        c=meta.get("category","other"); cat.setdefault(c,[]).append(fid)
        dirn[fid]=-1.0 if meta.get("direction")=="lower_better" else 1.0
    # 편의 별칭 (focused subset — round6/7 실증 정합)
    fam={**cat}
    fam["earnings"]=cat.get("consensus",[])   # 광의(consensus 전체)
    fam["earnings_rev"]=[f for f in ["C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings"] if f in fcols]  # 협의(revision, round7 t3.58)
    fam["idiovol"]=[f for f in ["D01_IdioVol","R12_Idiosyncratic_Risk","D41_Vol_of_Vol"] if f in fcols]
    fam["liquidity"]=cat.get("liquidity",[])
    fam["all"]=list(fcols)
    return fam, dirn

# ---------- 백테 (net long-only top-N, horizon H, 비중첩) + 게이트 metric ----------
def nw_t(x,lag=3):
    x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n)
# [W1 2026-07-02] dead `mdd(cumprod)` 제거 — 미사용 + answer-principles 자체합성(cumprod) 금지 정합.
#   MDD가 필요하면 canonical_screen_bt(→build_bt_result)의 contract drawdown을 쓸 것.

def backtest(panel,sigvals,H,top_n,bmf):
    d=panel.assign(sig=sigvals); ymarr=d["ym"].values; tk=d["Ticker"].values; sz=d["Size"].values
    months=sorted(d["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
    dec=[m for m in OOS if midx[m]%max(H,1)==0]; rec=[]; prev=set(); szp=[]
    for t in dec:
        te=np.where(ymarr==t)[0]
        if len(te)<top_n: continue
        s=sigvals[te]; ok=~np.isnan(s)
        if ok.sum()<top_n: continue
        idx=te[ok][np.argpartition(-s[ok],min(top_n,ok.sum()-1))[:top_n]]; sel=set(tk[idx])
        gross=np.nanmean(d[f"F{H}"].values[idx]); to=2*(top_n-len(sel&prev))/top_n if prev else 1.0
        allsz=sz[te]; szp.append(np.nanmean([(allsz<x).mean() for x in sz[idx] if not np.isnan(x)]))
        rec.append((t,gross-to*0.0015,bmf(t,H),to)); prev=sel
    r=pd.DataFrame(rec,columns=["ym","net","bm","to"]).dropna(subset=["net","bm"])
    def seg(lo,hi):
        x=r if lo is None else r[(r["ym"]>=lo)&(r["ym"]<=hi)]
        if len(x)<4: return {"IR":np.nan,"PORT_t":np.nan,"n":len(x)}
        a=x["net"].values-x["bm"].values
        return {"IR":round(a.mean()/a.std()*np.sqrt(12/H),3),"PORT_t":round(nw_t(a),2),"n":len(x)}
    full=seg(None,None);
    return {"H":H,"full":full,"recent":seg(RECENT_LO,"2026-12"),
            "p1":seg("2010-01","2015-12"),"p2":seg("2016-01","2020-12"),
            "TO":round(r["to"].mean()*12,1),"szPct":round(np.nanmean(szp),2) if szp else np.nan}

# ---------- W1: canonical 확정 (자체합성 없이 R canonical_screen_bt 경유) ----------
# backtest()의 PORT_t/net은 EW 산술평균·인라인 15bps 손계산 = metric_type "proxy"(탐색용).
# 의사결정 수치(CANDIDATE·validate)는 여기로: R contract(build_benchmark_compare, NW lag-3)
# = metric_type "canonical_screen". H개월 보유 = 월간 sticky 재선택(리밸월 top-N, 사이 유지)로
# 월간 복리·delta비용을 contract가 정확 산출(discovery non-overlap 근사보다 엄밀).
def _rscript():
    import glob as _g
    for c in [shutil.which("Rscript"), "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"]:
        if c and os.path.exists(c): return c
    hits=_g.glob("C:/Program Files/R/R-*/bin/Rscript.exe")
    if hits: return hits[0]
    raise RuntimeError("Rscript not found (PATH + /c/Program Files/R/*)")

def _ym2date(ym): return ym+"-01"   # 3 테이블 공통 Date 키(월초, canonical merge 일관성)

def canonical_confirm(panel, sigvals, H, top_n=25, lo=RECENT_LO, hi="2026-12", mode="monthly"):
    """탐색 신호를 R canonical_screen_bt로 authoritative PORT_t 재산출(자체합성 X).
    mode="monthly": 월간 리밸/마킹(H개월 sticky 유지, ppy=12). forge 북 basis.
    mode="quarterly": H개월 리밸/H개월수익 측정(비중첩, ppy=12/H). 3M 신호의 자연 cadence
        — 월간 마킹에 가두지 않고 실제 운용 방식(분기 sleeve)으로 측정.
    반환 dict(port_t, IR, turnover, net_sr, n_months, ppy, mode) 또는 None."""
    months=sorted(panel["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
    reb=[m for m in OOS if midx[m]%max(H,1)==0]
    bmf=bm_fwd_map()
    if mode=="quarterly":
        ppy=max(1,int(round(12/H)))
        d=panel[["ym","Ticker",f"F{H}"]].copy(); d["sig"]=sigvals
        sub=d[d["ym"].isin(reb)].dropna(subset=["sig"]).copy()
        if lo: sub=sub[sub["ym"]>=lo]
        if hi: sub=sub[sub["ym"]<=hi]
        if sub["ym"].nunique()<5: return None
        scores=sub[["ym","Ticker","sig"]].rename(columns={"sig":"score"}); scores["Date"]=scores["ym"].map(_ym2date); scores=scores[["Date","Ticker","score"]]
        rets=sub[["ym","Ticker",f"F{H}"]].dropna(subset=[f"F{H}"]).rename(columns={f"F{H}":"Ret_1m"}); rets["Date"]=rets["ym"].map(_ym2date); rets=rets[["Date","Ticker","Ret_1m"]]
        byms=sorted(sub["ym"].unique()); bench=pd.DataFrame({"ym":byms}); bench["BM_Ret"]=[bmf(t,H) for t in byms]
    else:
        ppy=12
        d=panel[["ym","Ticker","F1"]].copy(); d["sig"]=sigvals
        rebset=set(reb); ym2reb={}; last=None
        for m in months:
            if m in rebset: last=m
            ym2reb[m]=last
        dd=d[d["ym"].isin(OOS)].copy(); dd["reb"]=dd["ym"].map(ym2reb); dd=dd[dd["reb"].notna()]
        sig_at=d[["ym","Ticker","sig"]].rename(columns={"ym":"reb","sig":"score"})
        st=dd.merge(sig_at,on=["reb","Ticker"],how="left").dropna(subset=["score"])
        if lo: st=st[st["ym"]>=lo]
        if hi: st=st[st["ym"]<=hi]
        if st["ym"].nunique()<6: return None
        scores=st[["ym","Ticker","score"]].copy(); scores["Date"]=scores["ym"].map(_ym2date); scores=scores[["Date","Ticker","score"]]
        rets=st[["ym","Ticker","F1"]].dropna(subset=["F1"]).copy(); rets["Date"]=rets["ym"].map(_ym2date)
        rets=rets.rename(columns={"F1":"Ret_1m"})[["Date","Ticker","Ret_1m"]]
        byms=sorted(st["ym"].unique()); bench=pd.DataFrame({"ym":byms}); bench["BM_Ret"]=[bmf(t,1) for t in byms]
    bench=bench.dropna(subset=["BM_Ret"]); bench["Date"]=bench["ym"].map(_ym2date); bench=bench[["Date","BM_Ret"]]
    sd=os.path.join(OUT,"_canon_scratch"); os.makedirs(sd,exist_ok=True)
    scores.to_parquet(os.path.join(sd,"cs_scores.parquet"),index=False)
    rets.to_parquet(os.path.join(sd,"cs_returns.parquet"),index=False)
    bench.to_parquet(os.path.join(sd,"cs_bench.parquet"),index=False)
    wrapper=(ROOT+"/02_Infrastructure/discovery/run_canonical_screen.R").replace("\\","/")
    env={**os.environ,"QM_ROOT":ROOT,"CS_SCRATCH":sd.replace("\\","/"),"CS_TOPN":str(top_n),"CS_PPY":str(ppy)}
    try:
        subprocess.run([_rscript(),"-e",f"source('{wrapper}')"],env=env,check=True,
                       capture_output=True,text=True,timeout=300)
    except Exception as e:
        print("  [canonical_confirm] R 실패:",str(e)[:200]); return None
    rf=os.path.join(sd,"cs_result.json")
    if not os.path.exists(rf): return None
    try: r=json.load(open(rf,encoding="utf-8"))
    except Exception: return None
    if r.get("error"): print("  [canonical_confirm]",r["error"][:160]); return None
    return {"port_t":r.get("portfolio_alpha_t_nw_lag3"),"IR":r.get("information_ratio"),
            "turnover":r.get("turnover_annual"),"net_sr":r.get("net_sr"),
            "n_months":r.get("n_months"),"metric_type":r.get("metric_type","canonical_screen"),
            "mode":mode,"ppy":ppy}

# ---------- 신호 생성기 ----------
def sig_composite(panel,facs,dirn):
    w=np.array([dirn.get(f,1.0) for f in facs]); X=panel[facs].fillna(0.0).values; return X@w
def sig_ml(panel,facs,H,kind,retrain=12):
    from sklearn.linear_model import Ridge; from sklearn.ensemble import HistGradientBoostingRegressor as HGB
    from sklearn.preprocessing import StandardScaler
    d=panel; ym=d["ym"].values; months=sorted(set(ym)); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
    y=d.groupby("ym")[f"F{H}"].transform(lambda s:(s-s.mean())/(s.std()+1e-9)).values
    X=d[facs].fillna(0.0).values; pred=np.full(len(d),np.nan); order=np.array([midx[m] for m in ym]); mdl=None
    for i,t in enumerate(OOS):
        if i%retrain==0:
            tr=order<midx[t];
            if kind=="ridge": sc=StandardScaler().fit(X[tr]); mdl=Ridge(alpha=100).fit(sc.transform(X[tr]),y[tr]); scaler=sc
            else: mdl=HGB(max_iter=250,learning_rate=0.03,max_leaf_nodes=15,min_samples_leaf=80,l2_regularization=5,random_state=42).fit(X[tr],y[tr]); scaler=None
        te=ym==t;
        if te.sum(): pred[te]=mdl.predict(scaler.transform(X[te])) if scaler else mdl.predict(X[te])
    return pred

# ---------- 메인 explore ----------
def explore(families=("earnings","value","momentum","quality","idiovol","liquidity","all"),
            horizons=(1,3,6,12), method="composite", top_n=25, placebo=False, canonical=False, verbose=True):
    panel=ensure_panel(); fcols=[c for c in panel.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)]
    fam,dirn=load_families(fcols); bmf=bm_fwd_map(); rows=[]
    for famname in families:
        facs=fam.get(famname,[])
        if not facs: continue
        for H in horizons:
            if method=="composite": sig=sig_composite(panel,facs,dirn)
            else: sig=sig_ml(panel,facs,H,method)
            m=backtest(panel,sig,H,top_n,bmf)
            cand = (m["recent"]["PORT_t"] or -9)>=1.9 and (m["full"]["IR"] or -9)>-0.1 and (m["szPct"] or 0)>=0.5
            crow={"family":famname,"method":method,**{"H":H},
                  "full_IR":m["full"]["IR"],"recent_IR":m["recent"]["IR"],"recent_t":m["recent"]["PORT_t"],
                  "p1_IR":m["p1"]["IR"],"p2_IR":m["p2"]["IR"],"TO":m["TO"],"szPct":m["szPct"],
                  "n_recent":m["recent"]["n"],"metric_type":"proxy","canonical_recent_t":np.nan,"CANDIDATE":cand}
            if canonical and cand:   # 후보만 contract-grade 재확인 (자체합성 없는 authoritative)
                cc=canonical_confirm(panel,sig,H,top_n,lo=RECENT_LO,hi="2026-12")
                crow["canonical_recent_t"]=cc["port_t"] if cc else None
                crow["metric_type"]="proxy+canonical_screen"
            rows.append(crow)
    res=pd.DataFrame(rows)
    if placebo and len(res):
        best=res.sort_values("recent_t",ascending=False).iloc[0]
        H=int(best["H"]); pl=[]
        for _ in range(200):
            j=list(np.random.choice(fcols,2,replace=False)); m=backtest(panel,sig_composite(panel,j,dirn),H,top_n,bmf)
            if m["recent"]["PORT_t"] is not None and not np.isnan(m["recent"]["PORT_t"]): pl.append(m["recent"]["PORT_t"])
        pl=np.array(pl); pct=(pl<best["recent_t"]).mean()*100
        res.attrs["placebo"]={"family":best["family"],"H":H,"t":best["recent_t"],"pctile":round(pct,1),"pl_95":round(np.percentile(pl,95),2)}
    if verbose:
        print(res.to_string(index=False))
        print("\n※ recent_t/full_IR 등 = metric_type=proxy (EW 산술평균·인라인 15bps 근사, 탐색용).")
        if res.attrs.get("placebo"): print("placebo:",res.attrs["placebo"],"(>97.5%면 다중검정 통과)")
        c=res[res["CANDIDATE"]]; print(f"\n후보(recent PORT_t>=1.9 & full_IR>-0.1 & szPct>=0.5): {len(c)}건")
        if len(c):
            cols=["family","H","recent_IR","recent_t","full_IR","szPct"]
            if canonical: cols.append("canonical_recent_t")  # contract-grade authoritative
            print(c[cols].to_string(index=False))
            if canonical: print("  → canonical_recent_t = R canonical_screen_bt(contract, NW lag-3) authoritative. proxy와 괴리 크면 proxy 신뢰 하향.")
            else: print("  → --canonical 로 후보의 contract-grade PORT_t 재확인 권장(proxy는 의사결정 근거 아님).")
        print("\n※ 발굴 전용 — 자본 admit은 governor 수동. 후보는 verify4_overlay(book-marginal)+holdout 사전등록 필요.")
    res.to_csv(OUT+"/explore_results.csv",index=False)
    return res

def validate_factor(factor_name, horizons=(1,3,6), top_n=25, canonical=True):
    """신규 팩터: score_eff 단독 vs score_eff+factor 를 horizon별 비교(증분).
    proxy(빠른 근사) + canonical(contract-grade authoritative, 자체합성 X) 둘 다 보고."""
    panel=ensure_panel(); bmf=bm_fwd_map()
    if factor_name not in panel.columns:
        print("factor 없음(적재+backfill 후 explore_panel.parquet 재생성 필요):",factor_name); return
    print(f"=== validate {factor_name} (score_eff 대비 증분) ===")
    print("  [proxy 탐색] recent PORT_t (EW 산술평균·인라인 15bps 근사):")
    for H in horizons:
        base=backtest(panel,panel["score_eff"].values,H,top_n,bmf)
        z=(panel["score_eff"].fillna(0)+panel[factor_name].fillna(0)).values
        comb=backtest(panel,z,H,top_n,bmf)
        print(f"    H{H}: {base['recent']['PORT_t']} → {comb['recent']['PORT_t']} (Δ {round((comb['recent']['PORT_t'] or 0)-(base['recent']['PORT_t'] or 0),2)})")
    if canonical:
        print("  [canonical] contract-grade recent PORT_t (R canonical_screen_bt, NW lag-3 — 의사결정 근거):")
        for H in horizons:
            b=canonical_confirm(panel,panel["score_eff"].values,H,top_n,lo=RECENT_LO,hi="2026-12")
            z=(panel["score_eff"].fillna(0)+panel[factor_name].fillna(0)).values
            cc=canonical_confirm(panel,z,H,top_n,lo=RECENT_LO,hi="2026-12")
            if b and cc and b["port_t"] is not None and cc["port_t"] is not None:
                print(f"    H{H}: {round(b['port_t'],2)} → {round(cc['port_t'],2)} (Δ {round(cc['port_t']-b['port_t'],2)})  [n={cc['n_months']}, metric_type=canonical_screen]")
            else:
                print(f"    H{H}: canonical 산출 실패(overlap<6 또는 R 오류)")
    print("  Δ 양수 지속 + horizon 패턴이면 편입가치. 자본=forge build_bt_result(authoritative)+게이트(governor 수동).")

# ---------- W2: CANDIDATE → alpha-research seed 아티팩트 ----------
def export_discovery_seed(wt_id=None, results_csv=None, out_path=None):
    """explore_results.csv의 CANDIDATE를 alpha-research Step 0가 소비하는 discovery_seed.json으로.
    request.json 스키마 무관(별도 파일). factor_ids는 family 매핑에서. proxy+canonical 병기 + caveat."""
    rc=results_csv or (OUT+"/explore_results.csv")
    if not os.path.exists(rc): print("[export_discovery_seed] explore_results.csv 없음 — 먼저 explore 실행:",rc); return None
    res=pd.read_csv(rc)
    panel=ensure_panel(); fcols=[c for c in panel.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)]
    fam,_=load_families(fcols)
    cand=res[res["CANDIDATE"]==True] if "CANDIDATE" in res.columns else res.iloc[0:0]
    items=[]
    for _,r in cand.iterrows():
        famname=r["family"]; ids=fam.get(famname,[])
        cn=r.get("canonical_recent_t",np.nan); proxy_t=r.get("recent_t",np.nan)
        cav=f"horizon {int(r['H'])}M; recent-only(국면특정 가능, p2_IR={r.get('p2_IR')}); forward holdout 사전등록 필요"
        if pd.notna(cn):
            gap = (float(cn) < 0.6*float(proxy_t)) if pd.notna(proxy_t) and proxy_t not in (0,None) else False
            cav=(f"⚠ canonical(월간마킹) {round(float(cn),2)} ≪ proxy(분기) {proxy_t} = 분기-마킹 아티팩트 경고; " if gap else f"canonical(월간마킹) {round(float(cn),2)} vs proxy {proxy_t}; ")+cav
        items.append({"family":famname,"horizon_months":int(r["H"]),
                      "proxy_recent_port_t":(float(proxy_t) if pd.notna(proxy_t) else None),
                      "canonical_recent_port_t":(float(cn) if pd.notna(cn) else None),
                      "full_IR":(float(r["full_IR"]) if pd.notna(r.get("full_IR",np.nan)) else None),
                      "szPct":(float(r["szPct"]) if pd.notna(r.get("szPct",np.nan)) else None),
                      "turnover_annual":(float(r["TO"]) if pd.notna(r.get("TO",np.nan)) else None),
                      "factor_ids":ids,"caveat":cav})
    seed={"source":"discovery_explore","metric_note":"proxy=EW근사(탐색), canonical=contract-grade 월간마킹(의사결정근거). 자본 아님 — QEPM 풀검증(forge) 필요.",
          "candidates":items}
    if out_path is None:
        out_path=(ROOT+f"/qepm/mailbox/worktask/{wt_id}/discovery_seed.json") if wt_id else (OUT+"/discovery_seed.json")
    os.makedirs(os.path.dirname(out_path),exist_ok=True)
    json.dump(seed,open(out_path,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
    print(f"[export_discovery_seed] {len(items)}개 후보 → {out_path}")
    return out_path

# ---------- W3: 신규 온보딩 팩터를 discovery 패널에 증강 (validate 전제) ----------
def refresh_factor_in_panel(factor_id, value="Z_Score"):
    """explore_panel.parquet은 스냅샷 — 신규 온보딩 팩터 컬럼이 없다. 월별 factor_db parquet에서
    factor_id의 pre-C13 Z를 읽어 패널에 컬럼 추가(→ --validate 가능). C15 carve-out(발굴 substrate)."""
    import glob
    p=OUT+"/explore_panel.parquet"
    if not os.path.exists(p): print("[refresh_factor] explore_panel.parquet 없음 — ensure_panel 먼저"); return False
    panel=pd.read_parquet(p)
    if factor_id in panel.columns: panel=panel.drop(columns=[factor_id])  # 재병합(갱신)
    files=sorted(glob.glob(CACHE+"/factor_db/factor_db_*.parquet")); rows=[]
    for f in files:
        try: df=pq.read_table(f,columns=["Ticker","Factor_Name",value]).to_pandas()
        except Exception: continue
        df=df[df["Factor_Name"]==factor_id]
        if len(df)==0: continue
        ymtag=os.path.basename(f)[10:16]; ym=ymtag[:4]+"-"+ymtag[4:6]
        df=df[["Ticker",value]].rename(columns={value:factor_id}); df["ym"]=ym; rows.append(df)
    if not rows: print(f"[refresh_factor] {factor_id} 월별 parquet에 없음 — backfill_custom_factor 먼저"); return False
    fac=pd.concat(rows,ignore_index=True)
    panel=panel.merge(fac,on=["ym","Ticker"],how="left"); panel.to_parquet(p,index=False)
    print(f"[refresh_factor] {factor_id} 패널 병합 완료 ({fac['ym'].nunique()}개월, {len(fac)}행)"); return True

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--families",default="earnings,value,momentum,quality,idiovol,liquidity,all")
    ap.add_argument("--horizons",default="1,3,6,12"); ap.add_argument("--method",default="composite")
    ap.add_argument("--top_n",type=int,default=25); ap.add_argument("--placebo",action="store_true")
    ap.add_argument("--canonical",action="store_true",help="CANDIDATE를 R canonical_screen_bt로 contract-grade 재확인")
    ap.add_argument("--validate",default=None)
    ap.add_argument("--refresh-factor",dest="refresh_factor",default=None,
                    help="신규 온보딩 팩터를 월별 factor_db에서 읽어 explore_panel에 컬럼 증강(validate 전제)")
    ap.add_argument("--export-seed",dest="export_seed",nargs="?",const="__default__",default=None,
                    help="explore 후 CANDIDATE를 discovery_seed.json으로 export. 값 주면 해당 WT_id mailbox에 기록")
    a=ap.parse_args()
    did=False
    if a.refresh_factor: refresh_factor_in_panel(a.refresh_factor); did=True
    if a.validate: validate_factor(a.validate); did=True
    if not did:
        explore(tuple(a.families.split(",")),tuple(int(h) for h in a.horizons.split(",")),a.method,a.top_n,a.placebo,a.canonical)
    if a.export_seed is not None:
        export_discovery_seed(wt_id=None if a.export_seed=="__default__" else a.export_seed)
