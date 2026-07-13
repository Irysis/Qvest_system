# R19 / WT-D20260713_003 — Stage 1b: κ 그리드 튜닝 (IS-only forward-hedge-error 최소화)
# 이유: 자유 dlmMLE κ=0.46(clamp 0.1)는 일별 노이즈 과적합(β_kal sd 0.92 ≫ OLS 0.40, 퇴화).
#       "칼만 튜닝"의 본질 = 적응속도 κ를 IS forward-hedge-error로 튜닝(chain 자격요건 ② IS-only 선택).
# 출력: kappa_grid_curve.json (κ→ IS/OOS hedge error 곡선) + beta_kalman_tuned.parquet (κ* month-end β)
suppressMessages({library(arrow); library(data.table); library(dlm)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
OUT <- "stage_artifacts/WT_D20260713_003"

cat("[01b] loading daily...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Ret","BM_Ret","K200","KQ150")))
rd <- rd[Date>=as.Date("2004-06-01")]; rd[, Date:=as.Date(Date)]
rd <- rd[is.finite(Ret)&is.finite(BM_Ret)]
univ <- unique(rd[K200==1|KQ150==1, Ticker]); rd <- rd[Ticker %in% univ]
setorder(rd, Ticker, Date)
rd[, ym := format(Date,"%Y-%m")]
me <- rd[, .(sig_date=max(Date)), by=ym][order(ym)]
sig_dates <- me[ym>="2005-12" & ym<="2026-05", sig_date]
sig_set <- as.Date(sig_dates)
sig_ym  <- format(sig_set,"%Y-%m"); next_ym <- c(sig_ym[-1], NA)
fwd_of  <- setNames(next_ym, sig_ym)               # sig_date의 달 → 다음달 ym

# pre-split by ticker (병목 제거)
cat("[01b] split by ticker...\n")
rd_by <- split(rd[,.(Ticker,Date,Ret,BM_Ret,ym)], by="Ticker", keep.by=FALSE)
IS_END <- as.Date("2011-12-31")

KGRID <- c(1e-5, 3e-5, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1)
# half-life 근사(local-level): hl ≈ ln(2)/(-ln(1-g)), g=(sqrt(q^2+4q)-q)/2
hl_of <- function(q){ g<-(sqrt(q^2+4*q)-q)/2; round(log(2)/(-log(1-g)),1) }

# 한 종목·한 κ: month-end β + 다음달 daily 헤지잔차 MSE(각 stock-month)
filt_one <- function(sub, kappa) {
  if (nrow(sub) < 120L) return(NULL)
  dV_is <- var(sub$Ret[sub$Date<=IS_END], na.rm=TRUE)
  if (!is.finite(dV_is)||dV_is<=0) dV_is <- var(sub$Ret,na.rm=TRUE)
  if (!is.finite(dV_is)||dV_is<=0) return(NULL)
  mod <- tryCatch(dlmModReg(sub$BM_Ret, addInt=TRUE, dV=dV_is, dW=c(0,kappa*dV_is)), error=function(e) NULL)
  if (is.null(mod)) return(NULL)
  f <- tryCatch(dlmFilter(sub$Ret, mod), error=function(e) NULL)
  if (is.null(f)) return(NULL)
  bser <- as.numeric(f$m[-1,2L])
  d <- data.table(Date=sub$Date, ym=sub$ym, Ret=sub$Ret, BM_Ret=sub$BM_Ret, beta=bser)
  # month-end β at sig_dates
  be <- d[Date %in% sig_set, .(Date, beta=beta[.N]), by=.(sig_ym=ym)]
  be <- d[Date %in% sig_set][order(Date)][, .(Date, beta)]
  be <- unique(be, by="Date")
  if (!nrow(be)) return(NULL)
  # forward hedge MSE: β̂_t applied to next-month daily
  be[, fwd := fwd_of[format(Date,"%Y-%m")]]
  mse <- vapply(seq_len(nrow(be)), function(i){
    fy <- be$fwd[i]; if (is.na(fy)) return(NA_real_)
    fw <- d[ym==fy]; if (nrow(fw)<10L) return(NA_real_)
    mean((fw$Ret - be$beta[i]*fw$BM_Ret)^2)
  }, numeric(1))
  list(betas=data.table(Date=be$Date, beta_kalman=be$beta),
       he=data.table(Date=be$Date, mse=mse))
}

curve <- list(); tuned_betas <- NULL; best_k <- NA; best_is <- Inf
for (kappa in KGRID) {
  t0 <- Sys.time()
  is_mse <- c(); oos_mse <- c()
  betas_all <- vector("list", length(rd_by)); nm <- names(rd_by)
  for (j in seq_along(rd_by)) {
    r <- filt_one(rd_by[[j]], kappa)
    if (is.null(r)) next
    r$betas[, Ticker := nm[j]]; betas_all[[j]] <- r$betas
    hh <- r$he[is.finite(mse)]
    is_mse  <- c(is_mse,  hh[Date<=IS_END, mse])
    oos_mse <- c(oos_mse, hh[Date> IS_END, mse])
  }
  ismean <- mean(is_mse, na.rm=TRUE); oosmean <- mean(oos_mse, na.rm=TRUE)
  curve[[sprintf("%.0e",kappa)]] <- list(kappa=kappa, half_life_days=hl_of(kappa),
        is_mean_mse=ismean, oos_mean_mse=oosmean, n_is=length(is_mse), n_oos=length(oos_mse))
  cat(sprintf("[01b] κ=%.0e hl=%.0fd IS_MSE=%.3e OOS_MSE=%.3e (%.1fs)\n",
      kappa, hl_of(kappa), ismean, oosmean, as.numeric(Sys.time()-t0,units="secs")))
  if (is.finite(ismean) && ismean<best_is) { best_is<-ismean; best_k<-kappa
    tuned_betas <- rbindlist(betas_all, use.names=TRUE) }
}
cat(sprintf("[01b] κ* (IS-min) = %.0e  half-life=%.0fd\n", best_k, hl_of(best_k)))
tuned_betas[, kappa_star := best_k]
write_parquet(tuned_betas, file.path(OUT,"beta_kalman_tuned.parquet"))
writeLines(jsonlite::toJSON(list(
    method="IS-only forward-hedge-error 최소화 κ 튜닝 (chain 자격요건 ② IS-only 선택)",
    is_window="2006..2011-12", grid=KGRID, kappa_star=best_k,
    kappa_star_half_life_days=hl_of(best_k),
    free_mle_kappa=0.4556, free_mle_note="자유 dlmMLE κ=0.46(clamp 0.1)는 일별 노이즈 과적합 → β_kal sd 0.92 ≫ OLS 0.40. IS-튜닝으로 교체.",
    curve=curve), auto_unbox=TRUE, pretty=TRUE, digits=6), file.path(OUT,"kappa_grid_curve.json"))
cat("[01b] DONE.\n")
