suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
VOUT <- file.path(ROOT, "stage_artifacts/wt001_verify/stat_lens")
say <- function(fmt, ...) cat(sprintf(paste0("[A] ", fmt, "\n"), ...))

FILT <- c("D03_EWMA", "Q01_EB")

BASE  <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT base_panel nrow=%d ndates=%d  tuned nrow=%d ndates=%d", nrow(BASE), uniqueN(BASE$Date),
    nrow(TUNED), uniqueN(TUNED$Date))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","K200","KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d n_day=%d %s~%s (DAILY 실측)", nrow(RAW), uniqueN(RAW$Date),
    as.character(min(RAW$Date)), as.character(max(RAW$Date)))
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
rm(RAW); gc(verbose = FALSE)

fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]
say("INPUT returns_dt nrow=%d MONTHLY ndates=%d ; bench ndates=%d", nrow(returns_dt),
    uniqueN(returns_dt$Date), uniqueN(bench_dt$Date))

score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}
SC_M01 <- score_of("M01_PATHQ")
E <- merge(SC_M01, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score); E[, rk := seq_len(.N), by = Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
FZ <- merge(FZ, E[, .(Date, Ticker)], by = c("Date","Ticker"))
FZ[, q_rank := frank(fz) / .N, by = .(Date, F_)]
say("eligible %d행 / %d개월", nrow(E), uniqueN(E$Date))

# ---- F3 β 패널 재현 (run_wt122_measure.R 245-277 그대로) ----
RM <- merge(returns_dt, bench_dt, by = "Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L, i-60L):(i-1L)]]
  bb <- w[, {
    ok <- is.finite(Ret_1m) & is.finite(BM_Ret)
    if (sum(ok) >= 24L && var(BM_Ret[ok]) > 0) .(beta = cov(Ret_1m[ok], BM_Ret[ok])/var(BM_Ret[ok]), nb = sum(ok))
    else .(beta = NA_real_, nb = sum(ok))
  }, by = Ticker][is.finite(beta)]
  bb[, Date := dts[i]]
  beta_l[[i]] <- bb[, .(Date, Ticker, beta)]
}
BETA <- rbindlist(beta_l)
say("β 패널 %d행 / %d개월 (관측단위 = 종목-월, 각 β 는 trailing 60개월 중복창)", nrow(BETA), uniqueN(BETA$Date))

nwt <- function(x, lag) {
  x <- x[is.finite(x)]; fit <- lm(x ~ 1)
  as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3])
}
nwt_auto <- function(x) {
  x <- x[is.finite(x)]; fit <- lm(x ~ 1)
  as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, prewhite = FALSE, lag = NULL, adjust = FALSE))[1,3])
}

RESA <- list()
for (f in FILT) {
  D <- merge(FZ[F_ == f, .(Date, Ticker, fz, q_rank)], BETA, by = c("Date","Ticker"))
  s <- D[, .(b_top = median(beta[q_rank > 0.8]), b_med = median(beta),
             b_bot = median(beta[q_rank <= 0.2])), by = Date]
  s <- s[is.finite(b_top) & is.finite(b_med)][order(Date)]
  x <- s$b_top - s$b_med
  n <- length(x)
  ac <- as.numeric(acf(x, lag.max = 72, plot = FALSE)$acf)[-1]
  say("--- %s ---", f)
  say("복제: top β %.3f · 유니버스 중앙 %.3f · 차 %+.4f · n=%d개월  [원 산출 대조]",
      mean(s$b_top), mean(s$b_med), mean(x), n)
  say("계열 ACF: rho1=%.3f rho3=%.3f rho6=%.3f rho12=%.3f rho24=%.3f rho36=%.3f rho60=%.3f",
      ac[1], ac[3], ac[6], ac[12], ac[24], ac[36], ac[60])
  tt <- sapply(c(0,1,3,6,12,24,36,48,59,72), function(L) if (L==0) {
      as.numeric(t.test(x)$statistic) } else nwt(x, L))
  names(tt) <- paste0("lag", c(0,1,3,6,12,24,36,48,59,72))
  say("NW t by lag: %s", paste(sprintf("%s=%.2f", names(tt), tt), collapse="  "))
  say("자동 대역폭(Newey-West Andrews) t = %.2f", nwt_auto(x))
  # 유효표본: 분산팽창계수 (lag 59 기준)
  vif <- (tt["lag0"]/tt["lag59"])^2
  say("SE 팽창 (lag3 대비 lag59): %.2f배 · 유효 n ≈ %.1f (명목 %d)",
      abs(tt["lag3"]/tt["lag59"]), n/((tt["lag0"]/tt["lag59"])^2), n)
  # 비중복 부분표본 (60개월 간격)
  idx <- seq(1, n, by = 60)
  xs <- x[idx]
  say("비중복 부분표본(60개월 간격) n=%d  mean=%+.4f  단순 t=%.2f",
      length(xs), mean(xs), if (length(xs)>2) as.numeric(t.test(xs)$statistic) else NA_real_)
  # 이동블록 부트스트랩 (block=60)
  set.seed(7)
  L <- 60L; nb <- ceiling(n / L); bmeans <- numeric(2000)
  for (r in 1:2000) {
    st <- sample.int(n - L + 1L, nb, replace = TRUE)
    v <- unlist(lapply(st, function(j) x[j:(j+L-1L)]))[1:n]
    bmeans[r] <- mean(v)
  }
  say("이동블록 부트스트랩(L=60, B=2000): mean %+.4f · sd %.4f · t≈%.2f · P(>0)=%.3f",
      mean(bmeans), sd(bmeans), mean(x)/sd(bmeans), mean(bmeans > 0))
  RESA[[f]] <- list(series = x, dates = s$Date, n = n, mean = mean(x), acf = ac, t = tt,
                    t_auto = nwt_auto(x), boot_sd = sd(bmeans),
                    beta_top = mean(s$b_top), beta_univ = mean(s$b_med))
}
saveRDS(RESA, file.path(VOUT, "claimA_beta.rds"))
say("saved claimA_beta.rds")
