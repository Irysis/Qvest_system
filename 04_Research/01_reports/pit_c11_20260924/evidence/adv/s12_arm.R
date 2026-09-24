suppressPackageStartupMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
fw <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/fred_macro_wide.parquet"), mmap=FALSE)); fw[, Date:=as.Date(Date)]
ae <- as.data.table(read_parquet(file.path(R,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"), mmap=FALSE)); ae[, dd:=as.Date(decision_date)]; ae[, lf:=as.Date(last_feat_date)]
m4 <- as.data.table(read_parquet(file.path(R,"06_Registry/m4_published/m4_panel_published.parquet"), mmap=FALSE)); m4[, ym:=as.character(YM)]
m4 <- m4[, .SD[.N], by=ym][, .(ym, m4_fire = weight_str1715 < 0.999)]
ae[, ym := format(dd, "%Y-%m")]
x <- merge(ae[, .(ym, dd, lf, ae_fire=fire_seq==1)], m4, by="ym", all.x=TRUE)
x <- x[lf <= max(fw$Date)]
x[, vix_same := sapply(lf, function(d) nrow(fw[Date==d & !is.na(VIX)]) > 0)]
x[, t10_same := sapply(lf, function(d) nrow(fw[Date==d & !is.na(Term_Spread)]) > 0)]
x[, nf_unrel := sapply(lf, function(d) { z <- fw[!is.na(Chi_Fin_Cond) & Date <= d]; max(z$Date) + 5L >= d })]
x[, st_unrel := sapply(lf, function(d) { z <- fw[!is.na(StL_Fin_Stress) & Date <= d]; max(z$Date) + 6L >= d })]
x[, gate := ae_fire & m4_fire %in% TRUE]
cat(sprintf("[close_d: position set at KR close of last_feat] months=%d | US daily VIX dated == last_feat: %d | T10Y2Y same: %d | NFCI unreleased: %d | STLFSI4 unreleased: %d\n",
  nrow(x), sum(x$vix_same), sum(x$t10_same), sum(x$nf_unrel), sum(x$st_unrel)))
cat(sprintf("gate(0.70) months = %d ; of which any leak(VIX same-date or weekly unreleased) = %d\n", sum(x$gate), sum(x$gate & (x$vix_same | x$nf_unrel | x$st_unrel))))
print(x[gate==TRUE, .(ym, lf, vix_same, nf_unrel, st_unrel)])
bm <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/benchmark.parquet"), mmap=FALSE)); kr <- sort(unique(as.Date(bm$Date)))
x[, start_d := as.Date(sapply(dd, function(d) { i <- which(kr >= d)[1]; if (is.na(i)) NA_character_ else as.character(kr[i]) }))]
x[, nf_c := sapply(seq_len(.N), function(i) { z <- fw[!is.na(Chi_Fin_Cond) & Date <= lf[i]]; max(z$Date) + 5L >= start_d[i] })]
x[, st_c := sapply(seq_len(.N), function(i) { z <- fw[!is.na(StL_Fin_Stress) & Date <= lf[i]]; max(z$Date) + 6L >= start_d[i] })]
cat(sprintf("[BOOK carrier: position set at KR close of first trading day >= decision] gate months=%d, weekly-unreleased in gate months=%d (NFCI %d, STLFSI4 %d)\n",
  sum(x$gate, na.rm=TRUE), sum(x$gate & (x$nf_c | x$st_c), na.rm=TRUE), sum(x$gate & x$nf_c, na.rm=TRUE), sum(x$gate & x$st_c, na.rm=TRUE)))
