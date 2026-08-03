# =============================================================================
# build_fq002_grid_ext.R — FQ-125 1단계 확장 그리드 (WT-D20260803_008)
#
# build_fq002_grid.R 와 **동일 로직**, 창만 2019-12~ 로 확장.
# ★빈티지 정직성: 파일럿 grid 는 RAWDATA@20260802_0304+benchmark@20260802_0151 로 고정
#   되어 있는데 현재 소스는 그 이후 재생성됨. 따라서 본 스크립트는 확장 그리드를
#   **별도 파일**로 쓰고, 겹치는 구간(2023-01~)에서 pinned grid 와 값이 갈리는지
#   실측 대조한다. 갈리면 판정에 병기 — 조용한 교체 금지(§7 Vintage Pinning).
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

RAW_SRC   <- ".cache/RAWDATA.parquet"
BENCH_SRC <- ".cache/benchmark.parquet"
VINTAGE <- sprintf("RAWDATA@%s+benchmark@%s",
                   format(file.mtime(RAW_SRC), "%Y%m%d_%H%M"),
                   format(file.mtime(BENCH_SRC), "%Y%m%d_%H%M"))
PINNED <- readLines(file.path(OUT, "grid_vintage.txt"))[1]
cat("[grid_ext] 현재 vintage:", VINTAGE, "\n[grid_ext] pinned(파일럿):", PINNED, "\n")
cat("[grid_ext] vintage 동일 여부:", identical(VINTAGE, PINNED), "\n")

raw <- as.data.table(read_parquet(RAW_SRC,
        col_select = c("Date", "Ticker", "K200", "KQ150", "Size", "Ret", "Close", "Vol")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2019-08-01")]   # 확장창 + adv 30d lookback 여유
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)
raw[, ym := format(Date, "%Y-%m")]
me <- raw[, .(Date = max(Date)), by = ym]
sig_dates <- sort(me$Date)
sig_dates <- sig_dates[sig_dates >= as.Date("2019-11-01")]
cat("[grid_ext] sig_dates:", length(sig_dates), format(min(sig_dates)), "~", format(max(sig_dates)), "\n")
# 개수가 아니라 distinct-YM 로 단언 (seq.Date 31일 앵커 함정 계열 방어)
stopifnot(uniqueN(format(sig_dates, "%Y%m")) == length(sig_dates))

b <- as.data.table(read_parquet(BENCH_SRC, col_select = c("Date", "BM_Ret")))
b[, Date := as.Date(Date)]; bm_daily <- b[!is.na(BM_Ret)]
bm_month <- function(start_d, end_d) {
  seg <- bm_daily[Date > start_d & Date <= end_d, BM_Ret]
  if (!length(seg)) return(NA_real_)
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
stopifnot(nrow(BMg[is.na(BM_Ret)]) == 0)

# ── ★ 소스 벤치 무결성 게이트 + 명시 오버라이드 ──────────────────────────────
# 현행 .cache/benchmark.parquet(08-03 08:36 재생성)은 2026-07-27 에 BM_Close 가
# 9325 → 1069 로 **스케일 절단**된다(두 소스 접합 결함). 그 결과 2026-07 홀딩월이
# -91.36% 로 계산된다. 정본은 -23.63% (파일럿 pinned grid_bench 에 보존).
# → 조용히 쓰지 않는다: 결함을 탐지하고, pinned 정본으로 **라벨된 오버라이드**를 건다.
bad_days <- bm_daily[Date >= min(sig_dates) & abs(BM_Ret) > 0.30]
BENCH_OVERRIDE <- list(applied = FALSE)
if (nrow(bad_days)) {
  cat(sprintf("[grid_ext] ⚠ 소스 벤치 이상일 %d건 (|일수익|>30%%): %s\n", nrow(bad_days),
              paste(format(bad_days$Date), collapse = ",")))
}
chk <- BMg[Date == as.Date("2026-06-30"), BM_Ret]
cat(sprintf("[grid_ext] 2026-06-30 행 BM_Ret = %.4f (정본 -0.2363)\n", chk))
if (length(chk) == 1 && abs(chk - (-0.2363)) > 0.005) {
  pinb <- as.data.table(read_parquet(file.path(OUT, "grid_bench.parquet")))
  pinb[, Date := as.Date(Date)]
  pv <- pinb[Date == as.Date("2026-06-30"), BM_Ret]
  if (length(pv) != 1 || abs(pv - (-0.2363)) > 0.005)
    stop("[grid_ext] pinned 벤치에도 정본 없음 — 오버라이드 불가, 중단")
  BMg[Date == as.Date("2026-06-30"), BM_Ret := pv]
  BENCH_OVERRIDE <- list(applied = TRUE, date = "2026-06-30", source_value = chk,
                         pinned_value = pv, reason = "source benchmark scale break at 2026-07-27",
                         metric_type = "pinned_override")
  cat(sprintf("[grid_ext] ★오버라이드: 2026-06-30 BM_Ret %.4f → %.4f (pinned 정본)\n", chk, pv))
}
# 오버라이드 후에도 |월수익| > 40% 인 행이 남으면 중단 (결손을 정상값으로 내려앉히지 않음)
if (nrow(BMg[abs(BM_Ret) > 0.40])) {
  print(BMg[abs(BM_Ret) > 0.40]); stop("[grid_ext] 벤치 월수익 이상치 잔존 — 측정 불가")
}

write_parquet(Rg,  file.path(OUT, "gridx_returns.parquet"))
write_parquet(BMg, file.path(OUT, "gridx_bench.parquet"))
write_parquet(LQg, file.path(OUT, "gridx_liq.parquet"))
write_parquet(MEM, file.path(OUT, "gridx_universe_size.parquet"))
writeLines(VINTAGE, file.path(OUT, "gridx_vintage.txt"))

# ── ★ 겹침 구간 대조: pinned grid vs 확장 grid (2023-01~) ────────────────────
p_R <- as.data.table(read_parquet(file.path(OUT, "grid_returns.parquet"))); p_R[, Date := as.Date(Date)]
p_B <- as.data.table(read_parquet(file.path(OUT, "grid_bench.parquet")));   p_B[, Date := as.Date(Date)]
p_M <- as.data.table(read_parquet(file.path(OUT, "grid_universe_size.parquet"))); p_M[, Date := as.Date(Date)]
p_L <- as.data.table(read_parquet(file.path(OUT, "grid_liq.parquet")));     p_L[, Date := as.Date(Date)]

cmpf <- function(a, b, key, val, nm) {
  m <- merge(a, b, by = key, suffixes = c("_pin", "_new"))
  v1 <- m[[paste0(val, "_pin")]]; v2 <- m[[paste0(val, "_new")]]
  d <- abs(v1 - v2); d <- d[is.finite(d)]
  cat(sprintf("[cmp] %s: 공통 %d행 (pin %d / new %d) | max|Δ|=%.3e | Δ>1e-9 %d행\n",
              nm, nrow(m), nrow(a), nrow(b), if (length(d)) max(d) else NA_real_, sum(d > 1e-9)))
  list(n_common = nrow(m), n_pin = nrow(a), n_new = nrow(b),
       max_abs_diff = if (length(d)) max(d) else NA_real_, n_diff_gt_1e9 = sum(d > 1e-9))
}
ov <- as.Date("2023-01-01")
cmp <- list(
  returns = cmpf(p_R[Date >= ov], Rg[Date >= ov], c("Date","Ticker"), "Ret_1m", "Ret_1m"),
  bench   = cmpf(p_B[Date >= ov], BMg[Date >= ov], "Date", "BM_Ret", "BM_Ret"),
  size    = cmpf(p_M[Date >= ov], MEM[Date >= ov], c("Date","Ticker"), "Size", "Size"),
  adv     = cmpf(p_L[Date >= ov], LQg[Date >= ov], c("Date","Ticker"), "adv", "adv"))
jsonlite::write_json(list(vintage_new = VINTAGE, vintage_pinned = PINNED,
                          identical_vintage = identical(VINTAGE, PINNED), overlap_from = "2023-01-01",
                          bench_source_defect = list(
                            n_abnormal_days = nrow(bad_days),
                            dates = as.character(bad_days$Date),
                            override = BENCH_OVERRIDE),
                          compare = cmp),
                     file.path(OUT, "gridx_vintage_compare.json"), pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat(sprintf("[grid_ext] R %d행 | BM %d행 | LQ %d행 | MEM %d행 → %s\n",
            nrow(Rg), nrow(BMg), nrow(LQg), nrow(MEM), OUT))
