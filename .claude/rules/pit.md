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
| C4 | 재무제표 lag 위반 — ★현행(11-16~ · 도훈 FUNDAMENTAL-AVAIL-DEADLINE45-20261116 '보수적으로 법정기한 + 45일' · '공개일 + 1개월 규칙은 삭제'): 쓸 수 있는 첫날 = max(**법정 제출기한 + 45일 뒤 첫 거래일**, 공개일 뒤 첫 거래일). 법정 제출기한 = 사업보고서 기간 말 + 90일 · 분기 · 반기 + 45일(자본시장법 제159조 · 제160조 · DART 정기보고서 제출기한 · 마지막 날이 휴일이면 다음 거래일) · 공개일 = 퀀티 공시일과 DART 접수일 중 늦은 날(기한보다 늦게 낸 회사의 값을 제출 전에 쓰지 않는 바닥 · 공시일이 없으면 법정 마감 규칙) · 정정 의심 연도 = 다음 회계연도 사업보고서 공개일 · DART 당시 값도 같다 · 등록부 `06_Registry/fundamental_source.json`(legal_deadline_days · deadline_buffer_days · avail_lag_months = 0) · 재무 v2 = 11-09~ active. ★소비 규약(11-16): 재무 원천 parquet 을 직접 읽는 엔진 · 빌더는 행의 `Factor_Date`(생산자가 위 규칙으로 계산한 쓸 수 있는 첫날) ≤ 결정 시점으로만 거른다 — 엔진 안 고정 시차(익년 3/31 · +45일 · 분기 고정일)만 쓰면 위 규칙보다 이르다. 고정 규칙은 `pmax(고정, Factor_Date)` 처럼 늦추는 쪽으로만 덧댄다(레인 사전검사 P14 가 잡는다). ★정정 덮어쓰기(퀀티는 정정 뒤 값을 원래 기간에 붙인다 · 2014년 이전 · 2015~ DART 미대조 값은 정정 여부를 알 수 없다) = 위 보수 규칙(법정기한 + 45일)으로 대응한다(도훈 11-16 · 퀀티와이즈 정본 · 원 공시본 · DART 공시 목록은 수집하지 않는다 — FUNDAMENTAL-ORIGINAL-FILINGS-PIPELINE-20261116 C) — 법정기한 + 45일 뒤에 나온 정정만 PIT 경계로 남는다(기록 · L-JG-20261115_200516). ★팩터 DB 수리 이전 측정은 재측정 전 인용 · 소비 금지 — 기계 판정 = `contracts/factor_db_vintage.R`(A 자격 상시 보류 `factor_db_stale`) |
| C5 | overlay signal 타이밍 위반 — 신호는 **홀딩월 시작 전** 데이터만 (§ 오버레이 신호 타이밍) |
| C6 | survivorship bias — ★상장 전 이력 사용 금지(11-16 도훈 · RAWDATA-PRELISTING-EXCLUDE-20261116): 나중에 상장한 종목의 상장 전 이력(장외 K-OTC · 프리보드 · 코넥스)은 백테스트 · 팩터 · 유니버스 어디에도 쓰지 않는다 — 종목은 유가증권 · 코스닥 첫 상장 시점 이후 퀀티와이즈 가격부터 쓰고, 그 전 기간은 유니버스에서 뺀다. 장외 · 코넥스 데이터는 수집하지 않는다 |
| C7 | 자동 탐지 패턴 (lookahead_detector.R) |
| C8 | FM weight same-day 사용 |
| C9 | VT/DD same-day 사용 (`dd_lag <- c(0, dd_pct[-n])`) |
| C10 | 유동성 필터 당일 거래량 사용 (t-1 PIT) |
| C11 | 데이터 시간축 검증 (FRED 시차 등) |
| C13 | NEGATE_FACTORS / FLIP_SIGN 금지. Z_Score_Aligned only. 방향은 정본 접근자의 `direction` 인자로만 고른다 — `ic_asof`(기본 · 그 날까지의 IC 부호) · `registry`(등록부에 미리 선언된 기대수익 방향) · `defensive`(등록부 방어 방향). 시점을 넘는 학습 · 고정 방향 정렬은 `registry`, 방어 틸트는 `defensive`(11-09 FACTOR-COMBINABLE-VIEW · FACTOR-DIRECTION-TWO-VIEWS · 정책 `factor_db/DIRECTION_POLICY.md`) |
| C14 | IC 접근 시 Usable_Date <= sig_date |
| C15 | Factor DB parquet 직접 load 금지. `load_month_factors()` 경유 · 결합용 뷰(순위 [−1,1])는 `fc_load_month()` 경유 — 저장본 `.cache/factor_combinable/` 직접 읽기도 같은 위반(스캐너 `c15_load_path_scan.R`) |

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

## 오버레이 적용 위치 (v10.2 · 1계층 — 구 'S0/S1 오버레이 금지'의 현행 표기 · 2026-11-10)

- 충실구현(논문 그대로) 측정에는 논문에 없는 DD/VT/Regime 오버레이를 붙이지 않는다(순수 신호 측정)
- 예외: 논문(전략) 자체가 국면을 alpha source로 쓰면 그 국면만 허용
- **오버레이는 처방 · 강화 사슬(P2 방어 엔진 · P4 걸음)에서만** — 위 '오버레이 신호 타이밍'(C5) 의무와 함께

## Lockbox — 폐지 (v10 2026-08-29 도훈 지시)

**lockbox / Frozen Alpha(봉인 창) 제도는 완전 폐지됐다** ("lock box 개념은 삭제. 전략 구현 시 가용 가능한 데이터를 모두 활용할 것. 전기간 사용 허용. 반박 금지"). 전 에이전트·전 단계가 가용 데이터 전기간을 사용한다.

- **PIT C1~C15 는 계층 무관 불변** — lockbox 폐지는 미래참조 허용이 아니다. 검증 주체 = Judge(PIT 전담 에이전트, A등급 후 스폰).
- ⚠혼동 금지: C5 오버레이 신호 타이밍의 `overlay_signal_cutoff()`(`overlay_pit_guard.R`) + 등록 훅 `overlay_pit_grep.sh`는 lockbox 가 아니라 **살아있는 PIT 기계** — 불변.
- IS/OOS anchored 분할(`essence_score.R` oos_retention)도 lockbox 가 아니라 측정 규율 — 불변.
- 구 제도 전문·훅 계층 사연(2026-08-24 "세 층이 동시에 비어 있었다" 정정 포함) = `02_Infrastructure/docs/rules/lockbox-scope.md(10-14 정리로 보관소행 · 99_Archive/reorg_20261014 · 태그 pre-reorg-20261014)`(RETIRED 사료) + git 태그 `pre-v10-2layer`.
- (존치 교훈) **양성 대조 없는 계기는 방어선으로 세지 않는다** — 발화 실증(위반 주입 + 돌연변이 통제) 없는 훅·검사기를 방어선 목록에 올리지 말 것.
- ★정보 경계 τ_D = **2022-12-31**(v10.01 D6 · 2026-10-13 도훈 확정 — 구 ORGANIC-DE 09-25 의 컨트롤러 한정 예외를 승계·확장): 처방 에이전트(분석가·처방 담당·팩터 정의자·리뷰어) · 최종 후보 선택 규칙 · 교훈 카드는 τ_D 이전 성과·위기만 본다. 2023-01~ = 강건성 시험 구간. 사람·등급·Judge·BOOK·전략 구현은 전기간 그대로. 경계는 수치 튜닝만 막는다 — LLM 사전학습의 서사 지식(Glasserman & Lin 2023, arXiv:2309.17322)은 막지 못하므로 시험 구간 판정은 크기 짝 대조와 함께 읽는다.

## 조건부 IC 소비 (C1/C14 · D-E-V6 2026-09-25 — 구 'V6 Gap-Directed 가설' 절의 살아 있는 규칙만 · 2026-11-10)

- 조건부 IC 는 **`Usable_Date <= 결정 시점`의 조건부 IC**만 쓴다. **as-of 판 미제공 시 사용 안 함**(현행 `.cache/conditional_ic_matrix.csv` = 전기간 스냅샷 → C1/C14 대상 · 엔진 소비 함수 4종은 `02_Infrastructure/validation/cond_ic_asof_guard.R` 호출부 가드가 가린다 · D-E-V6 2026-09-25 도훈 결정)

## 위반 시 처리

1. 즉시 중단
2. 결과 무효
3. 연쇄 오염 파악
4. 재실행
5. 사용자 보고
