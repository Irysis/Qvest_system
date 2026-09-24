suppressMessages({library(arrow);library(data.table)})
m <- as.data.table(read_parquet(".cache/macro_fred.parquet", mmap=FALSE)); m[, Date:=as.Date(Date)]
grid <- sort(unique(m$Date))                      # regime_daily_v2 FRED grid (union of series dates)
kr <- as.data.table(read_parquet(".cache/benchmark.parquet", mmap=FALSE))[, .(d=as.Date(Date))]
kr <- kr[d >= as.Date("2003-01-01") & d <= as.Date("2026-09-04")]
# nominal release offsets (calendar days after FRED observation date)
rel <- list(NFCI=5L, STLFSI4=6L, ICSA=5L, UMCSENT=NA_integer_)
# regime_daily_v2: MRS[FRED row r] = raw[previous FRED row]; KR date d -> roll to FRED row <= d
prev_row <- function(d){ i <- findInterval(d, grid); ifelse(i>=2, grid[pmax(i-1,1)], NA) }
kr[, used_upto := as.Date(prev_row(as.numeric(d)), origin="1970-01-01")]
res <- list()
for (sid in c("NFCI","STLFSI4","ICSA")) {
  ob <- sort(unique(m[Series_ID==sid & !is.na(Value), Date]))
  j <- findInterval(as.numeric(kr$used_upto), as.numeric(ob))
  obs_used <- as.Date(ifelse(j>0, ob[pmax(j,1)], NA), origin="1970-01-01")
  release <- obs_used + rel[[sid]]
  # unknown at KR close d (US release morning ET on 'release' = KST evening of release day)
  unk_at_close_d <- release >= kr$d
  res[[sid]] <- data.table(series=sid, n_kr_days=nrow(kr), share_unreleased_at_KR_close_d=mean(unk_at_close_d, na.rm=TRUE))
}
# UMCSENT: FRED date = M-01 (final released ~ last Fri of M, prelim ~ 2nd Fri)
ob <- sort(unique(m[Series_ID=="UMCSENT" & !is.na(Value), Date]))
j <- findInterval(as.numeric(kr$used_upto), as.numeric(ob)); obs_used <- as.Date(ifelse(j>0, ob[pmax(j,1)], NA), origin="1970-01-01")
approx_final <- as.Date(cut(obs_used + 31, "month")) - 5   # ~ last week of reference month (근사)
res[["UMCSENT"]] <- data.table(series="UMCSENT(근사: 확정치 ~월말-5일)", n_kr_days=nrow(kr), share_unreleased_at_KR_close_d=mean(approx_final >= kr$d, na.rm=TRUE))
print(rbindlist(res))
cat("grid rows:", length(grid), " weekday share:", round(mean(!weekdays(grid) %in% c("Saturday","Sunday")),3), "\n")
