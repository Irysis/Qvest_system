#!/usr/bin/env Rscript
# fq002b_ceiling_20260809.R — FQ-002 (B) 배제형 필터의 **완전예지 천장**.
#
# ★규약(feedback-ceiling-first-before-refinement-probes): 정교화 probe 전에 천장부터.
#   겹침 확인이 WEAK(월평균 0.88종 제외)를 냈으므로, **어떤 신호로도 도달 불가**한지 먼저 본다.
#   천장 = 매월 계약-커버 종목 중 **사후적으로 가장 나쁜 k개를 제외**(완전예지). 실제 신호는
#   이 천장의 부분 회수일 뿐이다. 천장이 게이트 미만이면 라운드는 착수 전 폐기다.
# ★대조 3종(규약): ①완전예지 상한 ②무작위 상한 ③개별 최강(=신호 실측은 별도)
# 자본 판정 아님(metric_type=diagnostic). 포트 구성은 contract primitive 경유.
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
ov <- intersect(unique(car$ym), unique(P$ym))
C <- car[ym %in% ov]
C[, has_sig := Ticker %in% P$Ticker]
C <- merge(C, P[, .(ym, Ticker, w_ratio)], by = c("ym", "Ticker"), all.x = TRUE)
C[, covered := !is.na(w_ratio)]
say("공통 %d개월 · 행 %d · 월평균 보유 %.1f · 커버 %.1f (%.1f%%)",
    length(ov), nrow(C), nrow(C) / length(ov), C[covered == TRUE, .N] / length(ov),
    100 * mean(C$covered))

periods <- unique(C[, .(decision_date, eval_date)]); setorder(periods, eval_date)
bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
returns_dt <- C[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
mkW <- function(keep) {
  d <- C[keep]
  d[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
}
runW <- function(W, tag) {
  r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = 15, run_id = tag, strategy_id = tag)
  data.table(arm = tag, IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3,
             abs_SR = r$abs_net_sr, abs_MDD = r$abs_mdd, n_months = r$n_months)
}

base <- runW(mkW(rep(TRUE, nrow(C))), "base_book_topN")
say("\n기준선(계약 창 %d개월 book): IR %.4f · PORT_t %.3f", base$n_months, base$IR, base$PORT_t)

# ── ① 완전예지 상한: 매월 커버 종목 중 실현수익 하위 k 를 제외 ──
res <- list(base)
for (k in 1:3) {
  C[, drop_or := FALSE]
  C[covered == TRUE, drop_or := frank(ret_fwd, ties.method = "first") <= k, by = ym]
  res[[length(res) + 1L]] <- runW(mkW(!C$drop_or), sprintf("oracle_drop%d", k))[
    , n_drop := mean(C[, sum(drop_or), by = ym]$V1)][]
}
# ── ② 무작위 상한: 같은 강도(동일 개수)로 커버 종목 중 무작위 제외, 30 draw q95 ──
set.seed(20260809)
rand_ir <- numeric(0)
for (s in 1:30) {
  C[, drop_rd := FALSE]
  C[covered == TRUE, drop_rd := sample(c(rep(TRUE, min(1L, .N)), rep(FALSE, max(0L, .N - 1L)))), by = ym]
  rand_ir <- c(rand_ir, runW(mkW(!C$drop_rd), sprintf("rand%d", s))$IR)
}
say("\n② 무작위 제외(강도 1종/월, 30 draw): IR 중앙 %.4f · q05 %.4f · q95 %.4f",
    median(rand_ir), quantile(rand_ir, .05), quantile(rand_ir, .95))

T <- rbindlist(res, fill = TRUE)
T[, `:=`(dIR = round(IR - base$IR, 4), dPORT_t = round(PORT_t - base$PORT_t, 3))]
say("\n=== ① 완전예지 천장 (계약-커버 종목 중 사후 최악 k 제외) ===")
print(T[, .(arm, n_months, IR = round(IR, 4), dIR, PORT_t = round(PORT_t, 3), dPORT_t,
            n_drop = round(n_drop, 2))])

ceil1 <- T[arm == "oracle_drop1"]
say("\n★천장 판정 (k=1, 실제 신호 발화강도 0.88종/월과 가장 가까움):")
say("   완전예지 ΔIR = %+.4f · 무작위 q95 ΔIR = %+.4f · 게이트 0.05",
    ceil1$dIR, quantile(rand_ir, .95) - base$IR)
verdict <- if (ceil1$dIR < 0.05) {
  "ABORT — 완전예지로도 게이트 미달. 어떤 신호로도 도달 불가 → 배제형 필터 소비면 착수 전 폐기."
} else if (ceil1$dIR < quantile(rand_ir, .95) - base$IR) {
  "ABORT — 완전예지가 무작위 q95 도 못 넘음(구조적 무의미)."
} else "PROCEED — 천장이 게이트 초과. 실제 신호가 천장의 몇 %를 회수하는지 측정 가치 있음."
say("   ⇒ %s", verdict)

out <- list(schema = "fq002b_ceiling_v1", date = "20260809", metric_type = "diagnostic",
            n_months = base$n_months, coverage_pct = round(100 * mean(C$covered), 2),
            base = list(IR = round(base$IR, 4), PORT_t = round(base$PORT_t, 3)),
            oracle = lapply(seq_len(nrow(T)), function(i) as.list(T[i, .(arm, IR = round(IR,4), dIR, PORT_t = round(PORT_t,3), dPORT_t)])),
            random_q95_dIR = round(quantile(rand_ir, .95) - base$IR, 4),
            random_median_dIR = round(median(rand_ir) - base$IR, 4),
            gate = 0.05, verdict = verdict)
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/fq002b_ceiling_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/fq002b_ceiling_20260809.json")
