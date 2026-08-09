## STEP 8: 왜도를 지배하는 극단 관측의 데이터 무결성 점검
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv8] ", fmt, "\n"), ...)); flush.console() }
D <- as.data.table(readRDS(file.path(OUT, "adv_ms_input.rds"))$D)[order(Date)]

say("=== 상위 12 일간 수익 (BM_Ret) ===")
o <- order(D$BM_Ret, decreasing = TRUE)[1:12]
print(D[o, .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))])
say("=== 하위 12 일간 수익 ===")
o2 <- order(D$BM_Ret)[1:12]
print(D[o2, .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))])

say("=== 최대 양수일(%s) 전후 10일 ===", as.character(D$Date[o[1]]))
i <- o[1]; print(D[max(1,i-5):min(.N,i+5), .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))])

say("=== 연도별 |BM_Ret| > 8%% 일수 ===")
D[, yr := as.integer(format(Date, "%Y"))]
print(D[abs(BM_Ret) > 0.08, .N, by = yr][order(yr)])
say("=== 2026년 전체 요약 === n=%d · sd %.5f · min %+.4f · max %+.4f",
    D[yr==2026, .N], D[yr==2026, sd(BM_Ret)], D[yr==2026, min(BM_Ret)], D[yr==2026, max(BM_Ret)])
say("=== 전체 무조건 왜도 = %+.4f (참고: OFF 왜도와 비교) ===",
    { v<-D$BM_Ret; sum((v-mean(v))^3)/length(v)/sd(v)^3 })
