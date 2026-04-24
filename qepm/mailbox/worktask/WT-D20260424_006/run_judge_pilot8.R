# Judge Pilot 8 — Lockbox OOS + regime decomposition
# Opus 4.7 단독 판정
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(xts); library(zoo)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260424_006"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260424_006")

source(file.path(PROJECT_ROOT, "02_Infrastructure/validation/judge_oos_helper.R"))

cat("\n=== Pilot 8 Judge OOS Helper 실행 ===\n")
bt <- judge_oos_backtest(WT_ID)

cat("\n[LOCKBOX OOS SUMMARY]\n")
print(bt$comparison_table)

cat("\n[PERF FULL]\n"); print(bt$full_performance)
cat("\n[PERF TRAIN]\n"); print(bt$train_performance)
cat("\n[PERF VAL]\n"); print(bt$val_performance)
cat("\n[PERF LOCKBOX]\n"); print(bt$oos_performance)

cat("\n[ALPHA/IR FULL]\n"); print(bt$full_alpha)
cat("\n[ALPHA/IR LOCKBOX]\n"); print(bt$oos_alpha)

cat("\n[OOS_IS_RATIO]\n"); cat(bt$oos_is_ratio, "\n")

# 차트 생성
cat("\n=== 차트 생성 ===\n")
ch <- judge_generate_oos_charts(WT_ID, out_dir = file.path(STAGE_DIR))
cat("Full chart:", ch$full_chart_path, "\n")
cat("OOS chart:", ch$oos_chart_path, "\n")

# Lockbox regime decomposition 실행
cat("\n=== Lockbox Regime Decomposition ===\n")

# Lockbox 일별 수익률 추출
lockbox_dt <- bt$lockbox_dt  # full_nav[Date >= lockbox_start]
lockbox_dt[, ret := c(NA, diff(NAV)/head(NAV,-1))]
lockbox_dt <- lockbox_dt[!is.na(ret)]
cat("Lockbox days:", nrow(lockbox_dt), "\n")

# Regime signal load
regime_path <- file.path(PROJECT_ROOT, ".cache/unified_regime_signal.parquet")
if (!file.exists(regime_path)) {
  regime_path <- file.path(PROJECT_ROOT, ".cache/regime_signal.parquet")
}
if (file.exists(regime_path)) {
  regime_dt <- as.data.table(read_parquet(regime_path))
  setnames(regime_dt, tolower(names(regime_dt)))
  if ("date" %in% names(regime_dt)) regime_dt[, date := as.Date(date)]
  # 가능 컬럼: regime_category, score, category
  cat("Regime cols:", paste(names(regime_dt), collapse=","), "\n")
  cat("Regime rows:", nrow(regime_dt), "\n")

  # merge lockbox + regime forward-fill monthly→daily
  setorder(regime_dt, date)
  ld <- as.data.table(lockbox_dt)
  ld[, Date := as.Date(Date)]

  # 어떤 category 컬럼? 우선순위 regime_category > category
  cat_col <- intersect(c("regime_category","category","Regime"), names(regime_dt))[1]
  if (!is.na(cat_col)) {
    rg <- regime_dt[, .(date, category = get(cat_col))]
    ld <- rg[ld, on=.(date=Date), roll=TRUE]
    setnames(ld, "date", "Date")
  } else {
    ld[, category := "UNKNOWN"]
  }

  # regime별 SR/CAGR/MDD
  regime_stats <- list()
  cats <- c("RISK_ON","NEUTRAL","CAUTION","RISK_OFF","CRISIS")
  for (c in cats) {
    sub <- ld[category==c, ret]
    if (length(sub) < 5) {
      regime_stats[[c]] <- list(days=length(sub), days_pct=round(100*length(sub)/nrow(ld),2),
                                sr=NA, cagr=NA, mdd=NA)
      next
    }
    mu <- mean(sub, na.rm=TRUE); sig <- sd(sub, na.rm=TRUE)
    sr <- if (sig>0) mu/sig * sqrt(252) else NA
    cagr <- (prod(1+sub) ^ (252/length(sub)) - 1) * 100
    nav <- cumprod(1+sub)
    mdd <- min(nav/cummax(nav) - 1, na.rm=TRUE) * 100
    regime_stats[[c]] <- list(days = length(sub),
                              days_pct = round(100*length(sub)/nrow(ld),2),
                              sr = round(sr,4),
                              cagr = round(cagr,2),
                              mdd = round(mdd,2))
  }

  # BM도 동일 분해
  bm_ret_xts <- .joh_bm_to_ret(load_rawdata(use_cache=TRUE)$BM_DT, ld$Date)
  bm_dt <- data.table(Date = as.Date(index(bm_ret_xts)), bm_ret = as.numeric(bm_ret_xts))
  ld2 <- bm_dt[ld, on=.(Date)]
  regime_bm <- list()
  for (c in cats) {
    sub <- ld2[category==c, bm_ret]
    sub <- sub[!is.na(sub)]
    if (length(sub) < 5) { regime_bm[[c]] <- list(sr=NA, cagr=NA, mdd=NA); next }
    mu <- mean(sub); sig <- sd(sub)
    sr <- if (sig>0) mu/sig * sqrt(252) else NA
    cagr <- (prod(1+sub) ^ (252/length(sub)) - 1) * 100
    nav <- cumprod(1+sub)
    mdd <- min(nav/cummax(nav) - 1, na.rm=TRUE) * 100
    regime_bm[[c]] <- list(sr = round(sr,4), cagr = round(cagr,2), mdd = round(mdd,2))
  }

  cat("\n[REGIME STATS (STRATEGY)]\n")
  print(regime_stats)
  cat("\n[REGIME STATS (BM)]\n")
  print(regime_bm)

  # Active IR by regime
  active_ir_regime <- list()
  for (c in cats) {
    sub <- ld2[category==c]
    if (nrow(sub) < 5) { active_ir_regime[[c]] <- NA; next }
    active <- sub$ret - sub$bm_ret
    active <- active[!is.na(active)]
    if (length(active) < 5) { active_ir_regime[[c]] <- NA; next }
    mu <- mean(active); sig <- sd(active)
    ir <- if (sig>0) mu/sig*sqrt(252) else NA
    active_ir_regime[[c]] <- round(ir,4)
  }
  cat("\n[ACTIVE IR BY REGIME]\n"); print(active_ir_regime)

  # Save regime decomp
  regime_out <- list(
    wt_id = WT_ID,
    pilot_label = "Pilot 8 — MinVar_BetaSoft (gamma=0.5, beta_target=0.90) Judge Lockbox 4-regime",
    period = "Lockbox 2024-01-23 ~ 2026-01-23",
    n_days = nrow(ld),
    regime_stats = regime_stats,
    regime_bm = regime_bm,
    active_ir_regime = active_ir_regime,
    total_lockbox = list(
      sr = round(bt$oos_performance$Sharpe,4),
      cagr = round(bt$oos_performance$CAGR,2),
      mdd = round(bt$oos_performance$MDD,2),
      active_ir = round(bt$oos_alpha$IR,4),
      alpha_ann_pct = round(bt$oos_alpha$alpha_ann_pct,2)
    )
  )
  out_path <- file.path(STAGE_DIR, "lockbox_regime_decomposition.json")
  write_json(regime_out, out_path, pretty=TRUE, auto_unbox=TRUE, na="null")
  cat("\nSaved:", out_path, "\n")
} else {
  cat("regime signal not found, skip regime decomposition\n")
}

# lockbox OOS summary save
oos_summary <- list(
  wt_id = WT_ID,
  pilot = "Pilot 8",
  comparison = bt$comparison_table,
  full_perf = bt$full_performance,
  train_perf = bt$train_performance,
  val_perf = bt$val_performance,
  lockbox_perf = bt$oos_performance,
  full_alpha = bt$full_alpha,
  lockbox_alpha = bt$oos_alpha,
  oos_is_ratio = bt$oos_is_ratio,
  commission = bt$commission,
  ann_turnover = bt$ann_turnover_pct
)
write_json(oos_summary, file.path(STAGE_DIR, "lockbox_oos_summary.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("\nSaved lockbox_oos_summary.json\n")

cat("\n=== DONE ===\n")
