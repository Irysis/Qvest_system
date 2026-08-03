# =============================================================================
# diag_fq125_stage1_regime_robust.R — C3(사전관측 국면 분리) 강건성 + 소비면 실측
#
# ★정직 라벨: C3 의 lag1 국면 분리는 **사전등록되지 않았다**. 동월/lag1/trailing3 중
#   결과를 보고 lag1 을 지목했으므로 3-way 사후 선택이다. 본 스크립트는 그 취약성을
#   정면으로 잰다(치장이 아니라 반증 시도):
#     R1. 라벨 순열검정 — 국면 라벨을 월 간 셔플했을 때 관측 gap 이 얼마나 드문가
#     R2. 문턱 민감도 — 0 컷 대신 분위수 컷 스윕 (단일 draw 취약성, FQ-109 계열)
#     R3. 시점 분할 — new 구간 / pilot 구간 각각에서 분리가 재현되는가
#     R4. 소비면 실측 — broad_led 월만 보유하는 조건부 스크린의 canonical PORT_t
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(2)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
source("02_Infrastructure/contracts/canonical_screen_bt.R")

panelA <- as.data.table(read_parquet(file.path(OUTD, "panelx_A.parquet")))
Rg <- as.data.table(read_parquet(file.path(OUTD, "gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "gridx_bench.parquet")));   Bg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "gridx_liq.parquet")));     Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "gridx_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
SZ <- MEM[, .(Date, Ticker, Size)]
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = format(Date, "%Y%m"))]
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 8) return(NA_real_)
  m <- mean(x); e <- x - m; v <- sum(e^2) / n
  for (l in 1:lag) { if (l >= n) break
    cv <- sum(e[1:(n - l)] * e[(l + 1):n]) / n; v <- v + 2 * (1 - l / (lag + 1)) * cv }
  se <- sqrt(v / n); if (!is.finite(se) || se <= 0) return(NA_real_); m / se
}
S <- merge(me_dates, panelA[, .(ym, Ticker, w_amt)], by = "ym")
S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
S <- S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0, .(Date, Ticker, score)]
M <- merge(S, Rg, by = c("Date", "Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]
ICS <- M[, .(n = .N, ic = if (.N >= 8) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_),
         by = Date][is.finite(ic)][order(Date)]

megasp <- local({
  X <- merge(Rg, SZ, by = c("Date", "Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
  X[, rk := frank(-Size, ties.method = "first"), by = Date]
  X[, .(mega_spread = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by = Date][order(Date)]
})
megasp[, ms_lag1 := shift(mega_spread, 1)]
L <- merge(ICS, megasp, by = "Date")[is.finite(ms_lag1)]
obs_gap <- mean(L[ms_lag1 <= 0, ic]) - mean(L[ms_lag1 > 0, ic])
n_broad <- nrow(L[ms_lag1 <= 0])
cat(sprintf("[R0] n=%d | broad_led %d개월 | 관측 gap = %+.5f\n", nrow(L), n_broad, obs_gap))

# ── R1. 라벨 순열검정 ───────────────────────────────────────────────────────
set.seed(777); NP <- 5000L
perm <- replicate(NP, { idx <- sample.int(nrow(L), n_broad)
  mean(L$ic[idx]) - mean(L$ic[-idx]) })
p_two <- mean(abs(perm) >= abs(obs_gap)); p_one <- mean(perm >= obs_gap)
cat(sprintf("[R1] 순열 %d회: p(one-sided)=%.4f p(two-sided)=%.4f | 순열 gap sd=%.4f q95=%+.4f\n",
            NP, p_one, p_two, sd(perm), quantile(perm, .95, names = FALSE)))

# ── R2. 문턱 민감도 (0 컷은 단일 draw) ─────────────────────────────────────
qs <- c(.20, .30, .40, .50, .60, .70)
thr <- rbindlist(lapply(qs, function(q) {
  cut <- quantile(L$ms_lag1, q, names = FALSE)
  a <- L[ms_lag1 <= cut, ic]; b <- L[ms_lag1 > cut, ic]
  data.table(q = q, cut = cut, n_broad = length(a), mean_ic_broad = mean(a),
             t_nw_broad = nw_t(a), mean_ic_mega = mean(b), gap = mean(a) - mean(b))
}))
zero_cut_rank <- mean(L$ms_lag1 <= 0)
cat(sprintf("[R2] ms_lag1<=0 은 분포의 %.0f 분위\n", 100 * zero_cut_rank)); print(thr)

# ── R3. 시점 분할 재현 ──────────────────────────────────────────────────────
L[, era := fifelse(Date >= as.Date("2024-07-01"), "pilot", "new")]
era_rep <- L[, .(n = .N, n_broad = sum(ms_lag1 <= 0),
                 ic_broad = mean(ic[ms_lag1 <= 0]), ic_mega = mean(ic[ms_lag1 > 0]),
                 gap = mean(ic[ms_lag1 <= 0]) - mean(ic[ms_lag1 > 0]),
                 t_nw_broad = nw_t(ic[ms_lag1 <= 0])), by = era]
cat("[R3] 시점 분할 재현:\n"); print(era_rep)

# ── R4. 소비면 실측 — 조건부 스크린 canonical ──────────────────────────────
# broad_led(ms_lag1<=0) 월만 스코어 제공 → canonical_screen_bt 실측.
# ⚠ 월이 비연속이 되므로 turnover 는 해석 불가(과대) — PORT_t 만 소비.
broad_dates <- L[ms_lag1 <= 0, Date]
CN_all <- canonical_screen_bt(S, Rg, Bg, top_n = 20L, cost_bps_oneway = 15, liq_dt = Lg, liq_min = 2e8,
                              run_id = "fq125s1_all", strategy_id = "fq125s1_all",
                              periods_per_year = 12L, diag_dual_basis = TRUE, size_dt = SZ)
CN_brd <- canonical_screen_bt(S[Date %in% broad_dates], Rg, Bg, top_n = 20L, cost_bps_oneway = 15,
                              liq_dt = Lg, liq_min = 2e8, run_id = "fq125s1_broad",
                              strategy_id = "fq125s1_broad", periods_per_year = 12L,
                              diag_dual_basis = TRUE, size_dt = SZ)
cat(sprintf("[R4] canonical 무조건: PORT_t=%+.3f (n=%d) EW-uni=%+.3f net_SR=%.3f TO=%.2f\n",
            CN_all$portfolio_alpha_t_nw_lag3, CN_all$n_months,
            CN_all$diag_ew_universe$portfolio_alpha_t_nw_lag3, CN_all$net_sr, CN_all$turnover_annual))
cat(sprintf("[R4] canonical broad_led만: PORT_t=%+.3f (n=%d) EW-uni=%+.3f net_SR=%.3f (TO 해석불가)\n",
            CN_brd$portfolio_alpha_t_nw_lag3, CN_brd$n_months,
            CN_brd$diag_ew_universe$portfolio_alpha_t_nw_lag3, CN_brd$net_sr))

strip <- function(x) x[setdiff(names(x), c("benchmark_compare", "diag_cap_tier"))]
write_json(list(measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  honesty = "C3 lag1 국면 분리는 사전등록되지 않은 사후 선택(동월/lag1/trailing3 3-way). 본 배터리는 그 취약성 실측.",
  observed = list(n = nrow(L), n_broad = n_broad, gap = obs_gap),
  R1_permutation = list(n_perm = NP, p_one_sided = p_one, p_two_sided = p_two,
                        perm_sd = sd(perm), perm_q95 = quantile(perm, .95, names = FALSE)),
  R2_threshold_sweep = list(zero_cut_quantile = zero_cut_rank, table = thr),
  R3_era_replication = era_rep,
  R4_consumption = list(unconditional = strip(CN_all), broad_led_only = strip(CN_brd),
                        caveat = "월 비연속 → turnover 해석 불가. 월 선택은 사후. PORT_t 만 소비.")
  ), file.path(OUTD, "fq125_stage1_regime_robust.json"), pretty = TRUE, auto_unbox = TRUE,
  digits = 8, null = "null")
cat("\n→ ", file.path(OUTD, "fq125_stage1_regime_robust.json"), "\n")
