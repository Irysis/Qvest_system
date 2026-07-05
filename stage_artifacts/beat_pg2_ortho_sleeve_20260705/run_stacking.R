#!/usr/bin/env Rscript
# run_stacking.R — multi-sleeve stacking: score_eff + ortho sleeve → book IR vs PG2
#   book = blend_w*z(score_eff) + (1-blend_w)*z(sleeve)  [NOTE harness eval_book uses blend_w on SLEEVE]
#   task convention: blend_w*score_eff_z + (1-blend_w)*sleeve_z  → so pass sleeve_weight = 1-blend_w to eval_book.
#   marginal = book_IR - PG2_recon_IR (same pinned cache, recon-vs-recon). paired NW-t on active diff. oos v2.
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest) })
setDTthreads(1)
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("stage_artifacts/beat_pg2_ortho_sleeve_20260705/harness.R")
OUTDIR <- "stage_artifacts/beat_pg2_ortho_sleeve_20260705"

# ---- PG2 baseline (recon) ----
bl <- readRDS(file.path(OUTDIR, "pg2_baseline.rds"))
PG2_IR <- bl$book_ir
pg2_m <- as.data.table(bl$monthly)[, .(ym, eval_date, pg2_net = ret_net, bm = bm_ret, pg2_active = active)]
cat(sprintf("[stack] PG2 recon book_ir = %.4f | n = %d\n", PG2_IR, nrow(pg2_m)))

# ---- base score (STR_1715 score_eff) ----
BASE <- as.data.table(read_parquet(STR1715_ASP))

# ---- candidate sleeve loaders ----
FDB_DIR2 <- ".cache/factor_db"
load_fdb_factor <- function(fn) {
  files <- sort(list.files(FDB_DIR2, pattern = "factor_db_\\d{6}\\.parquet$", full.names = TRUE))
  files <- files[as.integer(gsub(".*factor_db_(\\d{6})\\.parquet$","\\1",files)) >= 200501]
  L <- rbindlist(lapply(files, function(f){
    d <- tryCatch(as.data.table(read_parquet(f, col_select=c("Date","Ticker","Factor_Name","Z_Score"))),
                  error=function(e) NULL)
    if (is.null(d)) return(NULL)
    d[Factor_Name == fn, .(Date, Ticker, score = Z_Score)]
  }), use.names=TRUE)
  L[!is.na(score)]
}
load_xattn <- function() {
  xa <- as.data.table(read_parquet("stage_artifacts/WT_D20260705_001/alpha_scores.parquet"))
  xa[!is.na(score), .(Date, Ticker, score)]
}

CANDS <- list(
  V15_NetDebt_Adj_EP = function() load_fdb_factor("V15_NetDebt_Adj_EP"),
  M27_Analyst_Rev_Mom = function() load_fdb_factor("M27_Analyst_Rev_Mom"),
  C02_EPS_Chg_1m      = function() load_fdb_factor("C02_EPS_Chg_1m"),
  XATTN_score         = function() load_xattn()
)
BLENDS <- c(0.85, 0.70, 0.55)   # weight on score_eff (base); sleeve weight = 1-blend

# paired NW-t on (book_active - pg2_active)
paired_nw_t <- function(diff) {
  diff <- diff[is.finite(diff)]
  if (length(diff) < 12) return(NA_real_)
  fit <- lm(diff ~ 1)
  se <- sqrt(NeweyWest(fit, lag = 3, prewhite = FALSE)[1,1])
  coef(fit)[1] / se
}
# oos_retention v2: anchored 3-split {55/65/75} median of (OOS active-SR / IS active-SR)
oos_v2 <- function(active) {
  n <- length(active); if (n < 40) return(NA_real_)
  sr <- function(x) if (length(x) < 6 || sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
  rr <- sapply(c(0.55,0.65,0.75), function(f){
    k <- floor(n*f); is_sr <- sr(active[1:k]); oos_sr <- sr(active[(k+1):n])
    if (is.na(is_sr)||is.na(oos_sr)||is_sr<=0) return(NA_real_)
    oos_sr/is_sr
  })
  median(rr, na.rm = TRUE)
}
mdd_from_net <- function(r) {
  nav <- cumprod(1+r); dd <- nav/cummax(nav)-1; -min(dd)
}
calmar_from_net <- function(r){
  n <- length(r); cagr <- prod(1+r)^(12/n)-1; m <- mdd_from_net(r); if (m<=0) return(NA_real_); cagr/m
}

RES <- list()
for (cn in names(CANDS)) {
  cat(sprintf("\n[stack] === candidate %s ===\n", cn))
  sleeve <- tryCatch(CANDS[[cn]](), error=function(e){cat("  LOAD ERR:",conditionMessage(e),"\n");NULL})
  if (is.null(sleeve) || nrow(sleeve)==0) { cat("  skip (no data)\n"); next }
  cat(sprintf("  sleeve rows=%s dates=%d range %s~%s\n", format(nrow(sleeve),big.mark=","),
              length(unique(sleeve$Date)), as.character(min(sleeve$Date)), as.character(max(sleeve$Date))))
  best <- NULL
  for (bw in BLENDS) {
    # eval_book blend_w is weight on SLEEVE. task wants blend_w on base → sleeve weight = 1-bw_base.
    sleeve_w <- 1 - bw
    ev <- tryCatch(eval_book(BASE, sleeve_z = sleeve, blend_w = sleeve_w,
                             base_col = "score_eff", sleeve_col = "score"),
                   error=function(e){cat("  EVAL ERR bw=",bw,":",conditionMessage(e),"\n");NULL})
    if (is.null(ev)) next
    X <- as.data.table(ev$monthly)[, .(ym, eval_date, book_net = ret_net, bm = bm_ret, book_active = active)]
    J <- merge(X, pg2_m[, .(ym, pg2_active, pg2_net)], by="ym")
    setorder(J, eval_date)
    dIR <- ev$book_ir - PG2_IR
    tnw <- paired_nw_t(J$book_active - J$pg2_active)
    oosr <- oos_v2(J$book_active)
    mdd <- mdd_from_net(J$book_net); calm <- calmar_from_net(J$book_net)
    # candidate own PORT_t via canonical (the stacked book as scores? no — book PORT_t = NW-t of book_active vs 0)
    fit0 <- lm(J$book_active ~ 1); se0 <- sqrt(NeweyWest(fit0, lag=3, prewhite=FALSE)[1,1])
    port_t <- coef(fit0)[1]/se0
    row <- list(code=cn, blend_w_base=bw, sleeve_w=sleeve_w,
                book_ir=round(ev$book_ir,4), pg2_ir=round(PG2_IR,4), dIR=round(dIR,4),
                paired_nw_t=round(as.numeric(tnw),3), book_port_t=round(as.numeric(port_t),3),
                book_gross_sr=round(ev$base_gross_sr,3), book_net_sr=round(sr_ann(J$book_net),3),
                mdd=round(mdd,4), calmar=round(as.numeric(calm),3), oos_retention_v2=round(as.numeric(oosr),3),
                n=nrow(J))
    cat(sprintf("  bw_base=%.2f: book_IR=%.4f dIR=%+.4f paired_NW_t=%+.2f book_PORT_t=%+.2f oos=%.2f calmar=%.2f mdd=%.3f\n",
                bw, ev$book_ir, dIR, as.numeric(tnw), as.numeric(port_t), as.numeric(oosr), as.numeric(calm), mdd))
    # write per-candidate×blend json + monthly series
    wpath <- file.path(OUTDIR, sprintf("multisleeve_%s_%02d.json", cn, round(bw*100)))
    write_json(row, wpath, auto_unbox=TRUE, pretty=TRUE, digits=6)
    spath <- file.path(OUTDIR, sprintf("multisleeve_%s_%02d_series.csv", cn, round(bw*100)))
    fwrite(J[, .(ym, eval_date, book_net, book_active, pg2_net, pg2_active, bm)], spath)
    if (is.null(best) || dIR > best$dIR) best <- row
  }
  RES[[cn]] <- best
}

SUM <- rbindlist(lapply(RES, as.data.table), use.names=TRUE, fill=TRUE)
setorder(SUM, -dIR)
fwrite(SUM, file.path(OUTDIR, "stacking_best_summary.csv"))
cat("\n[stack] ===== BEST blend per candidate (by dIR) =====\n")
print(SUM[, .(code, blend_w_base, book_ir, dIR, paired_nw_t, book_port_t, oos_retention_v2, calmar)])
cat(sprintf("\n[stack] PG2 recon IR = %.4f. success bar: dIR>=0.05 AND paired_nw_t>=2.0\n", PG2_IR))
pass <- SUM[dIR >= 0.05 & paired_nw_t >= 2.0]
cat(sprintf("[stack] candidates PASSING success bar: %d\n", nrow(pass)))
if (nrow(pass)>0) print(pass[, .(code, blend_w_base, book_ir, dIR, paired_nw_t)])
saveRDS(RES, file.path(OUTDIR, "stacking_results.rds"))
cat("[stack] DONE\n")
