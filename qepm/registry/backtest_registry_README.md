# Backtest Registry — Master Strategy Comparison Table

**Lawbook**: `00_Lawbook/Multi_Agent/backtest_result_contract.md` §22

## 사용

### 등재 (R)
```r
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/registry_writer.R")

# 1. bt_result 빌드
bt <- build_bt_result(sim_result, strategy_spec, run_id, strategy_id, ...)

# 2. Audit
bt <- audit_bt_result(bt)

# 3. Registry 등재 (audit FAIL 시 자동 차단)
register_bt_result(bt)
```

### 조회
```r
source("02_Infrastructure/contracts/registry_writer.R")
read_registry_summary(top_n = 10)  # Sharpe 내림차순
```

## 21 컬럼

| 컬럼 | 설명 |
|---|---|
| `run_id` | 실행 단위 |
| `strategy_id` | 전략 ID |
| `strategy_name` | 전략명 |
| `strategy_version` | 버전 |
| `start_date`, `end_date` | 기간 |
| `frequency` | daily/monthly |
| `universe_id` | 유니버스 |
| `benchmark_primary` | 1차 벤치마크 |
| `return_type` | gross/net |
| `cagr`, `vol`, `sharpe`, `mdd`, `calmar` | 핵심 metric |
| `information_ratio`, `hit_ratio_vs_bm` | vs BM |
| `turnover` | 평균 회전율 |
| `cvar_99` | tail risk |
| `integrity_status` | PASS/WARNING/FAIL (audit 결과) |
| `created_at` | 등재 시점 |

## L3 Hard Block

`integrity_status == "FAIL"` 인 bt_result는 **Registry 등재 자동 차단**.
Hook: `02_Infrastructure/hooks/backtest_contract_audit.sh` PreToolUse[Write].
