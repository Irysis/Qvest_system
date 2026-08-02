# =============================================================================
# run_wt022_decomp.R — WT-022 기전 분해 (Q-Lead 지시, 사후 진단 — 선택 비사용)
#   질문: 같은 MAX5 X10 필터가 WT-014 근사 프레임(+0.169 bare)에서 실코드(−0.113 bare)로
#         부호 반전한 원인 계층은? (선별폭 N / 가중 규칙 / TOphi 관성 / 점수 소스·하네스)
#   방법: 오늘 하네스(동일 alpha panel·raw 윈도우·liq·비용) 안에서 config 축만 바꿔
#         config별 base vs filt(X10) bare paired ΔIR·t 를 병렬 실측 → 부호 반전 축 귀속.
#   라벨: metric_type = realcode_recon_diag (bare, 종목계층). 선택/판정 비사용.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_022")
say <- function(fmt, ...) cat(sprintf(paste0("[wt022d] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ir_v <- function(a) mean(a) / sd(a) * sqrt(12)

# ── 입력 (본판과 동일) ────────────────────────────────────────────────────────
alpha_scores <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
alpha_scores[, Date := as.Date(Date)]; setkey(alpha_scores, Date, Ticker)
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Ret", "Size")))
raw[, Date := as.Date(Date)]; setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
MAX5 <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_014/alpha_scores.parquet"))
MAX5[, Date := as.Date(Date)]
MAX5 <- MAX5[is.finite(max5), .(d0 = Date, Ticker, max5)]
MAX5[, sig_ym := format(as.Date(format(d0, "%Y-%m-01")) %m+% months(1), "%Y-%m")]

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
cap_norm_size <- function(size_vec, ub = 0.20) {
  w <- size_vec; w[!is.finite(w) | w < 0] <- 0
  if (sum(w) <= 0) return(rep(1 / length(w), length(w)))
  w <- w / sum(w)
  for (it in 1:50) {
    if (all(w <= 0.2000001)) break
    w[w > ub] <- ub; rem <- 1 - sum(w); ix <- w < ub
    if (sum(ix) == 0 || rem <= 0) break
    w[ix] <- w[ix] + rem * w[ix] / sum(w[ix])
  }
  w[w > ub] <- ub; w / sum(w)
}

# ── 캐시 (본판 동일) ─────────────────────────────────────────────────────────
sig_dates <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
raw_dates <- sort(unique(raw$Date))
n_iter <- length(sig_dates) - 1L
cache <- vector("list", n_iter)
for (i in seq_len(n_iter)) {
  sig_label <- sig_dates[i]; next_sig <- sig_dates[i + 1L]
  idx_s <- findInterval(sig_label - 1, raw_dates) + 1L
  if (idx_s > length(raw_dates)) next
  start_d <- raw_dates[idx_s]
  idx_e <- findInterval(next_sig - 1, raw_dates) + 1L
  end_d <- if (idx_e > length(raw_dates)) max(raw_dates) else raw_dates[idx_e]
  panel_t <- alpha_scores[Date == sig_label & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) next
  liq <- raw[Date >= start_d - 30L & Date < start_d,
             .(A = mean(TradingAmt, na.rm = TRUE)), by = Ticker][A >= 2e8, Ticker]
  srets <- raw[Date > start_d & Date <= end_d,
               .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  size_d <- raw[Date < start_d & Date >= start_d - 15L & Ticker %in% panel_t$Ticker,
                .SD[which.max(Date)], by = Ticker, .SDcols = "Size"]
  cache[[i]] <- list(sig_label = sig_label, start_d = start_d, end_d = end_d,
                     panel_t = panel_t, liquid = liq, stock_rets = srets, size_d = size_d)
}
excl_x10 <- new.env(parent = emptyenv())
for (i in seq_len(n_iter)) {
  cc <- cache[[i]]; if (is.null(cc)) next
  ym_i <- format(cc$sig_label, "%Y-%m")
  m5 <- MAX5[sig_ym == ym_i, .(Ticker, max5)]
  if (nrow(m5) == 0L) next
  cand <- merge(cc$panel_t[, .(Ticker)], m5, by = "Ticker", all.x = TRUE)
  v <- cand$max5[is.finite(cand$max5)]
  if (length(v) < 30L) next
  thr <- quantile(v, 0.90, type = 7, names = FALSE)
  excl <- cand[is.finite(max5) & max5 >= thr, Ticker]
  if (length(excl)) assign(as.character(cc$sig_label), excl, envir = excl_x10)
}
paired_ym <- sort(unique(format(as.Date(paste0(unique(MAX5$sig_ym), "-01")), "%Y-%m")))

# ── config 가변 루프 ─────────────────────────────────────────────────────────
run_cfg <- function(filtered, n_top = 20L, weighting = "tilt", tophi = TRUE) {
  rows <- vector("list", n_iter)
  w_prev <- NULL
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    panel_t <- copy(cc$panel_t)
    regime_i <- panel_t$regime_state[1L]
    if (filtered) {
      key <- as.character(cc$sig_label)
      if (exists(key, envir = excl_x10, inherits = FALSE))
        panel_t <- panel_t[!Ticker %in% get(key, envir = excl_x10)]
    }
    setorder(panel_t, -score_eff)
    N_target <- min(n_top, nrow(panel_t))
    if (N_target < 5L) next
    picks <- panel_t[seq_len(N_target)]
    alpha_t <- setNames(picks$score_eff, picks$Ticker)
    tl <- intersect(names(alpha_t), cc$liquid)
    if (length(tl) < 5L) tl <- names(alpha_t)
    alpha_t <- alpha_t[tl]
    ub_use <- if (regime_i == "CRISIS") 0.10 else 0.20
    if (weighting == "tilt") {
      w <- tryCatch(
        linear_tilt_to_penalty_qd(alpha_t, 1.5, if (tophi) w_prev else NULL,
                                   if (tophi) 3.0 else 0, 0, ub_use),
        error = function(e) linear_tilt_qd(alpha_t, 1.5, 0, ub_use))
      names(w) <- names(alpha_t)
      w <- normalize_long_only(w, 0, ub_use, 1)
    } else if (weighting == "capnorm") {
      sz <- cc$size_d[match(names(alpha_t), Ticker), Size]
      w <- cap_norm_size(sz, ub = 0.20); names(w) <- names(alpha_t)
    } else {
      w <- setNames(rep(1 / length(alpha_t), length(alpha_t)), names(alpha_t))
    }
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
    rows[[i]] <- data.table(period_end = cc$end_d, ret = net)
    w_prev <- setNames(as.numeric(w), names(w))
  }
  out <- rbindlist(rows[!sapply(rows, is.null)])
  setorder(out, period_end); out
}

# 벤치 월윈도우
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
mk_bmw <- function(anchors) {
  bmw <- rep(NA_real_, length(anchors))
  for (i in 2:length(anchors)) {
    seg <- bm_x[index(bm_x) > anchors[i - 1] & index(bm_x) <= anchors[i]]
    if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
  }
  data.table(period_end = anchors, bmw = bmw)
}

configs <- list(
  realcode_tilt20_tophi  = list(n = 20L, w = "tilt",    tophi = TRUE),
  tilt25_tophi           = list(n = 25L, w = "tilt",    tophi = TRUE),
  tilt20_no_tophi        = list(n = 20L, w = "tilt",    tophi = FALSE),
  capnorm25_wt014_style  = list(n = 25L, w = "capnorm", tophi = FALSE),
  ew25                   = list(n = 25L, w = "ew",      tophi = FALSE)
)
decomp <- list()
for (nm in names(configs)) {
  cf <- configs[[nm]]
  b <- run_cfg(FALSE, cf$n, cf$w, cf$tophi)
  f <- run_cfg(TRUE,  cf$n, cf$w, cf$tophi)
  BW <- mk_bmw(b$period_end)
  D <- merge(merge(b[, .(period_end, rb = ret)], f[, .(period_end, rf = ret)],
                   by = "period_end"), BW, by = "period_end")
  D[, hold_ym := format(as.Date(format(period_end, "%Y-%m-01")) %m-% months(1), "%Y-%m")]
  D <- D[hold_ym %in% paired_ym & is.finite(bmw)]
  a_b <- D[, rb - bmw]; a_f <- D[, rf - bmw]
  decomp[[nm]] <- data.table(
    config = nm, n = nrow(D),
    base_port_t = round(nw_t(a_b), 3),
    base_ir = round(ir_v(a_b), 4),
    delta_ir = round(ir_v(a_f) - ir_v(a_b), 4),
    paired_t = round(nw_t(a_f - a_b), 3),
    mean_d_monthly = round(mean(a_f - a_b), 5))
  say("[%s] n=%d base PORT_t=%+.3f base IR=%.3f | ΔIR=%+.4f paired t=%+.3f",
      nm, nrow(D), decomp[[nm]]$base_port_t, decomp[[nm]]$base_ir,
      decomp[[nm]]$delta_ir, decomp[[nm]]$paired_t)
}
DD <- rbindlist(decomp)
fwrite(DD, file.path(OUT, "wt022_decomp_table.csv"))
saveRDS(DD, file.path(OUT, "wt022_decomp.rds"))
say("저장: wt022_decomp_table.csv / wt022_decomp.rds")
