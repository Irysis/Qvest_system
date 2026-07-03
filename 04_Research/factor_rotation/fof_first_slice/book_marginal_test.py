"""book_marginal_test.py — 천장 감사 구멍①: FoF의 book-marginal 편입 테스트 (§4 admission 실제 게이트).
incumbent = 배포북 L5_V2(period_returns_layer5.csv, v24 remeasure 기반). candidate = FoF(시즌드+IC틸트).
★merge 전 offset 검증(-3..+3, cor(book,BM) peak가 0이어야) — book misalignment 전례 방어.
측정: active basis(−BM) ρ·IR + 배분 w별 결합 ΔIR(게이트 ≥0.05) + 절대 SR basis 병기.
"""
import pandas as pd, numpy as np
R="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT=R+"/04_Research/factor_rotation/fof_first_slice"
def nw_t(x,lag=3):
    x=np.asarray(x,float); x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n) if s>0 else np.nan
def ir(a): a=np.asarray(a,float); a=a[~np.isnan(a)]; return a.mean()/a.std()*np.sqrt(12) if a.std()>0 else np.nan
def sr(a): return ir(a)
def mdd(r): nav=np.cumprod(1+np.asarray(r,float)); return 1-np.min(nav/np.maximum.accumulate(nav))

bk=pd.read_csv(R+"/04_Research/pg2_forensics/v24_book_remeasure/period_returns_layer5.csv")
bk=bk[["realized_ym","ret_L5_V2"]].rename(columns={"realized_ym":"ym","ret_L5_V2":"book"}).dropna()
ff=pd.read_csv(OUT+"/stack_fof_active.csv")  # ym, act_fof, net_fof, bm
M=ff.merge(bk,on="ym",how="inner").sort_values("ym").reset_index(drop=True)
print(f"merged n={len(M)} {M.ym.min()}..{M.ym.max()}")

## ── offset 검증 (book misalignment 전례): cor(book, bm) shift −3..+3 → peak가 0이어야 ──
print("\n=== offset audit: cor(book_ret, BM_ret) at shifts −3..+3 ===")
for k in range(-3,4):
    b=M["book"].shift(k); c=np.corrcoef(b.iloc[3:-3], M["bm"].iloc[3:-3])[0,1]
    print(f"  shift{k:+d}: {c:+.3f}" + ("  ← peak여야 정상(라벨 정렬)" if k==0 else ""))

M["book_act"]=M["book"]-M["bm"]
print("\n=== standalone (active vs cap-weight BM) ===")
for c,nm in [("book_act","배포북 L5_V2"),("act_fof","FoF(시즌드+IC틸트)")]:
    a=M[c].values; arec=M.loc[M.ym>='2021-01',c].values
    print(f"  {nm:18s} full: IR={ir(a):+.2f} PORT_t={nw_t(a):+.2f} | recent(2021+): IR={ir(arec):+.2f} PORT_t={nw_t(arec):+.2f}")
rho=np.corrcoef(M["book_act"],M["act_fof"])[0,1]
rr=M[M.ym>='2021-01']; rho_r=np.corrcoef(rr["book_act"],rr["act_fof"])[0,1]
print(f"\n  ★ρ(book_act, fof_act) full={rho:+.2f} | recent={rho_r:+.2f}  (낮을수록 결합가치)")

print("\n=== book-marginal: w_fof 배분별 결합 active IR (게이트 ΔIR≥0.05) ===")
inc=ir(M["book_act"].values)
rows=[]
for w in (0.0,0.1,0.2,0.3,0.4,0.5):
    comb=(1-w)*M["book_act"]+w*M["act_fof"]
    d=ir(comb.values)-inc
    rows.append((w,ir(comb.values),d,nw_t(comb.values)))
    print(f"  w_fof={w:.1f}: 결합 IR={ir(comb.values):+.3f}  ΔIR={d:+.3f} {'✓ADMIT' if d>=0.05 else ''}  PORT_t={nw_t(comb.values):+.2f}")
best=max(rows,key=lambda r:r[1])
print(f"\n  최적 w_fof={best[0]:.1f}: ΔIR={best[2]:+.3f} → {'★게이트 통과(≥0.05)' if best[2]>=0.05 else '게이트 미달'}")

print("\n=== 절대 SR basis (net, 참고 — 목표 2.5) ===")
for w in (0.0,0.2,0.3,0.5):
    comb=(1-w)*M["book"]+w*M["net_fof"]
    print(f"  w_fof={w:.1f}: 절대 SR={sr(comb.values):+.2f} MDD={100*mdd(comb.values):.1f}% CAGR={100*(np.prod(1+comb.values)**(12/len(comb))-1):+.1f}%")
M.to_csv(OUT+"/book_marginal_series.csv",index=False); print("\nsaved book_marginal_series.csv")
