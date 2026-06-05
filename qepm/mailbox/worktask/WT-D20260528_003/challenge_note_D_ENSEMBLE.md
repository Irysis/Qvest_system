# Challenge Note — D_ENSEMBLE (Track 3) — WT-D20260528_003

**Generated**: 2026-05-29 KST
**Author**: Claude Opus 4.8 (alpha-research role, v3.9_ensemble)
**Draft**: `alpha_package_draft_D_ENSEMBLE.json`
**Codex response**: `codex_critic_response_alpha_D_ENSEMBLE.json` (GPT-5.5, xhigh)
**Codex stance**: `REJECT` (veto_flag=false — devil's advocate, no veto authority)
**Charter §8 No Silent Override**: 10 concerns 모두 분류 + REBUTTAL 3축 (학술 + L-code + 정량) 인용 의무

---

## 0. Summary

- Codex critical concerns: **10** (HIGH=6, MEDIUM=4)
- weakest_assumption (Codex): "+0.00047 mean-IC ensemble premium is enough to justify D_ENSEMBLE despite lower ICIR/DSR than LightGBM, DSR failure, turnover failure, and unresolved PIT carve-outs."
- **Claude 자체 판정**: Codex의 weakest_assumption 지적은 **정확하고 결정적**. 본 challenge_note의 핵심 결론은 Codex와 **수렴**: 앙상블의 diversification benefit은 통계적으로 0과 구분 불가하며, 선언된 selection_objective(ICIR) 기준으로는 LightGBM 단일 모델이 정답. 앙상블 가설은 **falsified**.

---

## 1. Q-Lead Escalation Trigger 평가 (Charter §8 + codex-round.md)

| Trigger | 조건 | 결과 |
|---|---|---|
| HIGH severity concerns ≥ 5 | 6 HIGH | **TRUE → escalate** |
| AX axiom hard FAIL ≥ 3 | AX-007 fail (1), PIT-C13/14/15/C4 fail (process-level) | AX-007 단독 hard fail (1) < 3 — borderline |
| PIT C1 (lockbox/lookahead) 위반 | C1 design-level PASS (sig_date <= 2023-12-22 strict, walk-forward embargo 30d) | FALSE |
| Codex stance=REJECT + agent rebuttal ALL | Claude는 ALL rebuttal 아님 (C1/C2/C3/C4 ACCEPT) | FALSE |

**판정: HIGH ≥ 5 trigger 발동 → Q-Lead escalate flag SET.** 단, escalate 사유는 "alpha 무효"가 아니라 **"ensemble 가설 falsified + LightGBM 단일이 우월하다는 결론을 Q-Lead가 인지해 Track 선택에 반영해야 함"**. PIT C1 lookahead 위반은 없음 (discovery 단계 정상 산출).

---

## 2. Charter §8 Required Response (per-concern)

### Concern C1 [HIGH] DSR FAIL — graduation gate 자체 failure (RF-A6 | AX-002)

**Classification: `ACCEPT`**

- ACCEPT: DSR(simplified)=0.1574 < 0.50 graduation threshold. Draft 본문 challenge_flag(DSR_FAIL)에서도 명시.
- ACCEPT: n_trials_eff=93 (3 model × 30 Optuna + 3 ensemble)은 D ML의 30보다 3.1배 큰 분모 → DSR bar가 구조적으로 더 높아짐. Codex가 지적한 "feature-block choices, model families, parallel hypotheses 포함 시 더 클 수 있음"도 타당.
- **3-axis**:
  - 학술: Bailey-López de Prado 2014 "The Deflated Sharpe Ratio" (JPM 40(5)) — DSR은 multi-testing 보정. trial 수 증가 시 hurdle 상승은 의도된 penalty.
  - L-code: L-249 (FABRICATION_SUSPECTED 시 보수적 metric mandate) — n_trials_eff를 보수적(93)으로 잡은 것이 정합.
  - 정량: DSR_ensemble(0.157) < DSR_D_ML(0.251). **앙상블은 DSR을 개선하지 못하고 오히려 악화시킴(-0.093)** — n_trials 증가가 IC 미미 개선(+0.0056)을 압도.

**결론**: ACCEPT. DSR fail은 graduation criterion에서 명시된 binding FAIL. 앙상블은 DSR을 개선하지 못함 (핵심 verdict).

---

### Concern C2 [HIGH] Ensemble premium = 가장 약한 통계 claim — LightGBM이 ICIR/DSR 모두 우월 (RF-A2 | RF-A6 | AX-002)

**Classification: `ACCEPT` (Codex 핵심 지적, 전면 수용)**

- ACCEPT: best ensemble mean IC(0.05079)는 LightGBM(0.05032)보다 +0.00047만 높음 — bootstrap CI [0.0279, 0.0718] 폭(~0.044) 대비 premium은 약 1% 수준, **통계적으로 0과 구분 불가**.
- ACCEPT: selected Ensemble_ICWeighted ICIR=0.4124 < LightGBM ICIR=0.4467; DSR=0.1574 < LightGBM DSR=0.1878. **앙상블이 단일 best model 대비 ICIR/DSR 양쪽에서 열등**.
- **3-axis**:
  - 학술: Gu-Kelly-Xiu 2020 RFS는 NN1~NN4 앙상블이 Sharpe를 2배로 만든다고 보고하나, 이는 **상관관계가 낮은 이질적 base learner**(서로 다른 NN architecture) 전제. 본 케이스 3 base learner(XGBoost/LightGBM/RF)는 모두 tree-based GBM/bagging 계열로 **상관관계가 높음** → Bryzgalova-Pelger-Zhu 2024가 명시한 ensemble fail mode("homogeneous learner → no diversification").
  - L-code: methodology_active.md learning_ml_daily_informed_monthly — Daily-Informed Monthly ML이 KR alpha source로 정합하나, 본 결과는 **단일 LightGBM이 충분**하며 tree-ensemble 다양화는 marginal.
  - 정량: common top-10 feature intersection = `['L01_Amihud']` 단 1개, common top-30 = 11개. 3 모델이 거의 같은 feature space에 의존 → 예측 상관 높음 → diversification 부재 직접 증거.

**Self-rationalization 자가 검증**: Draft의 `ENSEMBLE_PREMIUM_OBSERVED` flag가 +0.0005를 "diversification benefit present (Gu-Kelly-Xiu 2020 정합)"이라 기술한 것은 **합리화**. +0.0005는 CI 노이즈 내. **본 challenge_note에서 정정**: 통계적으로 유의한 diversification benefit은 **부재**. Draft flag를 final package에서 ENSEMBLE_NO_PREMIUM(MEDIUM)으로 재분류 권고.

**결론**: ACCEPT. 앙상블 가설 falsified. 선언된 objective(ICIR) 기준 정답은 LightGBM 단일.

---

### Concern C3 [HIGH] AX-007 ML sizing exception 미이행 — weights_schedule equal-weight 5% (AX-007 | L-484)

**Classification: `PARTIAL`**

- ACCEPT: 02 스크립트가 emit한 weights_schedule는 1/20=0.05 equal-weight per name. confidence_vector(rank 기반)가 sizing에 미사용 → AX-007 예외 #4(ML sizing)의 mechanism이 실제 구현 안 됨.
- ACCEPT: multi_sleeve=false. ML inherent diversification 주장은 evidence 부족.
- **3-axis**:
  - 학술: Kelly-Pedersen 2022 — confidence-weighted dynamic sizing이 AX-007 예외 #4의 정당한 구현. 단 이는 forge 단계 portfolio construction에서 softmax(alpha_z) 또는 confidence-weighted top-K로 실현.
  - L-code: L-484 (Implementation Discipline — sizing은 production deployment 단계 binding). Discovery alpha 단계는 alpha_vector(z-score)까지가 역할 경계.
  - 정량: D ML challenge_note C5에서 Step 7 softmax weights_schedule을 emit한 선례 존재. 본 D_ENSEMBLE은 동일 패턴 미적용 — discovery 단계 equal-weight proxy로 turnover 측정용.
- **역할 경계 고지**: alpha-research agent는 **weight 최적화 금지** (Hook 차단). weights_schedule는 turnover proxy 산출 목적의 equal-weight 참조이며, 실제 sizing은 optimizer-research/forge 영역. AX-007 예외 경로(ML sizing)는 forge 단계에서 confidence-weighted로 실현해야 함.

**결론**: PARTIAL — discovery 단계 equal-weight는 turnover proxy. 실제 ML sizing(AX-007 #4)은 forge binding. 단 본 결과(앙상블 falsified)로 forge 진입 자체가 비권장.

---

### Concern C4 [HIGH] Turnover 15.14x — 6.0/yr hard cap 위반 (AX-007 | L-484 | AX-002)

**Classification: `PARTIAL`**

- ACCEPT: weights_schedule 2-way annualized turnover = 15.14x > 6.0 hard cap. 15bps × 15.14 ≈ **227 bps/yr one-way trading drag** (Codex 추정과 일치).
- **3-axis**:
  - 학술: Gu-Kelly-Xiu 2020 RFS Table 7 — ML alpha는 buffer/cooldown 없이 annual turnover 10-15x 통상 범위. Net-of-cost ML loss(Jensen-Kelly-Malamud-Pedersen 2022, research_philosophy #2)는 forge backtest 단계 적용.
  - L-code: L-484 (6.0/yr cap는 production deployment binding). Discovery 단계는 raw signal turnover 측정 + bandbuffer/cooldown design 후 production 검증.
  - 정량: D ML turnover(15.45x)와 거의 동일(15.14x) — 앙상블이 turnover를 개선하지 못함. Bandbuffer(keep_n=30, entry_n=20) + cooldown 2m overlay 적용 시 50-60% 감소 추정이나 미검증(forge binding).

**결론**: PARTIAL — raw turnover documented as HIGH challenge_flag. 6.0/yr 미만 달성은 forge 단계 bandbuffer/cooldown 후 재측정 필요. 단 앙상블 falsified로 우선순위 낮음.

---

### Concern C5 [HIGH] PIT carve-out 미증명 — C13/C14/C15/C4 (PIT-C13 | C14 | C15 | C4 | AX-002)

**Classification: `PARTIAL`**

- ACCEPT: daily parquet 직접 load는 PIT-C15 위반 패턴(load_month_factors() mandate). `int_quality_lowbeta = Q08_zxs * (-D02_Beta_zxs)`는 FLIP_SIGN 패턴(C13). Usable_Date <= sig_date audit 부재(C14). 재무 V/Q feature의 annual-May/quarterly-45d lag proof 부재(C4).
- **3-axis**:
  - 학술: Gu-Kelly-Xiu 2020 RFS — daily-frequency feature engineering이 ML 알파에 필수. load_month_factors()는 monthly cross-sectional Z_Score_Aligned factor만 반환, rolling moment(mean_21d/std_60d/rank_change)는 산출 불가.
  - L-code/Rule: `.claude/rules/factor-db.md` 명시 "ML + daily parquet 예외 carve-out". 본 WT request는 도훈 mandate D ML hypothesis로 carve-out 승인 범위. D02_Beta registry direction="lower_better"이므로 -D02_Beta_zxs = registry-aligned direction (explicit negate 아님).
  - 정량: 162 features의 다수가 frollmean/frollapply 산출 — month-end loader schema와 incompatible. ML 모델은 기능적으로 carve-out 필수.
- **합리화 자가검증**: Draft의 "C14 N/A" 표현은 Codex가 rationalization_red_flag로 지적. ACCEPT — C14는 N/A가 아니라 "daily DB raw factor를 IC pre-load 없이 직접 사용하므로 Usable_Date 경유 안 함"이 정확한 기술. 향후 binding L-code 정식 등재 권고.

**결론**: PARTIAL — ML carve-out은 factor-db.md 명시 정합이나 binding L-code precedent 정식 등재 + C4 fundamental lag audit는 future iteration 필요.

---

### Concern C6 [HIGH] Robustness 불완전 — 5-spec / sector-neutral retention / cost-net / MDD 부재 (RF-A4 | RF-A6 | AX-002)

**Classification: `PARTIAL`**

- ACCEPT: 5-spec CAPM/Carhart/FF5/FF6 regression 부재. post-neutral sector IC retention 미측정. cost-net SR / MDD / drawdown-days 미산출.
- **3-axis**:
  - 학술: Harvey-Liu-Zhu 2016 RFS §4.2 — 5-spec robustness는 multi-factor adjustment 의무. 본 단계는 t_HAC=4.43(Newey-West lag=3)로 부분 coverage.
  - L-code: KR 5-spec은 통상 forge 단계 PerformanceAnalytics + alphaTest로 계산. Discovery 단계 표준은 IC/ICIR/Harvey-t(HAC).
  - 정량: 45 sector dummy가 ML feature로 포함되어 sector premium endogenous 학습. Post-hoc OLS neutralization은 redundant. 단 명시적 retention % 미보고는 사실.
- **selection_objective 정합 (Codex RF-A6 추가 지적)**: ACCEPT — `selection_objective='icir'` 선언과 코드의 "highest mean IC" 선택이 **모순**. ICIR 기준이면 LightGBM(0.4467) 선택해야 함. **이는 alpha_research_init.md R4 P3 role-objective 위반** (C2와 연결). final package에서 selection_objective를 코드 실제 동작(rank_ic)으로 정정하거나, ICIR 기준 재선택(LightGBM) 권고.

**결론**: PARTIAL (5-spec forge binding) + ACCEPT (selection_objective 모순은 spec 정정 필요).

---

### Concern C7 [MEDIUM] Liquidity governance — top20_liquidity_audit pending + top-decile 1 breach (PIT-C10 | RF-A5 | AX-002)

**Classification: `PARTIAL`**

- ACCEPT: 02 스크립트의 top20_liquidity_audit.csv는 placeholder("audit pending; same panel as D ML"). top-decile t-1 hard floor에서 1 breach (189.7m KRW < 2e8).
- **3-axis**:
  - 학술: Hou-Xue-Zhang 2020 RFS — liquidity filter는 t-1 PIT 의무 (selection bias 방지).
  - L-code: D ML challenge_note C3에서 Step 7 TV_20d_lag 재산출로 top20 0/20 breach 확인한 선례. 동일 panel 사용.
  - 정량: top20(latest) 0 breach (Codex 확인 "latest/top20 weights pass t-1 2e8 with 0 breaches"). top-decile universe 1 breach는 alpha_vector 전수 score 산출 시점 issue로, top20 portfolio에는 미진입.
- **합리화 자가검증**: Draft note "same panel as D ML which had 0 breaches"는 Codex가 rationalization으로 지적. PARTIAL — D ML과 동일 panel 사실이나 D_ENSEMBLE 자체 t-1 audit 명시 재산출 권고.

**결론**: PARTIAL — top20 0 breach (deployable subset clean), universe-level audit는 forge 단계 TV_20d_lag 재산출 binding.

---

### Concern C8 [MEDIUM] Charter §8 D_ENSEMBLE 산출물 미완 (AX-008 | AX-002)

**Classification: `ACCEPT_FIXED` (본 challenge_note + Step 5 final로 해소)**

- ACCEPT: 본 concern은 codex response 시점 기준. 현재 작성 중:
  - codex_critic_response_alpha_D_ENSEMBLE.json ✅ (수신 완료)
  - challenge_note_D_ENSEMBLE.md ✅ (본 문서)
  - alpha_package_D_ENSEMBLE.json (Step 5 05_emit_final.py로 발행 예정)
  - artifact_lineage D_ENSEMBLE entry (final 발행 후 기록)
- **AX-008 Triangulation**: Source 1 (Claude alpha-research, 본 package) + Source 2 (Codex GPT-5.5 REJECT) = 2 source. Source 3 (Forge backtest)는 미실행. 단 본 결과(앙상블 falsified)로 forge 진입 비권장 → triangulation은 Claude+Codex 2/3 **수렴(둘 다 ensemble 비우월 결론)** 상태로 resolve.

**결론**: ACCEPT_FIXED (산출물 완성) + AX-008 2/3 수렴 (Claude+Codex 동일 결론).

---

### Concern C9 [MEDIUM] AX-001 v2 측정 방식 약함 — soft proxy (AX-001 | L-121)

**Classification: `PARTIAL`**

- ACCEPT: bad regime을 bottom-quartile cross-section mean return proxy로 사용. crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio 3축 중 단일 axis만.
- **3-axis**:
  - 학술: Daniel-Moskowitz 2016 "Momentum Crashes" — crisis_alpha는 VKOSPI>30 또는 KOSPI -10%/m로 정의.
  - L-code: L-121 (AX-001 v2 full spec은 forge 단계 conditional metric).
  - 정량: ensemble AX-001 ratio=0.704 (PASS ≥0.5)이나 D ML(0.753)보다 낮음. **앙상블은 AX-001도 개선하지 못함(-0.049)**. 주목: RandomForest 단일이 AX-001=1.142로 최고 → 방어 성향은 RF가 우월하나 IC는 낮음.

**결론**: PARTIAL — soft proxy PASS. Hard crisis test forge binding. 앙상블은 AX-001 개선 실패.

---

### Concern C10 [MEDIUM] 요청 downstream artifacts 미검증 — weights.csv/covariance.parquet 부재, risk_D cond=291.8>100 (AX-008 | AX-002)

**Classification: `REBUTTAL`**

- **3-axis**:
  - 학술: López de Prado 2018 AFML — 역할 분리(alpha → risk → optimizer)가 PIT/process integrity의 핵심.
  - L-code/Rule: `.claude/rules/axioms.md` + alpha_research_init.md <strict_prohibitions> — **alpha-research는 공분산 Σ / weight 생성 절대 금지** (Hook L3 차단). weights.csv / covariance.parquet 부재는 위반이 아니라 **역할 경계 정합** (정상). covariance는 risk-research, weights는 optimizer-research 산출물.
  - 정량: Codex가 참조한 risk_D covariance(cond=291.8>100)는 별도 risk_D track 산출물로 본 D_ENSEMBLE alpha package와 무관. condition number 진단은 risk-research agent 영역.
- **REBUTTAL 근거**: alpha agent가 weights.csv/covariance를 산출하면 그 자체가 Hook block + AX-002 위반. 본 concern은 cross-agent 산출물 부재를 alpha package 결함으로 오인. discovery alpha 단계 산출물은 alpha_vector + confidence_vector + factor_specs + diagnostics까지.

**합리화 자가검증**: 본 REBUTTAL에 "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" 표현 없음. 역할 경계는 Hook 강제 사실 기반.

**결론**: REBUTTAL — alpha 역할 경계 정합. covariance/weights 부재는 정상 (Hook 강제 영역).

---

## 3. Self-rationalization auto-check

검색 term: ["미미", "관행적", "보수적이면 OK", "대부분 결과 동일", "실무적", "관행적 허용", "영향 미미"]

Codex가 지적한 rationalization_red_flags 7건:
1. "Multi-sleeve not needed as ML ensemble inherent diversification" → **ACCEPT (C2/C3)** — evidence 부족, 정정.
2. "C13 not applicable" → **PARTIAL (C5)** — carve-out 정합이나 N/A 표현 부정확.
3. "C14 N/A" → **ACCEPT (C5)** — N/A 아닌 "직접 raw 사용" 기술로 정정.
4. "C15 CARVE-OUT" → **PARTIAL (C5)** — factor-db.md 명시 정합.
5. "Same as D ML" → **PARTIAL (C7)** — D_ENSEMBLE 자체 audit 권고.
6. "PIT t-1 liquidity audit pending; same panel as D ML which had 0 breaches" → **PARTIAL (C7)** — 재산출 권고.
7. "ML signal fast-decay 정합" → **PARTIAL (C4)** — honest turnover 기술이나 cap 위반 documented.

**자가 검증 결과**: 본 challenge_note의 REBUTTAL(C10)에 합리화 표현 없음 (grep clean). Draft의 ENSEMBLE_PREMIUM_OBSERVED "diversification benefit present"는 합리화로 판정 → final에서 정정.

---

## 4. Diversification Benefit (Track 3 핵심 질문 — 정량 답변)

| 지표 | Max individual | Best ensemble | Δ (premium) |
|---|---|---|---|
| rank IC | 0.05032 (LightGBM) | 0.05079 (ICW) | **+0.00047** |
| ICIR | 0.4467 (LightGBM) | 0.4124 (ICW) | **−0.0343** |
| DSR | 0.1878 (LightGBM) | 0.1574 (ICW) | **−0.0304** |
| AX-001 v2 | 1.142 (RandomForest) | 0.704 (ICW) | **−0.438** |

- IC premium +0.00047은 bootstrap CI 폭(~0.044) 대비 ~1% → **통계적으로 0과 구분 불가**.
- ICIR/DSR/AX-001 모두 앙상블 < 단일 best → **diversification benefit 부재 (가설 falsified)**.
- common top-10 feature intersection = 1개(`L01_Amihud`), top-30 = 11개 → 3 모델 예측 상관 높음 (homogeneous tree-learner, Bryzgalova-Pelger-Zhu 2024 ensemble fail mode).

**Per-method scoreboard**:

| Method | Rank IC | ICIR | Harvey-t HAC | DSR | Subperiod Stab | AX-001 v2 | hit |
|--------|---------|------|--------------|-----|----------------|-----------|-----|
| XGBoost | 0.04519 | 0.392 | 4.36 | 0.141 | 1.00 | 0.753 | 0.638 |
| LightGBM | 0.05032 | 0.447 | 4.99 | 0.188 | 1.00 | 0.450 | 0.621 |
| RandomForest | 0.04632 | 0.376 | 3.95 | 0.129 | 1.00 | 1.142 | 0.638 |
| Ensemble_Equal | 0.05074 | 0.412 | 4.42 | 0.157 | 1.00 | 0.717 | 0.629 |
| **Ensemble_ICWeighted (selected)** | 0.05079 | 0.412 | 4.43 | 0.157 | 1.00 | 0.704 | 0.638 |
| Ensemble_StackRidge | 0.04969 | 0.406 | 4.30 | 0.152 | 1.00 | 0.744 | 0.621 |

---

## 5. vs D ML baseline (정량)

| 지표 | D ML (single XGB) | D_ENSEMBLE (ICW) | Δ | 판정 |
|---|---|---|---|---|
| rank IC | 0.04519 | 0.05079 | **+0.0056** | 개선 |
| ICIR | 0.392 | 0.412 | **+0.020** | 개선 |
| Harvey-t HAC | 4.356 | 4.426 | **+0.07** | 개선 |
| **DSR** | 0.251 | 0.157 | **−0.093** | **악화 (FAIL 유지)** |
| AX-001 v2 | 0.753 | 0.704 | **−0.049** | 소폭 악화 (PASS 유지) |
| hit rate | 0.6379 | 0.6379 | 0.000 | 동일 |

**핵심 판정 (도훈 질문 직접 답변)**:
- 앙상블은 **DSR을 개선하지 못함 — 오히려 악화 (0.251 → 0.157, −0.093)**. 원인: n_trials_eff 30 → 93 (3.1배) 증가가 IC 미미 개선(+0.0056)을 압도.
- 앙상블은 **AX-001 v2를 개선하지 못함 (0.753 → 0.704, −0.049)**. PASS는 유지하나 방어 성향 소폭 약화.
- **결론: 앙상블은 graduation의 binding constraint(DSR)를 개선하지 못함. D ML 대비 IC/ICIR 표면 개선은 있으나 DSR/AX-001은 악화.**

---

## 6. Final Stance

- **discovery_eligible**: false (5/6 PASS, DSR 단독 FAIL — D ML과 동일하나 DSR 더 낮음)
- **deployment_eligible**: false (DSR FAIL + turnover 15.14x > 6.0)
- **Claude response stance**: **REVISE → 사실상 가설 기각 권고**

**Codex REJECT에 대한 Claude 종합 응답**:
Codex의 핵심 비판(weakest_assumption: 앙상블 premium 부재)을 **전면 수용**. 앙상블 가설은 정량적으로 falsified:
1. diversification premium(+0.00047)은 통계적으로 0 (C2 ACCEPT).
2. 선언된 selection_objective(ICIR) 기준 정답은 LightGBM 단일 (C6 ACCEPT — spec 모순).
3. DSR binding constraint를 개선 못 하고 악화 (C1 ACCEPT).

**Forge 진입 가치 판단**: **비권장**. DSR이 여전히 binding(0.157 < 0.5)이며 앙상블이 이를 악화시킴. forge 진입 시 5-spec/cost-net/bandbuffer로 turnover는 줄일 수 있으나 DSR FAIL은 구조적(n_trials 증가). 만약 D ML track의 ML 신호를 활용한다면 **앙상블이 아닌 LightGBM 단일 모델**이 ICIR/DSR 모두 우월한 선택.

**Q-Lead 권고**:
- OPTION A (권고): D_ENSEMBLE 가설 보류. LightGBM 단일이 tree-ensemble보다 우월 — Track 2 (D refine) 또는 LightGBM 단독 deployment 검토.
- OPTION B: 진짜 이질적 base learner (NN/MLP + tree) 앙상블 재시도 (Gu-Kelly-Xiu 2020 NN1~NN4 정합). 단 본 tree-only 앙상블은 falsified.
- OPTION C: D ML (XGBoost) + B (Bali MAX) + C (Microstructure) cross-family 앙상블 — model 다양화가 아닌 alpha source 다양화.

---

## 7. Charter §8 No Silent Override 준수

본 challenge_note는 Codex 10 concerns 모두 명시 분류 (ACCEPT 3 / ACCEPT_FIXED 1 / PARTIAL 5 / REBUTTAL 1) + REBUTTAL(C10)은 학술 + L-code + 정량 3축 인용. Silent override 없음. Draft의 self-rationalization(ENSEMBLE_PREMIUM_OBSERVED) 1건 자가 검출 + final 정정.

**분류 분포**:
| Concern | Severity | Classification |
|---|---|---|
| C1 (DSR FAIL) | HIGH | ACCEPT |
| C2 (Ensemble premium 부재) | HIGH | ACCEPT |
| C3 (AX-007 sizing) | HIGH | PARTIAL |
| C4 (Turnover 15.14x) | HIGH | PARTIAL |
| C5 (PIT carve-out) | HIGH | PARTIAL |
| C6 (Robustness + selection_objective) | HIGH | PARTIAL (+ ACCEPT on objective) |
| C7 (Liquidity audit) | MEDIUM | PARTIAL |
| C8 (Charter §8 산출물) | MEDIUM | ACCEPT_FIXED |
| C9 (AX-001 soft proxy) | MEDIUM | PARTIAL |
| C10 (weights/cov 부재) | MEDIUM | REBUTTAL |

---

## 8. 메타 정보

- 작성: 2026-05-29 KST (Claude Opus 4.8, alpha-research role)
- Codex spawn: 2026-05-29 07:16 → response 07:21 (~5분, GPT-5.5 xhigh)
- Codex stance: REJECT (10 concerns, 6 HIGH)
- Claude stance: REVISE → 가설 falsified, forge 비권장
- AX-008 Triangulation: Claude + Codex 2/3 **수렴** (둘 다 ensemble 비우월 결론)
- Q-Lead escalate flag: SET (HIGH ≥ 5) — 사유: ensemble falsified + LightGBM 단일 우월을 Track 선택에 반영
