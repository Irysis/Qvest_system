suppressPackageStartupMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
fw <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/fred_macro_wide.parquet"), mmap=FALSE)); fw[, Date:=as.Date(Date)]
cat(names(fw), "\n")
for (v in c("StL_Fin_Stress","Chi_Fin_Cond","KRW_USD","VIX")) { z <- fw[!is.na(get(v))]; cat(v, "n=", nrow(z), " weekday table of last 300 obs:"); print(table(weekdays(tail(z$Date,300)))) }
ae <- as.data.table(read_parquet(file.path(R,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"), mmap=FALSE))
ae[, dd:=as.Date(decision_date)]; ae[, lf:=as.Date(last_feat_date)]
# nominal release lags (calendar days after observation date): NFCI Fri->Wed +5 ; STLFSI4 Fri->Thu +6 ; released 08:30/10:00 ET = KST evening, so leak iff obs_date+lag >= decision_date
lagtab <- list(Chi_Fin_Cond=5L, StL_Fin_Stress=6L)
res <- ae[, {
  o <- list()
  for (v in names(lagtab)) { z <- fw[!is.na(get(v)) & Date <= lf]; last_obs <- max(z$Date); o[[paste0(v,"_obs")]] <- last_obs; o[[paste0(v,"_leak")]] <- (last_obs + lagtab[[v]]) >= dd }
  zk <- fw[!is.na(KRW_USD) & Date <= lf]; o$KRW_obs <- max(zk$Date); o$KRW_same_as_lf <- max(zk$Date) == lf
  o }, by=.(dd, lf, fire_seq)]
cat(sprintf("n=%d | NFCI leak %d | STLFSI4 leak %d | either %d | fire months %d, of which either-leak %d\n", nrow(res), sum(res$Chi_Fin_Cond_leak), sum(res$StL_Fin_Stress_leak),
  sum(res$Chi_Fin_Cond_leak | res$StL_Fin_Stress_leak), sum(res$fire_seq), sum((res$Chi_Fin_Cond_leak | res$StL_Fin_Stress_leak) & res$fire_seq==1)))
cat(sprintf("KRW obs date == last_feat (KR date) in %d months (NY noon d = KST d+1 01~02h, before decision 1st-of-month)\n", sum(res$KRW_same_as_lf)))
print(tail(res, 6))
# check the NFCI date semantics: a known value. NFCI week ending 2020-03-20 was about +0.x ; print 2020-03
print(fw[Date >= as.Date("2020-03-01") & Date <= as.Date("2020-04-05") & !is.na(Chi_Fin_Cond), .(Date, wd=weekdays(Date), Chi_Fin_Cond, StL_Fin_Stress)])
bm <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/benchmark.parquet"), mmap=FALSE)); bm[, Date:=as.Date(Date)]
rd <- sort(unique(bm$Date))
res[, start_d := as.Date(sapply(dd, function(d) { i <- which(rd >= d)[1]; if (is.na(i)) NA_character_ else as.character(rd[i]) }))]
res <- res[!is.na(start_d)]
res[, nf2 := (Chi_Fin_Cond_obs + 5L) >= start_d]; res[, st2 := (StL_Fin_Stress_obs + 6L) >= start_d]
cat(sprintf("[cutoff=first KR trading day >= decision (carrier start_d, KR close)] n=%d NFCI %d STLFSI4 %d either %d | fire %d either-leak-in-fire %d\n",
  nrow(res), sum(res$nf2), sum(res$st2), sum(res$nf2|res$st2), sum(res$fire_seq), sum((res$nf2|res$st2) & res$fire_seq==1)))
cat(sprintf("max days before release: NFCI %d, STLFSI4 %d\n", max((res$Chi_Fin_Cond_obs+5L-res$start_d)[res$nf2]), max((res$StL_Fin_Stress_obs+6L-res$start_d)[res$st2])))
print(table(as.integer((res$StL_Fin_Stress_obs+6L-res$start_d)[res$st2])))
