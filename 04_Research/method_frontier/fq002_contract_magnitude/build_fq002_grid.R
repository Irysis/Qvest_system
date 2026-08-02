# =============================================================================
# build_fq002_grid.R — FQ-002 측정 그리드 (신선 빈티지, WT-D20260802_018)
#
# 사유: wt005 grid(07-18산, RAWDATA_pin20260703)는 2026-07 폭락월(-23.63% 정본)을
#   미편입 (bench -11.0% / median 종목 -0.4% 실측 = 부분월). 파일럿 마지막 IC 관측월이
#   2026-07 홀딩이므로 stale grid 소비 = 판정 왜곡. 현행 RAWDATA(08-02 03:04, 7월 편입
#   + BM_Ret 수리 후) + 정본 .cache/benchmark.parquet 로 재구축한다.
# 로직: wt005 build_panel.R [3] 절 재현 (forward (start_d, end_d] 복리, adv = t-1 30d,
#   membership = K200|KQ150 at sig date). vintage tag 기록.
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
setDTthreads(2)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUT <- "04_Research/method_frontier/fq002_contract_magnitude"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

RAW_SRC   <- ".cache/RAWDATA.parquet"
BENCH_SRC <- ".cache/benchmark.parquet"
VINTAGE <- sprintf("RAWDATA@%s+benchmark@%s",
                   format(file.mtime(RAW_SRC), "%Y%m%d_%H%M"),
                   format(file.mtime(BENCH_SRC), "%Y%m%d_%H%M"))
cat("[grid] vintage:", VINTAGE, "\n")

raw <- as.data.table(read_parquet(RAW_SRC,
        col_select = c("Date", "Ticker", "K200", "KQ150", "Size", "Ret", "Close", "Vol")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2022-06-01")]   # 파일럿 창 + adv lookback 여유
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

raw[, ym := format(Date, "%Y-%m")]
me <- raw[, .(Date = max(Date)), by = ym]
sig_dates <- sort(me$Date)
sig_dates <- sig_dates[sig_dates >= as.Date("2023-01-01")]
cat("[grid] sig_dates:", length(sig_dates), format(min(sig_dates)), "~", format(max(sig_dates)), "\n")

b <- as.data.table(read_parquet(BENCH_SRC, col_select = c("Date", "BM_Ret")))
b[, Date := as.Date(Date)]; bm_daily <- b[!is.na(BM_Ret)]
bm_month <- function(start_d, end_d) {
  seg <- bm_daily[Date > start_d & Date <= end_d, BM_Ret]
  if (!length(seg)) return(NA_real_)   # wt005 는 0 반환이었다 — 결손을 0 으로 위장하지 않는다
  prod(1 + seg) - 1
}

R_list <- list(); bm_list <- list(); liq_list <- list(); mem_list <- list()
for (i in seq_along(sig_dates)) {
  sig <- sig_dates[i]
  ld <- raw[Date >= (sig - 30L) & Date < sig, .(adv = mean(TradingAmt, na.rm = TRUE)), by = Ticker]
  ld[, Date := sig]; liq_list[[i]] <- ld[, .(Date, Ticker, adv)]
  mem_list[[i]] <- raw[Date == sig & (K200 == 1 | KQ150 == 1), .(Date, Ticker, Size)]
  if (i < length(sig_dates)) {
    nxt <- sig_dates[i + 1L]
    pd <- raw[Date > sig & Date <= nxt, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    pd[, Date := sig]; R_list[[i]] <- pd[, .(Date, Ticker, Ret_1m)]
    bm_list[[i]] <- data.table(Date = sig, BM_Ret = bm_month(sig, nxt))
  }
}
Rg <- rbindlist(R_list); BMg <- rbindlist(bm_list); LQg <- rbindlist(liq_list); MEM <- rbindlist(mem_list)
stopifnot(nrow(BMg[is.na(BM_Ret)]) == 0)   # 벤치 결손월 금지 (조기 실패)

# 검증: 2026-06-30 시그널 행 = 2026-07 홀딩 — 정본 -23.63% 재현 확인
chk <- BMg[Date == as.Date("2026-06-30"), BM_Ret]
cat(sprintf("[grid] 2026-06-30 행 BM_Ret = %.4f (정본 -0.2363 기대)\n", chk))
if (length(chk) != 1 || abs(chk - (-0.2363)) > 0.005)
  stop("[grid] 7월 벤치 재현 실패 — 소스/정렬 확인")

write_parquet(Rg,  file.path(OUT, "grid_returns.parquet"))
write_parquet(BMg, file.path(OUT, "grid_bench.parquet"))
write_parquet(LQg, file.path(OUT, "grid_liq.parquet"))
write_parquet(MEM, file.path(OUT, "grid_universe_size.parquet"))
writeLines(VINTAGE, file.path(OUT, "grid_vintage.txt"))
cat(sprintf("[grid] R %d행 | BM %d행 | LQ %d행 | MEM %d행 → %s\n",
            nrow(Rg), nrow(BMg), nrow(LQg), nrow(MEM), OUT))
