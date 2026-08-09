#!/usr/bin/env Rscript
# =============================================================================
# p5_np2_np4.R — FQ-170 NP-2(처치-강건성) + NP-4(composite 성분 자격)
#
# ── 사전등록 (결과 도착 전 확정) ─────────────────────────────────────────
# NP-2 정직 재정의: 본 패널의 타 HUMP 재료는 z_neutral(Q01 중립판)뿐 — raw 와 동족이므로
#   이것은 **계열 일반화가 아니라 처치-강건성**(중립화를 거쳐도 밴드 규칙이 사는가) 검정이다.
#   진짜 계열 일반화는 FQ-171(현행 book 7종 형태 census, 타 세션 in-flight) 산출 대기 — 침범 금지.
#   예측: z_neutral 도 HUMP(FQ-166 E3 실측) ⇒ 밴드 > top-25, paired t >= 2.
#   추가 음성 대조: M01_PATHQ(MONOTONE_TOP) — 밴드가 해로워야 함.
# NP-4: 밴드-25 Q01 의 book composite 성분 자격 = 기존 컨센서스 3종(C01_SUE·C02_EPS_Chg_1m·
#   C04_ESBR, WT-001 패널 기재)의 top-25 active 와 |cor| < 0.30 (measurement-graduation §3 보강증거 기준).
#   통과 시 book-marginal ΔIR 측정 자격 — 측정 자체는 후속(FQ-165 절차 정합, 소관 중복 확인 후).
# metric_type = backtested_screen (계약 경유) · capital_claim = false
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT); OUT <- file.path(ROOT, "stage_artifacts/FQ170_claim_20260809")
sink(file.path(OUT, "p5_np2np4.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bm_dt <- as.data.table(P$bench)[, .(Date = as.Date(Date), BM_Ret)]
X <- merge(B, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[0] 패널: %d행 %d개월\n", nrow(X), uniqueN(X$Date)))

sel_w <- function(scorecol, rule) {
  D <- X[!is.na(get(scorecol))]
  D[, n_m := .N, by = Date]; D <- D[n_m >= 50]
  D[, pr := frank(get(scorecol), ties.method="first") / .N, by = Date]
  sel <- switch(rule,
    top25  = D[, .SD[frank(-get(scorecol), ties.method="first") <= 25], by = Date],
    band25 = { b <- D[pr > 0.70 & pr <= 0.90]
               b[, .SD[frank(-get(scorecol), ties.method="first") <= 25], by = Date] })
  sel[, .(Date, Ticker, w = 1)]
}
ts_of <- function(bt) {
  for (k in c("monthly","period_returns","series","port"))
    if (k %in% names(bt) && is.data.frame(bt[[k]])) return(as.data.table(bt[[k]]))
  NULL
}
act_series <- function(bt) {
  tt <- ts_of(bt); dc <- intersect(c("date","Date"), names(tt))[1]
  tt[, .(d_ = get(dc), a = ret_net - benchmark_ret)]
}
run_pair <- function(scorecol, lab) {
  bA <- weighted_screen_bt(sel_w(scorecol, "top25"),  ret, bm_dt, 15,
                           run_id="FQ170_NP2", strategy_id=paste0(lab,"_top25"))
  bB <- weighted_screen_bt(sel_w(scorecol, "band25"), ret, bm_dt, 15,
                           run_id="FQ170_NP2", strategy_id=paste0(lab,"_band25"))
  M <- merge(act_series(bA), act_series(bB), by = "d_", suffixes = c("A","B"))
  d <- M$aB - M$aA
  cat(sprintf("  %-14s top25 PORT_t=%+.3f · band25 PORT_t=%+.3f · paired B−A %+.2f%%p/yr t_NW3=%+.3f (n=%d)\n",
              lab, bA$portfolio_alpha_t_nw_lag3, bB$portfolio_alpha_t_nw_lag3,
              12*100*mean(d), .nw_t_mean(d, lag=3L), length(d)))
  list(A_t = bA$portfolio_alpha_t_nw_lag3, B_t = bB$portfolio_alpha_t_nw_lag3,
       paired_t = .nw_t_mean(d, lag=3L), diff_yr = 12*mean(d))
}

cat("\n=== [NP-2] 처치-강건성 + 추가 음성 대조 (EW basis) ===\n")
r_neu <- run_pair("z_neutral", "Q01_neutral")
r_m01 <- run_pair("M01_PATHQ", "M01_PATHQ")
np2_ok  <- r_neu$paired_t >= 2.0
ctrl_ok <- r_m01$diff_yr < 0
cat(sprintf("  판정: 중립판 %s (t %+.3f) · M01 음성대조 %s (diff %+.2f%%p)\n",
            ifelse(np2_ok, "재현", "미재현"), r_neu$paired_t,
            ifelse(ctrl_ok, "정상", "실패"), r_m01$diff_yr*100))

cat("\n=== [NP-4] composite 성분 자격 — 컨센서스 3종 top-25 active 와의 상관 ===\n")
A_panel <- as.data.table(P$A)
cat("  WT-001 A 패널 cols:", paste(names(A_panel), collapse=","), "\n")
XC <- merge(A_panel[, .(Date, Ticker, C01_SUE, C02_EPS_Chg_1m, C04_ESBR)],
            ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
XC <- merge(XC, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
XC <- XC[is.na(adv) | adv >= 2e8]
sel_wC <- function(scorecol) {
  D <- XC[!is.na(get(scorecol))]; D[, n_m := .N, by = Date]; D <- D[n_m >= 50]
  D[, .SD[frank(-get(scorecol), ties.method="first") <= 25], by = Date][, .(Date, Ticker, w = 1)]
}
bQ <- weighted_screen_bt(sel_w("Q01_EB", "band25"), ret, bm_dt, 15,
                         run_id="FQ170_NP4", strategy_id="Q01_band25")
sQ <- act_series(bQ)
np4 <- list()
for (cc in c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR")) {
  bC <- weighted_screen_bt(sel_wC(cc), ret, bm_dt, 15,
                           run_id="FQ170_NP4", strategy_id=paste0(cc,"_top25"))
  sC <- act_series(bC)
  M <- merge(sQ, sC, by = "d_", suffixes = c("Q","C"))
  r <- cor(M$aQ, M$aC)
  cat(sprintf("  cor(밴드Q01 active, %s top25 active) = %+.4f (n=%d) %s\n",
              cc, r, nrow(M), ifelse(abs(r) < 0.30, "<0.30 통과", ">=0.30 미달")))
  np4[[cc]] <- r
}
np4_pass <- all(abs(unlist(np4)) < 0.30)
cat(sprintf("  판정: composite 성분 상관 자격 %s (기준 전 성분 |cor|<0.30)\n",
            ifelse(np4_pass, "통과 — book-marginal ΔIR 측정 자격 확보", "미달")))

write_json(list(metric_type="backtested_screen", capital_claim=FALSE,
                np2=list(q01_neutral=r_neu, m01_control=r_m01,
                         verdict=ifelse(np2_ok && ctrl_ok, "TREATMENT_ROBUST", "MIXED"),
                         honest_scope="동족 처치-강건성 — 계열 일반화는 FQ-171 census 산출 대기(타 세션)"),
                np4=list(correlations=np4, pass=np4_pass)),
           file.path(OUT, "p5_np2np4.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
