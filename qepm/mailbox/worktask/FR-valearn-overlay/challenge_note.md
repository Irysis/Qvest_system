# Challenge Note — FR valearn regime/bear overlay (dispatch-orchestrator)

Codex Critic Round per `.claude/rules/codex-round.md` (No Silent Override).
Codex stance = **APPROVE_CONDITIONAL**, `pit_leak_found=false`. 6 concerns (HIGH×2, MEDIUM×3, LOW×1).
각 concern → ACCEPT / PARTIAL / REBUTTAL + 실측 증거(`_diag_robust.R`, `_diag_placebo.R`, `_diag_dd_regime.R`).

## C1 [HIGH] e=0.0 선택이 OOS model selection 아닌가 (e가 IS에서 preselect 됐나)
**ACCEPT (보강).** 정당한 지적 — 원 스크립트는 *국면*(CAUTION)은 IS Sharpe로 골랐으나 *노출레벨* e와 "best_oos_variant" picker가 OOS_retention을 사용. → **IS-only 프로토콜로 재검(`_diag_robust.R` (1))**: CAUTION off의 IS Sharpe e0.0=1.093 > e0.5=1.006 → **IS가 e=0.0을 선택**(OOS 미열람). 그 e*=0.0을 forward 적용 시 OOS net_SR 0.590(baseline OOS 0.466), MDD 34.4%(45.6%). 즉 e=0.0은 OOS cherry-pick이 아니라 **IS-selectable**. 결론(LIMIT) 불변. → 최종 보고에 "e도 IS-선택" 명시.

## C2 [HIGH] "book-level exposure cannot rescue"가 partial benefit 저평가 → wording
**ACCEPT.** Codex 제안 수용 — 평결을 **`RETENTION_LIMIT + PARTIAL_RISK_RESCUE`**로 정정. overlay는 MDD 45.6%→34.4%(−11.2pp)·net_SR 0.713→0.881·Calmar 0.323→0.516·grade F→C로 **실질 drawdown/SR 개선**. 단 task mandate 판정기준(OOS_retention −0.517→0.5+)은 **미달(−0.372 음수 유지)** → "alpha-retention repair는 실패, risk(tail) repair는 부분 성공"으로 정밀화.

## C3 [MEDIUM] CAUTION persistence가 n=11(IS)/n=5(OOS) 통계적 취약 — 2020-03 운 아닌가
**PARTIAL→REBUTTAL(증거).** leave-one-crash-out(`_diag_robust.R` (2)): 2008·2020 위기 **둘 다 제외** 후에도 overlay net_SR 0.850 > baseline 0.810(MDD 동일 30.1%). → CAUTION 효과는 2-event 아티팩트 **아님**(비위기 구간서도 소폭 양수 지속). placebo(`_diag_placebo.R`): 5국면 중 CAUTION만 baseline OOS_retention 개선(−0.372 > 타 국면 전부 −0.69~−2.0), IS·OOS 둘 다 최악(IS Sharpe −0.969/OOS mean −3.8%) → 경제적 persistence(저품질 가치주 약세진입 추가하락). **그러나 핵심**: persistent해도 OOS_retention −0.372(음수). 취약성과 무관하게 retention 회복 실패는 robust.

## C4 [MEDIUM] RISK_ON throttle 미시험 (OOS 붕괴 지배국면)
**REBUTTAL(증거).** RISK_ON 디리스크는 **IS-위반 선택**(IS Sharpe 1.08로 양호 → IS-only 규칙이 절대 안 고름; 고르면 데이터마이닝). 진단 차원 시험(`_diag_robust.R` (3)): RISK_ON e0.5 → OOS_retention **−1.423(악화)**. RISK_ON이 OOS alpha 붕괴 국면이자 *동시에* 모듈 bulk carry 국면이라 노출 줄이면 carry까지 제거 → 회복 불가. 이것이 "지배국면 RISK_ON 횡단선택 실패는 exposure scaling으로 타이밍 불가"의 직접 실측. broad claim 약화 우려에 답: "어떤 *exposure-scaling* overlay도 RISK_ON 붕괴 못 살림" — 단 C6 untested design(피처 필터)은 별도 후속으로 인정.

## C5 [LOW] cash=0가 디리스크 변형에 불리
**REBUTTAL(보수적, against-overlay).** cash=0은 디리스크 구간 수익을 RF만큼 과소 → overlay benefit **과소평가**(편향이 overlay에 불리). OOS_retention은 active(vs BM)라 RF 가산해도 BM도 동일 가산 → 음수 불변. Codex도 "0.7로 못 옮긴다" 동의. 민감도 재실행은 결론 불변이라 후속 advisory.

## C6 [MEDIUM] LOCF roll=TRUE PIT leak 가능성 + untested design
**REBUTTAL(PIT) + ACCEPT(후속).** PIT: `RG[q,on=.(Date),roll=TRUE]`=LOCF(직전관측, forward-fill 아님) + `shift(1L)`(전월말→이번달) 이중 lag. crash월(2020-03) t-1 regime=CAUTION = classifier가 crash 사전경고 실패한 *정직한* PIT 결과(미래라벨 썼으면 CRISIS). Codex `pit_leak_found=false` 정합. **ACCEPT(후속)**: untested design(CAUTION 내 crash-entry 확인 필터 — index trend/realized vol/credit stress; RISK_ON quality throttle)은 LIMIT 최종확정 전 가치 有 → 후속 L-code 트리거로 기록(현 결론은 *exposure-scaling* overlay 한정 LIMIT).

## 자기합리화 grep (codex-round.md) — 통과
"미미/관행적/실무적/보수적이면OK/대부분동일" 미사용. 모든 REBUTTAL = 실측 3축(placebo/leave-crash-out/IS-only protocol) + 메커니즘.

## 최종 평결 (Codex 반영)
**RETENTION_LIMIT + PARTIAL_RISK_RESCUE** (구 OVERLAY_LIMIT 정정).
- alpha-retention: overlay가 valearn OOS_retention −0.517을 회복 못함(best IS-clean variant −0.372, 0.5 게이트 미달, SR2.5 미입증). 붕괴 원인=지배국면 RISK_ON 횡단선택 실패+earnings-rev decay, exposure-scaling으로 타이밍 불가.
- risk-repair: CAUTION off(e0.0, IS-선택)는 MDD −11.2pp·SR +0.17·F→C 실질 tail 개선(leave-crash-out robust).
- project-factor-rotation 갱신: "직교 부재로 overlay 무가치" → "직교 알파(valearn) 확보로도 overlay는 **tail(MDD)만 다듬고 alpha 부재 구간(RISK_ON OOS decay)은 못 살린다**. overlay≠OOS-retention 만능; 직교 슬리브 존재가 overlay OOS robust의 충분조건 아님."
