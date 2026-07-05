#!/usr/bin/env Rscript
# eval_candidates.R — 직교 sleeve 후보 발굴 (XATTN + factor DB 318 scan)
#   기준: score_eff-book active(−BM)와 active-cor < 0.30  AND  standalone canonical PORT_t > 1.0
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("stage_artifacts/beat_pg2_ortho_sleeve_20260705/harness.R")
OUTDIR <- "stage_artifacts/beat_pg2_ortho_sleeve_20260705"

# book active series (PG2 recon) — 상관 기준
bl <- readRDS(file.path(OUTDIR, "pg2_baseline.rds"))
book_act <- bl$net_active_series[, .(ym, book_active = active)]

# precompute grids once per date-universe (heavy forward-return/liquidity recomputation shared across all candidates)
.GRIDS <- new.env()
get_grid <- function(sig_dates) {
  key <- paste0("g", length(sig_dates), "_", as.character(min(sig_dates)), "_", as.character(max(sig_dates)))
  if (is.null(.GRIDS[[key]])) .GRIDS[[key]] <- precompute_grid(sig_dates)
  .GRIDS[[key]]
}

# helper: candidate canonical active + cor vs book + PORT_t (uses matching precomputed grid)
eval_cand <- function(scores_dt, label, family) {
  sd <- sort(unique(as.data.table(scores_dt)[!is.na(score)]$Date))
  grid <- tryCatch(get_grid(sd), error = function(e) NULL)
  res <- if (is.null(grid)) NULL else tryCatch(canon_active_fast(scores_dt, grid, top_n = 25L), error = function(e) NULL)
  if (is.null(res) || is.null(res$period_returns) || nrow(res$period_returns) < 24L)
    return(data.table(code = label, family = family, n = if(is.null(res)) 0L else nrow(res$period_returns %||% data.table()),
                      active_cor = NA_real_, standalone_port_t = NA_real_, net_sr = NA_real_, ir = NA_real_))
  pr <- as.data.table(res$period_returns)
  pr[, ym := format(date, "%Y-%m")]
  pr[, cand_active := ret_net - benchmark_ret]
  J <- merge(pr[, .(ym, cand_active)], book_act, by = "ym")
  ac <- if (nrow(J) >= 24L && stats::sd(J$cand_active) > 0 && stats::sd(J$book_active) > 0)
          suppressWarnings(cor(J$cand_active, J$book_active)) else NA_real_
  data.table(code = label, family = family, n = nrow(pr),
             active_cor = ac, standalone_port_t = res$portfolio_alpha_t_nw_lag3,
             net_sr = res$net_sr, ir = res$information_ratio, n_overlap = nrow(J))
}

results <- list()

# ---- (a) XATTN (WT_D20260705_001) ----
cat("[eval] XATTN ...\n")
xa <- as.data.table(read_parquet("stage_artifacts/WT_D20260705_001/alpha_scores.parquet"))
# use 'score' (primary). alpha_active_hat also available.
xs <- xa[, .(Date, Ticker, score)]
r_x <- eval_cand(xs, "XATTN_score", "cross_sectional_attention")
results[["XATTN_score"]] <- r_x
if ("alpha_active_hat" %in% names(xa)) {
  xs2 <- xa[, .(Date, Ticker, score = alpha_active_hat)]
  results[["XATTN_alpha_active_hat"]] <- eval_cand(xs2, "XATTN_alpha_active_hat", "cross_sectional_attention")
}
cat(sprintf("[eval] XATTN score: cor=%.3f PORT_t=%.2f\n", r_x$active_cor, r_x$standalone_port_t))

# ---- (b) factor DB 318 scan ----
cat("[eval] loading factor DB (long format, all months) ...\n")
fdb_files <- sort(list.files(FDB_DIR, pattern = "factor_db_\\d{6}\\.parquet$", full.names = TRUE))
# 2005+ only (canonical universe era) — keep files >= 200501
keep <- fdb_files[as.integer(gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", fdb_files)) >= 200501]
cat(sprintf("[eval] factor_db months: %d (2005-01+)\n", length(keep)))
# load Date,Ticker,Factor_Name,Z_Score only
FDB <- rbindlist(lapply(keep, function(f)
  as.data.table(read_parquet(f, col_select = c("Date","Ticker","Factor_Name","Z_Score")))), use.names = TRUE)
FDB <- FDB[!is.na(Z_Score)]
factors <- sort(unique(FDB$Factor_Name))
cat(sprintf("[eval] %d factors, %s rows loaded\n", length(factors), format(nrow(FDB), big.mark=",")))

# align factor Date to STR_1715 sig_dates (monthly). Factor DB Date is month-key; recon uses raw Date.
# canon_active uses scores_dt Date directly as sig_date; FDB Date must be a raw trading date. Check overlap.
fdb_dates <- sort(unique(FDB$Date))
raw_dates <- sort(unique(.LOAD$raw$Date))
cat(sprintf("[eval] fdb date range %s~%s | raw range %s~%s\n",
            as.character(min(fdb_dates)), as.character(max(fdb_dates)),
            as.character(min(raw_dates)), as.character(max(raw_dates))))

# scan: for each factor, higher Z_Score = long. (raw Z_Score, C13-aligned already — no sign flip C13.)
scan_res <- vector("list", length(factors))
for (k in seq_along(factors)) {
  fn <- factors[k]
  sc <- FDB[Factor_Name == fn, .(Date, Ticker, score = Z_Score)]
  scan_res[[k]] <- eval_cand(sc, fn, "factor_db")
  if (k %% 40 == 0) cat(sprintf("  ... %d/%d\n", k, length(factors)))
}
FR <- rbindlist(scan_res, use.names = TRUE, fill = TRUE)
results[["factor_db"]] <- FR

# ---- combine + rank ----
ALL <- rbindlist(results, use.names = TRUE, fill = TRUE)
setorder(ALL, -standalone_port_t)
fwrite(ALL, file.path(OUTDIR, "all_candidates_scan.csv"))

# orthogonal + positive: cor<0.30 AND PORT_t>1.0
ORTHO <- ALL[!is.na(active_cor) & !is.na(standalone_port_t) & active_cor < 0.30 & standalone_port_t > 1.0]
setorder(ORTHO, -standalone_port_t)
fwrite(ORTHO, file.path(OUTDIR, "orthogonal_positive_candidates.csv"))

cat(sprintf("\n[eval] TOTAL candidates scanned: %d\n", nrow(ALL)))
cat(sprintf("[eval] ORTHOGONAL(cor<0.30) & POSITIVE(PORT_t>1.0): %d\n", nrow(ORTHO)))
cat("[eval] TOP orthogonal+positive:\n")
print(head(ORTHO[, .(code, family, active_cor = round(active_cor,3), standalone_port_t = round(standalone_port_t,2),
                     net_sr = round(net_sr,2), n = n)], 15))
saveRDS(ALL, file.path(OUTDIR, "all_candidates_scan.rds"))
cat("[eval] DONE — saved all_candidates_scan.csv + orthogonal_positive_candidates.csv\n")
