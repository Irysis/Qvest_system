# valmom_ortho_check.R - orthogonality + OOS retention for STR_AS_20260605_221011_31932 (valmom AMP2013)
# A-task: correlate valmom monthly active return vs STR_1715 (+ high-grade modules) monthly active;
#         compute OOS retention of active Sharpe (IS ~2015 vs OOS 2016+).
# PowerShell + Rscript -e "source(...)" only. No lookahead: uses realized returns only.

suppressPackageStartupMessages({ library(data.table); library(xts); library(jsonlite) })

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")

# ---- helper: daily Strategy_Ret -> monthly compounded return (PerformanceAnalytics-equivalent via apply.monthly is fine,
#      but we compound within each calendar month) ----
to_monthly_ret <- function(dt) {
  # dt: data.table(Date, Ret)
  dt <- copy(dt)[is.finite(Ret)]
  dt[, ym := format(Date, "%Y-%m")]
  m <- dt[, .(ret = prod(1 + Ret) - 1, last_date = max(Date)), by = ym]
  setorder(m, ym)
  m[, .(ym, ret)]
}

# ---- valmom: daily Strategy_Ret + bm_xts (daily) -> monthly active ----
vm <- readRDS(file.path(PROJ, "04_Research/strategies/STR_AS_20260605_221011_31932/sim_result.rds"))
vm_dt <- as.data.table(vm$DAILY_NAV_DT)[, .(Date = as.Date(Date), Ret = Strategy_Ret)]
bm_xts <- vm$bm_xts
bm_dt  <- data.table(Date = as.Date(index(bm_xts)), Ret = as.numeric(coredata(bm_xts)))

vm_m  <- to_monthly_ret(vm_dt); setnames(vm_m, "ret", "str")
bm_m  <- to_monthly_ret(bm_dt); setnames(bm_m, "ret", "bm")
vm_act <- merge(vm_m, bm_m, by = "ym")
vm_act[, active := str - bm]          # valmom monthly active return
cat(sprintf("[valmom] monthly months=%d range=%s..%s\n", nrow(vm_act), min(vm_act$ym), max(vm_act$ym)))

# ---- STR_1715: monthly ret_net + benchmark_ret from contract CSVs (already monthly) ----
s1715_dir <- file.path(PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output")
pr  <- fread(file.path(s1715_dir, "03_period_returns.csv"))
bch <- fread(file.path(s1715_dir, "05_benchmark_returns.csv"))
pr[,  ym := format(as.Date(date), "%Y-%m")]
bch[, ym := format(as.Date(date), "%Y-%m")]
s1715 <- merge(pr[, .(ym, str = ret_net)], bch[, .(ym, bm = benchmark_ret)], by = "ym")
s1715[, active := str - bm]
cat(sprintf("[STR_1715] monthly months=%d range=%s..%s\n", nrow(s1715), min(s1715$ym), max(s1715$ym)))

# ---- correlate valmom active vs STR_1715 active (overlap months) ----
ov <- merge(vm_act[, .(ym, vm_act = active)], s1715[, .(ym, s_act = active)], by = "ym")
cor_1715 <- if (nrow(ov) > 12) cor(ov$vm_act, ov$s_act, use = "complete.obs") else NA_real_
cat(sprintf("[corr] valmom vs STR_1715 active: rho=%.4f (overlap months=%d)\n", cor_1715, nrow(ov)))

# ---- correlate vs high-grade C modules (score>=40) from module_catalog ----
cat_path <- file.path(PROJ, "06_Registry/module_catalog.json")
mods <- tryCatch(fromJSON(cat_path)$modules, error = function(e) NULL)
peer_cors <- list()
if (!is.null(mods)) {
  for (k in names(mods)) {
    if (identical(k, "STR_AS_20260605_221011_31932")) next
    sc <- tryCatch(mods[[k]]$meta$score, error = function(e) NULL)
    if (is.null(sc) || !is.finite(as.numeric(sc)) || as.numeric(sc) < 40) next
    sp <- mods[[k]]$sim_result_path
    rds <- file.path(PROJ, sp)
    if (!file.exists(rds)) next
    pm <- tryCatch(readRDS(rds), error = function(e) NULL)
    if (is.null(pm) || is.null(pm$DAILY_NAV_DT) || is.null(pm$bm_xts)) next
    p_dt <- as.data.table(pm$DAILY_NAV_DT)[, .(Date = as.Date(Date), Ret = Strategy_Ret)]
    p_bm <- data.table(Date = as.Date(index(pm$bm_xts)), Ret = as.numeric(coredata(pm$bm_xts)))
    pm_m <- merge(to_monthly_ret(p_dt), to_monthly_ret(p_bm), by = "ym", suffixes = c(".s", ".b"))
    setnames(pm_m, c("ret.s", "ret.b"), c("str", "bm"))
    pm_m[, p_act := str - bm]
    o2 <- merge(vm_act[, .(ym, vm_act = active)], pm_m[, .(ym, p_act)], by = "ym")
    if (nrow(o2) > 12) {
      rho <- cor(o2$vm_act, o2$p_act, use = "complete.obs")
      peer_cors[[k]] <- list(rho = round(rho, 4), score = as.numeric(sc), overlap = nrow(o2))
      cat(sprintf("[corr] valmom vs %s (score %.1f) active: rho=%.4f (overlap=%d)\n", k, as.numeric(sc), rho, nrow(o2)))
    }
  }
}

# ---- OOS retention: IS = months <= 2015-12, OOS = >= 2016-01. Active Sharpe (monthly, annualized) ----
ann <- sqrt(12)
act_sharpe <- function(x) { x <- x[is.finite(x)]; s <- sd(x); if (!is.finite(s) || s <= 0) return(NA_real_); mean(x) / s * ann }
vm_act[, yr := as.integer(substr(ym, 1, 4))]
is_x  <- vm_act[yr <= 2015, active]
oos_x <- vm_act[yr >= 2016, active]
sr_is  <- act_sharpe(is_x)
sr_oos <- act_sharpe(oos_x)
retention <- if (is.finite(sr_is) && abs(sr_is) > 1e-9) sr_oos / sr_is else NA_real_
cat(sprintf("[OOS] active Sharpe IS(<=2015,n=%d)=%.4f | OOS(>=2016,n=%d)=%.4f | retention=%.4f\n",
            length(is_x), sr_is, length(oos_x), sr_oos, retention))

# ---- 3-axis orthogonality verdict ----
carhart4_t <- 1.63   # provided: Carhart4 alpha t (momentum-controlled), borderline
ortho_corr_ok  <- is.finite(cor_1715) && abs(cor_1715) < 0.30
ortho_oos_ok   <- is.finite(retention) && retention >= 0.70
ortho_carhart_ok <- carhart4_t >= 1.96
verdict <- if (ortho_corr_ok && ortho_oos_ok && ortho_carhart_ok) "ORTHOGONAL" else "NOT_ORTHOGONAL"

out <- list(
  strategy_id = "STR_AS_20260605_221011_31932",
  paper = "Asness-Moskowitz-Pedersen 2013 value(BM)+momentum(12-1) z-combo decile",
  corr_vs_STR_1715 = round(cor_1715, 4),
  corr_overlap_months = nrow(ov),
  peer_corr_highgrade = peer_cors,
  oos_active_sharpe_IS = round(sr_is, 4),
  oos_active_sharpe_OOS = round(sr_oos, 4),
  oos_retention = round(retention, 4),
  oos_split = "IS<=2015 / OOS>=2016",
  carhart4_alpha_t = carhart4_t,
  axes = list(
    carhart4_t_ge_1p96 = ortho_carhart_ok,
    corr_lt_0p30       = ortho_corr_ok,
    oos_retention_ge_0p70 = ortho_oos_ok
  ),
  verdict = verdict,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
out_dir <- file.path(PROJ, "stage_artifacts/alpha_search")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "valmom_ortho_check.json")
write_json(out, out_path, auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("\n[VERDICT] %s | corr_STR1715=%.4f | OOS_retention=%.4f | Carhart4_t=%.2f\n",
            verdict, cor_1715, retention, carhart4_t))
cat(sprintf("[saved] %s\n", out_path))
