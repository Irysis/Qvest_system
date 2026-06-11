# =============================================================================
# prep_s1b_s3.R — Track W substrate preparation: S1 (STR_1715 blend recon),
#   B (core/defense 2-sleeve), S3 (STR_1550 consensus core alpha, capped 25)
# Prereg: TRACKW_WEIGHTING_PREREG_v1. Outputs to intermediate/.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(zoo) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
INT_DIR    <- file.path(TRACKW_DIR, "intermediate")
dir.create(INT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R")))

month_end <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L

# ── load RAWDATA (full — needed by S3 factor_engine + return computation) ────
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]
BM_DT[, Date := as.Date(Date)]

# ── benchmark monthly (apply.monthly + Return.cumulative — standard fns) ─────
bm_x <- xts(BM_DT$BM_Ret, order.by = BM_DT$Date)
bm_m <- apply.monthly(bm_x, PerformanceAnalytics::Return.cumulative)
bench_dt <- data.table(ym = format(as.Date(index(bm_m)), "%Y-%m"),
                       bm_ret = as.numeric(bm_m))
fwrite(bench_dt, file.path(INT_DIR, "bench_monthly.csv"))
cat(sprintf("[prep] bench monthly: %d months %s ~ %s\n", nrow(bench_dt),
            bench_dt$ym[1], bench_dt$ym[nrow(bench_dt)]))

# =============================================================================
# S1 — STR_1715 blend_65_35 top-20 reconstruction (b1 selections, PIT-verified)
# =============================================================================
sel <- fread(file.path(PROJECT_ROOT, "04_Research/pg2_forensics/intermediate/variant_top20_selections.csv"))
sel <- sel[variant == "blend_65_35"]
sel[, `:=`(Date = as.Date(Date), w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]

pan <- as.data.table(read_parquet(file.path(PROJECT_ROOT,
        "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]
keep_cols <- intersect(c("Date","Ticker","score_eff","score_core_z","score_defense_z","Ret_1m"), names(pan))
panB <- pan[, ..keep_cols]
write_parquet(panB, file.path(INT_DIR, "b_panel.parquet"))

s1 <- merge(sel[, .(Date, w_idx, r_idx, Ticker, Ret_1m)],
            panB[, .(Date, Ticker, Score = score_eff)],
            by = c("Date","Ticker"), all.x = TRUE)
stopifnot(s1[is.na(Score), .N] == 0)
n_na_ret <- s1[is.na(Ret_1m), .N]
s1[is.na(Ret_1m), Ret_1m := 0]   # canonical convention (NA -> 0); count reported
setorder(s1, Date, -Score)
write_parquet(s1, file.path(INT_DIR, "s1_sel.parquet"))
s1_grid <- unique(s1[, .(w_idx, r_idx)]); setorder(s1_grid, w_idx)
fwrite(s1_grid, file.path(INT_DIR, "s1_grid.csv"))
cat(sprintf("[prep] S1: %d month-rows | %d months | NA Ret_1m->0: %d | %s ~ %s\n",
            nrow(s1), nrow(s1_grid), n_na_ret,
            as.character(min(s1$Date)), as.character(max(s1$Date))))

# =============================================================================
# B — between-sleeve selections from panel
#   B01-05 score-level theta top-20 | core top-13 / defense top-12 sleeves
# =============================================================================
last_pan_d <- max(panB$Date)
bt_dates <- sort(unique(panB[Date < last_pan_d, Date]))
panB2 <- panB[Date %in% bt_dates]
panB2[, w_idx := as.Date(vapply(Date, function(d) as.character(month_end(d)), character(1)))]
panB2[, r_idx := as.Date(vapply(Date, function(d)
        as.character(month_end(seq(as.Date(d), by = "1 month", length.out = 2)[2])), character(1)))]
panB2[is.na(Ret_1m), Ret_1m := 0]

theta_grid <- c(B01 = 0.35, B02 = 0.50, B03 = 0.65, B04 = 0.80, B05 = 1.00)
b_score_sel <- list()
for (bid in names(theta_grid)) {
  th <- theta_grid[[bid]]
  panB2[, sc_th := th * score_core_z + (1 - th) * score_defense_z]
  s <- panB2[!is.na(sc_th), .SD[order(-sc_th)][1:min(20, .N)], by = Date,
             .SDcols = c("Ticker","sc_th","Ret_1m","w_idx","r_idx")]
  s[, trial := bid]
  b_score_sel[[bid]] <- s[, .(trial, Date, w_idx, r_idx, Ticker, Score = sc_th, Ret_1m)]
}
b_score <- rbindlist(b_score_sel)
write_parquet(b_score, file.path(INT_DIR, "b_score_sel.parquet"))

core13 <- panB2[!is.na(score_core_z), .SD[order(-score_core_z)][1:min(13, .N)], by = Date,
                .SDcols = c("Ticker","score_core_z","Ret_1m","w_idx","r_idx")]
def12  <- panB2[!is.na(score_defense_z), .SD[order(-score_defense_z)][1:min(12, .N)], by = Date,
                .SDcols = c("Ticker","score_defense_z","Ret_1m","w_idx","r_idx")]
core13[, sleeve := "core"]; def12[, sleeve := "defense"]
setnames(core13, "score_core_z", "Score"); setnames(def12, "score_defense_z", "Score")
b_sleeves <- rbindlist(list(core13, def12), use.names = TRUE)
write_parquet(b_sleeves, file.path(INT_DIR, "b_sleeve_sel.parquet"))
cat(sprintf("[prep] B: score-grid rows %d | sleeve rows %d | months %d\n",
            nrow(b_score), nrow(b_sleeves), length(bt_dates)))

# =============================================================================
# S3 — STR_1550 FACTORS regeneration (factor_engine.R sourced VERBATIM)
#   then cap top-25 (immutable max-names; original n=30+buffer dropped, doc'd)
# =============================================================================
S3_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1550_consensus_core_alpha")
source(file.path(S3_DIR, "factor_engine.R"))   # liq >= 2e8 (t-1) applied inside
stopifnot(exists("FACTORS"), nrow(FACTORS) > 0)
F3 <- copy(FACTORS)
F3[, ym := format(Date, "%Y-%m")]
s3_sel <- F3[, .SD[order(-Score)][1:min(25, .N)], by = ym]
s3_sel[, w_idx := as.Date(vapply(Date, function(d) as.character(month_end(d)), character(1)))]
s3_sel[, r_idx := as.Date(vapply(Date, function(d)
        as.character(month_end(seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2])), character(1)))]

# forward 1m returns: compound of daily Ret over calendar month m+1 (asset-level prep)
RET <- RAWDATA[, .(Date, Ticker, Ret)]
RET[, ym := format(Date, "%Y-%m")]
mret <- RET[!is.na(Ret), .(Ret_1m = prod(1 + Ret) - 1), by = .(Ticker, ym)]
s3_sel[, ym_fwd := format(r_idx, "%Y-%m")]
s3_sel <- merge(s3_sel, mret, by.x = c("Ticker","ym_fwd"), by.y = c("Ticker","ym"), all.x = TRUE)
n_na3 <- s3_sel[is.na(Ret_1m), .N]
s3_sel[is.na(Ret_1m), Ret_1m := 0]
s3_out <- s3_sel[, .(Date, w_idx, r_idx, Ticker, Score, Ret_1m)]
setorder(s3_out, Date, -Score)
write_parquet(s3_out, file.path(INT_DIR, "s3_sel.parquet"))
s3_grid <- unique(s3_out[, .(w_idx, r_idx)]); setorder(s3_grid, w_idx)
fwrite(s3_grid, file.path(INT_DIR, "s3_grid.csv"))
cat(sprintf("[prep] S3: %d rows | %d months | NA Ret_1m->0: %d | %s ~ %s\n",
            nrow(s3_out), nrow(s3_grid), n_na3,
            as.character(min(s3_out$Date)), as.character(max(s3_out$Date))))

# =============================================================================
# Daily return slices for cov estimation (union tickers, from 2000-09)
# =============================================================================
tk_s1b <- sort(unique(c(s1$Ticker, b_score$Ticker, b_sleeves$Ticker)))
ret_s1b <- RET[Ticker %in% tk_s1b & Date >= as.Date("2000-09-01"), .(Date, Ticker, Ret)]
write_parquet(ret_s1b, file.path(INT_DIR, "ret_s1b.parquet"))
tk_s3 <- sort(unique(s3_out$Ticker))
ret_s3 <- RET[Ticker %in% tk_s3 & Date >= as.Date("2001-09-01"), .(Date, Ticker, Ret)]
write_parquet(ret_s3, file.path(INT_DIR, "ret_s3.parquet"))
cat(sprintf("[prep] ret slices: s1b %d rows (%d tk) | s3 %d rows (%d tk)\n",
            nrow(ret_s1b), length(tk_s1b), nrow(ret_s3), length(tk_s3)))
cat("PREP_S1B_S3_OK\n")
