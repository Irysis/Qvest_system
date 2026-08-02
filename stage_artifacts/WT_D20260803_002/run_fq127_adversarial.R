# =============================================================================
# run_fq127_adversarial.R — Self-Adversarial C3 정량 반박 실측
#   concern: tilt20_tophi가 production의 CRISIS ub 0.10 국면 조건을 생략 — 부호가 바뀌나?
#   방법: unified_regime_signal의 CRISIS 라벨월에 ub 0.10 적용판으로 T1/T2 재측정
#   라벨: adversarial sensitivity — 판정 axis 아님
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_002")
say <- function(fmt, ...) cat(sprintf(paste0("[fq127a] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ir_v <- function(a) mean(a) / sd(a) * sqrt(12)
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0; w[w < lb] <- lb; w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) { n <- length(w); return(rep(target_sum / n, n)) }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub); w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) { w <- w * (target_sum / sum(w)); break }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}
linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}
linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")))
raw[, Date := as.Date(Date)]; setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
REG <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
regdcol <- intersect(c("Date", "date"), names(REG))[1]
REG[, Date := as.Date(get(regdcol))]
regccol <- intersect(c("Category", "regime", "category"), names(REG))[1]
REG_m <- REG[, .(Date, Cat = get(regccol))]
REG_m[, ym := format(Date, "%Y-%m")]
REG_ym <- REG_m[, .(Cat = Cat[which.max(Date)]), by = ym]
say("regime 라벨: %s", paste(names(table(REG_ym$Cat)), collapse = ","))

BP <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/base_panel.parquet"))
BP[, Date := as.Date(Date)]
TP <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TP[, Date := as.Date(Date)]
S_M01   <- BP[Factor_Name == "M01_Mom_12_1" & is.finite(z), .(Date, Ticker, s = z)]
S_PATHQ <- TP[Factor_Name == "M01_PATHQ" & is.finite(score), .(Date, Ticker, s = score)]
S_SECR  <- TP[Factor_Name == "V01_SECREL" & is.finite(score), .(Date, Ticker, s = score)]
zx <- function(v) { m <- mean(v, na.rm = TRUE); sd0 <- sd(v, na.rm = TRUE)
                    if (!is.finite(sd0) || sd0 <= 0) return(rep(NA_real_, length(v)))
                    (v - m) / sd0 }
P2a <- copy(S_PATHQ)[, z1 := zx(s), by = Date][, .(Date, Ticker, z1)]
P2b <- copy(S_SECR)[, z2 := zx(s), by = Date][, .(Date, Ticker, z2)]
S_POS2 <- merge(P2a, P2b, by = c("Date", "Ticker"), all = TRUE)
S_POS2[, s := rowMeans(cbind(z1, z2), na.rm = TRUE)]
S_POS2 <- S_POS2[is.finite(s), .(Date, Ticker, s)]
arms <- list(M01 = S_M01, PATHQ = S_PATHQ, POS2 = S_POS2)

sig_dates <- sort(unique(S_PATHQ$Date))
raw_dates <- sort(unique(raw$Date))
n_iter <- length(sig_dates)
cache <- vector("list", n_iter)
for (i in seq_len(n_iter)) {
  sig_label <- sig_dates[i]
  idx_s <- findInterval(sig_label - 1, raw_dates) + 1L
  if (idx_s > length(raw_dates)) next
  start_d <- raw_dates[idx_s]
  if (i < n_iter) {
    next_sig <- sig_dates[i + 1L]
    idx_e <- findInterval(next_sig - 1, raw_dates) + 1L
    end_d <- if (idx_e > length(raw_dates)) max(raw_dates) else raw_dates[idx_e]
  } else end_d <- max(raw_dates)
  if (end_d <= start_d) next
  liq <- raw[Date >= start_d - 30L & Date < start_d,
             .(A = mean(TradingAmt, na.rm = TRUE)), by = Ticker][A >= 2e8, Ticker]
  srets <- raw[Date > start_d & Date <= end_d,
               .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  univ_d <- raw_dates[findInterval(sig_label, raw_dates)]
  univ <- raw[Date == univ_d & (K200 == TRUE | KQ150 == TRUE), Ticker]
  yml <- format(sig_label, "%Y-%m")
  cat_i <- REG_ym[ym == yml, Cat]
  ub_i <- if (length(cat_i) == 1L && cat_i == "CRISIS") 0.10 else 0.20
  cache[[i]] <- list(sig_label = sig_label, start_d = start_d, end_d = end_d,
                     liquid = liq, stock_rets = srets, univ = univ, ub = ub_i)
}
say("CRISIS ub 0.10 적용 월: %d / %d", sum(sapply(cache, function(c) !is.null(c) && c$ub < 0.2)), n_iter)

run_tilt_regime <- function(scores, n_top = 20L) {
  rows <- vector("list", n_iter); w_prev <- NULL
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    st <- scores[Date == cc$sig_label]
    if (nrow(st) < 30L) { w_prev <- NULL; next }
    st <- st[Ticker %in% cc$univ & Ticker %in% cc$liquid]
    if (nrow(st) < n_top) { w_prev <- NULL; next }
    setorder(st, -s)
    picks <- st[seq_len(n_top)]
    alpha_t <- setNames(picks$s, picks$Ticker)
    w <- tryCatch(linear_tilt_to_penalty_qd(alpha_t, 1.5, w_prev, 3.0, 0, cc$ub),
                  error = function(e) linear_tilt_qd(alpha_t, 1.5, 0, cc$ub))
    names(w) <- names(alpha_t)
    w <- normalize_long_only(w, 0, cc$ub, 1)
    mr <- merge(data.table(ticker = names(w), wv = as.numeric(w)),
                cc$stock_rets, by.x = "ticker", by.y = "Ticker", all.x = TRUE)
    mr[is.na(stock_ret), stock_ret := 0]
    gross <- sum(mr$wv * mr$stock_ret)
    if (is.null(w_prev) || length(w_prev) == 0L) to <- 1.0 else {
      an <- union(names(w), names(w_prev))
      w1 <- setNames(rep(0, length(an)), an); w0 <- w1
      w1[names(w)] <- w; w0[names(w_prev)] <- w_prev
      to <- sum(abs(w1 - w0)) / 2
    }
    net <- gross - (15 / 1e4) * to * 2
    rows[[i]] <- data.table(sig_label = cc$sig_label, start_d = cc$start_d,
                            period_end = cc$end_d, ret = net)
    w_prev <- setNames(as.numeric(w), names(w))
  }
  out <- rbindlist(rows[!sapply(rows, is.null)]); setorder(out, period_end); out
}

bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
act_of <- function(D) {
  D[, bmw := vapply(seq_len(.N), function(k) {
    seg <- bm_x[index(bm_x) > start_d[k] & index(bm_x) <= period_end[k]]
    if (nrow(seg) > 0) as.numeric(Return.cumulative(seg)) else NA_real_ }, numeric(1))]
  D <- D[is.finite(bmw)]; D[, act := ret - bmw]; D
}
R <- lapply(arms, function(sc) act_of(run_tilt_regime(sc, 20L)))
pstat <- function(A, B) {
  M <- merge(A[, .(sig_label, a_b = act)], B[, .(sig_label, a_c = act)], by = "sig_label")
  d <- M$a_c - M$a_b
  list(n = nrow(M), delta_ir = round(ir_v(M$a_c) - ir_v(M$a_b), 4),
       paired_t_nw = round(nw_t(d), 3), mean_d_ann_pct = round(mean(d) * 12 * 100, 3))
}
res <- list(T1_regime_ub = pstat(R$M01, R$PATHQ), T2_regime_ub = pstat(R$PATHQ, R$POS2))
say("T1 tilt20+CRISIS_ub0.10: n=%d ΔIR=%+.4f t=%+.3f mean_d=%+.2f%%/yr",
    res$T1_regime_ub$n, res$T1_regime_ub$delta_ir, res$T1_regime_ub$paired_t_nw, res$T1_regime_ub$mean_d_ann_pct)
say("T2 tilt20+CRISIS_ub0.10: n=%d ΔIR=%+.4f t=%+.3f mean_d=%+.2f%%/yr",
    res$T2_regime_ub$n, res$T2_regime_ub$delta_ir, res$T2_regime_ub$paired_t_nw, res$T2_regime_ub$mean_d_ann_pct)
saveRDS(res, file.path(OUT, "fq127_adversarial_regime_ub.rds"))
say("저장: fq127_adversarial_regime_ub.rds")
