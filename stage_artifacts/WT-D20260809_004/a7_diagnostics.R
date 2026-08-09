## A7 — advisory 진단 배터리 + 상속 상관 + alpha_vector 발행
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A7] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds")); L <- readRDS(file.path(OUT, "layers.rds"))
TI <- readRDS(file.path(OUT, "tilt_inputs.rds")); AR <- readRDS(file.path(OUT, "arms.rds"))
SC <- L$SC; D <- TI$D; alloc <- TI$alloc
RET <- P$fwd$returns_dt[, .(Date, Ticker, Ret_1m)]
BEN <- P$fwd$bench_dt[, .(Date, BM_Ret)]
LIQ <- P$liq20[, .(Date, Ticker, adv)]
ELIG <- P$ELIG; WIN <- AR$WIN

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  if (lag > 0) for (l in 1:min(lag, n-1)) s <- s + 2*(1 - l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s/n)
}
safe_ic <- function(a, b, minn = 30L) {
  ok <- is.finite(a) & is.finite(b); if (sum(ok) < minn) return(NA_real_)
  suppressWarnings(stats::cor(a[ok], b[ok], method = "spearman"))
}

## ── 1. rank-IC 배터리 (advisory) — 성장 합성 스코어, forward 정렬 ───────────
IC <- merge(SC[, .(Date = sig_date, Ticker, growth)], RET, by = c("Date","Ticker"))
ics <- IC[, .(ic = safe_ic(growth, Ret_1m), n = .N), by = Date][!is.na(ic)][order(Date)]
say("=== advisory 배터리 (성장 합성 스코어, 자격 유니버스, forward 1M) ===")
rep_ic <- function(dt, lab) {
  say("  %-16s rank_IC %+.4f · ICIR %+.3f · t_NW3 %+.2f · n=%d월", lab,
      mean(dt$ic), mean(dt$ic)/sd(dt$ic), nw_t(dt$ic, 3), nrow(dt))
  list(rank_ic = mean(dt$ic), icir = mean(dt$ic)/sd(dt$ic), t_nw3 = nw_t(dt$ic, 3), n = nrow(dt))
}
ic_full <- rep_ic(ics, "전창(284월)")
ic_win  <- rep_ic(ics[Date %in% WIN], "공통창(209월)")
## Harvey t (다중검정 보정: n_trials 반영 — Harvey-Liu-Zhu 는 문헌레벨 hurdle 3.0 참조)
say("  Harvey 참조 문턱 3.0 대비 rank-IC t_NW3 = %.2f (advisory)", ic_full$t_nw3)

## subperiod stability
sp <- ics[, per := fifelse(Date < as.Date("2015-01-01"), "2003-2014",
                    fifelse(Date < as.Date("2020-01-01"), "2015-2019", "2020-2026"))][
       , .(ic = mean(ic), t = nw_t(ic, 3), n = .N), by = per][order(per)]
print(sp)
sp_stab <- sum(sp$ic > 0)/nrow(sp)
say("  subperiod_stability (부기간 양(+) 비율) = %.2f", sp_stab)

## monotonicity — decile
DEC <- merge(SC[, .(Date = sig_date, Ticker, growth)], RET, by = c("Date","Ticker"))
DEC[, dec := cut(frank(growth, ties.method = "first"),
                 breaks = quantile(frank(growth, ties.method="first"), probs = seq(0,1,0.1)),
                 include.lowest = TRUE, labels = FALSE), by = Date]
dm <- DEC[!is.na(dec), .(r = mean(Ret_1m)), by = .(Date, dec)][, .(r = mean(r)), by = dec][order(dec)]
mono <- suppressWarnings(cor(dm$dec, dm$r, method = "spearman"))
say("  decile 단조성(Spearman rank) = %+.3f · D10-D1 월 %+.4f (연 %+.2f%%)",
    mono, dm[dec==10]$r - dm[dec==1]$r, (dm[dec==10]$r - dm[dec==1]$r)*1200)
print(dm)

## post-neutralization IC (섹터 중립화 후)
NEU <- merge(SC[, .(Date = sig_date, Ticker, Sector, growth)], RET, by = c("Date","Ticker"))
NEU[, g_neu := growth - mean(growth), by = .(Date, Sector)]
ics_n <- NEU[, .(ic = safe_ic(g_neu, Ret_1m)), by = Date][!is.na(ic)]
say("  post-neutralization(섹터) rank_IC %+.4f · 유지율 %.2f (RF-A4 문턱 0.30)",
    mean(ics_n$ic), mean(ics_n$ic)/ic_full$rank_ic)

## ── 2. 전창 층3 단독 (별도 창 라벨 — 공통창 수치와 나란히 비교 금지) ────────
say("")
say("=== 층3 단독을 전창(284월)에서 — ★다른 창, 공통창 수치와 병렬 비교 금지 ===")
r0_full <- canonical_screen_bt(
  SC[order(sig_date, -growth)][, rk := seq_len(.N), by = sig_date][
    , .(Date = sig_date, Ticker, score = fifelse(rk <= 25, 1000 - rk, -1))],
  RET, BEN, top_n = 25L, cost_bps_oneway = 15, liq_dt = LIQ, liq_min = 2e8,
  run_id = "R0_full284", strategy_id = "R0_full284", diag_dual_basis = TRUE)
say("  R0 전창: PORT_t %+.3f · IR %+.3f · alpha_ann %+.4f · netSR %+.3f · TO %.2f · n=%d",
    r0_full$portfolio_alpha_t_nw_lag3, r0_full$information_ratio, r0_full$alpha_annualized,
    r0_full$net_sr, r0_full$turnover_annual, r0_full$n_months)
say("  R0 전창 EW-유니버스 진단: PORT_t %+.3f · post2017_t %+.2f · oos_approx %s",
    r0_full$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    r0_full$diag_ew_universe$post2017_t_nw_lag3,
    sprintf("%.3f", r0_full$diag_ew_universe$oos_retention_approx))

## ── 3. 상속 상관 (discovery role card: alpha_inheritance_cor < 0.95) ────────
say("")
say("=== 상속 상관 (기존 admitted 대비) ===")
bp <- "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
inh <- NA_real_
if (file.exists(bp)) {
  BASE <- as.data.table(read_parquet(bp))
  say("  base 패널: %s행 · 컬럼 %s", format(nrow(BASE), big.mark=","), paste(names(BASE), collapse=","))
  sccol <- intersect(c("score","alpha","Score","alpha_score"), names(BASE))[1]
  dcol <- intersect(c("Date","date","sig_date"), names(BASE))[1]
  if (!is.na(sccol) && !is.na(dcol)) {
    B2 <- BASE[, .(Date = as.Date(get(dcol)), Ticker, bscore = get(sccol))]
    MM <- merge(SC[, .(Date = sig_date, Ticker, growth)], B2, by = c("Date","Ticker"))
    cs <- MM[, .(rho = safe_ic(growth, bscore)), by = Date][!is.na(rho)]
    inh <- mean(cs$rho)
    say("  월별 횡단면 Spearman 평균 = %+.4f (n=%d월) · 문턱 0.95 대비 %s",
        inh, nrow(cs), if (abs(inh) < 0.95) "PASS" else "FAIL")
    say("  ⚠ 이 base 패널은 저장 파생 패널이다 — production_parity 미검증. 상속-중복 판별용")
    say("     진단으로만 쓰고 book-marginal 주장에는 쓰지 않는다(2026-07-14 동월 look-ahead 계통).")
  } else say("  base 패널 컬럼 해석 실패 — 상속 상관 미산출")
} else say("  base 패널 부재 — 상속 상관 미산출")

## ── 4. DSR (진단 — chain/no-argmax 이라 게이트 아님) ───────────────────────
say("")
say("=== DSR (진단 산출. selection_type=diagnostic_no_argmax → 게이트 부적용) ===")
dsr <- function(sr_ann, n_months, n_trials, skew = 0, kurt = 3) {
  sr <- sr_ann/sqrt(12)
  if (n_trials < 2) return(NA_real_)
  e <- 0.5772156649
  sr0 <- sqrt(1/12) * ((1-e)*qnorm(1-1/n_trials) + e*qnorm(1-1/(n_trials*exp(1))))
  z <- (sr - sr0)*sqrt(n_months-1)/sqrt(1 - skew*sr + (kurt-1)/4*sr^2)
  pnorm(z)
}
n_trials_declared <- 7L   # R0 + B + C(2λ, judged) + Craw(2λ) + A(비교 arm 1) = 사전등록 열거
for (nm in c("R0","B","C_l0.5","C_l1.0")) {
  sr <- switch(nm, R0 = AR$R0$net_sr, B = AR$B$net_sr,
               C_l0.5 = AR$CS$C_combined_l0.5$net_sr, C_l1.0 = AR$CS$C_combined_l1.0$net_sr)
  say("  %-8s net active SR %+.3f → DSR(n_trials=%d) %.3f", nm, sr, n_trials_declared,
      dsr(sr, 209, n_trials_declared))
}

## ── 5. alpha_vector / confidence_vector (as_of = 최신 sig_date) ────────────
say("")
say("=== alpha_vector 발행 (as_of = 최신 신호일) ===")
asof <- max(SC$sig_date)
say("  as_of sig_date = %s", as.character(asof))
lam_pub <- 1.0
Dp <- D[sig_date == asof]
if (!nrow(Dp)) { Dp <- D[sig_date == max(D$sig_date)]; say("  ⚠ β_s 최신월 = %s 사용", as.character(max(D$sig_date))) }
qp <- Dp[, { w <- base * exp(lam_pub * sbeta * infl); if (!all(is.finite(w)) || sum(w) <= 0) w <- base
             .(Sector = Sector, n_q = alloc(w, n_s)) }, by = sig_date][n_q > 0]
scp <- merge(SC[sig_date == asof], qp[, .(Sector, n_q)], by = "Sector", all.x = TRUE)
scp[is.na(n_q), n_q := 0L]
setorder(scp, Sector, -growth)
scp[, rk := seq_len(.N), by = Sector]
scp[, selected := rk <= n_q]
say("  자격종목 %d · 선택 %d · 유효 섹터 %d", nrow(scp), sum(scp$selected), uniqueN(scp[selected==TRUE]$Sector))
## alpha_vector = 기대 초과수익 스케일 = growth z × (전창 실측 IC × 횡단면 수익 sd)
xsd <- merge(SC[, .(Date=sig_date, Ticker)], RET, by=c("Date","Ticker"))[, .(s = sd(Ret_1m)), by=Date][, mean(s)]
scale_a <- ic_full$rank_ic * xsd
scp[, alpha_hat := growth * scale_a]
## confidence: 팩터 커버리지 + 횡단면 랭크 안정성
gw <- L$GW[sig_date %in% c(asof, sort(unique(SC$sig_date), decreasing=TRUE)[2])]
prev_d <- sort(unique(SC$sig_date), decreasing = TRUE)[2]
rk_now <- SC[sig_date == asof, .(Ticker, r1 = frank(-growth)/.N)]
rk_pre <- SC[sig_date == prev_d, .(Ticker, r0 = frank(-growth)/.N)]
rk <- merge(rk_now, rk_pre, by = "Ticker", all.x = TRUE)
scp <- merge(scp, rk, by = "Ticker", all.x = TRUE)
scp[, conf := pmin(1, pmax(0, 0.35*(n_ok/3) + 0.35*(1 - pmin(1, abs(r1 - fcoalesce(r0, r1))*2)) +
                              0.30*pmin(1, abs(ic_full$t_nw3)/5)))]
say("  alpha_hat: 평균 %+.5f · [%.4f, %.4f] · confidence 평균 %.3f",
    mean(scp$alpha_hat), min(scp$alpha_hat), max(scp$alpha_hat), mean(scp$conf))

## alpha_scores.parquet — ★adv20>=2e8 이 이미 적용된 자격 패널만 발행 (2026-08-08 위반 재발 방지)
EM <- merge(SC[, .(Date = sig_date, Ticker, Sector, growth, n_ok)],
            ELIG[, .(Date, Ticker, adv20)], by = c("Date","Ticker"))
EM[, score := growth]
EM[, alpha_hat := growth * scale_a]
stopifnot(all(EM$adv20 >= 2e8))
say("  발행 패널 %s행 · Date %d · adv20 최소 %.3e (>=2e8 assert 통과)",
    format(nrow(EM), big.mark=","), uniqueN(EM$Date), min(EM$adv20))
write_parquet(EM, file.path(OUT, "alpha_scores.parquet"))
say("  저장: %s/alpha_scores.parquet", OUT)

saveRDS(list(ic_full=ic_full, ic_win=ic_win, sp=sp, sp_stab=sp_stab, mono=mono, dm=dm,
             ic_neu=mean(ics_n$ic), r0_full=r0_full, inh=inh, asof=asof, scp=scp,
             scale_a=scale_a, n_trials=n_trials_declared),
        file.path(OUT, "diagnostics.rds"))
say("저장 완료")
