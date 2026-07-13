# R19 / WT-D20260713_003 — Stage 2: 1차 endpoint = β 추정 정확도 (전방 헤지 오차, PIT)
# metric_1: 다음달 daily 헤지잔차 e_d = r_i,d − β̂_t·r_m,d, stock-month MSE 집계 (OLS vs Kalman, paired)
# metric_2: β̂_t vs 실현 β(t+1..t+12 daily OLS) 예측오차 RMSE
# 분해: 유니버스 전체 + cap-tier(MEGA/MID/OTHER) + melt-up 2025+
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
OUT <- "stage_artifacts/WT_D20260713_003"

beta_ols_p <- as.data.table(read_parquet(file.path(OUT,"beta_monthly.parquet")))[,.(Date,Ticker,beta_ols)]
beta_kal_p <- as.data.table(read_parquet(file.path(OUT,"beta_kalman_tuned.parquet")))[,.(Date,Ticker,beta_kalman)]
beta_m <- merge(beta_ols_p, beta_kal_p, by=c("Date","Ticker"), all=FALSE)  # tuned κ* Kalman
beta_m <- beta_m[!is.na(beta_ols) & !is.na(beta_kalman)]   # 두 arm 공통 stock-month만(paired)
# winsorize β to sensible market bounds [-0.5, 3.0] — 소형주 미수렴 극단 방지(공정 비교)
wz <- function(x) pmin(pmax(x, -0.5), 3.0)
beta_m[, beta_ols := wz(beta_ols)]; beta_m[, beta_kalman := wz(beta_kalman)]
setorder(beta_m, Ticker, Date)
sig_dates <- sort(unique(beta_m$Date))

cat("[02] loading RAWDATA daily...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Ret","BM_Ret","Size","K200","KQ150")))
rd <- rd[Date >= as.Date("2005-11-01")]
rd[, Date := as.Date(Date)]
rd <- rd[is.finite(Ret) & is.finite(BM_Ret)]
rd <- rd[Ticker %in% unique(beta_m$Ticker)]
setorder(rd, Ticker, Date)
rd[, ym := format(Date,"%Y-%m")]

# cap-tier: 각 sig_date 유니버스 내 Size 랭킹 (MEGA top10 / MID 11-30 / OTHER)
size_me <- rd[Date %in% sig_dates, .(Size=last(Size)), by=.(Date, Ticker)]
size_me <- size_me[is.finite(Size)]
size_me[, srank := frank(-Size, ties.method="first"), by=Date]
size_me[, tier := fifelse(srank<=10,"MEGA", fifelse(srank<=30,"MID","OTHER"))]
beta_m <- merge(beta_m, size_me[,.(Date,Ticker,tier,srank)], by=c("Date","Ticker"), all.x=TRUE)

# forward month map: sig_date t → 다음 sig_date의 달 (t+1 month) daily
sig_ym <- format(sig_dates,"%Y-%m")
next_ym <- c(sig_ym[-1], NA)                       # t의 다음달 = 다음 sig_date 달
fwd_map <- data.table(Date=sig_dates, fwd_ym=next_ym)
beta_m <- merge(beta_m, fwd_map, by="Date", all.x=TRUE)
beta_m <- beta_m[!is.na(fwd_ym)]

# ── metric_1: forward daily hedge residual MSE per stock-month ──
cat("[02] metric_1 forward hedge error...\n")
rd_idx <- rd[, .(Date,Ticker,Ret,BM_Ret,ym)]
setkey(rd_idx, Ticker, ym)
res_list <- vector("list", nrow(beta_m))
for (i in seq_len(nrow(beta_m))) {
  row <- beta_m[i]
  fwd <- rd_idx[.(row$Ticker, row$fwd_ym), nomatch=0L]
  if (nrow(fwd) < 10L) next                        # 최소 10 거래일
  e_ols <- fwd$Ret - row$beta_ols   * fwd$BM_Ret
  e_kal <- fwd$Ret - row$beta_kalman* fwd$BM_Ret
  res_list[[i]] <- data.table(Date=row$Date, Ticker=row$Ticker, tier=row$tier,
                    mse_ols=mean(e_ols^2), mse_kal=mean(e_kal^2), ndays=nrow(fwd))
}
he <- rbindlist(res_list, use.names=TRUE)
he[, melt := ifelse(Date>=as.Date("2025-01-01"),"meltup_2025+","pre2025")]
write_parquet(he, file.path(OUT,"hedge_error_stockmonth.parquet"))

# 집계 (전체 + tier + melt)
paired_stats <- function(dt) {
  d <- dt$mse_ols - dt$mse_kal                     # >0 이면 Kalman 우세(오차 작음)
  n <- length(d); nb <- sum(d>0); sign_p <- tryCatch(binom.test(nb,n,0.5)$p.value, error=function(e)NA)
  list(n=n, mean_mse_ols=mean(dt$mse_ols), mean_mse_kal=mean(dt$mse_kal),
       median_mse_ols=median(dt$mse_ols), median_mse_kal=median(dt$mse_kal),
       kalman_better_pct=round(100*mean(d>0),1),
       sign_test_p=round(sign_p,4),
       paired_t=round(mean(d)/(sd(d)/sqrt(n)),3),
       median_diff=median(d),
       rel_improve_pct=round(100*(mean(dt$mse_ols)-mean(dt$mse_kal))/mean(dt$mse_ols),3))
}
agg <- list(overall = paired_stats(he))
for (tt in c("MEGA","MID","OTHER")) agg[[tt]] <- paired_stats(he[tier==tt])
for (mm in c("pre2025","meltup_2025+")) agg[[mm]] <- paired_stats(he[melt==mm])
# melt × tier
for (tt in c("MEGA","MID","OTHER")) {
  s <- he[tier==tt & melt=="meltup_2025+"]
  if (nrow(s)>5) agg[[paste0("meltup_",tt)]] <- paired_stats(s)
}

# ── metric_2: β̂_t vs 실현 β(t+1..t+12 daily OLS) ──
cat("[02] metric_2 realized-β prediction error...\n")
# 실현 β: 각 (ticker, sig_date) 이후 252 거래일 OLS slope
realb_list <- vector("list", nrow(beta_m))
setkey(rd, Ticker, Date)
for (i in seq_len(nrow(beta_m))) {
  row <- beta_m[i]
  fut <- rd[.(row$Ticker)][Date > row$Date]
  fut <- head(fut[order(Date)], 252)
  if (nrow(fut) < 120L) next
  fit <- tryCatch(lm.fit(cbind(1,fut$BM_Ret), fut$Ret), error=function(e) NULL)
  if (is.null(fit)) next
  br <- min(max(fit$coefficients[2L], -0.5), 3.0)   # realized β도 winsorize(공정 비교)
  realb_list[[i]] <- data.table(Date=row$Date, Ticker=row$Ticker, tier=row$tier,
                      beta_real=br, err_ols=row$beta_ols-br, err_kal=row$beta_kalman-br,
                      melt=ifelse(row$Date>=as.Date("2025-01-01"),"meltup_2025+","pre2025"))
}
rb <- rbindlist(realb_list, use.names=TRUE)
write_parquet(rb, file.path(OUT,"realized_beta_pred.parquet"))
pred_stats <- function(dt){
  n<-nrow(dt); d<-dt$err_ols^2 - dt$err_kal^2
  nb<-sum(d>0); sp<-tryCatch(binom.test(nb,n,0.5)$p.value,error=function(e)NA)
  list(n=n, rmse_ols=round(sqrt(mean(dt$err_ols^2)),4), rmse_kal=round(sqrt(mean(dt$err_kal^2)),4),
       mae_ols=round(mean(abs(dt$err_ols)),4), mae_kal=round(mean(abs(dt$err_kal)),4),
       kalman_better_pct=round(100*mean(d>0),1), sign_test_p=round(sp,4),
       paired_t=round(mean(d)/(sd(d)/sqrt(n)),3),
       rel_rmse_improve_pct=round(100*(sqrt(mean(dt$err_ols^2))-sqrt(mean(dt$err_kal^2)))/sqrt(mean(dt$err_ols^2)),3))
}
pred <- list(overall=pred_stats(rb))
for (tt in c("MEGA","MID","OTHER")) pred[[tt]] <- pred_stats(rb[tier==tt])
for (mm in c("pre2025","meltup_2025+")) pred[[mm]] <- pred_stats(rb[melt==mm])

out <- list(endpoint="primary_beta_accuracy",
            metric_1_forward_hedge_error=agg,
            metric_2_realized_beta_pred=pred,
            note="paired_t>0 & kalman_better_pct>50 이면 Kalman이 β 추정 정확도에서 우세. metric_1은 다음달 daily 헤지잔차 MSE(작을수록 우수), metric_2는 실현β(252d) 예측오차.")
writeLines(jsonlite::toJSON(out, auto_unbox=TRUE, pretty=TRUE, digits=6),
           file.path(OUT,"primary_beta_accuracy.json"))
cat("[02] DONE.\n")
cat(sprintf("  metric_1 overall: kalman_better=%.1f%% paired_t=%.2f rel_improve=%.2f%% (n=%d)\n",
    agg$overall$kalman_better_pct, agg$overall$paired_t, agg$overall$rel_improve_pct, agg$overall$n))
cat(sprintf("  metric_2 overall: rmse_ols=%.4f rmse_kal=%.4f paired_t=%.2f\n",
    pred$overall$rmse_ols, pred$overall$rmse_kal, pred$overall$paired_t))
cat(sprintf("  meltup metric_1: kalman_better=%.1f%% paired_t=%.2f\n",
    agg[["meltup_2025+"]]$kalman_better_pct, agg[["meltup_2025+"]]$paired_t))
