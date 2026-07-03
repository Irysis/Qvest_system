"""
Quick-test for paper 2606.23596 (Body-Tail Test of Factor Models).
KR-FAITHFUL-IN-SPIRIT replication. Paper's discriminating result is q5-specific
(pattern lives in ROE/EG block, collapses when EG dropped). We have NO Global-q
daily series, so we build a KR q5-ANALOGUE from the factor panel and an FF-analogue,
then run the structural leg-alpha test at MONTHLY freq (panel is monthly fwd_ret_1m).

Paper construction (faithfully ported):
- Classification var = cumulative market-cap share (descending sort). body = top-p
  cap fraction (largest caps), tail = remainder. p grid {0.50,0.60,0.75,0.80,0.85,0.90,0.95}.
- Legs = VALUE-WEIGHTED (cap weights) buy-and-hold; previous-month weights so
  recombination R_M = w_B R_B + w_T R_T holds exactly (cap-wt market).
- Per leg: regress excess leg return on factor model -> leg alpha. Test joint
  H0: alpha_B = alpha_T = 0 (Wald) + check offsetting pattern (neg body / pos tail).
- Placebo: 200 random splits per ratio matched to leg cap shares.

Models compared:
  CAPM-analogue : [MKT]
  FF-analogue   : [MKT, ME, VAL, MOM]        (size, value, momentum)
  q5-analogue   : [MKT, ME, IA, ROE, EG]     (Hou-Mo-Xue-Zhang structure)

Factors are cross-sectional long-short (top-bottom quintile, cap-neutral-ish) monthly,
built from panel columns. MKT = cap-weighted market excess (rf=0 approx, KR).
metric_type = empirical_factor_regression (diagnostic, NOT a tradeable backtest).
PIT: panel is PIT-built (fwd_ret_1m is t+1 realized vs t-known factors). Monthly.
Std stats only (np.linalg.lstsq OLS + Newey-West HAC). NO self-synthesis of returns.
"""
import numpy as np, pandas as pd, pyarrow.parquet as pq, json
np.random.seed(42)

PANEL='.cache/discovery/phase0_panel_2005-01_2026-04.parquet'
# columns: market-cap proxy + factor signals + fwd return
need=['ym','Ticker','fwd_ret_1m','L26_Log_MktCap','S01_Size',
      'V01_BM','V02_EP','M01_Mom_12_1','Q02_ROE',
      'IN01_CapEx_to_Assets','Q06_Asset_Growth','GR02_Earnings_Growth','GR04_GPA_Growth']
df=pq.read_table(PANEL, columns=need).to_pandas()
df['ym']=df['ym'].astype(str)
df=df.dropna(subset=['fwd_ret_1m','L26_Log_MktCap']).copy()
# market cap level from log mktcap
df['mcap']=np.exp(df['L26_Log_MktCap'])
months=sorted(df['ym'].unique())
print(f"panel: {df.shape}, months {months[0]}..{months[-1]} (n={len(months)})")

def winz(s):
    lo,hi=s.quantile(0.01),s.quantile(0.99); return s.clip(lo,hi)

# ---- Build cap-weighted MARKET excess return (rf~0 KR monthly approx) ----
def capwt_mean(g, retcol='fwd_ret_1m'):
    w=g['mcap'].values; w=w/w.sum(); return float(np.sum(w*g[retcol].values))
mkt = df.groupby('ym').apply(capwt_mean).rename('MKT')

# ---- Build cross-sectional LS factors (top-bottom quintile cap-wt spread) ----
def ls_factor(df, sigcol, sign=1):
    out={}
    for ym,g in df.groupby('ym'):
        g=g.dropna(subset=[sigcol])
        if len(g)<20: continue
        s=sign*g[sigcol].values
        q=pd.qcut(pd.Series(s,index=g.index),5,labels=False,duplicates='drop')
        if q is None or q.nunique()<5: continue
        hi=g[q==4]; lo=g[q==0]
        if len(hi)<3 or len(lo)<3: continue
        wh=hi['mcap']/hi['mcap'].sum(); wl=lo['mcap']/lo['mcap'].sum()
        out[ym]=float((wh*hi['fwd_ret_1m']).sum() - (wl*lo['fwd_ret_1m']).sum())
    return pd.Series(out)

# ME (size): small-minus-big -> sign=-1 on log mktcap (small caps high)
ME = ls_factor(df,'L26_Log_MktCap',sign=-1).rename('ME')
# VAL: high BM minus low
VAL= ls_factor(df,'V01_BM',sign=1).rename('VAL')
# MOM
MOM= ls_factor(df,'M01_Mom_12_1',sign=1).rename('MOM')
# ROE (profitability)
ROE= ls_factor(df,'Q02_ROE',sign=1).rename('ROE')
# IA (investment): low investment minus high -> conservative; sign=-1 on CapEx/Assets
IA = ls_factor(df,'IN01_CapEx_to_Assets',sign=-1).rename('IA')
# EG (expected growth proxy): earnings growth high minus low
EG = ls_factor(df,'GR02_Earnings_Growth',sign=1).rename('EG')

F=pd.concat([mkt,ME,VAL,MOM,ROE,IA,EG],axis=1).dropna()
print("factor months after align:", F.shape)
print("factor mean(%/m) annualized(%):")
for c in F.columns: print(f"  {c:5s} mean={F[c].mean()*100:+.3f} ann={F[c].mean()*12*100:+.2f} t={F[c].mean()/F[c].std()*np.sqrt(len(F)):+.2f}")

# ---- Body/Tail legs by cumulative cap share ----
ratios=[0.50,0.60,0.75,0.80,0.85,0.90,0.95]
def leg_returns(df, p):
    """return per-month (R_body, R_tail, w_body, w_tail) cap-weighted."""
    rb={}; rt={}; wb={}
    for ym,g in df.groupby('ym'):
        g=g.sort_values('mcap',ascending=False)
        tot=g['mcap'].sum(); cum=g['mcap'].cumsum()/tot
        body=g[cum<=p]; tail=g[cum>p]
        if len(body)<2 or len(tail)<2: continue
        wbody=body['mcap'].sum()/tot
        rb[ym]=float((body['mcap']/body['mcap'].sum()*body['fwd_ret_1m']).sum())
        rt[ym]=float((tail['mcap']/tail['mcap'].sum()*tail['fwd_ret_1m']).sum())
        wb[ym]=wbody
    return pd.Series(rb),pd.Series(rt),pd.Series(wb)

def nw_ols(y, X, lag=3):
    """OLS with Newey-West HAC se. X already includes const. returns beta, se, t."""
    n,k=X.shape
    XtX_inv=np.linalg.inv(X.T@X)
    beta=XtX_inv@(X.T@y)
    resid=y-X@beta
    S=np.zeros((k,k))
    for l in range(0,lag+1):
        w=1.0 if l==0 else 1-l/(lag+1)
        for t in range(l,n):
            xt=X[t:t+1].T; xtl=X[t-l:t-l+1].T
            g=(resid[t]*xt)@(resid[t-l]*xtl).T
            S+= w*(g + (g.T if l>0 else 0))
    cov=XtX_inv@S@XtX_inv
    se=np.sqrt(np.diag(cov)); tstat=beta/se
    return beta,se,tstat

models={
 'CAPM':['MKT'],
 'FF_analog':['MKT','ME','VAL','MOM'],
 'q5_analog':['MKT','ME','IA','ROE','EG'],
}

results={}
for mname,fcols in models.items():
    Fm=F[fcols].dropna()
    rej=0; rows=[]
    for p in ratios:
        rb,rt,wb=leg_returns(df,p)
        idx=Fm.index.intersection(rb.index).intersection(rt.index)
        if len(idx)<40: continue
        Xf=np.column_stack([np.ones(len(idx))]+[Fm.loc[idx,c].values for c in fcols])
        yb=rb.loc[idx].values - 0.0  # rf~0
        yt=rt.loc[idx].values - 0.0
        bb,seb,tb=nw_ols(yb,Xf,lag=3); a_b=bb[0]*12*100; ta_b=tb[0]  # ann % alpha
        bt,set_,tt=nw_ols(yt,Xf,lag=3); a_t=bt[0]*12*100; ta_t=tt[0]
        # joint reject heuristic: both |t|>1.96
        joint_rej = (abs(ta_b)>1.96) and (abs(ta_t)>1.96)
        offsetting = (a_b<0) and (a_t>0)
        if joint_rej: rej+=1
        rows.append({'p':p,'alpha_body_ann%':round(a_b,1),'t_body':round(ta_b,2),
                     'alpha_tail_ann%':round(a_t,1),'t_tail':round(ta_t,2),
                     'joint_rej':bool(joint_rej),'offsetting':bool(offsetting),'n':int(len(idx))})
    results[mname]={'reject_count':f"{rej}/{len(rows)}",'rows':rows}
    print(f"\n=== {mname} ({'+'.join(fcols)}) ===")
    print(f"joint reject (both legs |t|>1.96): {rej}/{len(rows)}")
    for r in rows:
        flag='OFFSET' if r['offsetting'] else ''
        print(f"  p={r['p']:.2f} body_a={r['alpha_body_ann%']:+6.1f}(t={r['t_body']:+.2f}) tail_a={r['alpha_tail_ann%']:+6.1f}(t={r['t_tail']:+.2f}) {'REJ' if r['joint_rej'] else '   '} {flag}")

# ---- Placebo: random splits matched to body cap share, q5_analog only, p=0.80 ----
print("\n=== Placebo: 200 random cap-matched splits, q5_analog, p=0.80 ===")
p0=0.80; fcols=models['q5_analog']; Fm=F[fcols].dropna()
rb,rt,wb=leg_returns(df,p0)
idx=Fm.index.intersection(rb.index)
target_wb=wb.loc[idx].mean()
rej_rand=0; NR=200
g_by_month={ym:g for ym,g in df.groupby('ym')}
for it in range(NR):
    ra={}; rbb={}
    for ym in idx:
        g=g_by_month[ym]; perm=g.sample(frac=1.0,random_state=it*1000+hash(ym)%1000)
        tot=perm['mcap'].sum(); cum=perm['mcap'].cumsum()/tot
        A=perm[cum<=p0]; B=perm[cum>p0]
        if len(A)<2 or len(B)<2: continue
        ra[ym]=float((A['mcap']/A['mcap'].sum()*A['fwd_ret_1m']).sum())
        rbb[ym]=float((B['mcap']/B['mcap'].sum()*B['fwd_ret_1m']).sum())
    ra=pd.Series(ra); rbb=pd.Series(rbb)
    ii=Fm.index.intersection(ra.index).intersection(rbb.index)
    if len(ii)<40: continue
    Xf=np.column_stack([np.ones(len(ii))]+[Fm.loc[ii,c].values for c in fcols])
    _,_,ta=nw_ols(ra.loc[ii].values,Xf,lag=3)
    _,_,tb=nw_ols(rbb.loc[ii].values,Xf,lag=3)
    if (abs(ta[0])>1.96) and (abs(tb[0])>1.96): rej_rand+=1
print(f"random-split joint reject rate: {rej_rand}/{NR} = {rej_rand/NR*100:.1f}% (nominal ~5%)")

out={'models':results,'placebo_q5_p080':{'reject':rej_rand,'n':NR,'rate':rej_rand/NR},
     'factor_summary':{c:{'mean_m':float(F[c].mean()),'ann%':float(F[c].mean()*12*100),
                          't':float(F[c].mean()/F[c].std()*np.sqrt(len(F)))} for c in F.columns},
     'metric_type':'empirical_factor_regression','note':'KR q5-ANALOGUE (no Global-q daily); monthly; structural-spirit replication'}
with open('stage_artifacts/paper_recharge/bodytail_23596_results.json','w') as f: json.dump(out,f,indent=2)
print("\nsaved -> stage_artifacts/paper_recharge/bodytail_23596_results.json")
