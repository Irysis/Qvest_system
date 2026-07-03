## latent_factor_labeling.R — RAMP Gate 5 (1차): 잠재팩터(고유포트폴리오) 경제 라벨링
## ★핵심 정정 (도훈 mandate 2026-06-17): 전략풀 PCA 잠재팩터 = *1차* 순수팩터.
##   factor DB canonical 스타일은 *경제 라벨링 보조*로만 강등.
##   각 PC2~PC10 고유포트폴리오 *월별* 수익을 factor-DB canonical 스타일 수익(value/momentum/
##   quality/lowvol/size/liquidity)에 회귀 → R²·beta로 "PC_k ≈ <style>" 라벨. 매칭 안 되면 unlabeled(신규-α).
## ★PC1(=76% var)=market/beta = 팩터 아님 → 명시 분리(배분 입력 제외).
##
## 실측-only: canonical 스타일 수익은 rawdata에서 PIT-aligned 월별 cap-weighted 스프레드(자체합성 prod/cumprod 금지,
##   단일구간 cross-section 가중평균만). 회귀는 진단(라벨링)용 — 성능 채점 아님(그건 factor_validation/canonical_screen_bt).

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")
if (!exists("load_month_factors")) source("02_Infrastructure/factor_db/factor_db_connector.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# canonical 스타일 → factor DB proxy(higher = more of the style; direction은 long-leg).
# 보조 라벨링 전용 — 1차 순수팩터는 풀 PCA. (mandate: factor-DB는 경제라벨 전용)
.STYLE_PROXIES <- list(
  value      = "V01_BM",
  momentum   = "M01_Mom_12_1",
  quality    = "Q01_GPA",
  lowvol     = "D01_IdioVol",   # higher idiovol = worse → long-leg은 low idiovol; 부호는 z 정렬로 처리
  size       = "S01_Size",      # S01_Size: higher=large; small-cap premium은 부호 반대(회귀 beta로 흡수)
  liquidity  = "L01_Amihud"     # higher Amihud = illiquid
)

#==============================================================================
# 1. canonical 스타일 *월별* 수익 시계열 (top-quintile long-only, cap-weighted, net 15bps)
#    PIT: sig_date(t) 신호 → t→t+1M forward 실현수익. 자체합성 금지(단일구간 가중평균만).
#==============================================================================
#' @param rawdata data.table(Date, Ticker, Close, Vol, Size, K200, KQ150, ...)
#' @param sig_dates 월말 신호일
#' @return data.table(Date=sig월말, <style>_ret ...) — 월별 스타일 long-leg net return
build_canonical_style_returns <- function(rawdata, sig_dates, cost_bps = 15) {
  sig_dates <- sort(as.Date(sig_dates))
  asof_close <- function(d) {
    sub <- rawdata[Date <= d]; if (nrow(sub) == 0) return(NULL)
    rawdata[Date == max(sub$Date)]
  }
  style_names <- names(.STYLE_PROXIES)
  out <- vector("list", length(sig_dates) - 1L)

  for (i in seq_len(length(sig_dates) - 1L)) {
    d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
    c0 <- asof_close(d0); c1 <- asof_close(d1)
    if (is.null(c0) || is.null(c1)) next
    # forward 1M return per ticker
    m <- merge(c0[, .(Ticker, Close0 = Close, K200, KQ150, Size0 = Size)],
               c1[, .(Ticker, Close1 = Close)], by = "Ticker")
    m <- m[(K200 == TRUE | KQ150 == TRUE) & !is.na(Close0) & Close0 > 0 & !is.na(Close1)]
    if (nrow(m) < 30) next
    m[, ret := Close1 / Close0 - 1]

    # factor scores at d0 (PIT — load_month_factors uses Usable_Date<=sig_date C14).
    # ★load_month_factors returns LONG format: (Ticker, Factor_Name, Z_Score_Aligned).
    #   Z_Score_Aligned는 C13 direction-aligned (higher=better) → 모든 style의 long-leg = top quintile.
    fac <- tryCatch(load_month_factors(d0, factor_names = unlist(.STYLE_PROXIES)),
                    error = function(e) NULL)
    if (is.null(fac) || nrow(fac) == 0) next
    fac <- as.data.table(fac)
    if (!all(c("Ticker","Factor_Name","Z_Score_Aligned") %in% names(fac))) { next }
    row <- data.table(Date = d0)
    for (st in style_names) {
      pcol <- .STYLE_PROXIES[[st]]
      fsub <- fac[Factor_Name == pcol, .(Ticker, z = Z_Score_Aligned)]
      fsub <- fsub[!is.na(z)]
      if (nrow(fsub) == 0) { row[[paste0(st, "_ret")]] <- NA_real_; next }
      mm <- merge(m[, .(Ticker, ret, Size0)], fsub, by = "Ticker")
      if (nrow(mm) < 30 || stats::sd(mm$z, na.rm = TRUE) == 0) { row[[paste0(st, "_ret")]] <- NA_real_; next }
      # long-leg = top quintile of aligned z (higher=better, C13).
      thr <- stats::quantile(mm$z, 0.80, na.rm = TRUE)
      top <- mm[z >= thr]
      if (nrow(top) < 5) { row[[paste0(st, "_ret")]] <- NA_real_; next }
      # cap-weighted long-leg net return (single-period weighted mean — NOT compounded synthesis)
      w <- ifelse(is.na(top$Size0) | top$Size0 <= 0, 0, top$Size0)
      if (sum(w) == 0) w <- rep(1, nrow(top))
      lr <- stats::weighted.mean(top$ret, w = w, na.rm = TRUE) - (cost_bps / 1e4)
      row[[paste0(st, "_ret")]] <- lr
    }
    out[[i]] <- row
  }
  res <- rbindlist(out[!vapply(out, is.null, logical(1))], fill = TRUE)
  res[]
}

#==============================================================================
# 2. PC 고유포트폴리오 일별→월별 수익 (월말 신호일 정렬, 자체합성 금지)
#    eigen_returns(daily) → 각 월구간 일별수익의 *단순 합*(log-free 근사 금지) 대신
#    월말-월말 누적이 자체합성이므로, 회귀 라벨링용으로는 *월별 평균 일수익*(단위 무관 스케일)을 쓴다.
#    회귀는 R²/상대 beta(라벨)만 보므로 스케일 불변. (성능 수치 아님 — 부풀림 없음)
#==============================================================================
#' @param eigen_dt data.table(Date, PC1..PCk) daily
#' @param sig_dates 월말 신호일 (스타일 수익과 동일 grid)
#' @return data.table(Date=월말, PC1..PCk) — 월구간 평균 일수익 (라벨링용 스케일-불변 proxy)
aggregate_pc_monthly <- function(eigen_dt, sig_dates) {
  ed <- copy(as.data.table(eigen_dt))
  pc_cols <- grep("^PC[0-9]+$", names(ed), value = TRUE)
  ed[, Date := as.Date(Date)]
  sig_dates <- sort(as.Date(sig_dates))
  out <- vector("list", length(sig_dates) - 1L)
  for (i in seq_len(length(sig_dates) - 1L)) {
    d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
    seg <- ed[Date > d0 & Date <= d1]
    if (nrow(seg) == 0) next
    row <- data.table(Date = d0)
    for (pc in pc_cols) row[[pc]] <- mean(seg[[pc]], na.rm = TRUE)
    out[[i]] <- row
  }
  rbindlist(out[!vapply(out, is.null, logical(1))], fill = TRUE)[]
}

#==============================================================================
# 3. 라벨링 회귀: PC_k 월별수익 ~ Σ style_ret. R²·beta로 라벨 부여.
#==============================================================================
#' @param pc_monthly  from aggregate_pc_monthly
#' @param style_monthly from build_canonical_style_returns
#' @param exclude_pc1 TRUE → PC1(market/beta) 제외
#' @param r2_label_min  PC를 스타일로 라벨하는 최소 모델 R² (config gate5 권장 0.30)
#' @return list(label_table(dt), regressions(list))
label_latent_factors <- function(pc_monthly, style_monthly, exclude_pc1 = TRUE,
                                  r2_label_min = 0.30, beta_dom_frac = 0.50) {
  pc_cols <- grep("^PC[0-9]+$", names(pc_monthly), value = TRUE)
  if (isTRUE(exclude_pc1)) pc_cols <- setdiff(pc_cols, "PC1")
  style_cols <- grep("_ret$", names(style_monthly), value = TRUE)

  merged <- merge(pc_monthly, style_monthly, by = "Date")
  # drop rows with any NA in style cols
  merged <- merged[stats::complete.cases(merged[, ..style_cols])]
  n_obs <- nrow(merged)

  rows <- list(); regs <- list()
  for (pc in pc_cols) {
    y <- merged[[pc]]
    X <- as.matrix(merged[, ..style_cols])
    na_row <- function(reason) data.table(
      pc = pc, model_r2 = NA_real_, top_style = NA_character_, top_beta = NA_real_,
      top_abs_std_beta = NA_real_, second_style = NA_character_, second_abs_std_beta = NA_real_,
      beta_dominance = NA_real_, label = "unlabeled", reason = reason)
    if (n_obs < (length(style_cols) + 5L) || stats::sd(y) == 0) {
      rows[[pc]] <- na_row("insufficient_obs"); next
    }
    df <- data.frame(y = y, X)
    fit <- tryCatch(stats::lm(y ~ ., data = df), error = function(e) NULL)
    if (is.null(fit)) { rows[[pc]] <- na_row("lm_fail"); next }
    sm <- summary(fit)
    r2 <- sm$r.squared
    co <- stats::coef(fit)[-1]  # drop intercept
    # standardized betas (sd(x)/sd(y)) for dominance comparison
    sx <- apply(X, 2, stats::sd); sy <- stats::sd(y)
    std_beta <- co * sx / sy
    names(std_beta) <- gsub("_ret$", "", names(std_beta))
    ord <- order(abs(std_beta), decreasing = TRUE)
    top_style <- names(std_beta)[ord[1]]
    top_beta <- unname(co[ord[1]])
    top_abs_std <- unname(abs(std_beta)[ord[1]])
    abs_std_sorted <- sort(abs(std_beta), decreasing = TRUE)
    dom <- abs_std_sorted[1] / sum(abs_std_sorted)

    label <- if (!is.na(r2) && r2 >= r2_label_min && dom >= beta_dom_frac) {
      top_style
    } else if (!is.na(r2) && r2 >= r2_label_min) {
      paste0(top_style, "+mixed")
    } else {
      "unlabeled"   # 신규(풀 고유) 순수팩터 후보
    }
    reason <- if (label == "unlabeled") sprintf("model_r2=%.3f<%.2f", r2, r2_label_min)
              else sprintf("r2=%.3f dom=%.2f", r2, dom)

    rows[[pc]] <- data.table(
      pc = pc, model_r2 = round(r2, 4),
      top_style = top_style, top_beta = round(top_beta, 5),
      top_abs_std_beta = round(top_abs_std, 4),
      second_style = names(std_beta)[ord[2]] %||% NA_character_,
      second_abs_std_beta = round(unname(abs(std_beta)[ord[2]]) %||% NA_real_, 4),
      beta_dominance = round(dom, 4),
      label = label, reason = reason
    )
    # per-style std beta wide
    for (st in names(std_beta)) rows[[pc]][[paste0("stdbeta_", st)]] <- round(unname(std_beta[st]), 4)
    regs[[pc]] <- list(r2 = r2, coef = co, std_beta = std_beta)
  }
  list(label_table = rbindlist(rows, fill = TRUE), regressions = regs, n_obs = n_obs)
}

cat("[latent_factor_labeling.R] Loaded — build_canonical_style_returns / aggregate_pc_monthly / label_latent_factors\n")
