# Challenge Note — WT-D20260802_018 (FQ-002 계약수주 magnitude 파일럿)

**작성**: 2026-08-02, alpha-research Self-Adversarial Challenge (v8.2 — finalize 직전 자가 적대검증)
**대상**: pilot_results.json (n=24 IC개월, 2024-07~2026-06 시그널) + diag_size_confound.json + 4셀

## 실측 요약 (도전 대상)

| 셀 | meanIC | t (NW) | FMB t | 판정 지위 |
|---|---|---|---|---|
| A_revenue (primary) | +0.0164 | +0.52 (+0.57) | +0.46 | **사전등록 primary — null** |
| A_size (진단) | +0.0806 | +1.97 (+1.70) | +1.43 | 진단 병기 — 선택 금지 |
| B_revenue (정정소급) | +0.0084 | +0.27 | +0.39 | 누출검증용 |
| B_size (정정소급) | +0.0763 | +1.93 | +1.43 | 누출검증용 |
| A_revenue lag1 | +0.0089 | +0.31 | +0.08 | C5 스트레스 |

정정 A/B: mean(B−A) = −0.0080, paired t = −0.74 → **정정반영판 우위 없음 = 누출 지문 없음**.
canonical(참고): A_revenue PORT_t −0.73 / EW-uni +0.36 · A_size PORT_t −0.37 / EW-uni +1.49.

## Concern 1 — "primary null은 검정력 부족이지 신호 부재가 아니다" (자기 반론)

n=24 개월, IC sd ≈0.15 → 검출가능 효과크기 ≈ IC 0.06+ 수준. primary meanIC +0.016은
그보다 한참 작아 "작은 양의 신호"와 "0"을 구분 못 한다.
**분류: PARTIAL.** 파일럿의 사전등록 목적 자체가 "전구간 3.2일 크롤을 지불할 가치" 스크리닝이었고,
관측된 +0.016(t 0.52)은 지불 문턱에 못 미친다는 판정으로 충분하다. 단 보고서에
"null 확정"이 아니라 "**config-scoped 미달** (검정력 한계 병기)"로 서술한다 — 사전등록 §5도
파일럿은 자본 판정이 아니라고 명시.

## Concern 2 — "분모 축 결과 이질성은 revenue 분모의 측정 노이즈일 수 있다"

revenue 분모가 null인데 size 분모가 t≈1.9인 것은 신호가 아니라 **분모 품질** 문제일 수 있다:
최근매출액은 ① 억원 미만 반올림(rounding_flag) ② 외화환산(fx_flag) ③ 공시 시점의 stale 연간치
가 섞이고, 심지어 계약상대방 매출과의 혼동 위험(파서 v2에서 차단)도 있었다. 시총 분모는 신선한
시장가치라 노이즈가 작다.
**분류: ACCEPT (해석 반영).** 다만 이것이 primary 승격 근거가 되지는 않는다(사전등록 위반 = sweep).
next_probe #1로 도출: size-분모를 primary로 **새로 사전등록**하는 후속 라운드.

## Concern 3 — "A_size t=1.97은 소형주 틸트다"

**분류: REBUTTAL — 실측 3축 기각.** ① 같은 창 pure 1/Size IC = −0.066 (t −1.96, 소형주 역풍
— 2025-26 초대형주 레짐 정합) ② score~1/Size 단면 rank 상관 = **−0.025** (직교: 대형사가 큰
계약을 따서 분자가 규모에 비례) ③ size-잔차화 IC +0.077 (t 1.91) 생존. 오히려 역풍을 이기고
있다. (학술 근거: contract/order-backlog 계열은 SUE-류 정보 이벤트로 분류 — Jegadeesh-Livnat
2006 revenue surprise drift 계보. L-code 계보: occurrence null(t=0.59) EV-지도 D4와 양립 —
발생이 아니라 크기·가치관련성이 정보량.)
**주의 병기**: t 1.97은 문턱 근방 — WT-013 멤버십 섭동 sd 0.378 선례상 ±0.4는 흔들린다.
"살아있는 lead"이지 "확립"이 아니다.

## Concern 4 — "canonical PORT_t 음수인데 IC를 논하는 것 자체가 전이 벽 재현"

**분류: ACCEPT.** IC→PORT_t 전이 벽(v8.3)은 이 데이터에서도 그대로 관찰된다
(A_size IC t 1.9 → cap-w PORT_t −0.37). top-20 EW 포트는 occurrence+magnitude 혼합인 데다
cap-w 벤치와 구성 미스매치(EW-uni 진단은 +1.49로 갈림 = mega-cap 벤치 아티팩트 방향).
파일럿 판정을 IC 단계로 사전 한정한 것은 이 벽을 인지한 설계였고, 다음 라운드가 size-분모로
가더라도 **랭킹 소비면이 아니라 필터/오버레이 소비면**(WT-014/016 선례: 랭킹 −1.616 → 필터
ΔIR +0.169)을 우선 검토해야 한다.

## Concern 5 — "재파싱이 측정 중간에 파서를 바꿨다 — 사전등록 위반 아닌가"

**분류: REBUTTAL (근거 명시).** 파서 v2는 **값을 보고 규칙을 바꾼 게 아니라** 커버리지 결함
(자율공시 서식 22.9% 전량 NO_AMOUNT)을 수리한 것이다. 수리는 IC 측정 *이전*에 완료됐고
(재파싱 → 패널 빌드 → 측정 순서), 회귀검증 2/2(자율공시형 신규 추출 + 표준형 불변) + 상대방
매출 오염 차단을 실증했다. 사전등록의 "판별 불가분 보수적 제외" 원칙은 잔존 148건에 그대로
적용. 스모크(부분 22개월, 구파서)와 본측정의 수치 차이는 이 커버리지 회복 + 표본 확장에서 온다
— 스모크는 판정에 사용하지 않았다.

## 합리화 자기검증

answer-principles 회피표현 조항의 금칙 패턴을 본 노트의 판정 문장에 사용하지 않았음을
자가 확인함 (판정은 전부 수치 병기: t=+0.52, paired t=−0.74, 잔차화 t=+1.91 등).
성과 위장 없음 — primary는 음성으로 정직 보고하고 전구간 확장을 지불하지 않는다.

## Q-Lead escalation 판정

HIGH severity concern 0건 (PIT C1 위반 없음 · lockbox 무관 · AX hard FAIL 없음) → escalate 불요.
