suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[gap] ",fmt,"\n"),...))
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
F1 <- as.data.table(read_parquet(fp[length(fp)]))
prod <- unique(F1$Factor_Name)
reg  <- names(fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE))
say("★입력 실측: 레지스터리 %d · factor_db 최신월 산출 %d", length(reg), length(prod))
gap <- setdiff(reg, prod); extra <- setdiff(prod, reg)
say("등재됐으나 미산출 %d종 · 산출되나 미등재 %d종", length(gap), length(extra))

## ★양성 대조 — 생산 북 7종은 반드시 산출돼 있어야 한다
ctrl <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap","Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
say("양성 대조(생산 북 7종) 산출: %d/7 %s", sum(ctrl %in% prod),
    if(sum(ctrl %in% prod)<7) paste0("★미산출: ", paste(setdiff(ctrl,prod), collapse=" ")) else "")

## FQ-099 코호트 대조
clean <- readLines("stage_artifacts/fq099/fq099d1_clean_final.txt")
flowT <- readLines("stage_artifacts/fq099/flow_dependent_TRUE.txt")
say("--- FQ-099 '미탐색 25건' 중 실제 산출 여부 ---")
say("  산출됨 %d · ★미산출 %d", sum(clean %in% prod), sum(!clean %in% prod))
say("  미산출 목록: %s", paste(setdiff(clean, prod), collapse=" "))
say("--- 유량의존(fundamental) 32건 중 ---")
say("  산출됨 %d · ★미산출 %d", sum(flowT %in% prod), sum(!flowT %in% prod))
say("  미산출: %s", paste(setdiff(flowT, prod), collapse=" "))
writeLines(gap, "stage_artifacts/c14_revsurprise/registered_not_produced.txt")
say("전량 → stage_artifacts/c14_revsurprise/registered_not_produced.txt")
