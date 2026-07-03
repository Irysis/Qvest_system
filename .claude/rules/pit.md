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
| C1 | full-sample 통계 사용 (rolling/expanding window만) |
| C2 | same-day circular reference |
| C3 | 같은 기간 집계 → 적용 |
| C4 | 재무제표 lag 위반 (annual 5월, quarterly 45일+) |
| C5 | overlay signal t-1 기준 위반 |
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

## S0/S1 오버레이 금지

- S0 (가설) / S1 (구현)에서 DD/VT/Regime 오버레이 적용 금지
- S1은 순수 팩터 신호 측정. EW 20종목 + 15bps + 유동성만
- 예외: 전략 자체가 국면을 alpha source로 사용 시만 Regime 허용
- **오버레이는 S5 Mutation 또는 v6.4 Optimizer/Forge에서만**

## Lockbox / Frozen Alpha Scope (도훈 mandate 2026-05-09)

**원칙**: Lockbox / Frozen alpha (SIGNAL_CUTOFF) 정책은 **정규 리서치 단계 (alpha-research / risk-research / optimizer-research)** 에만 적용.

**운용·트래킹 단계 폐기**:
- forge (전기간 백테)
- monitoring (라이브 성과 트래킹)
- execution (주문 schedule)
- Q-Lead (집계 보고 / 도훈 mandate 응답)

이 단계들은 **최신 sig_date까지 자동 갱신** 의무 (lockbox 무관).

**상세 SOT**: `02_Infrastructure/docs/rules/lockbox-scope.md`

**Hook 강제**: `02_Infrastructure/hooks/selection_contamination_detector.sh` v6.5
- alpha / risk / optimizer / opt_ → block (정규 리서치 lockbox 차단)
- judge / forge / monitoring / execution → allow + audit log
- Q-Lead / unidentified → allow
- ⚠ **실커버리지 (2026-07-03 도훈 confirm, 아키텍처 감사)**: 본 훅과 역할경계 훅(`agent_role_guard`)은 agent marker(`/tmp/qvest_current_agent_{pid}`) 존재 시에만 발화하며, marker 자동 기록 메커니즘은 부재 — marker 미존재 시 allow. 실제 방어선 = R 계약(essence_score/registry_writer) + 게이트급 훅(safety_guard·backtest_contract_audit·legacy_write_block·discovery_graduation_gate) + 수동 confirm.

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
