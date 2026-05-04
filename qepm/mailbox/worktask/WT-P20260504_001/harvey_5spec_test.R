## Harvey-Liu-Zhu (2016) 5-spec t_NW HAC > 3.0 test
## S1_threshold AR overlay strategy alpha against:
##   CAPM, FF3, Carhart4, FF5, FF6
## Korean factors constructed from RAWDATA + Factor DB.
## Newey-West HAC standard error per Harvey-Liu-Zhu (2016 RFS).

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(sandwich)
  library(lmtest)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-P20260504_001")

# ------------------------------------------------------------
# 1. Load S1 threshold returns (post-hoc apply 결과)
# ------------------------------------------------------------
str_returns_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
str_dt <- fread(str_returns_path)
str_dt[, date := as.Date(date)]
setorder(str_dt, date)

beta_path <- file.path(base_dir,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
setorder(beta_dt, Date)
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

str_dt[, ym := format(date, "%Y-%m")]
beta_dt[, ym := format(Date, "%Y-%m")]
mrg <- beta_dt[str_dt, on = "ym"]
mrg <- mrg[!is.na(beta_threshold_lag)]

mrg[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
mrg[, ret_S1 := beta_threshold_lag * ret_net - db_thr * 0.0015]

# ------------------------------------------------------------
# 2. Build KR factors from RAWDATA monthly aggregation
# ------------------------------------------------------------
raw <- as.data.table(read_parquet(file.path(base_dir, ".cache/rawdata.parquet")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2003-01-01") & Date <= as.Date("2026-05-04")]
raw[, ym := format(Date, "%Y-%m")]
raw <- raw[!is.na(Ret) & is.finite(Ret) & abs(Ret) < 0.5]
raw <- raw[!is.na(Size) & Size > 0]

# Market factor: BM_Ret (KOSPI200)
mkt_dt <- raw[, .(Mkt = mean(BM_Ret, na.rm = TRUE)),
              keyby = .(ym)]

# Build size buckets monthly (small/big tertile)
month_starts <- raw[, .(date_first = min(Date)), by = ym]
size_classes <- raw[, {
  size_med <- median(Size, na.rm = TRUE)
  .(Ticker = Ticker, size_class = ifelse(Size <= size_med, "S", "B"),
    Ret = Ret)
}, by = .(ym)]

# Compute SMB monthly — equal-weight S vs B then aggregate daily->monthly
ret_monthly <- raw[, .(ret_m = prod(1 + Ret) - 1), by = .(ym, Ticker)]
size_classes_m <- raw[, {
  size_med <- median(Size, na.rm = TRUE)
  .(Ticker = unique(Ticker[Size <= size_med]), size_class = "S")
}, by = ym][!is.na(Ticker)]
size_classes_m_b <- raw[, {
  size_med <- median(Size, na.rm = TRUE)
  .(Ticker = unique(Ticker[Size > size_med]), size_class = "B")
}, by = ym][!is.na(Ticker)]
size_classes_all <- rbind(size_classes_m, size_classes_m_b)

# Merge with monthly returns
ret_with_class <- ret_monthly[size_classes_all, on = c("ym", "Ticker"), nomatch = 0]
smb_dt <- ret_with_class[, .(ret_class = mean(ret_m, na.rm = TRUE)),
                          by = .(ym, size_class)]
smb_wide <- dcast(smb_dt, ym ~ size_class, value.var = "ret_class")
smb_wide[, SMB := S - B]

# Momentum (UMD): use 12-1 month momentum
ret_monthly_sort <- copy(ret_monthly)
setorder(ret_monthly_sort, Ticker, ym)
# Compute 12-1m momentum via shift (skip most recent month)
ret_monthly_sort[, lret_m := log(1 + pmax(ret_m, -0.99))]
ret_monthly_sort[, lret_lag1 := shift(lret_m, 1, type = "lag"), by = Ticker]
ret_monthly_sort[, lret_sum_11_2 := frollsum(lret_lag1, 11,
                                              align = "right",
                                              fill = NA_real_), by = Ticker]
ret_monthly_sort[, mom_12_1 := exp(lret_sum_11_2) - 1]

# At each ym, sort by mom_12_1, top-30% vs bottom-30%, then EW return next month
mom_class_dt <- ret_monthly_sort[!is.na(mom_12_1), {
  q_lo <- quantile(mom_12_1, 0.30, na.rm = TRUE)
  q_hi <- quantile(mom_12_1, 0.70, na.rm = TRUE)
  .(Ticker = Ticker,
    mom_class = fcase(mom_12_1 >= q_hi, "W",
                       mom_12_1 <= q_lo, "L",
                       default = "M"))
}, by = ym]

# Apply at next month (1m lag)
ret_monthly_sort[, ym_next := format(as.Date(paste0(ym, "-01")) + 32, "%Y-%m")]
mom_class_dt[, ym_apply := format(as.Date(paste0(ym, "-01")) + 32, "%Y-%m")]

mom_apply <- mom_class_dt[, .(ym = ym_apply, Ticker, mom_class)]
ret_with_mom <- ret_monthly[mom_apply, on = c("ym", "Ticker"), nomatch = 0]
umd_dt <- ret_with_mom[mom_class %in% c("W", "L"),
  .(ret_class = mean(ret_m, na.rm = TRUE)), by = .(ym, mom_class)]
umd_wide <- dcast(umd_dt, ym ~ mom_class, value.var = "ret_class")
umd_wide[, UMD := W - L]

# Value (HML proxy): use Factor DB V01_BM monthly
fdb_files <- list.files(file.path(base_dir, ".cache/factor_db"),
                        pattern = "factor_db_[0-9]{6}\\.parquet$",
                        full.names = TRUE)
sort_keys <- as.integer(gsub(".*factor_db_([0-9]{6})\\.parquet", "\\1", basename(fdb_files)))
fdb_files <- fdb_files[order(sort_keys)]

read_bm <- function(f) {
  d <- as.data.table(read_parquet(f))
  if ("Factor_Name" %in% names(d)) {
    d <- d[Factor_Name == "V01_BM"]
  } else if ("Factor" %in% names(d)) {
    d <- d[Factor == "V01_BM"]
  } else {
    return(NULL)
  }
  if (nrow(d) == 0) return(NULL)
  d
}

bm_list <- lapply(fdb_files, function(f) tryCatch(read_bm(f), error = function(e) NULL))
bm_list <- bm_list[!sapply(bm_list, is.null)]
if (length(bm_list) > 0) {
  bm_dt <- rbindlist(bm_list, fill = TRUE)
  bm_dt[, ym := format(as.Date(Date), "%Y-%m")]
  hml_class_dt <- bm_dt[!is.na(Z_Score), {
    q_lo <- quantile(Z_Score, 0.30, na.rm = TRUE)
    q_hi <- quantile(Z_Score, 0.70, na.rm = TRUE)
    .(Ticker = Ticker,
      hml_class = fcase(Z_Score >= q_hi, "H",
                         Z_Score <= q_lo, "L",
                         default = "M"))
  }, by = ym]

  hml_class_dt[, ym_apply := format(as.Date(paste0(ym, "-01")) + 32, "%Y-%m")]
  hml_apply <- hml_class_dt[, .(ym = ym_apply, Ticker, hml_class)]
  ret_with_hml <- ret_monthly[hml_apply, on = c("ym", "Ticker"), nomatch = 0]
  hml_dt <- ret_with_hml[hml_class %in% c("H", "L"),
    .(ret_class = mean(ret_m, na.rm = TRUE)), by = .(ym, hml_class)]
  hml_wide <- dcast(hml_dt, ym ~ hml_class, value.var = "ret_class")
  hml_wide[, HML := H - L]
} else {
  hml_wide <- data.table(ym = unique(mrg$ym), HML = NA_real_)
  cat("[WARN] V01_BM not found in factor_db, HML = NA\n")
}

# Quality (RMW proxy): Q02_ROE
read_factor <- function(factor_name) {
  out <- lapply(fdb_files, function(f) {
    d <- as.data.table(read_parquet(f))
    fcol <- if ("Factor_Name" %in% names(d)) "Factor_Name" else "Factor"
    if (!fcol %in% names(d)) return(NULL)
    d2 <- d[get(fcol) == factor_name]
    if (nrow(d2) == 0) NULL else d2
  })
  out <- out[!sapply(out, is.null)]
  if (length(out) > 0) rbindlist(out, fill = TRUE) else NULL
}

build_factor_long_short <- function(name, dir = 1L) {
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
  ret_w <- ret_monthly[cap, on = c("ym", "Ticker"), nomatch = 0]
  agg <- ret_w[cls %in% c("H", "L"),
    .(ret_class = mean(ret_m, na.rm = TRUE)), by = .(ym, cls)]
  wide <- dcast(agg, ym ~ cls, value.var = "ret_class")
  wide[, factor := H - L]
  wide[, .(ym, factor)]
}

rmw_dt <- build_factor_long_short("Q02_ROE")
cma_dt <- build_factor_long_short("Q07_Earnings_Stability")  # proxy

if (is.null(rmw_dt)) rmw_dt <- data.table(ym = unique(mrg$ym), factor = NA_real_)
if (is.null(cma_dt)) cma_dt <- data.table(ym = unique(mrg$ym), factor = NA_real_)
setnames(rmw_dt, "factor", "RMW")
setnames(cma_dt, "factor", "CMA")

# ------------------------------------------------------------
# 3. Merge factors with S1 returns
# ------------------------------------------------------------
factors <- merge(mkt_dt, smb_wide[, .(ym, SMB)], by = "ym", all.x = TRUE)
factors <- merge(factors, hml_wide[, .(ym, HML)], by = "ym", all.x = TRUE)
factors <- merge(factors, umd_wide[, .(ym, UMD)], by = "ym", all.x = TRUE)
factors <- merge(factors, rmw_dt, by = "ym", all.x = TRUE)
factors <- merge(factors, cma_dt, by = "ym", all.x = TRUE)

dt <- merge(mrg[, .(ym, ret_S1)], factors, by = "ym")
dt <- dt[complete.cases(dt[, .(ret_S1, Mkt)])]

cat("\n[merged] n_months=", nrow(dt), "\n")
cat("Factor coverage:\n")
print(dt[, .(N = .N, SMB_NA = sum(is.na(SMB)),
             HML_NA = sum(is.na(HML)),
             UMD_NA = sum(is.na(UMD)),
             RMW_NA = sum(is.na(RMW)),
             CMA_NA = sum(is.na(CMA)))])

# ------------------------------------------------------------
# 4. Run 5 specifications with NW HAC
# ------------------------------------------------------------
run_spec <- function(formula_str, label, dt) {
  fit <- lm(as.formula(formula_str), data = dt)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, prewhite = FALSE, adjust = TRUE))
  alpha_row <- ct["(Intercept)", ]
  list(
    spec = label,
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

dt2 <- copy(dt)
dt2[is.na(SMB), SMB := 0]
dt2[is.na(HML), HML := 0]
dt2[is.na(UMD), UMD := 0]
dt2[is.na(RMW), RMW := 0]
dt2[is.na(CMA), CMA := 0]

spec1 <- run_spec("ret_S1 ~ Mkt", "CAPM", dt2)
spec2 <- run_spec("ret_S1 ~ Mkt + SMB + HML", "FF3", dt2)
spec3 <- run_spec("ret_S1 ~ Mkt + SMB + HML + UMD", "Carhart4", dt2)
spec4 <- run_spec("ret_S1 ~ Mkt + SMB + HML + RMW + CMA", "FF5", dt2)
spec5 <- run_spec("ret_S1 ~ Mkt + SMB + HML + RMW + CMA + UMD", "FF6", dt2)

results <- list(spec1, spec2, spec3, spec4, spec5)
summary_dt <- rbindlist(lapply(results, function(r) {
  data.table(spec = r$spec, n_obs = r$n_obs,
             alpha_monthly_pct = round(r$alpha_monthly * 100, 4),
             alpha_annual_pct = round(r$alpha_annual * 100, 2),
             t_NW = round(r$t_NW, 3),
             p_NW = round(r$p_NW, 4),
             pass_t3 = r$pass_t3,
             r_squared = round(r$r_squared, 3))
}))

cat("\n=== HARVEY 5-SPEC RESULTS (S1 threshold AR overlay) ===\n")
print(summary_dt)

n_pass <- sum(summary_dt$pass_t3)
cat(sprintf("\nPASS count (t_NW > 3.0): %d / 5\n", n_pass))
cat(sprintf("Harvey-Liu-Zhu (2016) Hurdle: t > 3.0 strict for multi-test deflation\n"))
cat(sprintf("Verdict: %s\n",
            ifelse(n_pass >= 3, "PASS_MAJORITY",
                   ifelse(n_pass >= 1, "PASS_PARTIAL", "FAIL"))))

# ------------------------------------------------------------
# 5. Save JSON
# ------------------------------------------------------------
output <- list(
  task_id = "WT-P20260504_001",
  prereq = "P2_harvey_5spec",
  variant_under_test = "S1_threshold_step",
  n_months = nrow(dt),
  factor_construction_method = "KR-domestic constructed from RAWDATA (Mkt=BM_Ret/SMB=size median split/UMD=mom_12_1) + Factor DB monthly Z (HML=V01_BM, RMW=Q02_ROE, CMA=Q07_Earnings_Stability proxy)",
  hurdle = "Harvey-Liu-Zhu (2016 RFS) t_NW > 3.0",
  results = lapply(results, function(r) list(
    spec = r$spec,
    n_obs = r$n_obs,
    alpha_monthly = r$alpha_monthly,
    alpha_annual = r$alpha_annual,
    se_NW = r$se_NW,
    t_NW = r$t_NW,
    p_NW = r$p_NW,
    r_squared = r$r_squared,
    pass_t3 = r$pass_t3
  )),
  summary = list(
    n_pass_t3 = n_pass,
    n_total = 5,
    pass_rate = n_pass / 5,
    verdict = ifelse(n_pass >= 3, "PASS_MAJORITY",
                     ifelse(n_pass >= 1, "PASS_PARTIAL", "FAIL"))
  ),
  caveats = list(
    "RMW proxied by Q02_ROE (true RMW requires gross profit / book equity from DART; available but not constructed in this run)",
    "CMA proxied by Q07_Earnings_Stability (true CMA requires asset growth; alternative proxy)",
    "HML uses V01_BM Z-score; matches Fama-French BM definition closely",
    "UMD uses 12-1m momentum constructed from RAWDATA returns",
    "Newey-West lag selected automatically by sandwich::NeweyWest() default",
    "Multi-test deflation: 5 specs tested → BH or Bonferroni adjustment recommended in companion DSR"
  ),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)

write_json(output, file.path(wt_dir, "harvey_5spec_results.json"),
           pretty = TRUE, auto_unbox = TRUE)

fwrite(summary_dt, file.path(wt_dir, "harvey_5spec_summary.csv"))
cat("\n[saved] harvey_5spec_results.json + harvey_5spec_summary.csv\n")
