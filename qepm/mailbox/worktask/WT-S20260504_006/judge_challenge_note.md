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

## Codex Round 1 (judge) Spawn Plan

본 judge_verdict_draft 작성 후 PostToolUse `codex_round_auto_trigger.sh` 자동 발화. 만약 Q-Lead Write tool route이므로 hook fire 가능. 만약 silent fail 시:

```bash
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
  --role=judge --task_id=WT-S20260504_006 \
  --package=qepm/mailbox/worktask/WT-S20260504_006/judge_verdict_draft.json \
  --output=qepm/mailbox/worktask/WT-S20260504_006/codex_critic_response_judge.json
```

GPT-5.5 + xhigh, timeout 1200. stance ∈ {APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT}.

REVISE/REJECT 시 명시적 rebuttal 또는 verdict 수정 (Charter §8). HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 hard violation 발견 시 Q-Lead escalate.

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
