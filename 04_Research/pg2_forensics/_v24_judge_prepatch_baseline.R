# _v24_judge_prepatch_baseline.R — judge_oos_helper.R 패치 *전* 합성 baseline 캡처
# (2026-06-11, cost model v2.4 작업. metric_type=diagnostic)
# .joh_run_static_weight_sim 의 현행(v2.3 flat ~30bps/리밸) 수치를 패치 전에 고정 기록.
# 패치 후 기본값 회귀(no-op) 판정의 비교 기준으로 사용.

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/validation/judge_oos_helper.R")

# 합성: 가격고정 Close=10000, Ret=0 -> NAV 감소 = 순수 비용 (b0 패턴 재사용)
syn_dates <- seq(as.Date("2020-01-01"), as.Date("2021-06-30"), by = "day")
syn_dates <- syn_dates[as.integer(format(syn_dates, "%u")) <= 5]
tk_all <- sprintf("T%02d", 1:10)

SYN_RAW <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW[, `:=`(Close = 10000, Ret = 0, Name = Ticker, Sector = "SYN")]

# 정적 weight: T01~T05 EW (judge helper는 고정 weight 월리밸 시뮬)
wdt <- data.table(Ticker = tk_all[1:5], Weight = rep(0.2, 5))

sim <- .joh_run_static_weight_sim(copy(SYN_RAW), copy(wdt),
                                  start_date = as.Date("2020-01-01"),
                                  end_date   = as.Date("2021-06-30"),
                                  commission = 0.0015,
                                  initial_cap = 1e8)

nav <- sim$daily_nav
out <- list(
  file        = "02_Infrastructure/validation/judge_oos_helper.R",
  captured    = "PRE-PATCH (v2.3 flat: full-sell 15bps + full-buy 15bps per rebal)",
  date        = as.character(Sys.Date()),
  metric_type = "diagnostic",
  n_rebal     = sim$n_rebalances,
  nav_end     = tail(nav$NAV, 1),
  total_ret   = tail(nav$NAV, 1) / 1e8 - 1,
  ann_turnover_pct = sim$ann_turnover_pct,
  period      = paste(min(nav$Date), "~", max(nav$Date))
)
jsonlite::write_json(out, "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/pg2_forensics/v24_judge_prepatch_baseline.json",
                     auto_unbox = TRUE, digits = 12)
cat(sprintf("[baseline] n_rebal=%d nav_end=%.4f total_ret=%.8f\n",
            out$n_rebal, out$nav_end, out$total_ret))
