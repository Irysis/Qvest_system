## A5 — F3 층 분해 arm 실측 (canonical_screen_bt 경유. proxy 손계산 금지)
## 사전등록: preregistration.json + prereg_amendment_1.json (본 스크립트 실행 전 확정)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A5] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds")); L <- readRDS(file.path(OUT, "layers.rds"))
TI <- readRDS(file.path(OUT, "tilt_inputs.rds"))
alloc <- TI$alloc; D <- TI$D
SC <- L$SC                       # sig_date, Ticker, Sector, growth (자격 유니버스 한정)
RET <- P$fwd$returns_dt[, .(Date, Ticker, Ret_1m)]
BEN <- P$fwd$bench_dt[, .(Date, BM_Ret)]
LIQ <- P$liq20[, .(Date, Ticker, adv)]
SIZE <- P$ME[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size), .(Date, Ticker, Size)]

WIN <- sort(unique(D$sig_date))                 # 공통 창 (β_s 가용)
say("공통 창 %d개월 %s ~ %s", length(WIN), as.character(min(WIN)), as.character(max(WIN)))
SCW <- SC[sig_date %in% WIN]
DW  <- D[sig_date %in% WIN]

## ── 선택기 ──────────────────────────────────────────────────────────────────
## kind: "growth"(섹터 내 성장 상위) / "random"(섹터 내 무작위, seed 필요)
## tilt: "none"(base) / "s"(scale-only β) / "raw"(문자 그대로)
build_scores <- function(lambda, tilt = "s", kind = "growth", seed = NULL,
                         infl_col = "infl", beta_col = NULL) {
  bcol <- if (!is.null(beta_col)) beta_col else if (tilt == "raw") "beta" else "sbeta"
  q <- DW[, {
    b <- if (tilt == "none") rep(0, .N) else get(bcol)
    iv <- get(infl_col)
    w <- base * exp(lambda * b * iv)
    if (!all(is.finite(w)) || sum(w) <= 0) w <- base
    .(Sector = Sector, n_q = alloc(w, n_s))
  }, by = sig_date]
  q <- q[n_q > 0]
  x <- merge(SCW, q, by = c("sig_date","Sector"))
  if (kind == "growth") {
    setorder(x, sig_date, Sector, -growth)
  } else {
    set.seed(seed)
    x[, .u := runif(.N)]
    setorder(x, sig_date, Sector, .u)
  }
  x[, rk := seq_len(.N), by = .(sig_date, Sector)]
  sel <- x[rk <= n_q]
  sel[, gs := seq_len(.N), by = sig_date]          # 월내 선택 순번
  sel[, .(Date = sig_date, Ticker, score = 1000 - gs)]
}

run_cs <- function(scores, lab, diag = TRUE) {
  canonical_screen_bt(scores, RET, BEN, top_n = 25L, cost_bps_oneway = 15,
                      liq_dt = LIQ, liq_min = 2e8, run_id = lab, strategy_id = lab,
                      diag_dual_basis = diag, size_dt = if (diag) SIZE else NULL)
}
brief <- function(r, lab) {
  say("  %-22s PORT_t %+6.3f · p %.4f · IR %+.3f · alpha_ann %+.4f · netSR %+.3f · TO %.2f · n=%d",
      lab, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue, r$information_ratio,
      r$alpha_annualized, r$net_sr, r$turnover_annual, r$n_months)
  invisible(r)
}

## ── R0 기준선: 섹터 구조 없이 성장 top-25 ───────────────────────────────────
say("")
say("=== arm 실측 (canonical top-25 EW · cap-w 벤치 · 15bps · adv20>=2e8) ===")
r0_sc <- SCW[order(sig_date, -growth)][, rk := seq_len(.N), by = sig_date][rk <= 25,
             .(Date = sig_date, Ticker, score = 1000 - rk)]
R0 <- brief(run_cs(r0_sc, "R0_growth_only"), "R0_growth_only")

## ── B: λ=0 (base 정원 + 섹터 내 성장 상위) ─────────────────────────────────
B  <- brief(run_cs(build_scores(0, "none", "growth"), "B_lambda0"), "B_lambda0")

## ── C: 결합 (틸트 정원 + 성장 상위), judged spec = scale-only β ─────────────
CS <- list()
for (lam in c(0.5, 1.0)) {
  lab <- sprintf("C_combined_l%.1f", lam)
  CS[[lab]] <- brief(run_cs(build_scores(lam, "s", "growth"), lab), lab)
}
## 문자 그대로의 raw β 판 (병기 — 폐기 아님)
for (lam in c(0.5, 1.0)) {
  lab <- sprintf("Craw_literal_l%.1f", lam)
  CS[[lab]] <- brief(run_cs(build_scores(lam, "raw", "growth"), lab), lab)
}

## ── A: 틸트 단독 (섹터 내 무작위, 20 시드) + A0 짝 통제 ────────────────────
say("")
say("=== A arm (틸트 단독 — 섹터 내 무작위 20 시드) ===")
seeds <- 1:20
seed_run <- function(lambda, tilt, tag) {
  vals <- rbindlist(lapply(seeds, function(s) {
    r <- run_cs(build_scores(lambda, tilt, "random", seed = s), paste0(tag,"_s",s), diag = FALSE)
    data.table(seed = s, port_t = r$portfolio_alpha_t_nw_lag3, ir = r$information_ratio,
               alpha_ann = r$alpha_annualized, net_sr = r$net_sr, to = r$turnover_annual,
               mean_active = r$mean_active_net)
  }))
  say("  %-22s PORT_t 평균 %+6.3f (sd %.3f · [%.2f, %.2f]) · IR 평균 %+.3f · alpha_ann 평균 %+.4f",
      tag, mean(vals$port_t), sd(vals$port_t), min(vals$port_t), max(vals$port_t),
      mean(vals$ir), mean(vals$alpha_ann))
  vals[, arm := tag][]
}
A0   <- seed_run(0,   "none", "A0_base_random")
A05  <- seed_run(0.5, "s",    "A_tilt_random_l0.5")
A10  <- seed_run(1.0, "s",    "A_tilt_random_l1.0")

## ── paired 증분 (C − B) 월별 시계열 ────────────────────────────────────────
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  if (lag > 0) for (l in 1:min(lag, n-1)) s <- s + 2*(1 - l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s/n)
}
pr_of <- function(r) r$period_returns[, .(date, ret_net)]
say("")
say("=== paired 증분 (C − B) — 같은 월 집합, 같은 층3 ===")
inc <- list()
for (lab in names(CS)) {
  m <- merge(pr_of(CS[[lab]]), pr_of(B), by = "date", suffixes = c("_c","_b"))
  d <- m$ret_net_c - m$ret_net_b
  inc[[lab]] <- list(n = length(d), mean_monthly = mean(d), annual_pct = mean(d)*12*100,
                     sd_monthly = sd(d), t_nw3 = nw_t(d, 3), t_plain = mean(d)/(sd(d)/sqrt(length(d))),
                     series = data.table(date = m$date, d = d))
  say("  %-22s Δ연 %+6.3f%% · sd(월) %.4f · t_NW3 %+5.2f · n=%d",
      lab, inc[[lab]]$annual_pct, inc[[lab]]$sd_monthly, inc[[lab]]$t_nw3, inc[[lab]]$n)
}
## B − R0 (섹터 정원 구조 자체의 기여)
mBR <- merge(pr_of(B), pr_of(R0), by = "date", suffixes = c("_b","_r"))
dBR <- mBR$ret_net_b - mBR$ret_net_r
say("  %-22s Δ연 %+6.3f%% · t_NW3 %+5.2f  (섹터 정원 구조 자체)", "B − R0",
    mean(dBR)*12*100, nw_t(dBR, 3))

## ── dual-basis 진단 병기 ───────────────────────────────────────────────────
say("")
say("=== dual-basis 진단 (비바인딩) ===")
db <- function(r, lab) {
  e <- r$diag_ew_universe
  say("  %-22s EW-유니버스 대비 PORT_t %+6.3f · post2017_t %+5.2f · oos_approx %s",
      lab, e$portfolio_alpha_t_nw_lag3, e$post2017_t_nw_lag3,
      if (is.finite(e$oos_retention_approx)) sprintf("%+.3f", e$oos_retention_approx) else "NA")
  ct <- r$diag_cap_tier
  if (isTRUE(ct$available))
    say("  %-22s cap-tier 비중 MEGA %.3f / MID %.3f / OTHER %.3f / UNRANKED %.3f",
        "", ct$weight_share_avg$MEGA, ct$weight_share_avg$MID, ct$weight_share_avg$OTHER,
        ct$weight_share_avg$UNRANKED)
}
db(R0, "R0_growth_only"); db(B, "B_lambda0")
for (lab in names(CS)) db(CS[[lab]], lab)

saveRDS(list(R0 = R0, B = B, CS = CS, A0 = A0, A05 = A05, A10 = A10, inc = inc,
             dBR = dBR, WIN = WIN, build_scores = build_scores),
        file.path(OUT, "arms.rds"))
say("")
say("저장: %s/arms.rds", OUT)
