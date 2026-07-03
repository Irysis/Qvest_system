# Lens B — 2022 market structure: KR FF5 style returns + benchmark
# 도훈 mandate 2026-06-12 defense recon. metric_type=proxy (diagnostic only).
suppressMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
})
data.table::setDTthreads(2)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

cat("=============== 1. kr_factor_returns_v2.parquet ===============\n")
fr <- as.data.table(read_parquet(file.path(ROOT, ".cache/kr_factor_returns_v2.parquet")))
cat("colnames:", paste(colnames(fr), collapse=", "), "\n")
cat("nrow:", nrow(fr), "\n")
print(head(fr, 3)); print(tail(fr, 3))

# detect date column
dcol <- intersect(c("Date","date","ym","month","Month"), colnames(fr))[1]
cat("date col:", dcol, "\n")
fr[, .d := as.Date(get(dcol))]
fcols <- setdiff(colnames(fr), c(dcol, ".d"))
fcols <- fcols[sapply(fr[, ..fcols], is.numeric)]
cat("factor cols:", paste(fcols, collapse=", "), "\n")

fx <- xts(as.matrix(fr[, ..fcols]), order.by = fr$.d)

show_window <- function(x, from, to, label) {
  w <- x[paste0(from, "/", to)]
  if (nrow(w) == 0) { cat(label, ": NO DATA\n"); return(invisible(NULL)) }
  cat("\n---", label, sprintf("(%s ~ %s, n=%d months) ---\n", from, to, nrow(w)))
  cat("monthly:\n"); print(round(coredata(w), 4))
  cat("cumulative (Return.cumulative):\n")
  print(round(Return.cumulative(w, geometric = TRUE), 4))
}

# 2022 monthly detail
w22 <- fx["2022"]
cat("\n--- 2022 full year monthly (rownames = month) ---\n")
m22 <- data.frame(date = index(w22), round(coredata(w22), 4))
print(m22)

show_window(fx, "2022-01", "2022-09", "2022-01~2022-09 (primary stress)")
show_window(fx, "2022-01", "2022-12", "2022 full year")
show_window(fx, "2008-06", "2008-11", "2008 GFC")
show_window(fx, "2011-08", "2011-09", "2011 US downgrade")
show_window(fx, "2018-10", "2018-10", "2018-10")
show_window(fx, "2020-02", "2020-03", "2020 COVID")
show_window(fx, "2026-03", "2026-03", "2026-03 meltup -19% month")

cat("\n=============== 2. benchmark.parquet 2022 ===============\n")
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
cat("colnames:", paste(colnames(bm), collapse=", "), "\n")
cat("nrow:", nrow(bm), "\n"); print(head(bm, 2))
bdcol <- intersect(c("Date","date"), colnames(bm))[1]
brcol <- intersect(c("BM_Ret","bm_ret","Ret","ret"), colnames(bm))[1]
cat("using date col:", bdcol, " ret col:", brcol, "\n")
bm[, .d := as.Date(get(bdcol))]
bx <- xts(bm[[brcol]], order.by = bm$.d); colnames(bx) <- "BM_Ret"
bmm <- apply.monthly(bx, Return.cumulative, geometric = TRUE)
b22 <- bmm["2022"]
cat("\n--- benchmark monthly 2022 ---\n")
print(data.frame(date = index(b22), BM = round(coredata(b22), 4)))
cat("cumulative 2022-01~09:\n"); print(round(Return.cumulative(bx["2022-01/2022-09"]), 4))
cat("cumulative 2022 full:\n");  print(round(Return.cumulative(bx["2022"]), 4))
cat("cumulative 2022-10~12 (Q4 rebound):\n"); print(round(Return.cumulative(bx["2022-10/2022-12"]), 4))

cat("\n=============== 3. conditional_ic_matrix — bad-market IC ranking ===============\n")
ic <- fread(file.path(ROOT, ".cache/conditional_ic_matrix.csv"))
ic[, bad_minus_good := ic_bad - ic_good]
ic_f <- ic[n_months >= 100]
cat("\n--- top 30 by ic_bad (n_months>=100) ---\n")
print(ic_f[order(-ic_bad)][1:30, .(Factor_Name, ic_all=round(ic_all,4), ic_bad=round(ic_bad,4),
       ic_good=round(ic_good,4), bad_minus_good=round(bad_minus_good,4),
       recent_3y_icir=round(recent_3y_icir,3), n_months, category)])
cat("\n--- D/V family rows (dividend/value mapping) ---\n")
print(ic[grepl("^(D|V)[0-9]", Factor_Name)][order(-ic_bad)][, .(Factor_Name, ic_all=round(ic_all,4),
       ic_bad=round(ic_bad,4), ic_good=round(ic_good,4), recent_3y_icir=round(recent_3y_icir,3), n_months, category)])
cat("\n--- Q family (quality) ---\n")
print(ic[grepl("^Q[0-9]", Factor_Name)][order(-ic_bad)][, .(Factor_Name, ic_all=round(ic_all,4),
       ic_bad=round(ic_bad,4), ic_good=round(ic_good,4), recent_3y_icir=round(recent_3y_icir,3), n_months, category)])

cat("\nDONE\n")
