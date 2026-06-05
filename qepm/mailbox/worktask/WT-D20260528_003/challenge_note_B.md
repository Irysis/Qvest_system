# Challenge Note — WT-D20260528_003 Hypothesis B (STR_1724 Bali MAX Pure)

**Charter v1.7 §8 No Silent Override compliance**

**Generated**: 2026-05-28 KST (overnight parallel research, hypothesis B)
**Codex critic response**: `codex_critic_response_alpha_B.json` (stance=REJECT, 8 concerns)

---

## Codex Round Decision Protocol (자율 분류)

본 challenge_note는 Codex critic 8 concerns에 대한 ACCEPT / PARTIAL / REBUTTAL 명시. Codex stance=REJECT를 base agent가 추가 검증 후 **TERMINATE 결론에 부합하므로 대부분 수용** (단 1건 REBUTTAL).

---

## C1 — n_trials=1 framing inconsistent with Phase 1/3 lineage

**Codex severity**: HIGH
**Codex 지적**: "M22 treated as pure single factor, no candidate selection penalty, despite admitted Factor DB Phase 1/3 selection context. DSR n=269 collapses to 1.5392e-97."

**Self-classify**: **PARTIAL ACCEPT**

**Rationale**:
- Draft `lineage.phase1_pit_caveat` 에 명시: "M22 selection은 Bali 2011 academic literature a-priori 채택, NOT Phase 1 ranking output". 그러나 lineage admits screening 일치 — academic + factor_db convergence.
- Codex 정합: M22가 Phase 1 candidates 중 하나로 Factor DB에 등재된 사실 자체가 weak selection bias (1/269) 형성. 단 등재는 학술 citation 보존이 의도이지 selection 결과가 아님.
- **수용**: dsr_selection_n_trials_269 = 0.0 explicitly provided in draft. transparency 확보.
- **부분 거부**: Bali 2011 + 200+ citations 학술적 a-priori는 단순 random 269-trial selection과 다른 prior. 다만 honest Coverage 위해 **두 DSR 모두 graduation FAIL 결과** 동등 (n=1 baseline은 통과해도 selection FAIL).
- **Net**: 최종 graduation FAIL 결론은 동일. 단어 reframe: "n_trials=269 conservative criterion under" (academic prior 약화 인정).

**Action**: alpha_package_B.json `lineage.selection_corrected_dsr_caveat` 강화 — "TERMINATE 결정은 두 DSR framing 모두 FAIL로 robust".

---

## C2 — rank_ic 0.0226 + subperiod 0.375 FAIL

**Codex severity**: HIGH
**Codex 지적**: "Core Alpha Lab gates fail: rank_ic 0.0226 < 0.04, subperiod_stability 0.375 < 0.50. Positive ICIR alone insufficient."

**Self-classify**: **ACCEPT**

**Rationale**:
- Draft `graduation_criteria_check.failed_gates = ["rank_ic", "subperiod_stability", "dsr_selection_n269"]` 명시. Codex 지적 완전 일치.
- Draft `verdict_self = "TERMINATE"` 결정 사유의 핵심.
- L-484 (sleeve break) + L-160/165/166 (single-sleeve 메커니즘 단절) 정합.
- **Action**: No change. 이미 reflected.

---

## C3 — Top20 active negative + AX-007 violation

**Codex severity**: HIGH
**Codex 지적**: "Top20 active -0.1224%/month t=-0.666, single-sleeve top20 long-only with no AX-007 exception."

**Self-classify**: **ACCEPT**

**Rationale**:
- Draft `ax_compliance.AX_007.status = "VIOLATION"` 명시. evidence: "Single-sleeve top20 long-only design with NO exception applied".
- Draft `challenge_flags[RF-A7-EQUIVALENT].severity = "HIGH"` 명시. evidence: "top 20 sleeve active return = -0.122%/month with negative t-stat (-0.67)".
- L-484 정합 — 'factor exists, sleeve does not'.
- **Action**: `follow_up_recommendations` 에 multi-sleeve 또는 50+ 변형 명시 — Codex와 일치.

---

## C4 — Defensive role broken (crisis IC -0.0195)

**Codex severity**: HIGH
**Codex 지적**: "Crisis IC=-0.0195, bad/normal ratio=-0.9498, crisis_minus_normal=-0.04. Cannot be sold as defensive alpha."

**Self-classify**: **ACCEPT**

**Rationale**:
- Draft `ax_compliance.AX_001_v2.status = "FAIL"` + evidence 동일.
- Draft `diagnostics.ax_001_v2.interpretation`: "Defensive role HARD FAIL... Suggests Bali MAX in KR market is risk-on alpha factor, not defensive lottery anomaly."
- Original Bali 2011 (US 1962-2005) defensive 특성과 KR market 차이 — KR retail-driven structure 자체가 lottery preference 시기 변동. 채택 framing 자체 변경 필요.
- **Action**: hypothesis_description 에 "Original Bali 2011 defensive characterization NOT replicated in KR — M22 is risk-on/elevated-regime factor in KR market" 추가.

---

## C5 — monotonicity_neut=-0.5758 marked PASS via abs() — direction inverted

**Codex severity**: HIGH (GOLD CATCH)
**Codex 지적**: "monotonicity_neut=-0.5758 marked PASS using abs() >= 0.5, but negative decile Spearman + D10-D1=-0.1401%/month means long-top-decile trading direction INVERTED."

**Self-classify**: **ACCEPT** (Codex GOLD CATCH)

**Rationale**:
- Step 5 validation script: `pass = !is.na(monotonicity_neut) && abs(monotonicity_neut) >= 0.5` — abs() 적용 정합 X.
- Long-top-decile sleeve (Z_neutral high = D10 = expected highest fwd_ret) 정합 조건: **signed** monotonicity > 0.5.
- Re-check: D10 = 0.7823%, D1 = 0.9224%. **D10 < D1 + D10 sleeve buy signal에 음수 영향**.
- 이건 IC=+0.023 (positive cross-sectional rank) vs decile pooled monotonicity -0.576 모순처럼 보이나 실제: cross-sectional 정렬은 미약 양, **pooled decile rank**는 sleeve 단위 음. **portfolio translation 결정적 손상**.
- Codex 지적이 graduation 결정에 critical — single-sleeve top20 long-only **direction inverted**.
- **Action**: validation script logic fix — `pass = signed_monotonicity >= 0.5` (not abs). 새 결과: monotonicity_neut FAIL (-0.576 < 0.5).
- **Updated failed_gates**: ["rank_ic", "subperiod_stability", "dsr_selection_n269", "monotonicity_neut_signed"].
- **결정**: TERMINATE 결정 더욱 robust.

---

## C6 — Harvey 1-spec only, missing 5-spec FF/Carhart/CAPM matrix

**Codex severity**: MEDIUM
**Codex 지적**: "Harvey base mandate requires multi-spec including CAPM/Carhart/FF5; only 1 rank-IC t reported."

**Self-classify**: **PARTIAL ACCEPT**

**Rationale**:
- Codex 정합: Harvey-Liu-Zhu 2016 "Lucky factors" methodology는 multi-specification testing (CAPM α, Carhart 4F α, FF5 α 등) 의무.
- 본 단일 cross-sectional rank IC t=3.97 robust to 1-spec testing — 그러나 5-spec matrix 부재 명시 limit.
- **수용**: 5-spec absence는 gap. 단 graduation은 이미 3 gate FAIL → 5-spec 추가 결과가 결정 바꾸지 않음 (전혀 통과 불가능).
- **부분 거부**: pure 1-factor hypothesis B에 5-spec full regression 의무는 over-engineering — 본 hypothesis는 단순 ranking 기반 alpha. 단 next iteration에서 추가 검증 권고.
- **Net**: 학술 검증 strict 기준 5-spec 부족 명시 + 본 hypothesis 1-spec 결과 (3.97)와 graduation FAIL 결정 robust.

**Action**: `factor_specs[0].diagnostics_caveat`: "Harvey t=3.97 reported is 1-spec (raw rank IC vs fwd_ret). Multi-spec FF5/Carhart α t-stat NOT computed in current analysis. Future iteration: recommend Bali 2011 §5 spec matrix replication (CAPM α / 3F α / 4F α / 5F α) before any reconceptualization advances."

---

## C7 — challenge_note + artifact_lineage absent for B

**Codex severity**: MEDIUM
**Codex 지적**: "Root challenge_note.md + artifact_lineage.json describe STR_1722/v3.7, not B. B-specific challenge trail incomplete."

**Self-classify**: **ACCEPT**

**Rationale**:
- 도훈 mandate 명시: hypothesis B는 `_B` suffix files (challenge_note_B.md / alpha_package_B.json / codex_critic_response_alpha_B.json) 분리. Codex가 root challenge_note.md (hypothesis A 산출) 참조해서 mismatch 감지 정합.
- **본 challenge_note_B.md 작성이 곧 ACCEPT 응답**.
- **Action**: artifact_lineage_B.json 동일 분리 생성 — 본 작업 후속 Step.

---

## C8 — weights.csv + covariance.parquet absent

**Codex severity**: MEDIUM
**Codex 지적**: "Requested downstream verification artifacts absent (weights.csv, covariance.parquet) → AX-008 triangulation incomplete."

**Self-classify**: **REBUTTAL**

**Rationale (학술 + L-code + 정량 data 3축)**:
- **Charter §8 + Hook 강제**: Alpha Agent는 covariance matrix 추정 + portfolio weights 제안 **절대 금지** (PreToolUse Hook block — `agent_role_guard.sh` Tier 2).
- `02_Infrastructure/prompts/alpha_research_init.md` line 92-100 `<strict_prohibitions>`: "공분산행렬 추정 금지 — Risk Agent 영역 / 포트폴리오 비중 제안 금지 — Optimizer Agent 영역 / 위반 시 Hook block + AX-002 위반".
- **L-269 Codex Round Decision Protocol §3**: 합리화 표현 사용 시 auto RE-VIEW. "관행적" "보수적이면 OK" 미사용. 명시적 role boundary 인용.
- **정량 data**: weights.csv / covariance.parquet 부재 ≠ alpha_package 결함. AX-008 triangulation은 **Risk + Optimizer + Forge agent spawn 후** 완성 의무 — Alpha agent role 침범 시 Hook L3 block.
- **Bali 2011 reference**: Bali et al. paper는 cross-sectional regression 결과만 제공, portfolio weights는 separate sleeve construction step. 본 hypothesis pure alpha discovery 동일 scope.
- **Counter-evidence accepted**: weights.csv + cov.parquet absence는 alpha_package_B 결함 NOT, **next-stage agent spawn 의무**. Q-Lead 가 Risk + Optimizer agent spawn 명령해야 함 (REJECT verdict 후 일반적으로 NOT spawn — TERMINATE면 충분).

**Conclusion**: Codex C8 지적은 Alpha agent role boundary 무이해. AX-008 triangulation 완성은 Q-Lead orchestration scope. 본 alpha_package_B 단계에서 weights/cov 산출 = role violation. **거부 + 명시적 boundary 인용**.

**합리화 grep check** ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적"): NONE ✓.

---

## Q-Lead Escalate Triggers Check

- **HIGH severity ≥ 5**: 5 (C1, C2, C3, C4, C5) → **TRIGGER**
- **AX axiom hard FAIL ≥ 3**: AX-001 v2 + AX-007 + AX-008 PENDING = 3 → **TRIGGER**
- **PIT C1 위반 발견**: NO (Codex C1 is selection bias not PIT)
- **Codex stance=REJECT + agent rebuttal ALL**: NO (1 of 8 rebuttal, 7 accept/partial)

**Q-Lead escalate 필요 여부**: YES (HIGH ≥ 5 AND AX hard FAIL ≥ 3). 단 본 hypothesis는 **verdict=TERMINATE** 자체 결정이라 Q-Lead 가 PG1 admission으로 진행할 일 없음. **Q-Lead morning retrieval 시 brief 통지 충분** (도훈 sleep mode).

---

## Verdict Summary

**Final verdict**: **TERMINATE** (consistent with draft self-assessment, reinforced by Codex 7/8 ACCEPT + 1/8 REBUTTAL).

**Gates failed (updated post-Codex C5 fix)**:
1. rank_ic 0.0226 < 0.040
2. subperiod_stability 0.375 < 0.500
3. dsr_selection_n_trials_269 = 1.5392e-97 ≪ 0.500
4. **monotonicity_neut signed -0.576 < +0.500 (Codex C5 fix)**

**AX hard FAILs**:
- AX-001 v2 — crisis IC -0.0195 (defensive role broken)
- AX-005 — 2020-2026 ICIR decay -58% (BAB-type weakening partial support)
- AX-007 — single-sleeve top20 active -0.122%/m t=-0.67 (sleeve break)

**No advancement** to PG1 admission. **Recommend lessons**:
1. M22 reconceptualization: risk-on / momentum-cluster factor in KR (not defensive)
2. Pair with verified defensive factor in multi-sleeve (AX-007 exception 1)
3. Test top 50+ diversified or long-short variant (AX-007 exception 2/3)
4. Add 5-spec matrix (FF/Carhart) before any next iteration (Codex C6 partial)

**Lockbox lockdown**: signal_cutoff=2023-12-22 lockbox compliance verified (C1+C13+C14+C15+Cycle 51 shift all PASS).

---

## Files written

- `qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft_B.json` (Step 6 draft)
- `qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha_B.json` (Codex Round Step 3)
- `qepm/mailbox/worktask/WT-D20260528_003/challenge_note_B.md` (본 파일, Step 4)
- `qepm/mailbox/worktask/WT-D20260528_003/alpha_package_B.json` (Step 5 final — 작성 예정 post-validation fix)
- `qepm/mailbox/worktask/WT-D20260528_003/artifact_lineage_B.json` (post-Codex C7)
- `stage_artifacts/WT_D20260528_003_overnight_B/alpha_scores.parquet`
- `stage_artifacts/WT_D20260528_003_overnight_B/alpha_validation.json`
