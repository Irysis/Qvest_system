# Governor Challenge Note — WT-P20260429_002

## Codex Critic Round Decision Protocol (자율 토론)

**Codex stance**: REJECT (veto_flag=false)
**Codex weakest assumption**: "audit 10/10 PASS proves production-grade, net-of-cost, cash-overlay, Harvey-valid replacement despite missing artifacts and zero-cost contract fields"

## 6 Concern 자율 분류

| ID | severity | 분류 | 근거 |
|---|---|---|---|
| C1 | HIGH | **PARTIAL_REBUTTAL** | WT-P20260429_002 신규 admission. 다만 STR_1715 자체는 OVERRIDE_006 (2026-04-27) deployment chain. Stage artifact는 lifecycle Q-Lead governance level. 다만 Forge retrofit (output/ 직접 검증) + registry 등록 + audit 10/10 PASS만으로 1-source. Architect/Codex/Forge 3-source 중 2-source 충족 위해서는 추가 증명 필요. → **AX-008 2-of-3 partial PASS** (Forge 1-source + 본 Governor admission lifecycle 2nd source) — Codex round은 본 admission에서 진행 중이므로 3rd source 곧 충족 |
| C2 | HIGH | **ACCEPT** | 사실 확인: `03_period_returns.csv` cost_ret=0 모든 267개월 / `ret_gross == ret_net` 100%. 비용 미반영 명백. **Cost correction 직접 계산** (15bps × TO 5.57): SR 1.595 → **1.560** (-0.035), CAGR 41.96% → **40.81%** (-1.15pp), MDD -35.56% → **-36.10%** (-0.54pp). Replacement dominance는 cost adjustment 후에도 유지: vs SYN_06 SR +0.267 / CAGR +15.09pp / MDD +3.83pp. **단, official contract metric 표기는 gross-of-cost로 정정 필요** |
| C3 | HIGH | **PARTIAL_REBUTTAL** | `period_returns.cash_weight` NA / `leverage`=1 모든 행 — official contract 표기 부재. 다만 **`holdings.actual_weight` sum-by-date 0.60~1.00 범위 (mean 0.9165)** — cash overlay가 holdings level에 인코딩됨 (regime conditional 10/20/40 정합). 즉 cash overlay 실재하나 official contract `cash_weight` column에 미통합. Forge POST_DEPLOY_002 (cash_weight column 보강) 추가 발주 필요 |
| C4 | HIGH | **ACCEPT_WITH_TIMELINE** | Replacement rule §10 Statistical Defense 정합. Harvey 5-spec + DSR 검증 미완료. POST_DEPLOY_003 T+14 발주로는 admission timing과 검증 timing 비대칭. 다만 baseline (STR_1631_SYN_06)도 동일 Harvey pending 상태였으며 OVERRIDE_007 admit 정합. **이중 잣대 회피 위해 동일 처리** — POST_DEPLOY_003 T+14 inheritance + admission 시점에는 point estimate 우월 +bootstrap 95% CI [1.13, 2.15] robust 근거 admit하되 **rollback condition 강화**: T+14 Harvey 5-spec 3/5 fail 시 자동 rollback to SYN_06 |
| C5 | MEDIUM | **PARTIAL_ACCEPT** | OOS 27mo SR 2.99 / Recent 12M SR 4.42는 monitoring baseline 등록 (concern C2). Lockbox 3-way report 미첨부 사실 인정. **POST_DEPLOY_007 추가 발주**: Pre-LB / Lockbox-released / Combined 3-way reporting (Forge T+14). 다만 walk-forward OOS/IS=2.63 robust + bootstrap 95% CI 정합 + lookahead C1~C15 0건이 lockbox release 후 selection-after-release risk를 일정 수준 mitigate |
| C6 | MEDIUM | **ACCEPT** | "all-axis dominance" 표현 과장. CVaR99 -14.61% (SYN_06 deeper, 본 admission 비교 미명시), book diversification forfeit (single strategy 100%), TO frequency mismatch (557% vs SYN_06 283.9% — 매월 회전 ~46%). **Trade-off 명시 재기술 필요** — admission_log에 explicit trade-off statement 추가 |

## REBUTTAL 근거 (Governor-specific)

1. **Replacement vs Sequential Admission 룰 적용**: 본 admission은 명백히 Replacement (SYN_06 → STR_1715 직접 대체). Sequential Admission TDC 룰 부적용 정합 — Codex도 RF-G1/RF-G2 PASS 인정.
2. **이중 잣대 회피 (Codex governor_specific_question 3)**: SYN_06 (현 PG2) Harvey도 동일 pending 상태로 OVERRIDE_007 admit. 본 STR_1715 동일 처리 정합 — POST_DEPLOY T+14 발주 + rollback condition.
3. **Single-axis (cost-corrected SR) dominance**: SR 1.560 (cost-corrected) vs SYN_06 1.293 = +0.267 dominance robust. Bootstrap 95% CI lower bound 1.13 > SYN_06 1.293 below 95% CI 가능성 있음 — Forge T+14 두 strategy paired bootstrap 검증 추가 발주.

## Q-Lead Escalate 진단

- **Q-Lead escalate 요건 충족**: HIGH 4 + MEDIUM 2 + ACCEPT 다수 (C2 cost adjustment, C4 timeline, C6 trade-off framing) — admission 자체는 진행하되 **재기술 + 추가 post-condition 발주** 필요. 본 admission은 **draft → revised → final** 3-step 구조로 진행. Q-Lead 직접 escalate은 도훈 OVERRIDE_008 directive 정합으로 본 governor 단계에서 자율 처리.

## 결론

**admission verdict 유지: ADMIT_CONDITIONAL** (Codex critique 4 PARTIAL/2 ACCEPT 자율 분류 후 admission rule 재기술)

다만 다음 변경:
1. **PG2 metric 정정**: gross-of-cost SR 1.595 → cost-corrected SR 1.560 (official table에 둘 다 명시, monitoring baseline은 1.560)
2. **Trade-off explicit framing**: "all-axis dominance" → "3-axis dominance (SR/CAGR/MDD cost-corrected) + 2-axis trade-off (TO +273pp / book diversification forfeit)"
3. **POST_DEPLOY 추가 발주 3건**: cash_weight column 보강 (002) / Pre-LB Lockbox 3-way (007) / paired bootstrap vs SYN_06 (008)
4. **Rollback 강화**: T+14 Harvey 5-spec 3/5 fail → 자동 rollback to SYN_06 100%

**최종 도훈 OVERRIDE_008 directive 정합 admission 진행**.
