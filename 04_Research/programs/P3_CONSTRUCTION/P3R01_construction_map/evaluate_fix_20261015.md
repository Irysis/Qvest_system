# P3R01 평가 스크립트 수리 기록 — 2026-10-15 01:00 무렵 (R2 감사 흔적)

## 무엇을 바꿨나
`evaluate.R` 의 기준 CDaR 판독. 구판은 기준 칸(P0R01_E1_C0 · P0R01_E2_C0) 평가 파일 `eval.json` 의 `visible$cdar` 를 읽었다.
그런데 P0R01 `evaluate.R` 의 visible 목록에는 cdar 가 없다(round_kit 이전 판). 그래서 `cdar0 = NA` 가 되고 `improve` 가 전부 FALSE 로 떨어진다.
결과적으로 측정값과 무관하게 판정이 `no_lever_over_ew` 로 고정됐다.

수리: 사전등록 문구(`rules.improve` = "보는 창 CDaR(behavior.stats.cdar)")대로, 같은 기준 칸의 보는 창 진단 패킷
`results/<기준 칸>/visible/diagnosis_packet.json` 의 `behavior.stats.cdar` 에서 읽는다(`eval.json` 에 값이 있으면 그대로 둔다).
그래도 못 읽으면 판정하지 않고 멈춘다. 이때 `evaluation.json` 은 쓰지 않는다(조용한 'EW 유지' 금지).

## 왜 규칙 개정이 아닌가
판정 규칙 · 지표 · 문턱 · 기준 칸은 그대로다. 등록된 문구가 지정한 필드를 그 문구대로 읽게 한 구현 수리다.
발견 경로: P3R02 사전등록 격리 교차 점검 ②(2026-10-15 00:48)의 권고.

## 열람 선언
수리 시점에 P3R01 · P0R01 칸 결과(json · log · eval.json · 패킷)의 **내용은 열지 않았다**. 파일 존재와 수정 시각만 확인했다.
수리는 합성 픽스처로만 검증했다(양방향 — 패킷이 있으면 읽고, 없으면 멈춘다).
그 시각 밤 파이프라인은 ② P0R01 칸 평가 단계였다. P3R01 측정 · 평가(④)는 시작 전이었다.

## 같이 확인한 것
같은 파이프라인의 P2R02 평가는 패킷을 직접 읽고, P1R01 평가는 eval.json 의 uc 만 읽는다 — 둘 다 해당 없음.
