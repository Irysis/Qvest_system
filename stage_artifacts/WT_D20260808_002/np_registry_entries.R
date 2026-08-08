## registry 항목 정정 — 앞선 census 의 getid 가 e$name 을 먼저 집어 "미등재" 오답을 냈다.
## registry 는 **팩터명이 곧 최상위 키**인 flat dict. 키로 직접 조회한다 (존재 검사 전에 정체 검사).
suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
r <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
cat("registry 최상위 키 개수:", length(r), "\n")
ks <- names(r)
cat("C 계열 등재 키:", paste(sort(ks[substr(ks,1,1)=="C" & grepl("^C[0-9]", ks)]), collapse=" "), "\n")
cat("M2x 등재 키:", paste(sort(grep("^M2", ks, value=TRUE)), collapse=" "), "\n")
for (tgt in c("C14_Revenue_Surprise","M26_Revenue_Mom","C10_SUE_Persistence","C11_Earnings_Streak",
              "C13_Revision_Breadth_3m","C15_Forecast_Error_Trend","C17_OP_Revision","C18_Earnings_CAR_3d")) {
  cat("=====", tgt, "존재:", tgt %in% ks, "\n")
  if (tgt %in% ks) cat(toJSON(r[[tgt]], auto_unbox = TRUE, pretty = TRUE), "\n")
}
