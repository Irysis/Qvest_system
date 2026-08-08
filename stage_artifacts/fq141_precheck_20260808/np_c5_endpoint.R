## NP-c5 — 256m 창의 종료월 2개월 민감도가 산술로 설명되는가 (내 계열 결함 여부 점검)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
D <- fread(file.path(OUT,"np157c2a1_d_extended.csv")); D[, Date := as.Date(Date)]; setorder(D, Date)
say <- function(fmt,...) cat(sprintf(paste0("[np-c5] ",fmt,"\n"),...))

A <- D[Date >= as.Date("2005-02-01") & Date <= as.Date("2026-05-31")]
n <- nrow(D); B <- D[(n-256+1L):n]
say("A: %s ~ %s  n=%d  d_ann=%+.5f", min(A$Date), max(A$Date), nrow(A), mean(A$d)*12)
say("B: %s ~ %s  n=%d  d_ann=%+.5f", min(B$Date), max(B$Date), nrow(B), mean(B$d)*12)
say("관측 차이 = %+.5f", mean(B$d)*12 - mean(A$d)*12)

dropped <- A[!Date %in% B$Date]; added <- B[!Date %in% A$Date]
say("--- A 에만 있는 월(빠진 것) %d개 ---", nrow(dropped)); print(dropped[, .(Date, d=round(d,5))])
say("--- B 에만 있는 월(들어온 것) %d개 ---", nrow(added));  print(added[,  .(Date, d=round(d,5))])

pred <- (sum(added$d) - sum(dropped$d)) / nrow(B) * 12
say("산술 예측 차이 = (added %+.5f - dropped %+.5f) / %d * 12 = %+.5f",
    sum(added$d), sum(dropped$d), nrow(B), pred)
say("관측 %+.5f vs 예측 %+.5f · 잔차 %+.2e", mean(B$d)*12-mean(A$d)*12, pred,
    (mean(B$d)*12-mean(A$d)*12) - pred)
say("판정: %s", if (abs((mean(B$d)*12-mean(A$d)*12)-pred) < 1e-9)
  "산술로 완전 설명 — 계열 결함 아님(창 양끝 월의 d 크기 차이)" else "잔차 존재 — 계열 점검 필요")
