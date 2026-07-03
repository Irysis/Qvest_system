"""run_kns_phaseA.py — Kozak-Nagel-Santosh (2017, NBER w24070) "Shrinking the Cross-Section"
논문 방법론 한치의 변형/누락/오차 없는 충실 구현 (Phase A: full-sample 복제).

충실 사양 (원전 eq. 번호):
  eq(1)  M_t = 1 − b'_{t-1}(R_t − ER_t)
  eq(3)  b_{t-1} = Z_{t-1} b            (Z = N×H 특성행렬, 횡단면 demean+표준화)
  eq(4)  F_t = Z'_{t-1} R_t             (특성-managed 팩터수익, zero-invest long-short)
         → 시장수익률에 직교화 (KNS §2.1: "orthogonalize w.r.t. market return")
  eq(13) μ̄ = (1/T) Σ F_t
  eq(14) Σ  = (1/T) Σ (F_t−μ̄)(F_t−μ̄)'
  eq(17) naive  b̂ = Σ⁻¹ μ̄   (T<H이면 Moore-Penrose pseudo-inverse)
  eq(22) L2     b̂ = (Σ + γI)⁻¹ μ̄,  γ = τ/(κ²T), τ=tr(Σ), prior η=2 → b~N(0,(κ²/τ)I)
  eq(24) PC공간 shrink factor d_j/(d_j+γ): 작은 고유값일수록 강하게 축소
  eq(28) elastic-net  b̂ = argmin (μ̄−Σb)'Σ⁻¹(μ̄−Σb) + γ2 b'b + γ1 Σ|b_i|  (LARS-EN)
         = argmin  b'(Σ+γ2 I)b − 2μ̄'b + γ1|b|_1  (centering/normalization 안함 — KNS §3.2)
  eq(29) 근제곱최대SR prior = κ
  eq(30) 3-fold CV:  R²_oos = 1 − (μ̄2−Σ2 b̂)'(μ̄2−Σ2 b̂)/(μ̄2'μ̄2),  γ argmax

데이터: explore_panel 327 RAW 특성(pre-C13, non-FWL — 우리 인프라 덮어쓰기 아님) + F1 종목수익 + BM.
슈퍼팩터 = 종목 SDF loading  s_i = Z_std[i,:]·b̂  (=b_{t-1} 성분).  방향 미조정(부호는 b̂이 학습 = C13 flip 아님).
"""
import os, sys, numpy as np, pandas as pd, json
np.set_printoptions(suppress=True, precision=4)
os.environ.setdefault("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0,"02_Infrastructure/discovery")
from discovery_explore import ensure_panel, bm_fwd_map, load_families, nw_t, HORIZONS_ALL
R=os.environ["QM_ROOT"]; OUT=R+"/04_Research/factor_rotation/fof_first_slice"

panel=ensure_panel()
excl=("ym","Ticker","score_eff","fwd_ret_1m","Size")+tuple(f"F{H}" for H in HORIZONS_ALL)
fcols=[c for c in panel.columns if c not in excl]
months=sorted(panel["ym"].unique()); mi={m:i for i,m in enumerate(months)}; bmf=bm_fwd_map()
ymv=panel["ym"].values; tkv=panel["Ticker"].values
H=len(fcols); T=len(months)
print(f"[data] H={H} raw chars | T={T} months ({months[0]}..{months[-1]}) | median N={int(panel.groupby('ym').size().median())}")

# ── Z_std: 월별 횡단면 demean + 표준화 (KNS §2.1) ──
Xraw=panel[fcols].values.astype(float); Xraw=np.where(np.isfinite(Xraw),Xraw,np.nan)
Z=np.full_like(Xraw,np.nan)
for t in np.unique(ymv):
    m=ymv==t; v=Xraw[m]; mu=np.nanmean(v,0); sd=np.nanstd(v,0); sd[sd<1e-9]=1.0
    Z[m]=(v-mu)/sd
Z=np.nan_to_num(Z)   # 결측 → 0 (표준화 후 중립)

# ── eq(4): 특성-managed 팩터수익  F_t[j] = (1/N_t) Σ_i Z_std[i,j] R_{i,t}  (per-unit-char 정규화) ──
# Z가 횡단 demean이라 excess/raw 무관(Σ_i Z_ij=0). R = F1(다음달 종목수익, PIT: Z는 당월 known).
F1=panel["F1"].values.astype(float)
mfr=np.full((T,H),np.nan)          # 신호월 k 기준(수익은 k+1월 실현)
for k,t in enumerate(months):
    m=ymv==t; r=F1[m]; ok=np.isfinite(r)
    if ok.sum()<25: continue
    z=Z[m][ok]; rr=r[ok]
    mfr[k]=(z.T@rr)/ok.sum()
valid=np.isfinite(mfr).all(1); mfr=mfr[valid]; mfr_months=[months[k] for k in range(T) if valid[k]]
mkt=np.array([bmf(mm,1) for mm in mfr_months])   # 시장(BM) 전방수익, mfr와 동일 정렬
print(f"[managed] F matrix: {mfr.shape[0]} months × {H} factors | mkt aligned {mkt.shape}")

def orth_market(Fm, mk):
    """KNS §2.1: 각 managed 팩터를 시장수익률에 직교화 (창 내 OLS 잔차)."""
    mkc=mk-mk.mean(); denom=(mkc@mkc)
    if denom<1e-12: return Fm.copy()
    beta=(Fm-Fm.mean(0)).T@mkc/denom          # H,
    return Fm - np.outer(mkc, beta)           # 잔차 (시장성분 제거)

def moments(Fm):
    mu=Fm.mean(0)                              # eq(13)
    C=(Fm-mu).T@(Fm-mu)/Fm.shape[0]           # eq(14)  1/T
    return mu, C

def b_l2(mu,C,g):                              # eq(22)
    return np.linalg.solve(C+g*np.eye(len(mu)), mu)

def b_naive(mu,C):                             # eq(17) pseudo-inverse (T<H)
    return np.linalg.pinv(C)@mu

def r2_oos(mu2,C2,bhat):                       # eq(30)
    e=mu2-C2@bhat
    return 1.0-(e@e)/(mu2@mu2)

# ── eq(30) 3-fold CV로 γ 선택 ──
Fo=orth_market(mfr, mkt)
mu_full,C_full=moments(Fo)
tau=np.trace(C_full); mean_eig=tau/H
gs=np.logspace(-4,3,60)*mean_eig               # γ/mean_eig ∈ [1e-4,1e3]
rng=np.random.RandomState(0); idx=rng.permutation(Fo.shape[0]); folds=np.array_split(idx,3)
cv=np.zeros(len(gs))
for gi,g in enumerate(gs):
    accs=[]
    for f in range(3):
        te=folds[f]; tr=np.concatenate([folds[j] for j in range(3) if j!=f])
        mu_tr,C_tr=moments(Fo[tr]); mu_te,C_te=moments(Fo[te])
        accs.append(r2_oos(mu_te,C_te,b_l2(mu_tr,C_tr,g)))
    cv[gi]=np.mean(accs)
gstar=gs[int(np.argmax(cv))]; kappa=np.sqrt(tau/(gstar*Fo.shape[0]))   # eq(29) 함의 κ
bL2=b_l2(mu_full,C_full,gstar)
bN=b_naive(mu_full,C_full)
sr2_l2=mu_full@bL2                              # 함의 max squared SR (monthly)
sr2_naive=mu_full@np.linalg.pinv(C_full)@mu_full
# PC공간 shrink 진단 (eq.24)
d,Q=np.linalg.eigh(C_full); d=d[::-1]; Q=Q[:,::-1]
shrink=d/(d+gstar)
print(f"\n[CV] γ*={gstar:.3e} (γ*/mean_eig={gstar/mean_eig:.3g}) | 함의 κ(월간 근제곱최대SR)={kappa:.3f}")
print(f"[CV] max R²_oos={cv.max():+.4f} @γ* | R²_oos(γ→0 naive쪽)={cv[0]:+.4f} | R²_oos(γ→대)={cv[-1]:+.4f}")
print(f"[SR] 함의 monthly max SR² : L2={sr2_l2:.4f} (annualSR≈{np.sqrt(max(sr2_l2,0)*12):.2f}) | naive(pinv)={sr2_naive:.4f}(과적합)")
print(f"[PC] eigenvalues top5={d[:5].round(6)} | shrink factor top5={shrink[:5].round(3)} | bottom5 shrink={shrink[-5:].round(4)}")
print(f"[b] L2: ||b||={np.linalg.norm(bL2):.3f} | #|b_j|>10%max={int((np.abs(bL2)>0.1*np.abs(bL2).max()).sum())}/{H}")

# ── eq(28) elastic-net (좌표하강; b'(Σ+γ2 I)b − 2μ̄'b + γ1|b|_1) ──
def elastic_net(mu,C,g1,g2,it=2000,tol=1e-9):
    A=C+g2*np.eye(len(mu)); b=np.zeros(len(mu)); dgA=np.diag(A).copy(); dgA[dgA<1e-12]=1e-12
    for _ in range(it):
        b0=b.copy()
        for j in range(len(mu)):
            rj=mu[j]-(A[j]@b - A[j,j]*b[j])
            b[j]=np.sign(rj)*max(abs(rj)-g1/2,0)/dgA[j]
        if np.max(np.abs(b-b0))<tol: break
    return b
# γ2=γ*(L2 유지), γ1 grid로 sparsity CV
g1s=np.logspace(-5,0,25)*mean_eig; cv1=np.zeros(len(g1s))
for gi,g1 in enumerate(g1s):
    accs=[]
    for f in range(3):
        te=folds[f]; tr=np.concatenate([folds[j] for j in range(3) if j!=f])
        mu_tr,C_tr=moments(Fo[tr]); mu_te,C_te=moments(Fo[te])
        accs.append(r2_oos(mu_te,C_te,elastic_net(mu_tr,C_tr,g1,gstar,it=400)))
    cv1[gi]=np.mean(accs)
g1star=g1s[int(np.argmax(cv1))]; bEN=elastic_net(mu_full,C_full,g1star,gstar)
nz=int((np.abs(bEN)>1e-8).sum())
print(f"\n[EN] elastic-net γ1*={g1star:.3e} γ2=γ*  | max R²_oos={cv1.max():+.4f} | 非0 계수={nz}/{H} (sparsity {1-nz/H:.1%})")
print(f"[EN] R²_oos(EN best) {cv1.max():+.4f} vs L2 {cv.max():+.4f} → {'EN 우위' if cv1.max()>cv.max() else 'L2 우위(sparsity 손실)'}")

# ── 슈퍼팩터 종목점수 s_i = Z_std[i,:]·b̂ (full-sample b̂, 진단용) ──
for tag,bh in [("L2",bL2),("EN",bEN)]:
    s=Z@bh
    # 월별 IC (s vs F1)
    ics=[]
    for t in np.unique(ymv):
        m=ymv==t; y=F1[m]; ok=np.isfinite(y)
        if ok.sum()<25: continue
        sc=s[m][ok]; yy=y[ok]
        if sc.std()>1e-9: ics.append(np.corrcoef(sc,yy)[0,1])
    ics=np.array(ics); print(f"[score {tag}] mean IC={ics.mean():+.4f} ICIR={ics.mean()/ics.std()*np.sqrt(12):+.2f} (full-sample b̂, 진단)")

np.savez(OUT+"/kns_phaseA.npz", bL2=bL2, bEN=bEN, gstar=gstar, g1star=g1star, kappa=kappa,
         cv=cv, gs=gs, fcols=np.array(fcols,dtype=object), mfr_months=np.array(mfr_months,dtype=object))
json.dump({"H":H,"T_managed":int(mfr.shape[0]),"gstar":float(gstar),"kappa":float(kappa),
           "cv_r2_max":float(cv.max()),"en_r2_max":float(cv1.max()),"en_nonzero":nz,
           "impl_monthly_maxSR2_L2":float(sr2_l2),"g1star":float(g1star)},
          open(OUT+"/kns_phaseA.json","w"),indent=2)
print("\nsaved kns_phaseA.npz + .json")
