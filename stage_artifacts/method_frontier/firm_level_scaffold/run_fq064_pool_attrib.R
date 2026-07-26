#==============================================================================
# run_fq064_pool_attrib.R — FQ-064 음(-) PORT_t 귀속 분해 (2026-07-26)
#
# 문제: FQ-064 신호 arm은 cap-w 벤치 대비 PORT_t −2.2156, NPS-풀 EW 대비 −2.147.
#   둘 다 음수인데, 이것이 (A) 신호가 나쁜 탓인지 (B) NPS-매칭 풀 자체가 시장 대비
#   열위인 탓인지 (C) 25종목 EW 스크린 자체의 구성/비용 페널티인지 분리되지 않았다.
#   random-null(20 seed)은 (C)+(B)를 함께 담고 있어 단독으론 (B)를 못 가른다.
#
# 이 스크립트가 재는 것 = **(B) 단독**: 신호를 전혀 쓰지 않은 NPS-매칭 풀 전체의
#   EW 수익을 시장 cap-w 벤치와 직접 대조한다. 종목 선택이 없으므로 (A)(C)가 소거된다.
#     pool_EW_t  ≈ 0  → 풀은 정상, 음수는 신호/구성 탓
#     pool_EW_t ≪ 0  → 풀 자체가 열위 = FQ-064 판정은 풀 편향에 오염
#
# 입력: fq064_out/fq064_canonical.json 의 diag_ew_universe.period_returns
#         (date, ret_net, ew_bench_ret=풀EW, active_ew) — 07-26 재실행분(bit-일치 확인됨)
#       + 표준 build_monthly_forward_returns 의 bench_dt(시장 cap-w)
# 산출: fq064_out/fq064_pool_attribution.json
# 규율: NW t는 계약 build_benchmark_compare 경유(자체합성 없음). metric_type=canonical_screen_diag.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
SCAF <- "stage_artifacts/method_frontier/firm_level_scaffold"
OUT  <- file.path(SCAF, "fq064_out")

source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/ramp/factor_validation.R")
stopifnot(exists("build_benchmark_compare"), exists("build_monthly_forward_returns"))

# ─── 1. 풀 EW 시계열 (신호 무관 — 매칭 풀 전체 동일가중) ─────────────────────
cj <- fromJSON(file.path(OUT, "fq064_canonical.json"), simplifyVector = TRUE)
pe <- as.data.table(cj$diag_ew_universe$period_returns)
stopifnot(all(c("date", "ew_bench_ret") %in% names(pe)), nrow(pe) > 0)
pe[, date := as.Date(date)]
setorder(pe, date)
cat(sprintf("[attrib] 풀 EW 시계열 %d개월 (%s ~ %s)\n",
            nrow(pe), min(pe$date), max(pe$date)))

# ─── 2. 시장 cap-w 벤치 (표준 함수 — 신호 arm과 동일 basis) ──────────────────
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% .MEND]
fwd <- build_monthly_forward_returns(RAWME, .MEND)
bench <- as.data.table(fwd$bench_dt)[, .(date = as.Date(Date), mkt_ret = BM_Ret)]

M <- merge(pe[, .(date, pool_ew = ew_bench_ret)], bench, by = "date")
stopifnot(nrow(M) > 0)
cat(sprintf("[attrib] 시장 벤치 정합 %d개월\n", nrow(M)))

# ─── 3. 계약 경유 NW t (풀 EW vs 시장 cap-w) ────────────────────────────────
prt <- data.table(date = M$date, ret_net = M$pool_ew, frequency = "monthly")
brt <- data.table(date = M$date, benchmark_ret = M$mkt_ret, benchmark_id = "MKT_capw_universe")
bc  <- build_benchmark_compare(prt, brt, run_id = "FQ064_pool_attrib",
                               strategy_id = "NPS_matched_pool_EW", annualization_factor = 12)
gv <- function(nm) { v <- bc[metric_name == nm, active_value]
                     if (length(v)) as.numeric(v[1]) else NA_real_ }

act <- M$pool_ew - M$mkt_ret
p17 <- M$date >= as.Date("2017-01-01")
.nw_t <- function(x) {          # 계약 미노출 구간(부기간)만 — 본 t는 계약값 사용
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2) / n; s <- g0
  for (l in 1:3) { gl <- sum(e[(l + 1):n] * e[1:(n - l)]) / n; s <- s + 2 * (1 - l / 4) * gl }
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s / n)
}

res <- list(
  metric_type = "canonical_screen_diag",
  metric_type_note = paste0(
    "신호 미사용 — NPS-매칭 풀 전체 EW 대 시장 cap-w. FQ-064 음(-) PORT_t의 ",
    "'풀 편향' 성분 단독 측정. HARD 게이트 비바인딩(판정 권위는 신호 arm cap-w)."),
  question = "NPS-매칭 풀 자체가 시장 대비 열위인가 (신호와 무관하게)",
  n_months = nrow(M),
  period = c(as.character(min(M$date)), as.character(max(M$date))),
  pool_ew_vs_mkt = list(
    portfolio_alpha_t_nw_lag3 = gv("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = gv("Portfolio_Alpha_t_pvalue"),
    information_ratio         = gv("Information_Ratio"),
    alpha_annualized          = gv("Alpha_Annualized"),
    mean_active_monthly       = mean(act),
    post2017_t_nw_lag3        = .nw_t(act[p17]),
    n_months_post2017         = sum(p17)),
  reference_arms = list(
    signal_vs_mkt_capw = cj$portfolio_alpha_t_nw_lag3,
    signal_vs_pool_ew  = cj$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    note = "07-26 재실행 실측(07-25 산출과 bit-일치)"),
  interpretation_rule = paste0(
    "pool_ew_vs_mkt t가 0 근처면 풀은 정상 → 신호 arm 음수는 신호/구성 탓. ",
    "t가 크게 음수면 풀 편향이 신호 arm 음수의 상당분을 설명 → FQ-064 판정 재프레이밍 필요."),
  benchmark_compare = bc)

write_json(res, file.path(OUT, "fq064_pool_attribution.json"),
           auto_unbox = TRUE, na = "null", pretty = TRUE)

cat(sprintf("\n[attrib] 풀 EW vs 시장 cap-w: t_NW=%.3f  p=%.4f  IR=%.3f  alpha_ann=%.4f\n",
    res$pool_ew_vs_mkt$portfolio_alpha_t_nw_lag3, res$pool_ew_vs_mkt$portfolio_alpha_t_pvalue,
    res$pool_ew_vs_mkt$information_ratio, res$pool_ew_vs_mkt$alpha_annualized))
cat(sprintf("[attrib] post2017 t=%.3f (n=%d)\n",
    res$pool_ew_vs_mkt$post2017_t_nw_lag3, res$pool_ew_vs_mkt$n_months_post2017))
cat(sprintf("[attrib] 대조 — 신호 vs 시장 %.4f / 신호 vs 풀EW %.4f\n",
    res$reference_arms$signal_vs_mkt_capw, res$reference_arms$signal_vs_pool_ew))
cat(sprintf("[out] %s\n", file.path(OUT, "fq064_pool_attribution.json")))
