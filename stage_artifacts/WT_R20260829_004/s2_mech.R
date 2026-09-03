# S2 — F1(위험 예측가능성) · F2(성분 귀속) : 성과 이전 관문 + 국면/변동성 신호 시계열 산출
# 단일 측정 규율: arm 배터리 없음. A0(무오버레이 실투형 슬리브)는 대비 arm 이 아니라
#   F1/F2 가 검정하는 슬리브 그 자체이며 후보의 승계 좌표(2/20 cell4)다.
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))
P <- readRDS(file.path(OUT, "panel.rds"))
FACTORS <- P$FACTORS; fwd <- P$fwd; DAILY <- P$DAILY; BMD <- P$BMD; ME <- P$ME
LIQ_MIN <- 2e8; RV_WIN <- 126L; ANN_D <- 252

## -- 적격집합 (유동성 20d ADV t-1 >= 2e8) --
S <- merge(FACTORS[, .(Date, Ticker, score = Score)],
           fwd$liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
S <- S[is.na(adv) | adv >= LIQ_MIN][, adv := NULL]
setorder(S, Date, -score)
cat(sprintf("[S2] eligible rows %d · months %d · median names %.0f\n",
            nrow(S), uniqueN(S$Date), median(S[, .N, by=Date]$N)))

## -- A0 보유 (top-25 EW) + 홀딩월 매핑 --
TOPN <- 25L
H0 <- S[, .(Ticker = Ticker[seq_len(min(TOPN, .N))]), by = Date]
sigd <- sort(unique(H0$Date))
hmap <- data.table(sig = sigd[-length(sigd)], hs = sigd[-length(sigd)], he = sigd[-1])
hmap[, holding_ym := format(he, "%Y-%m")]

## -- 슬리브 일간 수익 (EW 일간 리밸 = BSC 데실 규약과 동형) --
DD <- copy(DAILY); setkey(DD, Date)
sleeve_daily <- rbindlist(lapply(seq_len(nrow(hmap)), function(i) {
  tk <- H0[Date == hmap$sig[i], Ticker]
  x <- DD[Date > hmap$hs[i] & Date <= hmap$he[i] & Ticker %chin% tk]
  if (!nrow(x)) return(NULL)
  x[, .(r = mean(Ret, na.rm = TRUE), n_names = .N), by = Date][, sig := hmap$sig[i]][]
}))
setorder(sleeve_daily, Date)
cat(sprintf("[S2] sleeve daily: %d days %s~%s · median names %.0f\n",
            nrow(sleeve_daily), min(sleeve_daily$Date), max(sleeve_daily$Date),
            median(sleeve_daily$n_names)))

## -- 월간 실현분산 (BSC2015 eq5 규약: 월 스케일 = 21 * mean(r^2)) --
sleeve_daily[, ym := format(Date, "%Y-%m")]
RVs <- sleeve_daily[, .(rv = 21 * mean(r^2), nd = .N, sig = sig[1]), by = ym][nd >= 12]
BMD[, ym := format(Date, "%Y-%m")]
RVm <- BMD[, .(rv_bm = 21 * mean(BM_Ret^2), nd_bm = .N), by = ym][nd_bm >= 12]
RV <- merge(RVs, RVm, by = "ym")[order(ym)]

## -- beta_t : 슬리브 vs 시장, 직전 126 거래일(월말 t 까지) --
SB <- merge(sleeve_daily[, .(Date, r)], BMD[, .(Date, BM_Ret)], by = "Date")
setorder(SB, Date)
beta_at <- function(d) {
  x <- SB[Date < d]
  if (nrow(x) < 60) return(NA_real_)
  x <- x[seq(max(1, nrow(x) - RV_WIN + 1), nrow(x))]
  as.numeric(stats::cov(x$r, x$BM_Ret) / stats::var(x$BM_Ret))
}
me_of_ym <- SB[, .(me = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
me_of_ym[, beta := vapply(me, beta_at, numeric(1))]
RV <- merge(RV, me_of_ym[, .(ym, me, beta)], by = "ym")[order(ym)]
RV[, mkt_comp := beta^2 * rv_bm]
RV[, idio := pmax(rv - mkt_comp, 1e-10)]
RV[, mkt_share := mkt_comp / rv]
cat(sprintf("[S2] RV months %d · median beta %.3f · median mkt_share %.3f\n",
            nrow(RV), median(RV$beta, na.rm=TRUE), median(RV$mkt_share, na.rm=TRUE)))

## -- OOS R^2 (BSC eq4: 역사평균 대비) — 확장창 walk-forward, C1 준수 --
oos_r2 <- function(y, x, min_obs = 60L) {
  n <- length(y); e_m <- rep(NA_real_, n); e_f <- rep(NA_real_, n)
  if (n <= min_obs) return(list(r2 = NA_real_, n_eval = 0L))
  for (t in seq.int(min_obs + 1L, n)) {
    yi <- y[seq_len(t-1L)]; xi <- x[seq_len(t-1L)]
    ok <- is.finite(yi) & is.finite(xi)
    if (sum(ok) < min_obs || !is.finite(x[t]) || !is.finite(y[t])) next
    fit <- stats::lm.fit(cbind(1, xi[ok]), yi[ok])
    pred <- as.numeric(fit$coefficients[1] + fit$coefficients[2] * x[t])
    e_f[t] <- y[t] - pred
    e_m[t] <- y[t] - mean(yi[ok])
  }
  k <- is.finite(e_f) & is.finite(e_m)
  list(r2 = 1 - sum(e_f[k]^2)/sum(e_m[k]^2), n_eval = sum(k))
}
RV[, y_next := shift(rv, -1L)]
X <- RV[is.finite(y_next) & is.finite(beta)]
f1 <- oos_r2(X$y_next, X$rv)
f1_log <- oos_r2(log(X$y_next), log(X$rv))
Xm <- copy(RVm)[order(ym)]; Xm[, y_next := shift(rv_bm, -1L)]; Xm <- Xm[is.finite(y_next)]
f1_mkt <- oos_r2(Xm$y_next, Xm$rv_bm)
f2 <- list(
  beta_sq      = oos_r2(X$y_next, X$beta^2),
  market_rv    = oos_r2(X$y_next, X$rv_bm),
  market_comp  = oos_r2(X$y_next, X$mkt_comp),
  sleeve_rv    = oos_r2(X$y_next, X$rv),
  idio_comp    = oos_r2(X$y_next, X$idio))

## -- 국면 신호 (PIT-clean, 산출만 — 적용은 하류) --
BMm <- BMD[, .(bm_close = data.table::last(BM_Close), me = max(Date)), by = ym][order(ym)]
# ★strict t-1: 신호일(월말) 자신의 종가를 쓰지 않는다 — 직전 거래일 종가로 24개월 누적을 잡는다.
BMm[, bm_close_pit := vapply(me, function(d) {
  x <- BMD[Date < d]; if (!nrow(x)) NA_real_ else x$BM_Close[nrow(x)] }, numeric(1))]
BMm[, cum24 := bm_close_pit / shift(bm_close_pit, 24L) - 1]
BMm[, I_B := as.integer(is.finite(cum24) & cum24 < 0)]
mvol <- vapply(BMm$me, function(d) {
  x <- BMD[Date < d]
  if (nrow(x) < 60) return(NA_real_)
  x <- x[seq(max(1, nrow(x) - RV_WIN + 1), nrow(x))]
  sqrt(ANN_D) * stats::sd(x$BM_Ret)
}, numeric(1))
BMm[, mkt_vol126 := mvol]
BMm[, vol_hi := {
  v <- mkt_vol126; out <- rep(NA_integer_, .N)
  for (i in seq_len(.N)) {
    h <- v[seq_len(i-1L)]; h <- h[is.finite(h)]
    if (length(h) >= 36 && is.finite(v[i])) out[i] <- as.integer(v[i] > stats::median(h))
  }
  out }]
BMm[, panic := as.integer(I_B == 1L & vol_hi == 1L)]
SIG <- BMm[, .(signal_ym = ym, signal_month_end = me, cum24_bm = cum24, I_B,
               mkt_vol126_ann = mkt_vol126, vol_hi, panic)]
SIG[, holding_ym := substr(format(as.Date(paste0(signal_ym, "-01")) + 32, "%Y-%m"), 1, 7)]
SIG[, holding_month_start := overlay_signal_cutoff(holding_ym)]
SIG[, used_cutoff := signal_month_end]   # 배타적 상한 — 신호는 Date < signal_month_end 만 사용(strict t-1)
assert_overlay_pit(SIG$used_cutoff[is.finite(SIG$panic)],
                   SIG$holding_month_start[is.finite(SIG$panic)], label = "regime_panic")
cat(sprintf("[S2][PIT] assert_overlay_pit PASS · panic %d/%d 월 (%.1f%%)\n",
            sum(SIG$panic, na.rm=TRUE), sum(is.finite(SIG$panic)), 100*mean(SIG$panic, na.rm=TRUE)))

## -- 종목단 예측 변동성 sigma_i (직전 126거래일, 월말 t 까지) — 단변량, 공분산 아님 --
setkey(DD, Ticker, Date)
sv <- rbindlist(lapply(sigd, function(d) {
  x <- DD[Date > (d - 260L) & Date < d]
  y <- x[, .(sd_i = stats::sd(Ret, na.rm = TRUE), n_i = .N), by = Ticker][n_i >= 60 & is.finite(sd_i)]
  y[, Date := d][, .(Date, Ticker, vol126_ann = sd_i * sqrt(ANN_D), n_i)]
}))
cat(sprintf("[S2] stock vol panel: %d rows · %d months\n", nrow(sv), uniqueN(sv$Date)))

saveRDS(list(S=S, H0=H0, hmap=hmap, sleeve_daily=sleeve_daily, RV=RV, SIG=SIG, sv=sv, SB=SB),
        file.path(OUT, "s2_objects.rds"))

res <- list(
  meta = list(wt_id="WT-R20260829_004", as_of="2026-08-29", metric_type="canonical_screen",
              liq_ruler=fwd$liq_ruler, liq_ruler_source=fwd$liq_ruler_source,
              rv_convention="BSC2015 eq5 — 월 스케일 21*mean(r^2), 슬리브 EW 일간수익",
              n_rv_months=nrow(RV), sleeve_median_names=median(sleeve_daily$n_names)),
  F1_risk_predictability = list(
    statement="실투형 무오버레이 슬리브 월간 실현분산의 확장창 AR(1) OOS R^2 <= 0 이면 조건화 대상 부재",
    oos_r2_level = f1$r2, n_eval = f1$n_eval, oos_r2_log = f1_log$r2,
    positive_control_market_ar1_oos_r2 = f1_mkt$r2, market_n_eval = f1_mkt$n_eval,
    us_anchor_bsc2015 = list(momentum_rv_ar1_oos_r2 = 0.5782, market_rv_ar1_oos_r2 = 0.3881,
                             note="BSC2015 롱숏 WML — 우리 롱온리 슬리브와 다른 대상. 앵커이지 목표 아님"),
    verdict = if (is.finite(f1$r2) && f1$r2 > 0) "PASS" else "FAIL"),
  F2_component_attribution = list(
    statement="특이성분 OOS R^2 > 시장성분 OOS R^2 여야 이 축이 시장변동성 타이밍이 아님",
    oos_r2 = lapply(f2, function(z) z$r2), n_eval = f2$idio_comp$n_eval,
    market_share_of_total_variance_median = median(RV$mkt_share, na.rm=TRUE),
    beta_median = median(RV$beta, na.rm=TRUE),
    us_anchor_bsc2015 = list(beta_sq=0.0533, market_rv=0.0670, market_comp=0.2087,
                             momentum_rv=0.4382, idio=0.4706, market_share_of_risk=0.23),
    verdict = if (is.finite(f2$idio_comp$r2) && is.finite(f2$market_comp$r2) &&
                  f2$idio_comp$r2 > f2$market_comp$r2) "PASS" else "FAIL"),
  regime_signal = list(
    definition="panic = I_B(직전24개월 누적 KOSPI200 < 0) AND vol_hi(직전126거래일 시장 실현변동성 > 확장창 중앙값, min 36개월 이력)",
    n_months = sum(is.finite(SIG$panic)), n_panic = sum(SIG$panic, na.rm=TRUE),
    panic_rate = mean(SIG$panic, na.rm=TRUE), n_IB = sum(SIG$I_B, na.rm=TRUE),
    pit = list(cutoff_rule="first-day-of-holding-month (overlay_signal_cutoff)",
               assert_overlay_pit="PASS",
               max_used_cutoff=as.character(max(SIG$used_cutoff, na.rm=TRUE)),
               note="신호는 신호일(월말) *직전 거래일*까지의 데이터만 사용(strict t-1) · 홀딩월 = 신호월+1 · anchor_date/realized_ym 미사용")))
write_json(res, file.path(OUT, "s2_mech.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")

cat("\n===== F1 =====\n")
cat(sprintf("sleeve AR(1) OOS R2 = %+.4f (n_eval=%d) | log %+.4f | market positive control %+.4f\n",
            f1$r2, f1$n_eval, f1_log$r2, f1_mkt$r2))
cat("===== F2 =====\n")
for (nm in names(f2)) cat(sprintf("  %-12s OOS R2 = %+.4f\n", nm, f2[[nm]]$r2))
cat(sprintf("  median market share of total variance = %.3f | median beta = %.3f\n",
            median(RV$mkt_share, na.rm=TRUE), median(RV$beta, na.rm=TRUE)))
cat(sprintf("F1 verdict=%s · F2 verdict=%s\n",
            res$F1_risk_predictability$verdict, res$F2_component_attribution$verdict))
