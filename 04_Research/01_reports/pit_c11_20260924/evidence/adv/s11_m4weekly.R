suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
cat("ICSA weekday:"); print(table(weekdays(tail(m[Series_ID=="ICSA"]$Date, 100))))
mr <- as.data.table(read_parquet(file.path(C,"macro_regime.parquet"), mmap=FALSE)); mr[, Date:=as.Date(Date)]
cat("macro_regime cols:", paste(names(mr), collapse=","), "\n")
bm <- as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/pins/WT-D20260718_007_r1/benchmark.parquet", mmap=FALSE)); kr <- sort(unique(as.Date(bm$Date)))
lag <- c(STLFSI4=6L, NFCI=5L, ICSA=5L)
months <- seq(as.Date("2004-01-01"), as.Date("2026-06-01"), by="month")
out <- rbindlist(lapply(months, function(m0) {
  m_end <- seq(m0, by="month", length.out=2)[2] - 1
  hold_start <- kr[kr >= m_end + 1][1]   # first KR trading day of next month (position set at its close)
  r <- list(YM=format(m0, "%Y-%m"), hold_start=hold_start)
  for (s in names(lag)) {
    z <- m[Series_ID==s & !is.na(Value) & Date <= m_end]; setorder(z, Date)
    last_obs <- tail(z, 1); pub <- z[Date + lag[[s]] < hold_start]  # released strictly before holding-start day (release is KST evening)
    r[[paste0(s,"_asis")]] <- last_obs$Value; r[[paste0(s,"_pit")]] <- tail(pub$Value, 1); r[[paste0(s,"_leak")]] <- last_obs$Date + lag[[s]] >= hold_start
  }
  as.data.table(r) }))
out[, st_asis := fifelse(STLFSI4_asis > 1.5, 10, fifelse(STLFSI4_asis > 0, 5, 0))]; out[, st_pit := fifelse(STLFSI4_pit > 1.5, 10, fifelse(STLFSI4_pit > 0, 5, 0))]
out[, nf_asis := fifelse(NFCI_asis > 0, 8, 0)]; out[, nf_pit := fifelse(NFCI_pit > 0, 8, 0)]
cat(sprintf("months=%d | last weekly obs unreleased at holding start: STLFSI4 %d, NFCI %d, ICSA %d\n", nrow(out), sum(out$STLFSI4_leak), sum(out$NFCI_leak), sum(out$ICSA_leak)))
cat(sprintf("score-axis flips (as-is vs release-aware): STLFSI4 axis %d months, NFCI axis %d months\n", sum(out$st_asis != out$st_pit), sum(out$nf_asis != out$nf_pit)))
print(out[st_asis != st_pit | nf_asis != nf_pit, .(YM, hold_start, STLFSI4_asis, STLFSI4_pit, NFCI_asis, NFCI_pit)])
