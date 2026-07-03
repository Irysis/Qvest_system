# pd004_run.R — PD004: formal Harvey 5-spec factor regression + AX-001 v2 conditional
# defense evaluation of the R05 layer (Composition Search Cycle 2, Track P).
#
# Inputs (all read-only):
#   data/period_returns_layer5_copy.csv  - verbatim Read-tool copy of production
#     05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/
#     04_backtest_results/period_returns_layer5.csv (267 labels 2004-02..2026-04)
#   .cache/kr_factor_returns_v2.parquet  - MKT/SMB/HML/WML/RMW/CMA/RF monthly
#   04_Research/composition_search/cycle1b_trackV/inputs/bm_monthly.csv
#     - KOSPI200 BM daily compounded over (prev_me, me], calendar-month keyed
#
# Conventions enforced:
#   - realized_ym label offset (02_Infrastructure/docs/period_returns_realized_ym_convention.md):
#     book label m = calendar month m-1. Join rule: cal_ym = label_ym - 1 month.
#   - NW lag-3 Bartlett, no small-sample adjustment (contract .nw_t_mean parity;
#     multi-factor via sandwich::NeweyWest(lag=3, prewhite=FALSE, adjust=FALSE)).
#   - Data boundary: calendar months <= 2026-04 only (rawdata 2026-05-01+ contaminated).
#     Book last realized calendar month = 2026-03 (label 2026-04) -> inside boundary.
#   - No self-synthesis for performance stats: PerformanceAnalytics standard functions
#     (Return.annualized / StdDev.annualized / maxDrawdown). lm() for regressions.
#
# Output: pd004_regressions.json + pd004_regressions.md (same dir).

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(sandwich); library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TP   <- file.path(ROOT, "04_Research/composition_search/cycle2_trackP")
CUT_YM <- "2026-04"   # data boundary (calendar)

# ---------- 1. Load book copy + transcription checksum vs production audit ----------
bk <- fread(file.path(TP, "data/period_returns_layer5_copy.csv"))
stopifnot(nrow(bk) == 267L)
bk[, anchor_date := as.Date(anchor_date)]
setorder(bk, anchor_date)

mk_xts <- function(v, lab) xts(v, order.by = as.Date(paste0(lab, "-01")))
ann_sr <- function(x) as.numeric(Return.annualized(x, scale = 12)) /
                      as.numeric(StdDev.annualized(x, scale = 12))

# audit window identified by grid-search (_win_diag.R): the LAST 255 labels
# (2005-02..2026-04). Convention = geometric CAGR (Return.annualized) / StdDev.annualized
# / their ratio. Reproduces audit.json L4 0.3868/0.2212/1.7486/MDD 0.2481 and
# V2 0.4150/1.9536 exactly. First 12 labels (2004-02..2005-01) = pre-window ramp
# (overlays inactive), retained in file but outside the audited book window.
w255 <- bk[(.N - 254):.N]
stopifnot(w255$realized_ym[1] == "2005-02", w255$realized_ym[255] == "2026-04")
x_l4  <- mk_xts(w255$ret_L4_baseline, w255$realized_ym)
x_v2  <- mk_xts(w255$ret_L5_V2,       w255$realized_ym)
chk <- data.table(
  metric   = c("L4_CAGR", "L4_SR", "L4_MDD", "V2_CAGR", "V2_SR", "V2_MDD"),
  computed = c(as.numeric(Return.annualized(x_l4, scale = 12)), ann_sr(x_l4),
               as.numeric(maxDrawdown(x_l4)),
               as.numeric(Return.annualized(x_v2, scale = 12)), ann_sr(x_v2),
               as.numeric(maxDrawdown(x_v2))),
  audit    = c(0.3868, 1.7486, 0.2481, 0.4150, 1.9536, 0.2481))
chk[, diff := computed - audit]
cat("== transcription checksum (audit 255m window = labels 2005-02..2026-04, geometric) ==\n")
print(chk, digits = 5)
stopifnot(all(abs(chk$diff) < 0.005))
cat("checksum PASS (copy faithful to production audit baselines)\n\n")

# ---------- 2. Calendar alignment (label m -> calendar m-1) ----------
bk[, cal_ym := format(as.Date(paste0(realized_ym, "-01")) - 1L, "%Y-%m")]
book <- bk[, .(cal_ym, label_ym = realized_ym, regime,
               ret_orig, ret_L4 = ret_L4_baseline, ret_V2 = ret_L5_V2)]

bm <- fread(file.path(ROOT, "04_Research/composition_search/cycle1b_trackV/inputs/bm_monthly.csv"))
bm[, ym := format(as.Date(Date), "%Y-%m")]
bm <- bm[ym <= CUT_YM, .(cal_ym = ym, bm_ret = BM_Ret_m)]

fac <- as.data.table(read_parquet(file.path(ROOT, ".cache/kr_factor_returns_v2.parquet")))
fac[, ym := format(as.Date(Date), "%Y-%m")]
fac <- fac[ym <= CUT_YM]
first_ok <- sapply(c("MKT","SMB","HML","WML","RMW","CMA"),
                   function(f) as.character(min(fac[is.finite(get(f)), ym])))
cat("== factor first available ym ==\n"); print(first_ok)
last_fac_ym <- max(fac$ym)
cat("last factor ym:", last_fac_ym, "(Date", as.character(max(as.Date(fac$Date))), ")\n\n")

M <- merge(book, bm, by = "cal_ym")
M <- merge(M, fac[, .(cal_ym = ym, MKT, SMB, HML, WML, RMW, CMA)], by = "cal_ym")
setorder(M, cal_ym)
M <- M[cal_ym <= CUT_YM]
M[, act_orig := ret_orig - bm_ret]
M[, act_V2   := ret_V2   - bm_ret]

cat("== alignment sanity ==\n")
cat(sprintf("merged n=%d  cal range %s..%s\n", nrow(M), min(M$cal_ym), max(M$cal_ym)))
cat(sprintf("cor(book V2, bm)        = %+.4f  (offset report corrected ~ +0.57)\n",
            cor(M$ret_V2, M$bm_ret)))
cat(sprintf("cor(MKT, bm)            = %+.4f  (factor-vs-benchmark convention check)\n",
            cor(M$MKT, M$bm_ret, use = "complete.obs")))
# misalignment control: shift book +1 (i.e., undo correction) should collapse cor
M[, ret_V2_wrong := shift(ret_V2, 1L, type = "lead")]
cat(sprintf("cor(book V2 unshifted, bm) [control, expect ~0] = %+.4f\n\n",
            cor(M$ret_V2_wrong, M$bm_ret, use = "complete.obs")))

# ---------- 3. NW lag-3 machinery ----------
# contract-grade intercept-only NW t (verbatim pattern from
# 02_Infrastructure/contracts/backtest_result_contract.R::.nw_t_mean)
nw_t_mean <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    g <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    s <- s + 2 * w * g
  }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s / n)
}

SPECS <- list(
  CAPM     = c("MKT"),
  Carhart3 = c("MKT","SMB","HML"),            # = FF3 (mission naming)
  Carhart4 = c("MKT","SMB","HML","WML"),
  FF5      = c("MKT","SMB","HML","RMW","CMA"),
  FF6      = c("MKT","SMB","HML","RMW","CMA","WML"))

run_specs <- function(dt, yvar, tag) {
  out <- list()
  for (nm in names(SPECS)) {
    vars <- SPECS[[nm]]
    sub  <- dt[complete.cases(dt[, c(yvar, vars), with = FALSE])]
    f    <- as.formula(paste(yvar, "~", paste(vars, collapse = " + ")))
    fit  <- lm(f, data = sub)
    V    <- sandwich::NeweyWest(fit, lag = 3L, prewhite = FALSE, adjust = FALSE)
    a    <- unname(coef(fit)["(Intercept)"])
    se   <- sqrt(V["(Intercept)","(Intercept)"])
    tv   <- a / se
    pv   <- 2 * pt(-abs(tv), df = nobs(fit) - length(coef(fit)))
    bet  <- as.list(round(coef(fit)[vars], 4))
    out[[nm]] <- c(list(series = tag, spec = nm, n = nobs(fit),
                        alpha_monthly = round(a, 5), alpha_t_nw3 = round(tv, 3),
                        alpha_p = signif(pv, 3), adj_r2 = round(summary(fit)$adj.r.squared, 4)),
                   setNames(bet, paste0("b_", vars)))
  }
  out
}

cat("== 5-spec regressions: dependent = net active (book - BM), calendar-aligned ==\n")
resA <- list(orig = run_specs(M, "act_orig", "ret_orig_vanilla"),
             V2   = run_specs(M, "act_V2",   "ret_L5_V2_overlaid"))
tabA <- rbindlist(lapply(resA, function(s) rbindlist(lapply(s, as.data.table), fill = TRUE)),
                  fill = TRUE)
print(tabA, digits = 4)

# robustness: drop last calendar month if factor month possibly partial (Date gap < 15d)
fd <- sort(as.Date(fac$Date)); gap_last <- as.integer(diff(tail(fd, 2)))
Mrob <- M[cal_ym < last_fac_ym]
cat(sprintf("\nlast factor row gap = %d days -> robustness sample excl %s (n=%d)\n",
            gap_last, last_fac_ym, nrow(Mrob)))
resB <- list(orig = run_specs(Mrob, "act_orig", "ret_orig_vanilla_excl_last"),
             V2   = run_specs(Mrob, "act_V2",   "ret_L5_V2_excl_last"))
tabB <- rbindlist(lapply(resB, function(s) rbindlist(lapply(s, as.data.table), fill = TRUE)),
                  fill = TRUE)
cat("\n== robustness (excl possibly-partial last factor month) ==\n")
print(tabB[, .(series, spec, n, alpha_monthly, alpha_t_nw3, adj_r2)], digits = 4)

# house PORT_t (intercept-only NW lag-3 on net active) for both series
port_t <- data.table(
  series = c("ret_orig_vanilla", "ret_L5_V2_overlaid"),
  n      = nrow(M),
  port_t_nw_lag3 = c(round(nw_t_mean(M$act_orig), 3), round(nw_t_mean(M$act_V2), 3)))
cat("\n== house PORT_t (intercept-only, contract .nw_t_mean parity) ==\n")
print(port_t)

# ---------- 4. AX-001 v2 conditional defense evaluation (R05 layer = V2 - L4) ----------
# Layer diff is label-aligned (same row) -> offset-invariant.
bk[, d_R05 := ret_L5_V2 - ret_L4_baseline]
bk[, bad := regime %chin% c("CRISIS", "CAUTION")]

reg_stats <- bk[, .(n = .N, mean_d = mean(d_R05), sd_d = sd(d_R05),
                    hit_pos = mean(d_R05 > 0), mean_book_L4 = mean(ret_L4_baseline)),
                by = regime][order(-n)]
cat("\n== R05 layer (V2 - L4) by book regime, 267 labels ==\n")
print(reg_stats, digits = 4)

crisis_d  <- bk[regime == "CRISIS",  d_R05]
caution_d <- bk[regime == "CAUTION", d_R05]
bad_d     <- bk[bad == TRUE,  d_R05]
norm_d    <- bk[bad == FALSE, d_R05]
t_plain <- function(x) if (length(x) > 1 && sd(x) > 0) mean(x)/sd(x)*sqrt(length(x)) else NA_real_

# full-series MDD (label-invariant)
x_orig_f <- mk_xts(bk$ret_orig,        bk$realized_ym)
x_l4_f   <- mk_xts(bk$ret_L4_baseline, bk$realized_ym)
x_v2_f   <- mk_xts(bk$ret_L5_V2,       bk$realized_ym)
mdd <- c(orig = as.numeric(maxDrawdown(x_orig_f)),
         L4   = as.numeric(maxDrawdown(x_l4_f)),
         V2   = as.numeric(maxDrawdown(x_v2_f)))
sr_full <- c(orig = ann_sr(x_orig_f), L4 = ann_sr(x_l4_f), V2 = ann_sr(x_v2_f))

# BM-bad months (calendar-aligned, bm < -5%) as regime-free robustness
Mb <- merge(book, bm, by = "cal_ym")
Mb[, d_R05 := ret_V2 - ret_L4]
bm_bad <- Mb[bm_ret < -0.05]
cat(sprintf("\nBM-bad months (bm < -5%%, calendar): n=%d mean_d=%+.4f hit=%.2f\n",
            nrow(bm_bad), mean(bm_bad$d_R05), mean(bm_bad$d_R05 > 0)))

ax <- list(
  layer = "R05 (V2) on L4 baseline (AR-on-M4)",
  n_labels = nrow(bk),
  crisis_alpha = list(
    n = length(crisis_d), mean_monthly = round(mean(crisis_d), 5),
    t_plain = round(t_plain(crisis_d), 2), all_positive = all(crisis_d > 0),
    months = bk[regime == "CRISIS", paste(realized_ym, collapse = ", ")]),
  crisis_caution_alpha = list(
    n = length(bad_d), mean_monthly = round(mean(bad_d), 5),
    t_plain = round(t_plain(bad_d), 2), hit_pos = round(mean(bad_d > 0), 3)),
  mdd_vs_core = list(
    mdd_orig = round(mdd["orig"], 4), mdd_L4 = round(mdd["L4"], 4),
    mdd_V2 = round(mdd["V2"], 4),
    delta_vs_L4_pp = round((mdd["L4"] - mdd["V2"]) * 100, 2),
    delta_vs_orig_pp = round((mdd["orig"] - mdd["V2"]) * 100, 2)),
  bad_normal_ratio = list(
    mean_d_bad = round(mean(bad_d), 5), mean_d_normal = round(mean(norm_d), 5),
    note = "IC undefined for pure overlay layer; return-contribution ratio used (adapted, honest label)",
    ratio = if (mean(norm_d) != 0) round(mean(bad_d) / abs(mean(norm_d)), 1) else Inf),
  bm_bad_robustness = list(n = nrow(bm_bad), mean_d = round(mean(bm_bad$d_R05), 5),
                           hit_pos = round(mean(bm_bad$d_R05 > 0), 3)),
  full_period_sr_context = lapply(as.list(round(sr_full, 4)), identity)
)
cat("\n== AX-001 v2 components ==\n"); str(ax, max.level = 2)

# component verdicts
c1 <- ax$crisis_alpha$mean_monthly > 0 && ax$crisis_alpha$all_positive
c2 <- (mdd["L4"] - mdd["V2"]) > 0.005          # MDD relief vs Core >= 0.5pp
c3 <- mean(bad_d) > 0 && mean(bad_d) > mean(norm_d)
verdict <- list(
  crisis_alpha_positive = c1,
  mdd_relief_vs_core    = c2,
  bad_normal_favorable  = c3,
  components_passed     = sum(c(c1, c2, c3)),
  overall = if (c1 && c3 && c2) "PASS" else if (c1 && c3) "CONDITIONAL_PARTIAL (2/3: crisis+bad/normal PASS, MDD relief FAIL)" else "FAIL")
cat("\n== AX-001 v2 verdict ==\n"); str(verdict)

# ---------- 5. Persist ----------
out <- list(
  task = "PD004 - formal Harvey 5-spec regression + AX-001 v2 conditional defense (R05 layer)",
  date = "2026-06-12", agent = "trackP_pd004",
  metric_type = "backtested",
  labels = list(
    book_source = "05_Production/.../04_backtest_results/period_returns_layer5.csv (Read-tool verbatim copy, checksum vs audit.json PASS)",
    cost_model  = "v2.3_kr_retail_15bps flat per production audit.json (legacy label; book TO 5.57x/yr where flat ~ accurate per B0; NOT v2.4 delta)",
    regression_role = "diagnostic (factor-model alpha attribution on realized net active returns)",
    alignment   = "realized_ym offset corrected: book label m+1 <-> calendar m (convention SOT)",
    data_boundary = "calendar <= 2026-04 cut applied; book last realized calendar month = 2026-03 (inside boundary)",
    nw = "Newey-West lag-3 Bartlett, no small-sample adjustment (contract parity)"),
  transcription_checksum = chk,
  factor_first_available = as.list(first_ok),
  alignment_sanity = list(
    n = nrow(M), cal_range = paste(min(M$cal_ym), max(M$cal_ym), sep = ".."),
    cor_bookV2_bm = round(cor(M$ret_V2, M$bm_ret), 4),
    cor_MKT_bm = round(cor(M$MKT, M$bm_ret, use = "complete.obs"), 4),
    cor_unshifted_control = round(cor(M$ret_V2_wrong, M$bm_ret, use = "complete.obs"), 4)),
  spec_table_primary = tabA,
  spec_table_robust_excl_last_factor_month = tabB,
  last_factor_month_caveat = sprintf(
    "last kr_factor_returns_v2 row dated %s with %d-day gap from prior row (possibly partial month); robustness table excludes it",
    as.character(max(as.Date(fac$Date))), gap_last),
  port_t_house = port_t,
  ax001_v2 = list(components = ax, verdict = verdict),
  regime_layer_stats = reg_stats
)
write_json(out, file.path(TP, "pd004_regressions.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 6, dataframe = "rows")
cat("\nsaved:", file.path(TP, "pd004_regressions.json"), "\n")
cat("DONE_PD004_R\n")
