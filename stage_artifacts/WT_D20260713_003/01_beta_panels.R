# R19 / WT-D20260713_003 — Stage 1: β 패널 (OLS 252d rolling + Kalman dlm filtered, PIT)
# 출력: beta_monthly.parquet(Date,Ticker,beta_ols,beta_kalman) + beta_daily_filtered.parquet(hedge error용)
#       + kalman_kappa.json
suppressMessages({library(arrow); library(data.table); library(dlm)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE)
setDTthreads(2L)
OUT <- "stage_artifacts/WT_D20260713_003"

cat("[01] loading RAWDATA (col_select)...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Ret","BM_Ret","K200","KQ150","Size","Close","Vol")))
rd <- rd[Date >= as.Date("2004-06-01")]           # 252d 워밍업 여유
setorder(rd, Ticker, Date)
rd[, Date := as.Date(Date)]

# ── universe: K200 또는 KQ150 flag=1 인 종목만(compute 축소) ──
univ_tickers <- unique(rd[K200==1 | KQ150==1, Ticker])
cat(sprintf("[01] univ-ever tickers: %d\n", length(univ_tickers)))
rd <- rd[Ticker %in% univ_tickers]
rd <- rd[is.finite(Ret) & is.finite(BM_Ret)]

# month-end sig_dates (거래일 기준 각 달 마지막 Date)
rd[, ym := format(Date, "%Y-%m")]
me <- rd[, .(sig_date=max(Date)), by=ym][order(ym)]
sig_dates <- me[ym >= "2005-12" & ym <= "2026-05", sig_date]   # 워밍업 후
cat(sprintf("[01] sig_dates: %d (%s .. %s)\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

# ==========================================================================
# (A) OLS rolling 252d β at each month-end  — arm O control
# ==========================================================================
MIN_OBS <- 120L; WIN <- 252L
cat("[01] OLS rolling 252d β...\n")
ols_list <- vector("list", length(univ_tickers))
for (ti in seq_along(univ_tickers)) {
  tk <- univ_tickers[ti]
  sub <- rd[Ticker==tk, .(Date, Ret, BM_Ret)]
  if (nrow(sub) < MIN_OBS) next
  setorder(sub, Date)
  betas <- numeric(0); dts <- as.Date(character(0))
  for (sd in sig_dates) {
    sdd <- as.Date(sd, origin="1970-01-01")
    w <- sub[Date <= sdd]
    if (nrow(w) < MIN_OBS) next
    w <- tail(w, WIN)
    fit <- tryCatch(lm.fit(cbind(1, w$BM_Ret), w$Ret), error=function(e) NULL)
    if (is.null(fit)) next
    betas <- c(betas, fit$coefficients[2L]); dts <- c(dts, sdd)
  }
  if (length(betas)) ols_list[[ti]] <- data.table(Date=dts, Ticker=tk, beta_ols=betas)
}
beta_ols <- rbindlist(ols_list, use.names=TRUE)
cat(sprintf("[01] OLS β rows: %d\n", nrow(beta_ols)))

# ==========================================================================
# (B) Kalman time-varying β  — arm K
#   pooled κ = dW/dV : IS(2005..2011) 표본 종목 dlmMLE 로그비율 median
# ==========================================================================
IS_END <- as.Date("2011-12-31")
cat("[01] Kalman κ MLE (IS pooled)...\n")
set.seed(19)
# 표본: IS에서 obs 충분한 종목 40개
is_counts <- rd[Date<=IS_END, .N, by=Ticker][N>=500]
samp <- sample(is_counts$Ticker, min(40L, nrow(is_counts)))
buildTVreg <- function(parm, x) {
  # parm[1]=log(dV), parm[2]=log(dW). dlmModReg addInt=TRUE → 2 states (α, β) time-varying.
  # β만 시변: α state var 0으로 고정, β state var = dW.
  m <- dlmModReg(x, addInt=TRUE, dV=exp(parm[1]), dW=c(0, exp(parm[2])))
  m
}
kappas <- c()
for (tk in samp) {
  sub <- rd[Ticker==tk & Date<=IS_END, .(Ret, BM_Ret)][is.finite(Ret)&is.finite(BM_Ret)]
  if (nrow(sub) < 400) next
  v0 <- var(sub$Ret, na.rm=TRUE)
  fit <- tryCatch(dlmMLE(y=sub$Ret, parm=c(log(v0), log(v0*1e-3)),
                         build=function(p) buildTVreg(p, sub$BM_Ret),
                         control=list(maxit=100)),
                  error=function(e) NULL)
  if (is.null(fit) || fit$convergence!=0) next
  dV <- exp(fit$par[1]); dW <- exp(fit$par[2])
  if (is.finite(dV) && is.finite(dW) && dV>0) kappas <- c(kappas, dW/dV)
}
kappa <- median(kappas, na.rm=TRUE)
# 안전 clamp: 극단 방지 [1e-5, 1e-1]
kappa_raw <- kappa
kappa <- max(min(kappa, 1e-1), 1e-5)
cat(sprintf("[01] κ raw=%.3e clamped=%.3e (n=%d MLE fits)\n", kappa_raw, kappa, length(kappas)))
writeLines(jsonlite::toJSON(list(kappa=kappa, kappa_raw=kappa_raw, n_mle=length(kappas),
           IS_end=as.character(IS_END), model="dlmModReg addInt, β-only time-varying, dV per-stock, dW=κ·dV",
           pit="dlmFilter filtered only (no smoother)"), auto_unbox=TRUE, pretty=TRUE),
           file.path(OUT,"kalman_kappa.json"))

# per-stock Kalman filter (PIT: filtered β at each day, month-end 추출)
cat("[01] Kalman per-stock filter...\n")
kal_month <- vector("list", length(univ_tickers))
kal_daily <- vector("list", length(univ_tickers))
sig_set <- as.Date(sig_dates, origin="1970-01-01")
for (ti in seq_along(univ_tickers)) {
  tk <- univ_tickers[ti]
  sub <- rd[Ticker==tk, .(Date, Ret, BM_Ret)][is.finite(Ret)&is.finite(BM_Ret)]
  if (nrow(sub) < MIN_OBS) next
  setorder(sub, Date)
  dV <- var(sub$Ret[sub$Date<=IS_END], na.rm=TRUE)
  if (!is.finite(dV) || dV<=0) dV <- var(sub$Ret, na.rm=TRUE)
  if (!is.finite(dV) || dV<=0) next
  dW <- kappa*dV
  mod <- tryCatch(dlmModReg(sub$BM_Ret, addInt=TRUE, dV=dV, dW=c(0, dW)),
                  error=function(e) NULL)
  if (is.null(mod)) next
  filt <- tryCatch(dlmFilter(sub$Ret, mod), error=function(e) NULL)
  if (is.null(filt)) next
  # filtered state m: rows T+1 (incl prior at t0). β = 2nd column, drop prior row.
  bser <- as.numeric(filt$m[-1, 2L])
  bdt <- data.table(Date=sub$Date, Ticker=tk, beta_kalman=bser)
  # month-end value: 각 sig_date 이하 마지막 필터값
  bdt[, ym := format(Date,"%Y-%m")]
  me_k <- bdt[Date %in% sig_set | TRUE][, .SD[Date==max(Date)], by=ym]  # 각 달 마지막
  me_k <- me_k[Date %in% sig_set, .(Date, Ticker, beta_kalman)]
  if (nrow(me_k)) kal_month[[ti]] <- me_k
  # daily filtered (hedge-error 용) — 저장 축소: 2005+ 만
  kal_daily[[ti]] <- bdt[Date>=as.Date("2005-12-01"), .(Date, Ticker, beta_kalman)]
}
beta_kal <- rbindlist(kal_month, use.names=TRUE)
cat(sprintf("[01] Kalman β month rows: %d\n", nrow(beta_kal)))

# merge monthly panels
beta_m <- merge(beta_ols, beta_kal, by=c("Date","Ticker"), all=TRUE)
write_parquet(beta_m, file.path(OUT,"beta_monthly.parquet"))
# daily filtered kalman β + also need daily OLS β forward? For hedge error we use β̂_t (month-end) applied to next-month daily.
kal_daily_dt <- rbindlist(kal_daily, use.names=TRUE)
write_parquet(kal_daily_dt, file.path(OUT,"beta_kalman_daily.parquet"))
cat("[01] DONE. beta_monthly rows:", nrow(beta_m),
    " ols_only:", sum(is.na(beta_m$beta_kalman)),
    " kal_only:", sum(is.na(beta_m$beta_ols)),
    " both:", sum(!is.na(beta_m$beta_ols)&!is.na(beta_m$beta_kalman)),"\n")
cat(sprintf("[01] β_ols mean=%.3f sd=%.3f | β_kal mean=%.3f sd=%.3f\n",
    mean(beta_m$beta_ols,na.rm=T), sd(beta_m$beta_ols,na.rm=T),
    mean(beta_m$beta_kalman,na.rm=T), sd(beta_m$beta_kalman,na.rm=T)))
