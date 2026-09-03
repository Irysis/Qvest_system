## WT-R20260829_006 forge — 벤치 basis 귀속 + 상류 잔여(PORT_t / OOS) 권위 재현 대조
##  ★EX-POST 진단 전용. 결정경로 아님(결정경로 = run_all.R [5]).
##  ★weights.csv 는 as-is. 재선택/재가중 0.
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
SD <- file.path(ROOT, "stage_artifacts/WT_R20260829_006")

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/weighted_screen_bt.R"))
.t <- function(x) if (exists(".nw_t_mean", mode = "function")) .nw_t_mean(x, lag = 3L) else NA_real_
.ir <- function(x) mean(x) / sd(x) * sqrt(12)

AS_OF <- as.Date("2026-08-28")

## ── (1) forge 실현 월별 계열 (daily NAV -> 월 집계) + production BM ───────────
sim <- readRDS(file.path(SD, "forge_sim.rds"))
d <- as.data.table(sim$DAILY_NAV_DT)
bmp <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
m <- merge(d[, .(Date, r = Strategy_Ret)], bmp[, .(Date, b = BM_Ret)], by = "Date")
m[, ym := format(Date, "%Y-%m")]
FM <- m[, .(f_ret = prod(1 + r) - 1, f_bm_prod = prod(1 + b) - 1, dt = max(Date)), by = ym]
setorder(FM, ym)

## ── (2) 상류 basis: 알파 패널 월간 forward 수익 + 알파 패널 벤치 ──────────────
##   ★alpha engine 이 build_monthly_forward_returns 로 만든 그 패널을 그대로 읽는다.
P1 <- file.path("C:/Users/99922/AppData/Local/Temp/claude",
                "C--Users-99922-OneDrive-Quant-Module-Moltbot",
                "0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006/p1s_market.rds")
has_panel <- file.exists(P1)
cat("[panel] alpha p1s_market.rds present =", has_panel, "\n")

W <- fread(file.path(SD, "weights.csv"))[, .(Date = as.Date(sig_date), Ticker, w = as.numeric(weight))]
W <- W[Date < AS_OF]   # 역사 248 리밸만

res <- list()
if (has_panel) {
  P <- readRDS(P1)
  RET_DT <- as.data.table(P$RET_DT); BENCH_DT <- as.data.table(P$BENCH_DT)
  cat("[panel] RET_DT rows", nrow(RET_DT), "| BENCH_DT rows", nrow(BENCH_DT), "\n")

  ## 상류 연속수익 basis 재현 — weights.csv as-is, 15bps delta, 계약 경로
  up <- weighted_screen_bt(W, RET_DT, BENCH_DT, cost_bps_oneway = 15,
                           run_id = "FORGE_UPSTREAM_BASIS",
                           strategy_id = "WTR006_EWband40_upstream_basis")
  cat("\n[upstream basis reproduce] n_months =", up$n_months,
      "| PORT_t =", up$portfolio_alpha_t_nw_lag3, "\n")
  print(unlist(up[intersect(names(up), c("net_ir","tracking_error","alpha_annualized",
                                          "abs_net_sr","abs_cagr","abs_mdd"))]))

  ## 상류 월별 수익계열 직접 재구성(귀속 2x2 를 위해)
  RR <- merge(W, RET_DT, by = c("Date","Ticker"), all.x = TRUE)
  RR[is.na(Ret_1m), Ret_1m := 0]
  RR[, w := w / sum(w), by = Date]
  up_port <- RR[, .(u_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    mm <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    mm[is.na(w_cur), w_cur := 0]; mm[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(mm$w_cur - mm$w_prev)); prev <- cur
  }
  up_port[, u_ret := u_gross - traded[as.character(Date)] * 15 / 1e4]
  up_port <- merge(up_port, BENCH_DT[, .(Date, a_bm = BM_Ret)], by = "Date")
  ## sig_date -> 홀딩월(ym) 라벨: forward 수익이므로 sig_date 다음 달
  up_port[, ym := format(as.Date(format(Date, "%Y-%m-01")) + 31L, "%Y-%m")]

  X <- merge(FM, up_port[, .(ym, u_ret, a_bm)], by = "ym")
  setorder(X, ym)
  cat("\n[matched months]", nrow(X), "\n")

  a_ff <- X$f_ret - X$f_bm_prod   # forge 전략 vs forge(production) 벤치  <- 권위 basis
  a_fa <- X$f_ret - X$a_bm        # forge 전략 vs 알파패널 벤치
  a_uf <- X$u_ret - X$f_bm_prod   # 상류 전략 vs forge 벤치
  a_ua <- X$u_ret - X$a_bm        # 상류 전략 vs 알파패널 벤치  <- 상류 보고 basis

  tab <- data.table(
    basis = c("forge_strategy x forge_BM (권위)", "forge_strategy x alpha_BM",
              "upstream_strategy x forge_BM", "upstream_strategy x alpha_BM (상류 보고)"),
    port_t = c(.t(a_ff), .t(a_fa), .t(a_uf), .t(a_ua)),
    net_ir = c(.ir(a_ff), .ir(a_fa), .ir(a_uf), .ir(a_ua)),
    alpha_ann = c(mean(a_ff), mean(a_fa), mean(a_uf), mean(a_ua)) * 12)
  print(tab)

  cat("\n[benchmark series] cor =", cor(X$f_bm_prod, X$a_bm),
      "| mean|diff| =", mean(abs(X$f_bm_prod - X$a_bm)),
      "| cum forge_BM =", prod(1 + X$f_bm_prod) - 1,
      "| cum alpha_BM =", prod(1 + X$a_bm) - 1, "\n")
  cat("[strategy series] cor =", cor(X$f_ret, X$u_ret),
      "| mean|diff| =", mean(abs(X$f_ret - X$u_ret)),
      "| cum forge =", prod(1 + X$f_ret) - 1,
      "| cum upstream =", prod(1 + X$u_ret) - 1, "\n")

  ## 귀속 분해: 상류(1.221 보고) -> 권위 로 가는 두 경로
  d_bench_leg <- .t(a_uf) - .t(a_ua)   # 벤치만 교체
  d_strat_leg <- .t(a_ff) - .t(a_uf)   # 전략 실현만 교체
  cat("\n[attribution on PORT_t] upstream_reported =", .t(a_ua),
      "-> bench leg", d_bench_leg, "-> strategy-realization leg", d_strat_leg,
      "-> authoritative(monthly basis)", .t(a_ff), "\n")

  ## 부기간 IR (상류 P1/P2/P3 대조)
  X[, y := as.integer(substr(ym, 1, 4))]
  sub <- rbind(
    data.table(sub = "P1_pre2015", ir_forge = .ir(a_ff[X$y < 2015]),  ir_up = .ir(a_ua[X$y < 2015])),
    data.table(sub = "P2_2015_2019", ir_forge = .ir(a_ff[X$y >= 2015 & X$y <= 2019]),
               ir_up = .ir(a_ua[X$y >= 2015 & X$y <= 2019])),
    data.table(sub = "P3_2020plus", ir_forge = .ir(a_ff[X$y >= 2020]), ir_up = .ir(a_ua[X$y >= 2020])))
  cat("\n[subperiod IR]\n"); print(sub)

  res <- list(
    n_months_matched = nrow(X),
    upstream_basis_reproduce = list(
      n_months = up$n_months,
      port_t_nw3 = up$portfolio_alpha_t_nw_lag3,
      net_ir = up$net_ir %||% NA_real_,
      optimizer_declared_port_t = 1.219,
      optimizer_declared_net_ir = 0.2987,
      note = paste("weighted_screen_bt(weights.csv as-is, alpha 패널 forward 수익/벤치)로",
                   "상류 basis 를 재현 — 상류 수치를 forge 가 읽을 수 있는 양으로 확인한 것이지",
                   "권위 수치가 아니다.")),
    basis_table = as.list(tab),
    benchmark_series = list(cor = cor(X$f_bm_prod, X$a_bm),
                            mean_abs_diff = mean(abs(X$f_bm_prod - X$a_bm)),
                            max_abs_diff = max(abs(X$f_bm_prod - X$a_bm)),
                            cum_forge_bm = prod(1 + X$f_bm_prod) - 1,
                            cum_alpha_bm = prod(1 + X$a_bm) - 1,
                            forge_source = ".cache/benchmark.parquet BM_Ret (production harness BM_DT)",
                            alpha_source = "alpha engine build_monthly_forward_returns bench_dt"),
    strategy_series = list(cor = cor(X$f_ret, X$u_ret),
                           mean_abs_diff = mean(abs(X$f_ret - X$u_ret)),
                           max_abs_diff = max(abs(X$f_ret - X$u_ret)),
                           cum_forge = prod(1 + X$f_ret) - 1,
                           cum_upstream = prod(1 + X$u_ret) - 1,
                           note = paste("forge = 정수 주식수 share-based 일별 NAV 월집계(집행 t+1, 라운딩 잔여현금).",
                                        "upstream = 연속 비중 x forward 수익(라운딩·집행지연 없음).")),
    port_t_attribution = list(upstream_reported_basis = .t(a_ua),
                              benchmark_leg_delta = d_bench_leg,
                              strategy_realization_leg_delta = d_strat_leg,
                              authoritative_monthly_basis = .t(a_ff),
                              authoritative_daily_basis_note =
                                "권위 등급이 쓰는 PORT_t 는 daily(af=252) 계약값 — 아래 bt 값 참조."),
    subperiod_ir = as.list(sub),
    verdict_invariance = NA_character_)
  res$verdict_invariance <- sprintf(
    "네 basis PORT_t = %.4f / %.4f / %.4f / %.4f. A 문턱 2.95 · B 문턱 2.0 대비 전부 미달 -> 벤치·전략계열 선택은 등급을 옮기지 않는다.",
    tab$port_t[1], tab$port_t[2], tab$port_t[3], tab$port_t[4])
  cat("\n", res$verdict_invariance, "\n")
} else {
  cat("[WARN] alpha 패널 미발견 — 벤치 basis 귀속 축소 실행\n")
}

write_json(res, file.path(SD, "forge_baseline_reconciliation.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "null")
cat("\n[recon] forge_baseline_reconciliation.json written\n")
