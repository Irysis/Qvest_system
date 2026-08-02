# =============================================================================
# run_fq127_eval.R — WT-D20260803_002 base-의존성 재판정 실측
#   T1: WT-009 P2 (M01_PATHQ vs M01_Mom_12_1 paired) — EW-25 주장 +2.028을
#       production rank-tilt(tilt20+TOphi)로 재측정
#   T2: WT-021 POS2 (PATHQ+V01_SECREL EW vs PATHQ single) — 동일 축
#   configs: ew25(parity) / tilt20_tophi(판정) / tilt25_tophi(diag) / capnorm25(diag)
#   하네스: run_wt022_decomp.R 가중 함수 verbatim 재사용. 사전등록: preregistration.json
#   라벨: 감사 라운드 — 어떤 arm도 채택 후보 아님. 자본 주장 없음.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_002")
say <- function(fmt, ...) cat(sprintf(paste0("[fq127] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ir_v <- function(a) mean(a) / sd(a) * sqrt(12)

# ── WT-022 가중 함수 verbatim ────────────────────────────────────────────────
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
    if (sum(ix) == 0 || rem <= 0 || sum(w[ix]) <= 0) break
    w[ix] <- w[ix] + rem * w[ix] / sum(w[ix])
  }
  w[w > ub] <- ub; w / sum(w)
}

# ── 입력 ─────────────────────────────────────────────────────────────────────
say("입력 로드…")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Ret", "Size", "K200", "KQ150")))
raw[, Date := as.Date(Date)]; setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)

BP <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/base_panel.parquet"))
BP[, Date := as.Date(Date)]
TP <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TP[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/size_panel.parquet"))
SZ[, Date := as.Date(Date)]

say("base_panel factors: %s", paste(unique(BP$Factor_Name), collapse = ", "))
say("tuned_panel factors: %s", paste(unique(TP$Factor_Name), collapse = ", "))

# arm 점수 패널 3종
S_M01   <- BP[Factor_Name == "M01_Mom_12_1" & is.finite(z), .(Date, Ticker, s = z)]
S_PATHQ <- TP[Factor_Name == "M01_PATHQ" & is.finite(score), .(Date, Ticker, s = score)]
S_SECR  <- TP[Factor_Name == "V01_SECREL" & is.finite(score), .(Date, Ticker, s = score)]
# POS2 = 월별 횡단면 z 등가중 평균 (WT-021 정의 재현, 사전등록 고정)
zx <- function(v) { m <- mean(v, na.rm = TRUE); sd0 <- sd(v, na.rm = TRUE)
                    if (!is.finite(sd0) || sd0 <= 0) return(rep(NA_real_, length(v)))
                    (v - m) / sd0 }
P2a <- copy(S_PATHQ)[, z1 := zx(s), by = Date][, .(Date, Ticker, z1)]
P2b <- copy(S_SECR)[, z2 := zx(s), by = Date][, .(Date, Ticker, z2)]
S_POS2 <- merge(P2a, P2b, by = c("Date", "Ticker"), all = TRUE)
S_POS2[, s := rowMeans(cbind(z1, z2), na.rm = TRUE)]
S_POS2 <- S_POS2[is.finite(s), .(Date, Ticker, s)]

arms <- list(M01 = S_M01, PATHQ = S_PATHQ, POS2 = S_POS2)
say("arm 커버리지: M01 %d개월 / PATHQ %d / POS2 %d — 월평균 이름수 %d / %d / %d",
    uniqueN(S_M01$Date), uniqueN(S_PATHQ$Date), uniqueN(S_POS2$Date),
    round(nrow(S_M01)/uniqueN(S_M01$Date)), round(nrow(S_PATHQ)/uniqueN(S_PATHQ$Date)),
    round(nrow(S_POS2)/uniqueN(S_POS2$Date)))

# ── 월 캐시 (WT-022 로직 — 신호월말 -> 차기 신호월말) ────────────────────────
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
  } else {
    end_d <- max(raw_dates)
  }
  if (end_d <= start_d) next
  liq <- raw[Date >= start_d - 30L & Date < start_d,
             .(A = mean(TradingAmt, na.rm = TRUE)), by = Ticker][A >= 2e8, Ticker]
  srets <- raw[Date > start_d & Date <= end_d,
               .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  sz_m <- SZ[Date == sig_label, .(Ticker, Size)]
  # ★ 유니버스 멤버십 K200∪KQ150 (WT-009 run_wt009_eval.R:52 방식 재현 — CF-03 오염 재발 방지)
  univ_d <- raw_dates[findInterval(sig_label, raw_dates)]
  univ <- raw[Date == univ_d & (K200 == TRUE | KQ150 == TRUE), Ticker]
  cache[[i]] <- list(sig_label = sig_label, start_d = start_d, end_d = end_d,
                     liquid = liq, stock_rets = srets, size_m = sz_m, univ = univ)
}
say("캐시: %d/%d 신호월 준비", sum(!sapply(cache, is.null)), n_iter)

# ── 포트 실행기 (liq 사전필터 -> top-N -> 가중) ──────────────────────────────
run_arm_cfg <- function(scores, n_top = 25L, weighting = "ew", tophi = FALSE) {
  rows <- vector("list", n_iter)
  w_prev <- NULL
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    st <- scores[Date == cc$sig_label]
    if (nrow(st) < 30L) { w_prev <- NULL; next }
    st <- st[Ticker %in% cc$univ & Ticker %in% cc$liquid]
    if (nrow(st) < n_top) { w_prev <- NULL; next }
    setorder(st, -s)
    picks <- st[seq_len(n_top)]
    alpha_t <- setNames(picks$s, picks$Ticker)
    if (weighting == "tilt") {
      w <- tryCatch(
        linear_tilt_to_penalty_qd(alpha_t, 1.5, if (tophi) w_prev else NULL,
                                   if (tophi) 3.0 else 0, 0, 0.20),
        error = function(e) linear_tilt_qd(alpha_t, 1.5, 0, 0.20))
      names(w) <- names(alpha_t)
      w <- normalize_long_only(w, 0, 0.20, 1)
    } else if (weighting == "capnorm") {
      szv <- cc$size_m[match(names(alpha_t), Ticker), Size]
      w <- cap_norm_size(szv, ub = 0.20); names(w) <- names(alpha_t)
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
    rows[[i]] <- data.table(sig_label = cc$sig_label, period_end = cc$end_d, ret = net, to = to)
    w_prev <- setNames(as.numeric(w), names(w))
  }
  out <- rbindlist(rows[!sapply(rows, is.null)])
  setorder(out, period_end); out
}

# 벤치 월윈도우
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
mk_bmw <- function(starts, ends) {
  bmw <- rep(NA_real_, length(ends))
  for (i in seq_along(ends)) {
    seg <- bm_x[index(bm_x) > starts[i] & index(bm_x) <= ends[i]]
    if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
  }
  bmw
}

configs <- list(
  ew25          = list(n = 25L, w = "ew",      tophi = FALSE),
  tilt20_tophi  = list(n = 20L, w = "tilt",    tophi = TRUE),
  tilt25_tophi  = list(n = 25L, w = "tilt",    tophi = TRUE),
  capnorm25     = list(n = 25L, w = "capnorm", tophi = FALSE)
)

say("12 run (3 arm x 4 config) 실측 시작…")
runs <- list()
for (an in names(arms)) for (cn in names(configs)) {
  cf <- configs[[cn]]
  key <- paste(an, cn, sep = "|")
  runs[[key]] <- run_arm_cfg(arms[[an]], cf$n, cf$w, cf$tophi)
  say("  [%s] n=%d", key, nrow(runs[[key]]))
}

# active 시계열 부여
act_of <- function(rt) {
  D <- copy(rt)
  # start = 해당 sig month의 start_d와 동일 재계산: bm 윈도우는 (직전 period_end, period_end]가 아니라
  # (start_d, end_d] 를 써야 arm 간 결측월 비대칭에 강건 — cache에서 start를 재조인
  starts <- sapply(seq_len(nrow(D)), function(k) {
    i <- which(sig_dates == D$sig_label[k]); cache[[i]]$start_d })
  D[, bmw := mk_bmw(as.Date(starts, origin = "1970-01-01"), D$period_end)]
  D <- D[is.finite(bmw)]
  D[, act := ret - bmw]
  D
}
ACT <- lapply(runs, act_of)

# ── paired 판정 ──────────────────────────────────────────────────────────────
paired_stats <- function(base_key, cand_key) {
  A <- ACT[[base_key]][, .(sig_label, a_b = act)]
  B <- ACT[[cand_key]][, .(sig_label, a_c = act)]
  M <- merge(A, B, by = "sig_label")
  d <- M$a_c - M$a_b
  list(n = nrow(M),
       base_port_t = round(nw_t(M$a_b), 3), cand_port_t = round(nw_t(M$a_c), 3),
       ir_base = round(ir_v(M$a_b), 4), ir_cand = round(ir_v(M$a_c), 4),
       delta_ir = round(ir_v(M$a_c) - ir_v(M$a_b), 4),
       paired_t_nw = round(nw_t(d), 3),
       mean_d_ann_pct = round(mean(d) * 12 * 100, 3))
}

tests <- list(
  T1 = list(base = "M01", cand = "PATHQ", orig = list(frame = "canonical EW-25 (WT-009)", paired_t = 2.028, mean_d_ann_pct = 2.934)),
  T2 = list(base = "PATHQ", cand = "POS2", orig = list(frame = "canonical EW-25 (WT-021)", paired_t = 0.37, mean_d_ann_pct = 1.06))
)
RES <- list()
for (tn in names(tests)) {
  tt <- tests[[tn]]
  per_cfg <- list()
  for (cn in names(configs)) {
    ps <- paired_stats(paste(tt$base, cn, sep = "|"), paste(tt$cand, cn, sep = "|"))
    per_cfg[[cn]] <- ps
    say("[%s|%s] n=%d ΔIR=%+.4f paired t=%+.3f (base t=%+.2f cand t=%+.2f) mean_d=%+.2f%%/yr",
        tn, cn, ps$n, ps$delta_ir, ps$paired_t_nw, ps$base_port_t, ps$cand_port_t, ps$mean_d_ann_pct)
  }
  RES[[tn]] <- list(pair = tt, by_config = per_cfg)
}

# turnover 진단
TO <- rbindlist(lapply(names(runs), function(k)
  data.table(run_key = k, to_annual = round(sum(runs[[k]]$to) / (nrow(runs[[k]]) / 12), 3))))

saveRDS(list(RES = RES, TO = TO, runs_meta = lapply(runs, nrow),
             sig_range = range(sig_dates)),
        file.path(OUT, "fq127_eval_results.rds"))

# flat 테이블
FLAT <- rbindlist(lapply(names(RES), function(tn) {
  rbindlist(lapply(names(RES[[tn]]$by_config), function(cn) {
    ps <- RES[[tn]]$by_config[[cn]]
    data.table(test = tn, config = cn, n = ps$n, base_port_t = ps$base_port_t,
               cand_port_t = ps$cand_port_t, delta_ir = ps$delta_ir,
               paired_t_nw = ps$paired_t_nw, mean_d_ann_pct = ps$mean_d_ann_pct)
  }))
}))
fwrite(FLAT, file.path(OUT, "fq127_readjudication_table.csv"))
say("저장 완료: fq127_eval_results.rds / fq127_readjudication_table.csv")
