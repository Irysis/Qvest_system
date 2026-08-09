## 단일 극단일(+19.98%)이 헤드라인 효과의 ~44% 를 지므로 그 관측치 자체를 실측 확인
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
cat(sprintf("행수 %d · %s ~ %s\n", nrow(D), as.character(min(D$Date)), as.character(max(D$Date))))
cat("\n-- |BM_Ret| 상위 8일 --\n")
print(D[order(-abs(BM_Ret))][1:8, .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))])
cat("\n-- 데이터 말미 15일 --\n")
print(D[(.N-14):.N, .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))])
cat("\n-- 연도별 |BM_Ret|>10% 일수 --\n")
print(D[abs(BM_Ret) > 0.10, .N, by = .(yr = format(as.Date(Date), "%Y"))])
cat(sprintf("\n2026년 관측일수 = %d\n", D[format(as.Date(Date),"%Y")=="2026", .N]))
