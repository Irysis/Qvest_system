# challenge_note.md — WT-D20260802_015 Self-Adversarial Challenge (v8.2)

작성: alpha-research agent (finalize 직전 자기 적대검증). 판정 대상 = 튜닝 5팩터 국면-조건부 로테이션 실측 (사전등록 `stage_artifacts/WT_D20260802_015/preregistration.json`).

## 실측 요약 (전부 metric_type=canonical_screen, cap-w 권위, 295개월)

| arm | PORT_t | IR | TO/yr | EW-uni t | EW-uni post17 |
|---|---|---|---|---|---|
| PRIMARY 튜닝 로테이션 | +0.90 | 0.198 | 7.5 | +1.32 | −0.87 |
| C1 EW-정적(튜닝) | +0.34 | 0.068 | 5.2 | +0.28 | +0.05 |
| C2 base 로테이션 | +1.40 | 0.293 | 7.2 | +2.02 | −0.18 |
| C3 M01_PATHQ 단일 | +2.05 | 0.444 | 7.9 | +2.38 | +1.54 |

paired: 튜닝로테이션−base로테이션 t=−1.22 (−1.91%/yr) / 로테이션−EW정적 t=+1.28 (+2.72%/yr, post17 −1.59) / 로테이션−단일최강 t=−1.26.
PIT: assert_overlay_pit PASS + 위반 주입 차단 발화 + regime lag1 무붕괴(+1.25 > clean +0.90) + 오염판(r_{t+1}) −15.7% 열위.

## Concern 1 — 국면 라벨 3층(KTRI/VEA/FRED)의 vintage 전수 미감사 [ACCEPT]

- 제기: MSM 층은 expanding refit로 확인(`msm_daily_refit.R` — "이전 refit window는 그 때 계산됨")했으나 KTRI/VEA/FRED_MRS 층의 역사행 재계산 여부는 본 라운드에서 전수 감사하지 않았다.
- 처리: **ACCEPT (한계 기록, spec 변경 불요)**. 근거: 라벨 look-ahead는 성과를 **부풀리는** 방향인데 본 판정은 negative — 보수 방향으로 강건. 결정적으로 오염 주입판(홀딩월 자체 라벨 = 1개월 완전 look-ahead)조차 clean 대비 −15.7% **열위**(PORT_t 0.76 vs 0.90) → 이 라벨 축에는 애초에 이 규칙으로 착취 가능한 조건부 정보가 근소하다. 라벨 오염이 결론을 만들 수 없는 구조.

## Concern 2 — 단일 비중 규칙 1개만 측정 — family 판결로 오독될 위험 [ACCEPT]

- 제기: clip0 조건부-IC-비례 1규칙만 측정(사전등록 준수·sweep 회피의 대가). softmax/t-stat 가중/조건부-active 가중 등 미측정.
- 처리: **ACCEPT — 판정 scope를 config-scoped로 한정 서술**. 본 라운드 결론은 "이 규칙+이 라벨+이 팩터 풀"의 negative이지 국면-로테이션 family 판결이 아님(INV-7). 단 posterior 정합: DIST-RAMP-006(regime 변형 전량 천장 ~2.85)·WT-005/006(factor-timing OOS 벽)과 방향 일치 — 규칙 변형 재도전의 기대값은 낮게 사전 평가.

## Concern 3 — EW_INIT 24 + MIXED 56개월 희석이 paired t를 0으로 끌었다는 가설 [REBUTTAL]

- 제기: 초기 EW/fallback 월이 처치 강도를 희석해 로테이션 효과가 가려졌을 수 있다.
- 처리: **REBUTTAL (정량 3축 + L-code + 문헌)**.
  - 축1: COND-only 215개월 한정 재검 — 재탕 판별 t=−0.56(여전히 base 열위), 로테이션-vs-EW t=+0.36(효익 소멸 방향).
  - 축2: **전환월(라벨 변경 69개월) 한정 t=−0.27** vs 비전환월 +1.50 — 로테이션이 실제로 '움직인' 달의 기여가 0 이하. 겉보기 +1.28은 국면 전환이 아니라 지배 국면(RISK_ON 212/295)의 지속 tilt(M01 0.31·D03 0.28 평균 비중)에서 발생 = 사실상 정적 IC-tilt.
  - 축3: 오염판(미래 라벨)조차 열위 −15.7% — 라벨 정보력 부재로 희석 가설과 독립적으로 기전 기각.
  - L-code: DIST-RAMP-006 (n_sup=9, regime 변형 전량). 문헌: Arnott-Beck-Kalesnik 계열 factor-timing OOS 취약(WT-005 사전등록에서 소비한 HKS 프레임과 동일).

## Concern 4 — 규칙의 목적함수 미스매치: IC-비례 가중이 IC→PORT_t 전이 벽을 상속 [ACCEPT — 본 라운드 핵심 기전 지식]

- 제기: 비중을 조건부 **IC**에 비례시켰는데, 시스템 실측 공리급 사실은 "IC 강함 ≠ top-25 실현 active"(v8.3 M1 근거). 실제로 D03_EWMA는 IC 최상위(0.041)이나 PORT_t −1.73인데, 규칙이 NEUTRAL에서 D03에 0.33, CAUTION에서 Q01_EB(-0.21)에 0.60을 배정 — **전이 벽이 있는 팩터로 비중을 끌고 가는 구조적 anti-selection**.
- 처리: **ACCEPT**. 이것이 튜닝 로테이션이 base 로테이션보다도 열위인 기전 진단(튜닝 D03_EWMA의 IC가 base D03보다 강해 더 큰 비중을 받는데 PORT_t는 더 나쁨: −1.73 vs −1.43). WT 프롬프트 권고 규칙(조건부 IC 비례)을 사전등록대로 측정한 정직 산출이며, 결과적으로 **"조건부-IC 가중은 전이 벽을 국면 축으로 재수입한다"**는 지식이 본 라운드의 실질 산출물.

## Concern 5 — 재탕 판별의 방향 해석 [ACCEPT]

- 제기: 도훈 제시 차별 가설 D1("튜닝이 상관 0.209→0.145로 낮춰 축 분리 전제가 다름")은 지지되는가.
- 처리: **ACCEPT — D1 반증으로 판정**. 튜닝판 로테이션(+0.90)이 base판 로테이션(+1.40)보다 열위(−1.91%/yr). 상관 개선(축 분리)은 로테이션 효익으로 전이되지 않았고, 오히려 튜닝이 만든 IC-강화(D03_EWMA)가 Concern 4 기전으로 역효과. **재탕 여부 단답: 재탕 이하 — 구 config(base 입력 국면배분) 대비 개선 없음(방향 열위, 유의 아님)**.

## Self-rationalization 자기검증

answer-principles 회피표현 목록(pit.md 금지 표현 조항의 5종 패턴) 전수 grep — 본 노트·산출물에 해당 표현 사용 없음 확인. 오염판 열위(−15.7%)를 "PIT 무결의 증거"로 과대 해석하지 않도록 주의 — 정확한 서술은 "이 규칙이 소비하는 라벨 축의 조건부 정보가 근소하다"이며, 라벨 자체의 vintage 무결 증명은 아님(Concern 1).

## Q-Lead escalate 판정

HIGH severity 0건 / AX hard FAIL 0건 / PIT C1 위반 0건 → escalate 불요. 판정: NEGATIVE config-scoped, 자본 진행 없음, forge 미제출.
