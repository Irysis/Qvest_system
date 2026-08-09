## WT-D20260809_002 (FQ-166) 착수 전 사전 확인 — 세 재료 패널이 동일 프레임으로 맞춰지는가
## read-only. 라운드 성립 조건 판정용. 가정 금지 — 전부 실측 출력.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[pre] ", fmt, "\n"), ...)); flush.console() }

paths <- c(
  M26 = "stage_artifacts/WT_D20260808_002/alpha_scores.parquet",
  Q01 = "stage_artifacts/WT_D20260808_003/alpha_scores.parquet",
  W01 = "stage_artifacts/WT_D20260808_001/alpha_scores.parquet")

info <- list()
for (nm in names(paths)) {
  p <- paths[[nm]]
  say("=== %s : %s (존재 %s) ===", nm, p, file.exists(p))
  if (!file.exists(p)) next
  D <- as.data.table(read_parquet(p))
  dc <- grep("^Date$|date", names(D), value = TRUE)[1]
  if (!is.na(dc)) D[[dc]] <- as.Date(D[[dc]])
  say("  행 %d · 열 %d", nrow(D), ncol(D))
  say("  컬럼: %s", paste(names(D), collapse = ", "))
  if (!is.na(dc)) say("  기간 %s ~ %s · 고유월 %d", min(D[[dc]]), max(D[[dc]]), uniqueN(D[[dc]]))
  ## 수치열 후보 = 점수일 가능성
  num <- names(D)[vapply(D, is.numeric, logical(1))]
  say("  수치열: %s", paste(num, collapse = ", "))
  info[[nm]] <- list(D = D, datecol = dc, num = num)
}

## 공통 창 / 공통 종목 교집합 — 동일 프레임 가능성 판정
say("=== 동일 프레임 성립 진단 ===")
if (length(info) >= 2L) {
  keys <- lapply(info, function(x) unique(x$D[[x$datecol]]))
  common <- Reduce(intersect, keys)
  common <- as.Date(common, origin = "1970-01-01")
  say("  월 교집합 %d개 (%s ~ %s)", length(common),
      if (length(common)) min(common) else NA, if (length(common)) max(common) else NA)
  for (nm in names(info)) say("    %s 단독 월수 %d", nm, length(keys[[nm]]))
  tk <- lapply(info, function(x) unique(x$D$Ticker))
  say("  종목 교집합 %d (개별 %s)", length(Reduce(intersect, tk)),
      paste(sprintf("%s=%d", names(tk), lengths(tk)), collapse = " · "))
}
saveRDS(info[names(info)], "stage_artifacts/WT_D20260809_002/precheck_info.rds")
say("=== 사전 확인 완료 ===")
