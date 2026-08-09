## STEP 12: 2026 구간 데이터 무결성 예비 점검 (지배 관측의 출처 확인)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
say <- function(fmt,...) { cat(sprintf(paste0("[adv12] ",fmt,"\n"),...)); flush.console() }
S <- readRDS("stage_artifacts/alloc_daily/p0.rds")
say("alloc_daily/p0.rds 원소: %s", paste(names(S), collapse=", "))
BD <- as.data.table(S$BD)
say("BD: %d행 · 컬럼 %s", nrow(BD), paste(names(BD), collapse=", "))
BD[, yr := as.integer(format(Date, "%Y"))]
say("=== 연도별 일간 sd (연율화) 최근 12년 + 극단연도 ===")
tb <- BD[, .(n=.N, sd_d=sd(BM_Ret), sd_ann=sd(BM_Ret)*sqrt(252), min=min(BM_Ret), max=max(BM_Ret)), by=yr][order(yr)]
print(tb[yr %in% c(1997,1998,2000,2001,2008,2020,2022,2023,2024,2025,2026)])
say("=== 전체 연도 sd_ann 분포: median %.3f · 최대 %.3f (%d년) ===",
    median(tb$sd_ann), max(tb$sd_ann), tb[which.max(sd_ann), yr])
say("=== 2026 월별 ===")
BD[yr==2026, ym := format(Date, "%Y-%m")]
print(BD[yr==2026, .(n=.N, sd_d=round(sd(BM_Ret),5), sum_ret=round(sum(BM_Ret),4),
                     min=round(min(BM_Ret),4), max=round(max(BM_Ret),4)), by=ym][order(ym)])
say("=== 지수 레벨 연속성: 2026 누적 %.4f · 2025 누적 %.4f ===",
    exp(sum(log(1+BD[yr==2026]$BM_Ret)))-1, exp(sum(log(1+BD[yr==2025]$BM_Ret)))-1)
