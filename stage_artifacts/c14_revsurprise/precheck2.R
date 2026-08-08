## C14 사전 확인 v2 — v1 은 442파일(8.2GB)을 2회 전수 읽어 IO 과다로 중단. 1회 읽기 + 컬럼 축소.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[c14] ",fmt,"\n"),...)); flush.console()
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
say("★입력 실측: 월 파일 %d개 · %.1f GB (%s ~ %s)", length(fp),
    sum(file.size(fp))/1e9, basename(fp[1]), basename(fp[length(fp)]))

## 전제1 — 스키마와 팩터 존재 (최신 1개만)
sch <- schema(open_dataset(fp[length(fp)]))
say("최신월 컬럼: %s", paste(names(sch), collapse=", "))
F1 <- as.data.table(read_parquet(fp[length(fp)]))
long <- "Factor_Name" %in% names(F1)
say("형식: %s · %d행", if(long) "long(Factor_Name)" else "wide", nrow(F1))
fc <- if (long) unique(F1$Factor_Name) else names(F1)
say("팩터 %d종", length(fc))
TARGET <- c("C14_Revenue_Surprise","C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
for (k in TARGET) say("  %-24s 존재: %s", k, k %in% fc)
if (!("C14_Revenue_Surprise" %in% fc)) {
  say("★C14 미산출 — 이 라운드는 factor_db 산출부터 필요하다. 등재≠존재 확인됨.")
  say("   (레지스터리 등재는 되어 있으나 factor_db 가 계산하지 않음)")
}
say("--- C 계열 전수 ---"); say("  %s", paste(grep("^C[0-9]", fc, value=TRUE), collapse=" "))
