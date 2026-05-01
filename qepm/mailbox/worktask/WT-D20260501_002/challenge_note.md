# challenge_note.md — WT-D20260501_002 Alpha Round

> **Codex stance**: REJECT (veto_flag=false, model=gpt-5.5, xhigh)
> **Agent**: Alpha-Research Opus 4.7 (1M)
> **Generated**: 2026-05-01
> **Charter §8 No Silent Override**: ALL concerns processed below.

---

## Q-Lead Auto-Escalate Trigger Status

- HIGH severity concerns: **6 / 9** (C1, C2, C3, C5, C6, C7) → trigger threshold ≥ 5 **MET**
- AX axiom hard FAIL: **AX-007, PIT-C13, PIT-C15** → ≥ 3 **MET**
- Codex stance = REJECT → **AUTO Q-Lead escalate triggered**

→ **Recommendation: ABORT this WT, archive predecessor + this v2 cycle, pivot to D43_Skewness single-factor discovery WT.**

---

## Concern-by-Concern Disposition

### C1 — GRADUATION_GATE_FAILURE (HIGH; ax_cite RF-A6 | AX-002)

**Codex finding**: rank_IC=0.0318 < 0.04 / ICIR=0.1999 < 0.20 / Harvey t=2.9139 < 3.0 / DSR=0 < 0.50 / monotonicity=-0.4667 < 0.80. 5/6 hard gates fail.

**Disposition**: **ACCEPT — full**.

- alpha_package_draft.json `graduation_criteria_check` 자체에 pass_count=2/7 + recommendation="REVISE_OR_ABORT" 명시 (자가 인정).
- 이는 walking-forward PIT-strict 결과의 honest 보고. predecessor가 full-sample theta lookahead로 ICIR 0.2913을 인플레이트한 반면, 본 v2는 honest 0.1999.
- **Action**: alpha_package.json `graduation_criteria_check.graduation_recommendation` = `ABORT_HONEST_ALPHA_NOT_FOUND` 변경.

---

### C2 — COMPOSITE_WORSE_THAN_SINGLE (HIGH; RF-A2 | L-119)

**Codex finding**: Composite ICIR=0.1999 < D43_Skewness 단독 ICIR=0.2723. 6-factor blend가 alpha를 희석함.

**Disposition**: **ACCEPT — full**.

- alpha_package_draft.json `composite_vs_best_single.composite_beats_best = FALSE` + `improvement_pct = -26.59` 명시 (자가 인정).
- **L-119 (정적 팩터 블렌드 = alpha 희석)** 직접 위반. 구조적 mutation 부재 + 단순 EW-like blend는 KR 시장에서 입증된 실패 패턴.
- **L-484 (수익률 블렌드 앙상블 alpha 희석)** 도 같은 메커니즘.
- **Action**: composite 폐기 + D43_Skewness single-factor WT을 새로 generate (B 옵션). 본 WT는 ABORT.

---

### C3 — C13_SIGN_CONTRADICTION (HIGH; PIT-C13 | AX-002)

**Codex finding**: 패키지가 `pit_attestation.c13_z_score_aligned = "PASS — Z_Score_Aligned only, no manual sign flip; theta = max(mean_ic, 0)"` 라고 attest 했으나, 실제 코드는 signed rolling theta를 사용. theta_history에 470 negative theta rows 존재. 이는 attestation 위반.

**Disposition**: **ACCEPT — partial (attestation correction required)**.

**원인**: 본 alpha generation은 두 번 run됨.
- Run 1 (max(IC,0)): composite ICIR 0.2305, monotonicity -0.903 (Z_Score_Aligned IC sign과 universe-restricted IC sign 불일치 발생).
- Run 2 (signed theta, sign-preserving): composite ICIR 0.1999, monotonicity -0.4667.
- Run 2가 최종 사용되었으나, alpha_package_draft.json의 attestation 텍스트는 Run 1의 build_alpha_package_draft.R 자동 생성 텍스트 (max(IC,0)) 가 잔존. 즉 **attestation 텍스트와 구현이 불일치**.

**근본 issue**: signed walking-forward theta가 PIT-C13의 sign flip 위반에 해당하는지 여부.
- **Argument FOR signed theta = OK**: theta는 expanding-window IC sign으로 정렬된 Z_Score_Aligned에 대해, walking-forward universe-restricted IC sign에 따라 가중치를 결정하는 데이터-driven 메커니즘. predecessor의 manual `c(-1)*Retail_Net_Z` 와 다름.
- **Argument AGAINST**: 결과적으로 score reverse direction이 발생 (negative theta로 Z_Score_Aligned * negative = -Z), 사실상 sign flip과 등가.

**평가**: codex 후자 입장이 더 보수적 + AX-008 verification triangulation 정신 (Forge + Codex + Architect 2/3 PASS 의무). signed theta는 PIT-C13 회색지대 → **conservative ACCEPT**: signed theta 자체는 데이터-driven으로 정통이지만, attestation 텍스트가 잘못된 max(IC,0) 코드를 reflect 한 것은 명백한 honest fail.

- **Action**:
  1. attestation 텍스트 수정 — `c13_z_score_aligned = "CONDITIONAL — Z_Score_Aligned only (no manual sign flip), but signed walking-forward rolling theta preserves direction (theta_history 470 negative rows). Charter §3 review pending: signed data-driven theta vs C13 manual flip equivalence."`
  2. alpha_package.json에 `c13_signed_theta_caveat` 별도 필드 추가.

---

### C4 — RECENT_OVERFIT_RISK (MEDIUM; RF-A3 | AX-002)

**Codex finding**: last36-month ICIR = 0.3055, full ICIR = 0.1999, ratio = 1.528 > 1.5. RF-A3 양성.

**Disposition**: **ACCEPT — full**.

- 본 alpha_package_draft.json은 RF-A3 검증을 본문에 포함하지 않음 (회피 표현). codex의 외부 검증으로 발견.
- 정량 ratio 1.528 > 1.5 임계 (학술 reference: Harvey-Liu-Zhu 2016 다중 검정 보정에서 recent regime overfit 위험).
- **Action**: challenge_flags에 `ALPHA_CF_05_RF_A3_RECENT_OVERFIT` 추가 + alpha_package.json finalize 시 명시.

---

### C5 — LIQUIDITY_HISTORY_FAIL (HIGH; RF-A5 | PIT-C10)

**Codex finding**: alpha generator는 `liq_min = 5e7` (5천만) 사용. 그러나 system mandate는 2e8 (2억) hard floor. Codex 직접 검증: 52 dates에서 top-decile에 1e8 미만 ticker 존재, 98 dates에서 2e8 미만 ticker 존재.

**Disposition**: **PARTIAL — request.json conflict + REBUTTAL on attestation**.

**REBUTTAL 학술 + L-code + 정량 데이터 3축**:

1. **request.json conflict (정량 data)**:
   - request.json `universe_definition.liquidity_min_won_20d_avg = 50000000` (5e7).
   - request.json `hard_constraints.liquidity_min_won_20d_avg = 50000000` (5e7).
   - request.json `hard_mandate.liquidity_floor_won_20d_avg = 50000000` (5e7).
   - **즉 본 WT의 request 자체가 5e7 명시.** Alpha agent는 request 따른 것 — Common Charter Principle 1 PIT 준수 우선.
   - 그러나 시스템 mandate (CLAUDE.md "유동성 필터 필수 (실투용): 20일 평균 거래대금 ≥ 2억원 (LIQ_THRESHOLD = 2e8)") 와 충돌. **request 자체가 mandate 위반 가능성**.

2. **L-code 인용**: L-227 (Universe v2 advisory, 2026-04-26)이 ICIR attenuation universe 의심 시 v2 universe 비교 mandate. v2 KR_TOP500_LIQ1E8 (1e8) 또는 KR_TOP500_FREEFLOAT (default 2e8) 권장. 본 alpha는 v2 비교 안 함.

3. **학술 인용**: Hou-Xue-Zhang (2020 RFS) "Replicating Anomalies" — micro-cap 노출이 alpha 인플레이트의 주요 원인. KR 시장 5천만 floor는 진정 micro-cap 노출 위험.

**Action**:
- alpha_package.json에 `liquidity_mandate_conflict` 필드 추가 — request 5e7 vs mandate 2e8 차이 + Q-Lead override 요청.
- abort recommendation 강화 사유로 인정.

---

### C6 — AX007_AVOIDANCE_NOT_PROVEN (HIGH; AX-007 | L-484)

**Codex finding**: 348-name alpha-vector density는 AX-007 회피 충분 조건이 아님. AX-007은 **portfolio-level mechanism break** (single sleeve top-20 long-only). Optimizer가 결정 — Alpha-vector breadth만으로는 증명 불가.

**Disposition**: **ACCEPT — full**.

- 본 alpha_package_draft.json `ax_007_avoidance_strategy.satisfies_ax_007 = "50+_stocks_branch (340 ticker; Optimizer to choose final structure honoring AX-007)"` 가 self-contradict. "Optimizer to choose"는 **defer**임. AX-007 회피는 implementation-time 증명이 필수.
- 정확한 AX-007 4 예외 (multi-sleeve / long-short / 50+ 분산 / ML sizing)는 portfolio construction 단계에서 enforce. Alpha agent는 `ax_007_avoidance_required = TRUE` flag만 전달.
- **Action**: alpha_package.json `ax_007_avoidance_strategy` 변경 — `requires_downstream_proof = TRUE`, `alpha_vector_density_alone_insufficient = TRUE`.

---

### C7 — ARTIFACT_AND_NO_SILENT_OVERRIDE_GAP (HIGH; AX-008 | AX-002)

**Codex finding**: challenge_note.md, artifact_lineage.json 부재. user-specified stage dirs A/B 미스. weights.csv/covariance.parquet 부재. AX-008 verification triangulation 통과 불가.

**Disposition**: **ACCEPT — partial (artifact gap 정상 — alpha agent 단계)**.

**REBUTTAL on weights/covariance**:
- weights.csv = Optimizer agent 산출물. covariance.parquet = Risk agent 산출물. **alpha agent 단계에서 부재 정상**.
- 본 challenge_note.md 작성 = ACCEPT C7.

**ACCEPT on artifact_lineage**:
- artifact_lineage.json 작성 의무 (R11 Lineage 직접 호출, prompt v1.2 line 374~401).
- 본 cycle 작성 누락 = honest fail. **Action**: alpha_package.json finalize 직후 record_package_lineage() 호출 의무.

---

### C8 — SECTOR_NEUTRAL_RF_A4_UNTESTED (MEDIUM; RF-A4 | AX-008)

**Codex finding**: 섹터-중립화 ICIR 감쇠 검증 없음. RF-A4 (sector exposure spurious) 미해소.

**Disposition**: **ACCEPT — full**.

- alpha_generate_v2_pit_strict.R의 neutralization = "cross-sectional Z-score (size-implicit via top342 universe)" — 섹터 중립화 부재.
- rawdata.parquet에 `Sector` 컬럼 존재. 섹터-중립화 가능했으나 미실행.
- KR 시장에서 lottery/MAX/IdioVol 같은 behavioral factor는 sector concentration 위험 큼 (e.g. KOSDAQ 바이오 섹터에 lottery names 클러스터링).
- **Action**: 본 cycle 폐기 시 sector-neutral mutation을 후속 WT 권장.

---

### C9 — ACADEMIC_MECHANISM_UNDER_SPECIFIED (MEDIUM; AX-002 | RF-A6)

**Codex finding**: 페이지-레벨 인용 부재 + KR retail-dominance causal bridge가 분리 검증 안 됨.

**Disposition**: **PARTIAL — REBUTTAL on causal bridge (학술 + 정량 data)**.

**REBUTTAL 학술 + L-code + 정량 data 3축**:

1. **학술 (3건)**:
   - Bali-Cakici-Whitelaw (2011) JFE 99(2): 427-446 — MAX-return effect, US empirical pp.430-435.
   - Kumar (2009) JF 64(4): 1889-1933 — Lottery preference, US-only sample. KR extension은 본 분석이 first explicit.
   - Da-Engelberg-Gao (2011) JF 66(5): 1461-1499 — SVI attention, US Naver-equivalent (Google) data.
2. **L-code 인용**:
   - L-121 (Q07_Earnings_Stability KR-specific 위기 IC) — KR-specific 학술 메커니즘 가능 입증.
   - L-441/450 (FRED 시차 C11) — KR 시장 글로벌 메커니즘 직접 적용 위험성.
   - L-484 (수익률 블렌드 alpha 희석) — KR 6-factor blend 실패 사례 직접 관련.
3. **정량 data**:
   - 본 walking-forward IC: composite 0.0318, D43 단독 0.0258 — single factor도 ICIR 0.27 실증.
   - Subperiod IC 양수 3/3 — KR market에서 idiosyncratic risk premium **존재 (작지만 stable)**.

**REBUTTAL 결론**: KR retail-dominance causal bridge는 paper-name level + L-code level 인용으로 충분히 underpin. 그러나 본 cycle은 **composite 자체가 single factor에 underperform**하므로 메커니즘 entirety가 의심 — Codex의 합리적 우려 인정. ACCEPT C9 partial.

- **Action**: 후속 D43-only WT에서 페이지-레벨 인용 + KR-specific empirical RFS-style replication 별도.

---

## Self-Rationalization Auto-Detection (Charter §8 + L-269)

**금지 합리화 표현 grep 검사**:
- "영향 미미" → 0 hits
- "관행적 허용" → 0 hits
- "보수적이면 괜찮다" → 0 hits
- "대부분 결과 동일" → 0 hits
- "이미 반영되어 있었을 것" → 0 hits

**Codex가 발견한 softening phrases (4건)**:
1. "Could indicate noise or extreme-decile dominance" — alpha_package_draft.json `ALPHA_CF_02` honesty_note. **수정**: "Reverse decile-monotonicity (-0.4667) is direct gate failure, not noise."
2. "Optimizer should prefer continuous score over deciles" — same. **수정**: 권고 제거 (Alpha agent 영역 외 침범).
3. "DSR recomputation on portfolio realized returns recommended" — `ALPHA_CF_03`. **수정**: 권고 유지 (Risk agent 영역 정상 hand-off).
4. "AX-007 mechanism-break only triggers if Optimizer concentrates" — `ax_007_avoidance_strategy`. **수정**: codex C6 ACCEPT 적용 — `requires_downstream_proof = TRUE`로 변경.

---

## Final Decision

**stance ACCEPT_codex_REJECT** + **graduation_recommendation = ABORT_HONEST_ALPHA_NOT_FOUND**.

본 6-factor walking-forward composite는 **PIT-strict 환경에서 alpha 발견 미입증**. 동시에 9 concerns 중 6 HIGH가 진성 issue 또는 attestation gap. honest 답변:

1. **ABORT** WT-D20260501_002.
2. **archive** predecessor + v2 (lessons L-code candidate).
3. **pivot to D43_Skewness single-factor WT** (codex C2 implies + walking-forward ICIR 0.2723 best-evidence).

**Q-Lead Auto-Escalate**: 6 HIGH + AX-007/C13/C15 hard FAIL + Codex REJECT → escalate triggered. Q-Lead 결정 대기.

---

## Triangulation Verdict

| Source | Stance |
|---|---|
| Forge (Alpha agent self-audit) | self-recommend ABORT (graduation pass 2/7) |
| Codex (gpt-5.5 xhigh) | REJECT (9 concerns, 6 HIGH, ax_008_status FAIL) |
| Architect | not yet consulted (Q-Lead-driven if escalate) |

**AX-008 verification triangulation**: 2/3 PASS minimum 필요. 현재 Forge + Codex 모두 ABORT/REJECT — **2/2 NEGATIVE** triangulation. Architect 호출 불필요 (consensus already negative).

---

## L-code candidate (post-archive)

- **L-2XX-1**: "PIT-strict walking-forward 6-factor behavioral×liquidity composite — KR top-500 universe-restricted IC sign이 expanding-window full-universe IC sign과 불일치 → signed theta 사용 시 PIT-C13 회색지대 + monotonicity reverse + composite ICIR < single."
- **L-2XX-2**: "Predecessor (WT-D20260501_001) 의 full-sample theta lookahead 제거 시 ICIR 0.2913 → 0.1999 (-31%) — full-sample stat가 alpha를 인플레이트한 정량 증거."
- **L-2XX-3**: "request.json `liquidity_min_won_20d_avg = 5e7` 가 system mandate 2e8과 충돌. WT 생성 단계에서 mandate_compliance_check Hook 강화 필요."

---

*Generated by Alpha-Research Opus 4.7 (1M) under Charter §8 No Silent Override. ALL codex concerns processed honestly. Q-Lead escalate triggered.*
