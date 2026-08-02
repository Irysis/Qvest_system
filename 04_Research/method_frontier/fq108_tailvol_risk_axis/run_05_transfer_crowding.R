# =============================================================================
# FQ-108 run_05: (H3) 발생률→분산 전이 시험 + cap-tier 분해 + regime + crowding
#   - 전이: 동일 종목-월 패널에서 '사건 발생률 예측력' vs '2차 모멘트 예측력' 대조
#   - cap-tier: MEGA/MID/SMALL 별 위험예측 개선 (v8.3.1 risk 층 의무 필드)
#   - crowding_score_per_factor (research_philosophy P5, Acadian 2026)
#   Output: fq108_transfer.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq108_tailvol_risk_axis/fq108_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

CRASH_THR <- -0.20; BOOM_THR <- 0.20      # 사전 고정 (WT-020 계열 사건 정의)

SP <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_stock_pred.parquet")))
SP <- SP[arm == "A_base"]                  # 종목-월 재료는 arm 무관(동일) → 1벌만
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
L5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
L5[, ry := as.integer(gsub("-", "", return_ym))]
reg_map <- setNames(L5$regime, L5$ry)

SP <- SP[is.finite(realized_var) & realized_var > 0 & is.finite(ret_m)]
SP[, logrv := log(realized_var)]
SP[, crash := as.integer(ret_m <= CRASH_THR)]
SP[, boom  := as.integer(ret_m >= BOOM_THR)]
SP[, regime := reg_map[as.character(t_ym)]]
sz <- snap[, .(t_ym = ym, Ticker, size)]
SP <- merge(SP, sz, by = c("t_ym", "Ticker"), all.x = TRUE)
cat("[transfer] rows:", nrow(SP), " months:", uniqueN(SP$t_ym),
    " crash rate:", round(mean(SP$crash), 4), " boom rate:", round(mean(SP$boom), 4), "\n")

# =============================================================================
# (H3-a) 발생률 채널 — g35 상위분위 lift (월별 → FM-NW)
# =============================================================================
lift_by_month <- function(dt, evcol, scorecol, q = 0.20) {
  dt[, {
    s <- get(scorecol); e <- get(evcol)
    ok <- is.finite(s) & is.finite(e)
    if (sum(ok) < 40L) .(lift = NA_real_, base = NA_real_, top = NA_real_)
    else {
      s <- s[ok]; e <- e[ok]
      thr <- quantile(s, 1 - q, na.rm = TRUE)
      top <- mean(e[s >= thr]); base <- mean(e)
      .(lift = top - base, base = base, top = top)
    }
  }, by = t_ym]
}
L_crash <- lift_by_month(SP, "crash", "g35")
L_boom  <- lift_by_month(SP, "boom",  "g35")
fm_crash <- fm_nw_t(L_crash$lift); fm_boom <- fm_nw_t(L_boom$lift)
cat(sprintf("[occurrence] crash lift %.4f (NW t %.2f) | boom lift %.4f (NW t %.2f) | base %.4f\n",
            fm_crash$mean, fm_crash$t, fm_boom$mean, fm_boom$t, mean(L_crash$base, na.rm = TRUE)))

# 잔여 채널: xv(현행 Σ 대각) 통제 후, s63(단기 vol 레벨) 통제 후에도 lift 가 남는가
resid_lift <- function(dt, evcol, ctrl) {
  dt[, {
    ok <- is.finite(g35) & is.finite(get(ctrl)) & is.finite(get(evcol))
    if (sum(ok) < 40L) .(lift = NA_real_)
    else {
      gg <- g35[ok]; cc <- get(ctrl)[ok]; ee <- get(evcol)[ok]
      r <- residuals(lm(gg ~ cc))
      thr <- quantile(r, 0.80)
      .(lift = mean(ee[r >= thr]) - mean(ee))
    }
  }, by = t_ym]
}
fm_crash_res_xv  <- fm_nw_t(resid_lift(SP, "crash", "xv")$lift)
fm_crash_res_s63 <- fm_nw_t(resid_lift(SP, "crash", "s63")$lift)

# =============================================================================
# (H3-b) 분산 채널 — 동일 g35 의 log-RV 설명력 (증분 R², 월별 → FM-NW)
# =============================================================================
var_channel <- SP[, {
  ok <- is.finite(logrv) & is.finite(xv) & is.finite(g35) & is.finite(s63)
  if (sum(ok) < 40L) .(r2_x = NA_real_, r2_xg = NA_real_, r2_xs = NA_real_,
                       r2_xsg = NA_real_, b_g_given_x = NA_real_, b_g_given_xs = NA_real_,
                       sp_g = NA_real_)
  else {
    y <- logrv[ok]; x <- xv[ok]; g <- g35[ok]; s <- s63[ok]
    r2 <- function(f) summary(f)$r.squared
    f1 <- lm(y ~ x); f2 <- lm(y ~ x + g); f3 <- lm(y ~ x + s); f4 <- lm(y ~ x + s + g)
    .(r2_x = r2(f1), r2_xg = r2(f2), r2_xs = r2(f3), r2_xsg = r2(f4),
      b_g_given_x = unname(coef(f2)["g"]), b_g_given_xs = unname(coef(f4)["g"]),
      sp_g = suppressWarnings(cor(g, y, method = "spearman")))
  }
}, by = t_ym]
fm_bg_x  <- fm_nw_t(var_channel$b_g_given_x)
fm_bg_xs <- fm_nw_t(var_channel$b_g_given_xs)
cat(sprintf("[variance] incr R2 (g|x) %.4f | (g|x,s63) %.6f | coef g|x FM-t %.2f | coef g|x,s63 FM-t %.2f\n",
            mean(var_channel$r2_xg - var_channel$r2_x, na.rm = TRUE),
            mean(var_channel$r2_xsg - var_channel$r2_xs, na.rm = TRUE),
            fm_bg_x$t, fm_bg_xs$t))

# 대칭 대조: 사건 발생률에서도 s63 통제 후 증분이 사라지는가 (동일 재료 판별)
transfer <- list(
  event_definition = sprintf("crash: ret_m <= %.2f / boom: ret_m >= %.2f (월간수익, 사전고정)", CRASH_THR, BOOM_THR),
  base_rates = list(crash = mean(SP$crash), boom = mean(SP$boom), n_stock_months = nrow(SP)),
  occurrence_channel = list(
    crash_lift_top20pct = fm_crash$mean, crash_lift_nw_t = fm_crash$t, n_months = fm_crash$n,
    boom_lift_top20pct  = fm_boom$mean,  boom_lift_nw_t  = fm_boom$t,
    crash_lift_resid_of_sigma_diag = fm_crash_res_xv$mean, crash_lift_resid_of_sigma_diag_t = fm_crash_res_xv$t,
    crash_lift_resid_of_rv63       = fm_crash_res_s63$mean, crash_lift_resid_of_rv63_t = fm_crash_res_s63$t),
  variance_channel = list(
    spearman_g35_logrv_median = median(var_channel$sp_g, na.rm = TRUE),
    r2_sigma_diag_only = mean(var_channel$r2_x, na.rm = TRUE),
    r2_plus_g35        = mean(var_channel$r2_xg, na.rm = TRUE),
    incr_r2_g35_given_sigma_diag = mean(var_channel$r2_xg - var_channel$r2_x, na.rm = TRUE),
    r2_plus_rv63       = mean(var_channel$r2_xs, na.rm = TRUE),
    incr_r2_rv63_given_sigma_diag = mean(var_channel$r2_xs - var_channel$r2_x, na.rm = TRUE),
    incr_r2_g35_given_sigma_diag_and_rv63 = mean(var_channel$r2_xsg - var_channel$r2_xs, na.rm = TRUE),
    coef_g35_given_x_fm_nw_t = fm_bg_x$t,
    coef_g35_given_x_and_rv63_fm_nw_t = fm_bg_xs$t)
)

# =============================================================================
# cap-tier 분해 (v8.3.1 의무) — 종목-레벨 위험예측 채널을 tier 별로
# =============================================================================
SP[, tier := {
  r <- frank(-size, ties.method = "first", na.last = "keep")
  fifelse(is.na(r), NA_character_, fifelse(r <= 50L, "MEGA", fifelse(r <= 150L, "MID", "SMALL")))
}, by = t_ym]
tier_rows <- list()
for (tv in c("MEGA", "MID", "SMALL")) {
  sub <- SP[tier == tv]
  if (nrow(sub) < 500L) next
  vc <- sub[, {
    ok <- is.finite(logrv) & is.finite(xv) & is.finite(g35) & is.finite(s63)
    if (sum(ok) < 20L) .(r2_x = NA_real_, r2_xg = NA_real_, r2_xs = NA_real_, r2_xsg = NA_real_)
    else { y <- logrv[ok]; x <- xv[ok]; g <- g35[ok]; s <- s63[ok]
      r2 <- function(f) summary(f)$r.squared
      .(r2_x = r2(lm(y ~ x)), r2_xg = r2(lm(y ~ x + g)),
        r2_xs = r2(lm(y ~ x + s)), r2_xsg = r2(lm(y ~ x + s + g))) }
  }, by = t_ym]
  lf <- lift_by_month(sub, "crash", "g35")
  fl <- fm_nw_t(lf$lift)
  tier_rows[[length(tier_rows) + 1L]] <- data.table(
    tier = tv, n_stock_months = nrow(sub),
    crash_rate = mean(sub$crash),
    crash_lift = fl$mean, crash_lift_nw_t = fl$t,
    r2_sigma_diag = mean(vc$r2_x, na.rm = TRUE),
    incr_r2_g35 = mean(vc$r2_xg - vc$r2_x, na.rm = TRUE),
    incr_r2_rv63 = mean(vc$r2_xs - vc$r2_x, na.rm = TRUE),
    incr_r2_g35_given_rv63 = mean(vc$r2_xsg - vc$r2_xs, na.rm = TRUE))
}
TIER <- rbindlist(tier_rows)
cat("\n===== cap-tier decomposition =====\n"); print(TIER)

# =============================================================================
# regime 분해
# =============================================================================
reg_rows <- list()
for (rv in unique(SP$regime[!is.na(SP$regime)])) {
  sub <- SP[regime == rv]
  if (nrow(sub) < 500L) next
  lf <- lift_by_month(sub, "crash", "g35"); fl <- fm_nw_t(lf$lift)
  vc <- sub[, {
    ok <- is.finite(logrv) & is.finite(xv) & is.finite(s63) & is.finite(g35)
    if (sum(ok) < 20L) .(r2_x = NA_real_, r2_xs = NA_real_, r2_xsg = NA_real_)
    else { y <- logrv[ok]; x <- xv[ok]; s <- s63[ok]; g <- g35[ok]
      r2 <- function(f) summary(f)$r.squared
      .(r2_x = r2(lm(y ~ x)), r2_xs = r2(lm(y ~ x + s)), r2_xsg = r2(lm(y ~ x + s + g))) }
  }, by = t_ym]
  reg_rows[[length(reg_rows) + 1L]] <- data.table(
    regime = rv, n_months = uniqueN(sub$t_ym), crash_rate = mean(sub$crash),
    crash_lift = fl$mean, crash_lift_nw_t = fl$t,
    incr_r2_rv63 = mean(vc$r2_xs - vc$r2_x, na.rm = TRUE),
    incr_r2_g35_given_rv63 = mean(vc$r2_xsg - vc$r2_xs, na.rm = TRUE))
}
REG <- rbindlist(reg_rows)
cat("\n===== regime decomposition =====\n"); print(REG)

# =============================================================================
# crowding_score_per_factor (research_philosophy P5, Acadian 2026)
# =============================================================================
crowd <- NULL; crowd_status <- "not_run"
try({
  source(file.path(ROOT, "02_Infrastructure/config.R"))
  source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
  source(file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))
  RAW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
  crows <- list()
  for (sd_chr in c("2016-05-31", "2021-05-31", "2026-05-29")) {
    lmf <- load_month_factors(as.Date(sd_chr), coverage_min = 0.05,
                              factor_names = c("D35_RealVol_63d", "D45_Downside_Dev", "D05_MaxRet"))
    fe <- as.data.table(lmf)[, .(Ticker, factor_name = Factor_Name, exposure = Z_Score_Aligned)]
    cs <- crowding_score_per_factor(fe, sig_date = as.Date(sd_chr), RAWDATA = RAW, top_n = 20L)
    crows[[length(crows) + 1L]] <- cbind(data.table(sig_date = sd_chr), as.data.table(cs))
  }
  crowd <- rbindlist(crows, fill = TRUE)
  crowd_status <- "ok"
  cat("\n===== crowding_score_per_factor =====\n"); print(crowd)
}, silent = FALSE)
if (is.null(crowd)) crowd_status <- "FAILED_see_log (라벨 명시 — 침묵 결손 아님)"

out <- list(
  id = "FQ-108", stage = "run_05_transfer_crowding",
  metric_type = "risk_forecast_accuracy_diagnostic",
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  transfer = transfer,
  cap_tier_decomposition = list(
    basis = "cap_w_and_ew_uni (포트 2종 = cap-w tilt 실 book + EW 대조로 이중기준 확보)",
    tier_rule = "월별 size rank: 1-50 MEGA / 51-150 MID / 151+ SMALL",
    tiers = TIER,
    note = "본 라운드는 alpha 기여가 아니라 '위험예측 정확도'의 tier 분해다 — alpha_share 필드는 해당 없음(alpha 산출물 없는 lane)."),
  regime_decomposition = REG,
  crowding_status = crowd_status,
  crowding_score_per_factor = crowd)
write_json(out, file.path(OUT_DIR, "fq108_transfer.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = 8, na = "null")
cat("\n[done] run_05\n")
