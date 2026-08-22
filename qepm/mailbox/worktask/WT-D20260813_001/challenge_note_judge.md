# Self-Adversarial Challenge — Judge (WT-D20260813_001)

**작성**: judge (메인 세션 모델 자체 적대검증 — v8.2, 외부 Codex Round 대체). AX-008 3-source 중 1 (Judge는 adjudicator이나 finalize 직전 self-rationalization 방어는 본질 의무).
**대상**: `judge_package.json` (verdict = JUDGE_FAILED, Grade F).
**전제**: essence_score 권위 재실행 = Grade F / hard_fail TRUE (독립 재현). 모든 수치 forge-authoritative + essence 계약 재실행으로 대조 완료.

## 자기 비평 (devil's advocate) — ≥3건

### JC-1. [Grade F가 upstream NOT_SUPPORTED를 그대로 rubber-stamp한 것 아닌가 — 독립 검증 결여]
**분류: REBUTTAL (독립 재현 근거)**
- 우려: judge가 forge/alpha의 FAIL 라벨을 재계산 없이 승계하면 adjudicator 역할 실패.
- 통제 실측: essence_score.R을 forge bt_result.rds에 **직접 재실행** — Grade F, hard_fail TRUE, PORT_t 0.837·oos -0.855·calmar 0.212를 **contract가 독립 산출**(forge_package 서술과 별개 경로). 추가로 essence가 forge_package에 없던 **구조적 drawdown hard-fail**(55%+ episode 5, max underwater 39개월, catastrophic threshold 0.70)을 자체 검출 → 이는 승계가 아니라 독립 판정. bt_result metrics 24행 전수 확인(CAGR 0.142·Sharpe 0.578·Calmar 0.212·MDD 0.669, 198 monthly obs).

### JC-2. [F1 tail-hit t=+4.62가 강발화인데 F로 닫으면 기전 신호를 매장하는 것 아닌가 (AX-000 조기-한계 단정)]
**분류: PARTIAL (인정 + INV-7 정합 처리)**
- 인정: F1은 t=+4.62로 우연 수준을 크게 상회, 예측기가 상방 꼬리 종목을 실제로 식별한다는 실증이다. Grade F를 'target-form family 사망'으로 확대하면 AX-000 위반.
- 처리: judge_verdict를 **config-scoped negative**로 명시하고 screen_route를 dead가 아닌 `DISTRIBUTION_TARGET` 후속 소비 경로로 라우팅. next_probe ≥2 도출. F는 **자본 자격 판정**(HARD 3종)이지 방향 판결이 아님을 verdict_detail에 명기. INV-7 부활 조건 병기.

### JC-3. [net_IR essence값 0.234 vs optimizer 0.257 — Gate C net_IR leg를 통과로 볼 여지?]
**분류: REBUTTAL (Gate C는 AND, PORT_t leg가 지배)**
- Gate C = PORT_t ≥ 2.95 **AND** net_IR > 0.2(disc). net_IR은 essence 0.234·optimizer 0.257 둘 다 0.2 초과이나, PORT_t 0.837 << 2.95로 AND의 첫 leg가 FAIL → Gate C는 net_IR 값과 무관하게 FAIL. net_IR 통과를 근거로 부분 크레딧 부여 금지(measurement-graduation §3 HARD). 기록만 하고 판정 불변.

### JC-4. [no_signal_gate INDISTINGUISHABLE = judge가 재확인했는가, forge 라벨 승계인가]
**분류: PARTIAL (수치 대조 — 재실행은 forge 권한)**
- forge_package no_signal_gate_detail: diff_ann +0.073·diff_nw_t 0.972·control_port_t -0.859·strategy_port_t 0.838. control(시총상위 무신호)이 음(-)이고 strategy가 0.84로 둘 다 |t|<2 → 통계적으로 구별 불가가 수치 정합. judge는 이 계약 산출(forge-authoritative)을 재계산하지 않으나(no_signal_control.R은 forge 경유), diff의 부호·크기·상관 0.598이 INDISTINGUISHABLE 라벨과 내적 정합함을 확인. Gate C·D 판정의 보강 근거로만 소비(신호 기여 미증명 = Gate C의 alpha 실재성 결여와 동일 방향).

### JC-5. [essence hard_fail이 MDD 구조로 발화 — MDD 45% 단독 hard fail은 2026-06-13 폐지됐는데 부활시킨 것 아닌가]
**분류: REBUTTAL (구조적 drawdown 기준은 폐지 대상 아님)**
- measurement-graduation: "MDD 45% 단독 hard fail 폐지 → structural drawdown 기준(2026-06-13)". essence의 hard_fail은 MDD 45% **단독**이 아니라 catastrophic threshold 0.70 근접(66.9%) + 55%+ episode 5회 + max underwater 39개월의 **구조 프로파일** 발화 = 폐지된 단일-임계가 아니라 대체 기준 그 자체. 정합. 단 이 hard_fail이 없어도 PORT_t·oos·calmar 3종 전패로 Grade F 불변 — hard_fail은 판정을 바꾸지 않는 보강 축.

## 자기합리화 자동탐지 (의무)
회피표현(미미·관행적·보수적이면OK·대략·유사·거의) 스캔: verdict/근거에 사용 없음. PORT_t 0.837을 '거의 통과'로 완화하지 않고 FAIL 명시. F1 강발화를 'F 뒤집는 증거'로 과대해석하지 않고 config-scoped·소비마디 귀속. net_IR 0.234 통과를 부분크레딧으로 쓰지 않음.

## Q-Lead escalate trigger 점검
- HIGH severity concern ≥ 5? → No (PARTIAL 2·REBUTTAL 3, 실 위반 0)
- AX axiom hard FAIL ≥ 3? → No (Grade F는 정상 판정, axiom 위반 아님)
- PIT C1 hard violation 발견? → No (walk-forward sig_date < anchor 준수, ast_verify WARN_RESTATEMENT만·FAIL_LOOKAHEAD 없음)
- **escalate 불요.** verdict JUDGE_FAILED는 정상 게이트 결과이지 escalation 사유 아님.

## 결론 (Judge)
Grade F는 essence_score 계약 **독립 재실행**으로 확정(rubber-stamp 아님). graduation HARD 3종 전패(PORT_t 0.837·oos -0.855·calmar 0.212) + no_signal_gate INDISTINGUISHABLE + 구조적 drawdown hard-fail. 자본 자격 없음. 그러나 기전 축(F1 t+4.62·trim5 대조)은 지지 — 병목은 표적이 아니라 소비 마디(top-N EW 평균 흡수). config-scoped negative로 닫고 DISTRIBUTION_TARGET 라우팅 + next_probe 도출. target-form family 판결로 확대 금지(INV-7).
