#!/usr/bin/env Rscript
# dpl_ortho_pit_audit.R — WT_DPL_ORTHO 패널 PIT 검증 (dpl_pit_audit.R와 동일 로직, OUT만 ORTHO).
# Cycle 50 lookahead 재발 방지: bear_date_audit + forward-label 독립 재계산 대조.
# Exit: 0 = ALL PASS, 1 = ANY FAIL.

suppressPackageStartupMessages({ library(arrow); library(data.table) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_ORTHO")
PANEL <- file.path(OUT, "dpl_feature_panel.parquet")
RAW  <- file.path(ROOT, ".cache", "rawdata.parquet")

fail <- function(msg) { cat("[dpl_pit][FAIL]", msg, "\n"); quit(status = 1L) }

cat("[dpl_pit] (1) bear_date_audit.R ...\n")
ba <- system2("Rscript",
  c(shQuote(file.path(ROOT, "02_Infrastructure/sanity_checks/bear_date_audit.R"))),
  stdout = TRUE, stderr = TRUE)
cat(paste(ba, collapse = "\n"), "\n")
ba_status <- attr(ba, "status"); if (is.null(ba_status)) ba_status <- 0L
bear_pass <- (ba_status == 0L)
cat(sprintf("[dpl_pit] bear_date_audit exit=%d -> %s\n", ba_status,
            ifelse(bear_pass, "PASS", "FAIL")))

cat("[dpl_pit] (2) DPL panel forward-label independent recompute ...\n")
pan <- as.data.table(read_parquet(PANEL))
pan[, ymk := format(as.Date(date), "%Y-%m")]

raw <- as.data.table(read_parquet(RAW, col_select = c("Date","Ticker","Close","AdminStock","TradingHalt")))
raw[, Date := as.Date(Date)]
raw <- raw[!is.na(Close) & Close > 0]
raw[, ymk := format(Date, "%Y-%m")]
setorder(raw, Ticker, Date)
me <- raw[, .SD[.N], by = .(Ticker, ymk)]
setorder(me, Ticker, ymk)
me[, close_next := shift(Close, n = 1L, type = "lead"), by = Ticker]
me[, fwd_recompute := close_next / Close - 1]
me[, close_prev := shift(Close, n = 1L, type = "lag"), by = Ticker]
me[, bwd_recompute := Close / close_prev - 1]

cmp <- merge(pan[, .(ymk, Ticker, Ret_1m)], me[, .(ymk, Ticker, fwd_recompute, bwd_recompute)],
             by = c("ymk","Ticker"), all.x = TRUE)
cmp <- cmp[!is.na(Ret_1m) & !is.na(fwd_recompute)]
set.seed(42)
samp <- cmp[sample(.N, min(500L, .N))]
samp[, fwd_match := abs(Ret_1m - fwd_recompute) < 1e-6]
samp[, bwd_match := !is.na(bwd_recompute) & abs(Ret_1m - bwd_recompute) < 1e-6]
fwd_rate <- mean(samp$fwd_match)
bwd_rate <- mean(samp$bwd_match)
cat(sprintf("[dpl_pit] panel-label forward_match=%.4f  backward_match=%.4f  (n=%d)\n",
            fwd_rate, bwd_rate, nrow(samp)))
panel_pass <- (fwd_rate >= 0.95) && (bwd_rate < 0.10)
cat(sprintf("[dpl_pit] panel forward-label -> %s (forward>=0.95 AND backward<0.10)\n",
            ifelse(panel_pass, "PASS", "FAIL")))

out <- list(bear_date_audit_pass = bear_pass, bear_exit = ba_status,
            panel_forward_match = fwd_rate, panel_backward_match = bwd_rate,
            panel_pass = panel_pass, n_sample = nrow(samp),
            overall_pass = bear_pass && panel_pass)
jsonlite::write_json(out, file.path(OUT, "pit_audit.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[dpl_pit] pit_audit.json written.\n")

if (!out$overall_pass) fail("PIT audit failed — sweep 진입 금지 (Cycle 50 재발 방지).")
cat("[dpl_pit] ALL PASS — sweep 진입 허가.\n")
