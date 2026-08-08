# =============================================================================
# precheck_shapes.R — WT-D20260808_001 사전 확인 0단계: 입력 형태 실측
#   규약(2026-08-08): 측정 스크립트 첫 출력 = 입력의 행수·관측단위·범위 실측 인쇄.
#   가정 금지. 아래 어느 값도 하드코딩·추정하지 않는다.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/precheck_shapes.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[shape] ", fmt, "\n"), ...))

shape_of <- function(dt, nm, datecol = "Date", keycols = NULL) {
  d <- as.data.table(dt)
  say("%s: nrow=%d  ncol=%d  cols=[%s]", nm, nrow(d), ncol(d), paste(names(d), collapse = ","))
  if (datecol %in% names(d)) {
    dv <- as.Date(d[[datecol]])
    say("   %s: n_distinct=%d  범위 %s ~ %s", datecol, uniqueN(dv), min(dv), max(dv))
    # 관측 단위 판정: 인접 고유일자 간격 중앙값
    ud <- sort(unique(dv))
    if (length(ud) > 2) {
      gap <- as.numeric(diff(ud))
      say("   일자간격 중앙값=%.1f일 (min %.0f / max %.0f) → 관측단위 판정: %s",
          median(gap), min(gap), max(gap),
          if (median(gap) <= 5) "DAILY" else if (median(gap) <= 45) "MONTHLY" else "LOWER")
    }
  }
  if (!is.null(keycols) && all(keycols %in% names(d))) {
    say("   키 유일성: nrow=%d vs unique(%s)=%d → %s", nrow(d), paste(keycols, collapse = "+"),
        nrow(unique(d, by = keycols)),
        if (nrow(d) == nrow(unique(d, by = keycols))) "UNIQUE" else "DUPLICATED")
  }
  invisible(d)
}

BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
shape_of(BASE, "base_panel.parquet", keycols = c("Date", "Ticker", "Factor_Name"))
say("base Factor_Name: %s", paste(sort(unique(BASE$Factor_Name)), collapse = ", "))

TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
shape_of(TUNED, "tuned_panel.parquet", keycols = c("Date", "Ticker", "Factor_Name"))
say("tuned Factor_Name x 행수:")
print(TUNED[, .N, by = Factor_Name][order(Factor_Name)])
say("tuned score 요약 (팩터별 sd 중앙값):")
print(TUNED[, .(sd_z = sd(score, na.rm = TRUE)), by = .(Factor_Name, Date)][
  , .(sd_median = median(sd_z, na.rm = TRUE), n_month = .N), by = Factor_Name][order(Factor_Name)])

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
shape_of(RAW, ".cache/RAWDATA.parquet", keycols = c("Date", "Ticker"))
say("RAWDATA 관측단위 = 위 일자간격으로 판정할 것 (2026-08-08 사고: 월간으로 가정 금지)")

RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
say("월말 거래일(MEND): %d개  %s ~ %s", length(MEND), min(MEND), max(MEND))
SIG <- sort(unique(BASE$Date))
say("SIG(팩터 패널 월말): %d개  %s ~ %s", length(SIG), min(SIG), max(SIG))
say("SIG ⊆ MEND ? %s (교집합 %d)", all(SIG %in% MEND), length(intersect(SIG, MEND)))

RAWME <- RAW[Date %in% MEND]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
say("유니버스(K200∪KQ150, 월말): %d행 / 월평균 종목수 %.1f",
    nrow(UNIV), UNIV[, .N, by = Date][, mean(N)])
say("SIG 구간 유니버스 월평균 종목수 %.1f", UNIV[Date %in% SIG, .N, by = Date][, mean(N)])
cat("\n[shape] === 형태 실측 완료 — 이후 측정은 이 값 위에서만 설계 ===\n")
