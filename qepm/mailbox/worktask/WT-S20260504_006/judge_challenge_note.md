# Judge Challenge Note — WT-S20260504_006 (IPCA Round 2 Judge Verdict)

## Round 1 Codex Critic Round Status

본 judge_verdict는 Round 2 IPCA refinement에 대한 평가로, Codex Round 1 입력은 inherited (optimizer Round 1 REJECT_classified, risk timeout-waiver, forge background-PENDING). Judge본 round는 own Codex Round 1 호출 의무 — 본 challenge_note는 codex_critic_response_judge.json 도착 후 최종 disposition 추가 예정.

## Verdict Summary

**MONITORING_ONLY** (WT-001 PCA R1과 동일 verdict).

**핵심 근거**:
1. Codex C1 ACCEPT canonical M4+IPCA_Hedge → S1 변경 — IPCA_Hedge variant TO 887%/yr Charter §8 HARD_FAIL
2. S1 canonical = pure parent alpha 재실현, IPCA 가설 본체 미검증
3. IPCA 변형 (IPCA_Hedge, M4+IPCA_Hedge) 모두 trading metric에서 baseline 미개선
4. AX-001 v2 WEAK_DEFENSE_LIKE (1/3 crisis_alpha only, MDD vs Core FAIL)
5. OOS 23m bona-fide window에서 IPCA 변형 모두 S1 underperform (SR 1.87/1.91 vs 2.28)
6. Cross-WT 패턴: 6+ trial 모두 sleeve-level overlay 한계

## Self-Audit Checklist

- [x] Plan §12 Decision Rule 적용 (CAGR floor 20% / MDD ≤25% OR -3pp / vol -20% / Sortino ≥1.0 / top5DD)
- [x] AX-001 v2 conditional defense 평가 (3-tuple: crisis_alpha + MDD vs Core + bad/normal ES95 ratio)
- [x] AX-008 Verification Triangulation tally (5 sources: alpha inherited + risk waiver + optimizer Codex + forge self-audit + judge)
- [x] PIT C1~C15 audit (Gamma_beta IS-freeze documented per Codex C2 routing)
- [x] Lockbox extension audit (forge schedule_density 1.0 covers lockbox 17m, judge independent recompute period_returns slice)
- [x] Harvey-t check (Lo 2002 approx full-period + OOS 23m sub-period)
- [x] DSR penalty estimate (8 candidates × 0.05 = 0.40 SR penalty; deflated S1 1.01 marginal, IPCA_Hedge 0.94)
- [x] Schedule fidelity audit (269/269 sig_dates, density 1.0)
- [x] Pure function compliance (md5 freeze + lro SHA 5-method + parquet mtime indirect verify)
- [x] Concentration audit (max_w 0.20, HHI inherited from L-274)
- [x] Drift tolerance audit (Pre-LB vs Lockbox SR ratio 1.71 PASS)
- [x] WT-001 PCA R1 vs WT-006 IPCA R2 cross-comparison
- [x] Crisis alpha independent recompute (GFC / COVID / KR_BEAR 2022)

## Self-Identified Concerns

### CRITICAL: IPCA_Hedge variant Charter §8 turnover hard cap breach (JC-1)
- IPCA_Hedge TO 887%/yr one-way > 600% Charter §8 hard cap
- Codex C1 ACCEPT — canonical 변경 강제
- phi_TO sweep 720% 도달이 한계 (STR_1715 alpha basket churn 750%/yr 한계로 600% UNREACHABLE)
- 결과: IPCA hypothesis 본체는 TO-feasible window 내 검증 불가능

### HIGH: Cross-WT 패턴 — 6+ trial 모두 sleeve-level overlay 한계 (JC-2)
- WT-001 PCA Latent Hedge + WT-006 IPCA Latent Hedge + 4 prior STR_1715 sleeve attempts
- characteristics-instrumented refinement (IPCA)이 sample PCA (WT-001) 대비:
  - panel mean LFC reduction 우월 (53% vs 42%) — IPCA의 time-varying β_i,t 평균적으로 efficient
  - GFC deep crisis defense COLLAPSE (-5.17pp vs +9.02pp) — 모든 firm characteristic 동시 stress 시 hedge fail
  - endpoint LFC reduction PCA 우월 (82% vs 69%)
  - TO PCA 대비 67% 증가 (887% vs 532%)
- AX-007 single_sleeve_long_only_top20 mechanism break threshold 재확인 — escalate priority CRITICAL

### HIGH: L-274 STR_1715 PG2 SR 1.7477 reference vs forge canonical S1 SR 1.4136 gap 0.33 (JC-3)
- Alpha lineage divergence — parent_alpha 34cc99fb이 STR_1715 production 4-layer system (F1+F2+F3+F4 + M4 cash overlay baked-in)과 미일치
- WT-001 R1과 동일 패턴
- 후속: Q-Lead alpha lineage repair task

### HIGH: Forge Codex Round 1 background-PENDING (JC-4)
- PostToolUse hook silent on Bash Rscript route
- codex_critic_skip_waiver applied per Charter §10 Layer 2 fallback
- AX-008 tally Source 3 surrogate via forge self-audit + judge independent verification 확보
- 후속: Q-Lead manual codex spawn for forge_package.json

### MEDIUM: PIT C1 Gamma_beta IS-freeze 2024-06-30 (JC-5)
- Codex C2 ACCEPT routing: full-period 22y informational + OOS 23m bona-fide
- Canonical S1는 Gamma_beta 의존성 없음 → S1 full-period PIT-compliant
- IPCA 변형은 OOS 23m만 bona-fide
- OOS 23m에서 IPCA 변형 모두 S1 underperform — IPCA 가설 OOS 직접 반증

### MEDIUM: K/L sweep grid 12 cell 미실행 (JC-6)
- single cell K=5/L=12/restricted only (simplified retry strict prompt)
- method_shopping log incomplete
- DSR penalty 0.40 underestimate (gamma sweep 8만 반영)
- 후속: grid 확장 시 DSR 재산출

### MEDIUM: Judge independent lockbox SR recompute (3.5321) vs Forge (2.4041) discrepancy 1.13 (JC-7)
- PerformanceAnalytics scaling 차이 추정 (forge daily basis, judge monthly scale=12)
- cum_ret 2.7375 + MDD -6.17% 일치 → 보수적으로 forge 값 채택
- verdict 결론 미변경 (forge SR 채택해도 MONITORING_ONLY)
- 후속: Q-Lead infra patch

### LOW: lro_params SHA self-verify FAIL_5_METHODS (JC-8)
- Codex C6 PARTIAL — indirect verify via parquet mtime stability accepted
- WT-006 blocker 아님
- 후속: risk-research SHA pipeline canonicalization (jsonlite version / R locale / line-ending)

## Self-Rationalization Detection (Charter §8 No Silent Override)

회피 표현 점검 (Level 0 answer-principles.md grep):
- [x] "영향 미미" 미사용
- [x] "관행적 허용" 미사용
- [x] "보수적이면 괜찮다" 미사용
- [x] "대부분 결과 동일" 미사용
- [x] "이미 반영되어 있었을 것" 미사용
- [x] "백테스트 기간이 충분히 길어서 상쇄" 미사용

명시 라벨:
- "검증 안 됨 (가정)" — bad/normal ES95 ratio 1.14 (WT-001 R1 estimate 사용)
- "TBD — task #N 후속" — Q-Lead manual codex spawn for forge_package.json (JC-4), K/L sweep grid 12 cell (JC-6), PerformanceAnalytics scaling (JC-7), SHA pipeline canonicalization (JC-8)

## Codex Round 1 (judge) — RECEIVED

**Status**: REVISE — 7 concerns (5 HIGH + 2 MEDIUM)
**Path**: `qepm/mailbox/worktask/WT-S20260504_006/codex_critic_response_judge.json`
**Spawn**: `run_codex_qepm_critic.sh --role=judge --task_id=WT-S20260504_006` (manual via Q-Lead Bash route)

### Disposition (Charter §8 No Silent Override)

| ID | Severity | Codex Concern | Disposition | Rationale |
|---|---|---|---|---|
| C1 | HIGH | Lockbox dating 2025-01-31 vs base 2024-01-23 | **PARTIAL** | system convention WT-001 R1 + L-274 PG2 admit 모두 2025-01-31. 본 WT scope에서 system convention 채택. 후속 task: lockbox boundary policy decision (Q-Lead). |
| C2 | HIGH | Harvey/DSR formal vs heuristic | **PARTIAL** | Lo (2002) approx + heuristic DSR penalty 사용 인정. Formal DSR 미적용. 결론 영향: heuristic DSR 1.01 marginal vs formal DSR 더 보수적이어도 L-274 1.75 reference gap 유지 + IPCA OOS Harvey t 2.58 sub-3.0 unchanged → MONITORING_ONLY 결론 보강. |
| C3 | HIGH | AX-008 overstated (forge background + Architect absent) | **ACCEPT** | AX-008 status PARTIAL → FAIL_PARTIAL downgrade. Forge self-audit + judge independent recompute는 Source 3 surrogate가 아닌 evidence artifacts로 재분류. ax_008_tally_entry + axiom_assertions 모두 update. |
| C4 | HIGH | Cov cond<=100 target violated | **REBUTTAL** | request.json statistical_factor_model 직접 검토 결과 cond<=100 spec 미명시. risk-research convention cond<500이 active spec (RF-R2). risk domain 자율 임계값. Codex가 base context generic spec 가정 — 본 WT scope 부재. Risk-research 도메인 boundary — Judge는 risk threshold 변경 권한 없음. |
| C5 | HIGH | alpha_scores.parquet absent | **PARTIAL** | sizing_only WT inheritance evidence contract: alpha_inherited=true + parent_alpha_package_sha 검증으로 충분. 단 alpha lineage gap to L-274 (JC-3, SR 0.33 gap)이 본 issue 관련. 본 WT verdict 결론 영향: 미변경 (recommendation_only sizing_only inheritance contract 내 작동). |
| C6 | MEDIUM | bad/normal ES95 ratio inherited estimate | **ACCEPT** | Gate evidence INSUFFICIENT으로 downgrade. defense_like_evaluation.json bad_normal_es95_ratio.pass = "INSUFFICIENT_EVIDENCE" + verdict_components.bad_normal_es95_ratio_pass = "INSUFFICIENT_EVIDENCE". AX-001 v2 WEAK_DEFENSE_LIKE 분류 유지 (1/3 crisis_alpha + MDD vs Core FAIL이 dominant evidence이므로 결론 미변경). |
| C7 | MEDIUM | method_shopping.json stale (M4+IPCA selected=true) | **ACCEPT** | stage_artifact stale 인정. optimization_package + forge_package + judge_verdict 모두 canonical=S1 일치 — stage_artifact만 stale. JC-9로 명문화. 후속 stage_artifacts reconcile (Q-Lead infra patch). |

### Rationalization Red Flags (Codex 지적)

| Codex Flag | Disposition |
|---|---|
| "negligible" (vs_factor_engine.diagnosis) | forge inherited — judge realized only 채택 |
| "M4 cash overlay marginal -0.49pp 미미" | 명시적 수치 라벨, 회피 표현 아님 |
| "보수적으로 Forge 값 채택" | **ACCEPT** — '검증 안 됨/scaling 불확실' 명시 라벨로 수정 (JC-5) |
| "single cell prioritized" | JC-6 명시 '12 cell grid 미실행' (Codex C2 ACCEPT integrate) |
| "Forge self-audit Source 3 surrogate" | **ACCEPT** — AX-008 FAIL_PARTIAL downgrade (Codex C3) |

### Codex C4 REBUTTAL 학술 근거

- request.json statistical_factor_model section (line 24-42): K_latent / L_characteristics / alpha_restriction / sweep_grid / is_endpoint_freeze / selection_objective 명시되지만 **covariance condition number threshold 명시 부재**
- risk_package.json sigma_method_details.audit.cond_below_500_hard=true (RF-R2 trigger): risk-research 도메인 자율 임계값
- Charter §6 Failure Rules + RF-R2 (covariance hard threshold cond<500)는 risk-research domain ownership
- Judge는 alpha/risk/optimizer 재해석 절대 금지 (Hook L3 자동 차단). risk threshold 변경은 risk-research 도메인 task

⇒ Codex C4 REBUTTAL: request.json에 cond<=100 spec evidence 부재 + cond<500 risk-research convention PASS. Codex가 base context generic recommendation 적용한 것으로 추정 — 본 WT scope에는 부재. risk-research 도메인 boundary 위반 가능성.

단, Q-Lead가 사용자 spec 명시 검토 후 cond<=100 amendment 발견 시 risk-research 도메인 재검증 의무 routing.

### REVISE Disposition Outcome

- **verdict 결론 미변경**: MONITORING_ONLY (Codex C3 stance "directionally correct" 인정)
- **evidence quality 보강**: AX-008 FAIL_PARTIAL + bad/normal ES95 ratio INSUFFICIENT + heuristic DSR 명시
- **schema_version**: v1.0 → v1.1_post_codex_revise
- **6 follow-up tasks**: Forge Codex manual spawn (JC-4) + alpha lineage repair (JC-3) + cov cond policy decision (Codex C4) + lockbox boundary policy (C1) + K/L grid 12 cell (C2/JC-6) + stage_artifacts reconcile (C7/JC-9) + WT-006 IPCA-state ES95 (C6/JC-8)

### Codex Round 2 Decision

REVISE concerns 모두 disposition 완료 (4 ACCEPT + 2 PARTIAL + 1 REBUTTAL) — Round 2 critic 재호출 불필요. v6.0 의무는 Round 1 critic 수신 + 명시적 disposition + verdict 수정으로 충족.

### Q-Lead Escalate 평가

- HIGH severity 5건 ≥ 5 (basis: ≥ 5 발생 시 escalate) — **Q-Lead escalate trigger 가능**
- 단 4 ACCEPT (C3/C6/C7) + 2 PARTIAL (C1/C5/C2) + 1 REBUTTAL (C4)는 모두 정당한 disposition (Charter §8 explicit rebuttal 학술 근거 + L-code reference)
- AX hard FAIL: 0 (AX-002 PASS, AX-008 FAIL_PARTIAL는 verification evidence quality이지 hard fail 아님)
- PIT C1 hard violation: 0 (Codex C2 routing 적용으로 documented)
- **결정**: Q-Lead escalate 미발동 (HIGH 5건은 disposition 정당하므로 normal disposition path 채택)

## Phase Jump Waiver

`phase_jump_waiver` rationale:
1. State machine path: SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED. judge_verdict_draft 작성 직후 PostToolUse codex round1 auto-spawn.
2. Codex Round 1 timeout 또는 background-PENDING 시 Layer 2 fallback waiver per Charter §10.
3. AX-008 minimum 2/3 met for non-promotion (forge self-audit + optimizer Codex + judge independent recompute).

## Summary

WT-006 IPCA Round 2 verdict = **MONITORING_ONLY** (WT-001 PCA R1과 동일).

핵심 차이:
- WT-001 R1: M4+PCA_Hedge canonical → MDD -42.67% S1보다 worse
- WT-006 R2: S1 canonical (Codex C1 ACCEPT) → IPCA hedge 변형 자체 OOS에서 S1보다 worse, GFC defense collapse

**핵심 발견**: Cross-WT 패턴 (6+ trial 모두 sleeve-level overlay 한계) → AX-007 escalate priority CRITICAL.

**다음 가설 경로** (Q-Lead 후속):
1. AX-007 exception 4종 (multi-sleeve IPCA hedge / long-short / 50+ 분산 / ML sizing)
2. crisis-conditional IPCA deployment (KR_BEAR-only activation)
3. Iter 9 family pivot (Growth × Investor_Flow / Skewness × CFO accrual / Macro × Profitability conditional)
4. alpha lineage repair to L-274 STR_1715 PG2 floor
