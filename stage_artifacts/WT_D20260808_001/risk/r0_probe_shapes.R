# =============================================================================
# r0_probe_shapes.R — risk-research 착수 전 입력 실측 (첫 출력 = 입력 형태)
#   근거: feedback-assert-input-shape-before-measuring (2026-08-08)
#   라벨: metric_type = input_assert (성과 주장 아님)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
say <- function(fmt, ...) cat(sprintf(paste0("[in] ", fmt, "\n"), ...))

shape <- function(nm, dt, datecol = "Date") {
  say("%-24s rows=%8d ncol=%d cols=[%s]", nm, nrow(dt), ncol(dt),
      paste(names(dt), collapse = ","))
  if (datecol %in% names(dt)) {
    d <- as.Date(dt[[datecol]]); ud <- sort(unique(d))
    g <- if (length(ud) > 1) stats::median(as.numeric(diff(ud))) else NA_real_
    say("%-24s unique %s = %d  범위 %s ~ %s  간격중앙 %.1f일 => 관측단위 %s",
        "", datecol, length(ud), as.character(min(ud)), as.character(max(ud)), g,
        if (isTRUE(g > 20)) "월간" else if (isTRUE(g <= 5)) "일간" else "기타")
  }
  invisible(dt)
}

# 1. RAWDATA (일간 — 가정 금지, 실측)
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
say("RAWDATA 전체 컬럼: %s", paste(names(raw), collapse = ","))
raw[, Date := as.Date(Date)]
shape("rawdata", raw)
say("rawdata Ticker unique = %d | Ret non-NA %.3f | Size non-NA %.3f | Vol non-NA %.3f",
    uniqueN(raw$Ticker), mean(!is.na(raw$Ret)), mean(!is.na(raw$Size)), mean(!is.na(raw$Vol)))
if ("BM_Ret" %in% names(raw)) say("BM_Ret non-NA %.3f  unique/day 확인: 첫날 값 %d개",
    mean(!is.na(raw$BM_Ret)), uniqueN(raw[Date == min(Date)]$BM_Ret))

# 2. benchmark
bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date := as.Date(Date)]
shape("benchmark", bm)
if ("Index" %in% names(bm)) { say("benchmark Index 값: %s", paste(unique(bm$Index), collapse=",")) }

# 3. tuned panel (alpha 승계)
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]; shape("WT009 tuned_panel", TUNED)
print(TUNED[, .(rows=.N, n_month=uniqueN(Date), dmin=min(Date), dmax=max(Date)), by=Factor_Name])

# 4. emitted alpha panel
AS <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet"))
if ("Date" %in% names(AS)) AS[, Date := as.Date(Date)]
shape("WT001 alpha_scores", AS)

# 5. universe / sector / k200
u <- as.data.table(read_parquet(".cache/universe.parquet")); shape("universe", u)
sec <- as.data.table(read_parquet(".cache/universe_support/us_sector_lv1.parquet")); shape("sector_lv1", sec)
k2 <- as.data.table(read_parquet(".cache/universe_support/us_k200.parquet")); shape("us_k200", k2)
fl <- as.data.table(read_parquet(".cache/universe_support/us_float.parquet")); shape("us_float", fl)

# 6. production book weights (TE 진단 대상)
pw <- Sys.glob("04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/*.json")
say("production_weights json 개수 = %d (최근 3: %s)", length(pw),
    paste(basename(tail(sort(pw), 3)), collapse=","))

saveRDS(list(raw_rows=nrow(raw), raw_dates=uniqueN(raw$Date)),
        "stage_artifacts/WT_D20260808_001/risk/r0_shapes.rds")
say("완료")
