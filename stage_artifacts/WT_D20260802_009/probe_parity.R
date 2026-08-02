# probe_parity.R — parity FAIL 진단 (판정 아님, 구조 확인)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
W4 <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
# base 패널은 저장 전 중단됨 — 재현: 한 달만 로드
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
p4 <- as.data.table(read_parquet(file.path(W4, "panel_M01_Mom_12_1_canonical.parquet")))
p4[, Date := as.Date(Date)]
cat("WT4 dates sample:", format(head(sort(unique(p4$Date)), 4)), "...",
    format(tail(sort(unique(p4$Date)), 2)), "\n")
d_test <- as.Date("2015-06-30")
lm1 <- load_month_factors(d_test, factor_names = "M01_Mom_12_1")
lm5 <- load_month_factors(d_test, factor_names = c("V01_BM","M01_Mom_12_1","D03_RealVol","Q01_GPA","V06_fDY"))
a <- as.data.table(lm1)[, .(Ticker, z1 = Z_Score_Aligned)]
b <- as.data.table(lm5)[Factor_Name == "M01_Mom_12_1", .(Ticker, z5 = Z_Score_Aligned)]
m <- merge(a, b, by = "Ticker")
cat(sprintf("single vs 5-batch: n=%d max|diff|=%.2e\n", nrow(m), m[, max(abs(z1 - z5))]))
w <- p4[Date == d_test]
mm <- merge(a, w[, .(Ticker, v = value)], by = "Ticker")
cat(sprintf("single vs WT4: n=%d max|diff|=%.2e cor=%.4f\n",
    nrow(mm), mm[, max(abs(z1 - v))], mm[, cor(z1, v)]))
# 다른 달 (교차 확인)
for (dd in as.Date(c("2010-03-31", "2020-12-30", "2024-06-28"))) {
  dd <- as.Date(dd)
  w2 <- p4[abs(as.numeric(Date - dd)) <= 3]
  if (nrow(w2) == 0) next
  d4 <- unique(w2$Date)[1]
  lmx <- as.data.table(load_month_factors(d4, factor_names = "M01_Mom_12_1"))
  m2 <- merge(lmx[, .(Ticker, z = Z_Score_Aligned)], w2[Date == d4, .(Ticker, v = value)], by = "Ticker")
  cat(sprintf("%s: n=%d max|diff|=%.2e cor=%+.4f\n", format(d4), nrow(m2),
      m2[, max(abs(z - v))], m2[, cor(z, v)]))
}
