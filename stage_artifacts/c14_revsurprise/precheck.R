suppressPackageStartupMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[c14] ",fmt,"\n"),...))

say("=== 전제1: 이 팩터가 factor DB 에 실제로 산출돼 있는가 ===")
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
say("factor_db 월 파일 %d개 (%s ~ %s)", length(fp), basename(fp[1]), basename(fp[length(fp)]))
if (!length(fp)) { say("★factor_db 부재 — 중단"); quit(status=0) }
F <- as.data.table(read_parquet(fp[length(fp)]))
say("★입력 실측: 최신월 %s · %d행 · 컬럼 %s", basename(fp[length(fp)]), nrow(F), paste(head(names(F),8),collapse=","))
fc <- if ("Factor_Name" %in% names(F)) unique(F$Factor_Name) else names(F)
say("팩터 %d종", length(fc))
for (k in c("C14_Revenue_Surprise","C01_SUE","C04_ESBR","C02_EPS_Chg_1m","C06_TP_Gap")) {
  say("  %-24s in factor_db: %s", k, k %in% fc)
}

say("=== 전제2: 시계열 커버리지 (컨센서스는 KR 에서 짧을 수 있다) ===")
chk <- c("C14_Revenue_Surprise","C01_SUE")
for (k in chk) {
  n <- sapply(fp, function(f){
    d <- tryCatch(as.data.table(read_parquet(f)), error=function(e) NULL)
    if (is.null(d)) return(0L)
    if ("Factor_Name" %in% names(d)) sum(d$Factor_Name==k & !is.na(d[[grep("Value|Z_Score", names(d), value=TRUE)[1]]]))
    else if (k %in% names(d)) sum(!is.na(d[[k]])) else 0L
  })
  ok <- which(n > 0)
  if (!length(ok)) { say("  %-24s ★전 구간 0 — 미산출", k); next }
  say("  %-24s 유효월 %d/%d (%s ~ %s) · 종목 중앙 %.0f", k, length(ok), length(fp),
      basename(fp[min(ok)]), basename(fp[max(ok)]), median(n[ok]))
}
