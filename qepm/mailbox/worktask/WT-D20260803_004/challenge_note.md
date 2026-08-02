# Self-Adversarial Challenge — WT-D20260803_004 (FQ-121)

v8.2 규약 (Codex Critic Round 대체). finalize 직전 자가 적대검증. 작성: alpha-research agent, 2026-08-03.

## 대상 산출물

조합 자격 게이트 IS/OOS 분리 검증 — IS(2001-12~2014-02, 147m) 성분 게이트 `canonical PORT_t > 0` → OOS(2014-03~2026-06, 148m) 4-arm canonical 실측. 사전등록 `stage_artifacts/WT_D20260803_004/preregistration.json` (측정 전 고정, 단일 분할).

## Concern 1 — "OOS가 진짜 봉인이 아니다" (PIT/설계) → **ACCEPT (부분) — 사전 명시로 처리 완료**

WT-009/015/021에서 full-sample(295m) PORT_t가 이미 열람된 표본 위에 IS/OOS 경계를 놓았다. 따라서 본 라운드의 "OOS"는 미열람 데이터가 아니다.

- **처리**: 사전등록 `split.honesty_note`에 측정 전 명시 — 본 라운드가 제거하는 편향은 "성분 선별 절차의 IS-only 재현" 하나이며 그 이상을 주장하지 않는다. primary 판정(A1)은 열람 지식이 개입할 수 없는 **기계 절차**(IS 수치 → 문턱 0 → EW)라 arm 구성에 재량이 없다.
- **잔여 위험**: A2_POS2 arm은 full-sample 지식(WT-021 양-전이 2개)으로 정의된 arm — 그 OOS +0.44는 사후선별 잔영을 포함한다. **A2는 판정 근거에서 배제**(진단 전용), 판별 (a)(b)는 A1/A3/A4만 사용. 이미 그렇게 설계·보고됨.

## Concern 2 — "(b) INSUFFICIENT 물타기" (해석) → **ACCEPT — 결론 문구 강화**

paired t(A1−A4) = +0.69를 "조합이 열위는 아님"으로 보고하면 오독 유발 — 실제로는 A1(−0.03)과 A4(−0.39) **둘 다 OOS 알파가 0 근방**이라 비교 자체가 0 vs 0이다. 조합의 존재 이유는 "성립 실패"가 정직한 결론.

- **처리**: 최종 보고를 "**다팩터 조합 lane은 현 config(이 5팩터·cap-w·top-25)에서 재개 조건 미충족 — 닫힘(config-scoped)**"으로 명시. "판별 불가" 류 완곡 표현 배제.

## Concern 3 — "게이트 문턱(>0)이 너무 낮아서 실패한 것 아닌가" → **REBUTTAL (정량 3축 + 문헌 + L-code)**

"문턱을 t>1.0으로 올렸으면 Q01_EB(IS +1.76)가 걸러져 결과가 달랐을 것"이라는 반론 가능.

- **반박 근거 (정량 1)**: V01_SECREL은 IS t **+2.63으로 5팩터 중 최강**인데 OOS **−0.39로 음전**했다. 어떤 양수 문턱을 세워도 V01은 마지막까지 통과한다 — 문턱 상향은 이 실패 모드를 구조적으로 못 막는다.
- **(정량 2)**: 성분 5개 중 IS→OOS 부호 안정 2/5 (M01, D03). IS 12년(147m)의 t-stat 크기 순서(V01 2.63 > M01 2.32 > Q01 1.76 > V06 1.21)가 OOS 순서(M01 +0.71 > V06 −0.22 > V01 −0.39 > Q01 −1.41)와 **역상관에 가깝다** — 문턱은 순서를 바꾸지 못한다.
- **(정량 3)**: 사후 문턱 스캔은 sweep(사전등록 위반)이라 미실행 — 문턱 counterfactual 수치를 보고하지 않는 것 자체가 규율이다.
- **문헌**: Harvey-Liu-Zhu 2016 (in-sample t의 다중검정·감쇠 — 문턱 상향으로 해결 안 되는 비정상성), McLean-Pontiff 2016 (factor premium의 시간 감쇠).
- **L-code/사전지식**: post-2017 return-파생 팩터 cohort-wide 감쇠(측정-graduation §3 decay-pattern 라벨 근거), 16/16 admission FAIL posterior.

## Concern 4 — "placebo 음의 중심을 양성 증거로 재해석" → **PARTIAL — 진단 정보로 강등**

placebo(월내 순열 20 draw) 중심이 0이 아니라 **−1.69 (sd 0.55)**. "A1이 placebo 대비 +3σ"라는 해석은 사전등록 목적(0 근방 확인) 밖의 사후 재해석이다.

- **인정**: placebo 중심 이탈은 신호 문제가 아니라 **벤치-구성 아티팩트**(무작위 EW 25픽 vs cap-w KOSPI200 벤치, post-2014 mega-cap 구간)임이 자명 — dual-basis 진단(A1 EW-uni t +1.67 vs cap-w −0.03)과 정합.
- **처리**: "cap-w 벽이 OOS 판정을 지배한다"는 **진단**으로만 소비(v8.3 dual-basis mandate의 재분류 검토 라벨). A1을 placebo 대비 양성으로 **승격하지 않음** — cap-w HARD 판정 권위 불변.

## Concern 5 — "lag1 무붕괴 = PIT clean 증거" 오용 위험 → **ACCEPT — 검사력 라벨 부기**

lag1(A1_LAG +0.05 vs base −0.03) 무붕괴를 동월 누출 부재 증거로 쓰면 안 됨 — base 신호 자체가 0 근방이라 **붕괴할 것이 없어 검사력이 낮다**.

- **처리**: alpha_validation에 "lag1 시행·무붕괴·단 base≈0이라 검사력 낮음" 정직 라벨. PIT 방어의 실질은 패널 walk-forward 승계(WT-009 lag1 실증) + 위반 주입(누출 게이트가 +0.74 t 이득을 냄 = 분리가 실질 구속임을 실증) 쪽에 있다.

## 합리화 자기검증

금지 패턴("미미/관행적/실무적/보수적이면 OK/대부분 결과 동일") 사용 없음. 사후 문턱·분할 변경 없음(단일 분할 고정 준수). RE-VIEW 트리거 미발화.

## Escalation 판정

HIGH severity 0건 / AX axiom hard FAIL 0건 / PIT C1(lockbox·lookahead) 위반 0건 → Q-Lead 자동 escalate 조건 미충족.

## 종합

- ACCEPT 2 (C2, C5) / ACCEPT부분 1 (C1) / PARTIAL 1 (C4) / REBUTTAL 1 (C3)
- 판정 유지: (a) 미확립(t +1.26 < 2.0, 방향 양성) · (b) 성립 실패(t +0.69, 양 arm 모두 OOS 알파 0 근방) · **지배 발견 = 성분 자격(전이 부호)의 시계열 비정상성(부호 안정 2/5)** — 정적 IS 게이트로는 "조합은 전이-양성끼리만" 원칙을 기계화할 수 없음이 실측 확정.
