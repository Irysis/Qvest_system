## 층 3 후보 3종의 실제 가용 구간 + 등급/중복 확인 (착수 전 실측)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A0d] ", fmt, "\n"), ...))

FDB <- ".cache/factor_db"
files <- list.files(FDB, pattern = "^factor_db_\\d{6}\\.parquet$")
yms <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", files))
say("월간 factor_db 파일 %d개 · %s ~ %s", length(yms), yms[1], yms[length(yms)])

targets <- c("C01_SUE", "C02_EPS_Chg_1m", "M26_Revenue_Mom")
## 전 월 스캔 — 각 팩터 첫/마지막 등장 + 월별 커버 종목수
res <- rbindlist(lapply(yms, function(ym) {
  p <- file.path(FDB, sprintf("factor_db_%s.parquet", ym))
  d <- tryCatch(as.data.table(read_parquet(p, col_select = c("Ticker", "Factor_Name", "Z_Score"))),
                error = function(e) NULL)
  if (is.null(d)) return(NULL)
  d <- d[Factor_Name %in% targets]
  if (!nrow(d)) return(data.table(ym = ym, Factor_Name = NA_character_, n = 0L))
  o <- d[, .(n = sum(!is.na(Z_Score))), by = Factor_Name]
  o[, ym := ym][]
}), fill = TRUE)

for (f in targets) {
  s <- res[Factor_Name == f & n > 0]
  if (!nrow(s)) { say("%s : 월간 DB 전무", f); next }
  say("%-18s 가용 %s ~ %s (%d개월) · 월평균 커버 %.0f종목 · 최근 커버 %d",
      f, min(s$ym), max(s$ym), nrow(s), mean(s$n), s[ym == max(ym), n])
}
say("")
say("--- 3종 동시 가용 월 ---")
w <- dcast(res[!is.na(Factor_Name)], ym ~ Factor_Name, value.var = "n", fill = 0)
all3 <- w[Reduce(`&`, lapply(targets, function(f) w[[f]] > 100))]
say("3종 모두 100종목+ 커버: %d개월 · %s ~ %s", nrow(all3), min(all3$ym), max(all3$ym))

fwrite(res, "stage_artifacts/WT-D20260809_004/a0d_factor_avail.csv")
