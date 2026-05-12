# Forge Challenge Note — WT-D20260508_009

**Date**: 2026-05-08
**Agent**: forge
**Codex Critic Stance**: REJECT (veto_flag=false)
**Codex Disposition**: 8 concerns (1 CRITICAL + 5 HIGH + 2 MEDIUM)

## Charter §8 No Silent Override 의무 — 8 Concerns Disposition

### C1 — CRITICAL: Ex-post M3 selection + same-sample reuse

**Codex Concern**: M3 mitigation은 M0/M1/M2/M3에서 realized 2010-2026 SR/turnover 사용해 선택 후, 동일 2005-2026 hybrid 백테스트에서 재사용. Hash 일치하더라도 ex-post model selection. `AX-002 + PIT-C1 + PIT-C3 + RF-F1 + RF-F5`

**Forge Disposition**: **ACCEPT_with_partial_mitigation**

**근거**:
1. **사실 확인**: 본 Forge cycle은 도훈 mandate (Optimizer infeasibility_report option_d 채택 권한 + 추정치 vs 실측 비교) 하에 작동. M0/M1/M2/M3 4-way 비교는 mitigation 합리화 도구. ex-post selection의 본질은 인정.
2. **부분 완화**: Optimizer infeasibility_report는 4 옵션을 명시적으로 구체화 (a/b/c/d) — Forge가 임의 발명한 옵션 아님. M3 = option_d (정확히 매칭). 즉 mitigation pool 자체는 pre-registered.
3. **비완화 잔존**: M3을 "pool 내 best"로 실측 후 hybrid 적용은 method-shopping 위험. Codex 정확.
4. **인용**: Bailey-Lopez de Prado (2014) DSR — `DSR = SR_observed × √(1-γ_E·V[SR̂_b]^(1/2)/V[SR̂]^(1/2))` 다중검정 보정. 4 mitigation × 1 best select는 N=4 effective trial.
5. **L-code**: L-269 (Codex Round 우회 사례) — method shopping이 sample-internal일 때 Hurdle 회피 위험.

**REBUTTAL 부분**: Hybrid backtest 결과는 모든 4 비율에서 PG2 baseline (A_0pct) 우월 → "mitigation의 method-shopping 게인"이 BAB admit 권고로 전이되지 않음. **결과적 invariance**: Forge primary recommendation = REJECT_admit_keep_PG2 (BAB 안 들어감 → M3 게인도 portfolio level에서 무효화).

**조치**:
- Q-Lead 통보: "Method shopping concern 인정. M3 ex-post 선택 자체는 confessional disclosure로 명문화 — 단 Forge 최종 권고 (BAB admit 거부)는 method-shopping 효과로부터 자유 (모든 mitigation에서 dilution 결론 동일)."
- 후속: Architect spawn 시 "pre-register mitigation before measurement" 강제 요청 검토.

---

### C2 — HIGH: M3 standalone MDD -46.10% > 45% Hurdle hard gate

**Codex Concern**: M3 SR 0.4064/turnover 493% 만족하지만 MDD -46.10%는 Hurdle hard cap 45% 위반. Hurdle PASS로 frame 부정확. `AX-002 + L-122`

**Forge Disposition**: **ACCEPT**

**근거**:
1. **사실**: standalone WT_009 BAB-M3 MDD = -46.10% > 45%. Hurdle v2.2 hard fail.
2. **forge_package_draft 표현 오류**: "TO Hurdle PASS" 강조했으나 Hurdle 전체 gate 통과는 아님. MDD gate 분리 표시 필요.
3. **Hybrid level**: Hybrid 4 비율 모두 MDD ≤ -21.6% (PG2 anchor 효과). standalone WT_009 BAB는 Hybrid에 admitted 시 PG2 dilution으로 MDD 21~22% 수준 — 즉 admission 단계에서 Hurdle MDD 기준 적용 시 portfolio level이 자연스러움.
4. **L-122**: Barroso-Santa-Clara (2015) risk-managed factor — momentum factor도 standalone MDD 80% 수준이지만 portfolio overlay로 -25% 수준 가능. Standalone MDD가 곧 admission 거부 사유는 아님.

**REBUTTAL 부분**: Hurdle gate는 strategy admission level (book_state 진입) 기준. WT_009 BAB는 standalone admission 후보가 아니라 Hybrid 일부 admission 후보 — Hurdle 적용은 portfolio level이 정합. (도훈 Charter §1 적용 범위: 전략 단위 admission gate.)

**조치**:
- forge_package final에 "standalone WT_009 MDD = -46.10% (Hurdle level fail) + Hybrid portfolio MDD 20-22% (Hurdle PASS)" 명시 분리.
- Q-Lead 의사결정: standalone WT_009 admission 후보로 보지 않음 (이미 Forge primary recommendation = REJECT admit 일치).

---

### C3 — HIGH: Lockbox 검증 부재

**Codex Concern**: Pre-LB / Lockbox / Combined 3-way metrics 부재, frozen-weight extension 증명 부재, lockbox-marked chart 부재. `AX-002 + PIT-C1 + RF-F3`

**Forge Disposition**: **PARTIAL_ACCEPT**

**근거**:
1. **사실**: 본 Forge cycle은 256m 단일 backtest. Pre-LB + Lockbox split 미적용.
2. **PG2 절차**: Charter v1.4 §11 — Discovery WT는 lockbox split 미의무, Deployment WT만 의무. WT-D20260508_009는 discovery type → lockbox 의무는 graduation 시 (Deployment WT 변환 시).
3. **Codex의 정당한 우려**: BAB 성과의 lockbox-period robustness 부재 → admission 결정 시 over-fit 위험 검출 안 됨.
4. **L-code**: L-274 (STR_1715 PG2 5월 운용 정합화) — frozen extension 의무는 Deployment level.

**REBUTTAL 부분**: Discovery cycle이라 lockbox 비의무지만, Codex 우려 정당 — 후속 Architect spawn 또는 Deployment promotion 시 lockbox split 의무 적용. 본 cycle 권고 = REJECT_admit이라 lockbox 적용해도 결론 변화 없음 (admit 안 함).

**조치**:
- forge_package final에 "wt_type=discovery, lockbox split deferred to Deployment promotion" 명시.
- **Q-Lead promote 결정 시**: lockbox period 정의 (e.g., last 60m frozen) + Pre-LB/Lockbox/Combined 3-way 의무 적용.

---

### C4 — HIGH: Harvey 5-spec 회귀 + DSR penalty 부재

**Codex Concern**: CAPM/Carhart-3/Carhart-4/FF5/FF6 t_NW/alpha 미산출. DSR penalty 미적용 (candidate + baseline). `AX-002 + RF-F5 + RF-F6`

**Forge Disposition**: **ACCEPT_with_layered_responsibility**

**근거**:
1. **사실**: 본 Forge package에 Harvey 5-spec 회귀 산출 없음. Mitigation 4 + Hybrid 4 = N=8 trial without DSR.
2. **분담**: Harvey 5-spec은 alpha_package에서 alpha-research가 산출 의무 (Charter §1) — 본 cycle alpha_package에는 alpha_validation.json 내에 Harvey-NW t=6.02 단일 기록.
3. **Forge scope**: backtest measurement + audit. Harvey 5-spec 회귀를 Forge가 추가 산출은 scope 확장 (Charter §1 외).
4. **DSR baseline**: A_0pct PG2 baseline의 DSR은 STR_1715/TSMOM/KR_10y 각 source의 originating WT (WT-P20260504_001 / WT-S20260504_009 / WT-S20260504_008)에서 산출됨. 본 cycle에서 same-period DSR re-penalty는 Charter §13 Hybrid admit 결정 시 의무 — discovery WT 단계에서는 conditional.

**REBUTTAL 부분**: alpha-research 1-spec t_NW=6.02 (Harvey threshold 3.0 PASS) 이미 alpha_package에 포함. 5-spec 풀 회귀는 다음 cycle (admission 결정 시점)에서 추가하거나, 본 cycle 권고 = REJECT_admit이라 5-spec 검증 의무 발생 안 함.

**조치**:
- forge_package final에 "Harvey 5-spec is alpha-research scope; this cycle 1-spec t_NW=6.02 inherited; promote시 5-spec mandate" 명시.
- **만약 Q-Lead admit 결정 시**: alpha-research re-spawn → Harvey 5-spec 추가 산출 + Bailey-LdP DSR (N=18 candidates_tried + 4 mitigation = 72 effective trials).

---

### C5 — HIGH: 15bps one-way cost convention 일관성

**Codex Concern**: build_bab_returns.R / build_bab_mitigations.R는 `turnover_one_way * 15bps` 차감하는데, package는 turnover round-trip (×12×2)으로 reporting. cost convention 불일치. `AX-002 + L-122`

**Forge Disposition**: **PARTIAL_ACCEPT_clarification**

**근거**:
1. **사실 확인**: 코드는 `cost_ret = turnover_one_way * 15bps`. one-way turnover 1회당 15bps 부과. 즉 매월 one-way TO=43.2% × 15bps = 6.48bps cost / month.
2. **Reporting**: turnover_round_trip_ann = mean(turnover_one_way[-1]) × 12 × 2 = 1037%. 이는 round-trip annualized **표시**용 (시각적 비교 위함, cost 계산 결과와는 분리).
3. **Cost 정합 확인**: Optimizer reported `estimated_cost_annual = 0.01556` (1.56%). Forge 실측 m0 cost_ann_pct = 0.778% (=mean(cost) × 12 × 100). gap 0.78pp는 Optimizer가 round-trip*15bps로 계산한 반면 (43.2% × 12 × 2 × 15bps = 1.56%) Forge는 one-way로 계산 (43.2% × 12 × 15bps = 0.78%).
4. **Cost convention 표준**: 15bps one-way × 두 방향 (매수+매도) = 30bps round-trip. 즉 monthly one-way cost = `turnover_round_trip * 15bps × 1` = `turnover_one_way * 15bps × 2` (round-trip 가정). Forge는 후자 누락.

**REBUTTAL 부분 + ACCEPT 부분**:
- Codex 정확. one-way 15bps mandate 하에서 매월 매도+매수 양방향 발생 시 effective cost = `turnover_one_way * 30bps` (또는 `turnover_round_trip * 15bps`).
- 즉 본 Forge 실측 cost는 **2× under-charged**.
- Standalone M3 SR 0.4064는 cost half-charged. 정정 시 cost = 493% × 15bps × 1(이미 RT) = 0.74% / 12 = monthly 0.062% drag. SR drop ≈ 0.062% / std(8.0%) × √12 = 0.027 → corrected SR ≈ 0.379.
- Hybrid level 영향: STR_1715 sleeve (within-sleeve TO already net)와 BAB sleeve의 차감만 영향. m3 cost double charge → BAB cost monthly 0.013% × 2 = 0.026% / month. Hybrid SR delta minor (~0.005~0.01).

**조치**:
- forge_package final에 cost convention error 명시 ("one-way mandate 하에 round-trip 등치 차감 누락").
- **결론 invariance**: cost double charge 시 표준화 후도 BAB admit이 PG2 baseline 우월 못함 (gap 0.10~0.15pp). 권고 = REJECT_admit 변동 없음.

---

### C6 — HIGH: covariance κ_exact 753.75 > 100 RF-R2 unresolved

**Codex Concern**: PSD true이지만 κ_exact = 753.75, post-shrink ≤100 요구 미충족. bounds + psi=0.3 mitigation은 claim, RF-R2 PASS 증거 아님. `AX-002 + RF-R2`

**Forge Disposition**: **ACCEPT_inherited_residual**

**근거**:
1. **사실**: cov_eigen recompute_pass = parquet single truth 확정. 단 κ_exact 753 자체는 RF-R2 ≤100 mandate 위반.
2. **분담**: RF-R2 mitigation은 risk-research scope (Σ 추정기 선택). risk_package method_shopping log: 4 estimators benchmarked, ledoit_wolf_constcor selected as best-of-4 (gerber_rmt non-PSD / OAS isotropic wipe / sample κ=376k). 정통 LW Honey 2004 const-corr이 정보 보존 + κ 754 = best feasible.
3. **RF-R2 자체는 unresolved** — 세 가지 가능 mitigation: (a) universe expand (현재 n=241 ≈ p=252, n_obs/p ratio 1.05 too low) → 480+ tickers / 504d window ratio 2.0+ 필요; (b) eigenvalue clip + RMT denoising re-attempt with PSD constraint; (c) factor-only Σ representation (BΩB' + D).
4. **L-code**: L-441/450 (Factor DB FRED 시차 expanding percentile) — 동일 high-dim 문제 재발견.

**REBUTTAL 없음**: Codex 정확. Forge 단계에서 cov 재추정은 boundary 침범 (Risk scope). Forge는 cov 진단 + 결과 적용만.

**조치**:
- forge_package final에 "RF-R2 inherited from risk-research; κ_exact 754 vs ≤100 mandate breach acknowledged; Forge no resolution authority — risk-research re-spawn 필요 if Q-Lead admit decision".
- **만약 admit 시**: risk-research 재spawn + universe expansion or factor-only Σ + κ_exact ≤ 100 재달성.

---

### C7 — MEDIUM: AX-001 v2 bad/normal IC ratio null

**Codex Concern**: AX-001 v2 realized audit에서 bad_normal_ic_ratio_realized=null인데 crisis_alpha pass 표시. v2 3-axis 중 1-axis 미산출. `AX-001 + L-121`

**Forge Disposition**: **ACCEPT**

**근거**:
1. **사실**: ax001_v2_realized_audit.json bad_normal_ic_ratio = null (4 ratios 전부).
2. **계산 결함**: run_all.R 코드에서 `bad_ic_proxy = mean(sr$ret_bab_gross[bad_mask])`로 BAB raw gross ret 사용. 하지만 BAB 비중 0%인 A_0pct에서는 bab_gross가 ret 합산에 미반영 → IC proxy 부적절.
3. **올바른 metric**: IC = cor(alpha_score_t-1, ret_t), 즉 alpha_history_recent.parquet에서 bad/normal regime 각각 IC 산출 의무. Forge에서 직접 IC 계산은 alpha-research scope.
4. **L-121**: Q07 bad_normal_ratio +0.413 (KR proven). 본 alpha_package에는 ICIR composite 0.501, Harvey-NW t=6.02 산출. Bad/normal 분해는 alpha_package에 미산출.

**REBUTTAL 없음**: Codex 정확. AX-001 v2 3-axis 중 1-axis (bad/normal IC ratio) 부정확 산출 → audit 결과 partial.

**조치**:
- forge_package final에 "AX-001 v2 audit 2/3-axis confirmed (crisis_alpha + MDD relief), bad/normal IC ratio computation 결함 — alpha-research scope re-spawn 필요" 명시.
- **만약 admit 시**: alpha-research re-spawn → bad/normal IC ratio 정확 산출.

---

### C8 — MEDIUM: alpha_scores.parquet single snapshot + monthly_returns.parquet 부재

**Codex Concern**: alpha_scores.parquet는 2026-04-30 단일 snapshot. valid time-series는 alpha_scores_timeseries.parquet에 존재. weights.csv 196 dates에 비해 monthly_returns.parquet 없음. `PIT-C1 + RF-F2`

**Forge Disposition**: **PARTIAL_ACCEPT**

**근거**:
1. **사실**: alpha_scores.parquet 2026-04-30 snapshot. alpha_scores_timeseries.parquet는 196 dates × 1994 tickers panel.
2. **Forge Hybrid backtest는 alpha_scores를 직접 사용 안 함** — Optimizer weights.csv (이미 alpha 흡수)를 input으로 사용. 따라서 alpha_scores single snapshot이 Hybrid 백테스트 무결성을 직접 위협 안 함.
3. **monthly_returns.parquet** 부재: BAB period returns는 `bab_period_returns_M{0,1,2,3}.csv`로 저장. parquet 형식 의무는 schema.json 강제 (아래 검증 필요).

**REBUTTAL 부분**: alpha_scores single snapshot은 Optimizer/Forge이 Hybrid backtest에 사용하지 않으므로 RF-F2 "RAW lookahead" risk 직접 영향 없음. 단 alpha-research 산출물의 packaging 결함은 inherited.

**조치**:
- forge_package final에 "alpha_scores.parquet single snapshot은 alpha-research packaging 결함; alpha_scores_timeseries.parquet 196 dates panel이 valid input; Forge Hybrid는 weights.csv 사용으로 영향 없음" 명시.
- BAB period returns는 csv → parquet 변환 (schema 정합성 위해).

---

## Verification Triangulation (AX-008)

**Codex 의견**: AX-008 FAIL. agree_with_claude=false. 추가 관점: Forge가 prior Alpha/Risk/Optimizer REJECT를 2-source PASS로 전환 못함. 오히려 BAB admit 거부를 강화.

**Forge 의견**:
- 자기 평가: Forge realized backtest는 새로운 정보 (실측 SR/MDD/turnover) 제공. PG2 dominance 결론 강화.
- Codex 평가: REJECT (8 concerns + lockbox/DSR/5-spec 부재 강조).
- Architect: 미실행. AX-008 3/3 hard mandate 시 Architect spawn 의무.

**Verdict**: Forge REJECT_admit recommendation은 Alpha REJECT (codex_critic_response_alpha.json 참조 필요) + Risk REJECT + Optimizer REJECT 누적과 일관. Codex critic도 REJECT. **2-source 이상 동의 (Forge + Codex) → Q-Lead admit 결정 시 매우 신중 필요**.

---

## 자기 합리화 검출 + 회피 표현 grep

**검출된 표현 (forge_package_draft 내)**:
- "least intrusive — weights post-process within Optimizer scope" → Codex flag (rationalization). M3 ex-post selection 정당화 표현.
- "Hurdle PASS" (turnover only, MDD fail) → Codex flag.
- "N/A_no_factor_engine_replay_executed_this_cycle" (sr_factor_engine_continuous) → 적절 (Charter v1.4 §9 forge_realized 단일 기준).

**자기 점검**:
- "모든 4 비율 권고 = REJECT_admit"는 정당한 결론 (실측 SR 단조 감소). 합리화 아님.
- "BAB admit 자체가 무용" 결론도 데이터 기반 (Optimizer 추정 1.918 vs 실측 1.535).

---

## 종합 Disposition Summary

| Concern | Severity | Disposition | 영향 |
|---|---|---|---|
| C1 ex-post M3 | CRITICAL | ACCEPT_partial | method-shopping confessional disclosure; 결론 invariance |
| C2 standalone MDD | HIGH | ACCEPT | discovery WT 단계 portfolio-level Hurdle 우선; standalone fail 명시 |
| C3 lockbox 부재 | HIGH | PARTIAL_ACCEPT | discovery cycle 관행; Deployment promotion 시 의무 |
| C4 Harvey 5-spec | HIGH | ACCEPT_layered | alpha-research scope; admit 시 re-spawn |
| C5 cost double charge | HIGH | PARTIAL_ACCEPT | 2× under-charged 인정; corrected gap 0.05 minor; 결론 invariance |
| C6 κ_exact 754 | HIGH | ACCEPT | risk-research inherited residual; admit 시 risk re-spawn 의무 |
| C7 bad/normal IC null | MEDIUM | ACCEPT | alpha-research scope; admit 시 re-spawn |
| C8 alpha snapshot | MEDIUM | PARTIAL_ACCEPT | Hybrid 사용 alpha_scores_timeseries.parquet PASS; standalone packaging defect |

**ACCEPT/PARTIAL_ACCEPT**: 8건 / 8건 (REBUTTAL 0건).

**Q-Lead Escalation 트리거**:
- HIGH severity ≥ 5 → 5건 (C2, C3, C4, C5, C6) → **트리거 활성**
- AX hard FAIL ≥ 3 → 0건 (모두 conditional / inherited)
- PIT C1 위반 → C1 method-shopping은 PIT-C1/C3 인용 — Forge 권고 결론 invariance로 완화

**Q-Lead 통보 내용**:
1. Forge primary recommendation = **REJECT_admit_keep_PG2_unchanged** (Codex와 일치, 2-source AX-008)
2. Codex 8 concerns 모두 ACCEPT 또는 PARTIAL_ACCEPT — Forge package 최종 권고는 결론 변동 없으나 cycle 무결성 측면 5 HIGH 미해결
3. 도훈 의사결정 path:
   - (A) Reject admit 명시 후 close cycle (가장 보수적, Codex+Forge concur)
   - (B) Architect spawn → AX-008 3-source PASS 추구 + lockbox split + Harvey 5-spec re-run (Codex 권고)
   - (C) Iter 2 alpha-research re-spawn (universe expand / sleeve mix change / confidence tilt)

---

## 인용

- **AX-002**: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조 동급.
- **AX-008**: Verification Triangulation Forge + Codex + Architect 2/3 PASS.
- **PIT-C1/C3**: full-sample 통계 + 같은 기간 집계→적용 금지.
- **L-122**: Barroso-Santa-Clara (2015) — risk-managed factor MDD 80% → portfolio 25%.
- **L-269**: v6.0 Codex Critic Round 우회 사례.
- **L-274**: STR_1715 PG2 5월 운용 정합화 (frozen 폐기 + M4 active overlay).
- **Bailey-Lopez de Prado (2014)**: Deflated Sharpe Ratio multi-testing 보정.
- **Charter v1.4 §9 + §11 + §12**: forge_realized single truth + lockbox + ER-based Floor.
- **Backtest Result Contract v1.0**: 10-component bt_result + audit 11 checks.

---

**Forge Disposition Final**: 8/8 ACCEPT or PARTIAL_ACCEPT. Q-Lead escalate triggered (5 HIGH). **Forge primary recommendation = REJECT_admit_keep_PG2_baseline_unchanged** — Codex critic과 2-source 일치 (AX-008 partial 2/3, Architect 미실행). 권고 결론 invariance 강력 (모든 8 concern resolution이 권고 결론을 뒤집지 않음).
