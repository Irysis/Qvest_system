## WT-D20260813_006 / FQ-234 Lane B — 본 측정 (PREREG.json 고정 후)
## 실측-only: canonical_screen_bt 경유. proxy 손계산 없음.
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260822)
J <- list(); TOPN <- 25L

P <- as.data.table(read_parquet(file.path(OUT, "absorb_panel.parquet"))); P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT, "fwd.rds"))
RET <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQ, "liq_ruler", attr(fwd$liq_dt, "liq_ruler", exact = TRUE))
setattr(LIQ, "liq_ruler_source", attr(fwd$liq_dt, "liq_ruler_source", exact = TRUE))
SIZE <- P[, .(Date, Ticker, Size)]

valid_sig <- sort(unique(RET$Date)); valid_sig <- valid_sig[valid_sig < as.Date("2026-06-01")]
P <- P[Date %in% valid_sig]; RET <- RET[Date %in% valid_sig]
BEN <- BEN[Date %in% valid_sig]; LIQ <- LIQ[Date %in% valid_sig]; SIZE <- SIZE[Date %in% valid_sig]

WIN <- list(long = as.Date(c("2000-01-01","2026-06-01")), clean = as.Date(c("2015-07-01","2026-06-01")))
in_win <- function(d, w) d >= WIN[[w]][1] & d < WIN[[w]][2]

## 유동성 통과 모집단 (alpha_bridge step3)
ELIG <- merge(P[, .(Date, Ticker)], LIQ, by = c("Date","Ticker"), all.x = TRUE)[is.na(adv) | adv >= 2e8][, .(Date, Ticker)]
setkey(ELIG, Date, Ticker)

wins <- function(x) { q <- quantile(x, c(.01,.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }
zc <- function(x) { s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s == 0) return(rep(NA_real_, length(x))); (x - mean(x, na.rm = TRUE)) / s }

## alpha_bridge: raw -> winsorize -> z (월별 횡단면, 유동성 통과분만)
make_alpha <- function(col, neutralize = FALSE) {
  X <- merge(P[, .(Date, Ticker, raw = -get(col), win_vol, log_size)], ELIG, by = c("Date","Ticker"))
  X <- X[is.finite(raw)]
  X[, raw := wins(raw), by = Date]
  if (neutralize) {
    X <- X[is.finite(win_vol) & is.finite(log_size)]
    X[, resid := {
      fit <- try(lm(raw ~ zc(win_vol) + zc(log_size)), silent = TRUE)
      if (inherits(fit, "try-error")) rep(NA_real_, .N) else as.numeric(residuals(fit))
    }, by = Date]
    X[, score := zc(resid), by = Date]
  } else X[, score := zc(raw), by = Date]
  X[is.finite(score), .(Date, Ticker, score)]
}

run_screen <- function(S, w, tag, top_n = TOPN) {
  s <- S[in_win(Date, w)]
  if (nrow(s) == 0) return(NULL)
  r <- RET[in_win(Date, w)]; b <- BEN[in_win(Date, w)]
  l <- LIQ[in_win(Date, w)]; setattr(l, "liq_ruler", attr(LIQ,"liq_ruler",exact=TRUE))
  setattr(l, "liq_ruler_source", attr(LIQ,"liq_ruler_source",exact=TRUE))
  suppressWarnings(canonical_screen_bt(s, r, b, top_n = top_n, cost_bps_oneway = 15,
      liq_dt = l, liq_min = 2e8, size_dt = SIZE[in_win(Date, w)],
      run_id = paste0("FQ234_", tag, "_", w), strategy_id = paste0("FQ234_", tag), diag_dual_basis = TRUE))
}
pick <- function(cs) if (is.null(cs)) NULL else list(
  metric_type = cs$metric_type, n_months = cs$n_months,
  port_t = cs$portfolio_alpha_t_nw_lag3, port_p = cs$portfolio_alpha_t_pvalue,
  IR = cs$information_ratio, alpha_ann = cs$alpha_annualized,
  net_sr = cs$net_sr, mean_active_net = cs$mean_active_net,
  turnover_annual = cs$turnover_annual,
  ew_universe_port_t = tryCatch(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3_ew, error=function(e) NA),
  ew_universe = tryCatch(cs$diag_ew_universe, error = function(e) NULL),
  cap_tier = tryCatch(cs$diag_cap_tier, error = function(e) NULL))

## ══════════════ 1. 본 스펙 + 사전등록 통제판본 + 진단 ══════════════
SPECS <- list(
  primary      = list(col = "absorb",       neu = FALSE),
  absorb_neu   = list(col = "absorb",       neu = TRUE),
  absorb_share = list(col = "absorb_share", neu = FALSE),
  absorb_resid = list(col = "absorb_resid", neu = FALSE),
  absorb_1m    = list(col = "absorb_1m",    neu = FALSE),
  naive_INJ    = list(col = "absorb_naive", neu = FALSE))
ALPHA <- list()
J$screen <- list()
for (nm in names(SPECS)) {
  A <- make_alpha(SPECS[[nm]]$col, SPECS[[nm]]$neu); ALPHA[[nm]] <- A
  for (w in c("long","clean")) J$screen[[paste0(nm,"__",w)]] <- pick(run_screen(A, w, nm))
  cat("[screen]", nm, "done\n")
}

## ══════════════ 2. PIT — lag1 스트레스 + strict-PIT A/B ══════════════
lag1_of <- function(A) {
  d <- sort(unique(A$Date)); map <- data.table(Date = d[-length(d)], Date_new = d[-1])
  merge(A, map, by = "Date")[, .(Date = Date_new, Ticker, score)]
}
J$pit_lag1 <- list()
for (w in c("long","clean")) {
  L1 <- pick(run_screen(lag1_of(ALPHA$primary), w, "primary_lag1"))
  base <- J$screen[[paste0("primary__", w)]]
  J$pit_lag1[[w]] <- list(base_port_t = base$port_t, lag1_port_t = L1$port_t,
    base_alpha_ann = base$alpha_ann, lag1_alpha_ann = L1$alpha_ann,
    interpretation = "lag1 이 base 대비 붕괴하면 동월 누출 의심")
}
J$pit_strict_ab <- list()
for (w in c("long","clean")) {
  st <- J$screen[[paste0("primary__", w)]]; nv <- J$screen[[paste0("naive_INJ__", w)]]
  ab <- overlay_lookahead_ab(nv$port_t, st$port_t, "PORT_t", rel_tol = 0.05)
  J$pit_strict_ab[[w]] <- list(strict_port_t = st$port_t, contaminated_port_t = nv$port_t,
    inflation = ab$inflation, lookahead_detector_fires = ab$lookahead_suspected,
    note = "contaminated = 홀딩월 데이터 포함 고의 주입. 인플레가 크면 A/B 판별력 실증.")
}

## ══════════════ 3. rank IC / ICIR / Harvey-t (advisory) ══════════════
ic_of <- function(A, w) {
  M <- merge(A[in_win(Date, w)], RET, by = c("Date","Ticker"))
  ic <- M[, if (.N >= 20 && sd(score) > 0 && sd(Ret_1m) > 0)
            .(ic = cor(score, Ret_1m, method = "spearman")) else .(ic = NA_real_), by = Date]
  ic <- ic[is.finite(ic)]
  m <- mean(ic$ic); s <- sd(ic$ic); n <- nrow(ic)
  list(rank_ic = m, icir = m/s, n_months = n, harvey_t_rankic = m/(s/sqrt(n)),
       ic_pos_frac = mean(ic$ic > 0))
}
J$rank_ic <- list()
for (w in c("long","clean")) J$rank_ic[[w]] <- ic_of(ALPHA$primary, w)

## ══════════════ 4. F2 — vol·size 통제 FMB (Fama-MacBeth, NW) ══════════════
fmb <- function(w) {
  M <- merge(P[in_win(Date, w), .(Date, Ticker, absorb, win_vol, log_size)], RET, by = c("Date","Ticker"))
  M <- merge(M, ELIG, by = c("Date","Ticker"))
  M <- M[is.finite(absorb) & is.finite(win_vol) & is.finite(log_size) & is.finite(Ret_1m)]
  co <- M[, {
    a <- zc(wins(absorb)); v <- zc(wins(win_vol)); s <- zc(wins(log_size))
    b_uni <- tryCatch(coef(lm(Ret_1m ~ a))[2], error = function(e) NA_real_)
    b_ctl <- tryCatch(coef(lm(Ret_1m ~ a + v + s))[2], error = function(e) NA_real_)
    .(b_uni = as.numeric(b_uni), b_ctl = as.numeric(b_ctl))
  }, by = Date]
  nwt <- function(x) { x <- x[is.finite(x)]; .nw_t_mean(x, lag = 3L) }
  list(n_months = nrow(co),
       uni_mean = mean(co$b_uni, na.rm=TRUE), uni_nw_t = nwt(co$b_uni),
       ctl_mean = mean(co$b_ctl, na.rm=TRUE), ctl_nw_t = nwt(co$b_ctl),
       coef_survival_ratio = mean(co$b_ctl, na.rm=TRUE)/mean(co$b_uni, na.rm=TRUE))
}
J$F2_fmb <- list()
for (w in c("long","clean")) J$F2_fmb[[w]] <- fmb(w)

## ══════════════ 5. F1 — 기전 관측: 후속 3M 외국인/기관 순매수 분위차 ══════════════
f1 <- function(w) {
  M <- merge(P[in_win(Date, w), .(Date, Ticker, absorb, fwd_foreign_3m_n, fwd_inst_3m_n)],
             ELIG, by = c("Date","Ticker"))
  M <- M[is.finite(absorb) & is.finite(fwd_foreign_3m_n)]
  q <- M[, {
    g <- cut(frank(absorb), breaks = 5, labels = FALSE)
    .(for_hi = mean(fwd_foreign_3m_n[g == 5], na.rm=TRUE), for_lo = mean(fwd_foreign_3m_n[g == 1], na.rm=TRUE),
      ins_hi = mean(fwd_inst_3m_n[g == 5], na.rm=TRUE),  ins_lo = mean(fwd_inst_3m_n[g == 1], na.rm=TRUE))
  }, by = Date]
  q[, `:=`(dfor = for_hi - for_lo, dins = ins_hi - ins_lo)]
  nwt <- function(x) { x <- x[is.finite(x)]; .nw_t_mean(x, lag = 3L) }
  list(n_months = nrow(q),
       foreign_diff_mean = mean(q$dfor, na.rm=TRUE), foreign_diff_nw_t = nwt(q$dfor),
       inst_diff_mean = mean(q$dins, na.rm=TRUE), inst_diff_nw_t = nwt(q$dins),
       predicted = "흡수 상위분위(Q5)의 후속 외국인 순매수가 하위(Q1)보다 **낮아야** 기전 지지 (diff < 0)")
}
J$F1_mechanism <- list()
for (w in c("long","clean")) J$F1_mechanism[[w]] <- f1(w)

## ══════════════ 6. 분위 스프레드 (진단) ══════════════
qspread <- function(w) {
  M <- merge(ALPHA$primary[in_win(Date, w)], RET, by = c("Date","Ticker"))
  q <- M[, { g <- cut(frank(score), breaks = 5, labels = FALSE)
             .(q5 = mean(Ret_1m[g==5], na.rm=TRUE), q1 = mean(Ret_1m[g==1], na.rm=TRUE)) }, by = Date]
  q[, sp := q5 - q1]
  list(n_months = nrow(q), mean_monthly = mean(q$sp), annual = mean(q$sp)*12,
       nw_t = .nw_t_mean(q$sp[is.finite(q$sp)], lag = 3L),
       median_monthly = median(q$sp))
}
J$quintile_spread <- list()
for (w in c("long","clean")) J$quintile_spread[[w]] <- qspread(w)

writeLines(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null"),
           file.path(OUT, "04_measure.json"))
saveRDS(ALPHA, file.path(OUT, "alpha_variants.rds"))
cat("[done] 04_measure.json written\n")
