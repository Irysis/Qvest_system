# Round 9 — earnings-revision @ horizon LEAD을 capital-grade로 승격 + 구성방법론 sweep
#   mandate: 한 라운드 = 여러 구성방법론 동시 실측. 살아있는 신호(earnings 3-6M)에 깊게.
#   ① 구성 sweep: family × horizon × sizing(EW/conviction) × liq-filter(2e8) — 다중방법론
#   ② book-marginal: 실제 book(ret_L5_V5) active-basis ΔIR + active 상관(=diversification 메커니즘)
#   ③ value-up 국면 decomp: earnings active vs value sleeve active 상관 + 2021-23 vs 2024-26 분해
#   ④ look-ahead placebo: 신호 +1월 shift시 붕괴 확인
#   ⑤ DSR-style: sweep이므로 변형 t-분포 보고 + 경제-default 사전약정(argmax 금지)
#   ⑥ default 변형 월별 net 시리즈 CSV 내보내기 → round9_contract.R 계약-grade NW3 t
import pandas as pd, numpy as np, warnings, os
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"; OUT=CACHE+"/discovery"
OUTF=OUT+"/round9_results.txt"; open(OUTF,"w",encoding="utf-8").close()
def log(s):
    print(s,flush=True)
    with open(OUTF,"a",encoding="utf-8") as f: f.write(s+"\n")
np.random.seed(9)

pan=pd.read_parquet(OUT+"/phase0_panel_2005-01_2026-04.parquet")
fcols=[c for c in pan.columns if c not in ("ym","Ticker","score_eff","fwd_ret_1m")]
pan[fcols]=pan[fcols].fillna(0.0)
fi={f:j for j,f in enumerate(fcols)}

FAMILIES={
 "broad":["C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings"],
 "narrow":["C04_ESBR","C05_ESCR"],
 "sue":["C01_SUE"],
 "revonly":["C02_EPS_Chg_1m","C04_ESBR","C05_ESCR"],
}
FAMILIES={k:[f for f in v if f in fi] for k,v in FAMILIES.items()}
VALUE=[f for f in ["V01_BM","V14_EBIT_EV"] if f in fi]

# bm 월간 총수익
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas(); bc=[c for c in("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmm=bm.groupby("ym")[bc].apply(lambda r:np.expm1(np.log1p(r).sum()))

# 유동성: RAWDATA 월별 mean(Close*Vol), t-1 shift, ≥2e8 (PIT). liq_ok[(ym,tk)]
rd=pq.read_table(CACHE+"/RAWDATA.parquet",columns=["Date","Ticker","Close","Vol"]).to_pandas()
rd["ym"]=pd.to_datetime(rd["Date"]).dt.strftime("%Y-%m"); rd["tv"]=rd["Close"]*rd["Vol"]
mliq=rd.groupby(["Ticker","ym"])["tv"].mean().reset_index().sort_values(["Ticker","ym"])
mliq["tv_lag"]=mliq.groupby("Ticker")["tv"].shift(1)   # t-1 PIT
LIQOK=set(map(tuple, mliq.loc[mliq["tv_lag"]>=2e8,["ym","Ticker"]].values))
LIQPCT=mliq.set_index(["Ticker","ym"])["tv"]  # for basket size pctile (info)

months=sorted(pan["ym"].unique()); midx={m:i for i,m in enumerate(months)}; OOS=months[60:]
Fmat=pan[fcols].values; ymarr=pan["ym"].values; tkv=pan["Ticker"].values; fwdm=pan["fwd_ret_1m"].values

def build_series(family, H=3, top_n=25, sizing="ew", liq=False, sig_offset=0):
    """월별 net 시리즈 (H 리밸·월간마킹·delta cost 15bps). sizing=ew|conviction. sig_offset=placebo."""
    w=np.array([1.0 if f in family else 0 for f in fcols])
    held=None; held_w=None; rows=[]
    for m in OOS:
        i=midx[m]
        decide=(i%H==0) or (held is None)
        te=np.where(ymarr==m)[0]
        to=0.0
        if decide and len(te)>=top_n:
            # PIT placebo: sig_offset>0 이면 미래신호 사용(붕괴해야 정상)
            msig = months[min(i+sig_offset, len(months)-1)] if sig_offset else m
            tse=np.where(ymarr==msig)[0]
            # 같은 종목집합 정렬 필요 → msig는 placebo 전용(offset=0이 정상)
            base_te = te if sig_offset==0 else tse
            cand_tk = tkv[base_te]; cand_sig = Fmat[base_te]@w
            pool = np.arange(len(base_te))
            if liq:
                pool=np.array([k for k in pool if (m,cand_tk[k]) in LIQOK])
                if len(pool)<top_n: pool=np.arange(len(base_te))  # fallback: 유동성 부족월
            ps=cand_sig[pool]; sel_local=pool[np.argpartition(-ps,min(top_n,len(ps)-1))[:top_n]]
            sel_tk=cand_tk[sel_local]; sel_sig=cand_sig[sel_local]
            if sizing=="conviction":
                rk=pd.Series(sel_sig).rank().values  # 1..n
                nw=rk/rk.sum()
            else:
                nw=np.full(len(sel_tk),1.0/len(sel_tk))
            newsel=dict(zip(sel_tk,nw))
            # turnover = sum|Δw|
            allk=set(newsel)|(set(held) if held else set())
            to=sum(abs(newsel.get(k,0)-(held.get(k,0) if held else 0)) for k in allk)
            held=newsel
        # 이번달 보유바스켓 수익
        mt_tk=tkv[te]; mt_fwd=fwdm[te]
        if held:
            gv=0.0; wv=0.0
            for k,wk in held.items():
                hit=np.where(mt_tk==k)[0]
                if len(hit): gv+=wk*mt_fwd[hit[0]]; wv+=wk
            gross=gv/wv if wv>0 else np.nan
        else: gross=np.nan
        net=gross-(to*0.0015 if decide else 0.0)
        rows.append((m,net,bmm.get(m,np.nan),to if decide else 0.0))
    return pd.DataFrame(rows,columns=["ym","net","bm","to"]).dropna(subset=["net","bm"])

def nw_t(x,lag=3):
    x=np.asarray(x); x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n)
def mdd(r): nav=np.cumprod(1+r); return 1-np.min(nav/np.maximum.accumulate(nav))
def metr(d):
    r=d["net"].values; a=r-d["bm"].values; n=len(r)
    if n<5: return dict(n=n)
    cagr=np.prod(1+r)**(12/n)-1; m=mdd(r)
    return dict(n=n, absSR=r.mean()/r.std()*np.sqrt(12), cagr=cagr, mdd=m,
               calmar=cagr/m if m>0 else np.nan, activeIR=a.mean()/a.std()*np.sqrt(12),
               port_t=nw_t(a), to=d["to"].mean()*12)
def sub(d,lo,hi): return d[(d["ym"]>=lo)&(d["ym"]<=hi)]

# ============ ① 구성 sweep (다중방법론) ============
log("="*78)
log("Round 9 — earnings LEAD capital-grade + 구성 sweep. recent=2021-26(search기간 — holdout 별도).")
log("="*78)
log(f"\n① 구성방법론 sweep (long-only, net 15bps delta, PORT_t=hand-NW3 빠른비교; 계약값은 round9_contract.R)")
log(f"{'variant':38s} {'recent_t':>8} {'recent_IR':>9} {'recent_calmar':>13} {'full_t':>7} {'TO':>5} {'n':>4}")
sweep=[]
DEFAULT=("broad",3,25,"ew",True)   # 사전약정 경제-default (argmax 아님)
for fam in ["broad","narrow","sue","revonly"]:
    for H in [3,6]:
        for sizing in ["ew","conviction"]:
            for liq in ([True] if (fam=="broad" and H in(3,6)) else [False]):
                if not FAMILIES[fam]: continue
                d=build_series(FAMILIES[fam],H=H,top_n=25,sizing=sizing,liq=liq)
                rec=metr(sub(d,"2021-01","2026-12")); full=metr(d)
                tag=f"{fam}/H{H}/{sizing}/{'liq' if liq else 'noliq'}"
                is_def=(fam,H,25,sizing,liq)==DEFAULT
                sweep.append((tag,rec.get("port_t",np.nan),rec.get("activeIR",np.nan),
                              rec.get("calmar",np.nan),full.get("port_t",np.nan),rec.get("to",np.nan),rec.get("n",0),is_def))
                log(f"{tag:38s} {rec.get('port_t',np.nan):8.2f} {rec.get('activeIR',np.nan):9.2f} {rec.get('calmar',np.nan):13.2f} {full.get('port_t',np.nan):7.2f} {rec.get('to',np.nan):5.1f} {rec.get('n',0):4d}{'  <-DEFAULT' if is_def else ''}")

# ⑤ DSR-style: sweep t-분포 (경제-default vs argmax)
tvec=np.array([s[1] for s in sweep if not np.isnan(s[1])])
defrow=[s for s in sweep if s[7]]
log(f"\n⑤ sweep t-분포: max {tvec.max():+.2f} / median {np.median(tvec):+.2f} / min {tvec.min():+.2f} / n_variant {len(tvec)}")
if defrow: log(f"   경제-default({defrow[0][0]}) recent_t={defrow[0][1]:+.2f} (사전약정 — argmax 선택 아님, DSR 면제 chain 규율)")
log(f"   해석: 변형 다수가 t>1.5면 robust LEAD. default가 max 근처면 cherry-pick 아님.")

# ============ default 정밀: full/recent/subwindow ============
log(f"\n② default({DEFAULT}) 구간별 정밀")
dft=build_series(FAMILIES["broad"],H=3,top_n=25,sizing="ew",liq=True)
for tag,lo,hi in [("full","2010-01","2026-12"),("recent 21-26","2021-01","2026-12"),
                  ("2010-15","2010-01","2015-12"),("2016-20","2016-01","2020-12"),
                  ("21-23","2021-01","2023-12"),("24-26","2024-01","2026-12")]:
    mm=metr(sub(dft,lo,hi))
    if mm.get("n",0)>=5:
        log(f"  {tag:12s} n{mm['n']:3d} absSR {mm['absSR']:+.2f} CAGR {mm['cagr']*100:+5.1f}% MDD {mm['mdd']*100:4.1f}% calmar {mm['calmar']:+.2f} | IR {mm['activeIR']:+.2f} PORT_t {mm['port_t']:+.2f} TO {mm['to']:.1f}")

# ④ look-ahead placebo (offset=1 → 붕괴해야 PIT clean)
dpl=build_series(FAMILIES["broad"],H=3,top_n=25,sizing="ew",liq=True,sig_offset=1)
mpl=metr(sub(dpl,"2021-01","2026-12"))
log(f"\n④ look-ahead placebo (신호 +1월 shift, recent): PORT_t {mpl.get('port_t',np.nan):+.2f} (default {metr(sub(dft,'2021-01','2026-12'))['port_t']:+.2f} 대비 붕괴=PIT clean)")

# ============ ③ book-marginal (실제 book active-basis ΔIR + active 상관) ============
log(f"\n③ book-marginal — 실제 book(ret_L5_V5) active-basis. 메커니즘=낮은 active 상관 + 양수 sleeve.")
L5=pd.read_csv(ROOT+"/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5["ym"]=L5["realized_ym"].astype(str).str[:7]; bk=L5[["ym","ret_L5_V5"]].dropna()
mrg=dft.merge(bk,on="ym",how="inner")
mrg["bk_act"]=mrg["ret_L5_V5"]-mrg["bm"]; mrg["sl_act"]=mrg["net"]-mrg["bm"]
def ir(a): a=np.asarray(a); return a.mean()/a.std()*np.sqrt(12)
def srcal(r):
    r=np.asarray(r); n=len(r); cagr=np.prod(1+r)**(12/n)-1; m=mdd(r); return r.mean()/r.std()*np.sqrt(12),(cagr/m if m>0 else np.nan)
for tag,lo in [("full",None),("recent",2021)]:
    d=mrg if lo is None else mrg[mrg["ym"]>=f"{lo}-01"]
    if len(d)<6: continue
    acorr=np.corrcoef(d["bk_act"],d["sl_act"])[0,1]
    bir=ir(d["bk_act"]); bsr,bcal=srcal(d["ret_L5_V5"].values)
    log(f"  [{tag}] n{len(d)} book활성IR {bir:+.2f} book_SR {bsr:+.2f} | sleeve활성IR {ir(d['sl_act']):+.2f} | active상관 {acorr:+.2f}")
    for b in [0.85,0.75,0.65]:
        comb=b*d["ret_L5_V5"].values+(1-b)*d["net"].values; cact=comb-d["bm"].values
        csr,ccal=srcal(comb)
        log(f"     book{int(b*100)}/sleeve{int((1-b)*100)}: ΔactiveIR {ir(cact)-bir:+.3f} | SR {csr:+.2f}(Δ{csr-bsr:+.2f}) calmar {ccal:+.2f}")

# ============ ③' value-up 국면 decomp ============
log(f"\n③' value-up 분해 — earnings가 단순 value-up 국면인가? value sleeve와 active 상관 + 시기분해")
if VALUE:
    vdf=build_series(VALUE,H=3,top_n=25,sizing="ew",liq=True)
    vm=dft.merge(vdf[["ym","net"]].rename(columns={"net":"vnet"}),on="ym",how="inner")
    vm=vm[vm["ym"]>="2021-01"]
    ea=vm["net"]-vm["bm"]; va=vm["vnet"]-vm["bm"]
    log(f"  recent: earnings활성IR {ir(ea):+.2f} | value활성IR {ir(va):+.2f} | 상관 {np.corrcoef(ea,va)[0,1]:+.2f} (낮으면 earnings≠value-up)")
log(f"  시기분해: 21-23 PORT_t {metr(sub(dft,'2021-01','2023-12')).get('port_t',np.nan):+.2f} (value-up前 2022포함) vs 24-26 {metr(sub(dft,'2024-01','2026-12')).get('port_t',np.nan):+.2f}")
log(f"   해석: 21-23도 양수면 value-up 국면 단독 아님(2022 +21% 기여).")

# ============ ⑥ default 시리즈 CSV 내보내기 → 계약-grade ============
exp=dft[["ym","net","bm"]].copy(); exp.columns=["ym","ret_net","benchmark_ret"]
exp.to_csv(OUT+"/round9_default_series.csv",index=False)
log(f"\n⑥ default 월별 시리즈 → {OUT}/round9_default_series.csv (n={len(exp)}) → round9_contract.R 계약 NW3 t")
log("\n판정 기준: 계약 PORT_t(NW3) recent vs HARD 2.95 / book-marginal ΔactiveIR≥0.05 / placebo 붕괴 / value≠earnings / 21-23도 양수 → holdout 사전등록 자격.")
log("=== done ===")
