## arm B 성과 측정 + arm A 대비 짝지은 검정 (FQ233_ARMB_20260813)
## 사전등록 PREREG_armB_20260813.md §3(primary=q50 단독) §4(paired NW3 t, 문턱 ±2.0)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/fq233_probe0_20260813"

inp <- readRDS(file.path(OUT, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                         Ret_1m = as.numeric(Ret_1m))]
## 벤치 — 일별→월간 표준함수 집계 후 ym 키 (armA 와 동일 경로)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(returns_dt[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
stopifnot(nrow(bench_dt) >= 0.95 * uniqueN(returns_dt$Date))

sc <- as.data.table(read_parquet(file.path(OUT, "armB_scores.parquet")))[, Date := as.Date(Date)]

run_one <- function(col, tag) {
  s <- sc[, .(Date, Ticker = as.character(Ticker), score = as.numeric(get(col)))]
  r <- canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           strategy_id = paste0("FQ233_ARMB_", tag), run_id = "FQ233_ARMB_20260813")
  pr <- as.data.table(r$period_returns)
  px <- xts(pr$ret_net, order.by = as.Date(pr$date))
  list(tag = tag, res = r, pr = pr,
       sr_total = as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE)),
       cagr = as.numeric(Return.annualized(px, scale = 12, geometric = TRUE)),
       mdd  = as.numeric(maxDrawdown(px)))
}

cat("=== primary = q50 (사전등록 §3) ===\n")
B  <- run_one("q50", "q50_primary")
cat(sprintf("  total SR %+.4f · PORT_t %+.4f (p %.4f) · active IR %+.4f · CAGR %.2f%% · MDD %.2f%% · n=%d\n",
            B$sr_total, as.numeric(B$res$portfolio_alpha_t_nw_lag3),
            as.numeric(B$res$portfolio_alpha_t_pvalue), as.numeric(B$res$net_sr),
            100*B$cagr, 100*B$mdd, as.numeric(B$res$n_months)))

cat("\n=== secondary (기록만 — primary 교체 금지) ===\n")
S <- lapply(c("q10","q90"), function(cc) run_one(cc, cc))
for (s in S) cat(sprintf("  %-4s total SR %+.4f · PORT_t %+.4f · MDD %.2f%%\n",
                         s$tag, s$sr_total, as.numeric(s$res$portfolio_alpha_t_nw_lag3), 100*s$mdd))

cat("\n=== primary 검정: arm B(q50) − arm A 짝지은 NW lag-3 t ===\n")
A <- readRDS(file.path(OUT, "armA_canonical_result.rds"))
prA <- as.data.table(A$period_returns)[, .(date = as.Date(date), a = ret_net)]
prB <- B$pr[, .(date = as.Date(date), b = ret_net)]
j <- merge(prA, prB, by = "date")
cat(sprintf("  짝지은 달 %d (armA %d · armB %d)\n", nrow(j), nrow(prA), nrow(prB)))
stopifnot(nrow(j) >= 0.95 * min(nrow(prA), nrow(prB)))
d <- j$b - j$a
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }
t_paired <- nw_t(d)
cat(sprintf("  월평균 차이 %+.4f%%p · 연환산 %+.2f%%p · NW3 t = %+.4f\n",
            100*mean(d), 100*12*mean(d), t_paired))

verdict <- if (t_paired >= 2.0) "QUANTILE_TARGET_SUPPORTED" else
           if (t_paired <= -2.0) "QUANTILE_TARGET_INFERIOR" else "NOT_SUPPORTED_NO_DIFFERENCE"
cat(sprintf("\n★사전등록 §4 판정: paired NW3 t %+.4f vs ±2.0 → **%s**\n", t_paired, verdict))

write_json(list(round_id="FQ233_ARMB_20260813", prereg="PREREG_armB_20260813.md",
  metric_type="canonical_screen", selection_type="chain", primary="q50", verdict=verdict,
  primary_result=list(total_sr=B$sr_total, port_t=as.numeric(B$res$portfolio_alpha_t_nw_lag3),
    port_t_p=as.numeric(B$res$portfolio_alpha_t_pvalue), active_ir=as.numeric(B$res$net_sr),
    cagr=B$cagr, mdd=B$mdd, turnover=as.numeric(B$res$turnover_annual),
    n_months=as.numeric(B$res$n_months)),
  paired_vs_armA=list(n_months=nrow(j), mean_diff_monthly=mean(d),
    mean_diff_ann_pct=100*12*mean(d), nw3_t=t_paired, threshold=2.0),
  secondary=lapply(S, function(s) list(tag=s$tag, total_sr=s$sr_total,
    port_t=as.numeric(s$res$portfolio_alpha_t_nw_lag3), mdd=s$mdd)),
  note="secondary 는 기록 전용 — 사전등록 §3 이 primary 교체를 금지한다."),
  file.path(OUT,"armB_result.json"), auto_unbox=TRUE, pretty=TRUE, digits=8, na="null")
saveRDS(list(B=B, S=S, paired=list(t=t_paired, d=d, j=j)), file.path(OUT,"armB_full.rds"))
cat("\n저장: armB_result.json · armB_full.rds\n")
