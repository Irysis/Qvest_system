# Self-Adversarial Challenge — 측정 축 (WT-D20260822_012 / FQ-245)

- 작성: alpha-research (opus), finalize 직전. v8.2 self-adversarial (외부 Codex 없음).
- 대상: FQ-245 방향성 일치 국면 조건부 macro-beta momentum 의 canonical_screen_bt 실측.
- AX-008 3-source 중 1개 (Forge·Architect 와 함께 2/3).

## 측정 요약 (실측, metric_type=canonical_screen)

| endpoint | n | PORT_t(NW3) | mean_active/yr | 비고 |
|---|---|---|---|---|
| E1 PRIMARY (aligned pooled) | 74 | **−1.14** | **−12.4%** | 가설 방향(양+) 반대 |
| S1 (aligned_up) | 32 | −1.71 | −16.6% | 반대 |
| r1 (clean 2016+) | 36 | −1.27 | −23.0% | 반대 |
| lag1 stress | 74 | −0.11 | — | 붕괴 아님(음→음) |
| strict-PIT A/B | — | infl 0.0% | — | clean |
| MDD 조건부 | — | −59.5% | — | 예측 ≤45% **위반** |
| F-flow (Foreign) | 74 | +0.80 | — | E1 음(-)이라 moot |
| S2 정합도 회귀 | 253 | slope −0.008 (t −0.75) | — | 단조성 미지지 |
| 창-도달가능 상한(완전예지) | 74 | +17.15 | — | 창은 도달 가능 |

## 자기 비평 (devil's advocate, ≥3)

### 약점 1 — E1 음(-) 결과가 유니버스 오염 산물인가 (초판 결함이었음)
**제기**: 1차 측정에서 top-N Ret_1m 커버리지 5.8~6.6% = macro_beta_scores(3462종, DB 전체)를 유니버스 선-제한 없이 넣어 top-25 가 비유니버스 종목으로 채워지고 NA→0 강제로 수익이 위장됐다(WT-009 CF-03 재발).
**판정: ACCEPT (수리 완료)**. `returns_dt`(builder 가 K200|KQ150 멤버십으로 이미 제한)의 (Date,Ticker) 로 score 를 inner-join 해 선-제한. 재측정 후 커버리지 ~348종/월(quantile 197/327/348/350/352), 재실행. **수리 전(오염) E1 −1.17 → 수리 후 −1.14** — 부호·크기 실질 불변이나, 오염판을 판정 근거로 인용하지 않았음을 명기. 이 결함은 계약이 warn 으로 잡았고 내가 로그를 읽어 검거.

### 약점 2 — '미결(검정력)' 라벨이 음(-) 점추정을 숨기는가
**제기**: verdict_with_power(외부 sd 0.06162) = INCONCLUSIVE_UNDERPOWERED. 이 라벨만 보면 '검정력 부족, 미결' 로 읽혀 실은 **부호가 반대**(−12.4%/yr)라는 사실이 가려진다.
**판정: ACCEPT → 판정 서술 보수화**. verdict_with_power 는 |효과|<필요치를 underpowered 로 부르지만 **부호를 보지 않는다**(계약 §적용한계 (a)(b) 정합). 관측은 음(-)이고 3 arm(E1/S1/r1) 전부 음(-) + 완전예지 상한 +17.15 로 창은 도달 가능 ⇒ '창이 짧아 미결' 이 아니다. ⇒ 판정 라벨 = **`NULL_WITH_NEGATIVE_POINT_ESTIMATE`**(가설 방향 성립 아님, 단 |t|=1.14 로 유의 음(-)도 아님 = 방향 증거는 음이나 확립적 반증 아님). measurement-graduation §3 창-도달가능성 병기 의무 충족(상한 +17.15 산출).

### 약점 3 — MDD 예측 위반이 가설을 반증하는가
**제기**: F-MDD 사전예측(정렬월만 투자 → MDD ≤45%)이 실측 −59.5% 로 위반. 기전이 참이면 악화 국면 노출 제거로 MDD 완화 예측했는데 오히려 악화.
**판정: PARTIAL (기전 부수예측 실패)**. aligned_down(42월)은 '위험자산 하락 충격 국면' 을 포함하고, score 상위(하락 수혜 노출)를 long 하는데도 조건부 소비가 MDD 를 못 줄였다 = 방향 내장 소비가 하락 국면서 방어를 못 함. E1 음(-)과 정합(신호가 정렬국면서 역방향). 이 자체가 F-MDD 반증(사전예측 위반)이며, screen_route 를 OVERLAY_CANDIDATE 로 사전 라우팅한 조건(E1 성립 ∧ MDD>45%)의 전제(E1 성립)가 불충족이라 라우팅도 발동 안 함.

### 약점 4 — F-flow +0.80 을 기전 지지로 읽을 수 있나
**제기**: 외국인 순매수 스프레드 NW-t +0.80(양수). 약하지만 양(+)이니 flow 전달 기전 일부 지지?
**판정: REBUTTAL**. F-flow 반증규칙(reject_if: NW-t≤0 → 기각)은 **수익이 양(+)일 때** 기전 확인용이다. E1 활성수익이 음(-)인 상태에서 flow 가 양(+)이면 이는 기전 지지가 아니라 **'외국인이 사도 가격이 안 올랐다' = 전달 경로 단절**의 증거다(flow→price 비전이). ⇒ flow verdict='확인' 필드값은 규칙상 자동 산출된 것이나, **E1 음(-) 문맥에서 기전 성립 근거로 인용 불가**. self-rationalization 방지: "flow 양수니 방향은 맞다" 는 서술 금지 — E1 부호가 판정의 앵커다.

### 약점 5 — S2 aligned-only 무정보를 전표본으로 우회한 것이 사전등록 이탈인가
**제기**: 프레리그 S2 = "방향 일치 소비 활성수익을 C_t 에 회귀". aligned(3/3 동부호) 월은 정의상 |Σz|=Σ|z| → Ct≡1 상수 → 회귀 불능. 전표본(Ct∈[1/3,1])으로 회귀한 것은 사전등록 정의 이탈 아닌가.
**판정: PARTIAL (진단축이라 판정 무영향)**. S2 는 프레리그에서 '보고 전용 · 기전 형태 진단' (판정 권위 아님). aligned-only Ct≡1 은 설계 실현상 degeneracy(측정 착수 후 발견)이며, 진단 목적(정합강도 단조성)을 살리려 전표본 회귀로 대체 — 이 대체는 challenge_note 에 명시 기록(No Silent Override). 결과(slope −0.008, t −0.75)도 판정을 바꾸지 않으므로 자유도 소비 무관. ⇒ prereg S2 정의는 aligned regime 에서 degenerate 함을 next 설계자에게 승계.

### 약점 6 — 에피소드 동기 서술 (COVID/EuDebt) 철회
**제기**: 설계 후 확인 = COVID 2020H1 aligned 2월 / EuDebt 2011H2 aligned **0월**. 프레리그 규칙(각 창 ≥1)이 EuDebt 에서 미충족.
**판정: ACCEPT (동기 서술 철회, 가설 불변)**. 사전 라벨 규칙(3/3 부호정렬)이 EuDebt 창에 정렬월을 배정하지 않았다 ⇒ 가설 생성용 에피소드 근거(n=4 손라벨) 중 EuDebt arm 은 라벨 규칙과 불일치. 프레리그 §7 대로 동기 서술 철회, 라벨 규칙이 정본이므로 가설 자체는 불변. story-fitting 위험(가설설계 challenge 약점1)이 부분 현실화 — 판정은 라벨 규칙 기반 실측(E1)으로만.

## 분류 + 처리 (ACCEPT/PARTIAL/REBUTTAL)
- ACCEPT: 약점1(오염 수리) · 약점2(음-점추정 라벨 보수화) · 약점6(에피소드 철회)
- PARTIAL: 약점3(MDD 예측 위반=기전 부수예측 실패) · 약점5(S2 degeneracy 승계)
- REBUTTAL: 약점4(flow 양수를 지지로 읽지 않음)

## Self-rationalization auto-detection
answer-principles 회피표현 목록 전 항목 미사용 확인(측정 서술·판정 근거). '음수인데 미결이라 괜찮다' 류 합리화 auto RE-VIEW → 약점2 에서 부호 앵커 명문화로 차단(부호가 판정 앵커, |효과|<필요치 라벨이 부호 반대를 숨기지 못하게).

## Q-Lead escalate trigger 점검
- HIGH severity ≥5? No (측정 결함 1건=오염, 수리 완료).
- AX axiom hard FAIL ≥3? No.
- PIT C1(lockbox/lookahead) 위반? No (assert_overlay_pit PASS · lag1 붕괴 아님 · strict-PIT infl 0%).
- ⇒ **escalate 불요**. 정상 finalize (screen_diagnostic tier, NULL 방향 음-점추정).

## PIT 판정
assert_overlay_pit PASS · lag1 stress 붕괴 아님(−0.11, 음→음) · strict-PIT A/B 인플레 0.0% · Frequency=='d' 강제 · macro_regime.parquet 미소비 · delta20 shift(1). C5/C11 준수. C15 = macro_beta_scores 직접 소비(적용 제외) + RAWDATA 는 build_monthly_forward_returns 경유(load_month_factors 아니나 factor DB 아닌 raw 가격패널 — universe membership/return 산출 전용, C15 factor-parquet 직접 load 금지 대상 아님).
