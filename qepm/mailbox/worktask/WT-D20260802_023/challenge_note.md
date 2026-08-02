# Self-Adversarial Challenge Note — WT-D20260802_023 (v8.2)

작성: alpha-research agent, finalize 직전. Charter §8 No Silent Override.
대상: alpha_package.json (CTR_MAG_12M_MCAP 섭동 q05 확정 라운드, FQ-125)

## Concern 1 — "같은 패널 재사용인데 '신규 사전등록'이 무슨 의미인가" (자기 비평 최강수)

**제기**: WT-018에서 이미 관측한 셀(A_size, t 1.97)을 primary로 "사전등록"하는 것은 형식이다. 데이터를 본 뒤의 사전등록은 사후 선택(sweep)의 세탁 아닌가. 섭동 q05는 24개월 표본추출 불확실성을 전혀 다루지 못한다 — 같은 24개월 안에서 멤버십/스코어 jitter 강건성만 잰다.

**분류: ACCEPT (프레임 인정 — spec은 이미 방어 반영)**
- 인정: 본 라운드의 어떤 결과도 독립 표본 확인이 아니다. preregistration.json `provenance_honesty`에 측정 전 명문화했고, challenge_flags[0] SAME_PANEL_REUSE로 패키지에 승계했다.
- 이 라운드가 확립한 것의 정확한 경계: "관측된 t 1.97이 WT-013형 문턱-근방 단일 draw 아티팩트가 **아니다**" (전 120 draws 양수, min +1.365). 그 이상도 이하도 아님.
- sweep 재분류 방어: primary 승격 자체를 argmax로 하지 않았다 — WT-018이 승격을 거부(옳음)했고, 본 라운드는 승격을 **별도 사전등록 + 별도 판정 기준(q05)**으로 정식화했다. n_trials=1, 섭동 파라미터 측정 전 고정, 보조 지표로 primary 변경 없음.

## Concern 2 — "섭동 분포가 좁아서(sd 0.130) q05>0이 쉬운 시험이었다"

**제기**: WT-013의 sd 0.378은 top-25 포트 paired t(멤버십 의존 이산 통계)였다. IC는 77종 단면 순위 상관이라 구조적으로 섭동에 둔감 — q05>0 기준이 사실상 통과 예정이었던 것 아닌가.

**분류: PARTIAL (구조 차이 인정 + 보완 병기)**
- 인정: 검정 대상 통계의 섭동 민감도가 다르다. draw sd 0.130 실측이 그 증거이며 challenge_flags[1]에 명기.
- 반론 근거(정량 3축): ① 그래도 시험의 목적(문턱-근방 단일 draw 여부)에는 적합 — WT-013 사례처럼 draw 간 부호/문턱이 넘나들었다면 min이 0 근방으로 내려왔을 것인데 min +1.365로 전 draw가 양수 ② mean_ic q05 +0.0708로 크기도 보존 ③ 무섭동 t_NW 1.70과 q05 1.44의 간격이 좁아(0.26) 분포가 원점에서 멀리 떠 있음.
- 보완: 지불 권고문에 "q05>0은 부호 강건성이지 t>2.5 부활 조건의 동등 대체 아님"을 명시. 최종 지불 결정은 도훈.

## Concern 3 — "후반 12개월 약화(+0.122 → +0.040)는 decay 지문"

**제기**: 신호가 후반부에 1/3로 줄었다. 이대로면 전구간 크롤을 지불해도 최근 구간에서 죽은 신호일 수 있다.

**분류: PARTIAL (방향 인정 + 판별 불가 정직 보고)**
- 인정: 약화 방향은 실재하고 숨기지 않는다 (alpha_package regime_scope와 challenge_flags[2]에 승계).
- 반론 근거: ① 후반 12개월 = 2025H2~2026H1 초대형주 반도체 랠리 + 2026-07 폭락월 — 시스템 실측(reference-kr-2025-megacap-semi-regime)상 중형주 단면 신호 전반이 눌린 국면과 겹침 ② n=12씩이라 decay vs 국면의 통계 판별 자체가 불가 ③ 후반에도 부호는 양수(+0.040) 유지.
- 처리: 기각 조건을 사전 명시 — 전구간(259개월)에서 t_NW < 1이면 pilot 창 국면 아티팩트로 재분류. 이것이 전구간 크롤이 필요한 또 하나의 이유(판별 표본 확보).

## Concern 4 — "lag1 보존(t 1.94)은 PIT 무결의 증거가 아니라 검정력 부재"

**제기**: 12M 누적 신호는 월간 자기상관이 극도로 높아 lag1을 걸어도 신호가 거의 같다 — lag1 스트레스가 동월 누출을 못 잡는 구조다.

**분류: ACCEPT (진단 한계 명시 — 방어선은 다른 계층)**
- 인정: 이 신호 구조에서 lag1은 검정력이 낮다. self_pit_check note에 명문화했다.
- 실제 방어선: 빌더-계층의 구조적 컷오프(신호월 M 값 = rcept_dt ≤ M 말일 공시만) + 위반 주입 검사기 9/9 재실행(정정 혼입·미래 누출·parse실패 유입·중복 주입 전부 차단 발화 실증) + 정정 A/B(size 셀 paired t -0.83, 정정 반영판이 오히려 열세 = 누출 이득 부재).

## Concern 5 — "Ret_1m sanity 격리 66행 — grid 자체가 오염 vintage"

**제기**: canonical_screen_bt가 물리불가 월수익 66행을 격리하며 rawdata_sanitize 방화벽 미적용 vintage를 의심했다. 격리행이 신호-보유 종목에 몰려 있으면 IC가 편향된다.

**분류: PARTIAL (위생 결함 인정 — 판정 영향은 통제됨)**
- 인정: grid 재빌드 시 sanitize 적용 vintage를 쓰는 것이 옳다. challenge_flags[4] + next_probe에 등재.
- 판정 영향 통제 근거: ① WT-018과 정확 동일 grid·동일 sanity 필터(IC와 canonical 양쪽 [-1,5] 격리)로 라운드 간 일관 — parity 소수점 6자리 재현이 그 실증 ② 격리는 IC 계산 전 적용되므로 물리불가 수익이 판정에 유입되지 않음.

## 합리화 자기검증
answer-principles 회피표현 조항의 금지 목록(자기합리화 상투구 5종)을 대조 점검 — 본 노트와 alpha_package 서술에 해당 표현 사용 없음. 모든 한계는 명시 라벨(SAME_PANEL_REUSE 등 challenge_flags 5건)로 기록.

## Escalation 판정
HIGH severity 0건 / AX axiom hard FAIL 0건 / PIT C1(lockbox·lookahead) 위반 0건 → Q-Lead escalate 불요.

## AX-008 Triangulation
본 노트 = Self-Adversarial source (1/3). Forge·Architect 소스는 본 라운드 범위 밖(IC 확정까지 — graduation 주장 없음).
