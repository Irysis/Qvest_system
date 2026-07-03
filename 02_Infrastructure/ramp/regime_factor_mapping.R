## regime_factor_mapping.R — RAMP Gate 5 (3차): 국면조건부 팩터(군) 매트릭스 (헌법 §3.5/§6.7)
## 각 팩터군(또는 PC) × 국면(soft) 조건부 수익/위험. ★no hard switch — soft probability 가중.
## 국면 = regime_engine_daily(9축 MRS) soft score (Category 라벨 + Regime_Score_smooth 연속).
##   conditional E[ret|regime]는 soft-membership 가중평균 + James-Stein 류 shrinkage(소표본 → 전체평균 수축).
## 산출: outputs/ramp/regime_factor_matrix.parquet.
##
## 실측-only: 조건부 수익은 잠재팩터 일별수익을 국면 membership으로 가중평균(단일구간, 자체합성 없음).

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

#==============================================================================
# 1. 국면 soft membership (no hard switch)
#    Category(이산 라벨)는 진단 group으로, Regime_Score_smooth(연속)는 soft weight 산출에 사용.
#==============================================================================
#' @param regime_dt data.table(Date, Category, Regime_Score_smooth, MSM_Crisis_Prob, ...)
#' @return data.table(Date, regime_group, w_crisis, w_neutral, w_risk_on) soft memberships [0,1] sum=1
build_regime_membership <- function(regime_dt) {
  rg <- copy(as.data.table(regime_dt)); rg[, Date := as.Date(Date)]
  # soft membership over 3 macro states from continuous smooth score + crisis prob.
  # Regime_Score_smooth: higher = more risk-on. crisis prob in [0,1].
  s <- rg$Regime_Score_smooth
  if (all(is.na(s))) s <- rep(50, nrow(rg))
  s_norm <- (s - stats::quantile(s, 0.05, na.rm = TRUE)) /
            (stats::quantile(s, 0.95, na.rm = TRUE) - stats::quantile(s, 0.05, na.rm = TRUE) + 1e-9)
  s_norm <- pmin(pmax(s_norm, 0), 1)
  cp <- rg$MSM_Crisis_Prob; cp[is.na(cp)] <- 0
  # soft weights: crisis from crisis prob; risk_on from s_norm; neutral = residual
  w_crisis  <- cp
  w_risk_on <- (1 - cp) * s_norm
  w_neutral <- (1 - cp) * (1 - s_norm)
  tot <- w_crisis + w_risk_on + w_neutral; tot[tot == 0] <- 1
  data.table(Date = rg$Date,
             regime_category = rg$Category %||% NA_character_,
             w_crisis  = w_crisis / tot,
             w_neutral = w_neutral / tot,
             w_risk_on = w_risk_on / tot)
}

#==============================================================================
# 2. 국면조건부 매트릭스: 각 PC(or group) × regime soft-weighted mean/vol/DD-proxy + shrinkage
#==============================================================================
#' @param eigen_dt data.table(Date, PC2..PCk) daily eigen returns (PC1 제외 권장)
#' @param membership from build_regime_membership
#' @param group_map optional data.table(pc, group_id, economic_label) — group 레벨 집계
#' @param min_eff_n soft effective-N 하한(미만 → shrink 강화)
#' @param shrink_target "grand_mean" (소표본 conditional을 전체평균으로 수축)
#' @return data.table(unit, regime, eff_n, cond_mean, cond_vol, cond_sharpe_ann, shrunk_mean, raw_mean)
build_regime_factor_matrix <- function(eigen_dt, membership, group_map = NULL,
                                       min_eff_n = 60, exclude_pc1 = TRUE,
                                       trading_days = 252) {
  ed <- copy(as.data.table(eigen_dt)); ed[, Date := as.Date(Date)]
  pc_cols <- grep("^PC[0-9]+$", names(ed), value = TRUE)
  if (isTRUE(exclude_pc1)) pc_cols <- setdiff(pc_cols, "PC1")
  mm <- merge(ed[, c("Date", pc_cols), with = FALSE], membership, by = "Date")
  regimes <- c("crisis", "neutral", "risk_on")
  wcol <- c(crisis = "w_crisis", neutral = "w_neutral", risk_on = "w_risk_on")

  rows <- list()
  for (pc in pc_cols) {
    x <- mm[[pc]]
    grand_mean <- mean(x, na.rm = TRUE)
    for (rg in regimes) {
      w <- mm[[wcol[rg]]]
      ok <- !is.na(x) & !is.na(w) & w > 0
      if (!any(ok)) next
      xw <- x[ok]; ww <- w[ok]
      sw <- sum(ww); eff_n <- (sw^2) / sum(ww^2)   # Kish effective sample size
      cond_mean <- sum(ww * xw) / sw
      cond_var <- sum(ww * (xw - cond_mean)^2) / sw
      cond_vol <- sqrt(cond_var)
      # James-Stein style shrink toward grand mean by effective N
      lam <- eff_n / (eff_n + min_eff_n)   # eff_n>>min_eff_n → trust conditional; small → shrink
      shrunk <- lam * cond_mean + (1 - lam) * grand_mean
      cond_sharpe_ann <- if (cond_vol > 0) (shrunk / cond_vol) * sqrt(trading_days) else NA_real_
      rows[[length(rows) + 1L]] <- data.table(
        unit = pc, regime = rg, eff_n = round(eff_n, 1),
        raw_cond_mean = cond_mean, shrunk_mean = shrunk, cond_vol = cond_vol,
        cond_sharpe_ann = cond_sharpe_ann, grand_mean = grand_mean,
        shrink_lambda = round(lam, 3),
        low_sample_flag = eff_n < min_eff_n
      )
    }
  }
  mat <- rbindlist(rows, fill = TRUE)

  # group-level aggregation (economic label) if group_map provided
  group_mat <- NULL
  if (!is.null(group_map)) {
    gmsrc <- as.data.table(group_map)
    grp_col <- if ("econ_group_id" %in% names(gmsrc)) "econ_group_id" else "group_id"
    gm <- gmsrc[, .(pc, group_id = get(grp_col), economic_label = dominant_style)]
    setnames(gm, "pc", "unit")
    j <- merge(mat, gm, by = "unit", all.x = TRUE)
    group_mat <- j[, .(
      n_pc = uniqueN(unit),
      shrunk_mean = mean(shrunk_mean, na.rm = TRUE),
      cond_vol = mean(cond_vol, na.rm = TRUE),
      cond_sharpe_ann = mean(cond_sharpe_ann, na.rm = TRUE),
      eff_n = mean(eff_n, na.rm = TRUE),
      low_sample_any = any(low_sample_flag)
    ), by = .(group_id, economic_label, regime)]
  }
  list(pc_matrix = mat[], group_matrix = group_mat)
}

cat("[regime_factor_mapping.R] Loaded — build_regime_membership / build_regime_factor_matrix (soft, no hard switch)\n")
