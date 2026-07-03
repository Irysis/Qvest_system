## ============================================================================
## WT-D20260702_002 Forge — PG2 Layer4 3-way 재심 (clean-timing, capital-grade)
## 도훈 승인 2026-07-02 (P0-2). 배경: 오버레이 감사 — 2-2 faith merge가 concurrent
## (동월 look-ahead)로 확정, admit 근거 "1.675->1.875"는 클린 AR vs 리키 faith의
## 비대칭 비교였음. 본 재심 = 동일 클린 타이밍에서 3-way 공정 대결:
##   A_faith_clean : beta_R05 x m4 x beta_faith_CLEAN (S EOM m -> realized_ym m+2
##                   = 배포 forward_weights_R05_FAITH.R와 동일 타이밍)
##   B_AR          : beta_R05 x m4 x beta_AR (panel 기록 — 원래 클린)
##   C_noL4        : beta_R05 x m4 (Layer4 제거)
##   D_naked       : ret_orig (진단 참조 — 계약 측정 제외)
## 비용: canonical per-layer convention (|dL4|x15bps + |dR05|x15bps; C는 R05만)
##        + |dE|x15bps 민감도 병기. m4 delta 비과금은 canonical 동일(캐비앗 명기).
## 계약: build_bt_result 10-component + audit + benchmark_compare(NW lag-3).
## 벤치: 현행 benchmark.parquet(IKS200 수리본), backward anchor-window 정렬(감사 확정).
## 판정 권위: 자본/승격 결정은 judge + governor(도훈 수동) — 본 산출은 증거만.
## metric_type = backtested (계약 경유). selection: 3-way 사전지정 비교(sweep 아님 —
## 감사 결과로 지정된 후보 3개 고정, 탐색적 argmax 없음).
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
PROJECT_ROOT <- ROOT
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002")
OUT <- file.path(WT_DIR, "output"); dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
T_HALF <- 16L; CF <- c(a=0.13, d=0.79, e=-0.17, f=0.09); COST <- 0.0015

cat("[1] panel + clean faith 신호\n")
p <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
r <- bm$BM_Ret; n <- length(r)
rm252 <- frollmean(r,252,na.rm=TRUE); rs252 <- frollapply(r,252,sd,na.rm=TRUE)
rhat <- pmin(pmax((r-rm252)/(rs252+1e-12),-20),20); rhat[!is.finite(rhat)] <- NA
al <- 1-exp(-1/T_HALF); sig2 <- rep(NA_real_,n); acc <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) { acc <- al*rhat[t]^2+(1-al)*acc; sig2[t] <- acc }
N <- 6L*T_HALF; wn <- (0:N)*exp(-2*(0:N)/T_HALF); wn <- wn/sqrt(sum(wn^2)); phi <- rep(NA_real_,n)
for (t in (N+1):n) { seg <- rhat[(t-N):t]; if (all(is.finite(seg))) phi[t] <- pmin(pmax(sum(wn*rev(seg)),-2.5),2.5) }
bm[, S := CF["a"]+CF["d"]*sig2+CF["e"]*phi+CF["f"]*phi^2]
bm[, ym := format(Date,"%Y-%m")]
me <- bm[, .(S_eom=last(S)), by=ym]; setorder(me, ym)
me[, ym_p2 := format(as.Date(paste0(ym,"-01")) %m+% months(2), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_p2, S_clean=S_eom)], by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
exp_pct <- function(x) { out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[seq_len(i-1)]; past <- past[is.finite(past)]
    if (length(past) >= 24 && is.finite(x[i])) out[i] <- mean(past < x[i]) }
  out }
freq <- prop.table(table(round(p$beta_AR,2))); lo <- sort(as.numeric(names(freq))[as.numeric(names(freq)) < 0.999])
cumf <- 0; thr <- list()
for (l in lo) { ff <- as.numeric(freq[as.character(l)]); if (is.na(ff)) ff <- 0
  thr[[length(thr)+1]] <- c(l, 1-cumf-ff, 1-cumf); cumf <- cumf+ff }
map_freq <- function(pp){ if(!is.finite(pp)) return(1.0)
  for (tt in thr) if (pp >= tt[2] && pp < tt[3]) return(tt[1])
  if (length(lo) && pp >= 1-cumf) return(lo[1]); 1.0 }
b_faith_cl <- sapply(exp_pct(p$S_clean), map_freq)
b_faith_cl_lag1 <- shift(b_faith_cl, 1, fill=1.0)   # 지연 민감도용

cat("[2] 3-way 시리즈 (canonical per-layer cost)\n")
dR05 <- abs(p$beta_R05 - shift(p$beta_R05,1,fill=1.0))
mk_layer <- function(bL4) {
  dL4 <- abs(bL4 - shift(bL4,1,fill=1.0))
  p$beta_R05 * p$m4 * bL4 * p$ret_orig - dL4*COST - dR05*COST }
series <- list(
  A_faith_clean = mk_layer(b_faith_cl),
  B_AR          = mk_layer(p$beta_AR),
  C_noL4        = p$beta_R05 * p$m4 * p$ret_orig - dR05*COST,
  D_naked       = p$ret_orig,
  A_lag1_stress = mk_layer(b_faith_cl_lag1))
## sanity: B_AR == 기록 ret_L5_AR
chk <- max(abs(series$B_AR - p$ret_L5_AR), na.rm=TRUE)
cat(sprintf("    sanity B_AR vs 기록 ret_L5_AR max|diff| = %.2e %s\n", chk, ifelse(chk<1e-10,"(OK)","(*** MISMATCH ***)")))
## |dE| 민감도
mk_dE <- function(E) { dE <- abs(E - shift(E,1,fill=1.0)); E*p$ret_orig - dE*COST }
sens <- list(A=mk_dE(p$beta_R05*p$m4*b_faith_cl), B=mk_dE(p$beta_R05*p$m4*p$beta_AR), C=mk_dE(p$beta_R05*p$m4))

cat("[3] 지표 + paired NW-t\n")
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d-mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1-L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu/sqrt(s0/nn) }
ann_sr <- function(ret, idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(ret, order.by=idx), scale=12)[3,1])
oos_v2 <- function(ret) { ns <- length(ret)
  rs <- sapply(c(0.55,0.65,0.75), function(f2) { k <- floor(ns*f2)
    is_sr <- ann_sr(ret[1:k], p$anchor_date[1:k]); oo <- ann_sr(ret[(k+1):ns], p$anchor_date[(k+1):ns])
    if (!is.finite(is_sr) || abs(is_sr)<1e-9) return(NA_real_); oo/is_sr })
  round(median(rs, na.rm=TRUE),3) }
pre <- p$anchor_date < as.Date("2017-01-01")
res <- rbindlist(lapply(names(series), function(nm) {
  ret <- series[[nm]]; x <- xts(ret, order.by=p$anchor_date)
  data.table(variant=nm,
    SR=round(ann_sr(ret),3), CAGR=round(as.numeric(Return.annualized(x, scale=12)),4),
    MDD=round(as.numeric(maxDrawdown(x)),4), Calmar=round(as.numeric(CalmarRatio(x, scale=12)),3),
    Sortino_m=round(as.numeric(SortinoRatio(x, MAR=0)),4),
    ret_2025=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2025"])),4),
    ret_2026=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"])),4),
    SR_pre2017=round(ann_sr(ret[pre], p$anchor_date[pre]),3),
    SR_post2017=round(ann_sr(ret[!pre], p$anchor_date[!pre]),3),
    oos_v2=oos_v2(ret),
    nw_t_vs_B_AR=round(nw_t(ret - series$B_AR),2),
    nw_t_vs_C_noL4=round(nw_t(ret - series$C_noL4),2))
}))
cat("\n===== 3-WAY RETRIAL (per-layer cost, clean timing) =====\n"); print(res, nrow=99)
cat("\n|dE| 민감도 SR: A=", round(ann_sr(sens$A),3), " B=", round(ann_sr(sens$B),3), " C=", round(ann_sr(sens$C),3), "\n")

cat("\n[4] 계약 bt_result x3 (A/B/C)\n")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
anchor <- p$anchor_date
bm_x <- xts(bm$BM_Ret, order.by=bm$Date); bm_win <- rep(NA_real_, nrow(p))
for (i in 2:nrow(p)) { seg <- bm_x[index(bm_x) > anchor[i-1] & index(bm_x) <= anchor[i]]
  if (nrow(seg) > 0) bm_win[i] <- as.numeric(Return.cumulative(seg)) }
bm_win[1] <- 0
make_sim <- function(ret_vec) {
  strat_xts <- xts(ret_vec, order.by=anchor)
  nav <- as.numeric(cumprod(1+ret_vec))
  list(strategy_xts=strat_xts, DAILY_NAV_DT=data.table(Date=anchor, NAV=nav, NAV_gross=nav),
       bm_xts=xts(bm_win, order.by=anchor), HOLDINGS_LOG=NULL, PORTFOLIO_LOG=NULL) }
CAVEATS <- c(
  "CLEAN_TIMING=faith 신호 S(EOM m)->realized_ym m+2 (배포 forward_weights와 동일). 구 admit 근거(concurrent)와 비교불가 — 본 3-way가 공정 기준.",
  "M4_DELTA_UNCOSTED=canonical convention 유지(m4 회전 비과금) — 3-way 동일 적용이라 상대비교 무영향.",
  "PANEL_LINEAGE=holdings 불변 scalar overlay 계보(STR_1715 ret_orig 위 곱셈). 종목레벨 재실행 아님.",
  "SELECTION=감사 결과로 사전지정된 3-way 고정비교(탐색 argmax 없음). 선행 오버레이 탐색 sweep(n=31)은 별도 기록.",
  "DECISION_MANUAL=Layer4 처분은 judge+governor(도훈 수동) — 본 산출은 증거만.")
specs <- list(
  A_faith_clean = "PG2 Layer4=faith CLEAN-timing (S EOM m -> m+2, freq-match {0.4,0.7,1.0})",
  B_AR          = "PG2 Layer4=AR(absorption, 기록 — 원래 클린)",
  C_noL4        = "PG2 Layer4 제거 (beta_R05 x m4 only)")
pat_row <- function(bt) { tryCatch({ bc <- bt$benchmark_compare
  key <- if ("metric" %in% names(bc)) bc$metric else if ("metric_name" %in% names(bc)) bc$metric_name else rownames(bc)
  val_col <- setdiff(names(bc), c("metric","metric_name"))[1]
  as.numeric(bc[[val_col]][key=="Portfolio_Alpha_t_NW_lag3"]) }, error=function(e) NA_real_) }
bt_summary <- list()
for (nm in names(specs)) {
  spec <- list(strategy_id=paste0("PG2_L4RETRIAL_", nm), strategy_name=specs[[nm]],
    strategy_family="overlay_pg2_str1715", universe_rule="KOSPI200 U KOSDAQ150 (STR_1715 lineage)",
    rebalance_frequency="monthly", execution_date_rule="t+1 lag",
    signal_date_rule="all signals <= prev month-end (clean); AR/m4/R05 = panel canonical",
    lookahead_prevention=paste(CAVEATS, collapse=" | "), cost_bps=15)
  bt <- tryCatch(build_bt_result(make_sim(series[[nm]]), spec,
          run_id=paste0("L4_retrial_", nm, "_20260702"), strategy_id=spec$strategy_id,
          benchmark_id="KOSPI200", transaction_cost_bps=15, frequency="monthly"),
        error=function(e){cat("   ", nm, "build_bt_result 예외:", conditionMessage(e), "\n"); NULL})
  if (!is.null(bt)) {
    saveRDS(bt, file.path(OUT, paste0("bt_result_", nm, ".rds")))
    audit_int <- tryCatch(bt$audit$integrity, error=function(e) NA)
    pat <- pat_row(bt)
    bt_summary[[nm]] <- list(audit=audit_int, port_alpha_t_nw3=round(pat,3))
    cat(sprintf("    %s: audit=%s | Portfolio_Alpha_t_NW_lag3=%.3f\n", nm, audit_int, pat))
  } else bt_summary[[nm]] <- list(audit="BUILD_FAIL", port_alpha_t_nw3=NA)
}

fwrite(res, file.path(OUT, "layer4_retrial_comparison.csv"))
meta <- list(wt="WT-D20260702_002", date="2026-07-02", mandate="도훈 승인 P0-2 (pg2_reinforcement_roadmap_20260702.md)",
  caveats=CAVEATS, bt=bt_summary, metric_type="backtested(contract)",
  cost_primary="per-layer canonical", cost_sensitivity_dE=list(A=round(ann_sr(sens$A),3), B=round(ann_sr(sens$B),3), C=round(ann_sr(sens$C),3)))
write_json(meta, file.path(OUT, "layer4_retrial_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\n[DONE] 산출:", OUT, "\n")
