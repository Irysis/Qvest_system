# S1 — 주간 패널 재구성 + GH2005 준거가격/오버행 g 산출 (WT-R20260829_011)
#  사양 정본 = alpha_hypothesis.json::design_constants_preregistered #1~#8 (승계·재작성 금지)
#  PIT: 각 형성시점의 R 은 그 시점 이전 주 데이터만으로 재계산(확장창). C1/C2/C10.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_011"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
t0 <- Sys.time()

rl <- load_rawdata(use_cache = TRUE)
RAW <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl); gc(verbose = FALSE)
if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date")) BM_DT[, Date := as.Date(Date)]

## -- 월말 거래일 + 유니버스(K200 U KQ150, PIT 시변) --
alld <- sort(unique(RAW$Date))
ym_i <- as.integer(format(alld, "%Y")) * 12L + as.integer(format(alld, "%m"))
ME_all <- alld[c(diff(ym_i) > 0, TRUE)]
ME <- ME_all[ME_all >= as.Date("2005-01-01") & ME_all <= as.Date("2026-08-31")]
mem <- unique(RAW[Date %in% ME & (K200 == TRUE | KQ150 == TRUE),
                  .(Date, Ticker, mkt = fifelse(K200 == TRUE, "K200", "KQ150"))])
UNIV_TK <- sort(unique(mem$Ticker))
cat(sprintf("[S1] ME: %d months (%s ~ %s) | universe-ever tickers: %d | median names/mo %.0f\n",
            length(ME), min(ME), max(ME), length(UNIV_TK), median(mem[, .N, by = Date]$N)))

## -- 주간 축 재구성 (design_constants #1) --
WK_START <- as.Date("1997-06-01")
D <- RAW[Ticker %chin% UNIV_TK & Date >= WK_START,
         .(Date, Ticker, Close, Vol, Size, Ret, TradingHalt, AdminStock)]
rm(RAW); gc(verbose = FALSE)
D[, wk := as.integer((as.numeric(Date) + 3L) %/% 7L)]
D[, est_sh := fifelse(is.finite(Size) & is.finite(Close) & Close > 0, Size / Close, NA_real_)]
setorder(D, Ticker, Date)
D[, d_logsh := c(NA_real_, diff(log(pmax(est_sh, 1e-12)))), by = Ticker]
D[, sh_jump := is.finite(d_logsh) & abs(d_logsh) > 0.4]

WK <- D[, .(Date_end   = max(Date),
            Close_end  = Close[which.max(Date)],
            Size_end   = Size[which.max(Date)],
            est_sh_end = est_sh[which.max(Date)],
            Vol_sum    = sum(Vol, na.rm = TRUE),
            cum_ret    = prod(1 + ifelse(is.finite(Ret), Ret, 0)),
            halt       = as.integer(any(TradingHalt == 1, na.rm = TRUE) | any(AdminStock == 1, na.rm = TRUE)),
            shjump     = as.integer(any(sh_jump, na.rm = TRUE)),
            nd         = .N),
        by = .(Ticker, wk)]
setorder(WK, Ticker, wk)
rm(D); gc(verbose = FALSE)

WK[, V_raw := fifelse(is.finite(est_sh_end) & est_sh_end > 0, Vol_sum / est_sh_end, NA_real_)]
n_shjump <- sum(WK$shjump == 1L); n_halt <- sum(WK$halt == 1L)
WK[, V := V_raw]
WK[shjump == 1L, V := NA_real_]
WK[halt == 1L,   V := 0]
WK[!is.finite(V), V := 0]
WK[, V := pmin(pmax(V, 0), 0.999)]
cat(sprintf("[S1] weekly rows %d | shjump-weeks %d (%.3f%%) | halt/admin-weeks %d (%.2f%%) | V>0 med %.4f p90 %.4f\n",
            nrow(WK), n_shjump, 100*n_shjump/nrow(WK), n_halt, 100*n_halt/nrow(WK),
            median(WK$V[WK$V > 0]), as.numeric(quantile(WK$V[WK$V > 0], .9))))

WK[, P_ret := cumprod(cum_ret), by = Ticker]
WK[, P_cls := Close_end]

## -- 주 격자(연속 정수) x 종목 행렬화 --
wk_grid <- seq(min(WK$wk), max(WK$wk))
tk <- sort(unique(WK$Ticker))
Tn <- length(wk_grid); Nn <- length(tk)
idx_w <- match(WK$wk, wk_grid); idx_t <- match(WK$Ticker, tk)
mk <- function(v, fill = NA_real_) { M <- matrix(fill, Tn, Nn); M[cbind(idx_w, idx_t)] <- v; M }
Vm  <- mk(WK$V, 0)
PAm <- mk(WK$P_ret); PCm <- mk(WK$P_cls); SZm <- mk(WK$Size_end)
locf <- function(M) {
  for (j in seq_len(ncol(M))) {
    x <- M[, j]; ok <- which(is.finite(x))
    if (!length(ok)) next
    f <- ok[1]
    y <- x; idx <- cummax(ifelse(is.finite(x), seq_along(x), 0L))
    y[idx > 0] <- x[idx[idx > 0]]
    y[seq_len(f - 1L)] <- NA_real_
    M[, j] <- y
  }
  M
}
PAm <- locf(PAm); PCm <- locf(PCm); SZm <- locf(SZm)
cat(sprintf("[S1] grid: %d weeks x %d tickers\n", Tn, Nn))

## -- 준거가격 R (Eq.9, 260주 절단 + 재정규화 k) --
shiftd <- function(M, n) { if (n == 0L) return(M)
  rbind(matrix(NA_real_, n, ncol(M)), M[seq_len(nrow(M) - n), , drop = FALSE]) }
mkCL <- function(V) apply(log(1 - V), 2, cumsum)
CL <- mkCL(Vm); CL1 <- shiftd(CL, 1L)
ref_price <- function(Pm, W, CLx, CL1x, Vx) {
  num <- matrix(0, Tn, Nn); den <- matrix(0, Tn, Nn)
  for (n in seq_len(W)) {
    wgt <- shiftd(Vx, n) * exp(CL1x - shiftd(CLx, n))
    p   <- shiftd(Pm, n)
    ok  <- is.finite(wgt) & is.finite(p)
    wgt[!ok] <- 0; p[!ok] <- 0
    num <- num + wgt * p; den <- den + wgt
  }
  R <- num / den; R[!is.finite(R) | den <= 0] <- NA_real_; R
}
mk_g <- function(Pm, W, CLx = CL, CL1x = CL1, Vx = Vm) {
  R <- ref_price(Pm, W, CLx, CL1x, Vx)
  Pl <- shiftd(Pm, 1L)
  G <- (Pl - R) / Pl
  G[!is.finite(G)] <- NA_real_
  G
}
G260 <- mk_g(PAm, 260L)
cat(sprintf("[S1] g260 done %.0fs | coverage %.1f%%\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), 100 * mean(is.finite(G260))))
G156 <- mk_g(PAm, 156L); G364 <- mk_g(PAm, 364L)
G260c <- mk_g(PCm, 260L)

## -- gbar: 실제 V 대신 직전 52주 평균 V (Table 4 / F5) --
Vbar52 <- { S <- matrix(0, Tn, Nn); for (k in 1:52) { x <- shiftd(Vm, k); x[!is.finite(x)] <- 0; S <- S + x }; S / 52 }
Vb <- pmin(pmax(Vbar52, 1e-8), 0.999)
CLb <- mkCL(Vb); CL1b <- shiftd(CLb, 1L)
GBAR <- mk_g(PAm, 260L, CLb, CL1b, Vb)

## -- 5년 이력 요구 마스크 (#8 / INV-5) --
firstok <- apply(is.finite(PAm), 2, function(x) { w <- which(x); if (length(w)) w[1] else NA_integer_ })
HIST    <- outer(seq_len(Tn), firstok, function(i, f) i - f >= 260L); HIST[is.na(HIST)] <- FALSE
HIST156 <- outer(seq_len(Tn), firstok, function(i, f) i - f >= 156L); HIST156[is.na(HIST156)] <- FALSE

## -- 주간 수익 / 과거수익 / 평균회전율 --
RETW <- PAm / shiftd(PAm, 1L) - 1
cumret <- function(a, b) { X <- matrix(1, Tn, Nn)
  for (k in a:b) { r <- shiftd(RETW, k); r[!is.finite(r)] <- 0; X <- X * (1 + r) }; X - 1 }
RW_4_1    <- cumret(1, 4)
RW_52_5   <- cumret(5, 52)
RW_156_53 <- cumret(53, 156)
VBAR4   <- { S <- matrix(0, Tn, Nn); for (k in 1:4)    { x <- shiftd(Vm, k); x[!is.finite(x)] <- 0; S <- S + x }; S / 4 }
VBAR52  <- Vbar52
VBAR156 <- { S <- matrix(0, Tn, Nn); for (k in 53:156) { x <- shiftd(Vm, k); x[!is.finite(x)] <- 0; S <- S + x }; S / 104 }
LOGSZ <- log(pmax(SZm, 1))

wk_end <- WK[, .(wk_end = max(Date_end)), by = wk][order(wk)]

saveRDS(list(wk_grid = wk_grid, tk = tk, ME = ME, mem = mem,
             G260 = G260, G156 = G156, G364 = G364, G260c = G260c, GBAR = GBAR,
             HIST = HIST, HIST156 = HIST156, RETW = RETW,
             RW_4_1 = RW_4_1, RW_52_5 = RW_52_5, RW_156_53 = RW_156_53,
             VBAR4 = VBAR4, VBAR52 = VBAR52, VBAR156 = VBAR156, LOGSZ = LOGSZ,
             PAm = PAm, Vm = Vm, wk_end = wk_end,
             counts = list(n_shjump = n_shjump, n_halt = n_halt, n_weekrows = nrow(WK))),
        file.path(OUT, "s1_weekly.rds"))
cat(sprintf("[S1] saved. elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
