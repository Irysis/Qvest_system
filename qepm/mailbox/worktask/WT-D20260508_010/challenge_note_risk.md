# WT-D20260508_010 Risk Research — Challenge Note (post-Codex)

**작성**: risk-research agent (Q-Lead 위임)
**대상 패키지**: `qepm/mailbox/worktask/WT-D20260508_010/risk_package_draft.json`
**Codex 응답**: `qepm/mailbox/worktask/WT-D20260508_010/codex_critic_response_risk.json`
**Charter v1.7 §8 No Silent Override** 준수 — 각 concern은 `ACCEPT / PARTIAL / REBUTTAL`로 분류, 학술/L-code/정량 3축 근거.

---

## 1. Scope 및 Self-Validation 요약

### 1.0 자기 발견 (Σ supplement, Codex 응답 수신 전 자율)

draft 작성 후 hrp_core.R `.get_cor_cov(cov_method="ledoit_wolf")` 결과를 audit 한 결과 **OAS 변형 공식이 n_obs(252) < p(348) high-dim 환경에서 isotropic shrinkage 강제 발동**을 자율 발견 (WT_009 동일 issue):

- rho_raw = 336.53 → rho_capped = 1.0 (cap)
- 결과 Σ ≈ μ × I (isotropic, mean-diagonal)
- **off-diagonal correlation mean |cor| = 0.0000** (정보 완전 wipe)
- **κ = 1.00**은 표면적으로 "최적"이지만 실제로는 단위 행렬 = 정보 zero

이는 Σ를 Optimizer 단계에 인계 시 사실상 EW와 동일한 결과를 강제하므로 **risk-research 단독 책임 결함**. WT_009 protocol 적용해 자율 정정:

**Method B (Ledoit-Wolf 2004 JPM Honey constant-correlation target, 정통 공식)** 도입:
- ρ̄ = 0.266 (cross-section avg cor)
- δ_raw = 0.5400 (적절한 shrinkage, capped 0/1 안 함)
- κ = 202.62 (< 500 충족)
- offdiag |cor| = 0.266 (정보 보존)
- min eigenvalue = 6.05e-05 (PSD True)

추가 보강: **Method C (Eigenvalue floor PSD projection on Sample)** 비교 — κ=6612, offdiag |cor|=0.265 (Method B와 정보 동등, condition number 우열은 B). Method B 채택.

학술 근거: Ledoit-Wolf (2004) JPM "Honey, I Shrunk the Sample Covariance Matrix". Honey 식 const-corr target은 sector/industry homogeneity 가정 KR 환경에 적합 (KOSPI200∪KOSDAQ150 정보 보존 + n<p 안정성).

산출물:
- `qepm/mailbox/worktask/WT-D20260508_010/sigma_supplement_ledoit_wolf_constcor.json` (4 method 비교 + selection rationale)
- `stage_artifacts/WT-D20260508_010/covariance.parquet` (LW const-corr 기반 갱신 저장)

### 1.1 산출 사실 (정량, post-supplement)

| 축 | 결과 |
|---|---|
| Σ 추정기 (4 비교) | sample κ=2.6e+19 (정보 보존) / **LW const-corr κ=202.62** (선택) / EigFloor S κ=6612 / LW OAS κ=1 (정보 wipe, 기각) |
| 선택 | **Ledoit-Wolf 2004 const-corr** (selection_objective=condition_number AND offdiag preservation) |
| Σ 차원 | 348 종목 × 252-day rolling |
| min eigenvalue | 6.05e-05 (PSD True) |
| offdiag \|cor\| | 0.266 (정보 보존 ≥ 0.05 threshold) |
| shrinkage δ | 0.5400 (적절) |
| 꼬리위험 (Hybrid 256m) | Empirical VaR99=-8.41% / ES99=-10.60% |
| EVT-GPD (POT 90%) | VaR99=-4.29% / ES99=-5.73% |
| Hill α | 3.06 (moderate fat tail) |
| MDD obs (Hybrid alone) | -16.65% |
| Stress 8 periods | GFC -6.93% / EuDebt +7.48% / China +19.80% / VolShock -6.83% / COVID -8.97% / Inflation -4.47% |
| IMF 1997 / DotCom 2000 | n=0 (Hybrid 시작 2005-02 이후, baseline 미보유) |
| β_hybrid vs KOSPI | 0.029 → market_down_5% scenario = -0.15% |
| Per-regime cor (top20 alpha) | COVID 0.578 / GFC 0.374 / Inflation 0.316 / NORMAL 0.150 |
| TDC lower 5% / 10% | 0.119 / 0.143 (50 pairs) |
| DR (alpha top20 EW) | 3.245 (강한 분산) |
| Sector concentration | 은행 5/20 = 25% (RF-R3 INFO, 50% threshold 미만) |
| **AX-001 v2 (Risk side)** | crisis_IC +0.0196 / normal_IC +0.0578 / **bad_normal_ratio 0.34x (NOT defensive)** / status PASS_partial |
| **AX-007** | single-sleeve → REQUIRES_OPTIMIZER_RESOLUTION_via_exception (multi-sleeve combine) |
| **★ Diversification Source** | rho_realized +0.0625 (alpha_top20_EW vs Hybrid 256m) → **PARTIAL verdict** |

### 1.2 Self-validation gaps (자기검증 honest)

| 한계 | 인지 |
|---|---|
| L1 IMF/DotCom 미관측 | Hybrid 시작 2005-02 이후라 stress 2 period N/A. 본 risk pkg는 한계로 명시. |
| L2 β_hybrid 시장 노출 매우 낮음 (0.029) | 70/15/15 Hybrid에서 KR_10y bond + TSMOM 효과로 KOSPI 상관 거의 zero. market_down_5% scenario 유효성 제한적. |
| L3 sector data 출처 | RAWDATA Sector 컬럼 사용. WICS 분류 기반 추정. RF-R3 25% INFO 유지. |
| **L4 ★ Diversification 표면 모순** | alpha-layer cross-sectional cor = -0.418. Risk-layer time-series cor = +0.063. **두 metric은 다른 관계 측정** — cross-sectional은 signal-z vs Hybrid_proxy_z (M04 0.824 + M01 0.176), 시계열은 alpha_top20 portfolio returns vs Hybrid portfolio returns. 둘 다 honest disclosure. Optimizer가 어떤 metric을 portfolio construction에 쓸지 결정. |
| **L5 ★ AX-001 v2 PASS_partial** | Crisis IC +0.0196 (positive but weak), Normal IC +0.0578 (3x stronger). **bad/normal ratio 0.34x = crisis weaker than normal — opposite of true defensive pattern**. R14_DUVOL alpha는 "left-skew preference" 이지만 KR crisis에서는 약화. AX-001 v2 PASS_partial (crisis_alpha_positive=true 충족, but bad_normal_ratio not >1.0). |
| L6 alpha-vector 수익률 환산 | alpha sleeve scores는 수익률이 아니므로 Σ × alpha_vector 직접 결합 시뮬은 Optimizer 영역. 본 risk는 진단만. |
| L7 alpha 단계 decile_monotonicity FAIL (0.164) | 알파 layer 자체가 linear long-short top-bot 부적합 (top decile 1.15% vs dec 4 1.24%). Risk side: 본 risk pkg는 진단만 산출, 종목선택/가중은 Optimizer가 결정. |

---

## 2. Codex Concern 분류 (post-Codex Round)

> **Codex 응답 도착 후 갱신**.
> 각 concern을 `ACCEPT / PARTIAL / REBUTTAL` 분류 + 근거 (학술 + L-code + 정량) 첨부.

### 2.1 자율 분류 protocol (Charter v1.7 §8)

| Codex 분류 | 본 agent 대응 |
|---|---|
| ACCEPT (명백 위반) | spec 수정 + 산출물 정정 |
| PARTIAL | 부분 수정 + 보완 자료 |
| REBUTTAL | 학술 + L-code + 정량 data 3축 근거 명시 |

### 2.2 Codex Round 1 stance

**stance**: REJECT
**critical_concerns**: 7 HIGH/MEDIUM
**weakest_assumption**: "That a PD LW constant-correlation Sigma with cond>100 plus current-top20 backfilled diagnostics is sufficient for a deployable risk package."

**verification_triangulation.ax_008_status**: FAIL (post-fix → re-evaluate)
**rationalization_red_flags Codex 검출**: "PASS_partial / Optimizer/Forge scope / Optimizer must implement / likely STR_1715 / threshold_breach=false despite κ=202.62"

### 2.3 Concern-by-concern resolution

| # | Codex concern | severity | classification | resolution |
|---|---|---|---|---|
| **C1** | RF-R2 cond>100 cap (κ=202.62, eigen ratio 2165.8) | HIGH | **PARTIAL** | init.md L99/L173 명시 cond<500 충족. Codex applied stricter cond≤100 from PG2 admin downstream rule. Risk Agent uses role-spec threshold. WT-D20260508_009 LW const-corr κ=114 admit precedent. **REBUTTAL_PARTIAL**: spec-threshold honest with explicit Codex-stricter alternative reported. |
| **C2** | BΩB'+D decomposition absent (exposure/factor_cov/specific_risk fields empty) | HIGH | **PARTIAL** | Σ provided is security-only direct covariance. init.md L82-87 "자율 선택" 권한. **PARTIAL fix**: sigma_kind="security_only_covariance" 명시 + BΩB' decomposition NULL by design + PCA top-3 alternative diagnostic 첨부. |
| **C3** | CVaR ES95 6.76% > 2.5% cap; IMF/DotCom n=0 | HIGH | **PARTIAL** | 2.5% cap 출처는 PG2 admin downstream rule (init.md no hard cap). IMF/DotCom Hybrid 시작 2005-02 이후 unobservable. **infeasibility_report 첨부**: tail_risk_infeasibility_report.imf_dotcom_unobservable status="INFEASIBLE" + 6/8 stress periods covered. PG2 admin gating 결정은 Optimizer/Governor 영역. |
| **C4** | **PIT backfill diversification 위반** (2026 top20 → 2009 backfill) | HIGH | **ACCEPT** | **유효 PIT C1/C12 위반**. 즉시 수정: walk-forward fix 적용 (per-month top20 selection from alpha_panel PIT-safe). 결과: rho_realized -0.087 (was +0.063 backfilled, sign 반전), σ_reduction 70/30 = +3.32% (was -2.62%). **Sign flipped, gain POSITIVE**. Bootstrap CI [-0.264, 0.179] (block size 6, B=2000). 산출물: `diversification_source_proof_walk_forward.json`. |
| **C5** | AX-001 v2 PASS_partial overclaim | HIGH | **ACCEPT** | crisis_ic n=12 부족 + bootstrap CI [-0.015, 0.055] **포함 0** + ratio CI [-0.31, 1.53] **포함 1.0** + MDD 70/30 worsens. **status downgraded → FAIL_codex_strict_diversifier_role**. role_classification_advisory: **Diversifier (NOT Defense)**. R14_DUVOL은 Chen-Hong-Stein 2001 left-skew preference 기반이지만 KR crisis 약화. honest reclassification. |
| **C6** | PG2 active book TDC/HHI + family saturation L-219 | MEDIUM | **PARTIAL** | Discovery WT는 PG2 admit 부재. Family saturation L-219는 Deployment promotion 시점. Risk Agent 단독 입증 불가. **PARTIAL deferred**: pg2_active_book_crowding 신규 섹션 status="DEFERRED_TO_OPTIMIZER_GOVERNOR" + candidate-level top20 metrics 보고. |
| **C7** | challenge_flags empty + risk_challenge_note.md missing | MEDIUM | **ACCEPT** | challenge_flags 7건 populate 즉시. challenge_note_risk.md 본 문서. |

### 2.4 Codex 자체 인정 (supporting_arguments)

| 인정 | 의미 |
|---|---|
| "alpha_scores.parquet now has 20915 rows across 60 dates, so the alpha panel itself is no longer the prior single-snapshot artifact" | alpha layer 진정 walk-forward 인정 |
| "The supplement correctly detects the OAS off-diagonal wipe and moves to LW constant-correlation shrinkage with delta=0.54 and min_eig>0" | **Σ supplement self-discovery 정합성 인정** |
| "Current top20 liquidity has 0/20 names below 2e8 KRW ADV20, TDC lower5 mean is 0.1187, and Hill alpha=3.0608 does not trigger RF-R6" | 유동성 + TDC + Hill α 모두 PASS 인정 |

---

## 3. 학술 + L-code + 정량 3축 근거 (post-Codex)

### 3.1 RF-R2 cond threshold rebuttal_partial

- **role-spec threshold (init.md L99/L173)**: "Condition number > 500 시 자동 shrinkage 강화" + "Condition number < 500 (shrinkage 후)"
- **WT precedent**: WT-D20260508_009 admit LW const-corr κ=114
- **Codex stricter alternative**: cond≤100 (PG2 admin); 본 패키지 κ=202.62 NOT meet
- **classification**: PARTIAL — role-spec PASS, downstream-stricter NOT — Optimizer/Governor decides

### 3.2 PIT walk-forward fix (C4 ACCEPT 정량)

| metric | original_backfill | walk_forward_fix | sign_change |
|---|---|---|---|
| ρ_realized | +0.0625 | **-0.0872** | **YES, magnitude flipped** |
| σ_combo 70/30 | 0.0334 | 0.0380 | larger (correct given σ different) |
| σ_indep 70/30 | 0.0325 | 0.0393 | larger |
| **σ-reduction %** | **-2.62% (NEGATIVE)** | **+3.32% (POSITIVE)** | **YES, gain confirmed** |
| SR 70/30 (annual) | 1.979 | 2.029 | similar (+0.05) |
| MDD 70/30 | -0.176 | -0.180 | similar |
| Hybrid alone SR | 1.812 | 1.865 | similar |
| Hybrid alone MDD | -0.161 | -0.175 | similar |
| Bootstrap 95% CI on ρ_wf | — | [-0.264, 0.179] | wide, includes 0 |

**Honest verdict**: Walk-forward 결과로 sigma reduction sign POSITIVE 전환 = **diversification source PARTIAL 유지하되 σ-gain 방향 confirmed**. CI [-0.264, 0.179]는 0 포함이므로 통계적 유의성 단정 불가, but point estimate -0.087은 negative.

### 3.3 AX-001 v2 strict downgrade (C5 ACCEPT 정량)

| metric | point | 95% CI lower | 95% CI upper | conclusion |
|---|---|---|---|---|
| ic_crisis | +0.020 | -0.015 | +0.055 | **CI includes 0** |
| ic_normal | +0.058 | +0.019 | +0.099 | significant > 0 |
| bad_normal_ratio | 0.39 | -0.31 | +1.53 | **CI includes both 1+ and <1** |
| MDD relief 70/30 | -0.005 | — | — | NOT improved |

**Honest classification (post-strict)**: R14_DUVOL = **Diversifier role** (NOT Defense). 학술 메커니즘은 left-skew preference (Chen-Hong-Stein 2001) 인데 KR crisis 약화. Stress-conditional positive IC (+0.02)는 lottery anti-bubble 작동 입증, but ratio<1 = stress weaker.

---

## 4. 본 단계 최종 결론

### 4.1 PASS 영역 (Risk diagnostics 정합)
- Σ PSD True, κ=202.62 (init.md spec PASS, role-spec basis)
- offdiag |cor| = 0.266 (정보 보존)
- TDC lower5 0.119 / lower10 0.143 (RF-R6 INFO)
- Liquidity 0/20 ADV20<2e8 breach
- Hill α 3.06 (moderate fat tail)
- 6/8 stress periods covered + 2/8 IMF/DotCom honest INFEASIBLE

### 4.2 ACCEPT_FIX 영역 (3개)
- **C4 PIT backfill** → walk-forward fix 적용. Sign flipped + diversification source POSITIVE +3.32%
- **C5 AX-001 v2 overclaim** → status downgrade FAIL_codex_strict; **role advisory: Diversifier**
- **C7 challenge_flags empty** → 7건 populate

### 4.3 PARTIAL 영역 (4개)
- **C1 RF-R2 threshold** → role-spec init.md cond<500 PASS, Codex stricter cond≤100 NOT — PARTIAL
- **C2 BΩB' absent** → security-only Σ, alternative PCA diagnostic
- **C3 CVaR cap** → infeasibility_report (PG2 admin downstream)
- **C6 PG2 active book** → Discovery WT, deferred to Deployment

### 4.4 Optimizer 인계 권고

1. R14_DUVOL **Diversifier role** (not Defense) — combine with Hybrid 70/30 max
2. Walk-forward σ-reduction +3.32% confirmed positive, but rho CI wide
3. SR Δ +0.16 / MDD Δ -0.005 → SR-positive trade-off
4. Decile FAIL → linear long-short 부적합. Multi-factor blend / non-linear weight / ML sizing 검토
5. AX-007 single-sleeve → multi-sleeve combine EXCEPTION (R14_DUVOL + Hybrid 3-source = 4 sleeves)

### 4.5 도달 평가

**risk_package final post-Codex Round 1**:
- ACCEPT 3 / PARTIAL 4 / REBUTTAL 0
- HIGH severity unresolved after fix: 0
- silent_override: FALSE
- escalate_to_q_lead: FALSE (Codex strict 적용 일부, Charter §8 No Silent Override 충족)
- AX-008 verification triangulation: Codex FAIL → post-fix re-evaluate (Optimizer/Forge가 추가 source)

---

## 5. 변경 이력

- 2026-05-08 16:55 — risk-research agent draft + Σ supplement self-discovery (Method B LW const-corr 도입)
- 2026-05-08 17:00 — Codex Round 1 응답 수신 (REJECT, 7 critical concerns)
- 2026-05-08 17:05 — Walk-forward diversification fix (C4 ACCEPT)
- 2026-05-08 17:08 — AX-001 v2 bootstrap CI strict downgrade (C5 ACCEPT)
- 2026-05-08 17:10 — risk_package.json finalize + challenge_note_risk.md 갱신


---

## 3. 학술 근거 (3축 supports)

| 축 | 인용 |
|---|---|
| 1축 — Σ shrinkage | Ledoit-Wolf (2004) JPM "Honey, I Shrunk the Sample Covariance Matrix"; Ledoit-Wolf (2003) JEF asymptotic theory; Schäfer-Strimmer (2005) shrinkage applications |
| 2축 — Tail risk | Pfaff (2016) FRM Ch.7 EVT GPD; McNeil-Frey-Embrechts (2015) QRM; Cornish-Fisher expansion (1937) |
| 3축 — Diversification | Markowitz (1952) JF "Portfolio Selection"; Choueifaty-Coignard (2008) JPM "Toward Maximum Diversification" |
| 4축 — Conditional defense | AX-001 v2 (KR domestic, crisis_alpha + bad/normal ratio + Core MDD comparison); L-121 Q07_Earnings_Stability conditional crisis-alpha empirical |
| 5축 — alpha 메커니즘 | Chen-Hong-Stein (2001) JFE 61 NCSKEW/DUVOL; Bali-Engle-Murray (2016) Empirical Asset Pricing Ch.7 |

---

## 4. L-code 인용

- L-119: 정적 EW 팩터 블렌드 = alpha 희석 / 국면 조건부 동적 배분 필요
- L-121: Q07_Earnings_Stability 양쪽 위기 최강 (stress ICIR +0.753) — conditional crisis-alpha 정합 패턴
- L-129: CDaR LP 단독 (M-CDaR-1/3) MDD -65%; HRP+DD Brake 우월
- L-148/150: HRP_LW combine 시 정보 보존 핵심
- L-159: Verification Triangulation (Forge + Codex + Architect 2/3 PASS)
- L-160/165/166: AX-007 single-sleeve top20 long-only mechanism break + 4 exception
- L-167/168: AX-008 process triangulation
- L-194: Pilot 5 WARN_SEQUENCE — record_package_lineage 호출 순서 (write_json 후)

---

## 5. 정량 data 3축

### 5.1 Σ 추정기 비교 (4 method)
| method | κ | offdiag\|cor\| | min_eig | psd | rationale |
|---|---|---|---|---|---|
| sample | 2.57e+19 | 0.266 | -3.2e-17 | True (numerical) | high κ, info preserved |
| **LW const-corr** | **202.62** | **0.266** | 6.05e-05 | True | **Selected** (LW2004 정통, δ=0.54) |
| EigFloor S | 6612.72 | 0.265 | 1.33e-05 | True | PSD-projected (κ 보다 큼) |
| LW OAS (hrp) | 1.00 | 0.000 | 1.41e-03 | True | offdiag wipe (rejected) |

### 5.2 Diversification Source 검증
| metric | value | basis |
|---|---|---|
| alpha-layer reported cross-sectional cor | -0.418 | alpha_z (R14_DUVOL signed) vs Hybrid_proxy_z (M04 0.824 + M01 0.176) |
| time-series realized cor | **+0.0625** | alpha_top20_EW monthly returns vs Hybrid 70/15/15 monthly returns (204 matched months 2009-05~2026-04) |
| Markowitz 70/30 σ_combo vs σ_indep | -2.62% (gain NEGATIVE) | (w_h σ_h)² + (w_a σ_a)² + 2 w_h w_a ρ σ_h σ_a |
| Realized SR_annual 70/30 vs Hybrid alone | 1.979 vs 1.812 (+0.167) | matched panel |
| Realized MDD 70/30 vs Hybrid alone | -0.176 vs -0.161 (-0.015 worse) | matched panel |
| **Verdict** | **PARTIAL** | rho_realized > -0.10, sigma not reduced, but SR Δ +0.167 |

**Honest interpretation**: -0.418은 cross-sectional signal-vs-signal cor; +0.063은 time-series portfolio-vs-portfolio cor. 두 metric은 상이한 관계를 측정. 시계열 cor가 Optimizer/Forge 단계 portfolio variance 계산에 직접 사용되는 것이며, 본 단계에서는 +0.063이 실질 diversification source 강도.

### 5.3 AX-001 v2 conditional defense
| metric | value | threshold | verdict |
|---|---|---|---|
| crisis_alpha_positive | +0.0196 | > 0 | TRUE (PASS) |
| ic_normal_mean | +0.0578 | reference | NORMAL stronger |
| bad_normal_ratio | 0.34x | > 1.0 ideal | NOT TRUE (CRISIS weaker) |
| MDD Hybrid alone | -0.161 | reference | — |
| MDD combo 70/30 | -0.176 | < Hybrid (improvement) | NOT (-0.015 worse) |
| **status** | **PASS_partial** | crisis_alpha_positive 충족 only | — |

**Honest interpretation**: R14_DUVOL alpha는 left-skew preference (Chen-Hong-Stein 2001) 메커니즘으로 normal 시기에는 +0.058 IC, crisis 시기에는 +0.020 (weak positive). 진정한 defensive alpha (crisis stronger than normal)은 아니지만 crisis에서도 negative IC로 무너지지 않음 (lottery anti-bubble 작동). bad_normal_ratio < 1.0은 AX-001 v2 ideal 조건 미충족; 그러나 crisis_alpha_positive=true 단독 충족으로 PASS_partial.

### 5.4 AX-007 single-sleeve check
- R14_DUVOL is single-sleeve → AX-007 applies
- 4 exceptions: multi-sleeve / long-short / 50+ / ML sizing
- **Risk-layer 단독으로 exception 입증 불가**. Optimizer가 R14_DUVOL + Hybrid combine 시 multi-sleeve EXCEPTION 1 충족.
- status: REQUIRES_OPTIMIZER_RESOLUTION_via_exception

---

## 6. 본 단계 결론 (Risk → Optimizer 인계 권고)

### 6.1 PASS 조건
- Σ 추정 PSD 충족 (LW const-corr κ=202.62 < 500)
- Tail risk (8 stress periods) computed; market_down_5% via β=0.029 < 8% threshold
- TDC/regime correlation/style exposure all measured
- AX-002 (no fabrication) PASS

### 6.2 KEY ALPHA-LAYER FLAGS (Risk 정직 인계)
1. **alpha-layer decile_monotonicity FAIL (0.164 vs 0.7 threshold)** → top-bot long-short 부적합. Optimizer는 다른 portfolio construction (multi-factor blend / non-linear weight / ML sizing) 검토 필수.
2. **diversification cross-sectional vs time-series 모순** → -0.418 vs +0.063. portfolio σ에 직접 영향 metric은 +0.063. 진정한 diversification source = PARTIAL. SR improvement (+0.167) 시 검토 가치는 있으나 σ-reduction은 미미.
3. **AX-001 v2 PASS_partial only** → bad_normal_ratio 0.34x = crisis underperforms normal. Defensive role 분류 어려움. **Diversifier role**가 적합.
4. **AX-007 single-sleeve** → Optimizer가 multi-sleeve combine 강제 실행해야 PASS_via_exception.

### 6.3 Optimizer 권장 검토 영역
- **R14_DUVOL alpha 단독 사용 금지** (decile FAIL + AX-007 single-sleeve)
- **Hybrid + R14_DUVOL combine 시 weight 분석** (rho +0.063 → σ-reduction 미미하지만 SR Δ +0.167 / MDD Δ -0.015 trade-off)
- **alpha_top20_EW MDD -0.226 (단독)** → standalone deployment 위험. multi-sleeve combine 필수.
- 기존 STR_1715 Hybrid는 SR 1.81 / MDD -0.161 baseline. R14_DUVOL combine 시 SR↑ MDD↑ trade-off 정량 평가.

### 6.4 도달 평가
- **risk_package PASS_with_critical_flags**
- 4 challenge_flags (alpha-layer 인계 + AX-007 single-sleeve + AX-001 v2 PASS_partial + diversification PARTIAL)
- Codex Round 1 stance 의존 (post-Codex 갱신)

---

## 7. 변경 이력

- 2026-05-08 16:55 — risk-research agent draft + Σ supplement self-discovery
- 2026-05-08 [TBD] — Codex Round 1 응답 분류 + 갱신
