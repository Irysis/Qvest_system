#!/usr/bin/env Rscript
# =============================================================================
# te_alpha_research.R — WT-D20260705_007 Alpha Research
# Transfer Entropy net-sink alpha — 정식 QEPM 엔벨로프 첫 canonical PORT_t 측정.
#
# 차별점 (vs 선행 STR_AS_TE FAIL):
#   (1) canonical_screen_bt 경유 portfolio_alpha_t_nw_lag3 (선행 NA — 처음 측정)
#   (2) K200∪KQ150 PIT + 2e8 유동성 (선행도 K200∪KQ150이나 top-decile 50종·proxy 게이트만)
#   (3) ★신규 축: raw net-sink Score를 sector/size/beta/vol 중립화 → 잔차 TE 신호 격리
#       + top-N deployment(20/25) canonical + subperiod + uncertainty-aware(confidence)
#
# PIT: TE는 rolling 252d(C1), 신호 t 기준 forward 1M 실현수익으로 IC/포트 측정.
#      유동성 t-1 ADV20(C10). 중립화는 횡단면(당월 sig_date 시점) 회귀 잔차만.
# 데이터: pin RAWDATA_pin20260703 (graduation vintage 고정).
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(dplyr); library(jsonlite)
}))
data.table::setDTthreads(2L)
try(arrow::set_cpu_count(2L), silent = TRUE)
.flog <- function(...) { cat(sprintf(...), file = stderr()); flush(stderr()) }
options(error = function() { .flog("[te] ERROR — traceback:\n"); traceback(2); quit(status = 3) })

PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE <- file.path(PROJ, ".cache")
OUT   <- file.path(PROJ, "stage_artifacts", "WT-D20260705_007")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

RAW_PIN <- file.path(CACHE, "RAWDATA_pin20260703.parquet")
BM_PIN  <- file.path(CACHE, "benchmark_pin20260703.parquet")
stopifnot(file.exists(RAW_PIN), file.exists(BM_PIN))

.flog("[te] loading pinned RAWDATA (open_dataset pushdown 2003+)...\n")
# ★ open_dataset+collect (read_parquet col_select은 OneDrive mmap crash 유발) + Date>=2003 pushdown
RAWDATA <- open_dataset(RAW_PIN) %>%
  filter(Date >= as.Date("2003-06-01")) %>%
  select(Date, Ticker, K200, KQ150, Sector, Sector_Lv2, Size, Close, Vol, Ret) %>%
  collect() %>% as.data.table()
RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
.flog("[te] RAWDATA loaded rows=%d\n", nrow(RAWDATA))

BM_DT <- as.data.table(read_parquet(BM_PIN))
BM_DT[, Date := as.Date(Date)]
setnames(BM_DT, old = intersect(names(BM_DT), "BM_Ret"), new = "BM_Ret", skip_absent = TRUE)

# ---- 유동성: 20d ADV(거래대금) t-1 ----
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & shift(AvgTV20, 1L) >= 2e8, by = Ticker]  # t-1 PIT

# =============================================================================
# TE 엔진 (fe_te_sink.R 로직 이식 — sector/market 인덱스 -> 종목 net sink)
# =============================================================================
.TE_WINDOW  <- 252L
.TE_NBIN    <- 3L
.TE_MIN_OBS <- 200L
.TE_MIN_SEC <- 5L

RAWDATA[, ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)
# 시그널은 2005~ (252d burn-in 위해 엔진은 전체 데이터 사용, FACTORS만 필터)
.sig_dates <- .month_ends[.month_ends >= as.Date("2005-01-01")]  # 신호 시작
.flog("[te] sig_dates: %d (%s ~ %s)\n", length(.sig_dates),
      as.character(min(.sig_dates)), as.character(max(.sig_dates)))

# universe snapshot: sig_date 시점 LiqPass + 섹터 + 시총 (PIT)
.snap <- RAWDATA[Date %in% .sig_dates & LiqPass == TRUE & is.finite(Size) & Size > 0 &
                   !is.na(Sector_Lv2) & nzchar(Sector_Lv2),
                 .(Date, Ticker, Size, Sector = Sector_Lv2)]
setkey(.snap, Date)
.flog("[te] snapshot rows=%d unique tickers=%d\n", nrow(.snap), uniqueN(.snap$Ticker))

# ★메모리 절감: wide 행렬은 (a) 스냅샷에 등장하는 티커만 (b) 2003~ 날짜만.
#   전체(1990~, 수천 티커)를 dense 캐스트하면 3GB+ → OneDrive 페이징 crash.
.univ_tk <- unique(.snap$Ticker)
.min_date <- as.Date("2003-06-01")   # 252d burn-in 여유 (2005-01 신호 위해 2004 초까지 필요)
.Wlong <- RAWDATA[Ticker %in% .univ_tk & Date >= .min_date & is.finite(Ret),
                  .(Date, Ticker, Ret)]
.flog("[te] wide-long rows=%d tickers=%d dates=%d\n", nrow(.Wlong),
      uniqueN(.Wlong$Ticker), uniqueN(.Wlong$Date))
.W <- dcast(.Wlong, Date ~ Ticker, value.var = "Ret")
.wdates <- .W$Date; .W[, Date := NULL]
.Wmat <- as.matrix(.W); .wtk <- colnames(.Wmat)
rm(.W, .Wlong); gc(verbose = FALSE)
.flog("[te] Wmat dim=%dx%d (%.0f MB)\n", nrow(.Wmat), ncol(.Wmat),
      as.numeric(object.size(.Wmat))/1e6)

.discretize <- function(x, nbin) {
  ok <- is.finite(x)
  if (sum(ok) < 10L) return(rep(NA_integer_, length(x)))
  qs <- quantile(x[ok], probs = seq_len(nbin - 1L)/nbin, na.rm = TRUE, type = 7)
  if (any(!is.finite(qs)) || length(unique(qs)) < (nbin - 1L)) {
    r <- rank(x, ties.method = "average", na.last = "keep")
    b <- ceiling(r / sum(ok) * nbin); b[b < 1L] <- 1L; b[b > nbin] <- nbin
    return(as.integer(b))
  }
  b <- findInterval(x, qs) + 1L; b[!ok] <- NA_integer_; as.integer(b)
}
.te_xy <- function(xb, yb, nbin) {
  n <- length(yb); if (n < 30L) return(NA_real_)
  y1 <- yb[-1L]; y0 <- yb[-n]; x0 <- xb[-n]
  ok <- is.finite(y1) & is.finite(y0) & is.finite(x0)
  if (sum(ok) < 30L) return(NA_real_)
  y1 <- y1[ok]; y0 <- y0[ok]; x0 <- x0[ok]; N <- length(y1)
  idx3 <- (y1-1L)*nbin*nbin + (y0-1L)*nbin + (x0-1L) + 1L
  p3 <- tabulate(idx3, nbins = nbin^3)/N
  p_y0x0 <- tabulate((y0-1L)*nbin + (x0-1L) + 1L, nbins = nbin^2)/N
  p_y1y0 <- tabulate((y1-1L)*nbin + (y0-1L) + 1L, nbins = nbin^2)/N
  p_y0   <- tabulate(y0, nbins = nbin)/N
  te <- 0
  for (a in seq_len(nbin)) for (b in seq_len(nbin)) for (c in seq_len(nbin)) {
    i3 <- (a-1L)*nbin*nbin + (b-1L)*nbin + (c-1L) + 1L; pj <- p3[i3]; if (pj <= 0) next
    pyx <- p_y0x0[(b-1L)*nbin + (c-1L) + 1L]; pyy <- p_y1y0[(a-1L)*nbin + (b-1L) + 1L]; py <- p_y0[b]
    if (pyx <= 0 || pyy <= 0 || py <= 0) next
    te <- te + pj * log((pj/pyx)/(pyy/py))
  }
  if (!is.finite(te) || te < 0) te <- max(te, 0, na.rm = TRUE); te
}

cat(sprintf("[te] computing net-sink over %d sig_dates...\n", length(.sig_dates)))
# RAWDATA는 이후 불필요 (TE는 .Wmat/.snap만 사용) → 메모리 해제
rm(RAWDATA); gc(verbose = FALSE)
.flog("[te] RAWDATA freed. starting TE loop...\n")
.t0 <- Sys.time()
.sig_list <- vector("list", length(.sig_dates)); .k <- 0L
for (.ti in seq_along(.sig_dates)) {
  if (.ti %% 12L == 1L)
    .flog("[te] loop %d/%d (%s) elapsed=%.0fs k=%d\n", .ti, length(.sig_dates),
          as.character(.sig_dates[.ti]), as.numeric(difftime(Sys.time(), .t0, units="secs")), .k)
  t <- .sig_dates[.ti]; ti <- match(t, .wdates)
  if (is.na(ti) || ti < .TE_WINDOW) next
  lo <- ti - .TE_WINDOW + 1L; Rt <- .Wmat[lo:ti, , drop = FALSE]
  snap_t <- .snap[.(t)]; if (nrow(snap_t) < 20L || is.na(snap_t$Ticker[1])) next
  cidx <- match(snap_t$Ticker, .wtk); snap_t <- snap_t[!is.na(cidx)]; cidx <- cidx[!is.na(cidx)]
  if (length(cidx) < 20L) next
  Rk <- Rt[, cidx, drop = FALSE]
  valid <- colSums(is.finite(Rk)) >= .TE_MIN_OBS
  snap_t <- snap_t[valid]; cidx <- cidx[valid]; Rk <- Rk[, valid, drop = FALSE]
  if (nrow(snap_t) < 20L) next
  tks <- snap_t$Ticker; Rk[!is.finite(Rk)] <- NA_real_
  Rk0 <- Rk; Rk0[is.na(Rk0)] <- 0
  szv <- snap_t$Size; mkt_w <- szv/sum(szv); mkt_idx <- as.vector(Rk0 %*% mkt_w)
  sec_of <- snap_t$Sector; sec_levels <- unique(sec_of); sec_idx_map <- list()
  for (sc in sec_levels) {
    sel <- which(sec_of == sc); if (length(sel) < .TE_MIN_SEC) next
    w <- szv[sel]/sum(szv[sel]); sec_idx_map[[sc]] <- as.vector(Rk0[, sel, drop = FALSE] %*% w)
  }
  mkt_b <- .discretize(mkt_idx, .TE_NBIN)
  sec_b_map <- lapply(sec_idx_map, .discretize, nbin = .TE_NBIN)
  stk_b <- apply(Rk, 2L, .discretize, nbin = .TE_NBIN)
  nstk <- length(tks); Sc <- rep(NA_real_, nstk)
  for (j in seq_len(nstk)) {
    yb <- stk_b[, j]; if (sum(is.finite(yb)) < .TE_MIN_OBS) next
    src_set <- list(market = mkt_b); own <- sec_of[j]
    if (!is.null(sec_b_map[[own]])) src_set[["own"]] <- sec_b_map[[own]]
    inflow <- 0; outflow <- 0; cnt <- 0L
    for (sb in src_set) {
      if (is.null(sb) || sum(is.finite(sb)) < .TE_MIN_OBS) next
      te_in <- .te_xy(sb, yb, .TE_NBIN); te_out <- .te_xy(yb, sb, .TE_NBIN)
      if (is.finite(te_in) && is.finite(te_out)) { inflow <- inflow + te_in; outflow <- outflow + te_out; cnt <- cnt + 1L }
    }
    if (cnt == 0L) next
    Sc[j] <- inflow - outflow
  }
  ok <- is.finite(Sc); if (!any(ok)) next
  .k <- .k + 1L; .sig_list[[.k]] <- data.table(Date = t, Ticker = tks[ok], Score = Sc[ok])
}
.sig_list <- .sig_list[seq_len(.k)]
FACTORS <- rbindlist(.sig_list)
FACTORS <- FACTORS[Date >= as.Date("2005-01-01")]
rm(.Wmat); gc(verbose = FALSE)
cat(sprintf("[te] net-sink raw: rows=%d dates=%d tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

saveRDS(FACTORS, file.path(OUT, "te_netsink_raw.rds"))
.flog("[te] saved raw signal. rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date))
cat("[te] saved raw signal.\n")
