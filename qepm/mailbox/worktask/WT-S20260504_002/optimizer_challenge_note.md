# optimizer_challenge_note — WT-S20260504_002 (DCC_Vol_Target sizing_only)

**Agent**: optimizer-research
**Round**: 1
**Pre-Codex draft**: `optimization_package_draft.json`
**Codex response**: `codex_critic_response_optimizer.json` (round 1 dispatched, awaiting/timeout-tolerant)

---

## 1. Self-Audit (회피 표현 grep, pre-Codex)

| 표현 | 검출 | 처리 |
|---|---|---|
| 영향 미미 | 0건 | — |
| 관행적 허용 | 0건 | — |
| 보수적이면 괜찮다 | 0건 | — |
| 대부분 결과 동일 | 0건 | — |
| 이미 반영되어 있었을 것 | 0건 | — |
| 백테스트 충분히 길어서 상쇄 | 0건 | — |
| 유사/거의/대략/근사 | 1건 (expected_metrics_estimate "tentative") | 추정 라벨 (`production_grade=false`) 명시. 실제 metrics 는 forge phase backtest 결과로 갱신. |

**결과**: 회피 합리화 0건. 추정 영역은 `method_basis_label = "optimizer_recommendation_pre_forge"` + `production_grade = false` 명시.

---

## 2. 핵심 의사결정 4건 — 자기 비판

### 2.1 weights.csv schema = 부모 sleeve-level 유지 (per-ticker target_weights dict 미생성)

**결정**: `Date, weight_str1715, weight_cash` 3-column sleeve-level. 부모 WT-P20260429_002/weights.csv 와 동일 schema.

**근거**:
- sizing_only WT — 신규 alpha + 신규 ticker 선정 없음. STR_1715 sleeve 자체를 1-단위 자산으로 다룸.
- 부모 forge_package + parent run_all.R 이 sleeve 내부 per-ticker constraints (max 20, [0, 0.20], inside-sleeve Σ=1) 강제. 본 sizing_only optimizer 는 그 위 layer 의 sleeve-vs-cash allocation 만 결정.
- worktask_constraint_enforcer.sh 는 `target_weights` dict 가 없으면 `no_target_weights` 로 allow (line 53). Per-ticker hard-cap 검증 path 가 sleeve-level WT 에 부적절하므로 이 schema 가 정확한 분기.

**약점 인정**:
- `target_weights` dict 가 없으니 max 20 / per-ticker bound / Σ_per_ticker = 1 검증을 본 layer 에서 trigger 못 함. 이는 부모 strategy 에 위임된 invariant.
- Codex 가 "optimizer 는 per-ticker 결정 의무" 비판 가능. 그러나 sizing_only role_card 는 그 역할 분리.

**처리**: `constraints_enforced.weight_bounds_per_ticker = [0, 0.20]` 명시 + "inherited from parent run_all.R" 라벨. `weight_bounds_sleeve = [0, 1]`, `sigma_w_sleeve = 1.0` 별도 명시.

### 2.2 Cash combination rule = max(M4_cash, DCC_cash) — additive 거부

**결정**: `weight_cash_combined = max(weight_cash_M4, weight_cash_DCC)`, `weight_str1715 = 1 - weight_cash_combined`.

**근거**:
- 단일 cash sleeve 의미 보존 (M4 도 DCC 도 같은 cash_KRW 자산을 호출).
- Additive 시 Σ=1 breach: 12 months 에서 M4 + DCC > 1.0 → sleeve weight < 0 (long-only 위반).
- max() 는 항상 defensive (보다 큰 cash 호출 측이 dominate, 소수 조건 무시 안 함).
- Interpretability: 매 월 어떤 overlay 가 cash drive 했는지 명확 (`cash_definition_audit.json::dominance_when_both_active`).

**약점 인정**:
- max() 는 두 신호의 "intersection of agreement" 정보를 일부 소실 (둘 다 active 이면 더 strong defense 의미). 하지만 sleeve 한계 [0,1] 내에서 이 정보 활용은 cap 충돌.
- weighted_avg (e.g. 0.5×M4 + 0.5×DCC) 는 stress 시 max 보다 작은 cash → defensive 약화 → mdd_target ≤ -25% 와 충돌.

**처리**: `cash_combination_rule.alternatives_considered` 3안 명시 (additive_capped / weighted_avg_50_50 / max_dominant) + 각 reject 사유. `cash_definition_audit.json` 에 dominance + activation matrix 정량 기록.

### 2.3 Method shopping = 3 candidates only (HRP/MVO/CVaR 미포함)

**결정**: S1 / DCC_VolTarget / M4+DCC_VolTarget 3건만 비교. HRP/MVO/CVaR/ERC/BL 등 미시도.

**근거**:
- request.json `statistical_factor_model.method = "DCC_GARCH_Vol_Target"` 명시 — method 자체 고정 mandate.
- sizing_only WT — alpha vector + Σ 조합으로 weights 새로 풀지 않음. 부모 sleeve 의 vol-target sizing 단일 결정.
- HRP/MVO/CVaR 는 per-ticker weight 결정 method (alpha + Σ 입력). sleeve-level [0,1] vol scaling 에 부적절.

**약점 인정**:
- `method_shopping_log.candidates_tried = 3` 은 R2-C 상한 10 보다 매우 적음. method-shopping 다양성 부족 비판 가능.
- 그러나 R2-C 상한은 method 다양성 권장이지 강제 mandate 아님 (overfitting 방지). sizing_only 본질에 맞지 않는 method 추가는 token waste.

**처리**: `method_shopping_log.candidates_tried = 3` + `method_log` 에 각 reject_reason / select_reason 명시. `parallel_exec = false` rationale ("3 variants are deterministic transforms, sequential <1 sec, parallel overhead > work").

### 2.4 Forward May 2026 cash 58.1% — 268m 사상 최대 cash bridge

**관찰**: DCC σ_p forecast 5월 35.8% annual vs target 15% → scale_factor 0.42, cash_bridge 58.1%. M4 5월 NORMAL regime → M4 cash 0%. 결합 cash = max(0, 0.581) = 0.581.

**자기 비판**:
- 268m 표본 mean cash 28.2%, std ~15% → 5월 58% 는 +2σ outlier.
- DCC params 가 2022-07 ~ 2026-04 표본 (T=928d) 추정 → 최근 vol-rich 국면 (Iran War 2026, 반도체 cycle) overfit 가능성.
- σ_p 35.8% → 1m forward 가 mean-reversion 으로 30% 미만 강하면 cash 58.1% 는 over-defensive.

**처리**: `challenge_flags` RF-O-LAYER-A-FORWARD-EXTREME (HIGH) 명시. forge backtest 후 5월 1개월 realized vol 측정 + post-hoc audit 계획. 본 추정 round 에서 cash 58.1% 채택 — 도훈 mdd_target 우선 정책 + risk_package vol_target_decision (fixed 15% min rule) 인계.

---

## 3. Codex 비판 사전 대응 plan

### 3.1 예상 concern + Defense

| 예상 concern | Defense type | 근거 |
|---|---|---|
| "method_shopping 3건만 — R2-C 상한 10 미달, 다양성 부족" | REBUTTAL | sizing_only mandate `method = DCC_GARCH_Vol_Target` 고정 + sleeve-level [0,1] vol scaling 에 HRP/MVO/CVaR 부적절. `method_shopping_log.candidates_tried = 3` 은 task-fit. R2-C 는 권장이지 hard cap 아님 (method shopping 과적합 방지 목적). |
| "max() vs additive — additive 가 더 conservative defense" | REBUTTAL | additive 시 Σ=1 breach 12 months → long-only violation (Hard Constraint AX-002 위반). max() 가 defensive + Σ=1 보존 + interpretable. 학술 기반: Brinson-Hood-Beebower (1986) attribution 단일 cash sleeve 표준. L-274 STR_1715 PG2 single-cash-sleeve 정책 직접 참조. |
| "AX-001 v2 PARTIAL — CRISIS state alpha surrender 정량 평가 부재" | PARTIAL ACCEPT | 본 optimizer round 는 backtest 안 함 (sizing_only). Forge phase 가 정량 측정. `ax_001_v2_conditional_handoff.downstream_obligation` 에 forge backtest 의무 명시. |
| "S1 baseline metrics 가 추정 (production_grade=false) — 비교 무효" | REBUTTAL | sizing_only WT — 새로운 backtest 안 함. `expected_metrics_estimate.method_basis_label = optimizer_recommendation_pre_forge` 명시 + `production_grade = false` 라벨. forge phase 가 production_grade=true metrics 산출. 이는 fabrication 아니라 estimate label 분리 (Charter v1.4 §9). |
| "schedule_density 1.0 좋아 보이지만 risk's 208 active vs 60 burn-in 인데 변치 않음" | REBUTTAL | DCC inactive 60m 동안 weight_str1715=1.0 (S1-equivalent) — sleeve 의 default behavior 보존. 60m 강제 skip 시 schedule_density 가 208/267 = 0.78 < 0.95 violation. RF-O9 walk-forward 의무 + Charter §9 schedule density mandate 가 schedule 보존을 명시 (sig_dates 누락 시 forge run_all.R 가 fabrication 유도). |
| "Forward May 2026 cash 58% over-defensive — DCC params 최근 표본 overfit" | PARTIAL ACCEPT | RF-O-LAYER-A-FORWARD-EXTREME (HIGH) 사전 명시. 본 sizing_only round 는 risk_package vol_target_decision 인계. forge backtest 후 5월 realized vol post-hoc audit 의무. |

### 3.2 자율 분류 정책 (각 concern 도착 시)

- **ACCEPT (mandatory)**: Hard Constraint 위반 (max_names>20, max_w>0.20, Σw≠1), turnover>600%, RF-O9 single-snapshot 위반, infeasibility silent override. → 즉시 spec 수정.
- **PARTIAL**: 부분 인정 + downstream 보완 plan. 주로 추정 영역 (AX-001 v2 정량 평가).
- **REBUTTAL**: 학술 + L-code + 정량 data 3축 근거 필요. 위 표 6건 기준 마련.

### 3.3 자동 Q-Lead escalate trigger

- Hard Constraint 위반 발견 (max_names/max_w/Σw/turnover): 즉시 escalate
- HIGH severity ≥ 5
- AX axiom hard FAIL ≥ 3
- RF-O9 single-snapshot 발견 (현재: 267 monthly rows, RF-O9 PASS)

**현재 상태**: 위 trigger 0건.

---

## 4. Codex Round Decision (response 도착 후 채움)

**Status**: Codex critic round 1 dispatched, foreground/background timeout 가능성 인지.

### 4.1 Codex 도착 시 처리 protocol

1. `codex_critic_response_optimizer.json` parse → stance / critical_concerns / weakest_assumption.
2. 각 concern: ACCEPT / PARTIAL / REBUTTAL 분류 (Section 3.1 표 적용).
3. ACCEPT 시 → spec 수정 + round 2 draft.
4. PARTIAL 시 → optimization_package.json 에 보완 자료 + downstream obligation 명시.
5. REBUTTAL 시 → 학술 + L-code + 정량 data 3축 근거 본 note Section 4.2 기록.

### 4.2 Codex round timeout 시 waiver path (parent risk_package round 1 패턴)

**Pattern**: Risk_package round 1 codex timeout (15+ min) → round 2 자체검증 → `codex_critic_skip_waiver` 적용 (Q-Lead 권한, 도훈 명시 자율 진행).

**Optimizer round 1 도착 / 미도착 분기**:
- **도착**: stance 분석 + Section 4.1 protocol 적용.
- **미도착 (timeout)**: parent risk pattern 동등 적용 — 자체검증 + waiver 명시 ("optimizer round 1 codex timeout — 자율 검증으로 finalize, AX-008 forge + judge 2/3 PASS path 의존"). REJECT 본질이 sizing_only inheritance 한계에서 기인 (AX-007 single-sleeve mechanism limit) 인지 — sizing_only optimizer 영역에서 해소 불가.
- **REVISE/REJECT 도착**: 본 단계 design intent (max() rule, 3 variants, sleeve-level schema) 합리적 근거 보유 → REBUTTAL 우선 + critical Hard Constraint 위반 발견 시만 ACCEPT.

### 4.3 자기 합리화 자동 detect (Codex 응답 처리 시)

회피 표현 grep "미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적" 자기 적용. 검출 시 즉시 spec 재고.

---

## 5. PIT 자기 진단 요약

- **C1 (full-sample)**: PASS — pre-frozen DCC overlay (risk_package PIT-clean) + parent M4 overlay (production-validated) 합성. 본 optimizer 가 새로 추정 안 함.
- **C5 (overlay t-1)**: PASS — DCC 와 M4 overlay 둘 다 t-1 기준. max() 결합도 t 시점 deterministic.
- **C9 (DD/VT lag)**: PASS — 인계.

**핵심**: 본 optimizer 단계는 PIT-introduce 안 함 (no new estimation). Risk + Parent overlay paths 의 PIT 인계.

---

## 6. 후속 단계

- [ ] Codex response 도착 / timeout 분기 처리 → 본 note Section 4 채움
- [ ] sm_validated_advance("RISK_DONE" → "OPTIMIZER_DONE")
- [ ] record_package_lineage (input: risk_package + alpha_inherit_ref + request; output: optimization_package + weights canonical + 3 variants)
- [ ] optimization_package.json finalize (no `_draft` suffix)
- [ ] Forge agent handoff: weights.csv canonical + 3 variants + cash_definition_audit + lro_portfolio_mrc + (parent forge_package SHA reference)
- [ ] Telegram brief tg_agent_brief() v5 ENFORCE
