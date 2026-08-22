## WT-D20260813_006 / FQ-234 Lane B — 벤치 basis 라벨 실측 + 이중 보고 (Q-Lead 지시 2026-08-22)
## ①파이프라인이 실제로 쓴 벤치가 무엇인지 **실측 확인**(문서 서술 추정 금지)
## ②cap-w 유니버스-상대 + KOSPI200-상대 이중 산출
## ③screening 수치(SR/CAGR/IR)를 basis 라벨과 함께
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
J <- list(); TOPN <- 25L

P <- as.data.table(read_parquet(file.path(OUT, "absorb_panel.parquet"))); P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT, "fwd.rds"))
RET <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQ,"liq_ruler",attr(fwd$liq_dt,"liq_ruler",exact=TRUE))
setattr(LIQ,"liq_ruler_source",attr(fwd$liq_dt,"liq_ruler_source",exact=TRUE))
SIZE <- P[, .(Date, Ticker, Size)]
valid_sig <- sort(unique(RET$Date)); valid_sig <- valid_sig[valid_sig < as.Date("2026-06-01")]
RET <- RET[Date %in% valid_sig]; BEN <- BEN[Date %in% valid_sig]; LIQ <- LIQ[Date %in% valid_sig]
SIZE <- SIZE[Date %in% valid_sig]
ALPHA <- readRDS(file.path(OUT, "alpha_variants.rds"))
WIN <- list(long = as.Date(c("2000-01-01","2026-06-01")), clean = as.Date(c("2015-07-01","2026-06-01")))
in_win <- function(d, w) d >= WIN[[w]][1] & d < WIN[[w]][2]

## ══════ ① 실측: bench_dt 의 정체 ═══════════════════════════════════════════
## (a) 구성 규칙 = build_monthly_forward_returns 의 Size-가중 유니버스 forward 수익
## (b) KOSPI200 지수(IKS200) 월간 = BM_Close 월말 비율 (지수 레벨 비, 합성 아님)
BX <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
BX[, Date := as.Date(Date)]
sig_all <- sort(unique(fwd$returns_dt$Date))            # forward 구간 앵커 (d0 -> d1)
anchor <- data.table(Date = sig_all)
nxt <- data.table(Date = sig_all, Date1 = c(sig_all[-1], NA))
K <- merge(nxt, BX[, .(Date, C0 = BM_Close)], by = "Date")
K <- merge(K, BX[, .(Date1 = Date, C1 = BM_Close)], by = "Date1")
K[, BM_K200 := C1/C0 - 1]
K <- K[, .(Date, BM_K200)][Date %in% valid_sig]
CMP <- merge(BEN, K, by = "Date")
J$benchmark_identity <- list(
  pipeline_bench_construction = "build_monthly_forward_returns: weighted.mean(Ret_1m, w=Size at d0) over K200 UNION KQ150 members = **유니버스 cap-w proxy**",
  canonical_label_in_code = "canonical_screen_bt 가 benchmark_returns_tbl$benchmark_id 를 'KOSPI200_total_return' 으로 **하드코딩** — 실제 계열과 불일치(라벨 오기). 본 보고는 실계열 기준으로 라벨을 정정해 쓴다.",
  k200_source = ".cache/benchmark.parquet BM_Close (config.R DEFAULT_BM_CODE=IKS200) 월말 레벨 비",
  n_months = nrow(CMP),
  corr_pipeline_vs_k200 = cor(CMP$BM_Ret, CMP$BM_K200),
  mean_diff_monthly = mean(CMP$BM_Ret - CMP$BM_K200),
  mean_diff_annual = mean(CMP$BM_Ret - CMP$BM_K200) * 12,
  identical_series = isTRUE(all.equal(CMP$BM_Ret, CMP$BM_K200)))
for (w in c("long","clean")) {
  s <- CMP[in_win(Date, w)]
  J$benchmark_identity[[paste0("annual_", w)]] <- list(
    universe_capw_annual = mean(s$BM_Ret)*12, k200_annual = mean(s$BM_K200)*12,
    gap_annual_universe_minus_k200 = mean(s$BM_Ret - s$BM_K200)*12, n = nrow(s))
}

## ══════ ②③ 이중 basis 측정 ═══════════════════════════════════════════════
run_basis <- function(S, w, bench, tag) {
  s <- S[in_win(Date, w)]; r <- RET[in_win(Date, w)]
  b <- bench[in_win(Date, w)]
  l <- LIQ[in_win(Date, w)]; setattr(l,"liq_ruler",attr(LIQ,"liq_ruler",exact=TRUE))
  setattr(l,"liq_ruler_source",attr(LIQ,"liq_ruler_source",exact=TRUE))
  suppressWarnings(canonical_screen_bt(s, r, b, top_n = TOPN, cost_bps_oneway = 15,
    liq_dt = l, liq_min = 2e8, size_dt = SIZE[in_win(Date, w)],
    run_id = paste0("FQ234_", tag), strategy_id = paste0("FQ234_", tag), diag_dual_basis = FALSE))
}
own_metrics <- function(cs) {
  pr <- as.data.table(cs$period_returns)
  x <- xts(pr$ret_net, order.by = as.Date(pr$date))
  tab <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  list(own_cagr = as.numeric(tab[1,1]), own_vol = as.numeric(tab[2,1]),
       own_sharpe = as.numeric(tab[3,1]), max_dd = as.numeric(maxDrawdown(x)),
       basis_free = TRUE, source = "PerformanceAnalytics::table.AnnualizedReturns / maxDrawdown (표준함수)")
}
BEN_K <- K[, .(Date, BM_Ret = BM_K200)]
J$dual_basis <- list()
for (spec in c("primary","reverse_POSTHOC")) {
  A <- if (spec == "primary") ALPHA$primary else copy(ALPHA$primary)[, score := -score]
  for (w in c("long","clean")) {
    cu <- run_basis(A, w, BEN,   paste0(spec,"_capwUniv_",w))
    ck <- run_basis(A, w, BEN_K, paste0(spec,"_k200_",w))
    om <- own_metrics(cu)
    J$dual_basis[[paste0(spec,"__",w)]] <- list(
      basis_A_universe_capw = list(
        benchmark_label = "K200_UNION_KQ150_capweighted_universe_proxy (파이프라인 기본)",
        port_t = cu$portfolio_alpha_t_nw_lag3, IR = cu$information_ratio,
        active_sharpe_net_sr_field = cu$net_sr, alpha_ann = cu$alpha_annualized,
        mean_active_net = cu$mean_active_net, n_months = cu$n_months),
      basis_B_kospi200 = list(
        benchmark_label = "KOSPI200 (IKS200) 지수 월간수익",
        port_t = ck$portfolio_alpha_t_nw_lag3, IR = ck$information_ratio,
        active_sharpe_net_sr_field = ck$net_sr, alpha_ann = ck$alpha_annualized,
        mean_active_net = ck$mean_active_net, n_months = ck$n_months),
      basis_free_own = om,
      turnover_annual = cu$turnover_annual,
      note = "★canonical_screen_bt 의 net_sr 필드는 **active(초과) Sharpe = IR** 이지 전략 자체 Sharpe 가 아니다. screening 게이트의 SR 은 basis_free_own$own_sharpe 로 판정한다.")
  }
}

## ══════ screening 게이트 재판정 (basis 명시) ══════════════════════════════
J$screen_gate_dual <- list()
for (k in names(J$dual_basis)) {
  v <- J$dual_basis[[k]]
  own <- v$basis_free_own
  br1 <- isTRUE(own$own_sharpe >= 0.7) && isTRUE(own$own_cagr >= 0.12)
  J$screen_gate_dual[[k]] <- list(
    own_sharpe = own$own_sharpe, own_cagr = own$own_cagr, own_mdd = own$max_dd,
    branch1_sr07_cagr12 = br1,
    port_t_universe_capw = v$basis_A_universe_capw$port_t,
    port_t_kospi200 = v$basis_B_kospi200$port_t,
    bases_disagree_on_sign = (sign(v$basis_A_universe_capw$port_t) != sign(v$basis_B_kospi200$port_t)),
    note = "branch1 = [own SR>=0.7 AND own CAGR>=12%] (basis-free). branch2(score>=40)는 hurdle_gate 18-component 소관 — 본 단계 미산출.")
}

writeLines(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null"),
           file.path(OUT, "06_basis.json"))
cat("[done] 06_basis.json\n")
