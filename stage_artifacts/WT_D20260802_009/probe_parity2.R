# probe_parity2.R — WT-004 패널 stale 가설 검증 (bad월의 WT4값 == 내 전월값?)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
W4 <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
BASE <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))
p4 <- as.data.table(read_parquet(file.path(W4, "panel_M01_Mom_12_1_canonical.parquet")))
p4[, Date := as.Date(Date)]
b <- BASE[Factor_Name == "M01_Mom_12_1", .(Date, Ticker, z)]
pr <- readRDS(file.path(OUT, "parity_detail.rds"))$M01_Mom_12_1
bad_months <- pr[mad >= 1e-10, sort(Date)]
cat("bad 월수:", length(bad_months), "\n")
# 거래말 < 캘린더말 여부
cal_end <- as.Date(format(bad_months, "%Y-%m-01")) + 32
cal_end <- cal_end - as.integer(format(cal_end, "%d"))
cat("bad월 중 거래말<캘린더말:", sum(bad_months < cal_end), "/", length(bad_months), "\n")
ok_months <- pr[mad < 1e-10, sort(Date)]
cal_end_ok <- as.Date(format(ok_months, "%Y-%m-01")) + 32
cal_end_ok <- cal_end_ok - as.integer(format(cal_end_ok, "%d"))
cat("ok월 중 거래말==캘린더말:", sum(ok_months == cal_end_ok), "/", length(ok_months), "\n")
# lag 대조: bad월 t의 WT4값 vs 내 t-1값
chk <- list()
for (d in tail(bad_months, 8)) {
  d <- as.Date(d)
  i <- match(d, SIG); if (is.na(i) || i < 2) next
  prev <- SIG[i - 1L]
  m <- merge(p4[Date == d & is.finite(value), .(Ticker, v4 = value)],
             b[Date == prev, .(Ticker, zprev = z)], by = "Ticker")
  cat(sprintf("%s: vs 내 %s n=%d max|diff|=%.2e\n", format(d), format(prev),
      nrow(m), m[, max(abs(v4 - zprev))]))
}
