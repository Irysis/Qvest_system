#==============================================================================
# measure_scores.R — Shared long-only measurement wrapper (CA / VoC / Causal / IPCA)
#
# Takes a per-stock monthly score parquet (Date,Ticker,score) and measures it as a
# canonical top-N EW LONG-ONLY portfolio via canonical_screen_bt() (contract-grade
# portfolio_alpha_t_nw_lag3 + IR + net SR + turnover, metric_type=canonical_screen).
# This is the UNIFIED measurement (fixes the existing IPCA's custom-diagnostic gap).
#
# Env:
#   MEASURE_SCORES     scores parquet (Date,Ticker,score)
#   MEASURE_PANEL_DIR  dir with returns_monthly.parquet + benchmark_monthly.parquet
#   MEASURE_TAG        label (default = basename of scores)
#   MEASURE_TOPN       top-N (default 20; mandate max 25)
#   MEASURE_OUT        output json (default <scores dir>/measure_<tag>.json)
# Run (PowerShell): & Rscript.exe -e "source('.../measure_scores.R')"
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
# contract first (canonical_screen_bt needs build_benchmark_compare)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R")))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R")))

SCORES <- Sys.getenv("MEASURE_SCORES", "")
PANEL_DIR <- Sys.getenv("MEASURE_PANEL_DIR", file.path(ROOT, "stage_artifacts/WT_CA/panel_kr30"))
TAG <- Sys.getenv("MEASURE_TAG", "")
TOPN <- as.integer(Sys.getenv("MEASURE_TOPN", "20"))
if (!nzchar(SCORES)) stop("MEASURE_SCORES env required")
if (!nzchar(TAG)) TAG <- tools::file_path_sans_ext(basename(SCORES))
OUT <- Sys.getenv("MEASURE_OUT", file.path(dirname(SCORES), paste0("measure_", TAG, ".json")))

# floor Date to month-first so per-ticker month-end dates (vary by ticker) align with
# the single per-month benchmark date — uniform monthly key across scores/returns/bench
norm_date <- function(dt) { dt[, Date := as.Date(cut(as.Date(Date), "month"))]; dt }
scores <- norm_date(as.data.table(read_parquet(SCORES)))
returns <- norm_date(as.data.table(read_parquet(file.path(PANEL_DIR, "returns_monthly.parquet"))))
bench   <- norm_date(as.data.table(read_parquet(file.path(PANEL_DIR, "benchmark_monthly.parquet"))))

cat("[measure:", TAG, "] scores:", nrow(scores), "rows /", uniqueN(scores$Date), "months;",
    "top_n=", TOPN, "\n")

res <- canonical_screen_bt(scores[, .(Date, Ticker, score)],
                           returns[, .(Date, Ticker, Ret_1m)],
                           bench[, .(Date, BM_Ret)],
                           top_n = TOPN, cost_bps_oneway = 15,
                           run_id = TAG, strategy_id = TAG)

# compact summary (drop the bulky benchmark_compare table for the json print)
bc <- res$benchmark_compare
res$benchmark_compare <- NULL
summary <- c(list(tag = TAG, top_n = TOPN, scores_path = SCORES,
                  n_score_months = uniqueN(scores$Date)), res)

cat(sprintf("[measure:%s] n_months=%s  PORT_t_nw=%.3f  IR=%.3f  net_SR=%.3f  alpha_ann=%.4f  TO=%.2f\n",
            TAG, res$n_months,
            ifelse(is.null(res$portfolio_alpha_t_nw_lag3) || is.na(res$portfolio_alpha_t_nw_lag3), NA, res$portfolio_alpha_t_nw_lag3),
            ifelse(is.null(res$information_ratio) || is.na(res$information_ratio), NA, res$information_ratio),
            ifelse(is.null(res$net_sr) || is.na(res$net_sr), NA, res$net_sr),
            ifelse(is.null(res$alpha_annualized) || is.na(res$alpha_annualized), NA, res$alpha_annualized),
            ifelse(is.null(res$turnover_annual) || is.na(res$turnover_annual), NA, res$turnover_annual)))

# gate check vs graduation HARD thresholds (PORT_t>=2.95, IR>0.2) — diagnostic
port_t <- res$portfolio_alpha_t_nw_lag3
summary$gate_port_t_2_95 <- isTRUE(!is.na(port_t) && port_t >= 2.95)
summary$gate_ir_pos <- isTRUE(!is.na(res$information_ratio) && res$information_ratio > 0.2)

write_json(summary, OUT, pretty = TRUE, auto_unbox = TRUE, na = "null")
if (!is.null(bc)) fwrite(bc, file.path(dirname(OUT), paste0("benchmark_compare_", TAG, ".csv")))
cat("[measure:", TAG, "] saved ->", OUT, "\n")
