# hurst_rate_matched_overlay.R — regime 노출 어댑터 chain step 2 (arxiv:2607.19497, 2026-08-09).
# 사전등록: stage_artifacts/paper_recharge/prereg_hurst_rate_matched_20260809.json
#
# ★step 1(고정문턱 H>0.5) 실패 기전 1줄: 269개월 중 238개월(88.5%) 발화 → 상시 full 노출이라
#   bare 로 수렴(IR 1.457 vs bare 1.477 · MDD -0.4073 vs -0.4074). ΔIR +0.048 은 신호 가치가
#   아니라 **오버레이 제거 효과**였고, _x_book 의 ΔIR -0.027 · ΔMDD 0.0000 이 그것을 확인했다.
#   ⇒ 고칠 것은 신호가 아니라 **발화율**이다.
#
# ★재프레이밍: 문턱을 흔들면 sweep(DSR HARD 대상)이다. 대신 **발화율을 제약으로 고정**하고
#   그 제약 하에서 Hurst 가 기존 unified 앙상블보다 나은 달을 고르는지만 묻는다.
#   목표 발화율조차 상수로 두지 않는다 — unified 방어라벨(CRISIS∪CAUTION)의 **확장창 실현 발화율**에서
#   파생한다. 자유 파라미터 0개.
#
# ★PIT: ① H 창 = Date < first-day-of-holding-month
#        ② 백분위 분포 · 목표 발화율 = **직전 홀딩월까지의 값만**(확장창, C1 — full-sample 금지)
#        used_cutoff 는 월별로 신고하고 wrap_exposure_adapter 가 검사한다.

suppressMessages({ library(data.table); library(arrow) })

BENCH_PATH  <- ".cache/benchmark.parquet"
REGIME_PATH <- ".cache/unified_regime_signal.parquet"
WIN         <- 252L
EXP_FIRE    <- 0.70   # 기존 하네스 CAT_EXPOSURE CAUTION 재사용 (새 자유도 아님)
EXP_HOLD    <- 1.00
BURN_IN     <- 60L
MIN_OBS     <- 64L
DEFENSIVE   <- c("CRISIS", "CAUTION")

.hurst_rs <- function(x) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < MIN_OBS) return(NA_real_)
  ks <- unique(round(exp(seq(log(16), log(floor(n / 2)), length.out = 8L))))
  ks <- ks[ks >= 16L & ks <= floor(n / 2)]
  if (length(ks) < 3L) return(NA_real_)
  rs <- vapply(ks, function(k) {
    m <- floor(n / k)
    v <- vapply(seq_len(m), function(j) {
      seg <- x[((j - 1L) * k + 1L):(j * k)]
      z <- cumsum(seg - mean(seg)); s <- stats::sd(seg)
      if (!is.finite(s) || s <= 0) NA_real_ else (max(z) - min(z)) / s
    }, numeric(1))
    mean(v, na.rm = TRUE)
  }, numeric(1))
  ok <- is.finite(rs) & rs > 0
  if (sum(ok) < 3L) return(NA_real_)
  unname(stats::coef(stats::lm(log(rs[ok]) ~ log(ks[ok])))[2L])
}

exposure_schedule <- function(ctx) {
  pr <- as.data.table(ctx$periods)
  pr[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  setorder(pr, eval_date)
  pr[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]
  pr[, hold_ym := format(hold_start, "%Y-%m")]

  if (!file.exists(BENCH_PATH) || !file.exists(REGIME_PATH)) {
    cat("[HurstRateMatched] 벤치 또는 레짐 신호 부재 — 제외\n"); return(NULL) }
  bm <- as.data.table(read_parquet(BENCH_PATH))
  if (!all(c("Date", "BM_Ret") %in% names(bm))) { cat("[HurstRateMatched] 벤치 컬럼 결손 — 제외\n"); return(NULL) }
  bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- bm[is.finite(BM_Ret)]

  rg <- as.data.table(read_parquet(REGIME_PATH))[, .(ym = as.character(YM), Category = as.character(Category))]
  setorder(rg, ym)

  n <- nrow(pr)
  H <- rep(NA_real_, n); cut <- rep(as.Date(NA), n)
  for (i in seq_len(n)) {
    w <- bm[Date < pr$hold_start[i]]
    if (nrow(w) < MIN_OBS) { cut[i] <- pr$hold_start[i] - 1L; next }
    w <- tail(w, WIN)
    H[i] <- .hurst_rs(w$BM_Ret)
    cut[i] <- max(w$Date)
  }

  expo <- rep(EXP_HOLD, n); fired <- rep(FALSE, n); target <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i <= BURN_IN || !is.finite(H[i])) next
    past <- H[seq_len(i - 1L)]; past <- past[is.finite(past)]
    if (length(past) < BURN_IN) next
    # ★목표 발화율 = 확장창 unified 방어라벨 실현율 (직전 홀딩월까지만 — full-sample 금지)
    rg_past <- rg[ym < pr$hold_ym[i]]
    if (nrow(rg_past) < BURN_IN) next
    q <- mean(rg_past$Category %in% DEFENSIVE, na.rm = TRUE)
    if (!is.finite(q) || q <= 0 || q >= 1) next
    target[i] <- q
    thr <- stats::quantile(past, probs = q, names = FALSE, type = 7)
    if (H[i] <= thr) { expo[i] <- EXP_FIRE; fired[i] <- TRUE }
  }
  cut[is.na(cut)] <- pr$hold_start[is.na(cut)] - 1L

  realized <- mean(fired[(BURN_IN + 1L):n])
  tgt_mean <- mean(target, na.rm = TRUE)
  cat(sprintf("[HurstRateMatched] %d개월 · H 중앙값 %.3f · 발화 %d (%.1f%%) · 목표율 평균 %.1f%% · 평균노출 %.4f\n",
              n, stats::median(H, na.rm = TRUE), sum(fired), 100 * realized, 100 * tgt_mean, mean(expo)))
  # F3 배관 반증: 실현 발화율이 목표에서 5%p 초과 이탈하면 구현 결함 — 판정 무효이므로 호명한다.
  if (is.finite(tgt_mean) && abs(realized - tgt_mean) > 0.05)
    cat(sprintf("[HurstRateMatched] ★F3 위반 — 실현 발화율 %.1f%% vs 목표 %.1f%% (>5%%p 이탈). 구현 결함 의심, 판정 무효 처리할 것\n",
                100 * realized, 100 * tgt_mean))

  list(exposure = data.table(Date = pr$eval_date, exposure = expo), used_cutoff = cut)
}
