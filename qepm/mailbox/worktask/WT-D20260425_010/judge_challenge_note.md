# Judge Challenge Note — WT-D20260425_010 STR_1699 (REGENERATE)

## 문서 메타
- **task_id**: WT-D20260425_010
- **str_id**: STR_1699
- **judge_agent**: judge_opus47_v6.1_multigate
- **regenerated_at**: 2026-04-25T22:25:00+0900
- **regenerate_trigger**: REC-1 P1 HIGH (Architect REC-1 critical finding)
- **previous_verdict_at**: 2026-04-25T19:55:00+0900 (stale 2.5h)

---

## 1. Regenerate 사유 — Architect REC-1 critical finding

이전 `judge_verdict.json` (2026-04-25T19:55) **stale 라벨**:
- `lockbox_status: "STRUCTURALLY_UNAVAILABLE"`
- `lockbox_audit_ref: null`
- 사유: "kr_factor_returns_v2.parquet ends 2026-03-04, WML/RMW/CMA effective coverage to 2023-11" → 가정 lockbox unmeasurable

**Architect Phase E audit 발견 (architect_audit.json M12)**:
- `judge_lockbox_audit.json` 동일 시점 (2026-04-25T22:03) 작성 — `judge_lockbox_harness_v6.1.judge_lockbox_nav()` 함수 호출 성공
- Lockbox period 2024-01-23~2026-04-25 (n=549 days) 직접 NAV synthesis 측정
- KR FF5 v2 v3 backfill 의존성 = 5-spec factor regression에만 필요. **Lockbox NAV 측정에는 RAWDATA price returns만 충분**
- 즉 stale 가정은 mis-attribution

**Downstream impact**:
- Governor admission이 stale 정보 기반 deferral 결정
- Lockbox SR 1.7395 (= Pre-LB 0.914의 1.903배) evidence가 Governor PG2 active 평가에 누락
- Architect REC-1 P1 HIGH 발주 → 본 regenerate

---

## 2. 핵심 갱신 사항

### 2.1 lockbox_evaluation 갱신
| Field | Before | After |
|-------|--------|-------|
| lockbox_status | STRUCTURALLY_UNAVAILABLE | **MEASURED_VIA_HARNESS_V61** |
| lockbox_audit_ref | null | `qepm/mailbox/worktask/WT-D20260425_010/judge_lockbox_audit.json` |
| n_lockbox_months | 0 | **n_days 549 (≈ 26.4 months)** |
| Lockbox SR | (미측정) | **1.7395** |
| Lockbox MDD | (미측정) | **-25.63%** |
| Lockbox total_return | (미측정) | **147.61%** |
| Lockbox ann_ret | (미측정) | 51.62% |
| Lockbox ann_vol | (미측정) | 25.88% |

### 2.2 Pre-LB vs Lockbox SR ratio overfitting 진단 (NEW)
- **Pre-LB SR**: 0.9139 (215 months, 2006-02~2023-12)
- **Lockbox SR**: 1.7395 (549 days, 2024-01-23~2026-04-25)
- **SR ratio (pre-LB / lockbox)**: 0.5254
- **일반 overfitting pattern**: Pre-LB > Lockbox (in-sample over-tuning, 1.5~3x typical)
- **이번 case pattern**: **INVERSE — Lockbox > Pre-LB by 1.903x**
- **진단**: `INVERSE_OVERFITTING_FORWARD_VALIDATION_EXCEPTIONAL`
- **해석**: Multi-sleeve cross-family blender의 frozen weights buy-and-hold 구조가 24-26 KR equity rally + low-vol regime에서 outperform. ex-ante mis-specified parameter 회피 효과 강함

### 2.3 Forge Phase4 cross-validation
- **Judge harness (daily NAV, 549d)**: SR 1.7395
- **Forge phase4 (monthly returns, 29mo)**: SR 1.6823
- **Cross-validation delta**: +3.4% (within method noise — frequency 차이 + drift term)
- **Independent triangulation**: PASS

### 2.4 AX-008 Triangulation 갱신
| Source | Before | After |
|--------|--------|-------|
| Forge | PASS | PASS (+ Phase4 OOS extension) |
| Codex | REBUTTAL_VALID | REBUTTAL_VALID + post-Forge empirical |
| Architect | NOT_INVOKED | **PASS (architect_v6.2_ax008_3rd_source)** |
| Total | 2_of_3 | **3_of_3** |

**Architect PASS 근거**:
- v6.2 mandate 13건 중 11 PASS + 2 PASS_WITH_NOTE + 0 FAIL (compliance 100%)
- Hook architecture audit 6/6 무한루프 회피 PASS
- Multi-sleeve design soundness Y
- Production readiness 6.5/10 (PG1 Probe Phase admit 충분)
- Iter 4→5 KR FF5 v2 backfill DIRECT_CAUSAL 검증

### 2.5 Verdict 유지 vs 갱신
- **Before**: JUDGE_PASSED_WITH_NOTE (gates 6/6 + 2 NOTE)
- **After**: **JUDGE_PASSED_WITH_NOTE** (유지)
- **사유**: Lockbox 측정으로 NOTE-1 (LOCKBOX_DEFERRED) RESOLVED 처리. 단 잔존 NOTE 7건 active (Defense_Ballast labeling, CVaR_d_proxy breach, CRISIS regime n=5, RF-A1 sub_stab, regime tilt bias, baseline DSR gap). 신규 NOTE 1건 추가 (NOTE-7 Lockbox regime tilt bias, NOTE-8 Baseline DSR gap propagated from Architect REC-3)
- 즉 verdict 등급은 동일하나 evidence stack이 강화됨

### 2.6 Recommended Scenario 갱신
- **Before**: INTEGRATION_80_20 (closed-form approximation cor=0.8, SR 1.232)
- **After**: **FORGE_PHASE4_REPLACEMENT_A** (NAV-level direct synthesis)
- **사유**: Forge phase4가 Scenario A/B/D NAV-level 직접 산출 → ranking A (1.239) > B (0.907) > D (0.762). Initial closed-form approximation의 cor=0.8 가정이 NAV-level 직접 측정 시 Scenario B SR 0.6926로 supersede. **Replacement A가 dominance**

---

## 3. Phase4 fair scenario comparison (NAV-level direct)

| Scenario | SR | CAGR | MDD | DSR_post | Harvey FF5 | Risk-adj score | n_months |
|----------|----|----|----|----|----|----|----|
| **A_Replacement** | **0.9139** | **17.58%** | -34.93% | **3.022** | **3.93** | **1.239** | 215 |
| B_60_20_20 | 0.6926 | 13.33% | -57.10% | 1.925 | 2.10 | 0.907 | 190 |
| D_PG2_80_20 | 0.5791 | 11.93% | -63.32% | 1.507 | 1.78 | 0.763 | 190 |
| MEGA_05_same_period | 0.3624 | 6.65% | -81.17% | 0.787 | -0.03 | 0.585 | 215 |

**fair Δ replacement vs baseline**: ΔSR +0.5515 / ΔCAGR +10.93pp

**Lockbox supplementary**: SR 1.7395 / MDD -25.63% (549 days, frozen weights) — additional forward validation

---

## 4. 잔존 OPEN NOTE 7건 (Active)

| ID | Severity | Description |
|----|----------|-------------|
| NOTE-2 | MEDIUM | Defense_Ballast labeling (registry update 필수) |
| NOTE-3 | LOW | Integration NAV-level (phase4 supersede) |
| NOTE-4 | LOW | CVaR_d_proxy breach 4.4% (lockbox NAV로 realized 산출 가능) |
| NOTE-5 | MEDIUM | CRISIS regime n=5 small sample |
| NOTE-6 | INFO | RF-A1 sub_stab alpha-signal level (portfolio level 무영향) |
| NOTE-7 | LOW | Lockbox regime tilt bias (regime decomposition 권고) |
| NOTE-8 | MEDIUM | Baseline DSR gap (Architect REC-3 동일) |

NOTE-1 (LOCKBOX_DEFERRED) → **RESOLVED** (judge_lockbox_audit propagate)

---

## 5. Governor handoff actions

1. **REC-4 (Architect)**: Governor admission_verdict의 'AX-008 1 source PASS only' → '**AX-008 3-source PASS**' 갱신. `architect_audit.json` 결과 흡수
2. **REC-5 (Architect)**: strategy_registry에 `Core_Alpha + Defense_Ballast` role taxonomy 등록
3. **NOTE-7**: Lockbox 549d NAV regime decomposition 산출 → Bull regime 비중 과대 시 conservative SR adjustment
4. **NOTE-8 / Architect REC-3**: MEGA_05 same DSR penalty basis (15-cand × 0.05 = 0.75) 산출 → STR_1699 vs MEGA_05 fair DSR comparison
5. **NOTE-4**: Lockbox 549d daily NAV × portfolio returns로 realized CVaR_d 직접 계산

---

## 6. PIT compliance 재확인

| Check | Status | Evidence |
|-------|--------|----------|
| C_lockbox_post_cutoff | PASS | last_sig_date 2023-12-01 < lockbox_start 2024-01-23 (strict) |
| Frozen weights = no re-optimization | PASS | judge_lockbox_audit.json verdict_basis "lockbox_period_measured_directly_via_judge_harness_v6.1" |
| C1~C15 전수 | PASS | Initial verdict Gate_0 결과 유지 |
| Hash audit Pure Function R12 | PASS | pre==post md5 alpha 30dabd25 / risk a2e2bcea / opt 952106a2 |

---

## 7. Telegram brief

`tg_agent_brief(agent="Judge", ...)` 단일 진입점으로 발송. 첨부 차트:
- `04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/output/equity_curve.png`
- `04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/output/oos_zoom_chart.png`

---

## 8. 합리화 금지 자체 점검

| 합리화 phrase | 본 regenerate 사용 여부 |
|--------------|------------------------|
| "영향 미미" | 사용 안 함 |
| "관행적 허용" | 사용 안 함 |
| "보수적이면 괜찮다" | 사용 안 함 |
| "stale 그대로 OK" | 사용 안 함 (Architect 발견 명시 + lockbox_evaluation 직접 갱신) |

본 regenerate는 Architect critical finding을 honestly absorb. Stale 라벨 발견 → judge_lockbox_harness_v6.1 측정 결과 propagate → AX-008 3-source PASS 정식 라벨링.
