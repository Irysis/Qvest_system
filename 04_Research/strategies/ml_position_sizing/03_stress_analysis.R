cat("=== ML Position Sizing: 8-Period Stress Analysis ===\n")
## 8대 스트레스 구간별 가중 방법 비교
## 참조: memory/reference_stress_periods.md (9/11~Iran War)
## 입력: horse_race_results에서 생성된 ml_sizing_monthly_rets.csv

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(tidyr)
  library(lubridate)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

# ═══════════════════════════════════════════════════════════════════
# 1. Load Monthly Returns
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading monthly returns...\n")

rets_path <- file.path(CACHE_DIR, "ml_sizing_monthly_rets.csv")
if (!file.exists(rets_path)) {
  stop("[ERROR] Monthly returns not found. Run 02_horse_race.R first.")
}

ret_dt <- fread(rets_path)
ret_dt[, Date := as.Date(Date)]
setorder(ret_dt, Date)

method_cols <- setdiff(names(ret_dt), c("Date", "BM", "M4_LSTM", "Year"))
method_cols <- method_cols[!is.na(method_cols)]

cat(sprintf("[data] Monthly returns: %d months, %d methods\n",
            nrow(ret_dt), length(method_cols)))
cat(sprintf("[data] Methods: %s\n", paste(method_cols, collapse=", ")))
cat(sprintf("[data] Date range: %s ~ %s\n",
            as.character(min(ret_dt$Date)), as.character(max(ret_dt$Date))))

# ═══════════════════════════════════════════════════════════════════
# 2. Define 8 Stress Periods
# ═══════════════════════════════════════════════════════════════════
stress_periods <- list(
  list(label="9/11",       start="2001-09-01", end="2001-12-31"),
  list(label="GFC",        start="2007-10-01", end="2009-03-31"),
  list(label="EuDebt",     start="2011-07-01", end="2011-12-31"),
  list(label="ChinaShock", start="2015-06-01", end="2016-02-29"),
  list(label="TradeWar",   start="2018-03-01", end="2018-12-31"),
  list(label="COVID",      start="2020-01-01", end="2020-06-30"),
  list(label="RateHike",   start="2022-01-01", end="2022-12-31"),
  list(label="IranWar",    start="2026-02-01", end="2026-04-30")
)

cat(sprintf("\n[setup] Stress periods: %d\n", length(stress_periods)))

# ═══════════════════════════════════════════════════════════════════
# 3. Helper: Stress Period Metrics
# ═══════════════════════════════════════════════════════════════════
calc_stress_metrics <- function(rets, bm_rets, label, start_date, end_date) {
  s <- as.Date(start_date)
  e <- as.Date(end_date)

  # 해당 기간 월간 수익률
  mask <- ret_dt$Date >= s & ret_dt$Date <= e
  if (sum(mask) == 0L) {
    return(data.table(
      Period = label,
      Start = start_date, End = end_date,
      N_months = 0L,
      Period_Ret = NA, MDD = NA, Sharpe = NA,
      BM_Ret = NA, Excess_Ret = NA, Protected = FALSE
    ))
  }

  r  <- rets[mask]
  b  <- bm_rets[mask]

  # 기간 총수익률
  r_clean <- ifelse(is.na(r), 0, r)
  b_clean <- ifelse(is.na(b), 0, b)
  period_ret <- prod(1 + r_clean) - 1
  bm_ret     <- prod(1 + b_clean) - 1

  # MDD
  nav_str <- cumprod(1 + r_clean)
  run_max <- cummax(nav_str)
  dd <- (run_max - nav_str) / run_max
  mdd <- max(dd)

  # BM MDD
  bm_nav <- cumprod(1 + b_clean)
  bm_run_max <- cummax(bm_nav)
  bm_dd <- (bm_run_max - bm_nav) / bm_run_max
  bm_mdd <- max(bm_dd)

  # Sharpe (기간 내)
  n_m <- sum(mask)
  sr  <- if (n_m >= 2L && sd(r, na.rm=TRUE) > 1e-10)
    mean(r, na.rm=TRUE) / sd(r, na.rm=TRUE) * sqrt(12) else NA_real_

  # 초과수익
  excess <- period_ret - bm_ret

  # Protected: 전략 MDD < BM MDD
  protected <- (!is.na(mdd) && !is.na(bm_mdd) && mdd < bm_mdd)

  data.table(
    Period     = label,
    Start      = start_date,
    End        = end_date,
    N_months   = n_m,
    Period_Ret = period_ret,
    MDD        = mdd,
    BM_MDD     = bm_mdd,
    Sharpe     = sr,
    BM_Ret     = bm_ret,
    Excess_Ret = excess,
    Protected  = protected
  )
}

# ═══════════════════════════════════════════════════════════════════
# 4. Run Stress Analysis for Each Method
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Computing stress metrics for each method × period...\n")

bm_rets <- ret_dt$BM
all_stress <- vector("list", length(method_cols))

for (mi in seq_along(method_cols)) {
  meth <- method_cols[mi]
  meth_rets <- ret_dt[[meth]]

  stress_results <- vector("list", length(stress_periods))
  for (si in seq_along(stress_periods)) {
    sp <- stress_periods[[si]]
    stress_results[[si]] <- calc_stress_metrics(
      meth_rets, bm_rets,
      sp$label, sp$start, sp$end
    )
  }

  method_stress <- rbindlist(stress_results)
  method_stress[, Method := meth]
  all_stress[[mi]] <- method_stress
}

stress_dt <- rbindlist(all_stress, fill=TRUE, use.names=TRUE)

# BM 행도 추가
bm_stress <- vector("list", length(stress_periods))
for (si in seq_along(stress_periods)) {
  sp <- stress_periods[[si]]
  bm_stress[[si]] <- calc_stress_metrics(bm_rets, bm_rets, sp$label, sp$start, sp$end)
  bm_stress[[si]][, Method := "BM(KOSPI)"]
}
bm_stress_dt <- rbindlist(bm_stress)
stress_dt <- rbind(stress_dt, bm_stress_dt, fill=TRUE)

# 결과 저장
fwrite(stress_dt, file.path(OUT_DIR, "stress_comparison.csv"))
cat(sprintf("[saved] stress_comparison.csv -> %s\n",
            file.path(OUT_DIR, "stress_comparison.csv")))

# 요약 출력
cat("\n=== Stress Period Summary ===\n")
stress_wide <- dcast(stress_dt, Period ~ Method, value.var="Period_Ret")
print(stress_wide)

cat("\n=== Protected Count (MDD < BM MDD) ===\n")
protected_summary <- stress_dt[Method != "BM(KOSPI)",
  .(Protected_Count = sum(Protected, na.rm=TRUE),
    Total_Periods = sum(!is.na(Protected))),
  by=Method]
protected_summary[, Protected_Pct := round(100 * Protected_Count / Total_Periods, 1)]
setorder(protected_summary, -Protected_Count)
print(protected_summary)

# ═══════════════════════════════════════════════════════════════════
# 5. Stress Heatmap
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Generating stress heatmap...\n")

# Period_Ret 기준 히트맵
heat_dt <- stress_dt[, .(Period, Method, Period_Ret, Protected, MDD, BM_MDD)]

# Period 순서 고정
period_order <- sapply(stress_periods, `[[`, "label")
heat_dt[, Period := factor(Period, levels=period_order)]

# Method 순서: SR 기준 (horse_race_results.csv에서)
hr_path <- file.path(OUT_DIR, "horse_race_results.csv")
if (file.exists(hr_path)) {
  hr_dt <- fread(hr_path)
  method_order <- c(hr_dt[order(-SR), Method], "BM(KOSPI)")
} else {
  method_order <- unique(heat_dt$Method)
}
heat_dt[, Method := factor(Method, levels=method_order)]

# 수익률 라벨 (%)
heat_dt[, label_txt := sprintf("%.1f%%", Period_Ret * 100)]
heat_dt[is.na(Period_Ret), label_txt := "N/A"]

# 보호 여부 표시 (* = Protected)
heat_dt[Protected == TRUE, label_txt := paste0(label_txt, "*")]

p_heat <- ggplot(heat_dt[!is.na(Period)],
                  aes(x=Method, y=Period, fill=Period_Ret)) +
  geom_tile(color="white", linewidth=0.5) +
  geom_text(aes(label=label_txt), size=3, fontface="bold") +
  scale_fill_gradient2(
    low="#D55E00", mid="white", high="#009E73",
    midpoint=0,
    labels=scales::percent,
    name="Period\nReturn"
  ) +
  labs(
    title="ML Position Sizing: Stress Period Returns",
    subtitle="* = Protected (Strategy MDD < BM MDD) | Methods ordered by OOS SR",
    x="Weighting Method", y="Stress Period"
  ) +
  theme_minimal(base_size=11) +
  theme(
    axis.text.x=element_text(angle=35, hjust=1, size=9),
    axis.text.y=element_text(size=10),
    panel.grid=element_blank(),
    legend.position="right"
  )

ggsave(file.path(OUT_DIR, "stress_heatmap.png"), p_heat,
       width=14, height=7, dpi=150)
cat("[saved] stress_heatmap.png\n")

# ═══════════════════════════════════════════════════════════════════
# 6. MDD Comparison Chart
# ═══════════════════════════════════════════════════════════════════
mdd_dt <- stress_dt[, .(Period, Method, MDD)]
mdd_dt[, Period := factor(Period, levels=period_order)]
mdd_dt[, Method := factor(Method, levels=method_order)]

p_mdd <- ggplot(mdd_dt[!is.na(MDD) & !is.na(Period)],
                 aes(x=Period, y=MDD*100, group=Method, color=Method)) +
  geom_line(linewidth=0.8) +
  geom_point(size=2) +
  scale_color_manual(values=c(
    EW="grey60", InvVol="#E69F00", HRP="#56B4E9",
    M1_ElasticNet="#009E73", M2_LightGBM="#F0E442",
    M3_QRF="#0072B2", M5_GARCHX="#D55E00",
    "BM(KOSPI)"="black"
  )) +
  scale_y_continuous(labels=function(x) paste0(x,"%")) +
  labs(
    title="ML Position Sizing: Max Drawdown per Stress Period",
    subtitle="Lower MDD = better drawdown protection",
    x="Stress Period", y="Max Drawdown (%)", color="Method"
  ) +
  theme_minimal(base_size=11) +
  theme(axis.text.x=element_text(angle=35, hjust=1),
        panel.grid.minor=element_blank())

ggsave(file.path(OUT_DIR, "stress_mdd_comparison.png"), p_mdd,
       width=14, height=6, dpi=150)
cat("[saved] stress_mdd_comparison.png\n")

# ═══════════════════════════════════════════════════════════════════
# 7. Overall Summary Report
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Generating summary report...\n")

report_path <- file.path(OUT_DIR, "stress_summary_report.txt")
sink(report_path)

cat("=== ML Position Sizing: Stress Analysis Report ===\n\n")
cat(sprintf("Generated: %s\n\n", Sys.time()))

cat("=== 8 Stress Periods Coverage ===\n")
for (sp in stress_periods) {
  n_m <- nrow(ret_dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)])
  cat(sprintf("  %-12s %s ~ %s  [%d months in data]\n",
              sp$label, sp$start, sp$end, n_m))
}

cat("\n=== Period Return by Method (%) ===\n")
ret_tbl <- dcast(stress_dt, Period ~ Method, value.var="Period_Ret")
ret_tbl_pct <- copy(ret_tbl)
for (col in setdiff(names(ret_tbl_pct), "Period")) {
  ret_tbl_pct[[col]] <- round(ret_tbl_pct[[col]] * 100, 1)
}
print(ret_tbl_pct)

cat("\n=== MDD by Method (%) ===\n")
mdd_tbl <- dcast(stress_dt, Period ~ Method, value.var="MDD")
mdd_tbl_pct <- copy(mdd_tbl)
for (col in setdiff(names(mdd_tbl_pct), "Period")) {
  mdd_tbl_pct[[col]] <- round(mdd_tbl_pct[[col]] * 100, 1)
}
print(mdd_tbl_pct)

cat("\n=== Protection Rate (MDD < BM MDD, %) ===\n")
print(protected_summary)

cat("\n=== Key Findings ===\n")
# 최고 Protection Rate
best_protected <- protected_summary[which.max(Protected_Count)]
cat(sprintf("  Best drawdown protection: %s (%d/%d periods = %.0f%%)\n",
            best_protected$Method, best_protected$Protected_Count,
            best_protected$Total_Periods, best_protected$Protected_Pct))

# 최고 GFC 수익률
gfc_row <- stress_dt[Period == "GFC" & Method != "BM(KOSPI)"]
if (nrow(gfc_row) > 0L && !all(is.na(gfc_row$Period_Ret))) {
  best_gfc <- gfc_row[which.max(Period_Ret)]
  cat(sprintf("  Best GFC period: %s (%.1f%% vs BM: %.1f%%)\n",
              best_gfc$Method, best_gfc$Period_Ret*100,
              unique(stress_dt[Period=="GFC"&Method=="BM(KOSPI)", Period_Ret])*100))
}

# COVID 최고
covid_row <- stress_dt[Period == "COVID" & Method != "BM(KOSPI)"]
if (nrow(covid_row) > 0L && !all(is.na(covid_row$Period_Ret))) {
  best_covid <- covid_row[which.max(Period_Ret)]
  cat(sprintf("  Best COVID period: %s (%.1f%%)\n",
              best_covid$Method, best_covid$Period_Ret*100))
}

cat("\n=== L-123 Compliance Note ===\n")
cat("  MC-P1: IC prefilter top-50 from fdb_daily D/R/L family\n")
cat("  MC-P2: fdb_daily (일간 Factor DB, 309 factors) 참조\n")
cat("  MC-P3: Walk-forward expanding window (oos_yr 단위 refit)\n")
cat("  M4 LSTM: Skipped (keras3/torch not available)\n")

sink()
cat(sprintf("[saved] Summary report -> %s\n", report_path))

elapsed <- difftime(Sys.time(), t0, units="mins")
cat(sprintf("\n[done] Stress analysis complete. Elapsed: %.1f minutes\n", elapsed))
gc()
