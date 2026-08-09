#!/usr/bin/env Rscript
# fq002b_filter_measure_20260809.R — FQ-002 (B) 배제형 필터 본 측정.
# 사전등록: stage_artifacts/paper_recharge/prereg_fq002b_filter_20260809.json (측정 전 고정)
# ★PIT: 홀딩월 M 은 패널 ym = M-1 만 쓴다(w_ratio 는 12M 누적이라 ym=M 은 동월 look-ahead).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
Sys.setenv(QVEST_WEIGHTING_AB_NORUN = "1")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ops/auto_weighting_ab.R")
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
car[, ym := as.integer(format(decision_date, "%Y%m"))]

P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_B_corrected.parquet"))
P[, ym := as.integer(ym)]
# ★lag: 패널 ym 을 다음 홀딩월에 매핑
shift_ym <- function(y) { yr <- y %/% 100L; mo <- y %% 100L; mo <- mo + 1L
  yr <- yr + (mo - 1L) %/% 12L; mo <- ((mo - 1L) %% 12L) + 1L; yr * 100L + mo }
P[, ym_use := shift_ym(ym)]

C <- merge(car, P[, .(ym_use, Ticker, w_ratio)], by.x = c("ym", "Ticker"), by.y = c("ym_use", "Ticker"), all.x = TRUE)
C[, covered := !is.na(w_ratio)]
ov <- sort(unique(C[covered == TRUE]$ym))
C <- C[ym >= min(ov) & ym <= max(ov)]
setorder(C, ym)
say("★lag 적용 후: %d개월(%d~%d) · 행 %d · 월평균 보유 %.1f · 커버 %.2f종 (%.1f%%)",
    uniqueN(C$ym), min(C$ym), max(C$ym), nrow(C), nrow(C)/uniqueN(C$ym),
    C[covered==TRUE,.N]/uniqueN(C$ym), 100*mean(C$covered))

periods <- unique(C[, .(decision_date, eval_date)]); setorder(periods, eval_date)
bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
returns_dt <- C[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
runW <- function(keepvec, tag) {
  d <- C[keepvec]
  W <- d[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
  r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = 15, run_id = tag, strategy_id = tag)
  list(IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3, n = r$n_months)
}

base <- runW(rep(TRUE, nrow(C)), "base")
say("기준선 book(같은 창): IR %.4f · PORT_t %.3f · %d개월", base$IR, base$PORT_t, base$n)

# ── primary: 커버 종목 중 w_ratio 하위 3분위 제외 ──
C[, drop_sig := FALSE]
C[covered == TRUE, drop_sig := frank(w_ratio, ties.method = "average") / .N <= (1/3), by = ym]
n_drop <- mean(C[, sum(drop_sig), by = ym]$V1)
prim <- runW(!C$drop_sig, "primary_bottom_tercile")
say("\n[primary] 하위3분위 제외 — 월평균 %.2f종 · IR %.4f · ΔIR %+.4f · PORT_t %.3f (Δ %+.3f)",
    n_drop, prim$IR, prim$IR - base$IR, prim$PORT_t, prim$PORT_t - base$PORT_t)

# ── 음성대조(F4): 난수 신호로 같은 절차 ──
set.seed(20260809)
neg_ir <- numeric(0)
for (s in 1:30) {
  C[, drop_ng := FALSE]
  C[covered == TRUE, drop_ng := frank(runif(.N), ties.method = "first") / .N <= (1/3), by = ym]
  neg_ir <- c(neg_ir, runW(!C$drop_ng, sprintf("neg%d", s))$IR)
}
say("[F4 음성대조] 난수 신호 30 draw: ΔIR 중앙 %+.4f · q05 %+.4f · q95 %+.4f",
    median(neg_ir)-base$IR, quantile(neg_ir,.05)-base$IR, quantile(neg_ir,.95)-base$IR)

# ── 양성대조: 완전예지 재현 ──
C[, drop_or := FALSE]
C[covered == TRUE, drop_or := frank(ret_fwd, ties.method = "first") <= 1L, by = ym]
orc <- runW(!C$drop_or, "oracle_drop1")
say("[양성대조] 완전예지 k=1: ΔIR %+.4f (사전 측정 +0.4139 대비 재현)", orc$IR - base$IR)

# ── F3 시대 교락: 전/후반 분할 ──
mid <- sort(unique(C$ym))[ceiling(uniqueN(C$ym)/2)]
h1 <- C[ym <= mid]; h2 <- C[ym > mid]
sub <- function(D, tag) {
  pr <- unique(D[, .(decision_date, eval_date)]); setorder(pr, eval_date)
  bd <- build_period_bench(pr)[!is.na(BM_Ret)]; rd <- D[, .(Date=eval_date, Ticker, Ret_1m=ret_fwd)]
  f <- function(kp, t2) { d <- D[kp]
    W <- d[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][,.(Date,Ticker,w)]
    weighted_screen_bt(W, rd, bd, cost_bps_oneway=15, run_id=t2, strategy_id=t2)$information_ratio }
  c(base = f(rep(TRUE,nrow(D)), paste0(tag,"_b")), filt = f(!D$drop_sig, paste0(tag,"_f")))
}
s1 <- sub(h1, "h1"); s2 <- sub(h2, "h2")
say("[F3 시대] 전반(<=%d) ΔIR %+.4f · 후반 ΔIR %+.4f · 부호 %s",
    mid, s1["filt"]-s1["base"], s2["filt"]-s2["base"],
    if (sign(s1["filt"]-s1["base"]) == sign(s2["filt"]-s2["base"])) "일치" else "★갈림(시대 교락 라벨)")

dIR <- prim$IR - base$IR; q95 <- unname(quantile(neg_ir,.95) - base$IR); rec <- dIR / 0.4139
say("\n=== 사전등록 판정 ===")
say("  ΔIR %+.4f · 음성대조 q95 %+.4f · 회수율 %.1f%% (천장 +0.4139)", dIR, q95, 100*rec)
v <- if (dIR <= q95) "F1 반증 — 무작위 q95 이하. 신호가 아니라 '무언가를 뺐다' 효과." else
     if (rec < 0.25) "F2 반증 — q95 는 넘되 회수율 <25%. 천장은 실재하나 이 신호로는 못 캔다." else
     "사전등록 통과 — 신호 특이 효과 확인. 단 창 병기 의무."
say("  ⇒ %s", v)

write(toJSON(list(schema="fq002b_filter_v1", date="20260809", metric_type="canonical_screen",
  prereg="stage_artifacts/paper_recharge/prereg_fq002b_filter_20260809.json",
  window=c(min(C$ym), max(C$ym)), n_months=base$n, coverage_pct=round(100*mean(C$covered),2),
  mean_drop=round(n_drop,3),
  base=list(IR=round(base$IR,4), PORT_t=round(base$PORT_t,3)),
  primary=list(IR=round(prim$IR,4), dIR=round(dIR,4), PORT_t=round(prim$PORT_t,3)),
  negative_control=list(median_dIR=round(median(neg_ir)-base$IR,4), q95_dIR=round(q95,4)),
  positive_control=list(oracle_dIR=round(orc$IR-base$IR,4), prior_measured=0.4139),
  era_split=list(mid=mid, h1_dIR=round(unname(s1["filt"]-s1["base"]),4), h2_dIR=round(unname(s2["filt"]-s2["base"]),4)),
  recovery_rate=round(rec,4), verdict=v), pretty=TRUE, auto_unbox=TRUE, na="null"),
  "stage_artifacts/paper_recharge/fq002b_filter_results_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/fq002b_filter_results_20260809.json")
