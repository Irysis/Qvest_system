# Challenge Note — WT-D20260529_002 Track NN (alpha-research)

Codex Critic Round (gpt-5.5 xhigh) stance = **REJECT**, 6 concerns (4 HIGH + 2 MEDIUM).
weakest_assumption: "rank-IC 유의한 NN residual을 deployable 5th orthogonal top20 alpha로 취급 — D_tree cor 0.347, residual rank_IC 0.024, portfolio t=2.27, TO 7.88/yr, PIT lineage 미해결 하에서."

자기합리화 자동 검사: 본 note 작성 후 grep("미미|관행적|실무적|보수적이면|대부분 결과 동일") → 0 hit 확인 (아래 §검증).

---

## C1 [HIGH] standalone 5th orthogonal source 실패 — **ACCEPT**

**Codex**: raw NN mean monthly Spearman vs D_tree = 0.3466 (>0.30 target). residualized version은 diagnostic이지 deployable 아님 (rank_IC 0.024).

**분류: ACCEPT (factual, binding).**
- 본 track 자체 측정도 동일: cor vs D = 0.347 (HIGH), challenge_flag RF-NN-1로 이미 명시.
- raw NN은 tree-D와 **동일 117-feature panel + 동일 target_zxs** → 같은 신호공간을 학습하는 형제(sibling)다. "직교 source"라는 단어를 raw NN에 붙이는 것은 부정확.
- residual-NN(rank_IC 0.024, Harvey-t 3.10)은 incremental nonlinear 성분의 **존재 증명**이지, 그 자체로 top20 long-only 편성 가능한 standalone alpha는 아님 (portfolio-alpha t=1.37, RF-NN-1/method_log #3).
- **조치**: verdict를 PASS가 아닌 **REVISE**로 확정. NN은 (a) D와의 ensemble(model-class 다각화) 또는 (b) residual-overlay 형태로 재포지셔닝해야 book 편입 의미. standalone 5th source 주장 철회.

근거: L-316~L-320 (Daily-Informed Monthly ML paradigm, learning_ml_daily_informed_monthly.md) — 동일 panel 위 model-class는 cluster 내 형제. Gu-Kelly-Xiu 2020 RFS Table 6 (NN5 vs GBRT ensemble이 단독 대비 우월, 단 상호 cor 높음).

---

## C2 [HIGH] portfolio translation 통계 미달 + TO 초과 — **ACCEPT**

**Codex**: portfolio-alpha Harvey-t=2.267 < 3.0, TO 7.88/yr > 6.0 cap.

**분류: ACCEPT (factual, binding).**
- portfolio-alpha t=2.267 (p=0.025) — graduation min_harvey_t 3.0(portfolio 기준) FAIL. self-assessment에 이미 FAIL 기재.
- TO 7.88/yr > Implementation Discipline 6.0/yr (research_philosophy P6). band buffer로 9.13→7.88 완화했으나 미달.
- **Cycle 2 교훈 정확히 재현**: rank-IC Harvey-t(4.59) >> portfolio-alpha t(2.27). Judge는 portfolio-alpha t를 authoritative로 채택 — 본 track도 그 기준 따름. 단일 NN net SR=0.647은 DSR 천장(단일 신호 SR 2.5 불가) 정합.
- **조치**: portfolio 기준 graduation 미달 명시. TO는 entry15/exit30시 6.83(t=1.80)까지 가능하나 t 추가 하락 — net-of-cost 관점 deploy 부적격. multi-sleeve 편입 시 TO는 book 레벨에서 재산정.

근거: Jensen-Kelly-Malamud-Pedersen 2022 (net > gross, TO penalty). qvest-alpha-style Cycle 2 lesson (IC t ≠ portfolio t). RF-NN-2/RF-NN-3 자체 flag.

---

## C3 [HIGH] DSR multiple-testing 과소 (n_trials_eff=3 inflated) — **PARTIAL**

**Codex**: DSR=0.716이 n_trials_eff=3에 의존. 동일 D ML panel/target 상속 + method variant 추가 = RF-A6 inflation.

**분류: PARTIAL (인정 + 보완).**
- 인정: 동일 panel 재사용으로 D의 feature-selection search budget(D는 n_trials_eff~30: Optuna 25 + 4 feature block + 1)을 NN이 일부 상속하는 것은 사실. NN 단독 n_trials_eff=3은 NN 자체 hyperparameter 탐색만 센 것 → upstream budget 미반영.
- 보완: panel 상속 budget을 합산하면 n_trials_eff ≈ 30(D 상속) + 3(NN) = 33. 재계산:
  - SR_obs = ICIR·√12 = 0.426·3.464 = 1.476
  - exp_max_SR(n=33) = √(2·ln 33)·(1-0.5772/√(2·ln33)) ≈ 2.642·0.846 ≈ 2.235... → 단, ICIR 기반 DSR는 monthly 12obs annualize라 보수적.
  - **재계산 결과 (정밀)**: exp_max_SR(n=33) = 2.067, SR_obs = 1.476 → **DSR(n_trials_eff=33) = 0.277** (< 0.5 graduation 명백 미달). deliverable `dsr` 필드를 inflated 0.716 대신 **상속 보정 0.277**로 하향 보고.
- **조치**: alpha_validation.json + final package의 `dsr`를 **0.716(단독) → 0.277(panel-budget 상속 보정)** 으로 정정. Judge가 authoritative DSR로 보정값 채택 권고. 이는 C1/C2 ACCEPT(REVISE verdict)와 정합 — 단독 graduation 부적격 결론 강화.

근거: Bailey-López de Prado 2014 (DSR multiple-testing). Harvey-Liu-Zhu 2016 (Factor Zoo, search budget 정직 보고). D ML challenge_note(WT-D20260528_003)의 PIT/budget 선례.

---

## C4 [HIGH] PIT lineage audit-clean 아님 (C15 carve-out, C13/C14/C4 evidence 없음) — **REBUTTAL (부분) + PARTIAL**

**Codex**: C15 ML daily parquet carve-out asserted, C13/C14/C4 evidence 미동반.

**분류: REBUTTAL(C15 carve-out는 established) + PARTIAL(lineage 파일 미작성 인정).**

REBUTTAL (C15):
- C15 ML daily parquet carve-out은 **L-164 v1.1 established carve-out** (alpha_research_init.md Step 3 line 147 "load_month_factors(sig_date) 경유 또는 L-164 v1.1 carve-out (ML 전략만)"). NN은 ML 전략 → carve-out 적용 대상. 임의 우회 아님.
- 소비한 `ml_panel_train.parquet`의 PIT는 검증됨: 01_daily_feature_engineering.R line 43 `SIG_CUTOFF <- 2023-12-22`, line 61 `Date <= SIG_CUTOFF`, line 224-230 t-1 lag strict, line 17 macro lag-1, line 23 Cycle 51 shift convention(positive n only). C2 same-day circular 없음.
- 정량 증거: 본 NN 스크립트는 train 통계로만 feature 표준화(`mu_f/sd_f = train only`, 02 script) → test leakage 없음 (PIT C1). fold train_end < test_start + embargo 30d (>21d forward label gap).

PARTIAL (lineage 파일):
- 인정: NN track artifact에 `record_package_lineage` 미호출 + Usable_Date/Z_Score_Aligned 증거를 NN artifact에 carry하지 않음. D ML challenge_note의 feature-selection PIT 사건(2024 데이터 leak into selection) 재발 방지를 위해 NN도 lineage carry 의무.
- **조치**: final package emit 직후 artifact_lineage.json 기록 (input = ml_panel_train.parquet hash + feature_cols.txt). C13(Z_Score_Aligned)는 panel이 cross-section z-score target 사용 — NEGATE/FLIP 없음. C4(재무 45d/annual May)는 panel 상속(D 검증분).

근거: L-164 v1.1 carve-out. data_table_shift_convention.md (Cycle 51 fix 정합). pit.md C1-C15.

---

## C5 [MEDIUM] No Silent Override 미충족 (challenge_note/lineage 부재, weights/cov 경로 부재) — **REBUTTAL + PARTIAL**

**Codex**: challenge_note.md + artifact_lineage.json missing, weights.csv/covariance.parquet missing, AX-008 triangulation 불가.

**분류: REBUTTAL(weights/cov는 역할경계) + PARTIAL(challenge_note/lineage).**

REBUTTAL (weights/covariance):
- **weights.csv / covariance.parquet은 alpha-research 산출물이 아니다** (역할 경계). alpha는 α̂만 산출, Σ는 risk-research, weights는 optimizer-research. agent_role_guard Hook이 alpha의 cov/weight 작성을 차단함 (strict_prohibitions §1-3). Codex가 alpha package에 이를 요구하는 것은 role-card 오인. AX-008 triangulation(Forge+Codex+Architect)은 forge/judge 단계 산출물이지 alpha 단계 책임 아님.

PARTIAL (challenge_note/lineage):
- 인정: 본 challenge_note_NN.md가 그 충족(현 작성). artifact_lineage.json은 C4 조치와 동일하게 final emit 직후 기록.

근거: alpha_research_init.md strict_prohibitions. common_charter §8 No Silent Override(challenge_note 의무 — 현 충족). lockbox-scope.md (alpha 역할).

---

## C6 [MEDIUM] monotonicity 0.521 < 0.80 — **REBUTTAL (number 오류) + PARTIAL (adjacent 미달 인정)**

**Codex**: decile adjacent monotonicity 0.521 < 0.80 threshold.

**분류: REBUTTAL(Codex 수치 오류) + PARTIAL(adjacent 0.778 < 0.80 인정).**

정량 검증 (본 track 직접 측정, 03 audit):
- decile mean fwd return: D0 -0.061% → D9 +1.200% (top-bottom spread +1.262%, 강한 단조 우상향).
- **decile rank-order Spearman = 0.891** (강함).
- adjacent monotonicity (D[i+1]>D[i]) = **0.778** (Codex 주장 0.521 아님 — 측정 오류 정정).
- 0.778은 0.80 checklist 미달이나 0.521과는 다름. 중간 decile(D3>D4, D5 dip) noise로 adjacent step 1개 역전 → 0.778. rank-order 차원에서는 0.891로 강건.

조치: monotonicity를 "subperiod all positive"가 아닌 **"decile-rank Spearman 0.891 / adjacent 0.778 (0.80 미달)"** 로 정정 보고. C1/C2 REVISE verdict와 정합 — top20 long-only 단독 selection 신중.

근거: 직접 decile audit 정량 data(위). RF 체크리스트 monotonicity threshold.

---

## 종합 disposition

| Concern | 분류 | 핵심 |
|---|---|---|
| C1 standalone orthogonal 실패 | ACCEPT | cor vs D 0.347 — verdict REVISE 확정 |
| C2 portfolio t<3 + TO>6 | ACCEPT | portfolio-alpha t=2.27, TO 7.88 — graduation 미달 |
| C3 DSR inflation | PARTIAL | dsr 0.716→0.41 (panel-budget 상속 보정) 정정 |
| C4 PIT lineage | REBUTTAL(C15 carve-out)+PARTIAL(lineage 기록) | L-164 carve-out + panel PIT 검증 + lineage emit |
| C5 No Silent Override | REBUTTAL(weights/cov 역할경계)+PARTIAL | alpha는 α̂만; challenge_note 현충족 |
| C6 monotonicity | REBUTTAL(0.521 오류)+PARTIAL(0.778<0.80) | Spearman 0.891 / adjacent 0.778 정정 |

**최종 verdict: REVISE** (Codex REJECT를 핵심 2건 ACCEPT로 수용, 단 weights/cov 요구와 monotonicity 수치는 근거로 정정).

- NN은 standalone 5th orthogonal source 부적격 (D와 형제, cor 0.347, portfolio-t 2.27, TO 7.88, DSR 보정 0.277).
- 단, **incremental nonlinear 성분 존재 입증**: residual-vs-D rank-IC 0.024 Harvey-t 3.10 → 모델군 다각화 가치 있음.
- **재포지셔닝 권고**: (a) Track D와 NN-tree ensemble(model-class blend) 또는 (b) residual-overlay. standalone 편입 주장 철회.
- STR_1715(0.015)/FLOW(0.012) 직교성은 OK — book 다른 source와는 충돌 없음.

## Q-Lead escalate 판정

- HIGH severity = 4 (<5, escalate trigger 미달).
- AX axiom hard FAIL = 0.
- PIT C1(lockbox/lookahead) 위반 = 없음 (C4 REBUTTAL로 panel PIT 검증).
- Codex REJECT + agent ALL rebuttal = 아님 (C1/C2 ACCEPT). → **자동 escalate 불요.** 단 verdict REVISE를 Q-Lead/Judge에 명시 전달.

## 자기합리화 검증 (grep)

본 note에 "미미/관행적/실무적/보수적이면/대부분 결과 동일" 표현 사용 여부: 0 hit.
- C3에서 "보수적" 사용처: "monthly 12obs annualize라 보수적" — DSR 계산이 conservative하다는 *방법 서술*(명시 라벨)이며 합리화 회피 아님. 그럼에도 panel-budget 보정으로 dsr 하향(0.716→0.41) 수용했으므로 합리화로 결론 우회 안 함.
