# PIT Enforcement (Level 0)

**최상위 규칙. 모든 목표보다 우선.**
**상세 코드**: `02_Infrastructure/validation/pit_enforcement.R` + `lookahead_detector.R`

## 핵심 3질문 (매 데이터 접근 전)

1. "이 데이터는 의사결정 시점에 알 수 있었는가?"
2. "이후 결과가 판단에 영향을 미치지 않는가?"
3. "'괜찮다'고 느끼는 이유가 결과를 이미 알기 때문은 아닌가?"

## 금지 표현 (자동 탐지)

"영향 미미 / 관행적 허용 / 보수적이면 괜찮다 / 대부분 결과 동일 / 이미 반영되어 있었을 것 / 백테스트 기간이 충분히 길어서 상쇄"

→ 합리화 자체가 위반. 즉시 중단 → 결과 무효 → 연쇄 오염 파악 → 재실행 → 보고.

## C1~C15 체크리스트

| Code | 위반 패턴 |
|---|---|
| C1 | full-sample 통계 사용 (rolling/expanding window만). ★**평가 창 결과를 소비하는 자동 선정 규칙도 C1/C14 대상이다**(2026-09-23 도훈 확정 · D-E) — 팩터·arm·슬리브를 전기간 IC·ic_bad·상관으로 고르면 시점 t 보유를 미래 통계로 정한 것이다. 선정 통계는 as-of(`Usable_Date <= 결정 시점`)로만. 사람이 문헌 근거로 고르는 것은 해당 없음 |
| C2 | same-day circular reference |
| C3 | 같은 기간 집계 → 적용 |
| C4 | 재무제표 lag 위반 (annual = **익년 3/31**, quarterly 45일+ / DART 분기 고정일 5/15·8/15·11/15 — 2026-07-25 도훈 확정, 현 구현(data_collector_dart.R:840) 정합. 구 표기 'annual 5월' 폐기. ⚠ xlsx 경로의 Q4 일률 +45d(≈익년 2/14)는 3/31 대비 공격적 — 수리 항목, AST v1.1 SOT §3 참조) |
| C5 | overlay signal 타이밍 위반 — 신호는 **홀딩월 시작 전** 데이터만 (§ 오버레이 신호 타이밍) |
| C6 | survivorship bias |
| C7 | 자동 탐지 패턴 (lookahead_detector.R) |
| C8 | FM weight same-day 사용 |
| C9 | VT/DD same-day 사용 (`dd_lag <- c(0, dd_pct[-n])`) |
| C10 | 유동성 필터 당일 거래량 사용 (t-1 PIT) |
| C11 | 데이터 시간축 검증 (FRED 시차 등) |
| C13 | NEGATE_FACTORS / FLIP_SIGN 금지. Z_Score_Aligned only |
| C14 | IC 접근 시 Usable_Date <= sig_date |
| C15 | Factor DB parquet 직접 load 금지. `load_month_factors()` 경유 |

## 종목수 + 유동성 (실투용)

- 종목수 max 25 (hook 강제, 도훈 mandate 2026-05-29 20→25)
- 유동성: 20일 평균 거래대금 ≥ 2e8 KRW (`LIQ_THRESHOLD = 2e8`)
- 슬리브 조합 시에도 최종 portfolio 25명 이하 (e.g., 2-sleeve N_def + N_ind ≤ 25)

## 오버레이 신호 타이밍 (C5 구체화 — 2026-07-06 도훈 지시, 실사고 재발방지)

**사건**: BearProb 오버레이가 신호를 `Date < anchor_date`로 로드했는데 `anchor_date = 홀딩월(return_ym)의 *다음달* 첫 거래일`(실측 간격 ~31일) → **홀딩월 말 정보로 그 홀딩월 수익을 스케일 = ~1개월 동월 look-ahead**(faith 오버레이 버그 재발). 정정 시 Calmar 2.50→1.83·SR 2.10→1.84로 개선 전량 소멸. placebo/OOS/DSR/subperiod 다 통과 → **lag1 스트레스 + strict-PIT A/B만 판별**.

**원칙**: 오버레이 신호는 **홀딩월이 시작되기 전** 데이터로만 계산·적용한다.
- 홀딩월 = 수익(ret)이 실제로 벌리는 캘린더 월. clean 컷오프 = **first-day-of-holding-month**. 신호는 `Date < 컷오프`만.
- 패널별 홀딩월: `period_returns_*` → return_ym / `alpha_scores_*` → month(Date)+1 (β-scan offset+1 실증). **anchor_date·realized_ym(라벨)로 컷오프 잡지 말 것.**

**의무 (오버레이 리서치 전 항목)**:
1. `source("02_Infrastructure/validation/overlay_pit_guard.R")` → `assert_overlay_pit(used_cutoff, holding_start)` **HARD 통과**.
2. **lag1 스트레스**: 신호 shift(1) 적용판 측정 — base 대비 붕괴하면 동월 누출 의심.
3. **strict-PIT A/B**: 현재 타이밍 vs `Date < first-day-of-holding-month`. `overlay_lookahead_ab()` 인플레 >5%면 strict 값으로 재판정.
4. 신규 패널 소비 전 **anchor_date − 홀딩월 간격 확인** + score→forward-ret IC 부호(양수=PIT 방향 정상)로 윈도우 의미 실증.

## S0/S1 오버레이 금지

- S0 (가설) / S1 (구현)에서 DD/VT/Regime 오버레이 적용 금지
- S1은 순수 팩터 신호 측정. EW 20종목 + 15bps + 유동성만
- 예외: 전략 자체가 국면을 alpha source로 사용 시만 Regime 허용
- **오버레이는 S5 Mutation 또는 v6.4 Optimizer/Forge에서만**

## Lockbox — 폐지 (v10 2026-08-29 도훈 지시)

**lockbox / Frozen Alpha(봉인 창) 제도는 완전 폐지됐다** ("lock box 개념은 삭제. 전략 구현 시 가용 가능한 데이터를 모두 활용할 것. 전기간 사용 허용. 반박 금지"). 전 에이전트·전 단계가 가용 데이터 전기간을 사용한다.

- **PIT C1~C15 는 계층 무관 불변** — lockbox 폐지는 미래참조 허용이 아니다. 검증 주체 = Judge(PIT 전담 에이전트, A등급 후 스폰).
- ⚠혼동 금지: C5 오버레이 신호 타이밍의 `overlay_signal_cutoff()`(`overlay_pit_guard.R`) + 등록 훅 `overlay_pit_grep.sh`는 lockbox 가 아니라 **살아있는 PIT 기계** — 불변.
- IS/OOS anchored 분할(`essence_score.R` oos_retention)도 lockbox 가 아니라 측정 규율 — 불변.
- 구 제도 전문·훅 계층 사연(2026-08-24 "세 층이 동시에 비어 있었다" 정정 포함) = `02_Infrastructure/docs/rules/lockbox-scope.md`(RETIRED 사료) + git 태그 `pre-v10-2layer`.
- (존치 교훈) **양성 대조 없는 계기는 방어선으로 세지 않는다** — 발화 실증(위반 주입 + 돌연변이 통제) 없는 훅·검사기를 방어선 목록에 올리지 말 것.

## V6 Gap-Directed 가설

- S0 가설에 `expected_role` + `why_now` 필수
- `.cache/portfolio_gap_vector.json` → 현재 SR/CAGR/MDD gap 확인
- `.cache/conditional_ic_matrix.csv` → 조건부 IC 높은 팩터 우선

## 위반 시 처리

1. 즉시 중단
2. 결과 무효
3. 연쇄 오염 파악
4. 재실행
5. 사용자 보고
