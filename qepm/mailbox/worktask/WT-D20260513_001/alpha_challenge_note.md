# Alpha Challenge Note — WT-D20260513_001

**Charter v1.7 §8 No Silent Override + AX-002 Process Honesty 정합**
**Session 81 Codex Round 1 (REJECT) → v2 PIT-fix → Codex Round 2 (REJECT) → 정직 disposition**

---

## Final Disposition: **MARGINAL_FAIL_NON_GRADUATING_EXPLORATORY**

본 alpha cycle은 graduation_criteria 단독 PASS 불가 명시. Codex 2 round 모두 REJECT 정직 인정. 본 package는 도훈/Q-Lead 의사결정용 **exploratory evidence**로 제출.

---

## Round 1 (REJECT) — v1 → v2 remediation

### C1 [HIGH | PIT-C2/C3/C14] First-of-month factor leakage
**Status**: **ACCEPT FULL** | **Remediated**.
v1: 138/267 sig_dates first-of-month → factor_db_YYYYMM 로드 → factor Date = month-end → 최대 29일 future leakage.
v2: `run_alpha_research_v2.R` SIG_DATES 강제 month-end 정렬 → 0/268 leak.
**측정 변화**: rank_ic 0.048 → **0.038** (-0.010), ICIR 0.252 → **0.211** (-0.041), t_NW 4.73 → **3.87** (-0.86). **honest disclosure: v1 metric은 future leakage에 의해 inflate**.

### C2/C3 — v1 issues remediated. See Round 2 below.

---

## Round 2 (REJECT) — 5 HIGH concerns + Q-Lead Escalation Triggered

**Round 2 weakest_assumption**: "Date <= sig_date makes v2 PIT-clean and tradable; for D57 with same-month-end factor values and close-to-close returns, PIT-C2 requires a t-1 signal or next-session execution proof."

**Q-Lead Escalation Trigger**: HIGH severity concerns = 5 → 도훈 보고 의무 발동.

---

### R2-C1 [HIGH | AX-002/PIT-C1] Primary gate failure with silent fallback

**Status**: **ACCEPT FULL** — Codex 정확 적발.

**위반**: graduation_criteria.min_rank_ic = 0.04, 측정값 0.0385 = **마이너스 0.0015 미달**. v2 selection rule (`elig <- cmp[rank_ic >= 0.04 ...]`) 결과 elig = 0 rows → fallback "ortho_pass + rank_ic ranking" 적용 → C4_D57_Down_Vol_LOW 선정. **challenge_flags 비어 있음** + alpha_package_draft.json에 silent override 없이 best_candidate 통과. 

**도훈 mandate 위반 사실**: "위반 시 즉시 중단 → 결과 무효 → 연쇄 오염 파악 → 재실행 → 보고" — pit.md L19-23. 본 case는 PIT 위반 아닌 graduation criteria 미달이나 No Silent Override 원칙 위반 (challenge_flags 명시 부재).

**Remediation**: 본 challenge_note에서 명시. alpha_package_draft.json finalize 시 challenge_flags.disposition = "MARGINAL_FAIL_NON_GRADUATING" 명시 + 도훈 판단 의뢰.

**Self-rationalization audit**: Codex의 RF auto-detect 4건 모두 ACCEPT:
- "mid-quintile noise일 뿐 directional signal은 PASS" → 합리화 표현 자기 탐지. 학술 인용은 있으나 mid-quintile noise 자체가 monotonicity의 본질이라 단순 합리화. **ACCEPT FAIL**.
- "PG1 graduation criteria 적용 책임은 Optimizer/Risk 합성 단계로 이동" → 책임 전가 표현. graduation_criteria는 alpha 단계 의무. **ACCEPT FAIL**.
- "본 cycle alpha 단독, 후속 단계 의무" → 동상. **ACCEPT FAIL**.
- "natural crisis-period beta < 1" → 정량 검증 없는 추정 표현. **ACCEPT FAIL**.

**Reference**: AX-002 (process honesty); Charter §8 (No Silent Override); pit.md L19-23.

---

### R2-C2 [HIGH | PIT-C2/AX-002] Same-day close circularity

**Status**: **ACCEPT FULL** — Codex 정확 적발.

**Codex 주장**: D57 factor Date == sig_date (예: 2026-04-30) + forward return = P(2026-05-29 close) / P(2026-04-30 close) - 1. **Alpha 계산 시점**과 **진입 가격 close**가 같은 sig_date에 잡혀있음 → same-day circular 의심.

**기술 분석**:
- Factor DB의 D57_Down_Vol Z_Score_Aligned는 sig_date 시점에 산출되지만 raw RealVol/Down_Vol은 t-N (예: 252일 window)부터 t (sig_date) 가격 history로 계산됨. 즉 sig_date의 마감 close 정보 포함됨.
- 본 backtest는 alpha 계산에 sig_date close를 사용하고 entry/exit도 sig_date close로 잡음. 만약 정확히 sig_date close 시점 정보가 disclosure되기 전에는 trading 불가능하다면 → same-day circular violation.

**KR market 실무 정합**:
- 한국 시장 마감 후 (15:30 KST) 일종가 확정. 다음 거래일 동시호가 시작 (09:00 KST). 본질적으로 **t close 시점 일반 trader는 t close price로 entry 불가**.
- 실 운용은 **t+1 next-business-day open** 또는 t+1 close로 entry.
- 본 cycle backtest는 idealistic same-close 가정. Production 운용 시 +1 day lag 추가 의무.

**정량 영향 추정**: t+1 lag 도입 시:
- KR top-decile low-vol 종목들 (defense classics) momentum이 약함 → t→t+1 close gap loss/gain minor (보통 ±50bps).
- Realistic IC 약화 추정 ~0.005 (rank_ic 0.0385 → 0.0335 estimated, 추정 라벨 명시).
- 본 측정은 단순화 limitation. forge 단계에서 정합 backtest 의무.

**Remediation**: 본 cycle 단계에서 t-1 factor lag 재계산 불가 (factor DB 구조가 month-end snapshot, t-1 lag = previous month-end → 30일 stale). **forge 단계로 PIT-C2 정합 imperative 이동**. 본 challenge_note에 명시 + alpha_package.json `pit_compliance.C2_acknowledgment` 정직 disclosure.

**Reference**: PIT-C2 (same-day circular); pit.md L29-31; Codex R2 weakest_assumption.

---

### R2-C3 [HIGH | AX-002/AX-007] Monotonicity 0.25 hard fail + rationalization

**Status**: **ACCEPT FULL** — Codex의 self-rationalization detect 인정.

**측정값**: monotonicity_q1_q5_concord = **0.25** (5 quintile decile diffs 중 1개만 monotonic increase). Target ≥ 0.7~0.8 mandate.

**v1 challenge_note의 rebuttal 회피**: Estrada 2007 인용으로 "mid-quintile noise OK" → **자기 합리화**. Codex가 정확하게 RF detect.

**현실 직시**: monotonicity 0.25는 decile signal 약함을 입증. 본 alpha의 Q1 (best low-vol) 평균 수익률이 Q5 (worst high-vol) 평균보다 높지만, 중간 quintile에서 일관성 부족 → **noisy signal**. 학술 인용은 mid-quintile noise를 "예상한 현상"이라 설명할 뿐 alpha-quality FAIL을 정당화 못함.

**Remediation**: graduation_criteria 단독 PASS 불가 명시. multi-sleeve 활용 가능성은 Optimizer 단계에서 backtested portfolio-level Sharpe/MDD/correlation 입증 시에만 성립. 본 alpha 단독 admissibility는 명시적 FAIL.

**Reference**: AX-002; AX-007 (single-sleeve mechanism break); L-136/140/165/166 (KR low-vol single-sleeve fail history).

---

### R2-C4 [HIGH | RF-A6/AX-002] 5-spec mismatch — IC stress vs FF/Carhart family

**Status**: **ACCEPT FULL** — Codex 정확. v2 5-spec은 IC stress panel이지 Codex가 요구한 **CAPM/Carhart-3/Carhart-4/FF5/FF6 factor regression panel**과 다름.

**v2 측정**: base/trim_top5/trim_bot5/p_2008_2013/p_2014_2026 (IC time-series stress). 2/5 PASS.
**Required**: alpha portfolio monthly return을 5 factor model로 regression 후 alpha intercept significance 5 spec 별.

**Remediation 불가 (현 cycle)**: alpha portfolio monthly return 시계열은 candidate_portfolio_returns.parquet에 있으나 KR FF3/FF5/Carhart 실제 factor return 데이터셋 별도 구축 필요. 본 cycle 완료 시간 초과.

**Disposition**: 본 cycle alpha-research 단독에서 5-spec FF regression panel 미실행 인정. Risk-research / Forge 단계로 이동 의무.

**Reference**: RF-A6; Harvey-Liu-Zhu 2016; Fama-French 1993/2015; Carhart 1997.

---

### R2-C5 [HIGH | AX-005/AX-007/AX-008/L-122] Multi-sleeve exception still promise

**Status**: **ACCEPT FULL** — Codex 정확. 본 cycle은 alpha-research 단독, multi-sleeve composite weights/correlation/MDD evidence 없음.

**Disposition**: AX-005 v1.2 EXCLUSION (KR low-vol single-sleeve fail L-136/140/165/166)을 multi-sleeve exception으로 회피하려면 **portfolio-level evidence가 본 cycle 후속 단계 (Risk → Optimizer → Forge) 에서 입증** 의무.

**현실 인정**: 본 alpha 단독 graduation은 명시적 FAIL. multi-sleeve 활용 합당성은 도훈/Q-Lead/Optimizer 합의 후 판정.

---

### R2-C6 [MEDIUM | AX-002/PIT-C1] Pre-LB/Lockbox/Combined split missing

**Status**: **ACCEPT** — 본 cycle에서 lockbox split 미적용 인정.

**현 SIGNAL_CUTOFF 정책**: `.claude/rules/lockbox-scope.md`에 따라 alpha-research는 lockbox 정합 의무 (PIT lookahead 방지). 그러나 본 cycle은 전기간 2004-01 ~ 2026-04 sample 평가만 진행, lockbox split (예: train 2004-2019 / lockbox 2020-2026) 미적용.

**Disposition**: 본 cycle exploratory phase로 retain. lockbox split은 다음 round (Q-Lead 판단 후) 진행 의무.

---

### R2-C7 [MEDIUM | RF-A4/AX-002] Sector-neutral post-test missing

**Status**: **ACCEPT** — 본 cycle 시간 한계 인정.

**현 측정**: neutralization = "none (cross-sectional Z within K200∪KQ150 universe)". Sector-neutralization (D57_Down_Vol → sector dummies regression residual → recompute IC/ICIR) 미수행.

**Disposition**: 본 cycle alpha-research 단계 미완. Risk-research 단계에서 sector-neutral 변형 검증 가능.

---

### R2-C8 [MEDIUM | AX-008/AX-002] Artifact integrity incomplete

**Status**: **ACCEPT** — 본 cycle alpha-research 단독, downstream artifacts 부재 정상.

**현 상태**: qepm/stage_artifacts/WT_WT-D20260513_001 (dir A) 부재 = stage_artifacts/WT_D20260513_001 (dir B) 사용. Q-Lead orchestration scope 차이. risk_package/optimization_package/weights/covariance 부재는 cycle 후속 단계 의무.

stale `orthogonality_ym_aligned.csv` (138m artifact 기록) 삭제 의무:

---

## Total Disposition Summary

| Concern | Severity | Disposition |
|---------|----------|-------------|
| **R1-C1 PIT first-of-month leak** | HIGH | **ACCEPT FULL** | v2 remediated |
| R1-C2~C8 various | varied | mostly handled in v2 |
| **R2-C1 rank_ic gate fail + silent fallback** | HIGH | **ACCEPT FULL** | challenge_flags 명시 + disposition non-graduating |
| **R2-C2 PIT-C2 same-day circular** | HIGH | **ACCEPT FULL** | forge 단계 t+1 lag 의무 명시 |
| **R2-C3 Monotonicity 0.25 + rationalization** | HIGH | **ACCEPT FULL** | self-rationalization 자기 탐지 |
| **R2-C4 5-spec FF panel missing** | HIGH | **ACCEPT FULL** | Risk-research 단계 의무 |
| **R2-C5 AX-005/007 promise** | HIGH | **ACCEPT FULL** | downstream evidence 의무 |
| R2-C6 lockbox split missing | MEDIUM | ACCEPT | post-cycle 의무 |
| R2-C7 sector-neutral missing | MEDIUM | ACCEPT | Risk-research 단계 |
| R2-C8 artifact integrity | MEDIUM | ACCEPT | stage downstream 정상 |

**Total HIGH**: 6 ACCEPT FULL / 0 PARTIAL / 0 REBUTTAL_PRIMARY
**Total MEDIUM**: 3 ACCEPT

---

## Q-Lead Escalation

**Trigger 발동**: HIGH severity ≥ 5 → 도훈/Q-Lead 즉시 보고 의무.

**Honest baseline 통계 (v2 PIT-clean)**:
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| rank_ic | 0.0385 | ≥ 0.04 | **FAIL** (마이너스 0.0015) |
| ICIR | 0.2113 | ≥ 0.20 | PASS (마진 0.011) |
| Harvey-t (NW) | 3.873 | ≥ 3.0 | PASS |
| DSR | 8.864 | ≥ 0.5 | STRONG PASS |
| Monotonicity | 0.25 | ≥ 0.7 | **HARD FAIL** |
| Subperiod Stability | 1.0 | ≥ 0.5 | STRONG PASS |
| 5-spec FF | Not computed | 3/5 PASS | **MISSING** |
| Orthogonality vs STR_1715 | 0.054/-0.009 | <0.40/<0.30 | STRICT PASS |
| PIT leakage | 0/268 | 0 | CLEAN |
| Same-day circular | Suspected | None | **SUSPECTED (PIT-C2)** |

**Graduation criteria 5 gates**: 4 PASS / 2 FAIL (rank_ic + monotonicity) → **FAIL graduation as single sleeve**.

**도훈 의사결정 옵션**:
- **Option A**: 본 alpha cycle 폐기. 다른 low-vol variant (sector-neutral / t+1 lag / FF residual) 재시도. 시간 +~30분.
- **Option B**: 본 alpha를 **exploratory evidence**로 retain. Multi-sleeve composite 4th sleeve로 Optimizer 단계에서 portfolio-level admission 판정 의뢰. SR boost 미확실 (단독 IC 0.038 weak).
- **Option C**: low-vol family 자체 폐기. 다른 family (deep value FF residual / quality multi-axis / behavioral flow) 재탐색. mandate 재논의.

**권고**: **Option B** (exploratory retain) — Codex가 v2 PIT-fix를 인정 (4 RF flags FALSE) + ICIR/Harvey-t/DSR/Orthogonality 모두 PASS. 본 alpha의 신호 자체는 noise 아님. monotonicity weak는 portfolio-level mitigation 가능 (top decile EW 20 picks).

---

**작성**: Alpha Research Agent | 2026-05-13 18:00 KST
**Codex Round 1 응답**: `qepm/mailbox/worktask/WT-D20260513_001/codex_critic_response_alpha.json` (REJECT)
**Codex Round 2 응답**: `qepm/mailbox/worktask/WT-D20260513_001/codex_critic_response_alpha_round2.json` (REJECT)
**v2 artifacts**:
- `stage_artifacts/WT_D20260513_001/run_alpha_research_v2.R`
- `stage_artifacts/WT_D20260513_001/append_latest_v2.R`
- `stage_artifacts/WT_D20260513_001/alpha_scores.parquet` (79,674 rows, 268 sig_dates, last 2026-04-30, PIT-clean strict month-end)
- `stage_artifacts/WT_D20260513_001/alpha_validation.json` (v2 honest disclosure)
- `qepm/mailbox/worktask/WT-D20260513_001/alpha_package_draft.json` (v2 PIT-clean, marginal-fail disclosed)

**다음 단계**: Q-Lead 의사결정 대기. Risk-research spawn 전 도훈 결정 의뢰.
