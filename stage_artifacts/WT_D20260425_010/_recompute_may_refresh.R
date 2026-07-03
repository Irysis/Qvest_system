## ============================================================================
## STR_1715 — 2026-05-01 sig_date alpha RE-COMPUTE on REFRESHED factor_db_202605
## (Jun-17 session; supersedes 06-08 degraded snapshot theta C04=0.2945)
##
## Recipe (canonical, validated against 05_Production 268m + factor_engine_proposal.R):
##   - Core sleeve (0.65): C01_SUE,C02_EPS_Chg_1m,C04_ESBR,C06_TP_Gap
##       theta = expanding-IC weights (mean IC over PAST, clip>=0, L1-normalize)
##       PIT-strict IC: Usable_Date < 2026-05-01 (fwd ret realized before decision)
##   - Defense sleeve (0.35): Q07_Earnings_Stability,M08_Residual_Mom,Q25_Ohlson_O
##       theta = EW (1/3 each) — recipe build_composite_ew, IC-independent
##   - score_eff = 0.65*z(Score_Core) + 0.35*z(Score_Defense)   [per-sig_date x-sec z]
##   - winsor 2.5 sigma on each factor Z before sleeve aggregation
##
## Data sourcing (sig_date 2026-05-01 -> canonical factor_db_202605):
##   - Core4 + Q07 + Q25  : factor_db_202605 (REFRESHED, Date=2026-05-31)  [restored]
##   - M08_Residual_Mom   : MISSING in 202605 partial rebuild (66 beta/regime factors dropped)
##                          -> sourced from factor_db_202604 (Date=2026-04-30), PIT-safe past
##                             momentum. FORCED DEVIATION, logged. (202606 = future, excluded)
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

SLEEVE_CORE    <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")
SLEEVE_DEFENSE <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
MAY_SIG  <- as.Date("2026-05-01")
PIT_REF  <- as.Date("2026-04-30")
W_CORE <- 0.65; W_DEF <- 0.35

winsor_z <- function(x, sigma = 2.5) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(x)
  pmax(pmin(x, m + sigma * s), m - sigma * s)
}

## ---- 1. Compute Core theta (expanding-IC, PIT-strict) ----------------------
ic <- as.data.table(read_parquet(file.path(ROOT, ".cache/factor_db/factor_ic_monthly.parquet")))
ic[, Date := as.Date(Date)]; ic[, Usable_Date := as.Date(Usable_Date)]
past_ic <- ic[Usable_Date < MAY_SIG & !is.na(IC) & Factor_Name %in% SLEEVE_CORE]
icm <- past_ic[, .(mean_IC = mean(IC, na.rm = TRUE), n = .N), by = Factor_Name]
theta_raw <- setNames(pmax(icm$mean_IC, 0), icm$Factor_Name)
theta_core <- setNames(rep(0, length(SLEEVE_CORE)), SLEEVE_CORE)
for (fn in names(theta_raw)) theta_core[fn] <- theta_raw[fn]
theta_core <- theta_core / sum(abs(theta_core))
theta_def  <- setNames(rep(1/length(SLEEVE_DEFENSE), length(SLEEVE_DEFENSE)), SLEEVE_DEFENSE)

cat("[theta] Core (expanding-IC, PIT-strict Usable_Date<2026-05-01):\n")
print(round(theta_core, 4))
cat(sprintf("  (max signal Date used = %s)\n", as.character(max(past_ic$Date))))
cat("[theta] Defense (EW 1/3):\n"); print(round(theta_def, 4))

## ---- 2. Load refreshed May Z (Core4 + Q07 + Q25 from 202605) ---------------
f5 <- as.data.table(read_parquet(file.path(ROOT, ".cache/factor_db/factor_db_202605.parquet"),
  col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))
need_05 <- c(SLEEVE_CORE, "Q07_Earnings_Stability", "Q25_Ohlson_O")
f5 <- f5[Factor_Name %in% need_05 & Coverage == TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
f5[, sig_date := MAY_SIG]
cat(sprintf("\n[202605] loaded %d rows | factors: %s\n", nrow(f5),
            paste(sort(unique(f5$Factor_Name)), collapse = ",")))

## ---- 3. M08 from 202604 (PIT-safe; 202605 lacks it) ------------------------
f4 <- as.data.table(read_parquet(file.path(ROOT, ".cache/factor_db/factor_db_202604.parquet"),
  col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))
m08 <- f4[Factor_Name == "M08_Residual_Mom" & Coverage == TRUE & !is.na(Z_Score),
          .(Ticker, Factor_Name, Z_Score)]
m08[, sig_date := MAY_SIG]
cat(sprintf("[202604] M08_Residual_Mom: %d rows (FORCED — Apr-end PIT-safe)\n", nrow(m08)))

fdb <- rbind(f5, m08)

## ---- 4. Direction alignment (C13/C14, expanding-IC sign) -------------------
fdb_al <- align_factor_direction(fdb, .load_registry(), sig_date = MAY_SIG, min_ic_months = 12L)
if ("Z_Score_Aligned" %in% names(fdb_al)) {
  fdb_al[, Z_Score := Z_Score_Aligned]; fdb_al[, Z_Score_Aligned := NULL]
}
fw <- dcast(fdb_al, sig_date + Ticker ~ Factor_Name, value.var = "Z_Score", fill = NA_real_)

## ---- 5. Liquidity (C10, t-1 AvgTV20 >= 2e8) --------------------------------
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date", "Ticker", "Close", "Vol")))
raw[, Date := as.Date(Date)]
raw[, TV := Close * Vol]
raw[order(Date), AvgTV20_t := frollmean(TV, 20L, align = "right"), by = Ticker]
raw[order(Date), AvgTV20 := shift(AvgTV20_t, 1L, type = "lag"), by = Ticker]
pit_close <- raw[Date <= PIT_REF, max(Date)]
liq <- raw[Date == pit_close & !is.na(AvgTV20) & AvgTV20 >= 2e8, .(Ticker)]
cat(sprintf("\n[liq] PIT close=%s | liquid tickers=%d\n", as.character(pit_close), nrow(liq)))
fw <- merge(fw, liq, by = "Ticker")

## ---- 6. Universe (K200 u KQ150, latest membership <= 2026-04-30) -----------
k200  <- as.data.table(read_parquet(file.path(ROOT, ".cache/universe_support/us_k200.parquet")))
kq150 <- as.data.table(read_parquet(file.path(ROOT, ".cache/universe_support/us_kq150.parquet")))
k200[, Date := as.Date(Date)]; kq150[, Date := as.Date(Date)]
k2d <- k200[Date <= PIT_REF, max(Date)]; kqd <- kq150[Date <= PIT_REF, max(Date)]
uni <- unique(c(k200[Date == k2d & K200 == 1, Ticker], kq150[Date == kqd & KQ150 == 1, Ticker]))
fw <- fw[Ticker %in% uni]
cat(sprintf("[universe] k200=%s kq150=%s | union=%d | panel after=%d\n",
            as.character(k2d), as.character(kqd), length(uni), nrow(fw)))

## ---- 7. Sleeve composite (winsor + IC weights) -----------------------------
agg <- function(df, facs, w) {
  fac <- intersect(names(w), facs); fac <- intersect(fac, names(df))
  W <- as.numeric(w[fac]); W <- W / sum(W)
  X <- as.matrix(df[, ..fac]); X <- apply(X, 2, winsor_z, sigma = 2.5)
  X[is.na(X)] <- 0
  as.numeric(X %*% W)
}
core_facs_present <- intersect(SLEEVE_CORE, names(fw))
def_facs_present  <- intersect(SLEEVE_DEFENSE, names(fw))
cat(sprintf("\n[sleeve] core present=%s | defense present=%s\n",
            paste(core_facs_present, collapse=","), paste(def_facs_present, collapse=",")))
fw[, Score_Core := agg(.SD, core_facs_present, theta_core)]
fw[, Score_Defense := agg(.SD, def_facs_present, theta_def)]
# per-sig_date cross-sectional z
zc <- function(x){ m<-mean(x,na.rm=T); s<-sd(x,na.rm=T); if(is.na(s)||s<1e-10) x-m else (x-m)/s }
fw[, Score_Core_z := zc(Score_Core)]
fw[, Score_Defense_z := zc(Score_Defense)]
fw[, score_eff := W_CORE * Score_Core_z + W_DEF * Score_Defense_z]

## ---- 8. Assemble alpha_scores May row to canonical schema ------------------
may_alpha <- fw[, .(
  Date = sig_date, Ticker,
  score_eff, score_core_z = Score_Core_z, score_defense_z = Score_Defense_z,
  Ret_1m = NA_real_, regime_state = "CAUTION",
  theta_core = toJSON(as.list(round(theta_core, 4)), auto_unbox = TRUE),
  theta_defense = toJSON(as.list(round(theta_def, 4)), auto_unbox = TRUE)
)]
setkey(may_alpha, Date, Ticker)
cat(sprintf("\n[may_alpha] %d rows | non-NA score_eff=%d\n", nrow(may_alpha), sum(!is.na(may_alpha$score_eff))))
cat("Top 15 by score_eff:\n")
print(may_alpha[order(-score_eff)][1:15, .(Ticker, score_eff=round(score_eff,4),
     core_z=round(score_core_z,4), def_z=round(score_defense_z,4))])

## ---- 9. Splice into alpha_scores.parquet (replace 2026-05-01 row) ----------
ap_path <- file.path(ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
existing <- as.data.table(read_parquet(ap_path))
existing[, Date := as.Date(Date)]
existing[, theta_core := as.character(theta_core)]
existing[, theta_defense := as.character(theta_defense)]
# back up degraded version once
bk <- file.path(ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores_PRE_refresh_0608snap.parquet")
if (!file.exists(bk)) { write_parquet(existing, bk); cat(sprintf("[backup] %s\n", bk)) }
kept <- existing[Date != MAY_SIG]
may_alpha[, theta_core := as.character(theta_core)]
may_alpha[, theta_defense := as.character(theta_defense)]
merged <- rbind(kept, may_alpha, use.names = TRUE, fill = TRUE)
setkey(merged, Date, Ticker)
write_parquet(merged, ap_path)
cat(sprintf("[write] alpha_scores.parquet updated (%d rows, %s ~ %s)\n",
            nrow(merged), as.character(min(merged$Date)), as.character(max(merged$Date))))

saveRDS(list(theta_core = theta_core, theta_def = theta_def,
             n_may = nrow(may_alpha), top = may_alpha[order(-score_eff)][1:25]),
        file.path(ROOT, "stage_artifacts/WT_D20260425_010/_may_recompute_summary.rds"))
cat("\n=== May recompute DONE ===\n")
