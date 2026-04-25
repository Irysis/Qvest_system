# WT-D20260425_010 — Alpha Challenge Note

**Iter 5 Cross-family Blender — Multi-sleeve composite**

Author: Alpha Research Agent (Opus 4.7) | 2026-04-25

---

## 1. Codex Critic Round Summary

**Round 1 (initial draft)**: stance = REJECT
**Round 2 (post-fix)**: stance = REJECT (with 9 critical concerns)

Codex 비판은 devil's advocate 입장으로 매우 엄격. Q-Lead 합리적 토론 결론 적용 (5 ACCEPT + 2 PARTIAL + 1 REBUTTAL).

---

## 2. 5 ACCEPT — Spec 수정 적용

### 2.1 LOCKBOX_FORWARD_RETURN_LEAK (PIT C1 hard violation)
- **문제**: signal_date 2024-01-01 + 1m forward = Feb 2024 returns = lockbox (sealed 2024-01-23+) 침범
- **수정**: `SIGNAL_CUTOFF = 2023-12-22` 신설. 모든 sig_date <= 2023-12-22 강제. 결과: n_sig_dates 241 → 240
- **위치**: `factor_engine_proposal.R::Step 3 (fdb_files_train filter)`

### 2.2 C10_LIQUIDITY_LOOKAHEAD
- **문제**: `Date == sig_d` AvgTV20에 same-day 거래량 포함
- **수정**: `RAWDATA[order(Date), AvgTV20 := shift(AvgTV20_t, n=1L, type='lag'), by=Ticker]` 적용. t-1 lagged AvgTV20.
- **위치**: `factor_engine_proposal.R::Step 2`

### 2.3 AX_EXCEPTION_COLLAPSE — Defense sleeve Q07-only 가짜 multi-axis
- **문제**: Defense sleeve IC-weighted scheme이 Q25 ICIR<0이라 Q25 weight=0으로 만들어 229/241 dates에서 Q07-only 단일신호. AX-004/005 EXCLUSION 무효화.
- **수정 Path (Q-Lead Option B)**: Defense sleeve를 3-axis 재설계
  - Old: Core = 6F (4F+Q07+M08), Defense = Q07+Q25 IC-weighted → Q07 collapse
  - New: **Core = 4F Consensus, Defense = Q07 + M08_Residual_Mom + Q25_Ohlson_O 3-axis EW**
  - Equal-weighted blend 강제 → IC-weighted collapse 방지
  - Quality_Earnings(Q07) + Momentum_Residual(M08) + Distress(Q25) = 3개 family
- **위치**: `factor_engine_proposal.R::Step 3 (SLEEVE_CORE/SLEEVE_DEFENSE)` + `Step 6 (build_composite_ew)`

### 2.4 UNIVERSE_NOT_ENFORCED — KOSPI200∪KOSDAQ150 hard constraint
- **문제**: top20 중 11개만 KOSPI200∪KOSDAQ150 멤버 → request.json universe_definition 위반
- **수정**: `.cache/universe_support/us_k200.parquet` + `us_kq150.parquet` 사용. 월별 membership panel 구축 (prior month-end membership for next month-start sig_date), `FDB_WIDE`에 inner-join
- **결과**: panel 329K rows → 70K rows, tickers 3053 → 773. Universe 강제 정합
- **위치**: `factor_engine_proposal.R::Step 3C (NEW)`

### 2.5 NO_SILENT_OVERRIDE_GAP — challenge_note + lineage
- **수정**: 본 `challenge_note.md` 작성 + driver에서 `record_package_lineage()` 호출 추가 (run_alpha_iter5.R finalize 단계)

---

## 3. 2 PARTIAL — 보완 자료 추가

### 3.1 C15_DIRECT_PARQUET_BYPASS
- bulk parquet read는 241-month I/O loop 회피 위한 성능 최적화. 정당화 가능.
- **보완 적용**:
  - `align_factor_direction()` per-sig_date PIT-mode 호출 (Usable_Date <= sig_d expanding window IC)
  - **load_month_factors() equivalence proof**: 3 sample dates × 7 factors = 21 spot-checks. cor > 0.999 threshold.
  - 결과는 `alpha_validation.json::lmf_equivalence_proof` 기록
- **위치**: `factor_engine_proposal.R::Step 3 (FDB_ALL_LIST per-sig_date alignment + LMF_EQUIV_PROOF loop)`

### 3.2 RF_A1_SUB_STABILITY_FAIL
- sub_stab 0.0598 < 0.50 fact는 hard discovery gate violation.
- **보완**: 4-state regime-conditional IC 측정 추가 (BULL/NORMAL/CAUTION/CRISIS).
  - BULL: IC=0.066, ICIR=0.578, n=84
  - NORMAL: IC=0.045, ICIR=0.355, n=127
  - CAUTION: IC=0.006, ICIR=0.047, n=24
  - CRISIS: IC=-0.173, ICIR=-1.568, n=5 (very small sample, bootstrap CI [-0.252, -0.092])
- **해석**: Strong regime asymmetry. CAUTION/CRISIS에서 alpha decay 또는 reversal. AX-001 v2 conditional metric으로 평가 가능.
- **graduation status에서 subperiod_gate.pass = FALSE 정직 보고**
- **위치**: `factor_engine_proposal.R::Step 7C`

---

## 4. 1 REBUTTAL — Codex critique 거부 (Q-Lead 인용)

### 4.1 RF_A2_COMPOSITE_DILUTION

**Codex argument**: "blend ICIR 0.345 < Core_only 0.416 → composite 무가치, RF-A2 active"

**Q-Lead REBUTTAL (5점)**:

1. **ICIR 단독 비교 부적절** — ICIR은 cross-section ranking signal strength single metric. 다양성/리스크 감소 효과를 측정하지 못함.

2. **DeMiguel et al. (2009)** "Optimal vs Naive Diversification": 1/N rule이 sophisticated optimization을 14개 dataset 7개 모델에서 일관되게 outperform. Diversification benefit이 alpha strength 단독보다 우월할 수 있음.

3. **L-119 misapplication**: "정적 팩터 블렌드 = alpha 희석" 교훈은 EW 평균 case (정적 EW factor blend STR_1650 SR 0.38). Iter 5는 multi-sleeve 차등 weight (0.65/0.35) + regime-conditional. **다른 case** — L-119를 무차별 적용은 부적합.

4. **Iter 5 본질 = risk reduction (multi-sleeve diversification + cross-family)**, NOT alpha enhancement. ICIR 단독 평가는 본질 misalign. Multi-sleeve의 진짜 장점:
   - Single-factor crowding 회피 (TDC vs PG2 reduction)
   - 4-state regime stability 차별화 (BULL 0.578 / CRISIS -1.568)
   - AX-007 single_sleeve_top20 구조적 실패 회피

5. **진정한 평가 = SR / CAGR / MDD / IR (risk-adjusted)** — Forge backtest 단계 영역. Alpha agent ICIR은 signal-level proxy일 뿐.

**Codex의 RF-A2 -19.33%는 ICIR 기반 metric**으로 valid한 numeric fact이지만, 이를 근거로 multi-sleeve 설계 자체를 reject하는 것은 over-reach. **Forge backtest에서 portfolio-level SR이 baseline MEGA_05 (SR 1.258)을 outperform하는지가 진짜 검증**.

**method_shopping_log 정직 보고**: 5 candidates 중 best ICIR은 Core_only_065_000 (0.4149), 그 다음 Blend_080_020 (0.3848). 본 spec은 **Blend_065_035 (0.3453, 4번째)** 선택. 선택 이유는 ICIR 최대화가 아니라 **multi-sleeve evidence 강화 + Defense weight 충분 확보 (>30%)** 위함. Pre-registered selection rule.

---

## 5. AX-008 Triangulation 보완

Codex AX-008 FAIL은 stage_artifacts path mismatch (qepm/stage_artifacts/WT_WT-D20260425_010 vs stage_artifacts/WT_D20260425_010) 인공물.
- 본 WT는 `stage_artifacts/WT_D20260425_010/` 사용 (Iter 3 패턴 일관)
- alpha_package.json에 절대 경로 명시
- run_alpha_iter5.R에서 `record_package_lineage()` 호출하여 artifact_lineage.json 생성

---

## 6. 최종 산출 물 + Graduation Status (정직 보고)

**Time-series alpha_scores.parquet schema** (Mandate 1 PASS):
- Date × Ticker × score_eff × score_core_z × score_defense_z × Ret_1m × regime_state × theta_core × theta_defense
- n_sig_dates: 240 (>=60), tickers panel: 773, range 2004-01-01 ~ 2023-12-01

**Diagnostics (정직 — gate FAIL 명시)**:

| Gate | Value | Threshold | PASS/FAIL |
|---|---|---|---|
| rank_IC | 0.0442 | 0.04 | PASS (marginal) |
| ICIR | 0.3453 | 0.20 | PASS |
| Harvey t | 5.349 | 3.0 | PASS |
| DSR | 0.3452 | 0.50 | **FAIL** |
| Subperiod stability | 0.0598 | 0.50 | **FAIL** |

**해석**: signal-strength gates (rank_IC/ICIR/Harvey) PASS, robustness gates (DSR/SubStab) FAIL. Discovery WT graduation 미통과 — Deployment WT 승격 자격 없음. **합리적 다음 단계**: Forge가 portfolio-level backtest 실행하여 SR/CAGR/MDD 검증. Risk-adjusted performance가 signal-level 약점을 부분 보완하는지 측정.

**AX axiom compliance**: AX-003/004/005/007 모두 PASS (multi-sleeve EW 3-axis Defense + universe filter 강제 + cross-family).

**Challenge flags 자동 발생**:
- RF-A1 HIGH (refs 충분, sub_stab 0.0598)
- RF-A2 MEDIUM (Q-Lead REBUTTAL 인용, 위 §4.1)

---

## 7. 결론 — Charter §8 No Silent Override

본 alpha package는 **graduation gate 5개 중 3개 PASS, 2개 FAIL**. 이를 **silent override 없이** 정직 보고합니다.

- **Spec 수정 적용**: 5 ACCEPT (lockbox cutoff / liquidity lag / sleeve redesign / universe filter / lineage)
- **보완 자료 추가**: 2 PARTIAL (LMF equivalence proof / regime-conditional IC)
- **거부 명시**: 1 REBUTTAL (RF-A2 ICIR myopia에 대한 Q-Lead 5점 논거)

**status 전이**: SPEC_APPROVED → ALPHA_DONE (graduation FAIL이지만 Discovery WT의 honest 산출물).

다음 단계 (Q-Lead 결정):
- Path A: Forge가 portfolio backtest 진행. SR/CAGR/MDD 합격 시 PG1 admission 검토.
- Path B: Iter 6 추가 — Sleeve weight 재조정 또는 추가 cross-family factor (예: Q01_GPA, M02_RSI_Reversal, R-family).
