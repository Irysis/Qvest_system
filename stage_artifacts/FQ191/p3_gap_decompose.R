## FQ-191 P3 — 두 실패 게이트의 원인 분해 (부활 가능성 판별)
##  A. PORT_t 갭 0.746 — FQ-178 사다리(net→gross→EW-basis) 적용. 비-신호 채널이 얼마인가.
##  B. oos_retention 0.414 — 신호 감쇠인가 **표본 구조**인가.
##     ★핵심: anchored 분할은 **시간**으로 자른다. 국면 ON 월이 앞쪽에 몰려 있으면
##       뒤 구간엔 ON 이 적어 active SR 이 떨어진다 — 알파 감쇠가 아니라 사건 희소성이다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ191")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")

M <- fread(file.path(OUT, "p1_rule.csv"))[, date := as.Date(date)]
M <- M[date < as.Date("2026-01-01")]     # 정본 창
say("=== 입력 실측 === %d개월 · %s ~ %s · 국면 ON %d", nrow(M), min(M$date), max(M$date), sum(M$regime))

## ---- B. oos 진단 — 국면 ON 월의 시간 분포 -----------------------------------
say("=== B. oos_retention 0.414 의 원인 ===")
M[, yr := format(date, "%Y")]
print(M[, .(n = .N, on = sum(regime), on_pct = round(100*mean(regime),1)), by = yr][order(yr)])
for (f in c(0.55, 0.65, 0.75)) {
  k <- floor(nrow(M) * f)
  say("  분할 %.0f%%: IS %d개월(ON %d, %.1f%%) / OOS %d개월(ON %d, %.1f%%)",
      f*100, k, sum(M$regime[1:k]), 100*mean(M$regime[1:k]),
      nrow(M)-k, sum(M$regime[(k+1):nrow(M)]), 100*mean(M$regime[(k+1):nrow(M)]))
}
say("  ★ON 비율이 IS/OOS 에서 크게 다르면 oos_retention 은 **알파 감쇠가 아니라 사건 희소성**을 잰다")

## ON 월만의 초과수익이 시대별로 감쇠하는가 (진짜 신호 감쇠 여부)
say("  --- ON 월 초과수익의 시대 프로파일 (신호 감쇠 직접 검사) ---")
ON <- M[regime %in% TRUE][, act := ret_rule_net - bm]
ON[, half := ifelse(seq_len(.N) <= .N/2, "전반", "후반")]
print(ON[, .(n = .N, act_ann = round(mean(act)*12*100, 2), sd = round(sd(act), 4)), by = half])
say("  ★전/후반 초과가 비슷하면 신호는 안 죽었다 — oos 미달은 분할 아티팩트")

## ---- A. PORT_t 사다리 -------------------------------------------------------
say("=== A. PORT_t 갭 0.746 채널 분해 (FQ-178 사다리) ===")
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]

rule_t <- function(cost, ew_basis = FALSE) {
  r <- suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=cost,
        run_id="L", strategy_id="L", diag_dual_basis=ew_basis,
        size_dt = US[,.(Date,Ticker,Size)]))
  PRx <- as.data.table(r$period_returns)
  ## EW-유니버스 basis: 벤치를 신호 풀 EW 로 교체
  if (ew_basis) {
    POOL <- merge(S[,.(Date,Ticker)], rt, by=c("Date","Ticker"))[, .(bm2 = mean(Ret_1m)), by=Date]
    PRx <- merge(PRx, POOL[, .(date = Date, bm2)], by="date")
    PRx[, benchmark_ret := bm2]
  }
  X <- merge(PRx[, .(date, ret_net, benchmark_ret)],
             M[, .(date, regime)], by="date")
  X[, r2 := ifelse(regime, ret_net, benchmark_ret)]
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  X[, r2 := r2 - sw * cost/1e4]
  pr <- data.table(date=X$date, ret_net=X$r2, frequency="monthly")
  br <- data.table(date=X$date, benchmark_ret=X$benchmark_ret, benchmark_id="B")
  bc <- build_benchmark_compare(pr, br, run_id="L", strategy_id="L", annualization_factor=12L)
  v <- bc[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value]
  as.numeric(v[1])
}
t_net  <- rule_t(15, FALSE)
t_gross<- rule_t(0,  FALSE)
t_ew   <- rule_t(0,  TRUE)
say("  net 15bps · cap-w 벤치      : PORT_t %+.3f  (정본 재현)", t_net)
say("  + 비용 제거(반사실 0bps)     : PORT_t %+.3f  (Δ %+.3f)", t_gross, t_gross - t_net)
say("  + EW-유니버스 basis          : PORT_t %+.3f  (Δ %+.3f)", t_ew, t_ew - t_gross)
say("  ★HARD 2.95 대비: net %+.3f · 두 채널 제거 후 %+.3f", 2.95 - t_net, t_ew - 2.95)
say("  ⇒ 비-신호 채널(비용+벤치)이 갭 %.3f 중 %.3f 를 설명 (%.0f%%)",
    2.95 - t_net, t_ew - t_net, 100*(t_ew - t_net)/(2.95 - t_net))

saveRDS(list(t_net=t_net, t_gross=t_gross, t_ew=t_ew, on_profile=ON), file.path(OUT,"p3.rds"))
say("=== P3 완료 ===")
