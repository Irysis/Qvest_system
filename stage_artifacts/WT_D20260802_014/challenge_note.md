# challenge_note.md — WT-D20260802_014 Self-Adversarial Challenge (v8.2)

finalize 직전 자체 적대검증. 대상 = MAX5_63 상위 10% 제외-필터 소비면 실측 (사전등록 preregistration.json 고정 후 단일 시험).

## C1. paired t 1.565 — ΔIR 점추정 통과이나 통계 확증 미달 [PARTIAL]

- 제기: ΔIR +0.1692는 사전등록 기준(+0.05)의 3.4배이나 paired NW lag-3 t = +1.565 (p≈0.12) — 월별 Δactive의 노이즈로 이 점추정이 나올 확률이 무시 수준이 아니다.
- 처리: PARTIAL 인정. 판정 문구를 "사전등록 ΔIR 기준 충족 + 통계 확증은 보통 수준"으로 제한하고 자본 주장 0. 보강 정황(선택 아닌 병기): ① EW top-25 basis 동방향 ΔIR +0.0931 ② X=5% 진단 동방향 +0.0862(t +1.47) ③ abs MDD −55.9%→−44.4% (11.4pp 개선) ④ 발동 실효 95.7% (구성 실변화) ⑤ 사전등록 단일시험 — sweep 부재로 선택 인플레 0.
- 합리화 자기검증: 회피성 완화 표현 미사용 — 유의성 미달을 헤드라인에 병기.

## C2. lag1 붕괴(ΔIR +0.169 → −0.036) — 동월 누출 의심 [REBUTTAL(구조) + 사실 병기(감쇠)]

- 제기: 신호 1개월 지연 시 편익 전량 소멸 — 동월 look-ahead 실사고(2026-07-06 BearProb) 지문과 유사한가.
- REBUTTAL 근거:
  - 구조: max5 창 = 63거래일 하드 슬라이스, 종점 d0 = 전월말. 홀딩월 first-day 컷오프 대비 간격 1거래일(>0) — C5 컷오프 충족. BearProb 사고는 anchor가 홀딩월 *다음달*(−31일 방향 오류)이었고 본 건은 방향·간격 모두 정상. 창 하드슬라이스로 동월 중첩 기전이 문법적으로 부재(WT-010 동일 판정 승계 — lag1 verdict "누출 기전 구조 부재").
  - 학술 1+: Bali-Cakici-Whitelaw 2011 JFE (MAX effect) — 복권형 프리미엄은 직전월 극단수익 측정·월간 리밸에서 성립하는 단기 현상. 신호 자체의 fast-decay가 문헌 표준과 정합.
  - 정량 3축: ① 신호 종점-홀딩 시작 간격 = 1거래일 실측(PIT 방향 양수) ② lag1 판은 역전이 아니라 0 부근(−0.036) — 누출 제거 후 잔존 신호가 음수로 뒤집히는 오염 지문과 다름 ③ 동일 패널 WT-010 placebo 5시드 대역과 정합(형상 채널 파괴 시 소멸 — 신호 실재).
- 사실 병기(수용): fresh 신호 의존은 실재 — 리밸 집행이 1개월 지연되면 편익 소멸. 운용 함의로 기록.

## C3. CRISIS 역효과 (mean Δ −0.33%/월, t −1.78) [ACCEPT]

- 제기: 사전등록 병기 가설("복권형 배제는 위기월에 더 유효")이 반증됨 — 오히려 위기월에 배제가 해롭다(고-MAX5 종목의 위기 중 과매도 반등 편입 기회를 자름). 편익은 NEUTRAL(t +2.28) 집중.
- 처리: ACCEPT — regime_scope를 실측대로 기록(weakens_or_reverses_in: CRISIS). 국면조건부 필터 on/off는 사후 선택(sweep)이라 본 라운드 채택 금지 — next_probe로만 등재.

## C4. 2015-19 부기간 음수 (Δ −0.19%/월, t −1.13) [ACCEPT]

- 제기: 편익이 전 기간 균질 아님 — pre2015 +1.59 / 2015-19 −1.13 / 2020+ +1.70. 2015-19는 cohort-wide 팩터 감쇠기와 겹치나 본 필터도 그 구간 무효.
- 처리: ACCEPT — 정직 병기. post2017 +1.06(양수 유지)이 최소한의 최근성 방어이나 확증 아님.

## C5. ΔIR basis 혼동 위험 [ACCEPT — 라벨 강제]

- 제기: 본 ΔIR = weighted_screen basis(선별 계층, cap_norm(Size) top-25, 15bps). §4 admission의 ΔIR(net_active_recon_v1, book recon NAV)와 수치 등치 금지.
- 처리: ACCEPT — 전 산출물에 basis 라벨 명기. 자본 관련 주장 없음(admission = governor + 도훈 수동).

## C6. overlay 미반영 [PARTIAL]

- 제기: incumbent book은 R05 overlay(β 스케일) 포함 — 본 측정은 bare 선별 계층. overlay는 곱셈 노출이라 Δ의 부호는 보존되나 크기·위기월 상호작용은 미측정(특히 C3의 CRISIS 역효과는 overlay가 위기 노출을 이미 줄이는 구간과 겹침 — 상쇄 가능).
- 처리: PARTIAL — 한계 명시 + next_probe(overlay-포함 exposure_dt A/B)로 승계.

## 종합

- HIGH severity 위반 0 / PIT C1~C15 hard 위반 0 / AX axiom hard FAIL 0 → Q-Lead escalate 트리거 비발동.
- 판정 요지: 사전등록 기준 충족(특성화 positive) + 통계 확증 보통 + 국면·부기간 이질성 실재. 자본 주장 없음.
- 합리화 스캔: answer-principles 회피표현 목록 전수 대조 — 해당 표현 미사용 확인 (본 절은 목록을 재인용하지 않음, 탐지기 오발화 방지).
