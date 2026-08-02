# =============================================================================
# run_wt006_panel.R — WT-D20260802_006 시그니처 피처 패널 빌드
#   각 (sig_date, Ticker): 최근 63 거래일 (p̃, ṽ) 경로의 truncated signature
#   불변량 (사전등록 preregistration.json 정의 그대로).
#
# PIT: 창 = sig_date 이하 최근 거래일만 (C1 rolling). Vol=0/결측일은 경로에서
#   스킵(재매개화 불변성으로 정당 — 사전등록 명시). 저장 Ret 재계산 없음(price/vol만).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_panel.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
source(file.path(OUT, "signature_lib.R"))
say <- function(fmt, ...) cat(sprintf(paste0("[wt006p] ", fmt, "\n"), ...))

t0 <- Sys.time()
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
say("RAW %d행 로드 (%.1fs)", nrow(RAW), as.numeric(difftime(Sys.time(), t0, units = "secs")))

RAW[, ym := format(Date, "%Y-%m")]
CAL  <- sort(unique(RAW$Date))
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
SIG  <- MEND[MEND >= as.Date("2004-12-01") & MEND < max(MEND)]
say("sig months %d (%s ~ %s)", length(SIG), as.character(min(SIG)), as.character(max(SIG)))

# 유니버스 멤버십 (월말) + ever-universe 축소
RAWME <- RAW[Date %in% SIG]
univ_by_date <- RAWME[K200 == TRUE | KQ150 == TRUE, .(Date, Ticker)]
univ_all <- unique(univ_by_date$Ticker)
say("ever-universe %d tickers, 월평균 %.0f", length(univ_all),
    univ_by_date[, .N, by = Date][, mean(N)])

# size_dt (eval cap-tier 진단용) 저장
size_dt <- RAWME[Ticker %chin% univ_all & is.finite(Size) & Size > 0, .(Date, Ticker, Size)]
write_parquet(size_dt, file.path(OUT, "size_panel.parquet"))

D <- RAW[Ticker %chin% univ_all & is.finite(Close) & Close > 0 &
           is.finite(Vol) & Vol > 0, .(Date, Ticker, Close, Vol)]
rm(RAW); gc(verbose = FALSE)
setkey(D, Ticker, Date)
say("일간 유효행 %d", nrow(D))

# ── 날짜 루프 (창은 시장 캘린더 기준 63/21/126 거래일) ───────────────────────
res <- vector("list", length(SIG))
t1 <- Sys.time()
for (si in seq_along(SIG)) {
  sd_ <- SIG[si]
  i <- findInterval(sd_, CAL)
  s63  <- CAL[max(1L, i - 62L)]
  s21  <- CAL[max(1L, i - 20L)]
  s126 <- CAL[max(1L, i - 125L)]
  univ <- univ_by_date[Date == sd_, Ticker]
  W <- D[Ticker %chin% univ & Date >= s126 & Date <= sd_]
  if (nrow(W) == 0L) next
  f <- W[, {
    in63 <- Date >= s63
    ff <- sig_features_pv(Close[in63], Vol[in63], min_days = 40L)
    in21 <- Date >= s21
    list(n_days = as.integer(ff[["n_days"]]),
         A_pv = ff[["A_pv"]], lvl1_p = ff[["lvl1_p"]], lvl1_v = ff[["lvl1_v"]],
         A_tp = ff[["A_tp"]], A_tv = ff[["A_tv"]],
         logsig3_ppv = ff[["logsig3_ppv"]], logsig3_pvv = ff[["logsig3_pvv"]],
         A_pv_w21 = levy_pv_only(Close[in21], Vol[in21], min_days = 15L),
         A_pv_w126 = levy_pv_only(Close, Vol, min_days = 80L))
  }, by = Ticker]
  f[, Date := sd_]
  res[[si]] <- f
  if (si %% 40L == 0L)
    say("  %d/%d (%s) %.0fs", si, length(SIG), format(sd_, "%Y-%m"),
        as.numeric(difftime(Sys.time(), t1, units = "secs")))
}
PAN <- rbindlist(res, use.names = TRUE)
setcolorder(PAN, c("Date", "Ticker"))
say("패널 %d행, A_pv non-NA %d (%.1f%%), %.0fs", nrow(PAN), sum(is.finite(PAN$A_pv)),
    100 * mean(is.finite(PAN$A_pv)), as.numeric(difftime(Sys.time(), t1, units = "secs")))

# 분포 sanity (진단 — 성과 무참조)
qs <- PAN[is.finite(A_pv), quantile(A_pv, c(.01, .25, .5, .75, .99))]
say("A_pv 분포: p1=%.1f p25=%.1f med=%.1f p75=%.1f p99=%.1f", qs[1], qs[2], qs[3], qs[4], qs[5])

write_parquet(PAN, file.path(OUT, "signature_panel.parquet"))
say("저장 완료 — signature_panel.parquet")
