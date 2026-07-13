# R19 / WT-D20260713_003 — Stage 1c: κ 재선택 = metric_2(실현 β 예측오차) IS-min
# 이유: forward-hedge-MSE 튜닝은 idiosyncratic 지배로 퇴화(κ*→1e-1, hl 2d, β sd 0.92). β-vs-β 타겟으로 교체.
# 핵심 판정: 적응 칼만 β̂_t 가 stale 252d OLS 보다 실현 forward-252d β 를 잘 예측하는가?
# 출력: kappa_metric2_curve.json + beta_kalman_tuned.parquet(κ*_2 month-end β, 덮어씀)
suppressMessages({library(arrow); library(data.table); library(dlm)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
OUT <- "stage_artifacts/WT_D20260713_003"

rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Ret","BM_Ret","K200","KQ150")))
rd <- rd[Date>=as.Date("2004-06-01")]; rd[, Date:=as.Date(Date)]
rd <- rd[is.finite(Ret)&is.finite(BM_Ret)]
univ <- unique(rd[K200==1|KQ150==1, Ticker]); rd <- rd[Ticker %in% univ]
setorder(rd, Ticker, Date); rd[, ym := format(Date,"%Y-%m")]
me <- rd[, .(sig_date=max(Date)), by=ym][order(ym)]
sig_dates <- me[ym>="2005-12" & ym<="2026-05", sig_date]; sig_set <- as.Date(sig_dates)
IS_END <- as.Date("2011-12-31")
rd_by <- split(rd[,.(Ticker,Date,Ret,BM_Ret)], by="Ticker", keep.by=FALSE)
nm <- names(rd_by)

# ── realized forward-252d β per (ticker, sig_date) — κ-independent, 1회 ──
cat("[01c] realized forward-252d β...\n")
real_list <- vector("list", length(rd_by))
for (j in seq_along(rd_by)) {
  sub <- rd_by[[j]]; if (nrow(sub)<150) next
  setorder(sub, Date)
  br <- vapply(sig_set, function(sd){
    fut <- sub[Date>sd]; if (nrow(fut)<120L) return(NA_real_)
    fut <- head(fut[order(Date)],252)
    f <- tryCatch(lm.fit(cbind(1,fut$BM_Ret),fut$Ret),error=function(e)NULL)
    if (is.null(f)) NA_real_ else f$coefficients[2L]
  }, numeric(1))
  real_list[[j]] <- data.table(Date=sig_set, Ticker=nm[j], beta_real=br)
}
REAL <- rbindlist(real_list)[is.finite(beta_real)]
cat(sprintf("[01c] realized β rows: %d\n", nrow(REAL)))

# ── OLS backward-252d β realized-prediction RMSE (baseline) ──
beta_ols <- as.data.table(read_parquet(file.path(OUT,"beta_monthly.parquet")))[,.(Date,Ticker,beta_ols)]
mo <- merge(beta_ols, REAL, by=c("Date","Ticker"))
mo[, is_flag := Date<=IS_END]
ols_rmse_is  <- sqrt(mean((mo[is_flag==TRUE,  beta_ols-beta_real])^2))
ols_rmse_oos <- sqrt(mean((mo[is_flag==FALSE, beta_ols-beta_real])^2))
ols_rmse_all <- sqrt(mean((mo$beta_ols-mo$beta_real)^2))

# ── per-κ Kalman filter → month-end β → realized-pred RMSE ──
KGRID <- c(1e-5, 3e-5, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2)
hl_of <- function(q){ g<-(sqrt(q^2+4*q)-q)/2; round(log(2)/(-log(1-g)),1) }
filt_beta <- function(sub, kappa){
  if (nrow(sub)<120L) return(NULL); setorder(sub,Date)
  dV <- var(sub$Ret[sub$Date<=IS_END],na.rm=TRUE); if(!is.finite(dV)||dV<=0) dV<-var(sub$Ret,na.rm=TRUE)
  if(!is.finite(dV)||dV<=0) return(NULL)
  mod <- tryCatch(dlmModReg(sub$BM_Ret,addInt=TRUE,dV=dV,dW=c(0,kappa*dV)),error=function(e)NULL)
  if(is.null(mod)) return(NULL)
  f <- tryCatch(dlmFilter(sub$Ret,mod),error=function(e)NULL); if(is.null(f)) return(NULL)
  d <- data.table(Date=sub$Date, beta=as.numeric(f$m[-1,2L]))
  be <- d[Date %in% sig_set][order(Date)]; unique(be,by="Date")
}
curve <- list(); best_k<-NA; best_is<-Inf; best_panel<-NULL
for (kappa in KGRID){
  t0<-Sys.time(); pl<-vector("list",length(rd_by))
  for (j in seq_along(rd_by)){ be<-filt_beta(rd_by[[j]],kappa); if(is.null(be)||!nrow(be)) next
    be[,Ticker:=nm[j]]; pl[[j]]<-be[,.(Date,Ticker,beta_kalman=beta)] }
  KB <- rbindlist(pl)
  mk <- merge(KB, REAL, by=c("Date","Ticker")); mk[,is_flag:=Date<=IS_END]
  rmse_is  <- sqrt(mean((mk[is_flag==TRUE, beta_kalman-beta_real])^2))
  rmse_oos <- sqrt(mean((mk[is_flag==FALSE,beta_kalman-beta_real])^2))
  rmse_all <- sqrt(mean((mk$beta_kalman-mk$beta_real)^2))
  sd_k <- sd(KB$beta_kalman,na.rm=TRUE)
  curve[[sprintf("%.0e",kappa)]] <- list(kappa=kappa, half_life_days=hl_of(kappa),
       rmse_is=round(rmse_is,4), rmse_oos=round(rmse_oos,4), rmse_all=round(rmse_all,4), beta_sd=round(sd_k,3))
  cat(sprintf("[01c] κ=%.0e hl=%.0fd RMSE_IS=%.4f RMSE_OOS=%.4f β_sd=%.3f (%.0fs)\n",
      kappa,hl_of(kappa),rmse_is,rmse_oos,sd_k,as.numeric(Sys.time()-t0,units="secs")))
  if(is.finite(rmse_is)&&rmse_is<best_is){best_is<-rmse_is;best_k<-kappa;best_panel<-copy(KB)}
}
cat(sprintf("[01c] OLS baseline: RMSE_IS=%.4f RMSE_OOS=%.4f RMSE_all=%.4f\n",ols_rmse_is,ols_rmse_oos,ols_rmse_all))
cat(sprintf("[01c] κ*_2 (metric_2 IS-min) = %.0e hl=%.0fd\n", best_k, hl_of(best_k)))
best_panel[, kappa_star := best_k]
write_parquet(best_panel, file.path(OUT,"beta_kalman_tuned.parquet"))
writeLines(jsonlite::toJSON(list(
   method="metric_2(실현 forward-252d β 예측) IS-min κ 선택. hedge-MSE 튜닝은 idiosyncratic 지배 퇴화(κ*→1e-1)로 폐기.",
   kappa_star=best_k, kappa_star_half_life_days=hl_of(best_k), grid=KGRID,
   ols_baseline=list(rmse_is=round(ols_rmse_is,4),rmse_oos=round(ols_rmse_oos,4),rmse_all=round(ols_rmse_all,4)),
   kalman_curve=curve,
   verdict_primary=sprintf("칼만 κ*_2 실현β 예측 RMSE_OOS=%.4f vs OLS %.4f — %s",
      curve[[sprintf("%.0e",best_k)]]$rmse_oos, ols_rmse_oos,
      ifelse(curve[[sprintf("%.0e",best_k)]]$rmse_oos < ols_rmse_oos, "칼만 우세","OLS 동급/우세"))),
   auto_unbox=TRUE, pretty=TRUE, digits=6), file.path(OUT,"kappa_metric2_curve.json"))
cat("[01c] DONE.\n")
