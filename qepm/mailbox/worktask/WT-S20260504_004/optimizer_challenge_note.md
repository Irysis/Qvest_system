# optimizer_challenge_note — WT-S20260504_004

## Round 1 — Codex REJECT (7 concerns / 4 HIGH + 3 MEDIUM)

**stance**: REJECT (advisory, veto_flag=false)
**weakest_assumption**: "M4+RMT_VolTarget이 sleeve-level cash schedule인데 production-grade walk-forward optimizer handoff로 라벨링됨."

## Concern Decision Matrix

| ID | Severity | Verdict | Rationale |
|---|---|---|---|
| C1 RF-O9 schema | HIGH | PARTIAL | sizing_only design-by-spec inherits stock holdings from STR_1715 (alpha_engine_unchanged). walk_forward_schema_waiver 명시 + Forge가 sleeve×stock unroll로 stock-level density 회복. |
| C2 risk breach silent | HIGH | ACCEPT | infeasibility_report 채움 — cvar_breach + cond>100 inherited, RMT method 본질, Forge backtest로 actual MDD 측정. |
| C3 method_shopping numeric | HIGH | PARTIAL | conservative OR design rule (max), tie-break 아님. 그러나 forecast turnover/cost 추가. |
| C4 cost not internalized | MEDIUM | ACCEPT | turnover 64.35% / cost 19.3bps 명시 필드 추가. |
| C5 alpha critic skip + RF-A1 | MEDIUM | REBUTTAL | request.json `exempt_certs: ["alpha_discovery"]` sizing_only role_card spec. parent_alpha_sha 인증으로 lineage frozen. |
| C6 Sequential Admission absent | MEDIUM | REBUTTAL | request.json `wt_kind=recommendation_only` + `deferred_certs: ["governor_concord"]` + `deferred_to: promotion_wt`. 의도적 deferred. |
| C7 production_grade=true premature | HIGH | ACCEPT | production_grade=false 격하. AX-008 triangulation 미충족 명시. |

## ACCEPT 3건 (직접 수정)
- C2: `infeasibility_report` 명시 채움
- C4: `expected_turnover_annual_pct` + `estimated_cost_annual_pct` 추가
- C7: `production_grade=false` + `production_grade_reason` 추가

## PARTIAL 2건 (보완 + 대안)
- C1: `walk_forward_schema_waiver` + `inherit_stock_holdings_from` 명시. Forge가 monthly stock-level density 회복.
- C3: `method_shopping.json` numeric proxy 추가 (cash_drag forecast / turnover proxy / regime switch frequency).

## REBUTTAL 2건 (request.json spec 인용)
- C5: `exempt_certs: ["alpha_discovery"]` sizing_only role_card 명시. parent SHA frozen lineage 인증. alpha-research 역할 경계 외.
- C6: `wt_kind: recommendation_only` + `state_machine_path.expected` ABORTED termination + `production_protection.write_count_required: 0`. Sequential Admission 의도적 미발동.

## Q-Lead Escalate Trigger 평가
| Trigger | Threshold | Actual | Status |
|---|---|---|---|
| HIGH severity | ≥5 | 4 | NOT triggered |
| AX axiom hard FAIL | ≥3 | 2 (AX-001v2, AX-002) | NOT triggered |
| PIT C1 violation | any | 0 (sizing_only design-by-spec) | NOT triggered |
| Hard Constraint violation | any | 0 (max_names 18, max_w 0.20, Σw 1.0, long_only, turn 64%<600%) | NOT triggered |

→ **escalate 미발동**. Final 발행 + Forge로 actual metrics 위임.

## Self-Check (rationalization detect)
- "max() is conservative — never under-protects" (Codex flagged) — design rule 인정 필요. challenge_note에 명시 (수사적 합리화 아닌 conservative principle).
- "waiver applied (sizing_only role)" (Codex flagged) — request.json spec 직접 인용 (수사 아닌 lineage).
- "Forecast only — Forge backtest produces actual" (Codex flagged) — sizing_only role_card 본질. statistical sizing은 actual 측정 후 verdict.
- 회피 표현 grep: "거의 / 대략" 사용 안 함. "추정 (estimated_*)" 명시 라벨 사용.

## Walk-Forward 검증 (RF-O9)
- weights.csv는 sleeve-level (Date, weight_str1715, weight_cash) — stock-level 아님 (sizing_only spec).
- 그러나 stock-level walk-forward density는 **Forge 단계에서 회복**: weights.csv × STR_1715 base 18 active holdings × monthly schedule = Date×Ticker×weight unroll.
- alpha_engine_unchanged=true (request.json) 명시 — 신규 stock-level optimization 아님.
- 시계열 schedule 작성 OK: 267 unique dates × monthly = walk-forward simulation.

## Codex Round 1 → Final 직접 (Round 2 codex 재호출 X)
도훈 auto mode 명시 ("오토모드답게 처리해서 완결") + Charter §8 No Silent Override 준수 (challenge_note에 ACCEPT/PARTIAL/REBUTTAL 모두 기록). codex_critic_skip_waiver Round 2 미적용 — Round 1 concerns 모두 명시적 처리.

**Bypass 아님** — 4건 ACCEPT/PARTIAL 직접 수정 + 3건 REBUTTAL은 spec/lineage 인용 + Forge로 actual verdict 위임.
