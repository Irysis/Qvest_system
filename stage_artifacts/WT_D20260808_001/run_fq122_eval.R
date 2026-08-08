# =============================================================================
# run_fq122_eval.R — FQ-122 (b) 하위분위 제외필터 한계기여 실측
#   사전등록: preregistration.json + preregistration_addendum.json (측정 전 고정)
#   (a) 타이브레이커 = F4 킬스위치로 측정 전 기각 — 본 스크립트에서 실행하지 않음
#
#   P1 (primary, powered) : 소비 구간(M01 rank 1~25 / 1~50) 내 조건부 정보 FM-NW
#   P2 (secondary)        : 제외필터 paired 한계기여 × {W1 EW25, W2 tilt25} 재구성 base
#   P2b (addendum §7b)    : × {W3 production 실코드 tilt20(parity gate), W4 prod EW20}
#   F2/F3                 : 주체(개인 순매수) / β-drag 반증 관측
#   가드                  : 항등식 · 플라시보 · lag1 · 회전 · dual-basis · 국면 상호작용
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/run_fq122_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(lubridate)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[fq122] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
nw_ci <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  fit <- lm(x ~ 1)
  se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)[1, 1]),
                 error = function(e) NA_real_)
  mean(x) + c(-1.96, 1.96) * se
}
ir_v <- function(a) mean(a) / sd(a) * sqrt(12)

# =============================================================================
# 0. 입력 실측 (첫 출력 = 입력 형태)
# =============================================================================
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
say("INPUT tuned_panel rows=%d · 관측단위 MONTHLY(월말) · %d월 · %s~%s",
    nrow(TUNED), uniqueN(TUNED$Date), as.character(min(TUNED$Date)), as.character(max(TUNED$Date)))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
SIG <- sort(unique(TUNED$Date)); sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/size_panel.parquet"))
size_dt[, Date := as.Date(Date)]
say("INPUT returns_dt rows=%d (Date=신호월말, Ret_1m=익월) · bench %d월 · liq %d행",
    nrow(returns_dt), nrow(bench_dt), nrow(liq_dt))

# eligible set
W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
           Date + Ticker ~ Factor_Name, value.var = "score")
W <- merge(W, UNIV, by = c("Date","Ticker"))
W <- merge(W, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
W <- W[is.na(adv) | adv >= 2e8]
W <- merge(W, returns_dt, by = c("Date","Ticker"), all.x = TRUE)
W <- merge(W, bench_dt, by = "Date", all.x = TRUE)
W[, act := Ret_1m - BM_Ret]
ELIG <- W[is.finite(M01_PATHQ)]
say("ELIGIBLE set rows=%d · %d월 · 월 평균 %.1f / 중앙 %d 종목",
    nrow(ELIG), uniqueN(ELIG$Date), nrow(ELIG)/uniqueN(ELIG$Date),
    ELIG[, .N, by = Date][, as.integer(median(N))])
ELIG[, rk_m01 := frank(-M01_PATHQ, ties.method = "first"), by = Date]
FACS <- c("D03_EWMA","Q01_EB")

# =============================================================================
# 1. P1 (PRIMARY) — 소비 구간 내 조건부 정보 (전표본 횡단면 FM)
# =============================================================================
say("── P1 (primary): 소비 구간 내 조건부 정보 FM-NW ──")
p1_rows <- list()
for (reg in c(25L, 50L)) for (f in FACS) {
  D <- ELIG[rk_m01 <= reg & is.finite(get(f)) & is.finite(act)]
  D[, xz := { s <- sd(get(f)); if (!is.finite(s) || s <= 0) NA_real_ else (get(f) - mean(get(f)))/s }, by = Date]
  sl <- D[is.finite(xz), { if (.N < 8L) .(b = NA_real_) else .(b = as.numeric(coef(lm(act ~ xz))[2])) }, by = Date]
  b <- sl$b[is.finite(sl$b)]
  ci <- nw_ci(b)
  p1_rows[[paste(reg,f)]] <- data.table(
    region = paste0("M01_rank1_", reg), factor = f, n_months = length(b),
    slope_monthly = mean(b), slope_ann_pct = 100*12*mean(b), t_nw = nw_t(b),
    ci_lo_ann_pct = 100*12*ci[1], ci_hi_ann_pct = 100*12*ci[2],
    obs_per_month = round(nrow(D)/uniqueN(D$Date), 1))
}
P1 <- rbindlist(p1_rows)
print(P1)
# 검정력 라벨 (해당 계열 자체 sd 사용)
P1[, `:=`(sd_series = NA_real_, power_verdict = NA_character_)]
for (i in seq_len(nrow(P1))) {
  reg <- as.integer(sub(".*_", "", P1$region[i])); f <- P1$factor[i]
  D <- ELIG[rk_m01 <= reg & is.finite(get(f)) & is.finite(act)]
  D[, xz := { s <- sd(get(f)); if (!is.finite(s) || s <= 0) NA_real_ else (get(f) - mean(get(f)))/s }, by = Date]
  sl <- D[is.finite(xz), { if (.N < 8L) .(b = NA_real_) else .(b = as.numeric(coef(lm(act ~ xz))[2])) }, by = Date]
  b <- sl$b[is.finite(sl$b)]
  v <- verdict_with_power(observed_t = P1$t_nw[i], observed_monthly = mean(b),
                          n = length(b), sd_monthly = sd(b), design = "full")
  P1$sd_series[i] <- sd(b); P1$power_verdict[i] <- v$verdict
}
say("P1 검정력 라벨:"); print(P1[, .(region, factor, slope_ann_pct, t_nw, sd_series, power_verdict)])

# =============================================================================
# 2. P2 — 제외필터 arm (재구성 base: W1 EW25 · W2 tilt25)
# =============================================================================
# 배제 집합: eligible set 내 팩터 가용분의 월별 하위 q 분위
excl_set <- function(f, q) {
  D <- ELIG[is.finite(get(f))]
  D[, thr := quantile(get(f), q, type = 7, na.rm = TRUE), by = Date]
  D[get(f) <= thr, .(Date, Ticker)]
}
score_base <- ELIG[, .(Date, Ticker, score = M01_PATHQ)]
apply_excl <- function(sc, ex) if (is.null(ex)) sc else
  sc[!ELIG[ex, on = .(Date, Ticker), .(Date, Ticker)], on = .(Date, Ticker)]

# ── W1: canonical_screen_bt (EW 25) ─────────────────────────────────────────
run_w1 <- function(ex, tag) {
  sc <- apply_excl(score_base, ex)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liq_dt, liq_min = 2e8, run_id = "WT-D20260808_001",
    strategy_id = paste0("FQ122_W1_", tag), diag_dual_basis = TRUE, size_dt = size_dt)
}
say("── W1 (재구성 base, EW25, canonical_screen_bt) ──")
w1 <- list(base = run_w1(NULL, "base"))
for (f in FACS) for (q in c(0.10, 0.20, 0.30))
  w1[[sprintf("%s_q%02d", f, round(q*100))]] <- run_w1(excl_set(f, q), sprintf("%s_q%02d", f, round(q*100)))
for (nm in names(w1)) {
  r <- w1[[nm]]; ew <- r$diag_ew_universe
  say("  %-18s PORT_t=%+.3f netSR=%+.3f IR=%+.3f TO=%.0f%%/yr n=%d | EWuni t=%+.2f",
      nm, r$portfolio_alpha_t_nw_lag3, r$net_sr %||% NA_real_, r$information_ratio %||% NA_real_,
      100*(r$turnover_annual %||% NA_real_), r$n_months, ew$portfolio_alpha_t_nw_lag3 %||% NA_real_)
}

paired_from_canon <- function(rb, rf) {
  # canonical_screen_bt$period_returns = data.table(date, ret_net, benchmark_ret)
  pb <- as.data.table(rb$period_returns); pf <- as.data.table(rf$period_returns)
  stopifnot(all(c("date","ret_net","benchmark_ret") %in% names(pb)))
  m <- merge(pb[, .(date, rb = ret_net, bm = benchmark_ret)],
             pf[, .(date, rf = ret_net)], by = "date")
  m[, `:=`(ab = rb - bm, af = rf - bm)]
  d <- m$af - m$ab; ci <- nw_ci(d)
  data.table(n = nrow(m), base_ir = ir_v(m$ab), filt_ir = ir_v(m$af),
    delta_ir = ir_v(m$af) - ir_v(m$ab),
    d_monthly = mean(d), d_ann_pct = 100*12*mean(d), paired_t = nw_t(d),
    ci_lo_ann_pct = 100*12*ci[1], ci_hi_ann_pct = 100*12*ci[2], sd_d = sd(d))
}

# ── W2: tilt 25 (가중 규칙 #2) ───────────────────────────────────────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0; w[w < lb] <- lb; w[w > ub] <- ub
  s <- sum(w); if (s <= 1e-12) return(rep(target_sum/length(w), length(w)))
  w <- w * (target_sum/s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12; if (!any(over)) break
    excess <- sum(w[over] - ub); w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (!length(free)) { w <- w * (target_sum/sum(w)); break }
    w[free] <- w[free] + excess * (w[free]/sum(w[free]))
  }
  w / sum(w) * target_sum
}
linear_tilt_qd <- function(a, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(a); if (N <= 1) return(rep(1, N))
  r <- rank(a, ties.method = "average"); centered <- (r - mean(r))/(N - 1)
  normalize_long_only(pmax(1 + lambda*2*centered, 1e-6)/sum(pmax(1 + lambda*2*centered, 1e-6)), lb, ub, 1)
}
linear_tilt_to_penalty_qd <- function(a, lambda = 1.5, w_prev = NULL, phi = 3.0, lb = 0, ub = 0.20) {
  wt <- linear_tilt_qd(a, lambda, lb, ub); names(wt) <- names(a)
  if (is.null(w_prev) || phi <= 0) return(wt)
  wp <- setNames(numeric(length(wt)), names(wt))
  cm <- intersect(names(wt), names(w_prev)); wp[cm] <- w_prev[cm]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * wt
  if (sum(wp) > 0) wp <- wp/sum(wp)
  bl <- phi/(1 + phi)
  normalize_long_only(bl*wp + (1 - bl)*wt, lb, ub, 1)
}
run_tilt_panel <- function(ex, top_n = 25L) {
  sc <- apply_excl(score_base, ex)
  sc <- merge(sc, ELIG[, .(Date, Ticker, Ret_1m, BM_Ret)], by = c("Date","Ticker"))
  dts <- sort(unique(sc$Date)); w_prev <- NULL; rows <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    d <- sc[Date == dts[i]]; setorder(d, -score)
    n <- min(top_n, nrow(d)); if (n < 5L) next
    p <- d[seq_len(n)]; a <- setNames(p$score, p$Ticker)
    w <- tryCatch(linear_tilt_to_penalty_qd(a, 1.5, w_prev, 3.0, 0, 0.20),
                  error = function(e) linear_tilt_qd(a, 1.5, 0, 0.20))
    names(w) <- names(a)
    rr <- p$Ret_1m; rr[!is.finite(rr)] <- 0
    gross <- sum(w * rr)
    traded <- if (is.null(w_prev)) 2 else {
      an <- union(names(w), names(w_prev))
      w1 <- setNames(rep(0, length(an)), an); w0 <- w1
      w1[names(w)] <- w; w0[names(w_prev)] <- w_prev; sum(abs(w1 - w0))
    }
    rows[[i]] <- data.table(date = dts[i], ret_net = gross - traded*15/1e4,
                            traded = traded, bm = p$BM_Ret[1])
    w_prev <- setNames(as.numeric(w), names(w))
  }
  out <- rbindlist(rows[!sapply(rows, is.null)]); setorder(out, date); out
}
paired_from_panel <- function(pb, pf) {
  m <- merge(pb[, .(date, rb = ret_net, bm)], pf[, .(date, rf = ret_net)], by = "date")
  m[, `:=`(ab = rb - bm, af = rf - bm)]
  d <- m$af - m$ab; ci <- nw_ci(d)
  data.table(n = nrow(m), base_ir = ir_v(m$ab), filt_ir = ir_v(m$af),
    delta_ir = ir_v(m$af) - ir_v(m$ab), d_monthly = mean(d), d_ann_pct = 100*12*mean(d),
    paired_t = nw_t(d), ci_lo_ann_pct = 100*12*ci[1], ci_hi_ann_pct = 100*12*ci[2], sd_d = sd(d))
}
say("── W2 (재구성 base, tilt25 λ1.5 φ3) ──")
w2_base <- run_tilt_panel(NULL)
say("  base n=%d 연회전 %.0f%%", nrow(w2_base), 100*mean(w2_base$traded)*12/2)
w2 <- list()
for (f in FACS) w2[[f]] <- run_tilt_panel(excl_set(f, 0.20))

# ── 결과표 (재구성 base) ─────────────────────────────────────────────────────
res_recon <- list()
for (f in FACS) for (q in c(0.10, 0.20, 0.30)) {
  k <- sprintf("%s_q%02d", f, round(q*100))
  r <- paired_from_canon(w1$base, w1[[k]])
  r[, `:=`(weighting = "W1_recon_ew25", factor = f, q = q,
           base_port_t = w1$base$portfolio_alpha_t_nw_lag3,
           filt_port_t = w1[[k]]$portfolio_alpha_t_nw_lag3,
           base_to = 100*(w1$base$turnover_annual %||% NA_real_),
           filt_to = 100*(w1[[k]]$turnover_annual %||% NA_real_))]
  res_recon[[paste("W1",k)]] <- r
}
for (f in FACS) {
  r <- paired_from_panel(w2_base, w2[[f]])
  r[, `:=`(weighting = "W2_recon_tilt25", factor = f, q = 0.20,
           base_port_t = nw_t(w2_base$ret_net - w2_base$bm), filt_port_t = NA_real_,
           base_to = 100*mean(w2_base$traded)*12/2, filt_to = 100*mean(w2[[f]]$traded)*12/2)]
  res_recon[[paste("W2", f)]] <- r
}
RECON <- rbindlist(res_recon, fill = TRUE)
RECON[, sign_agree := sign(delta_ir) == sign(paired_t)]
say("── 재구성 base 결과 ──")
print(RECON[, .(weighting, factor, q, n, delta_ir = round(delta_ir,4),
                d_ann_pct = round(d_ann_pct,3), paired_t = round(paired_t,3),
                ci = sprintf("[%+.2f, %+.2f]", ci_lo_ann_pct, ci_hi_ann_pct), sign_agree)])

saveRDS(list(P1 = P1, RECON = RECON, w1 = w1, w2_base = w2_base, w2 = w2),
        file.path(OUT, "fq122_part1.rds"))
say("저장: fq122_part1.rds")
