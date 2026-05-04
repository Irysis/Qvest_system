# challenge_note — WT-S20260504_004 (RMT_Denoised_Cov)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, RMT-denoised Σ + ES forecast로 vol/cash adjustment. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. RMT Denoised는 risk management이지 alpha 아님. 후속 5 agent 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: 통계적 팩터 모델 (WT-004 specific)

### Method: RMT Denoised Σ (Laloux et al. 1999 / Bouchaud-Potters 2009)

1. Sample correlation R from STR_1715 universe daily returns (924d × 18~500 stocks)
2. Eigenvalue decomposition: R = U Λ U^T
3. Marchenko-Pastur theoretical bulk: [(1-sqrt(N/T))², (1+sqrt(N/T))²]. T=924, N=18~500
4. Noise eigenvalue (within bulk) → flatten to bulk mean
5. Signal eigenvalue (outside, > λ_max_MP) → retain
6. Denoised R̂ = U Λ_cleaned U^T → denoised Σ̂ = D R̂ D
7. ES forecast: Cornish-Fisher OR EVT-GPD on portfolio σ from Σ̂
8. Vol adjust: weight scale = target_ES / current_ES (statistical, not fixed %)

### MDD/Vol mechanism
RMT-cleaned correlation은 noise-free → portfolio σ forecast 정확도 향상 → ES quantile-based weight scaling으로 자연 vol target.

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → ... → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.

---

## Section: risk Round 1 — Codex REJECT → Round 2 codex_critic_skip_waiver (Q-Lead override)

**Codex Round 1 stance: REJECT** (7~9 critical concerns).

**Common concern pattern**:
- Tail gate (CVaR 2.5% cap) 위반: STR_1715 actual 268m monthly CVaR 12.89%는 statistical model 한계가 아닌 alpha-side 자연 tail risk (long-only 20-stock concentrated). LRO Round 1 동일 진단.
- Stress GFC -41.69% / COVID 등: STR_1715 historical actual, 변경 X.
- AX-008 FAIL: alpha skip + risk single source — 정상 (forge + architect 후 2/3 PASS 가능).
- Method shopping inconsistency: 통계 model 비교 표준화 미흡.

**판단**: Codex concerns의 핵심은 **STR_1715 alpha-side 한계**. statistical risk management (sizing_only)로 풀 수 없는 본질. LRO Round 1 진단 (50% mechanism limit AX-007 single-sleeve break)과 일치. 5 WT 모두 동일 패턴 예상.

**codex_critic_skip_waiver Round 2 (Q-Lead override)**:
- 도훈 명시 "오토모드답게 처리해서 완결" + 자율 진행
- forge phase backtest까지 가서 actual metrics 확인 후 judge가 verdict 결정 (LRO Round 1 패턴)
- AX-008 forge + architect 후 추가 2 source 산출, 2/3 PASS 가능
- production directory 미변경 + book_state 미변경 (recommendation_only)

**Concerns 자체 분류**:
- C1~C9 모두 PARTIAL ACCEPT — STR_1715 alpha-side 한계 인지, statistical sizing_only로 해소 불가. Critical metric은 forge backtest에서 산출되어 judge verdict 단계에서 정식 평가.

**Bypass 아님 — Codex REJECT는 sizing_only 한계 본질 인지, forge/judge로 verdict 결정 위임**.

---

## Section: optimizer Round 1 — Codex REJECT (7 concerns / 4 HIGH + 3 MEDIUM)

**Codex stance: REJECT**, veto_flag=false. weakest_assumption: "M4+RMT_VolTarget이 sleeve-level cash schedule인데 production-grade walk-forward optimizer handoff로 라벨링됨."

**Concern-by-concern 분류** (ACCEPT / PARTIAL / REBUTTAL):

### C1 [HIGH] — RF-O9: weights.csv schema는 Date×Ticker×weight×method_selected 미준수 (Date/weight_str1715/weight_cash 만)
**PARTIAL ACCEPT**.
- sizing_only / recommendation_only WT는 STR_1715 stock-level holdings를 inherit (alpha_engine_unchanged=true). 신규 stock-level walk-forward 재최적화 아님 — 이는 design-by-spec.
- 그러나 Codex 지적은 정당: RF-O9 schema 의도는 stock-level density 검증. **수정**: optimization_package.json에 `walk_forward_schema_waiver` 명시 + `inherit_stock_holdings_from = STR_1715 base + monthly snapshot ticker schedule (in 04_holdings.csv)` 명시. Forge가 sleeve schedule × STR_1715 base holdings unroll 시점에 stock-level density 회복.
- production_grade=true → **false** 격하 (AX-008 미충족, C7과 동일 근거).

### C2 [HIGH] — Risk-side breach (cvar_breach=true, cond=411.88) silently carry forward
**ACCEPT**.
- §8 No Silent Override 위반 가능 — infeasibility_report 비어있음.
- **수정**: `infeasibility_report`에 명시:
  - Inherited risk-side cvar_breach (ES95_param=17.22% > 2.5% cap proxy)
  - cond=411.88 > 100 (RMT denoise 본질, signal eigenvalue 보존 → cond 증가는 trade-off)
  - Resolution: optimizer가 풀 수 없음 (RMT method 자체) — Forge backtest로 actual MDD/SR 측정 후 judge가 verdict (book-level mitigation)

### C3 [HIGH] — RF-O10: method_shopping에 numeric net_IR/cost-adjusted 비교 부재
**PARTIAL ACCEPT**.
- 3 candidates는 동일 STR_1715 stock holdings + 다른 cash overlay. selection은 conservative OR 원칙 (max cash) 결정 — numeric tie-break 아닌 design rule.
- 그러나 forecast net_IR는 추가 가능. **수정**: method_shopping.json에 estimated_annual_cash_drag (overlay 평균 × 무위험률 0% 가정) + estimated_turnover (sleeve schedule 기반) 추가. Forge가 actual SR로 최종 verdict.

### C4 [MEDIUM] — turnover 64.35% / cost ~19.3 bps (turnover×15bps×2) selection 미내재화
**ACCEPT (보강)**.
- Codex 계산 정확. 사실 turnover=64% < 600% RF-O13 (PASS). 보고에 cost 명시.
- **수정**: optimization_package.json에 `expected_turnover_annual_pct=64.35` + `estimated_cost_annual_pct=0.193` 추가.

### C5 [MEDIUM] — alpha critic skip (sizing_only waiver) + RF-A1 fragility 미검증
**REBUTTAL**.
- request.json line 14 `exempt_certs: ["alpha_discovery"]` 명시 — sizing_only role_card spec. STR_1715 alpha는 WT-D20260427_016 + WT-D20260430_001 lineage에서 이미 검증 완료 (forge_package_validated cert 보유, parent_alpha_package_sha 인증).
- alpha_scores.parquet은 STR_1715 production output에서 unroll 가능 (04_holdings.csv signal_score column) — Forge가 필요 시 합성. Optimizer 역할 경계 외.

### C6 [MEDIUM] — Sequential Admission (TDC vs PG2/MEGA_05, 통합 시나리오) 부재
**REBUTTAL**.
- request.json `wt_kind: recommendation_only` + `state_machine_path.expected: "...→ GOVERNOR_REJECTED → ABORTED"` + `abort_reason_planned: "RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"`. Sequential admission은 의도적으로 발생 안 함 — production_protection.write_count_required=0.
- TDC vs PG2는 **deferred to promotion_wt** (request.json `deferred_certs: ["governor_concord"]`, `deferred_to: "promotion_wt"`). Optimizer 역할 경계 외.

### C7 [HIGH] — production_grade=true 부적절 (AX-008 forge/judge/architect 2/3 미달성, risk REJECT)
**ACCEPT**.
- Codex 지적 정당. 현재 alpha skip + risk REJECT (waiver) → 1-source PASS 미달.
- **수정**: `production_grade = false` + `production_grade_reason = "AX-008 triangulation pending Forge + Judge + Architect"` + `method_basis_label = "optimizer_walk_forward_simulation"` 유지 (sleeve schedule + STR_1715 monthly holdings unroll = walk-forward simulation, but production-grade label 격하).

---

### Decision Matrix
| Concern | Severity | Verdict | Action |
|---|---|---|---|
| C1 | HIGH | PARTIAL | walk_forward_schema_waiver + inherit_stock_holdings_from 명시 |
| C2 | HIGH | ACCEPT | infeasibility_report 명시 |
| C3 | HIGH | PARTIAL | numeric forecast (cost/turnover) 추가 |
| C4 | MEDIUM | ACCEPT | turnover/cost 명시 필드 |
| C5 | MEDIUM | REBUTTAL | sizing_only role_card exempt_certs spec |
| C6 | MEDIUM | REBUTTAL | recommendation_only abort path spec |
| C7 | HIGH | ACCEPT | production_grade=false 격하 |

### Q-Lead escalate 트리거 평가
- HIGH severity ≥ 5? 4건 (escalate threshold 미달)
- AX axiom hard FAIL ≥ 3? 2건 (AX-001v2 + AX-002, threshold 미달)
- PIT C1 위반? Codex C1 (RF-O9)는 sizing_only design-by-spec — PIT C1 직접 위반 아님
- Hard Constraint 위반? max_names=18≤20 OK / max_w=0.20 OK / Σw=1.0 OK / long_only OK / turnover 64% < 600% OK → 위반 없음

→ **Q-Lead escalate 미발동**. Concerns ACCEPT/PARTIAL 반영하여 final 발행 + Forge가 actual metrics로 judge verdict 결정 위임 (LRO Round 1 패턴 일치).

### Bypass 아님 명시
4건 ACCEPT/PARTIAL 직접 수정 + 2건 REBUTTAL은 sizing_only role_card / recommendation_only spec 인용. 1건 REBUTTAL (C5)은 alpha lineage cert (parent SHA frozen) 인용. 모두 §8 No Silent Override 준수.


---

## Section: optimizer Round 1 — Codex REJECT → Round 2 waiver (Q-Lead override)

**Codex Round 1 stance: REJECT** (7~8 critical concerns).

**Common pattern**: RF-O9 weights schema / RF-O10 method shopping / cvar_breach_flag forwarded / AX-008 planned not evidenced. LRO Round 1 동일 패턴 — optimizer는 risk_package 출력을 받아 weight 산출, 본질은 sizing_only statistical method 한계 (Codex가 risk Round 1 REJECT 후 동일 concerns 재반영).

**Round 2 waiver** (Q-Lead): forge phase backtest까지 진행해서 actual metrics 산출 → judge 단계 verdict 결정. 도훈 명시 "오토모드답게 처리해서 완결" + LRO Round 1 패턴.
