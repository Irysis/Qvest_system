## WT-D20260813_006 / FQ-234 Lane B — 착수 0항 실행 (측정 전 사전 계산)
##  ① PIT 3종 (assert HARD + 위반 주입으로 판별력 실증 + lag1 준비)
##  ② 커버리지 창 확정
##  ③ 비용 채널 상한 사전 계산 (회전율)
##  ④ 검정력 계약 (결과량 계열 직접 측정 sd)
##  + F3 (hidden-clone 사전 검사) — 성과 이전에 발화 가능한 반증
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260822)
J <- list()

P <- as.data.table(read_parquet(file.path(OUT, "absorb_panel.parquet")))
P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT, "fwd.rds"))
RET <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQ, "liq_ruler", attr(fwd$liq_dt, "liq_ruler", exact = TRUE))
setattr(LIQ, "liq_ruler_source", attr(fwd$liq_dt, "liq_ruler_source", exact = TRUE))
J$liq_ruler <- fwd$liq_ruler; J$liq_ruler_source <- fwd$liq_ruler_source

## ── 마지막 신호월 = 부분월(2026-06-30 -> 2026-07-24) 제외 ─────────────────
valid_sig <- sort(unique(RET$Date))
valid_sig <- valid_sig[valid_sig < as.Date("2026-06-01")]
J$sig_dates_used <- c(as.character(min(valid_sig)), as.character(max(valid_sig)), length(valid_sig))
P <- P[Date %in% valid_sig]
RET <- RET[Date %in% valid_sig]; BEN <- BEN[Date %in% valid_sig]; LIQ <- LIQ[Date %in% valid_sig]

## ══════════════════════════════════════════════════════════════════════════
## ① PIT — HARD assert + 위반 주입(판별력 실증)
## ══════════════════════════════════════════════════════════════════════════
first_of_next_month <- function(d) {
  fm <- as.Date(format(d, "%Y-%m-01")); y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m"))
  m2 <- m + 1L; y2 <- y + (m2 - 1L) %/% 12L; m2 <- ((m2 - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", y2, m2))
}
sig <- sort(unique(P$Date))
holding_start <- first_of_next_month(sig)
## strict 판본: 피처가 사용한 마지막 관측일 = sig 직전 거래일 (Date < d0 규약)
used_cutoff_strict <- sig - 1L
## naive 판본(고의 위반): 창이 홀딩월 끝까지 = 홀딩월 마지막 거래일
holding_end <- c(sig[-1], as.Date("2026-06-30"))
used_cutoff_naive <- holding_end

r_strict <- tryCatch({ assert_overlay_pit(used_cutoff_strict, holding_start, "absorb_strict"); "PASS" },
                     error = function(e) paste("STOP:", conditionMessage(e)))
r_naive <- tryCatch({ assert_overlay_pit(used_cutoff_naive, holding_start, "absorb_naive_injected"); "PASS(=검사기 무력)" },
                    error = function(e) paste("BLOCKED:", substr(conditionMessage(e), 1, 160)))
J$pit_assert_strict <- r_strict
J$pit_assert_violation_injected <- r_naive
cat("[PIT] strict:", r_strict, "\n[PIT] injected:", r_naive, "\n")

## ══════════════════════════════════════════════════════════════════════════
## ② 창 확정 — KQ150 소급투영(FQ-241) 회피
## ══════════════════════════════════════════════════════════════════════════
WIN <- list(
  clean  = list(lo = as.Date("2015-07-01"), hi = as.Date("2026-06-01"),
                note = "KQ150 소급투영 회피 청정창"),
  long   = list(lo = as.Date("2000-01-01"), hi = as.Date("2026-06-01"),
                note = "전창(flow 지평) — 2010-02~2015-06 KQ150 생존자편향 병기 필요, 2010-02 이전은 K200-only")
)
for (nm in names(WIN)) {
  s <- sig[sig >= WIN[[nm]]$lo & sig < WIN[[nm]]$hi]
  J[[paste0("window_", nm)]] <- list(n_months = length(s),
    from = as.character(min(s)), to = as.character(max(s)), note = WIN[[nm]]$note)
}

## ── 유동성 필터 후 실효 유니버스 크기 (창별) ──
Pl <- merge(P[, .(Date, Ticker, absorb)], LIQ, by = c("Date","Ticker"), all.x = TRUE)
Pl <- Pl[!is.na(absorb) & (is.na(adv) | adv >= 2e8)]
J$eff_universe_median <- list(
  clean = as.numeric(median(Pl[Date >= WIN$clean$lo, .N, by = Date]$N)),
  long  = as.numeric(median(Pl[, .N, by = Date]$N)))

## ══════════════════════════════════════════════════════════════════════════
## ③ 비용 채널 상한 사전 계산 — 회전율 (성과 측정 전)
## ══════════════════════════════════════════════════════════════════════════
turnover_of <- function(S, top_n = 25L) {
  S <- S[!is.na(score)]; setorder(S, Date, -score)
  W <- S[, { n <- min(top_n, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  list(traded_mean = mean(traded[-1]), turnover_annual = mean(traded[-1]) * 12,
       cost_annual = mean(traded[-1]) * 12 * 15 / 1e4)
}
mk_scores <- function(col, win) {
  S <- merge(P[Date >= WIN[[win]]$lo & Date < WIN[[win]]$hi, .(Date, Ticker, score = -get(col))],
             LIQ, by = c("Date","Ticker"), all.x = TRUE)
  S <- S[!is.na(score) & (is.na(adv) | adv >= 2e8)][, .(Date, Ticker, score)]
  S
}
J$cost_precompute <- list()
for (col in c("absorb", "absorb_1m", "absorb_share")) {
  for (win in c("clean","long")) {
    tt <- turnover_of(mk_scores(col, win))
    J$cost_precompute[[paste0(col, "_", win)]] <- tt
  }
}
## 랭크 자기상관 (회전 구조 진단)
rho_lag1 <- function(col) {
  X <- P[!is.na(get(col)), .(Date, Ticker, v = get(col))]
  X[, r := frank(v) / .N, by = Date]
  setorder(X, Ticker, Date)
  X[, r_prev := shift(r), by = Ticker]
  X[, dm := as.integer(round(as.numeric(Date - shift(Date)) / 30.4)), by = Ticker]
  Y <- X[!is.na(r_prev) & dm == 1]
  Y[, .(rho = cor(r, r_prev, method = "spearman"), n = .N)]
}
J$rank_autocorr <- list(absorb = as.list(rho_lag1("absorb")),
                        absorb_1m = as.list(rho_lag1("absorb_1m")),
                        absorb_share = as.list(rho_lag1("absorb_share")))

## ══════════════════════════════════════════════════════════════════════════
## ④ 검정력 계약 — 결과량 계열 **직접 측정** (승계 sd 사용 금지)
##    외부 잡음 기준 = 같은 유니버스/창에서 무작위 top-25 EW 바스켓의 월 active 수익 sd
## ══════════════════════════════════════════════════════════════════════════
random_basket_active <- function(win, n_draw = 120L, top_n = 25L) {
  U <- Pl[Date >= WIN[[win]]$lo & Date < WIN[[win]]$hi, .(Date, Ticker)]
  U <- merge(U, RET, by = c("Date","Ticker"))
  U <- merge(U, BEN, by = "Date")
  sds <- numeric(n_draw)
  for (k in seq_len(n_draw)) {
    pick <- U[, .(r = mean(Ret_1m[sample.int(.N, min(top_n, .N))]), b = BM_Ret[1]), by = Date]
    sds[k] <- sd(pick$r - pick$b)
  }
  list(sd_median = median(sds), sd_q05 = as.numeric(quantile(sds, .05)),
       sd_q95 = as.numeric(quantile(sds, .95)), n_months = uniqueN(U$Date))
}
J$power <- list()
for (win in c("clean","long")) {
  rb <- random_basket_active(win)
  n <- J[[paste0("window_", win)]]$n_months
  re <- required_effect(n = n, t_threshold = 2.0, sd_monthly = rb$sd_median)
  re295 <- required_effect(n = n, t_threshold = 2.95, sd_monthly = rb$sd_median)
  J$power[[win]] <- list(
    measured_sd_monthly_random25_active = rb$sd_median,
    measured_sd_band = c(rb$sd_q05, rb$sd_q95),
    contract_default_sd = SPREAD_SD_MONTHLY_25EW,
    ratio_measured_over_default = rb$sd_median / SPREAD_SD_MONTHLY_25EW,
    n_months = n,
    required_annual_t2 = re$required_annual,
    required_annual_t295 = re295$required_annual,
    nw_inflation_used = re$nw_inflation, nw_inflation_source = re$nw_inflation_source)
}

## ══════════════════════════════════════════════════════════════════════════
## F3 — hidden-clone 사전 검사 (성과 이전 발화 가능)
## ══════════════════════════════════════════════════════════════════════════
f3 <- P[!is.na(absorb) & !is.na(indiv_level), {
  if (.N >= 30 && sd(absorb) > 0 && sd(indiv_level) > 0)
    .(cp = cor(absorb, indiv_level), cs = cor(absorb, indiv_level, method = "spearman"), n = .N)
  else .(cp = NA_real_, cs = NA_real_, n = .N)
}, by = Date]
J$F3_hidden_clone <- list(
  mean_pearson = mean(f3$cp, na.rm = TRUE), mean_spearman = mean(f3$cs, na.rm = TRUE),
  max_abs_spearman = max(abs(f3$cs), na.rm = TRUE),
  frac_months_abs_ge_0.8 = mean(abs(f3$cs) >= 0.8, na.rm = TRUE),
  threshold = 0.8,
  verdict = if (abs(mean(f3$cs, na.rm = TRUE)) >= 0.8) "REJECT_REPACKAGING" else "PASS")

## 피처 상호 상관 (진단)
cc <- P[!is.na(absorb), .(Date, absorb, absorb_resid, absorb_1m, absorb_share, win_vol, log_size)]
cm <- cor(as.matrix(cc[, -1]), use = "pairwise.complete.obs", method = "spearman")
J$feature_corr_pooled_spearman <- as.list(as.data.frame(round(cm, 3)))

cat(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE, digits = 6), "\n")
writeLines(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE, digits = 6),
           file.path(OUT, "03_precheck.json"))
