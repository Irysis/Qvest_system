## q1 — STR_1698 계약 retrofit 가능성 확인 (sim_result 요구 필드 vs 보유 산출물)
## 헌법 근거: backtest-contract.md "기존 178개: **사용 시점 전환**" — retrofit 은 인정된 경로.
## 보유: daily_nav.csv · performance_summary.json · crowding/oos json · PNG. **holdings 없음**.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say  <- function(fmt, ...) { cat(sprintf(paste0("[q1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/harness_compliance.R")

say("=== 1. build_bt_result 가 sim_result 에서 요구하는 필드 ===")
L <- readLines("02_Infrastructure/contracts/backtest_result_contract.R", warn=FALSE)
hits <- regmatches(L, gregexpr("sim_result\\$[A-Za-z_.]+", L))
flds <- sort(unique(sub("^sim_result\\$", "", unlist(hits))))
say("  참조 필드 %d개: %s", length(flds), paste(flds, collapse=", "))

say("=== 2. STR_1698 보유 산출물 ===")
d <- "04_Research/strategies/STR_1698_WT008_M08_Swap/backtest_result"
ff <- list.files(d); say("  %d개: %s", length(ff), paste(ff, collapse=", "))
NAV <- fread(file.path(d, "daily_nav.csv"))
say("  daily_nav.csv 컬럼: %s · %d행", paste(names(NAV), collapse=", "), nrow(NAV))
say("  범위 %s ~ %s", min(NAV[[1]]), max(NAV[[1]]))
PS <- tryCatch(fromJSON(file.path(d, "performance_summary.json")), error=function(e) NULL)
if (!is.null(PS)) say("  performance_summary 키: %s", paste(names(PS), collapse=", "))

say("=== 3. ★필드별 조달 가능성 ===")
avail <- list(
  nav          = "★가능 — daily_nav.csv",
  returns      = "★가능 — nav 차분(계약 내부 함수 경유)",
  dates        = "★가능 — daily_nav.csv",
  holdings     = "✗불가 — 산출물 없음(PG2 와 동일 결손)",
  weights      = "✗불가 — 산출물 없음",
  turnover     = "△부분 — performance_summary 에 있으면",
  benchmark    = "★가능 — 외부 벤치 계열",
  costs        = "△선언값(15bps)로 대체"
)
for (k in names(avail)) say("  %-12s %s", k, avail[[k]])
say("  ⇒ 요구 필드 중 **holdings/weights 가 결손**이다.")

say("=== 4. ★판정: retrofit 이 무엇을 주고 무엇을 못 주나 ===")
say("  줄 수 있는 것: period_returns → benchmark_compare → **PORT_t·IR·metrics**")
say("     = book-marginal 판정에 필요한 것은 **전부 조달 가능**하다.")
say("  못 주는 것: holdings/weights 기반 컴포넌트(04_holdings) · 그에 의존하는 진단")
say("     = 소비면 분석(필터·겹침)은 여전히 불가. PG2 도 같은 상태다(칩 task_be236d0c).")
say("  ★그러나 **retrofit 은 PIT 를 검증하지 않는다** — 계약 밖에서 만든 NAV 를 감싸는 것뿐이다.")
say("     C15 는 경유 확인됐으나(load_month_factors) 그것만으로 PIT 전체가 보장되지 않는다.")
say("     ⇒ 정직한 라벨 = **metric_type='backtested(retrofit)' + PIT 미검증 명시**.")
say("=== 5. 현재 준수 상태 재확인 ===")
r <- harness_compliance(d)
say("  10-component %d/11 · C15 %s · compliant %s · metric_type %s",
    r$ten_component, r$c15 %||% "미상", r$compliant, r$metric_type)
`%||%` <- function(a,b) if (is.null(a)||is.na(a)) b else a
say("=== ★결론 ===")
say("  retrofit 은 **book-marginal 판정에 필요한 컴포넌트를 전부 만들 수 있다**(holdings 제외).")
say("  단 ①PIT 검증은 별개 ②holdings 결손은 PG2 와 동일한 미해소 상태")
say("  ⇒ 다음 세션 착수 조건: 계열 연장(2024-04 종료) 이 선행 — 연장 없이는 파킹 겹침 51<60 로 막힌다.")
say("     연장 = run_all.R 재실행(57,986바이트, 일간 DB 의존) → 칩 task_b065b34d 범위.")
