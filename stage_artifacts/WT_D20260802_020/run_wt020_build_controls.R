# =============================================================================
# run_wt020_build_controls.R — WT-D20260802_020 통제 4축 패널 빌드 (C15 준수)
#   D01_IdioVol / D02_Beta / D03_RealVol / D45_Downside_Dev
#   전 256개 d0 월을 load_month_factors() 경유로만 로드 (parquet 직접 read 금지)
#   산출: stage_artifacts/WT_D20260802_020/controls_panel.parquet
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_020/run_wt020_build_controls.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_020")
say <- function(fmt, ...) cat(sprintf(paste0("[wt020-ctrl] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")   # CACHE_DIR 선정의 — connector ofile 중첩-source 함정 회피
source("02_Infrastructure/factor_db/factor_db_connector.R")

EX <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_014/alpha_scores.parquet"))
EX[, Date := as.Date(Date)]
dd <- sort(unique(EX$Date))
say("후보 패널: %d행 / %d개 d0월 (%s ~ %s)", nrow(EX), length(dd),
    as.character(min(dd)), as.character(max(dd)))

ctrl <- c("D01_IdioVol", "D02_Beta", "D03_RealVol", "D45_Downside_Dev")
res <- vector("list", length(dd))
t0 <- Sys.time()
for (i in seq_along(dd)) {
  f <- tryCatch(
    suppressMessages(load_month_factors(dd[i], factor_names = ctrl)),
    error = function(e) { say("월 %s 로드 실패: %s", as.character(dd[i]), conditionMessage(e)); NULL })
  if (is.null(f) || !nrow(f)) next
  w <- dcast(as.data.table(f), Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = mean)
  w[, Date := dd[i]]
  res[[i]] <- w
  if (i %% 32 == 0)
    say("진행 %d/%d (%.0fs 경과)", i, length(dd),
        as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
CP <- rbindlist(res, fill = TRUE)
for (cc in ctrl) if (!cc %in% names(CP)) CP[, (cc) := NA_real_]
CP <- CP[, c("Date", "Ticker", ctrl), with = FALSE]
say("통제 패널: %d행 / %d월 / 컬럼 결측률 %s", nrow(CP), uniqueN(CP$Date),
    paste(sprintf("%s=%.1f%%", ctrl, 100 * CP[, sapply(.SD, function(x) mean(!is.finite(x))),
                                              .SDcols = ctrl]), collapse = " "))
write_parquet(CP, file.path(OUT, "controls_panel.parquet"))
say("저장 완료 — controls_panel.parquet (Z_Score_Aligned, IC-정렬 방향 — 부호는 회귀 판정에 비관여)")
