# ===========================================================
# Architect KR FF5/Carhart-4 regression for V2 returns
# WT-H20260513_001 — AX-008 3rd Source — P2 prerequisite
#
# Construct KR factors using SAME admit precedent method
# (WT-P20260504_001 harvey_5spec_test.R lines 1~290):
#   Mkt   = mean(BM_Ret)
#   SMB   = small(Size median) - big monthly EW
#   HML   = V01_BM Z-score top-30% - bottom-30%
#   UMD   = 12-1m momentum top-30% - bottom-30%
#   RMW   = Q02_ROE Z-score top-30% - bottom-30%
#   CMA   = Q07_Earnings_Stability Z-score top-30% - bottom-30%
#
# Use V2 returns from architect_independent_results.rds (Phase 7 NAV)
# ===========================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(sandwich)
  library(lmtest)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(base_dir)

cat("============================================================\n")
cat("ARCHITECT KR FF5/CARHART-4 REGRESSION — V2 ret_series\n")
cat("============================================================\n\n")

# Load Architect V2 returns from saved RDS
master <- readRDS("qepm/mailbox/worktask/WT-H20260513_001/architect_master_table.rds")
setDT(master)

# Compute V2 ret_overlay (cost_v2 convention: 0.0015 Δw)
master[, dw_V2 := c(NA, abs(diff(w_final_V2)))]
master[, cost_V2 := ifelse(is.na(dw_V2), 0, dw_V2 * 0.0015)]
master[, ret_V2 := w_final_V2 * ret_net - cost_V2]

# Also L4 baseline
master[, dw_L4 := c(NA, abs(diff(w_final_L4)))]
master[, cost_L4 := ifelse(is.na(dw_L4), 0, dw_L4 * 0.0015)]
master[, ret_L4 := w_final_L4 * ret_net - cost_L4]

# Subset effective rows (non-NA)
dt_ret <- master[!is.na(ret_V2), .(ym, date, ret_V2, ret_L4)]
cat(sprintf("V2 returns rows after NA drop: %d (date range %s ~ %s)\n",
            nrow(dt_ret), as.character(min(dt_ret$date)), as.character(max(dt_ret$date))))

# ============================================================
# Load RAWDATA + build factors
# ============================================================
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2003-01-01") & Date <= as.Date("2026-05-04")]
raw[, ym := format(Date, "%Y-%m")]
raw <- raw[!is.na(Ret) & is.finite(Ret) & abs(Ret) < 0.5]
raw <- raw[!is.na(Size) & Size > 0]

cat("RAWDATA: ", nrow(raw), " rows after filter\n")

# Mkt = mean(BM_Ret) daily → monthly  (Carhart standard: daily comp → monthly)
mkt_daily <- raw[, .(BM = first(BM_Ret)), by = .(Date, ym)]
mkt_dt <- mkt_daily[, .(Mkt = prod(1 + BM, na.rm = TRUE) - 1), by = ym]
cat("Mkt monthly range:", round(range(mkt_dt$Mkt, na.rm=TRUE), 4), "\n")

# Monthly returns per ticker
ret_monthly <- raw[, .(ret_m = prod(1 + Ret) - 1), by = .(ym, Ticker)]

# SMB: size median split monthly EW
size_classes <- raw[, {
  size_med <- median(Size, na.rm = TRUE)
  .(Ticker = unique(Ticker), size_class = ifelse(Size[1] <= size_med, "S", "B"))
}, by = .(ym, Ticker)]
# Simpler: take first Size obs per (ym, Ticker)
size_classes <- raw[, .(Size_first = first(Size)), by = .(ym, Ticker)]
size_classes[, size_med := median(Size_first, na.rm=TRUE), by = ym]
size_classes[, size_class := ifelse(Size_first <= size_med, "S", "B")]
ret_with_size <- ret_monthly[size_classes, on = c("ym","Ticker"), nomatch=0]
smb_dt <- ret_with_size[, .(ret_class = mean(ret_m, na.rm=TRUE)),
                         by = .(ym, size_class)]
smb_wide <- dcast(smb_dt, ym ~ size_class, value.var = "ret_class")
smb_wide[, SMB := S - B]
cat("SMB rows:", nrow(smb_wide), "\n")

# UMD: 12-1m momentum at end of ym applied next ym
ret_monthly_sort <- copy(ret_monthly)
setorder(ret_monthly_sort, Ticker, ym)
ret_monthly_sort[, lret_m := log(1 + pmax(ret_m, -0.99))]
ret_monthly_sort[, lret_lag1 := shift(lret_m, 1, type = "lag"), by = Ticker]
ret_monthly_sort[, lret_sum_11_2 := frollsum(lret_lag1, 11,
                                              align = "right", fill = NA_real_),
                  by = Ticker]
ret_monthly_sort[, mom_12_1 := exp(lret_sum_11_2) - 1]

mom_class_dt <- ret_monthly_sort[!is.na(mom_12_1), {
  q_lo <- quantile(mom_12_1, 0.30, na.rm = TRUE)
  q_hi <- quantile(mom_12_1, 0.70, na.rm = TRUE)
  .(Ticker = Ticker,
    mom_class = fcase(mom_12_1 >= q_hi, "W",
                       mom_12_1 <= q_lo, "L",
                       default = "M"))
}, by = ym]
mom_class_dt[, ym_apply := format(as.Date(paste0(ym, "-01")) + 32, "%Y-%m")]
mom_apply <- mom_class_dt[, .(ym = ym_apply, Ticker, mom_class)]
ret_with_mom <- ret_monthly[mom_apply, on = c("ym","Ticker"), nomatch=0]
umd_dt <- ret_with_mom[mom_class %in% c("W","L"),
                       .(ret_class = mean(ret_m, na.rm=TRUE)),
                       by = .(ym, mom_class)]
umd_wide <- dcast(umd_dt, ym ~ mom_class, value.var = "ret_class")
umd_wide[, UMD := W - L]
cat("UMD rows:", nrow(umd_wide), "\n")

# HML / RMW / CMA from Factor DB Z-scores
fdb_files <- list.files(".cache/factor_db",
                        pattern = "factor_db_[0-9]{6}\\.parquet$",
                        full.names = TRUE)
sort_keys <- as.integer(gsub(".*factor_db_([0-9]{6})\\.parquet", "\\1",
                              basename(fdb_files)))
fdb_files <- fdb_files[order(sort_keys)]

read_factor <- function(factor_name) {
  out <- lapply(fdb_files, function(f) {
    d <- tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0) return(NULL)
    fcol <- if ("Factor_Name" %in% names(d)) "Factor_Name" else "Factor"
    if (!fcol %in% names(d)) return(NULL)
    d2 <- d[get(fcol) == factor_name]
    if (nrow(d2) == 0) NULL else d2
  })
  out <- out[!sapply(out, is.null)]
  if (length(out) > 0) rbindlist(out, fill = TRUE) else NULL
}

build_factor_LS <- function(name, dir = 1L) {
  d <- read_factor(name)
  if (is.null(d) || !"Z_Score" %in% names(d)) return(NULL)
  d[, ym := format(as.Date(Date), "%Y-%m")]
  c_dt <- d[!is.na(Z_Score), {
    q_lo <- quantile(Z_Score, 0.30, na.rm = TRUE)
    q_hi <- quantile(Z_Score, 0.70, na.rm = TRUE)
    .(Ticker = Ticker,
      cls = fcase(Z_Score * dir >= q_hi * dir, "H",
                   Z_Score * dir <= q_lo * dir, "L",
                   default = "M"))
  }, by = ym]
  c_dt[, ym_apply := format(as.Date(paste0(ym, "-01")) + 32, "%Y-%m")]
  cap <- c_dt[, .(ym = ym_apply, Ticker, cls)]
  ret_w <- ret_monthly[cap, on = c("ym","Ticker"), nomatch=0]
  agg <- ret_w[cls %in% c("H","L"),
               .(ret_class = mean(ret_m, na.rm=TRUE)),
               by = .(ym, cls)]
  wide <- dcast(agg, ym ~ cls, value.var = "ret_class")
  wide[, factor := H - L]
  wide[, .(ym, factor)]
}

hml_dt <- build_factor_LS("V01_BM")
rmw_dt <- build_factor_LS("Q02_ROE")
cma_dt <- build_factor_LS("Q07_Earnings_Stability")

if (is.null(hml_dt)) hml_dt <- data.table(ym = unique(dt_ret$ym), factor = NA_real_)
if (is.null(rmw_dt)) rmw_dt <- data.table(ym = unique(dt_ret$ym), factor = NA_real_)
if (is.null(cma_dt)) cma_dt <- data.table(ym = unique(dt_ret$ym), factor = NA_real_)

setnames(hml_dt, "factor", "HML")
setnames(rmw_dt, "factor", "RMW")
setnames(cma_dt, "factor", "CMA")
cat("HML rows:", nrow(hml_dt), " | RMW:", nrow(rmw_dt), " | CMA:", nrow(cma_dt), "\n")

# Merge factors
factors <- merge(mkt_dt, smb_wide[, .(ym, SMB)], by = "ym", all.x = TRUE)
factors <- merge(factors, hml_dt, by = "ym", all.x = TRUE)
factors <- merge(factors, umd_wide[, .(ym, UMD)], by = "ym", all.x = TRUE)
factors <- merge(factors, rmw_dt, by = "ym", all.x = TRUE)
factors <- merge(factors, cma_dt, by = "ym", all.x = TRUE)

# Merge with V2 returns
dt <- merge(dt_ret, factors, by = "ym")
dt <- dt[complete.cases(dt[, .(ret_V2, Mkt)])]
cat("\nMerged dataset: n_months=", nrow(dt), "\n")
cat("Factor NA counts:\n")
print(dt[, .(N=.N, SMB_NA=sum(is.na(SMB)), HML_NA=sum(is.na(HML)),
             UMD_NA=sum(is.na(UMD)), RMW_NA=sum(is.na(RMW)),
             CMA_NA=sum(is.na(CMA)))])

# Fill remaining NA factors with 0 (precedent convention)
dt2 <- copy(dt)
for (col in c("SMB","HML","UMD","RMW","CMA")) {
  dt2[is.na(get(col)), (col) := 0]
}

# ============================================================
# Run 5 specifications
# ============================================================
run_spec <- function(formula_str, label, dt, dep = "ret_V2") {
  fml <- as.formula(formula_str)
  fit <- lm(fml, data = dt)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, prewhite = FALSE, adjust = TRUE))
  alpha_row <- ct["(Intercept)", ]
  list(
    spec = label,
    dep_var = dep,
    n_obs = nobs(fit),
    alpha_monthly = unname(alpha_row[1]),
    alpha_annual = (1 + unname(alpha_row[1]))^12 - 1,
    se_NW = unname(alpha_row[2]),
    t_NW = unname(alpha_row[3]),
    p_NW = unname(alpha_row[4]),
    r_squared = summary(fit)$r.squared,
    pass_t3 = unname(alpha_row[3]) > 3.0,
    coefs = setNames(as.numeric(coef(fit)), names(coef(fit)))
  )
}

cat("\n=== V2 LAYER 5 R05 — KR FF5 / Carhart-4 REGRESSIONS ===\n")
s1 <- run_spec("ret_V2 ~ Mkt",                                 "CAPM",      dt2)
s2 <- run_spec("ret_V2 ~ Mkt + SMB + HML",                     "FF3",       dt2)
s3 <- run_spec("ret_V2 ~ Mkt + SMB + HML + UMD",               "Carhart4",  dt2)
s4 <- run_spec("ret_V2 ~ Mkt + SMB + HML + RMW + CMA",         "FF5",       dt2)
s5 <- run_spec("ret_V2 ~ Mkt + SMB + HML + RMW + CMA + UMD",   "FF6",       dt2)

results_v2 <- list(s1, s2, s3, s4, s5)
summary_v2 <- rbindlist(lapply(results_v2, function(r) {
  data.table(spec=r$spec, n_obs=r$n_obs,
             alpha_monthly_pct=round(r$alpha_monthly*100, 4),
             alpha_annual_pct=round(r$alpha_annual*100, 2),
             t_NW=round(r$t_NW, 3),
             p_NW=round(r$p_NW, 4),
             pass_t3=r$pass_t3,
             r_squared=round(r$r_squared, 3),
             beta_Mkt=round(r$coefs["Mkt"], 4),
             beta_SMB=round(ifelse("SMB" %in% names(r$coefs), r$coefs["SMB"], NA), 4),
             beta_HML=round(ifelse("HML" %in% names(r$coefs), r$coefs["HML"], NA), 4),
             beta_UMD=round(ifelse("UMD" %in% names(r$coefs), r$coefs["UMD"], NA), 4),
             beta_RMW=round(ifelse("RMW" %in% names(r$coefs), r$coefs["RMW"], NA), 4),
             beta_CMA=round(ifelse("CMA" %in% names(r$coefs), r$coefs["CMA"], NA), 4))
}))
print(summary_v2)
n_pass_v2 <- sum(summary_v2$pass_t3)
cat(sprintf("\nV2 PASS count (t_NW > 3.0): %d / 5\n", n_pass_v2))
cat(sprintf("Verdict: %s\n",
            ifelse(n_pass_v2 >= 3, "PASS_MAJORITY",
                   ifelse(n_pass_v2 >= 1, "PASS_PARTIAL", "FAIL"))))

# Compare with L4 baseline as sanity
cat("\n=== L4 BASELINE — sanity check ===\n")
l1 <- run_spec("ret_L4 ~ Mkt", "CAPM", dt2, "ret_L4")
l2 <- run_spec("ret_L4 ~ Mkt + SMB + HML", "FF3", dt2, "ret_L4")
l3 <- run_spec("ret_L4 ~ Mkt + SMB + HML + UMD", "Carhart4", dt2, "ret_L4")
l4 <- run_spec("ret_L4 ~ Mkt + SMB + HML + RMW + CMA", "FF5", dt2, "ret_L4")
l5 <- run_spec("ret_L4 ~ Mkt + SMB + HML + RMW + CMA + UMD", "FF6", dt2, "ret_L4")
results_l4 <- list(l1,l2,l3,l4,l5)
summary_l4 <- rbindlist(lapply(results_l4, function(r) {
  data.table(spec=r$spec, alpha_mo_pct=round(r$alpha_monthly*100, 4),
             alpha_an_pct=round(r$alpha_annual*100, 2),
             t_NW=round(r$t_NW, 3), pass=r$pass_t3,
             R2=round(r$r_squared, 3))
}))
print(summary_l4)

# ============================================================
# Save JSON
# ============================================================
out <- list(
  task_id = "WT-H20260513_001",
  agent = "architect",
  prereq = "P2_harvey_5spec_full_FF5_carhart4_kr",
  variant = "L5_V2_aggressive_regime",
  n_months = nrow(dt),
  date_range = c(min(dt$ym), max(dt$ym)),
  factor_construction_method = "KR-domestic (admit precedent WT-P20260504_001 method): Mkt=BM_Ret monthly compound, SMB=size median split, HML=V01_BM Z, UMD=12-1m mom, RMW=Q02_ROE Z, CMA=Q07_Earnings_Stability Z",
  hurdle = "Harvey-Liu-Zhu (2016 RFS) t_NW > 3.0",
  v2_results = lapply(results_v2, function(r) list(
    spec=r$spec, n_obs=r$n_obs,
    alpha_monthly=r$alpha_monthly, alpha_annual=r$alpha_annual,
    se_NW=r$se_NW, t_NW=r$t_NW, p_NW=r$p_NW,
    r_squared=r$r_squared, pass_t3=r$pass_t3,
    coefs=as.list(r$coefs)
  )),
  l4_baseline_sanity = lapply(results_l4, function(r) list(
    spec=r$spec, alpha_monthly=r$alpha_monthly,
    t_NW=r$t_NW, pass_t3=r$pass_t3, r_squared=r$r_squared
  )),
  summary = list(
    v2_n_pass_t3 = n_pass_v2,
    v2_n_total = 5,
    v2_pass_rate = n_pass_v2 / 5,
    v2_verdict = ifelse(n_pass_v2 >= 3, "PASS_MAJORITY",
                        ifelse(n_pass_v2 >= 1, "PASS_PARTIAL", "FAIL"))
  ),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)
write_json(out, "qepm/mailbox/worktask/WT-H20260513_001/architect_kr_ff5_v2.json",
           pretty = TRUE, auto_unbox = TRUE)
fwrite(summary_v2, "qepm/mailbox/worktask/WT-H20260513_001/architect_kr_ff5_v2_summary.csv")
cat("\n[saved] architect_kr_ff5_v2.json + architect_kr_ff5_v2_summary.csv\n")
