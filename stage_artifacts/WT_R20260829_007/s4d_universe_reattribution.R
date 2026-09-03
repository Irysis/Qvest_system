# S4d — 재귀속 확정축: **회귀 표본 유니버스**
#   선행 런 analysis_fmb.csv 의 월평균 단면 N = 1397.7 (256개월) — K200 union KQ150(월중앙 ~339)이 아니라
#   유동성 통과 **전 시장**이다. 즉 t +3.199 는 mandate 유니버스에서 측정된 적이 없다.
#   여기서 전 시장 표본을 복원해 t 를 재현하고, 같은 표본을 K200 union KQ150 으로 좁혔을 때의 붕괴를 실측한다.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(RcppRoll)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
t0 <- Sys.time()

RAW <- as.data.table(arrow::read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","Ret","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2003-01-01") & is.finite(Close) & Close > 0]
setorder(RAW, Ticker, Date)
RAW[, hi_incl := { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_max(Close, n = min(252L, n), align="right", fill=NA) }, by = Ticker]
RAW[, hi_excl := shift(hi_incl, 1L), by = Ticker]
RAW[, prior_score := fifelse(is.finite(hi_excl) & hi_excl > 0, Close/hi_excl - 1, NA_real_)]
RAW[, dval := Vol*Close]
RAW[, avgtv20 := shift(frollmean(dval, n = pmin(seq_len(.N), 20L), adaptive = TRUE, na.rm = TRUE), 1L), by = Ticker]
cat(sprintf("[S4d] rolling done %.1fs · rows %d · tickers %d\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")), nrow(RAW), uniqueN(RAW$Ticker)))

udates <- sort(unique(RAW$Date))
ME <- as.Date(tapply(as.character(udates), format(udates, "%Y-%m"), max)); ME <- sort(ME)
ME <- ME[ME >= as.Date("2005-01-01") & ME <= as.Date("2026-08-31")]

M <- RAW[Date %in% ME, .(Date, Ticker, Close, Size, prior_score, avgtv20, K200, KQ150)]
setorder(M, Ticker, Date)
M[, mret := Close/shift(Close) - 1, by = Ticker]
M[, m12 := { s <- rep(0, .N); c0 <- rep(0L, .N)
             for (k in 0:11) { xx <- shift(mret, k); s <- s + fifelse(is.finite(xx), log1p(xx), 0); c0 <- c0 + as.integer(is.finite(xx)) }
             fifelse(c0 >= 10L, expm1(s), NA_real_) }, by = Ticker]
M[, fwd := shift(mret, -1L), by = Ticker]
M[, LiqPass := is.finite(avgtv20) & avgtv20 >= 2e8]
M[, in_index := (K200 == TRUE | KQ150 == TRUE)]
rm(RAW); gc(verbose = FALSE)

nw_prior <- function(x) { x <- x[!is.na(x)]; T_n <- length(x); if (T_n < 5) return(NA_real_)
  xb <- mean(x); L <- max(1, floor(T_n^(1/3))); v <- var(x)
  for (j in seq_len(L)) v <- v + 2*(1 - j/(L+1))*cov(x[1:(T_n-j)], x[(j+1):T_n])
  xb/sqrt(max(v/T_n, 1e-20)) }
zsd <- function(v) (v - mean(v, na.rm=TRUE))/max(sd(v, na.rm=TRUE), 1e-8)

run <- function(dt, lbl) {
  d <- dt[is.finite(prior_score) & is.finite(Size) & Size > 0 & is.finite(m12) & is.finite(fwd),
          .(Date, S = prior_score, lnS = log(Size), Mo = m12, Y = fwd)]
  co <- d[, { if (.N < 30L) NULL else { m <- copy(.SD)
      m[, `:=`(Sz = zsd(S), Lz = zsd(lnS), Mz = zsd(Mo))]
      f <- tryCatch(lm(Y ~ Sz + Lz + Mz, data = m), error=function(e) NULL)
      if (is.null(f)) NULL else c(as.list(coef(f)), list(N = .N)) } }, by = Date]
  list(label = lbl, n_months = nrow(co), n_cs_median = median(co$N),
       lambda_score = mean(co$Sz, na.rm=TRUE), t_score = nw_prior(co$Sz),
       lambda_size = mean(co$Lz, na.rm=TRUE), t_size = nw_prior(co$Lz),
       lambda_mom = mean(co$Mz, na.rm=TRUE), t_mom = nw_prior(co$Mz)) }

G <- list(
  U1_full_market_liqpass = run(M[LiqPass == TRUE], "전 시장 + 유동성 통과 (선행 런 표본 재구성)"),
  U2_full_market_all     = run(M, "전 시장 (유동성 무필터)"),
  U3_index_liqpass       = run(M[LiqPass == TRUE & in_index == TRUE], "K200 union KQ150 + 유동성 (mandate 유니버스)"),
  U4_index_only          = run(M[in_index == TRUE], "K200 union KQ150 (유동성 무필터)"))
cat("\n===== 유니버스 축 재귀속 (선행 사양 · 선행 정의 · 선행 NW 공식 고정) =====\n")
for (nm in names(G)) { x <- G[[nm]]
  cat(sprintf("%-24s N중앙=%5.0f  lambda=%+8.5f  t(Score)=%+7.3f | t(Size)=%+7.3f t(Mom)=%+7.3f  n=%d\n",
              nm, x$n_cs_median, x$lambda_score, x$t_score, x$t_size, x$t_mom, x$n_months)) }
cat("선행 런 보고치: N중앙~1398 · lambda +0.00494 · t +3.199 | Size t -3.225 | Mom t -1.886 (n=254~256)\n")

write_json(list(
  meta = list(wt_id = "WT-R20260829_007", test_id = "F4d — 유니버스 축 재귀속",
              metric_type = "cross_sectional_regression", envelope_applicability = "NOT_APPLICABLE",
              evidence = "stage_artifacts/alpha_search/20260612_132740_321992/analysis_fmb.csv 의 N 열 월평균 = 1397.7 (256개월)"),
  grid = G,
  reading = "선행 런의 FM 단면은 mandate 유니버스(K200 union KQ150, 월중앙 ~339)가 아니라 전 시장이었다. 유니버스를 mandate 로 좁혔을 때 t 가 어떻게 되는지가 이 표의 답이다."),
  file.path(OUT, "s4d_universe_reattribution.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("\n[S4d] done %.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))
