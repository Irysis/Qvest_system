# S2 — 월간 패널 + 무효화 조항 판정(INV-5/INV-3/INV-1) + 착수 검정력 게이트(INV-4)
#  ★순서 강제(handoff.next_steps): (0) INV-4  (1) INV-3 + INV-5  (2) INV-1  — a2/a6 을 읽기 전에 끝낸다.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_011")
t0 <- Sys.time()
S1 <- readRDS(file.path(OUT, "s1_weekly.rds"))
ME <- S1$ME; tk <- S1$tk; wk_grid <- S1$wk_grid

## -- 월간 raw 집계 (past return / turnover / size) : PIT = ME 시점 확정치 --
rl <- load_rawdata(use_cache = TRUE); RAW <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl); gc(verbose = FALSE)
if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date")) BM_DT[, Date := as.Date(Date)]
RAW <- RAW[Ticker %chin% tk & Date >= as.Date("1999-01-01")]
RAW[, ym := as.integer(format(Date, "%Y")) * 12L + as.integer(format(Date, "%m"))]
MO <- RAW[, .(Date_end = max(Date),
              cum_ret  = prod(1 + ifelse(is.finite(Ret), Ret, 0)),
              Vol_sum  = sum(Vol, na.rm = TRUE),
              Close_end = Close[which.max(Date)],
              Size_end  = Size[which.max(Date)]),
          by = .(Ticker, ym)]
setorder(MO, Ticker, ym)
MO[, est_sh := fifelse(is.finite(Size_end) & is.finite(Close_end) & Close_end > 0, Size_end / Close_end, NA_real_)]
MO[, to_m := fifelse(is.finite(est_sh) & est_sh > 0, Vol_sum / est_sh, NA_real_)]
MO[, PA := cumprod(cum_ret), by = Ticker]

ym_grid <- seq(min(MO$ym), max(MO$ym))
Tm <- length(ym_grid); Nm <- length(tk)
mkM <- function(v, fill = NA_real_) { M <- matrix(fill, Tm, Nm)
  M[cbind(match(MO$ym, ym_grid), match(MO$Ticker, tk))] <- v; M }
PAm <- mkM(MO$PA); TOm <- mkM(MO$to_m); SZm <- mkM(MO$Size_end)
shd <- function(M, n) { if (n == 0L) return(M)
  rbind(matrix(NA_real_, n, ncol(M)), M[seq_len(nrow(M) - n), , drop = FALSE]) }
r_1m     <- PAm / shd(PAm, 1L) - 1
r_12_2   <- shd(PAm, 1L) / shd(PAm, 12L) - 1
r_36_13  <- shd(PAm, 12L) / shd(PAm, 36L) - 1
avg_lag <- function(M, a, b) { S <- matrix(0, Tm, Nm); C <- matrix(0L, Tm, Nm)
  for (k in a:b) { x <- shd(M, k); ok <- is.finite(x); x[!ok] <- 0; S <- S + x; C <- C + ok }
  out <- S / pmax(C, 1L); out[C < ceiling((b - a + 1) * 0.5)] <- NA_real_; out }
vbar_1   <- shd(TOm, 1L)
vbar_12_2<- avg_lag(TOm, 2L, 12L)
vbar_36_13 <- avg_lag(TOm, 13L, 36L)
logsz    <- log(pmax(SZm, 1))

## -- 주간 g -> 월간 매핑 (design_constants #5) --
wk_of <- function(d) as.integer((as.numeric(d) + 3L) %/% 7L)
gi <- match(wk_of(ME) - 1L, wk_grid)               # m = w_d - 1
stopifnot(!any(is.na(gi)))
pick <- function(M) M[gi, , drop = FALSE]
G     <- pick(S1$G260);  G156 <- pick(S1$G156);  G364 <- pick(S1$G364)
Gc    <- pick(S1$G260c); GB   <- pick(S1$GBAR)
HIST  <- pick(S1$HIST);  HIST156 <- pick(S1$HIST156)
mi <- match(as.integer(format(ME, "%Y")) * 12L + as.integer(format(ME, "%m")), ym_grid)
pickM <- function(M) M[mi, , drop = FALSE]

## -- forward 수익 + 벤치 + 유동성 (계약 경유) --
ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(verbose = FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
returns_dt <- as.data.table(fwd$returns_dt); bench_dt <- as.data.table(fwd$bench_dt); liq_dt <- as.data.table(fwd$liq_dt)

## -- long panel 조립 --
long <- CJ(i = seq_along(ME), j = seq_along(tk))
P <- data.table(Date = ME[long$i], Ticker = tk[long$j],
                g = as.vector(G[cbind(long$i, long$j)]),
                g156 = as.vector(G156[cbind(long$i, long$j)]),
                g364 = as.vector(G364[cbind(long$i, long$j)]),
                gcls = as.vector(Gc[cbind(long$i, long$j)]),
                gbar = as.vector(GB[cbind(long$i, long$j)]),
                hist5 = as.vector(HIST[cbind(long$i, long$j)]),
                hist3 = as.vector(HIST156[cbind(long$i, long$j)]),
                r1  = as.vector(pickM(r_1m)[cbind(long$i, long$j)]),
                r122 = as.vector(pickM(r_12_2)[cbind(long$i, long$j)]),
                r3613= as.vector(pickM(r_36_13)[cbind(long$i, long$j)]),
                v1  = as.vector(pickM(vbar_1)[cbind(long$i, long$j)]),
                v122= as.vector(pickM(vbar_12_2)[cbind(long$i, long$j)]),
                v3613=as.vector(pickM(vbar_36_13)[cbind(long$i, long$j)]),
                s   = as.vector(pickM(logsz)[cbind(long$i, long$j)]))
P <- merge(P, S1$mem, by = c("Date","Ticker"))                       # 유니버스(PIT 시변)
P <- merge(P, liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
P <- merge(P, returns_dt[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
P[, liq_ok := is.na(adv) | adv >= 2e8]
cat(sprintf("[S2] panel %d rows | %d months | median names %.0f | liq_ok %.1f%%\n",
            nrow(P), uniqueN(P$Date), median(P[, .N, by = Date]$N), 100*mean(P$liq_ok)))

## ============================ INV-5 (표본 이탈률) ============================
att <- P[liq_ok == TRUE, .(n = .N, n_hist = sum(hist5, na.rm = TRUE),
                           n_g = sum(is.finite(g) & hist5)), by = Date]
att[, drop_rate := 1 - n_g / n]
INV5 <- list(median_drop_rate = median(att$drop_rate),
             mean_drop_rate = mean(att$drop_rate),
             p25 = as.numeric(quantile(att$drop_rate, .25)), p75 = as.numeric(quantile(att$drop_rate, .75)),
             first10 = att$drop_rate[1:10], last10 = tail(att$drop_rate, 10),
             threshold = 0.40,
             verdict = if (median(att$drop_rate) >= 0.40) "TRIGGERED_DOWNGRADE_TO_3Y" else "PASS")
cat(sprintf("[S2] INV-5 표본 이탈률 median %.4f (p25 %.3f p75 %.3f) -> %s\n",
            INV5$median_drop_rate, INV5$p25, INV5$p75, INV5$verdict))
G_ACTIVE <- if (INV5$verdict == "PASS") "g" else "g156"
HIST_ACT <- if (INV5$verdict == "PASS") "hist5" else "hist3"

## 유효 표본 정의(사전등록: 5년 이력 + 유동성 + g 가용)
P[, gU := get(G_ACTIVE)]; P[, histU := get(HIST_ACT)]
Q <- P[liq_ok == TRUE & histU == TRUE & is.finite(gU) & is.finite(r122) & is.finite(r1) &
       is.finite(r3613) & is.finite(v122) & is.finite(s)]
cat(sprintf("[S2] 회귀 유효표본 %d rows | %d months | median names %.0f\n",
            nrow(Q), uniqueN(Q$Date), median(Q[, .N, by = Date]$N)))

## ============================ INV-3 (배관 양성대조) ==========================
## g ~ r_1 + r_12:2 + r_36:13 + vbar_1 + vbar_12:2 + vbar_36:13 + s   (Table 1 Panel B 이식)
fm_run <- function(dt, yv, xv, minobs = 30L) {
  co <- dt[, {
    d <- .SD[stats::complete.cases(.SD)]
    if (nrow(d) < minobs) as.list(setNames(rep(NA_real_, length(xv) + 2L), c("(Intercept)", xv, "r2")))
    else { f <- stats::lm(stats::as.formula(paste(yv, "~", paste(xv, collapse = "+"))), data = d)
      cf <- stats::coef(f); v <- as.list(cf[c("(Intercept)", xv)]); v$r2 <- summary(f)$adj.r.squared; v }
  }, by = Date, .SDcols = c(yv, xv)]
  co
}
inv3 <- fm_run(Q, "gU", c("r1","r122","r3613","v1","v122","v3613","s"))
nwt <- function(x) .nw_t_mean(x[is.finite(x)], lag = 3L)
INV3 <- list(
  spec = "g ~ r_1M + r_12:2M + r_36:13M + Vbar_1M + Vbar_12:2M + Vbar_36:13M + log(size)",
  n_months = sum(is.finite(inv3$r122)),
  coef = sapply(c("r1","r122","r3613","v1","v122","v3613","s"), function(k) mean(inv3[[k]], na.rm = TRUE)),
  nw_t = sapply(c("r1","r122","r3613","v1","v122","v3613","s"), function(k) nwt(inv3[[k]])),
  adj_r2_mean = mean(inv3$r2, na.rm = TRUE),
  paper = list(a1 = 0.5527, a2 = 0.4907, a3 = 0.1771, a4 = -0.9159, a5 = -6.4051, a6 = -2.7843, a7 = 0.0504, R2adj = 0.5879))
INV3$sign_match <- list(
  past_returns_positive = all(INV3$coef[c("r1","r122","r3613")] > 0),
  past_turnover_negative = all(INV3$coef[c("v1","v122","v3613")] < 0),
  size_positive = INV3$coef["s"] > 0)
INV3$verdict <- if (INV3$sign_match$past_returns_positive && INV3$sign_match$past_turnover_negative &&
                    INV3$sign_match$size_positive) "REPRODUCED" else "PARTIAL_OR_FAIL"
cat("[S2] INV-3 coef:", paste(sprintf("%s=%.4f(t %.2f)", names(INV3$coef), INV3$coef, INV3$nw_t), collapse=" "), "\n")
cat(sprintf("[S2] INV-3 adjR2 %.4f (paper 0.5879) -> %s\n", INV3$adj_r2_mean, INV3$verdict))

## ============================ INV-1 (다중공선성) =============================
cc <- Q[, .(rho = suppressWarnings(stats::cor(gU, r122, method = "pearson")),
            rho_sp = suppressWarnings(stats::cor(rank(gU), rank(r122))), n = .N), by = Date]
vifg <- Q[, {
  d <- .SD[stats::complete.cases(.SD)]
  if (nrow(d) < 30L) NA_real_ else {
    r2 <- summary(stats::lm(gU ~ r1 + r122 + r3613 + v122 + s, data = d))$r.squared
    1 / max(1e-9, 1 - r2) }
}, by = Date, .SDcols = c("gU","r1","r122","r3613","v122","s")]$V1
INV1 <- list(rho_mean = mean(cc$rho, na.rm = TRUE), rho_median = median(cc$rho, na.rm = TRUE),
             rho_sd = sd(cc$rho, na.rm = TRUE), rho_spearman_mean = mean(cc$rho_sp, na.rm = TRUE),
             vif_g_mean = mean(vifg, na.rm = TRUE), vif_g_median = median(vifg, na.rm = TRUE),
             vif_g_p95 = as.numeric(quantile(vifg, .95, na.rm = TRUE)),
             paper_rho = list(mean = 0.5482, median = 0.5529, sd = 0.1250),
             threshold = list(abs_rho_bar = 0.85, vif = 10),
             verdict = if (abs(mean(cc$rho, na.rm = TRUE)) >= 0.85 || mean(vifg, na.rm = TRUE) >= 10)
                         "UNDETERMINED_NON_IDENTIFIED" else "PASS")
cat(sprintf("[S2] INV-1 rho_bar %.4f (med %.4f sd %.4f | paper 0.5482) | VIF(g) mean %.2f med %.2f -> %s\n",
            INV1$rho_mean, INV1$rho_median, INV1$rho_sd, INV1$vif_g_mean, INV1$vif_g_median, INV1$verdict))

## ==================== deflator (1) 해상도: 1M vs 1W forward IC ===============
ic_m <- Q[is.finite(Ret_1m), .(ic = suppressWarnings(stats::cor(gU, Ret_1m, method = "spearman")), n = .N), by = Date]
ic_m <- ic_m[n >= 30L]
# 주간 IC: g[m] vs RETW[m+1], 유니버스=직전 ME 멤버십+유동성
memk <- unique(P[liq_ok == TRUE, .(Date, Ticker)])
wk_end <- S1$wk_end; wkidx <- seq_along(wk_grid)
me_wk <- wk_of(ME)
GW <- S1$G260; RW <- S1$RETW; HW <- S1$HIST
ic_w <- rbindlist(lapply(seq_along(ME), function(i) {
  lo <- if (i == 1L) me_wk[i] - 3L else me_wk[i - 1L]
  hi <- me_wk[i] - 2L
  ws <- match(seq(max(lo, min(wk_grid)), max(hi, lo)), wk_grid); ws <- ws[!is.na(ws) & ws + 1L <= nrow(RW)]
  if (!length(ws)) return(NULL)
  tks <- memk[Date == ME[i], Ticker]; jj <- match(tks, tk); jj <- jj[!is.na(jj)]
  rbindlist(lapply(ws, function(m) {
    gg <- GW[m, jj]; rr <- RW[m + 1L, jj]; hh <- HW[m, jj]
    ok <- is.finite(gg) & is.finite(rr) & hh
    if (sum(ok) < 30L) return(NULL)
    data.table(wk = m, ic = stats::cor(gg[ok], rr[ok], method = "spearman"), n = sum(ok))
  }))
}))
DEF1 <- list(ic_1m_mean = mean(ic_m$ic, na.rm = TRUE), ic_1m_n = nrow(ic_m),
             ic_1w_mean = mean(ic_w$ic, na.rm = TRUE), ic_1w_n = nrow(ic_w),
             ratio_raw = mean(ic_m$ic, na.rm = TRUE) / mean(ic_w$ic, na.rm = TRUE))
cat(sprintf("[S2] deflator(1) IC_1M %.5f (n=%d) | IC_1W %.5f (n=%d) | ratio %.4f\n",
            DEF1$ic_1m_mean, DEF1$ic_1m_n, DEF1$ic_1w_mean, DEF1$ic_1w_n, DEF1$ratio_raw))

saveRDS(list(P = P, Q = Q, returns_dt = returns_dt, bench_dt = bench_dt, liq_dt = liq_dt,
             ME = ME, tk = tk, ym_grid = ym_grid, mi = mi, gi = gi,
             INV5 = INV5, INV3 = INV3, INV1 = INV1, DEF1 = DEF1, att = att,
             ic_m = ic_m, ic_w = ic_w, G_ACTIVE = G_ACTIVE),
        file.path(OUT, "s2_objects.rds"))
write_json(list(INV5 = INV5, INV3 = INV3, INV1 = INV1, DEF1 = DEF1),
           file.path(OUT, "s2_gates.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("[S2] done elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
