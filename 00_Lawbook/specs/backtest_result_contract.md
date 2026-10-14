# Backtest Result Contract v1.0 — Qvest 백테스트 산출물 표준

> 모든 전략 백테스트는 동일한 결과 객체 구조를 출력해야 한다.
> 모든 성과지표는 동일한 정의로, 동일한 수익률 벡터에서 계산되어야 한다.
> 추정 지표와 백테스트 지표는 절대 섞이지 않는다.

발효: 2026-04-29 (Session 73, 도훈 명시 지침)
근거 사례: L-247 (Q-Lead 3회 회피 — 표준 부재가 비교 분석 부정확의 근본 원인)
폐지/대체: 기존 schema 미정합 — 신규 전략은 본 contract 의무

---

## 0. 본 Contract의 목적

**Qvest는 리서치 시스템**이다 (도훈 2026-04-29). 실제 운용 서포트가 아니므로:
- 매수/매도 각 0.15% cost는 백테스트 입력 단계에서 차감 → `ret_net`에 반영
- 별도 `costs` / `trades` component 불필요

핵심 원칙:
1. **모든 전략은 동일한 결과 객체 구조를 출력한다**
2. **모든 성과지표는 동일한 정의로 계산한다**
3. **모든 지표는 원천 테이블과 계산 방법을 가진다**
4. **추정 지표와 백테스트 지표를 절대 섞지 않는다**
5. **벤치마크 비교는 별도 표준 테이블로 저장한다**
6. **전략 간 비교는 long-format metrics table과 master registry에서 수행한다**

---

## 1. 10-Component bt_result Schema

```r
bt_result <- list(
  manifest          = run_manifest_tbl,        # §4
  strategy_spec     = strategy_spec_tbl,        # §5
  nav               = nav_tbl,                  # §6
  period_returns    = period_returns_tbl,       # §7
  holdings          = holdings_tbl,             # §8
  benchmark_returns = benchmark_returns_tbl,    # §11
  metrics           = metrics_tbl,              # §12
  benchmark_compare = benchmark_compare_tbl,    # §14
  rolling_metrics   = rolling_metrics_tbl,      # §15
  drawdowns         = drawdown_tbl,             # §16
  audit             = audit_tbl                 # §20
)
```

**제외**:
- §9 `trades` (도훈 결정) — 거래내역 별도 저장 안 함
- §10 `costs` (도훈 결정) — 백테스트 입력 단계 commission=0.0015 차감 → `ret_net` 반영. 별도 component 불필요

**전략 비교 핵심**: `nav`, `period_returns`, `metrics`, `benchmark_compare`. 성과표만이 아니라 **수익률 벡터와 NAV 경로 모두 필수**.

---

## 2. 산출물 파일 구조

```
04_Research/strategies/<strategy_id>/output/
  bt_result.rds                      # R 재사용 원본 객체
  00_manifest.json                   # 실행 증명서
  01_strategy_spec.json              # 전략 계약서
  02_nav.csv
  03_period_returns.csv
  04_holdings.csv
  05_benchmark_returns.csv
  06_metrics.csv                     # long-format
  07_benchmark_compare.csv
  08_rolling_metrics.csv
  09_drawdowns.csv
  10_audit.csv
  report.xlsx                        # 11-sheet 사람용 리포트
```

저장 원칙:
| 파일 | 목적 |
|---|---|
| `.rds` | R에서 재사용할 원본 객체 |
| `.csv` | 다른 시스템과 호환 가능한 표준 산출물 |
| `.xlsx` | 사람이 보는 리포트 (11-sheet) |
| `.json` | 설정·실행 조건·데이터 스냅샷 기록 |

---

## 3. 필수 ID 체계

모든 테이블에 다음 키 포함:

| 필드 | 설명 |
|---|---|
| `run_id` | 특정 백테스트 실행 단위 (예: `STR_1631_SYN_06_20260429_001`) |
| `strategy_id` | 전략 고유 ID (예: `STR_1631_SYN_06`) |
| `strategy_name` | 전략명 |
| `strategy_version` | 전략 버전 |
| `portfolio_id` | 포트폴리오 ID |
| `benchmark_id` | 벤치마크 ID |
| `date` | 기준일 |
| `frequency` | daily / weekly / monthly |
| `currency` | KRW / USD |
| `return_type` | gross / net |
| `data_snapshot_id` | 사용 데이터 버전 |
| `code_version` | git hash 또는 script version |
| `config_hash` | 파라미터 설정 해시 |

---

## 4. manifest 표준

해당 백테스트가 어떤 조건에서 실행됐는지 기록하는 **실행 증명서**.

| 필드 | 예시 |
|---|---|
| `run_id` | `STR_1631_SYN_06_20260429_001` |
| `strategy_id` | `STR_1631_SYN_06` |
| `strategy_version` | `v1.0_variant_A_outlier` |
| `run_datetime` | `2026-04-29T13:00:00+09:00` |
| `start_date` | `2003-02-01` |
| `end_date` | `2026-04-30` |
| `frequency` | `monthly` (rebalance) / `daily` (NAV) |
| `rebalance_rule` | `bimonthly_signal_t_plus_1_execution` |
| `universe_id` | `KR_TOP342_LIQUIDITY_2E8` |
| `benchmark_ids` | `KOSPI200, KOSPI` |
| `transaction_cost_bps` | `15` (commission, 매수/매도 각각) |
| `slippage_bps` | `15` (cost 모델에 포함) |
| `risk_free_rate_source` | `0` 또는 `KR_Gov3Y` |
| `data_snapshot_id` | `quantiwise_20260429` |
| `code_version` | git hash 또는 `run_all.R_v1` |
| `created_by_agent` | `Forge_v55` 또는 `Q-Lead_manual` |
| `integrity_status` | `PASS` / `FAIL` / `WARNING` (audit 결과) |

---

## 5. strategy_spec 표준

전략의 **계약서**. 성과만이 아니라 어떤 규칙으로 만든 전략인지 명시.

| 필드 | 설명 |
|---|---|
| `strategy_id` | 전략 ID |
| `strategy_name` | 전략명 |
| `strategy_family` | Value / Momentum / Quality / Multi-factor / Macro / Allocation |
| `signal_description` | 시그널 설명 (1-2문장) |
| `universe_rule` | 유니버스 구성 규칙 |
| `rebalance_frequency` | monthly / weekly / bimonthly |
| `signal_date_rule` | 예: 월말 종가 기준 |
| `execution_date_rule` | 예: 익월 첫 영업일 시가 |
| `weighting_method` | EW / VW / RP / Optimized / IVOL / HRP |
| `max_position_weight` | 종목당 최대 비중 (예: 0.20) |
| `max_leverage` | 최대 레버리지 (long-only = 1.0) |
| `cash_rule` | 미투자 현금 처리 방식 |
| `cost_model` | commission / tax / slippage 가정 |
| `missing_data_rule` | 결측 처리 방식 |
| `risk_controls` | 섹터 제한 / 베타 제한 / 변동성 제한 |
| `lookahead_prevention` | PIT 검증 방식 (C1~C15 어디 적용) |
| `survivorship_bias_control` | 상장폐지/편입편출 처리 방식 |

---

## 6. nav 테이블 표준

**모든 성과 계산의 중심**. CAGR / MDD / Calmar 모두 nav 경로에서 직접 산출.

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id` | ID |
| `date` | 기준일 (daily) |
| `nav_gross` | 비용 차감 전 NAV |
| `nav_net` | 비용 차감 후 NAV |
| `cash_weight` | 현금 비중 |
| `gross_exposure` | 총 익스포저 |
| `net_exposure` | 순 익스포저 |
| `leverage` | 레버리지 |
| `cum_cost` | 누적 비용 (manifest commission_bps × turnover에서 derive) |
| `drawdown_net` | 순 NAV 기준 drawdown |
| `is_rebalance_date` | 리밸런싱일 boolean |

---

## 7. period_returns 테이블 표준

**Sharpe / Vol / CVaR / Win Rate 모두 여기서 산출**.

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id` | ID |
| `date` | 수익률 기준일 |
| `frequency` | daily / monthly |
| `ret_gross` | 비용 차감 전 수익률 |
| `ret_net` | 비용 차감 후 수익률 |
| `risk_free_ret` | 동일 주기 무위험수익률 |
| `excess_ret_net` | `ret_net - risk_free_ret` |
| `turnover` | 해당 기간 회전율 (holdings 변화에서 derive) |
| `cost_ret` | 비용으로 차감된 수익률 (= ret_gross - ret_net) |
| `cash_weight` | 현금 비중 |
| `leverage` | 레버리지 |
| `n_holdings` | 보유 종목 수 |

**중요 규칙**: period_returns 부재 시 Sharpe / Volatility / CVaR / Win Rate 산출 불가 → audit FAIL.

---

## 8. holdings 테이블 표준

전략의 **실제 포트폴리오 구성**.

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id` | ID |
| `date` | 보유 기준일 (rebalance date) |
| `ticker` | 종목코드 |
| `name` | 종목명 |
| `sector` | 섹터 |
| `target_weight` | 목표 비중 |
| `actual_weight` | 실제 비중 |
| `price` | 기준 가격 |
| `shares` | 보유 수량 |
| `market_value` | 평가금액 |
| `signal_score` | 최종 시그널 점수 |
| `rank` | 종목 순위 |
| `entry_date` | 편입일 |
| `holding_period` | 보유 기간 (개월) |
| `is_new_position` | 신규 편입 boolean |
| `is_exiting_position` | 편출 예정 boolean |

**Turnover 계산**: `L1(actual_weight_t - actual_weight_{t-1}) / 2` (trades 부재 보완).

전략 비교 분석 가능:
- 종목 중복도 (전략 간 유사성)
- 섹터 편중 (리스크 요인)
- 팩터 노출 (알파 원천)
- 회전율 (비용 민감도)
- 실제 구현 가능성 (유동성·거래대금)

---

## 9. ~~trades 테이블~~ — 제외

**제외 사유 (도훈, 2026-04-29)**: Qvest는 리서치 시스템. 거래내역 별도 저장 불필요. holdings 변화에서 turnover derive로 충분.

---

## 10. ~~costs 테이블~~ — 제외

**제외 사유 (도훈, 2026-04-29)**: 매수/매도 각 0.15% cost는 `run_monthly_simulation(commission=0.0015)` 백테스트 입력 단계에서 차감 → `nav_net` / `ret_net`에 반영. 별도 costs 테이블 불필요.

manifest의 `transaction_cost_bps=15` / `slippage_bps=15` 입력 파라미터 기록은 유지 (재현성).

---

## 11. benchmark_returns 테이블 표준

벤치마크는 **하나가 아닌 여러 개** 허용.

| 컬럼 | 설명 |
|---|---|
| `benchmark_id`, `benchmark_name` | ID |
| `date` | 기준일 |
| `frequency` | daily / monthly |
| `benchmark_ret` | 벤치마크 수익률 |
| `benchmark_nav` | 벤치마크 NAV |
| `risk_free_ret` | 무위험수익률 |
| `benchmark_excess_ret` | 벤치마크 초과수익률 |

기본 벤치마크:
| 전략 유형 | 벤치마크 |
|---|---|
| 국내 전체주식형 | KOSPI / KOSPI200 / KRX300 |
| 중소형주 | KOSDAQ / KOSPI Small Cap |
| 글로벌 | MSCI ACWI / ACWX |
| 멀티에셋 | 60/40 / Risk Parity / 현금 |
| 팩터 전략 | EW Universe / Market Cap Universe |

---

## 12. metrics 테이블 표준 (long-format)

```r
metrics_tbl <- data.table(
  run_id, strategy_id,
  metric_group,        # return / risk / drawdown / exposure
  metric_name,         # CAGR / Sharpe / MDD / ...
  metric_value,
  metric_unit,         # percent / ratio / days
  period_start, period_end,
  frequency,           # daily / monthly
  return_type,         # gross / net
  annualization_factor, # 252 / 12
  observation_count,
  metric_type,         # backtested / estimated / proxy / unavailable
  input_source,        # period_returns / nav / holdings
  calculation_method,  # 명시적 공식 reference (예: "PerformanceAnalytics::maxDrawdown")
  is_official          # 공식 성과표 포함 여부 boolean
)
```

**핵심 규칙**:
- `metric_type ∈ {backtested, estimated, proxy, unavailable}`
- **official 성과표 = `metric_type == "backtested" AND is_official == TRUE`만 포함**
- estimated / proxy / unavailable은 long-format에 저장하되 official 산출물 제외

---

## 13. 필수 성과지표 (cost 제외)

### 13.1 수익률 지표
| Metric | 설명 | Source |
|---|---|---|
| Total Return | 전체 누적수익률 | nav |
| CAGR | 연율화 수익률 | nav |
| Annualized Return | 주기 수익률 평균의 연율화 | period_returns |
| Best Period Return | 최고 월/일 수익률 | period_returns |
| Worst Period Return | 최악 월/일 수익률 | period_returns |
| Positive Period Ratio | 양의 수익률 비율 | period_returns |

### 13.2 위험 지표
| Metric | 설명 | Source |
|---|---|---|
| Annualized Volatility | 연율화 변동성 | period_returns |
| Downside Volatility | 하방 변동성 | period_returns |
| VaR 95 / 99 | quantile | period_returns |
| CVaR 95 / 99 | tail mean | period_returns |
| Skewness | 왜도 | period_returns |
| Kurtosis | 첨도 | period_returns |

### 13.3 위험조정 성과
| Metric | 설명 | Source |
|---|---|---|
| Sharpe | 학술 표준 `mean(ER)/sd(ER)*√N` | period_returns |
| Sortino | 초과수익률 / 하방변동성 | period_returns |
| Calmar | CAGR / abs(MDD) | nav |
| Return / CVaR | CAGR / abs(CVaR) | period_returns |
| Pain Ratio | 초과수익률 / 평균 drawdown | nav |

### 13.4 드로다운 지표
| Metric | 설명 | Source |
|---|---|---|
| MDD | 최대 낙폭 | nav |
| MDD Start / Trough / Recovery Date | 일자 | nav |
| Max Drawdown Duration | 최장 회복 기간 | drawdowns |
| Average Drawdown | 평균 drawdown | drawdowns |
| Average Recovery Months | 평균 회복 개월 | drawdowns |

### 13.5 거래 지표 (cost 제외)
| Metric | 설명 | Source |
|---|---|---|
| Average Turnover | 평균 회전율 | holdings |
| Annualized Turnover | 연율화 회전율 | holdings |
| Average N Holdings | 평균 보유 종목 수 | holdings |
| Average Cash Weight | 평균 현금 비중 | period_returns |
| Average Leverage | 평균 레버리지 | period_returns |

**제외**: Total Cost / Cost Drag CAGR (cost component 자체 제외).

---

## 14. benchmark_compare 테이블 표준

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id`, `benchmark_id` | ID |
| `period_start`, `period_end` | 비교 구간 |
| `frequency` | daily / monthly |
| `metric_name` | 비교 지표명 |
| `strategy_value`, `benchmark_value`, `active_value` | 값 |
| `metric_unit` | percent / ratio |
| `observation_count` | 관측치 수 |

필수 비교지표:
| Metric | 의미 |
|---|---|
| Excess CAGR | 전략 CAGR - BM CAGR |
| Excess Total Return | 전략 누적 - BM 누적 |
| Active Return Mean | 평균 초과수익률 |
| Tracking Error | 초과수익률 변동성 |
| Information Ratio | mean(active) / sd(active) * √N |
| Beta to Benchmark | regression coef |
| Alpha Annualized | regression intercept × N |
| Correlation | 전략-BM 수익률 상관 |
| Up Capture | BM 상승기 민감도 |
| Down Capture | BM 하락기 민감도 |
| Hit Ratio vs BM | BM을 이긴 기간 비율 |
| MDD Difference | 전략 MDD - BM MDD |
| Recovery Difference | 전략 회복기간 - BM 회복기간 |
| Worst Relative Month | 최악 초과수익률 기간 |

---

## 15. rolling_metrics 테이블 표준

전략 비교의 핵심은 **전기간 성과가 아니라 안정성**.

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id`, `benchmark_id` | ID |
| `date` | 롤링 계산 기준일 |
| `window` | 3M / 6M / 12M / 36M / 60M |
| `metric_name` | Rolling Sharpe / Rolling MDD / Rolling IR |
| `metric_value` | 값 |
| `return_type` | gross / net |
| `observation_count` | 관측치 수 |

권장:
| Window | 지표 |
|---|---|
| 3M | 단기 수익률 / 단기 초과수익률 |
| 6M | 단기 안정성 |
| 12M | Rolling Return / Rolling Sharpe / Rolling IR |
| 36M | 장기 Rolling Sharpe / Rolling MDD |
| 60M | 장기 Regime Robustness |

---

## 16. drawdowns 테이블 표준

**MDD 1건이 아니라 모든 drawdown 에피소드** 전수.

| 컬럼 | 설명 |
|---|---|
| `run_id`, `strategy_id`, `drawdown_id` | ID |
| `peak_date`, `trough_date`, `recovery_date` | 일자 |
| `drawdown_depth` | 낙폭 |
| `drawdown_length` | 고점~저점 기간 |
| `recovery_length` | 저점~회복 기간 |
| `total_underwater_period` | 전체 물밑 기간 |
| `benchmark_drawdown_depth` | 동일 구간 BM 낙폭 |
| `relative_drawdown` | 전략 DD - BM DD |

이 테이블이 있어야 "MDD는 낮지만 회복이 느린 전략" 같은 문제 식별 가능.

---

## 17. 공식 비교용 Summary View

여러 전략 비교 시 최종 `strategy_comparison_panel`:

| strategy_id | benchmark_id | CAGR | Vol | Sharpe | MDD | Calmar | IR | Hit Ratio | Turnover | CVaR 99 |
|---|---|---|---|---|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

**최종 요약일 뿐**. 모든 값은 nav / period_returns / holdings / benchmark_returns에서 재현 가능해야 함.

---

## 18. Metric 계산 표준

### 18.1 CAGR
```
CAGR = (Final NAV / Initial NAV) ^ (annualization_factor / observation_count) - 1
```
- 월간: annualization_factor = 12
- 일간: annualization_factor = 252

### 18.2 Volatility
```
Annualized Volatility = sd(period_return) * sqrt(annualization_factor)
```

### 18.3 Sharpe (Charter v1.4 §12 학술 표준)
```
Sharpe = mean(period_return - risk_free_return) /
         sd(period_return - risk_free_return) *
         sqrt(annualization_factor)
```
필수 조건:
| 항목 | 조건 |
|---|---|
| 수익률 벡터 | 필수 |
| 무위험수익률 | 명시 |
| 주기 | 명시 |
| 연율화 계수 | 명시 |
| 비용 반영 여부 | 명시 |
| 관측치 수 | 명시 |

### 18.4 MDD
```
Drawdown_t = NAV_t / cummax(NAV_t) - 1
MDD = min(Drawdown_t)
```
**MDD는 수익률 평균이 아닌 NAV 경로에서 계산**.

### 18.5 CVaR
```
VaR_99 = quantile(period_return, 0.01)
CVaR_99 = mean(period_return[period_return <= VaR_99])
```
**실제 분포에서 계산** (parametric assumption 금지).

### 18.6 Information Ratio
```
Active Return = Strategy Return - Benchmark Return
IR = mean(Active Return) / sd(Active Return) * sqrt(annualization_factor)
```

### 18.7 자체 합성 금지 (Charter Plan + 답변 원칙 §8 정합)
| 허용 | 금지 |
|---|---|
| `PerformanceAnalytics::Return.cumulative` | `prod(1+r)-1` 자체 합성 |
| `apply.monthly(R, Return.cumulative)` | `r[, .(prod(1+r)-1), by=YM]` |
| `maxDrawdown` | running max + diff 자체 합성 |
| `table.AnnualizedReturns` | 연간 metric 자체 함수 |
| `Return.portfolio` | `0.8*r1+0.2*r2` 자체 blending |
| `mean(ER)/sd(ER)*sqrt(N)` (Charter v1.4 §12 명시 예외) | — |

---

## 19. 공식 성과표 포함 조건

| 지표 | 공식 포함 조건 |
|---|---|
| CAGR | nav_net 존재 |
| Sharpe | period_returns$ret_net 존재 |
| MDD | nav_net 경로 존재 |
| CVaR | 수익률 관측치 충분 |
| IR | 전략 수익률과 BM 수익률 날짜 정렬 |
| Turnover | holdings 변화 존재 |
| Alpha / Beta | 전략 / BM / 무위험수익률 정렬 |

NA 처리:
- 수익률 벡터 없음 → Sharpe NA (`metric_type='unavailable'`)
- NAV 경로 없음 → CAGR / MDD NA
- 벤치마크 없음 → IR / Beta / Alpha NA
- 거래내역 없음 (Qvest는 holdings로 대체) → Turnover from holdings derive

---

## 20. audit 테이블 표준 (L3 hard block trigger)

**에이전트가 추정치를 백테스트 성과처럼 말하지 못하게 막는 장치**.

| 컬럼 | 설명 |
|---|---|
| `run_id` | ID |
| `check_group` | data / return / metric / benchmark / PIT |
| `check_name` | 점검 항목 |
| `status` | PASS / FAIL / WARNING |
| `details` | 설명 |
| `affected_metrics` | 영향받는 지표 |
| `severity` | low / medium / high / critical |

**10 audit checks** (cost 관련 단순화):

| # | Check | FAIL 조건 |
|---|---|---|
| 1 | `realized_return_vector_exists` | period_returns$ret_net 부재 |
| 2 | `nav_path_exists` | nav$nav_net 부재 |
| 3 | `rebalance_path_executed` | holdings 부재 또는 단일 시점 |
| 4 | `transaction_cost_param_recorded` | manifest$transaction_cost_bps 부재 |
| 5 | `benchmark_aligned` | 전략 / BM 날짜 불일치 |
| 6 | `risk_free_rate_defined` | risk_free_ret 처리 불명확 |
| 7 | `point_in_time_checked` | strategy_spec$lookahead_prevention 부재 |
| 8 | `lookahead_bias_checked` | C1~C15 검증 미수행 |
| 9 | `survivorship_bias_checked` | universe 처리 불명확 |
| 10 | `estimated_metrics_separated_from_backtested` | metrics$metric_type 미분류 |

**Critical FAIL 시**:
- metrics_tbl `is_official=FALSE` 강제
- `metric_type='unavailable'` 변경
- Hook L3 hard block (`metrics_official.csv` / `backtest_registry.csv` 등재 시도 차단)
- L-code 등재 차단 (methodology_active.md)

---

## 21. Excel Report 11-Sheet 구조 (cost / trades sheet 제외)

| Sheet | 내용 |
|---|---|
| 00_Run_Summary | 실행 조건 요약 (manifest) |
| 01_Performance_Summary | 공식 성과표 (metric_type=backtested only) |
| 02_Benchmark_Compare | 벤치마크 비교 |
| 03_NAV | 전략 / BM NAV 경로 |
| 04_Period_Returns | 기간별 수익률 |
| 05_Monthly_Returns | 월별 수익률 매트릭스 |
| 06_Rolling_Metrics | 롤링 성과 |
| 07_Drawdowns | 드로다운 구간 전수 |
| 08_Holdings | 리밸런싱별 보유 종목 |
| 09_Exposure | 익스포저 분석 |
| 10_Audit | 검증 결과 |
| 11_Notes | 주석·한계·예외 |

**제외**: 원래 §21의 09_Trades / 10_Costs 시트 (trades + costs component 제외 정합).

---

## 22. Master Registry — `qepm/registry/backtest_registry.csv`

여러 백테스트 결과를 모아서 관리하는 마스터 테이블.

```r
backtest_registry_columns <- c(
  "run_id", "strategy_id", "strategy_name", "strategy_version",
  "start_date", "end_date", "frequency",
  "universe_id", "benchmark_primary", "return_type",
  "cagr", "vol", "sharpe", "mdd", "calmar",
  "information_ratio", "hit_ratio_vs_bm", "turnover",
  "cvar_99", "integrity_status", "created_at"
)
```

비교 가능 분석:
| 목적 | 비교 기준 |
|---|---|
| 고수익 전략 선별 | CAGR / Total Return |
| 위험조정 성과 | Sharpe / Sortino / Calmar |
| 벤치마크 초과 | IR / Excess CAGR |
| 방어력 | MDD / CVaR / Down Capture |
| 안정성 | Rolling Sharpe / Rolling IR |
| 실전성 | Turnover / Holdings 수 |
| 포트폴리오 편입 가치 | 기존 전략과의 상관 / 초과수익 상관 |

---

## 23. 전략 간 비교 추가 표준

### strategy_correlation 테이블
| 컬럼 | 설명 |
|---|---|
| `strategy_id_1`, `strategy_id_2` | 전략 ID |
| `correlation_return` | 수익률 상관 |
| `correlation_excess_return` | 초과수익률 상관 |
| `correlation_drawdown` | drawdown 상관 |
| `overlap_holdings_avg` | 평균 보유종목 중복도 |
| `overlap_sector_avg` | 평균 섹터 중복도 |

### strategy_diversification_value 테이블
| 컬럼 | 설명 |
|---|---|
| `candidate_strategy_id` | 후보 전략 |
| `base_portfolio_id` | 기존 포트폴리오 |
| `standalone_sharpe`, `combined_sharpe` | 샤프 비교 |
| `marginal_sharpe_contribution` | 한계 샤프 기여 |
| `mdd_reduction` | MDD 개선 |
| `correlation_to_base` | 기존 포트폴리오와 상관 |
| `include_decision` | INCLUDE / WATCH / REJECT |

이게 있어야 "좋은 전략"과 "포트폴리오에 필요한 전략"을 구분 가능.

---

## 24. 적용 범위 (도훈 결정, 2026-04-29)

| 적용 | 범위 |
|---|---|
| **신규 전략** | 의무. `build_bt_result()` 호출 부재 시 PG2 admission 차단 |
| **STR_1631_SYN_06 + STR_1715** | 즉시 retrofit (V1.0 도입 검증용) |
| **나머지 178개 전략** | 사용 시점 wave-by-wave. 미등록 상태 허용 |

---

## 25. AX 정합 + 위반 시 절차

### AX 정합
- **AX-002** (프로세스 우회 = 미래참조): 본 contract가 audit으로 추정 vs 백테스트 분리 → AX-002 직접 enforcement
- **AX-001 v2** (조건부 평가): rolling_metrics + benchmark_compare + drawdowns가 위기 conditional 평가 산출 가능
- **답변 원칙 v1.0** (L-247): metric_type 분류로 "추정 vs 백테스트 분리" 구조 강제

### 위반 시 절차
| Level | 발견 주체 | 조치 |
|---|---|---|
| L1 | 자가 발견 (build_bt_result audit) | metric_type='unavailable' → official 산출표 제외 |
| L2 | Hook PreToolUse[Write] L3 hard block | `backtest_contract_audit.sh` deny + log + Telegram |
| L3 | 사용자 지적 | L-code 등재 + Lawbook §부록 위반 패턴 명문화 |

---

## 26. 변경 이력

| 일자 | 버전 | 변경 |
|---|---|---|
| 2026-04-29 | v1.0 | 도훈 명시 23-section Contract → 21-section (trades + costs 제외) lawbook 신규 작성 |
