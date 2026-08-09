## A6 — (i) EW-유니버스 진단 수리 (ii) F1 lag1 스트레스 (iii) F4 블록순열 플라시보 + 검정력 바
##
## ★수리 사유: a5 는 scores_dt 에 **선택된 25종만** 실었다. canonical_screen_bt 의
##   diag_ew_universe 는 scores 패널을 '유동성필터 前 유니버스'로 삼으므로, 그 벤치가
##   포트 자신의 gross 가 되어 active = -비용 (상수 음수) → PORT_t -53~-66 이라는
##   무의미한 수치가 나왔다. 진단 오용이지 알파 성질이 아니다.
##   수리 = 전 자격종목에 점수를 실어(비선택 = -1) top-25 선택은 동일하게 두고
##   패널 유니버스를 복원한다. cap-w 본판정 수치는 선택이 동일하므로 불변이어야 한다(parity 확인).
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(future.apply) })
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A6] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds")); L <- readRDS(file.path(OUT, "layers.rds"))
TI <- readRDS(file.path(OUT, "tilt_inputs.rds")); AR <- readRDS(file.path(OUT, "arms.rds"))
alloc <- TI$alloc; D <- TI$D; SC <- L$SC
RET <- P$fwd$returns_dt[, .(Date, Ticker, Ret_1m)]
BEN <- P$fwd$bench_dt[, .(Date, BM_Ret)]
LIQ <- P$liq20[, .(Date, Ticker, adv)]
SIZE <- P$ME[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size), .(Date, Ticker, Size)]
WIN <- AR$WIN
SCW <- SC[sig_date %in% WIN]; DW <- D[sig_date %in% WIN]

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  if (lag > 0) for (l in 1:min(lag, n-1)) s <- s + 2*(1 - l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s/n)
}

## ── 전-유니버스 점수 생성기 (선택 25종 = 양수 점수, 나머지 -1) ─────────────
make_scores_full <- function(qtbl, kind = "growth", seed = NULL) {
  x <- merge(SCW, qtbl, by = c("sig_date","Sector"), all.x = TRUE)
  x[is.na(n_q), n_q := 0L]
  if (kind == "growth") setorder(x, sig_date, Sector, -growth)
  else { set.seed(seed); x[, .u := runif(.N)]; setorder(x, sig_date, Sector, .u) }
  x[, rk := seq_len(.N), by = .(sig_date, Sector)]
  x[, sel := rk <= n_q]
  x[sel == TRUE, gs := seq_len(.N), by = sig_date]
  x[, score := fifelse(sel == TRUE, 1000 - gs, -1)]
  x[, .(Date = sig_date, Ticker, score)]
}
quotas <- function(lambda, tilt = "s", infl_vec = NULL, beta_col = "sbeta") {
  dd <- copy(DW)
  if (!is.null(infl_vec)) dd <- merge(dd[, !"infl"], infl_vec, by = "sig_date")
  dd[, {
    b <- if (tilt == "none") rep(0, .N) else get(beta_col)
    w <- base * exp(lambda * b * infl)
    if (!all(is.finite(w)) || sum(w) <= 0) w <- base
    .(Sector = Sector, n_q = alloc(w, n_s))
  }, by = sig_date][n_q > 0]
}
run_cs <- function(scores, lab, diag = TRUE) {
  canonical_screen_bt(scores, RET, BEN, top_n = 25L, cost_bps_oneway = 15,
                      liq_dt = LIQ, liq_min = 2e8, run_id = lab, strategy_id = lab,
                      diag_dual_basis = diag, size_dt = if (diag) SIZE else NULL)
}

## ── (i) 수리판 headline arm + parity 확인 ──────────────────────────────────
say("=== (i) EW-진단 수리판 — cap-w 본판정 parity 확인 ===")
B2  <- run_cs(make_scores_full(quotas(0, "none")), "B_lambda0_full")
C05 <- run_cs(make_scores_full(quotas(0.5, "s")),  "C_l0.5_full")
C10 <- run_cs(make_scores_full(quotas(1.0, "s")),  "C_l1.0_full")
R02 <- run_cs(SCW[order(sig_date, -growth)][, rk := seq_len(.N), by = sig_date][
                , .(Date = sig_date, Ticker, score = fifelse(rk <= 25, 1000 - rk, -1))], "R0_full")
par_chk <- data.table(
  arm = c("R0","B","C_l0.5","C_l1.0"),
  capw_t_a5 = c(AR$R0$portfolio_alpha_t_nw_lag3, AR$B$portfolio_alpha_t_nw_lag3,
                AR$CS$C_combined_l0.5$portfolio_alpha_t_nw_lag3, AR$CS$C_combined_l1.0$portfolio_alpha_t_nw_lag3),
  capw_t_a6 = c(R02$portfolio_alpha_t_nw_lag3, B2$portfolio_alpha_t_nw_lag3,
                C05$portfolio_alpha_t_nw_lag3, C10$portfolio_alpha_t_nw_lag3))
par_chk[, abs_diff := abs(capw_t_a6 - capw_t_a5)]
print(par_chk)
say("parity: 최대 |차| = %.2e (선택이 동일하므로 0 이어야 정상)", max(par_chk$abs_diff))
say("")
say("--- 수리된 EW-유니버스 진단 (비바인딩) ---")
for (nm in c("R0","B","C_l0.5","C_l1.0")) {
  r <- switch(nm, R0 = R02, B = B2, C_l0.5 = C05, C_l1.0 = C10)
  e <- r$diag_ew_universe
  say("  %-10s EW-유니버스 PORT_t %+6.3f · post2017_t %+5.2f · oos_approx %s · netSR %+.3f · n=%d",
      nm, e$portfolio_alpha_t_nw_lag3, e$post2017_t_nw_lag3,
      if (is.finite(e$oos_retention_approx)) sprintf("%.3f", e$oos_retention_approx) else "NA",
      e$net_sr, e$n_months)
}

## ── (ii) F1 lag1 스트레스 ──────────────────────────────────────────────────
say("")
say("=== (ii) F1 lag1 스트레스 (infl_{t-1} + β_{s,t-1}) ===")
DL <- copy(D)[order(Sector, sig_date)]
DL[, `:=`(beta_l1 = shift(sbeta), infl_l1 = shift(infl)), by = Sector]
DL <- DL[sig_date %in% WIN & !is.na(beta_l1) & !is.na(infl_l1)]
q_lag <- function(lambda) DL[, {
  w <- base * exp(lambda * beta_l1 * infl_l1)
  if (!all(is.finite(w)) || sum(w) <= 0) w <- base
  .(Sector = Sector, n_q = alloc(w, n_s))
}, by = sig_date][n_q > 0]
C05L <- run_cs(make_scores_full(q_lag(0.5)), "C_l0.5_lag1", diag = FALSE)
C10L <- run_cs(make_scores_full(q_lag(1.0)), "C_l1.0_lag1", diag = FALSE)
pr <- function(r) r$period_returns[, .(date, ret_net)]
incf <- function(rc, rb) {
  m <- merge(pr(rc), pr(rb), by = "date", suffixes = c("_c","_b"))
  d <- m$ret_net_c - m$ret_net_b
  list(n = length(d), ann = mean(d)*12*100, sd = sd(d), t = nw_t(d, 3), series = d, date = m$date)
}
i05 <- incf(C05, B2); i10 <- incf(C10, B2)
i05L <- incf(C05L, B2); i10L <- incf(C10L, B2)
say("  λ=0.5  base Δ연 %+.3f%% (t %+.2f)  →  lag1 Δ연 %+.3f%% (t %+.2f) · 잔존율 %.2f",
    i05$ann, i05$t, i05L$ann, i05L$t, i05L$ann/i05$ann)
say("  λ=1.0  base Δ연 %+.3f%% (t %+.2f)  →  lag1 Δ연 %+.3f%% (t %+.2f) · 잔존율 %.2f",
    i10$ann, i10$t, i10L$ann, i10L$t, i10L$ann/i10$ann)

## ── (iii) F4 블록순열 플라시보 ─────────────────────────────────────────────
say("")
say("=== (iii) F4 블록순열 플라시보 (판정 = 블록 12, 200판) ===")
sds <- sort(unique(DW$sig_date)); n <- length(sds)
infl_real <- unique(DW[, .(sig_date, infl)])[order(sig_date)]
block_perm <- function(v, blk, seed) {
  set.seed(seed)
  nb <- ceiling(length(v)/blk)
  idx <- split(seq_along(v), rep(seq_len(nb), each = blk, length.out = length(v)))
  unlist(idx[sample(nb)], use.names = FALSE)[seq_along(v)]
}
run_placebo <- function(blk, lambda, draws = 200L) {
  plan(multisession, workers = min(8L, max(1L, parallel::detectCores() - 1L)))
  on.exit(plan(sequential), add = TRUE)
  future_lapply(seq_len(draws), function(k) {
    suppressPackageStartupMessages(library(data.table))
    ord <- block_perm(infl_real$infl, blk, seed = 10000L*blk + 100L*lambda + k)
    iv <- data.table(sig_date = infl_real$sig_date, infl = infl_real$infl[ord])
    r <- run_cs(make_scores_full(quotas(lambda, "s", infl_vec = iv)),
                sprintf("pl_b%d_l%.1f_%d", blk, lambda, k), diag = FALSE)
    m <- merge(r$period_returns[, .(date, ret_net)], pr(B2), by = "date", suffixes = c("_c","_b"))
    d <- m$ret_net_c - m$ret_net_b
    data.table(draw = k, ann = mean(d)*12*100, sd_m = sd(d), t = nw_t(d, 3))
  }, future.seed = TRUE) |> rbindlist()
}
PL <- list()
for (lam in c(0.5, 1.0)) {
  PL[[sprintf("b12_l%.1f", lam)]] <- run_placebo(12L, lam, 200L)
}
## 블록 민감도(진단 전용)
for (blk in c(6L, 24L)) PL[[sprintf("b%d_l0.5", blk)]] <- run_placebo(blk, 0.5, 100L)

obs <- c("0.5" = i05$ann, "1.0" = i10$ann)
for (lam in c(0.5, 1.0)) {
  p <- PL[[sprintf("b12_l%.1f", lam)]]
  o <- obs[as.character(lam)]
  pct <- mean(p$ann < o)
  say("  λ=%.1f 판정(블록12·200판): 실측 Δ연 %+.3f%% · 플라시보 평균 %+.3f%% · sd %.3f · 백분위 %.1f%% (95분위 %.3f%%)",
      lam, o, mean(p$ann), sd(p$ann), 100*pct, quantile(p$ann, .95))
}
for (nm in c("b6_l0.5","b24_l0.5")) {
  p <- PL[[nm]]
  say("  [진단] %s (100판): 평균 %+.3f%% · sd %.3f · 실측 백분위 %.1f%%",
      nm, mean(p$ann), sd(p$ann), 100*mean(p$ann < obs["0.5"]))
}

## ── 검정력 바 (외부 기준 = 플라시보 paired sd) ─────────────────────────────
say("")
say("=== 검정력 판정 (외부 기준 sd = 플라시보 paired 월 차이 sd) ===")
pw_out <- list()
for (lam in c(0.5, 1.0)) {
  p <- PL[[sprintf("b12_l%.1f", lam)]]
  sd_ext <- median(p$sd_m)
  ii <- if (lam == 0.5) i05 else i10
  v <- verdict_with_power(observed_t = ii$t, observed_monthly = ii$ann/1200,
                          n = ii$n, sd_monthly = sd_ext)
  say("  λ=%.1f  외부 sd %.5f · 필요 연 %.3f%% · 실측 연 %+.3f%% · 관측/필요 %.2f · implied_t %.2f → %s",
      lam, sd_ext, v$required$required_annual*100, ii$ann,
      abs(ii$ann/100)/v$required$required_annual, v$implied_t_threshold, v$verdict)
  pw_out[[sprintf("l%.1f", lam)]] <- list(sd_ext = sd_ext,
    required_annual_pct = v$required$required_annual*100, observed_annual_pct = ii$ann,
    ratio = abs(ii$ann/100)/v$required$required_annual, implied_t = v$implied_t_threshold,
    verdict = v$verdict, bar_restates_t = v$bar_restates_t)
}

saveRDS(list(R02=R02,B2=B2,C05=C05,C10=C10,C05L=C05L,C10L=C10L,
             i05=i05,i10=i10,i05L=i05L,i10L=i10L,PL=PL,pw=pw_out,par_chk=par_chk),
        file.path(OUT, "stress.rds"))
say("")
say("저장: %s/stress.rds", OUT)
