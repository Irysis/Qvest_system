# PG2 현행(AR) vs 개선(충실 추세오버레이) 성과 비교 + 시각화 3-panel PNG.
import pandas as pd, numpy as np, warnings
warnings.filterwarnings("ignore")
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=ROOT+"/.cache/discovery"
PNG=OUT+"/pg2_faithful_comparison.png"
d=pd.read_csv(OUT+"/verify_overlay_series.csv"); d["date"]=pd.to_datetime(d["date"]); d=d.sort_values("date").reset_index(drop=True)
def stats(x):
    x=np.asarray(x,float); x=x[np.isfinite(x)]; nav=np.cumprod(1+x); mdd=1-np.min(nav/np.maximum.accumulate(nav))
    cagr=nav[-1]**(12/len(x))-1; sr=x.mean()/x.std()*np.sqrt(12); dn=x[x<0]
    return dict(SR=sr,CAGR=cagr,MDD=mdd,Calmar=cagr/mdd,Sortino=x.mean()/dn.std()*np.sqrt(12))
sb=stats(d["ret_book"]); sf=stats(d["ret_faith"])
print("=== PG2 성과 비교 (2004-2026, 269m) ===")
print(f"  {'':16}{'현 PG2(AR)':>12}{'개선(충실)':>12}{'Δ':>10}")
for k in ["SR","CAGR","MDD","Calmar","Sortino"]:
    v=" %+.1f%%"%((sf[k]-sb[k])*100) if k in("CAGR","MDD") else " %+.3f"%(sf[k]-sb[k])
    fb="%.1f%%"%(sb[k]*100) if k in("CAGR","MDD") else "%.3f"%sb[k]
    ff="%.1f%%"%(sf[k]*100) if k in("CAGR","MDD") else "%.3f"%sf[k]
    print(f"  {k:16}{fb:>12}{ff:>12}{v:>10}")

# NAV / DD / annual
for c in ["ret_book","ret_faith","bmret"]: d[c]=pd.to_numeric(d[c],errors="coerce")
navB=np.cumprod(1+d["ret_book"].fillna(0)); navF=np.cumprod(1+d["ret_faith"].fillna(0)); navM=np.cumprod(1+d["bmret"].fillna(0))
ddB=navB/navB.cummax()-1; ddF=navF/navF.cummax()-1
d["yr"]=d["date"].dt.year
annB=d.groupby("yr")["ret_book"].apply(lambda r:np.prod(1+r.dropna())-1); annF=d.groupby("yr")["ret_faith"].apply(lambda r:np.prod(1+r.dropna())-1)

plt.rcParams.update({"font.size":10,"axes.grid":True,"grid.alpha":0.3})
fig,(a1,a2,a3)=plt.subplots(3,1,figsize=(12,13),gridspec_kw={"height_ratios":[2.2,1.2,1.4]})
a1.plot(d["date"],navB,label=f"Current PG2 (AR)  SR {sb['SR']:.2f}",color="#1f4e79",lw=1.8)
a1.plot(d["date"],navF,label=f"Improved (Faithful trend-overlay)  SR {sf['SR']:.2f}",color="#2e8b57",lw=1.8)
a1.plot(d["date"],navM,label="KOSPI (benchmark)",color="#999999",lw=1.0,ls="--")
a1.set_yscale("log"); a1.set_title("PG2 Book: Current (AR) vs Improved (Faithful Paper#4 Trend-Overlay) — Cumulative NAV (log scale), 2004–2026",fontsize=11,weight="bold")
a1.set_ylabel("NAV (log)"); a1.legend(loc="upper left",fontsize=9)
a1.text(0.99,0.03,f"Improved: SR {sf['SR']:.2f} / MDD {sf['MDD']*100:.1f}% / Calmar {sf['Calmar']:.2f}\nCurrent : SR {sb['SR']:.2f} / MDD {sb['MDD']*100:.1f}% / Calmar {sb['Calmar']:.2f}",
        transform=a1.transAxes,ha="right",va="bottom",fontsize=9,bbox=dict(boxstyle="round",fc="#f5f5f5",ec="#cccccc"))
a2.fill_between(d["date"],ddB*100,0,color="#1f4e79",alpha=0.45,label="Current (AR)")
a2.fill_between(d["date"],ddF*100,0,color="#2e8b57",alpha=0.45,label="Improved")
a2.set_title("Underwater Drawdown (%)",fontsize=10,weight="bold"); a2.set_ylabel("Drawdown %"); a2.legend(loc="lower left",fontsize=9)
x=np.arange(len(annB)); a3.bar(x-0.2,annB.values*100,0.4,label="Current (AR)",color="#1f4e79")
a3.bar(x+0.2,annF.values*100,0.4,label="Improved",color="#2e8b57")
a3.set_xticks(x); a3.set_xticklabels(annB.index,rotation=45,fontsize=8); a3.axhline(0,color="k",lw=0.6)
a3.set_title("Annual Returns (%)",fontsize=10,weight="bold"); a3.set_ylabel("Return %"); a3.legend(fontsize=9)
plt.tight_layout(); plt.savefig(PNG,dpi=130,bbox_inches="tight"); print(f"\nPNG → {PNG}")
