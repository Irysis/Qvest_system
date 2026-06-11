# v24_adv_verify_d.R — liquidation-path crash equivalence: PRE-PATCH harness (5e2b83fc^)
# Confirms the rbindlist 4-vs-7 column portfolio_log crash on liquidation months is
# PRE-EXISTING (not introduced by the v2.4 patch). metric_type=diagnostic.
Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "04_Research/pg2_forensics/_prepatch_harness_v24check.R"))

syn_dates <- seq(as.Date("2020-01-01"), as.Date("2021-06-30"), by = "day")
syn_dates <- syn_dates[as.integer(format(syn_dates, "%u")) <= 5]
tk_all <- sprintf("T%02d", 1:10)
SYN_RAW <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW[, `:=`(Close = 10000, Ret = 0, Name = Ticker, Sector = "SYN")]
SYN_BM  <- data.table(Date = syn_dates, BM_Ret = 0)
syn_me  <- SYN_RAW[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
syn_sig <- sort(syn_me$d)
f_liq <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  if (i == 6L) data.table(Date = syn_sig[i], Ticker = "T01", Score = NA_real_)
  else         data.table(Date = syn_sig[i], Ticker = tk_all[1:5], Score = 5:1)
}))

err <- tryCatch({
  run_monthly_simulation(copy(SYN_RAW), copy(SYN_BM), copy(f_liq), n_holdings = 5,
                         commission = 0.0015, initial_cap = 1e8, weight_method = "equal")
  NA_character_
}, error = function(e) conditionMessage(e))

cat(sprintf("[prepatch liquidation probe] error='%s'\n", err))
jsonlite::write_json(list(prepatch_commit = "5e2b83fc^", error = err,
                          crashed = !is.na(err)),
                     file.path(ROOT, "04_Research/pg2_forensics/v24_adv_verify_d.json"),
                     auto_unbox = TRUE)
