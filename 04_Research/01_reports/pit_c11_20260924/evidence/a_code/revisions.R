suppressMessages({library(arrow);library(data.table)})
old <- as.data.table(read_parquet(".cache/fred_macro.parquet.bak_20260701", mmap=FALSE)); old[, Date:=as.Date(Date)]
new <- as.data.table(read_parquet(".cache/fred_macro.parquet", mmap=FALSE)); new[, Date:=as.Date(Date)]
cut <- as.Date("2026-05-31")   # 두 vintage 모두 존재했던 과거 구간만 비교
j <- merge(old[Date <= cut, .(Series_ID, Date, v0=Value)], new[Date <= cut, .(Series_ID, Date, v1=Value)], by=c("Series_ID","Date"))
out <- j[, .(n_common=.N, n_changed=sum(abs(v1-v0) > 1e-9, na.rm=TRUE),
             max_abs_chg=max(abs(v1-v0), na.rm=TRUE),
             first_changed=if (any(abs(v1-v0)>1e-9, na.rm=TRUE)) min(Date[abs(v1-v0)>1e-9], na.rm=TRUE) else as.Date(NA)), by=Series_ID][order(-n_changed)]
print(out)
