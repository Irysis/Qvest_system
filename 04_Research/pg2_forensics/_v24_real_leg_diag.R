# _v24_real_leg_diag.R — b0 REAL 레그 "'names' attribute" 에러 원인 추적 (2026-06-11)
# b0_fee_ab_test.R real_low 레그를 동일 구성으로 재현 + sys.calls 캡처. metric_type=diagnostic

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
if (!"Name" %in% names(RAWDATA))   RAWDATA[, Name := Ticker]
if (!"Sector" %in% names(RAWDATA)) RAWDATA[, Sector := NA_character_]

cat("[diag] RAWDATA cols:", paste(names(RAWDATA), collapse = ","), "\n")
cat("[diag] BM_DT cols:", paste(names(BM_DT), collapse = ","),
    "| BM range:", as.character(min(BM_DT$Date)), "~", as.character(max(BM_DT$Date)), "\n")
cat("[diag] RAWDATA Date class:", class(RAWDATA$Date)[1],
    "| BM Date class:", class(BM_DT$Date)[1], "\n")

me <- RAWDATA[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
sig_dates <- sort(me$d)
sig_dates <- sig_dates[sig_dates >= as.Date("2019-12-01") & sig_dates <= as.Date("2023-12-31")]
sig_dt <- data.table(Date = sig_dates)
f_rlow <- RAWDATA[sig_dt, on = "Date", nomatch = 0][
  !is.na(Size) & !is.na(Close), .(Date, Ticker, Score = Size)]
cat("[diag] f_rlow rows:", nrow(f_rlow), "| sig dates:", length(unique(f_rlow$Date)), "\n")

trace_txt <- NULL
out <- withCallingHandlers(
  tryCatch({
    sim <- run_monthly_simulation(RAWDATA, BM_DT, f_rlow,
                                  n_holdings = 20, commission = 0.0015,
                                  initial_cap = 1e8, weight_method = "equal")
    nav <- sim$DAILY_NAV_DT
    cat(sprintf("[diag] SIM OK: nav rows=%d nav_end=%.0f\n", nrow(nav), tail(nav$NAV, 1)))
    "OK"
  }, error = function(e) {
    cat("[diag] ERROR:", conditionMessage(e), "\n")
    cat("[diag] CALL STACK (innermost last):\n")
    writeLines(trace_txt)
    "ERROR"
  }),
  error = function(e) {
    calls <- sys.calls()
    trace_txt <<- sapply(calls, function(cl) substr(paste(deparse(cl), collapse = " "), 1, 160))
  })
cat("[diag] result:", out, "\n")
