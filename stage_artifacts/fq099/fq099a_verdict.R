suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099a] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
PLI <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
         "InterestExp","InterestIncome","DepAmort","RandD","OperatingCF","InvestCF","FinanceCF",
         "Dividends","FCF1","FCF2","EBITDA","EBIT")
## m4 엔진 팩터코드도 수집
m4 <- paste(readLines("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R", warn=FALSE), collapse="\n")
m4codes <- unique(unlist(regmatches(m4, gregexpr('"[A-Z]{1,4}[0-9]{2}_[A-Za-z_0-9]+"', m4, perl=TRUE))))
m4codes <- gsub('"','',m4codes)
base <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
          "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
say("base 엔진 팩터 %d종: %s", length(base), paste(base, collapse=" "))
say("m4  엔진 팩터 %d종: %s", length(m4codes), paste(head(m4codes,20), collapse=" "))
prod <- unique(c(base, m4codes))
say("생산 합집합 %d종", length(prod))
inter <- intersect(prod, flow)
say("★유량의존 51건과의 교집합: %d종%s", length(inter),
    if(length(inter)) paste0(" — ", paste(inter, collapse=" ")) else " (없음)")

## 레지스터리에서 생산 팩터 각각이 유량 원항목을 쓰는지 직접 확인 (코드목록 대조와 독립 축)
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
say("--- 독립 확인: 생산 팩터별 정의문에 유량 원항목 등장 ---")
miss <- c()
for (k in prod) {
  if (is.null(reg[[k]])) { miss <- c(miss,k); next }
  b <- paste(unlist(reg[[k]]), collapse=" | ")
  h <- PLI[sapply(PLI, function(p) grepl(p, b, fixed=TRUE))]     # ★fixed 필수
  say("  %-26s %s", k, if(length(h)) paste0("★유량: ", paste(h, collapse=" ")) else "유량 없음")
}
if (length(miss)) say("  ⚠레지스터리 미등재 %d종: %s (판정 불가 — 결손을 '유량 없음'으로 읽지 말 것)", length(miss), paste(miss, collapse=" "))
