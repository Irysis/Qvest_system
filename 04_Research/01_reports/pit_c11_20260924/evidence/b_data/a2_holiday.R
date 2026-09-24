suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[, Date := as.Date(Date)]
daily <- c("VIXCLS","SP500","DGS10","DGS2","T10Y2Y","DEXKOUS","BAMLH0A0HYM2","T10YIE","T5YIE","BAMLC0A4CBBB")
cat("weekday dist (1=Sun..7=Sat):\n")
for (s in c(daily,"WALCL","NFCI","STLFSI4","ICSA")) { x <- m[Series_ID==s]; tb <- table(factor(wday(x$Date),levels=1:7)); cat(sprintf("%-13s %s\n", s, paste(tb, collapse=" "))) }
us_hol <- as.Date(c("2026-07-03","2025-11-27","2025-01-09","2025-07-04","2024-07-04","2024-11-28","2025-12-25","2026-01-19","2025-04-18","2026-04-03","2025-05-26","2025-09-01","2025-10-13","2025-11-11","2018-12-05","2012-10-29","2012-10-30","2001-09-11","2001-09-12","2001-09-13","2001-09-14","2025-01-20","2025-06-19"))
kr_hol <- as.Date(c("2025-01-28","2025-01-29","2025-01-30","2025-10-03","2025-10-06","2025-10-07","2025-10-08","2025-10-09","2025-03-03","2025-05-05","2025-05-06","2025-06-03","2025-06-06","2025-08-15","2024-09-16","2024-09-17","2024-09-18","2024-10-01","2026-02-16","2026-02-17","2026-02-18","2026-03-02","2026-05-05","2026-05-25","2026-06-03","2025-12-31","2024-12-31"))
chk <- function(ds, lab) {
  cat("\n==", lab, "==\n")
  out <- rbindlist(lapply(ds, function(d) { r <- list(Date=d, wd=wday(d)); for (s in daily) r[[s]] <- if (nrow(m[Series_ID==s & Date==d])) "Y" else "."; as.data.table(r)}))
  print(out)
}
chk(us_hol, "US holidays (expect '.' if Date = US obs date)")
chk(us_hol+1, "US holiday +1 day (expect '.' if Date shifted to KST availability)")
chk(kr_hol, "KR holidays (expect 'Y' for US-traded series if Date = US obs date)")
