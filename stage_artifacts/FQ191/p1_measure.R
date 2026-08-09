## FQ-191 P1 — 국면-조건부 운용 규칙의 HARD 3종 (사전등록 그대로)
## OFF 월 처리 = **벤치마크 보유** (측정 전 고정. 현금·유지 2안은 감도로만 병기)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ191")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

MY <- "Q-Lead 2026-08-09"
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-191")
g <- assert_can_start(Q$entries[[i]], "FQ-191", my_session = MY)
if (!isTRUE(g$reentry)) {
  Q$entries[[i]] <- make_claim(Q$entries[[i]], "claimed", MY, "HARD 3종 측정")
  Q$updated <- "2026-08-09"; write_frontier_queue(Q); say("claim 기록")
}

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
say("사전등록 OK — OFF 월 처리 = **%s** (측정 전 고정)",
    PRE$`★the_only_degree_of_freedom_fixed_now`$CHOSEN_BEFORE_MEASUREMENT)

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
say("=== 입력 실측 === returns %d행 · %d개월 · bench %d행", nrow(R), uniqueN(R$Date), nrow(BM))
R <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
say("  물리불가 격리 후 %d행", nrow(R))

me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[, .(ym, Ticker, w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[, .(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size) & Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score) & score>0, .(Date,Ticker,score)]
rt <- R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[, .(Date,BM_Ret)]

SZ <- merge(R[,.(Date,Ticker,Ret_1m)], US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
MSv <- SZ[!is.na(Size), { o <- order(-Size); .(ms = mean(Ret_1m[head(o,10)]) - median(Ret_1m)) }, by=Date][order(Date)]
MSv[, regime := shift(ms,1L) <= 0]
say("  국면 ON %d / %d", sum(MSv$regime,na.rm=TRUE), nrow(MSv))

sigr <- suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
          run_id="FQ191_SIG", strategy_id="FQ191_SIG", diag_dual_basis=FALSE))
PR <- as.data.table(sigr$period_returns)
say("  SIG 무조건부: PORT_t %+.3f · 회전율 %.2f/yr (참조)", sigr$portfolio_alpha_t_nw_lag3, sigr$turnover_annual)

## ---- 국면-조건부 NAV: ON=계약 sleeve · OFF=벤치 ------------------------------
M <- merge(PR[, .(date, sig = ret_net, bm = benchmark_ret)],
           MSv[, .(date = Date, regime)], by="date")[!is.na(regime)]
M[, w_on := as.integer(regime)]
M[, ret_rule := ifelse(regime, sig, bm)]
## 국면 전환 비용: sleeve<->벤치 전량 교체 = |Δw| = 1 (전환 달만)
M[, sw := c(0L, abs(diff(w_on)))]
M[, ret_rule_net := ret_rule - sw * 1.0 * 0.0015]
say("=== 국면 전환 ===")
say("  전환 %d회 / %d개월 (연 %.1f회) · 전환비용 총 %.2f%%p (연 %.2f%%p)",
    sum(M$sw), nrow(M), sum(M$sw)/(nrow(M)/12), sum(M$sw)*0.15, sum(M$sw)*0.15/(nrow(M)/12))

gate <- function(dt, lab) {
  pr <- data.table(date=dt$date, ret_net=dt$ret_rule_net, frequency="monthly")
  br <- data.table(date=dt$date, benchmark_ret=dt$bm, benchmark_id="KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id=paste0("FQ191_",lab),
                                strategy_id=paste0("FQ191_",lab), annualization_factor=12L)
  gv <- function(n) { v <- bc[metric_name==n, active_value]; if(!length(v)) NA_real_ else as.numeric(v[1]) }
  act <- dt$ret_rule_net - dt$bm
  nav <- cumprod(1+dt$ret_rule_net); n <- length(nav)
  mdd <- min(nav/cummax(nav) - 1)
  cagr <- nav[n]^(12/n) - 1
  oos <- .canon_oos_rough(act)
  list(lab=lab, n=n, port_t=gv("Portfolio_Alpha_t_NW_lag3"), ir=gv("Information_Ratio"),
       alpha_ann=gv("Alpha_Annualized"), cagr=cagr, mdd=mdd,
       calmar=if (mdd<0) cagr/abs(mdd) else NA_real_, oos=oos,
       sr=mean(act)/sd(act)*sqrt(12))
}
say("=== ★HARD 3종 (정본 = 2026 제외) ===")
res <- list()
for (cfg in list(list(d=M[date < as.Date("2026-01-01")], l="정본: 2026 제외"),
                 list(d=M, l="감도: 2026 포함"))) {
  r <- gate(cfg$d, cfg$l); res[[length(res)+1L]] <- r
  say("  --- %s (n=%d) ---", r$lab, r$n)
  say("    PORT_t %+.3f (HARD 2.95) %s", r$port_t, if (!is.na(r$port_t) && r$port_t>=2.95) "PASS" else "FAIL")
  say("    oos_retention %+.3f (HARD 0.7) %s", r$oos, if (!is.na(r$oos) && r$oos>=0.7) "PASS" else "FAIL")
  say("    calmar %+.3f (HARD 0.64) %s", r$calmar, if (!is.na(r$calmar) && r$calmar>=0.64) "PASS" else "FAIL")
  say("    [참조] CAGR %+.2f%% · MDD %+.2f%% · IR %+.3f · active SR %+.3f · alpha_ann %+.4f",
      r$cagr*100, r$mdd*100, r$ir, r$sr, r$alpha_ann)
}

say("=== 감도: OFF 월 대체 처리 (판정 아님 — 사전등록이 argmax 금지) ===")
for (alt in c("현금","sleeve 유지")) {
  A <- copy(M)
  A[, ret_rule := if (alt=="현금") ifelse(regime, sig, 0) else sig]
  A[, sw := if (alt=="sleeve 유지") 0L else c(0L, abs(diff(w_on)))]
  A[, ret_rule_net := ret_rule - sw*0.0015]
  r <- gate(A[date < as.Date("2026-01-01")], alt)
  say("  %-10s : PORT_t %+.3f · calmar %+.3f · oos %+.3f · CAGR %+.2f%% · MDD %+.2f%%",
      alt, r$port_t, r$calmar, r$oos, r$cagr*100, r$mdd*100)
}

saveRDS(list(res=res, M=M), file.path(OUT,"p1.rds")); fwrite(M, file.path(OUT,"p1_rule.csv"))
say("=== P1 완료 ===")
