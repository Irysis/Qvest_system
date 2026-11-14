## D2 정정(18:22) 전후 RAWDATA 전 열 대조 — 바뀐 것이 Ret 10행뿐인가
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
a <- as.data.table(read_parquet(file.path(SP, "rawdata_post_d2_1731.parquet"), mmap = FALSE))
b <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"), mmap = FALSE))
cat("rows", nrow(a), nrow(b), "· cols same", identical(names(a), names(b)), "\n")
setorder(a, Date, Ticker); setorder(b, Date, Ticker)
stopifnot(identical(a$Date, b$Date), identical(a$Ticker, b$Ticker))
for (cn in setdiff(names(a), c("Date", "Ticker"))) {
  x <- a[[cn]]; y <- b[[cn]]
  d <- if (is.numeric(x)) !((is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)) else !((is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y))
  if (sum(d)) cat(sprintf("  %-14s 바뀐 행 %d\n", cn, sum(d)))
}
k <- which(!((is.na(a$Ret) & is.na(b$Ret)) | (!is.na(a$Ret) & !is.na(b$Ret) & a$Ret == b$Ret)))
ch <- data.table(Date = a$Date[k], Ticker = a$Ticker[k], before = a$Ret[k], after = b$Ret[k])
reg <- as.data.table(jsonlite::fromJSON(file.path(ROOT, "06_Registry/ret_fill_registry.json"))$entries)[, .(Date = as.Date(Date), Ticker, Ret_reg = Ret, method)]
ch <- merge(ch, reg, by = c("Date", "Ticker"), all.x = TRUE)
options(width = 200)
print(ch[, .(Date, Ticker, before = round(100 * before, 2), after = round(100 * after, 2), eq_reg = abs(after - Ret_reg) < 1e-12, method)])
cat(sprintf("Ret 바뀐 행 %d · 모두 등록부 값 %s\n", nrow(ch), all(ch$after == ch$Ret_reg | abs(ch$after - ch$Ret_reg) < 1e-12)))
fwrite(ch, file.path(SP, "d2b_changed_rows.csv"))
