# =============================================================================
# run_wt009_base.R — WT-D20260802_009 base 패널 (registry 정본 5종)
#   load_month_factors() 경유(C15) Z_Score_Aligned 그대로 — base 재정의 없음.
#   parity: WT_D20260802_004 ast_compile 패널(M01/D03)과 값 대조 의무.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_009/run_wt009_base.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[wt009b] ", fmt, "\n"), ...))

source("02_Infrastructure/factor_db/factor_db_connector.R")

F5 <- c("V01_BM", "M01_Mom_12_1", "D03_RealVol", "Q01_GPA", "V06_fDY")

# ── 월말 sig 그리드 (2001-12 ~ 최신-1) + 유니버스 멤버십 ─────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "K200", "KQ150", "Size", "Sector")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
SIG  <- MEND[MEND >= as.Date("2001-12-01") & MEND < max(MEND)]
RAWME <- RAW[Date %in% SIG]
UNIV <- RAWME[K200 == TRUE | KQ150 == TRUE, .(Date, Ticker)]
say("sig months %d (%s ~ %s), 월평균 %.0f종목", length(SIG),
    as.character(min(SIG)), as.character(max(SIG)), UNIV[, .N, by = Date][, mean(N)])

# size (cap-tier 진단) + sector (P1 튜닝 + 반증 HHI) 저장
write_parquet(RAWME[Ticker %chin% unique(UNIV$Ticker) & is.finite(Size) & Size > 0,
                    .(Date, Ticker, Size)], file.path(OUT, "size_panel.parquet"))
write_parquet(RAWME[Ticker %chin% unique(UNIV$Ticker) & !is.na(Sector),
                    .(Date, Ticker, Sector)], file.path(OUT, "sector_panel.parquet"))
rm(RAW, RAWME); gc(verbose = FALSE)

# ── base 패널: 월별 load_month_factors (5종 일괄 필터) ───────────────────────
t0 <- Sys.time()
res <- vector("list", length(SIG))
for (i in seq_along(SIG)) {
  lm <- tryCatch(load_month_factors(SIG[i], factor_names = F5), error = function(e) NULL)
  if (!is.null(lm) && nrow(lm))
    res[[i]] <- data.table(Date = SIG[i], Ticker = lm$Ticker,
                           Factor_Name = lm$Factor_Name, z = lm$Z_Score_Aligned)
  if (i %% 40L == 0L) say("  %d/%d (%s) %.0fs", i, length(SIG), format(SIG[i], "%Y-%m"),
                          as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
BASE <- rbindlist(res[!vapply(res, is.null, logical(1))])
say("base 패널 %d행 (%.1f min)", nrow(BASE),
    as.numeric(difftime(Sys.time(), t0, units = "mins")))
cov_tab <- BASE[, .(n_months = uniqueN(Date), rows = .N), by = Factor_Name]
for (i in seq_len(nrow(cov_tab)))
  say("  %-14s months=%d rows=%d", cov_tab$Factor_Name[i], cov_tab$n_months[i], cov_tab$rows[i])

# ── parity: WT_004 ast_compile 패널과 대조 (M01/D03, 공통 Date-Ticker) ───────
W4 <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
for (f in c("M01_Mom_12_1", "D03_RealVol")) {
  p4 <- as.data.table(read_parquet(file.path(W4, sprintf("panel_%s_canonical.parquet", f))))
  p4[, Date := as.Date(Date)]
  m <- merge(BASE[Factor_Name == f, .(Date, Ticker, z)],
             p4[is.finite(value), .(Date, Ticker, value)], by = c("Date", "Ticker"))
  mad_ <- m[, max(abs(z - value))]
  say("parity %s: n=%d max|diff|=%.2e %s", f, nrow(m), mad_,
      ifelse(mad_ < 1e-10, "PASS", "FAIL"))
  if (mad_ >= 1e-10) stop("[wt009b] parity FAIL — base 경로 불일치, 중단")
}

write_parquet(BASE, file.path(OUT, "base_panel.parquet"))
say("저장 완료 — base_panel.parquet")
