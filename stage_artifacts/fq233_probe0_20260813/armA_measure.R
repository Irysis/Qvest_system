## arm A 성과 측정 — R 계약 경유 (FQ233_ARMA_20260813)
## 사전등록 = PREREG_armA_20260813.md §3. Python 은 스코어까지만, 성과는 여기서.
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/fq233_probe0_20260813/armA_measure.R")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/fq233_probe0_20260813"

sc <- as.data.table(read_parquet(file.path(OUT, "armA_scores.parquet")))
sc[, Date := as.Date(Date)]
scores_dt <- sc[, .(Date, Ticker = as.character(Ticker), score = as.numeric(score))]
cat(sprintf("스코어 %d행 · %d개월 (%s ~ %s)\n", nrow(scores_dt), uniqueN(scores_dt$Date),
            min(scores_dt$Date), max(scores_dt$Date)))

inp <- readRDS(file.path(OUT, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                         Ret_1m = as.numeric(Ret_1m))]
cat(sprintf("forward %d행 · %d개월\n", nrow(returns_dt), uniqueN(returns_dt$Date)))

## 벤치마크 — 정본 benchmark.parquet (IKS200. 버그벤치 IKS001 아님)
## ★★초판이 밟은 함정: 이 파일은 **일별**(9,007행·간격 1일)인데 월간처럼 썼다.
##   `Date %in% returns_dt$Date` 로 거른 133행은 '월초가 거래일인 날의 **하루치** 수익' 이었고,
##   결과적으로 월간 포트 수익을 하루치 벤치와 비교했다(백테 n_months 199→101 로 잘림).
## 수리: 일별 → 월간 집계는 **PerformanceAnalytics 표준**(`apply.monthly` + `Return.cumulative`).
##   ⚠repo 내 `fq081_build_benchmark()` 는 `prod(1+BM_Ret)-1` 자체 합성이라 재사용하지 않는다
##   (answer-principles 자체합성 금지 — 값이 같아도 경로가 게이트).
suppressPackageStartupMessages({library(xts); library(PerformanceAnalytics)})
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
cat("benchmark 컬럼:", paste(names(bm), collapse = ", "), "\n")
bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
cat(sprintf("bench 원본 %d행(일별) · %s ~ %s\n", nrow(bm), min(bm$Date), max(bm$Date)))
bx  <- xts(bm$BM_Ret, order.by = bm$Date)
bmm <- apply.monthly(bx, Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))

## 포트 축(anchor=보유월 월초)과 **ym 키**로 맞춘다 — 정확일치 금지(컨벤션 다름)
axis_dt <- unique(returns_dt[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
cat(sprintf("bench 월간 %d개월 → 포트 축 정렬 후 %d개월\n", nrow(bench_m), nrow(bench_dt)))
## ★조인 손실 감시 — 유니버스에만 박고 벤치엔 안 박아서 이번에 또 밟았다
.cov <- nrow(bench_dt) / uniqueN(returns_dt$Date)
if (.cov < 0.95) stop(sprintf("벤치 축 덮개 %.1f%% — 컨벤션 불일치 의심(중단)", 100*.cov))

cat("\n=== canonical_screen_bt (top-25 EW long-only · 15bps · liq 2e8) ===\n")
res <- canonical_screen_bt(scores_dt = scores_dt, returns_dt = returns_dt, bench_dt = bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           strategy_id = "FQ233_ARMA_meanTarget_XGB",
                           run_id = "FQ233_ARMA_20260813")
str_num <- function(x) if (is.null(x) || !is.finite(x)) "NA" else sprintf("%+.4f", x)
cat("\n--- 반환 필드 ---\n"); print(names(res))

m <- res
cat("\n=== 판정 1급 결과량 ===\n")
for (k in c("net_sr","portfolio_alpha_t_nw_lag3","portfolio_alpha_t_pvalue","information_ratio",
            "alpha_annualized","mean_active_net","n_months","top_n","turnover_annual",
            "selected_ret_coverage","metric_type")) {
  v <- m[[k]]
  if (is.null(v)) next
  cat(sprintf("  %-28s %s\n", k,
              if (is.numeric(v)) str_num(as.numeric(v)[1]) else as.character(v)[1]))
}
## ★기간 손실 감시 — 초판은 199개월 스코어가 101개월로 잘렸는데 조용히 통과했다
.exp_m <- uniqueN(scores_dt$Date)
cat(sprintf("\n기간 대조: 스코어 %d개월 → 백테 %s개월 (%.1f%%)\n",
            .exp_m, m$n_months, 100 * as.numeric(m$n_months) / .exp_m))
if (as.numeric(m$n_months) < 0.95 * .exp_m)
  warning(sprintf("★백테 기간이 스코어 대비 %.1f%% — 축 손실 조사 필요",
                  100 * as.numeric(m$n_months) / .exp_m), call. = FALSE)

## 사전등록 §4 판정 밴드 [0.30, 0.70]
.sr <- suppressWarnings(as.numeric(m$net_sr)[1])
verdict <- if (!is.finite(.sr)) "MEASUREMENT_FAILED" else
           if (.sr >= 0.30 && .sr <= 0.70) "REPRODUCED" else
           if (.sr < 0.30) "NOT_REPRODUCED_LOW" else "NOT_REPRODUCED_HIGH_CHECK_LEAKAGE"
cat(sprintf("\n★사전등록 판정: net_sr = %s vs 밴드 [0.30, 0.70] → **%s**\n", str_num(.sr), verdict))
if (verdict == "NOT_REPRODUCED_HIGH_CHECK_LEAKAGE")
  cat("  ⇒ 사전등록 §4 의무 점검 3종(lag1 스트레스 · 학습창 인덱스 감사 · Hit_Ratio) 즉시 수행\n")
saveRDS(res, file.path(OUT, "armA_canonical_result.rds"))
write_json(res, file.path(OUT, "armA_canonical_result.json"), auto_unbox = TRUE,
           pretty = TRUE, digits = 8, na = "null")
cat(sprintf("\n저장: armA_canonical_result.{rds,json}\n"))
