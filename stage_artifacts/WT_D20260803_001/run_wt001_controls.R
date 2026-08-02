# =============================================================================
# run_wt001_controls.R — WT-D20260803_001 통제 패널 빌드 (C15 준수)
#   D35_RealVol_63d + D45_Downside_Dev — Q-Lead 지시 (자체 계산 금지, 로더 경유)
#   전 d0월을 load_month_factors() 경유로만 로드 (parquet 직접 read 금지)
#   산출: stage_artifacts/WT_D20260803_001/controls_panel_d35.parquet
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_001/run_wt001_controls.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_001")
say <- function(fmt, ...) cat(sprintf(paste0("[wt001-ctrl] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")   # CACHE_DIR 선정의 — connector ofile 중첩-source 함정 회피
source("02_Infrastructure/factor_db/factor_db_connector.R")

EX <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_014/alpha_scores.parquet"))
EX[, Date := as.Date(Date)]
dd <- sort(unique(EX$Date))
dd <- dd[dd <= as.Date("2026-03-31")]   # data_currency_flag (WT-020): d0 >= 2026-04-30 라벨 소비 금지
say("d0 그리드: %d개월 (%s ~ %s)", length(dd), as.character(min(dd)), as.character(max(dd)))

ctrl <- c("D35_RealVol_63d", "D45_Downside_Dev")
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
say("통제 패널: %d행 / %d월 / 결측률 %s", nrow(CP), uniqueN(CP$Date),
    paste(sprintf("%s=%.1f%%", ctrl, 100 * CP[, sapply(.SD, function(x) mean(!is.finite(x))),
                                              .SDcols = ctrl]), collapse = " "))
mon_cov <- CP[, .(n_d35 = sum(is.finite(D35_RealVol_63d)),
                  n_d45 = sum(is.finite(D45_Downside_Dev))), by = Date]
say("월별 D35 커버리지: min %d / median %.0f | <100 인 월 %d개",
    mon_cov[, min(n_d35)], mon_cov[, median(n_d35)], mon_cov[n_d35 < 100, .N])
write_parquet(CP, file.path(OUT, "controls_panel_d35.parquet"))
say("저장 완료 — controls_panel_d35.parquet (Z_Score_Aligned, IC-정렬 방향 — 부호 비관여, 흡수력만 소비)")
