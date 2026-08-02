# =============================================================================
# run_wt010_panel.R — WT-D20260802_010 W1 barycenter 편차 패널 빌드
#   각 (sig_date, Ticker): 최근 63 거래일 저장 Ret 경험분포의
#   robust 정규화 분위 → 횡단면 barycenter 편차 성분 + 대조 모멘트.
#
# PIT: 창 = sig_date 이하 최근 거래일만 (C1 rolling). barycenter = 당월 횡단면만
#   (시계열 정보 없음). 저장 Ret 사용 (재계산 금지 — rawdata Ret 방화벽).
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_010/run_wt010_panel.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
source(file.path(OUT, "ot_w1_lib.R"))
say <- function(fmt, ...) cat(sprintf(paste0("[wt010p] ", fmt, "\n"), ...))

t0 <- Sys.time()
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Ret", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
say("RAW %d행 로드 (%.1fs)", nrow(RAW), as.numeric(difftime(Sys.time(), t0, units = "secs")))

RAW[, ym := format(Date, "%Y-%m")]
CAL  <- sort(unique(RAW$Date))
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
SIG  <- MEND[MEND >= as.Date("2004-12-01") & MEND < max(MEND)]
say("sig months %d (%s ~ %s)", length(SIG), as.character(min(SIG)), as.character(max(SIG)))

RAWME <- RAW[Date %in% SIG]
univ_by_date <- RAWME[K200 == TRUE | KQ150 == TRUE, .(Date, Ticker)]
univ_all <- unique(univ_by_date$Ticker)
say("ever-universe %d tickers, 월평균 %.0f", length(univ_all),
    univ_by_date[, .N, by = Date][, mean(N)])

size_dt <- RAWME[Ticker %chin% univ_all & is.finite(Size) & Size > 0, .(Date, Ticker, Size)]
write_parquet(size_dt, file.path(OUT, "size_panel.parquet"))

D <- RAW[Ticker %chin% univ_all & is.finite(Ret), .(Date, Ticker, Ret)]
rm(RAW); gc(verbose = FALSE)
setkey(D, Ticker, Date)
say("일간 유효행 %d", nrow(D))

res <- vector("list", length(SIG))
t1 <- Sys.time()
for (si in seq_along(SIG)) {
  sd_ <- SIG[si]
  i <- findInterval(sd_, CAL)
  s63 <- CAL[max(1L, i - 62L)]
  univ <- univ_by_date[Date == sd_, Ticker]
  W <- D[Ticker %chin% univ & Date >= s63 & Date <= sd_]
  if (nrow(W) == 0L) next
  ff <- W[, {
    f <- ot_stock_quantiles(Ret, min_days = 40L)
    if (is.null(f)) list(ok = FALSE, n_days = NA_integer_, m = NA_real_, s = NA_real_,
                         vol63 = NA_real_, dsd63 = NA_real_, skew63 = NA_real_,
                         kurt63 = NA_real_, max5 = NA_real_, qn = list(NULL), qr = list(NULL))
    else list(ok = TRUE, n_days = f$n, m = f$m, s = f$s,
              vol63 = f$vol, dsd63 = f$dsd, skew63 = f$skew,
              kurt63 = f$kurt, max5 = f$max5, qn = list(f$q_norm), qr = list(f$q_raw))
  }, by = Ticker]
  ok <- ff[ok == TRUE]
  if (nrow(ok) < 30L) next                     # 횡단면 barycenter 최소 폭
  Qn <- do.call(rbind, ok$qn); Qr <- do.call(rbind, ok$qr)
  dec <- ot_cs_decompose(Qn)
  qbar_raw <- colMeans(Qr)
  w1_raw <- rowMeans(abs(sweep(Qr, 2L, qbar_raw)))
  out <- ok[, .(Ticker, n_days, vol63, dsd63, skew63, kurt63, max5)]
  out[, `:=`(rtail = dec$rtail, ltail = dec$ltail, w1_shape = dec$w1_shape,
             w1_raw = w1_raw,
             meanc = ok$m - mean(ok$m),
             scalec = log(ok$s) - mean(log(ok$s)),
             Date = sd_)]
  res[[si]] <- out
  if (si %% 40L == 0L)
    say("  %d/%d (%s) %.0fs", si, length(SIG), format(sd_, "%Y-%m"),
        as.numeric(difftime(Sys.time(), t1, units = "secs")))
}
PAN <- rbindlist(res, use.names = TRUE)
setcolorder(PAN, c("Date", "Ticker"))
say("패널 %d행, rtail non-NA %d (%.1f%%), %.0fs", nrow(PAN), sum(is.finite(PAN$rtail)),
    100 * mean(is.finite(PAN$rtail)), as.numeric(difftime(Sys.time(), t1, units = "secs")))

qs <- PAN[is.finite(rtail), quantile(rtail, c(.01, .25, .5, .75, .99))]
say("rtail 분포: p1=%.3f p25=%.3f med=%.3f p75=%.3f p99=%.3f", qs[1], qs[2], qs[3], qs[4], qs[5])
qs2 <- PAN[is.finite(w1_shape), quantile(w1_shape, c(.5, .9, .99))]
say("w1_shape: med=%.3f p90=%.3f p99=%.3f", qs2[1], qs2[2], qs2[3])

write_parquet(PAN, file.path(OUT, "ot_panel.parquet"))
say("저장 완료 — ot_panel.parquet")
