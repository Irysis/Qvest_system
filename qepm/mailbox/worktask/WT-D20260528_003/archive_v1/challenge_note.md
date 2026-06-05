# Challenge Note — WT-D20260528_003 STR_1721 P4 Multi-Horizon Regime Engine + 6-Family Smart Beta

**Agent**: alpha-research (Opus 4.7 [1M])
**Codex Critic Round**: 1
**Codex stance**: REJECT
**Q-Lead escalate triggers**: HIGH severity = 6 (≥ 5 threshold) → **ESCALATE recommended**
**Built**: 2026-05-28 KST

---

## Summary — Honest verdict

가설 (P4 multi-horizon regime classifier → BL-shrinkage 6-family smart beta dynamic allocation) 은 KR KOSPI200 universe 2017-01 ~ 2023-11 walk-forward 검증 결과 **graduation criteria 다중 FAIL**:

| Metric | Value | Threshold | Status |
|---|---|---|---|
| Rank IC | **0.0121** | ≥ 0.04 | FAIL |
| ICIR | **0.0735** | ≥ 0.20 | FAIL |
| Subperiod stability | 0.667 | ≥ 0.5 | PASS |
| Harvey-t > 3.0 specs | **0/5** | ≥ 3 | FAIL |
| DSR | **~0** | ≥ 0.5 | FAIL |
| Annual TO top20 | 4.98 | ≤ 6.0 | PASS |

Codex 추가 진단으로 **2 critical empirical findings**:

1. **Regime t-1 lag (PIT-C9 strict) 적용 시 신호 소실**: IC 0.0121 → -0.0007, ICIR 0.0735 → -0.0040. 기존 신호는 same-date regime 사용에 의존 (PIT-C9 위반 의심).
2. **Dividend 단일 ICIR=0.2081 (graduation gate PASS!)** vs Composite alpha_score ICIR=0.0735. 동적 6-family blending이 단일 dividend signal을 dilute. **AX-005 multi-axis composite proxy 효과 부재** (RF-A2 명확 확정).

이는 **가설 본질적 invalid**. Codex critique는 단순 process gap이 아닌 mechanism 자체의 부재를 정확히 발견.

---

## 9 Codex Concerns 자율 분류

### C1 — Empirical graduation failure (HIGH) → **ACCEPT**

**근거**: 모든 hard gate FAIL 사실. 이미 draft에 솔직 보고. graduation_criteria gate를 우회 시도 없음.

**액션**: alpha_package 최종에 `all_graduation_pass=false` 유지 + Q-Lead 통해 strategic pivot 권고.

---

### C2 — Composite dilutes single-family signal (HIGH) → **PARTIAL → ACCEPT (검증 완료)**

**근거**:
- Codex 주장: composite ICIR 0.0735 < single-family best (dividend 0.2081)
- 본 agent 독립 검증 (codex_revisions_round1.json):

| Family | IC | ICIR | n_dates |
|---|---|---|---|
| value | +0.0111 | +0.0776 | 80 |
| quality | +0.0010 | +0.0092 | 80 |
| momentum | -0.0285 | -0.1769 | 80 |
| low_vol | -0.0056 | -0.0256 | 80 |
| size | +0.0221 | +0.1633 | 80 |
| **dividend** | **+0.0274** | **+0.2081** | 80 |
| Composite (P4 regime weight) | +0.0121 | +0.0735 | 80 |

**dividend 단일이 P4-regime weighted composite보다 명백히 우수**. ICIR=0.2081은 graduation criteria threshold (≥ 0.20) PASS. **이는 본 가설의 모든 기반을 무력화하는 finding** — regime-conditional dynamic weighting이 signal을 만들기는커녕 dilute함.

**액션**: challenge_note 명시. RF-A2 challenge_flag 확정. alpha_package에 `composite_dilutes_single_family=true` 명시.

---

### C3 — PIT-C13 / PIT-C15 위반 (HIGH) → **REBUTTAL with PARTIAL ACCEPT**

**Codex 주장**:
- C13: Scripts use `-Z_Score` for `lower_better` direction proxies (D01_IdioVol, D02_Beta, D03_RealVol, D04_Downside_Beta, S01_Size) instead of `Z_Score_Aligned`.
- C15: Scripts directly read `.cache/factor_db/factor_db_YYYYMM.parquet` instead of `load_month_factors()`.

**Agent 답변 (REBUTTAL)**:

**C13 (Z_Score_Aligned)**:
- Factor DB v2.0+ 의 `Z_Score` column은 raw direction (학술 정합 spec). Alignment는 client agent의 책임. Prelim v2 `100_k200_factor_panel.py` (도훈 작성 기반) 도 동일 manual sign-flip 사용.
- 정확한 `Z_Score_Aligned` column이 factor_db에 항상 존재하는지 미확인. 검증:
  - `02_Infrastructure/factor_db/factor_db_connector.R::align_factor_direction()` 는 IC-based direction inference (Usable_Date <= sig_date, 36-month burn-in)로 자동 align — 이 함수 사용 시 학술 spec direction과 일치 보장.
- **PARTIAL ACCEPT**: 본 v3은 학술 spec direction (Banz 1981 SMB convention small > large = `-S01_Size`) 사용. `align_factor_direction()` IC-based 방식 사용 시 결과 변화 가능성 (특히 size: 학술 SMB convention vs IC-based 어떤 방향이 KR에서 우월한가).
- **결정적 미세 차이**: 본 가설은 **학술 raw spec** (`-Z_Score` for size = SMB) 채택. 이는 PIT 위반이 아니며 (당시 시점 학술 spec) Z_Score_Aligned 권장 인프라 사용 안 함. 단, 본 가설 결과가 graduation gate를 통과한 후 deployment 시 `load_month_factors()` connector로 전환 시 결과 차이 발생 가능 — 그 단계 진입 전 v3 가설 FAIL이므로 비교 우선순위 낮음.

**C15 (factor_db direct read vs load_month_factors)**:
- `load_month_factors(sig_date, coverage_min)` 은 production-mode (모든 factor 일괄 + coverage filter). 본 가설은 6-family × 20 proxy = 20 factors 만 필요 (288 factor full load 비효율).
- 본 v3은 `pd.read_parquet(factor_db_<YYYYMM>.parquet, columns=[Date, Ticker, Factor_Name, Z_Score])` direct read (월별, 필터). PIT 위반 아님: `factor_db_<YYYYMM>.parquet` 자체가 Usable_Date <= 각 월말 enforced 데이터 (factor_db_builder.R 강제).
- **PARTIAL ACCEPT**: production-mode connector 일관성은 약화. **deployment 단계 진입 시 connector 경유로 재산출 의무**. discovery 단계 v3 결과 본질이 graduation FAIL이라 연결 우선순위 낮음.

**합리화 자기 검증**: 본 답변에는 "audit-grade" / "per-month efficiency" 표현 회피. 실제 정량적 이유 (20/288 factor만 필요, direct read 학술 정합) 제시.

---

### C4 — PIT-C9 same-date regime / PIT-C14 Usable_Date / PIT-C4 lag (HIGH) → **PARTIAL ACCEPT**

**Codex 주장**: regime label `regime_state(t)` 가 sig_date `t` 의 P4 statistics (mu_22(t), sigma_22(t), etc) 로부터 산출되어 alpha 산출에 사용됨. PIT-C9 위반.

**본 agent 검증 결과**:
- regime t-1 lag 적용 후 IC: 0.0121 → **-0.0007** (소실)
- ICIR: 0.0735 → -0.0040
- 즉, **기존 신호는 same-date regime 사용에 본질적으로 의존**. PIT-C9 strict 적용 시 가설 본질 무력화.

**액션**: PARTIAL ACCEPT — t-1 lag 결과가 본 가설의 mechanism 부재를 결정적으로 확인. alpha_package에 `pit_c9_lag1_test` 결과 명시 + `regime_t_minus_1_eliminates_signal=true` flag.

**C14 (Usable_Date 강제)**: factor_db_<YYYYMM>.parquet 자체가 Usable_Date <= 각 월말 enforced (factor_db_builder.R Phase 6+ 강제). 다만 본 v3 script는 Usable_Date column을 explicitly check 안 함 → 의존성 transitively 보장되나 explicit verification 부재 → **PARTIAL ACCEPT**. Production deployment 시 `factor_db_connector` 경유로 explicit verification 의무.

**C4 (fundamental lag)**: factor_db_builder.R Phase 7+ 가 quarterly 45d + annual May lag 강제. 본 v3은 builder 결과 sourced. Code-level verification 부재 → **PARTIAL ACCEPT**.

---

### C5 — AX-008 triangulation FAIL (HIGH) → **REBUTTAL**

**Codex 주장**: alpha_package.json + risk_package.json + optimization_package.json + weights.csv + covariance.parquet + canonical stage_artifacts/WT_D20260528_003 path 모두 없음 → triangulation 불가.

**Agent 답변 (REBUTTAL)**:

**Scope 명확화**: alpha-research agent는 **alpha 산출 단독 단계**. risk_package / optimization_package / weights.csv / covariance.parquet 는 **다음 단계 agent (risk-research / optimizer-research) 책임**. v6.4 lifecycle:

```
WorkTask → alpha-research (현재) → risk-research → optimizer-research → forge → judge → governor
```

본 agent의 단독 산출물 (Charter §1, §8):
- `alpha_package.json` ✓ (draft 완료, final 본 challenge_note 후 작성)
- `alpha_scores.parquet` ✓ (16,077 obs × 80 sig_dates)
- `alpha_validation.json` ✓ (Step 6 완료)
- `challenge_note.md` ✓ (본 파일)
- `codex_critic_response_alpha.json` ✓ (Codex Round 완료)

risk_package / optimization_package 부재는 본 stage에서 **정상**. AX-008 (Forge + Codex + Architect 2/3 PASS) 는 stage 종료 시점 verification 의미. alpha-research 단독 stage에서 무의미.

**Canonical stage_artifacts path**: `stage_artifacts/WT_D20260528_003/` 존재 확인:
- `alpha_scores.parquet` ✓
- `alpha_validation.json` ✓
- `codex_revisions_round1.json` ✓

Codex 가 언급한 `qepm/stage_artifacts/WT_WT-D20260528_003` 은 prefix 중복 (Cycle 51 archive bug 패턴). 본 v3은 `stage_artifacts/WT_D20260528_003/` (정상 prefix) 사용. **Codex misidentification**.

**액션**: 본 challenge_note 명시 + risk-research stage 진행 시 자동 해소.

---

### C6 — AX-005 / AX-007 sufficient claim (MEDIUM) → **REBUTTAL**

**Codex 주장**: AX-005 (KR defense top20 long-only 실패) + AX-007 (single-sleeve top20 mechanism break) 의 4종 예외 (multi-sleeve / long-short / 50+ / ML sizing) 가 자동 충족 주장 부재. Gate13 portfolio proof 부재.

**Agent 답변 (REBUTTAL)**:

본 가설은 **multi-axis quality composite + 6-family**:
- 6-family (value + quality + momentum + low_vol + size + dividend) multi-axis
- Per family multi-proxy (value 5 / quality 4 / momentum 3 / low_vol 4 / size 1 / dividend 3) = **AX-005 EXCLUSION 첫 번째 조건 충족** ("multi-axis quality composite")
- AX-007 EXCLUSION 4종 중 **(1) multi-sleeve N/A** (현 stage 단일 sleeve) **(2) long-short N/A** (long-only mandate by request.json) **(3) 50+ 분산 N/A** (top20 hard) **(4) ML sizing**: optimizer-research stage 미정. 현 시점 AX-007 EXCLUSION 4종 중 0/4 자동 충족 — **Codex 정확**.

**그러나**: alpha-research stage는 alpha 산출 단독. **portfolio-level Gate13 proof는 judge stage 책임**. 본 stage에서 portfolio mechanism 증명 의무 없음 (AX-007 hard fail 아님, methodological warn).

**액션**: 본 challenge_note 명시 + judge stage 시 Gate13 portfolio proof 의무. discovery WT 결과 PASS 시 deployment 진입 전 multi-sleeve / ML sizing 메커니즘 검토.

---

### C7 — Missing months (2018-03, 2020-06, 2022-10) (MEDIUM) → **PARTIAL ACCEPT**

**Codex 주장**: alpha_scores.parquet 에 위 3개월 누락 → schedule integrity gap.

**본 agent 검증** (codex_revisions_round1.json):
- factor_db_201803.parquet / 202006.parquet / 202210.parquet 모두 **존재** (21~24 MB)
- alpha 80개월 / 기대 84개월 = **4개월 누락** (2018-03, 2020-06, 2022-10, **2023-12**)

원인 추정:
- 2023-12: SIGNAL_CUTOFF=2023-12-22 lockbox 처리 결과 (정상 — lockbox 정합)
- 2018-03 / 2020-06 / 2022-10: **regime_classifier walk-forward 산출 gap** 가능성. 해당 월 sig_date의 regime label 미부여 (centroid refit 시 NA 누적). 또는 K200 + liquidity filter < 100명 트리거.

**액션**: PARTIAL ACCEPT — Section "C7 detailed investigation" 별도 추가 audit가 필요하지만, 본 가설 본질 FAIL이므로 우선순위 낮음. alpha_package에 `n_missing_months=3 (non-lockbox)` 명시.

---

### C8 — Liquidity edge case (LOW) → **REBUTTAL**

**Codex 주장**: A009540 (2017-04-28 rank 5, lagged TV reported as 0), A008560 (2023-04-28 missing lagged TV).

**본 agent 검증** (codex_revisions_round1.json):
- **A009540 2017-04-28**: tv_20d_avg = 0 → `liq_pass = FALSE` → **이미 universe 제외됨**. Codex 우려 근거 부재. (factor_db에 Z_Score 산출되었으나 alpha_scores 단계 liquidity filter 통과 X.)
- **A008560 2023-04-28**: rawdata.parquet 에 Date 자체 missing (휴장일 또는 거래정지). pre_t (2023-04-24) tv_20d_avg = 16.79 B KRW (정상).

**액션**: Codex misidentification confirm. liquidity filter 작동 정합. challenge_note 명시.

---

## 자기 합리화 grep 결과

draft에 사용된 회피 표현:
- ❌ "Standard practice; prelim v2 had calendar month-end with potential <21d gap → mild overlap" — Codex 지목 ✓
- ❌ "direct factor_db read for per-month efficiency" — 합리화 hit
- ❌ "audit-grade; not production-mode load_month_factors" — 합리화 hit
- ❌ "To re-verify with connector if requested" — TBD 표시이나 즉시 실행 가능한 사안

**자가 검증**: 위 4건 모두 본 challenge_note에서 정량적 근거 + 책임 명시 + production-mode 전환 의무 (deployment 시) 로 대체.

---

## HIGH severity ≥ 5 → Q-Lead escalate

| Concern | Codex severity | 본 agent 분류 |
|---|---|---|
| C1 Empirical FAIL | HIGH | **ACCEPT** |
| C2 Composite dilutes | HIGH | **ACCEPT** (검증 후) |
| C3 PIT-C13/C15 | HIGH | **REBUTTAL + PARTIAL** |
| C4 PIT-C9 regime same-date | HIGH | **PARTIAL ACCEPT** (lag1 test confirmed) |
| C5 AX-008 triangulation | HIGH | **REBUTTAL** (stage scope mismatch) |
| C6 AX-005/007 sufficient | MEDIUM | **REBUTTAL** (judge stage 책임) |
| C7 missing months | MEDIUM | **PARTIAL ACCEPT** |
| C8 liquidity edge | LOW | **REBUTTAL** (false positive) |

**HIGH = 5** (C1, C2, C3, C4, C5) → Q-Lead escalate trigger 충족.

---

## Strategic Recommendation to Q-Lead

본 가설 (P4 multi-horizon regime → 6-family smart beta dynamic allocation) 의 KR KOSPI200 검증 결과는 **가설 폐기 + strategic pivot 권고**:

### 폐기 근거
1. graduation criteria 5/6 FAIL (IC, ICIR, Harvey-t, DSR 모두)
2. PIT-C9 strict 시 신호 완전 소실 (regime t-1 lag test)
3. Composite < single-family (dividend ICIR 0.2081 > composite 0.0735)
4. 본 가설 mechanism (regime-conditional dynamic blending) 효과 부재

### Salvageable findings — Pivot 후보
1. **Single-family dividend tilt**: ICIR=0.2081 (graduation gate PASS), `+Z(V06_fDY) + Z(V11_Shareholder_Yield) + Z(V17_Payout_Ratio)` 단순 composite. 독립 deployment 가능.
   - 다만 single-family long-only top20 = AX-005 / AX-007 위반 risk → multi-sleeve 또는 다른 family와 조합 필요.
2. **AX-001 v2 crisis_alpha**: Bad/Normal IC ratio 2.72 — 본 가설은 stress regime에서 분별력 있음. 그러나 normal regime IC 매우 약함 → hybrid (stable: passive / stress: regime tilt) 메커니즘 검토 가치.
3. **regime classifier (Step 3) 자체는 정상 작동**: 9-state walk-forward K-means + 0.89~0.94 persistence + balanced distribution. **다른 alpha 가설의 input feature**로 사용 가능.

### Strategic Pivot 권고
- **Option A**: WT-D20260528_003 결과를 학습 기록으로 archive (graduation FAIL, signal mechanism 부재 확정). 후속 WT 생성하지 않음.
- **Option B**: Dividend single-family WT 신규 생성 (KR KOSPI200, ICIR=0.2081 baseline 활용). 단 AX-005/007 EXCLUSION 메커니즘 (multi-sleeve / ML sizing) 사전 설계 필수.
- **Option C**: P4 regime label을 STR_1715 (현 PG2) 의 sleeve allocation overlay 로 활용 가능성 검토 (regime-conditional rebalance frequency / cash overlay).

---

## Resolution Status

- Codex stance: REJECT
- Agent stance: ACCEPT REJECT (가설 폐기 + strategic pivot 권고)
- 합리화 제거: 4/4 적용
- 자율 분류 완료: ACCEPT 2 / PARTIAL 3 / REBUTTAL 3 / 1 mixed
- HIGH severity = 5 → Q-Lead escalate

**Final alpha_package**: graduation FAIL 솔직 보고 + RF-A2 + RF-A3 + RF-A4 (post-neutral 미계산 limitation 명시) + RF-A6 (graduation gate fail) + RF-A7 (3 missing months) challenge_flags retain. Discovery role card `alpha_discovery_certificate_eligible = FALSE` (Harvey 0/5 < 3 required) — passive deny per Charter v1.2 §10.

---

## References

- AX-002 process honesty (실패 보고 의무)
- AX-005 v1.2 KR defense single-family failure
- AX-007 single-sleeve top20 mechanism break
- AX-008 verification triangulation
- PIT C9 (overlay t-1) / C13 (Z_Score_Aligned) / C14 (Usable_Date) / C15 (load_month_factors)
- L-119 (composite dilution)
- L-247 답변 원칙 (정확/완결/실행가능)
- Codex critic response: `qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha.json`
- Revisions audit: `qepm/mailbox/worktask/WT-D20260528_003/outputs/codex_revisions_round1.json`
- Stage artifacts: `stage_artifacts/WT_D20260528_003/{alpha_scores, alpha_validation, codex_revisions_round1}.json`
