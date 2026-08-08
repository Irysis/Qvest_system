## 침묵 스킵 7종 ↔ M2x 계열 중복쌍 대조 (제안서 근거 — C14/M26 이 유일 사례인지)
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
r <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
say <- function(fmt,...) cat(sprintf(paste0("[pair] ",fmt,"\n"),...))
show <- function(k) {
  if (!k %in% names(r)) { say("%-26s 미등재", k); return(invisible()) }
  e <- r[[k]]
  say("%-26s cat=%-10s def=%s", k, e$category, substr(e$definition,1,110))
}
say("--- 침묵 스킵 7종 (cons-게이트) ---")
for (k in c("C10_SUE_Persistence","C11_Earnings_Streak","C13_Revision_Breadth_3m",
            "C14_Revenue_Surprise","C15_Forecast_Error_Trend","C17_OP_Revision","C18_Earnings_CAR_3d")) show(k)
say("--- M2x 컨센서스 파생 계열 (실산출 대조군) ---")
for (k in c("M25_Earnings_Mom_Streak","M26_Revenue_Mom","M27_Analyst_Rev_Mom","M28_OP_Rev_Mom")) show(k)

## 실산출 여부 (최신 완결월)
d <- as.data.table(read_parquet(".cache/factor_db/factor_db_202507.parquet", col_select=c("Factor_Name")))
fc <- unique(d$Factor_Name)
say("--- factor_db_202507 실산출 여부 ---")
for (k in c("C10_SUE_Persistence","C11_Earnings_Streak","C13_Revision_Breadth_3m","C14_Revenue_Surprise",
            "C15_Forecast_Error_Trend","C17_OP_Revision","C18_Earnings_CAR_3d",
            "M25_Earnings_Mom_Streak","M26_Revenue_Mom","M27_Analyst_Rev_Mom","M28_OP_Rev_Mom"))
  say("  %-26s %s (%d행)", k, k %in% fc, sum(d$Factor_Name==k))

## registry 등재 C계열 vs 실산출 — 대조 (제안서 §3 방어선 근거)
reg_c <- sort(grep("^C[0-9]", names(r), value=TRUE))
say("registry C계열 %d종 · 실산출 %d종 · ★누락 %d종: %s",
    length(reg_c), sum(reg_c %in% fc), sum(!reg_c %in% fc), paste(setdiff(reg_c, fc), collapse=" "))
reg_all <- names(r)
say("registry 전체 %d종 · 202507 실산출과 교집합 %d · ★등재O 산출X %d종",
    length(reg_all), sum(reg_all %in% fc), sum(!reg_all %in% fc))
say("  등재O 산출X 전수: %s", paste(sort(setdiff(reg_all, fc)), collapse=" "))
