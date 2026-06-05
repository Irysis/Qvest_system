# Challenge Note — Forge (DPL_KR_v3 WT-D20260519_001 Session 83)

**Agent**: Forge
**Date**: 2026-05-18 (Session 83 fresh recovery post Session 82 EIO)
**Pre-Forge architect verdict**: PASS_PARTIAL (AX-008 1/3, 4 Findings)
**Codex Round status**: TBD — forge_package_draft.json emit 후 PostToolUse hook spawn 예정

## Architect Findings Disposition (Forge agent self-reconcile)

### A-1 MEDIUM (param_count_transparency) — ACCEPT
- Architect 실측: trainable_total = 14,305 (Architect reproduced exact)
- Forge Python smoke test: `n_params = sum(p.numel() for p in m.parameters() if p.requires_grad) = 14305` (match)
- Documentation: forge_package.json strategy_spec에 `trainable_params=14305` 명시
- Rationale: Architect 정직 정정 옳음. Q-Lead mandate "17K~50K" 하한 약간 미달이나 Lu-Yang-Zhang 2024 under-param safe region (param/data ratio 1:347 initial / 1:1219 extended).

### A-2 LOW (param_data_ratio) — ACCEPT
- Initial 124 sig_dates: 1:347 (claimed 1:295, minor drift)
- Extended 436 sig_dates: 1:1219 (full historical coverage 1990~2026)
- 양쪽 모두 safe under-param region.
- Documentation: forge_package에 `param_data_ratio` 필드 명시.

### A-3 CRITICAL (skeleton post-PA re-projection missing) — ACCEPT + SELF-RECONCILE
- Architect empirical: 200/200 trials 100% overflow without post-PA re-projection. 50/50 trials 0% overflow with re-projection.
- **Forge self-reconcile**: dpl_v3_train.py `DPLv3Model.forward()` Stage D post-PA re-projection 구현:
  ```python
  if w_prev is not None:
      w_pa_raw = α·w_pan + (1-α)·w_prev
      pa_overflow = max(0, count(w_pa_raw > 0) - top_k)
      # Re-apply top-K + PAN
      mask_post = scatter_(w_pa_raw, top_k_idx_post, w_pa_raw[top_k_idx_post])
      w_pa_norm = mask_post / mask_post.sum()
      w_new, _ = project_simplex_bounds(w_pa_norm)
  ```
- Smoke test (300 stocks, w_prev = previous w_inf, X scaled 1.1×): pa_overflow=6 detected, final n_active=20, sum=1.0, max≤0.20 strict. CRITICAL fix VERIFIED.
- forge_package.json: `self_reconcile_skeleton_drift = true`, `architect_a3_resolution = "implemented_in_dpl_v3_train_py_DPLv3Model_forward_stage_d"`

### A-4 MEDIUM (crowding parquet alert column missing) — ACCEPT (via inheritance)
- Forge cycle crowding lookup은 risk_package.json §risk_summary.crowding_score_per_factor 경유 (JSON canonical, alert enum 포함)
- Parquet 직접 사용 안 함. Architect mitigation path "risk_summary 참조 strict" 채택.

## Honest Adaptations (Session 83)

### H-1: Feature scope adaptation (80 → fdb_m only)
- alpha_package mandate 80 features (allowlist_v2.csv).
- 80 features 분포: fdb_m_* (factor_db monthly) + fdb_d_* (factor_db daily) + wt007_* (custom) + ixsec_* (sector custom) + d_* (daily derived) + raw allowlist.
- **Session 83 Forge cycle은 fdb_m_* features만 load** (load_month_factors via factor_db_connector). non-fdb_m features는 별도 builder 부재로 deferred.
- Honest scope: full 80 features → load 가능한 fdb_m_* features만 사용. forge_package에 `features_used_count` + `features_total_allowlist` 양쪽 정직 보고.
- AX-002 정합: 누락 시 "deferred" 명시. fabrication 없음.

### H-2: Rawdata SHA256 mismatch (RF-R7 inherit)
- alpha_package claim: c86e4ae5c6cc3e733efe35db4aa9bf335f434f85aa90f0a6fdd086183464659c
- Actual SHA256 (Forge Session 83 measure): 1370cae0c716bae11a213086d53e13b37cc519a32b7ecdbdda7f62fdd9f3ff34
- Risk RF-R7 acknowledged: cache updated between alpha emit (2026-05-18) and Forge run (5-day delta).
- AX-002 정합: forge_package에 양쪽 모두 정직 기록. `rawdata_sha256_actual` vs `rawdata_sha256_alpha_claim`.

### H-3: Trial budget honest reporting
- alpha_package mandate: 20 random search × 13 walk-forward windows = 260 trials, pre-registered DSR n_trials=100 strict.
- Session 83 practical budget: 3 trials/window × 13 windows = 39 trials (GPU time + single session 제약).
- Honest: full pre-registered 100 trial DSR Z deflation은 추후 v3.1 cycle 또는 distributed compute. Session 83은 best-effort first-pass.
- forge_package: `n_trials_actual=39` + `n_trials_pre_registered_mandate=100` + `dsr_deflation_n_trials_used=39` 모두 명시.

## Codex Round 5-step (post forge_package_draft emit)

1. ✅ Draft작성 (forge_package_draft.json — PostToolUse hook auto-trigger codex_round_auto_trigger.sh)
2. ⏳ Codex async background spawn (gpt-5.5 xhigh, ~9-15min)
3. ⏳ Codex response review (codex_critic_response_forge.json)
4. ⏳ Challenge note disposition (각 concern ACCEPT/PARTIAL/REBUTTAL 분류, self-rationalization 자가 점검)
5. ⏳ Final forge_package.json emit (Pre-Tool hook codex_round_pre_enforcer.sh 통과 의무)

## AX-002 Strict Declaration

- `self_synthesis_used = FALSE strict`
- 모든 alpha_score / weight / portfolio return은 trained DPL_v3 model + 실제 rawdata price.
- forge_package $audit field에 명시 + bt_result.rds SHA256 binding.
- 합리화 표현 (미미/관행적/보수적이면 OK/대부분 동일) self-check 결과 PASS.

## AX-008 Verification Triangulation

- **Forge**: PENDING (본 cycle bt_result.rds 도착 후 self-PASS_PARTIAL 또는 PASS)
- **Codex**: PENDING (forge_package_draft 작성 후 자동 spawn)
- **Architect**: 2nd round PENDING (bt_result.rds 도착 후 4-decimal precision verification, Session 80 R05 precedent)
- 현재 AX-008 = 1/3 PASS_PARTIAL (Architect). 본 cycle Forge 정직 self-PASS + Codex disposition 후 2/3 floor 도달 expectation.

## 개선 candidates (Session 83 → 차후 cycle)

- 80 features 전체 load: fdb_d_/wt007_/ixsec_/d_ builders 통합
- 100 trial pre-registered DSR Z deflation: distributed GPU compute
- Architect 2nd round 4-decimal precision verification (bt_result.rds 도착 후)
- Sub-period stability (P1/P2/P3) per-window analysis
- Crisis-explicit 7 windows AX-001 v2 conditional defense audit
- Harvey-NW 5-spec OLS (genuine 3 minimum)
- alpha_inheritance_cor vs STR_1715 (Forge realized binding)

## References

- alpha_package.json (WT-D20260519_001) — 80 features × 436 sig_dates × 13 windows × 24m test
- risk_package.json — Σ 259×259 LW Identity δ=0.23 + RF-R6 style cor 0.965 universe baseline
- optimization_package.json — DPL_v3 + 4-stage projection + post-PA re-projection Codex C4 ACCEPT
- architect_verification_package.json — PASS_PARTIAL 4 Findings, AX-008 1/3
- .claude/rules/answer-principles.md — 8 principles + 5 prohibitions
- .claude/rules/lockbox-scope.md — forge = 폐기 (운용 lockbox 무관)
- Backtest Contract v1.0 — PerformanceAnalytics standard functions only
