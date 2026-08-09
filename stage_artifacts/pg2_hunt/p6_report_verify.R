## p6 — 보고 수치 전량 재현 검증 (인용 금지 · 이 실행 출력만 보고한다)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[v] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

say("################ A. incumbent (PG2) 실측 ################")
inc <- bm_load_incumbent()
say("  기간 %d개월 %s ~ %s", nrow(inc), min(inc$date), max(inc$date))
say("  net SR (arith,12) %.4f · net active IR **%.4f**",
    mean(inc$ret_net)/sd(inc$ret_net)*sqrt(12), bm_ir(inc$active))
J <- jsonlite::fromJSON(file.path(ROOT,
  "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/_clean_metrics_summary.json"))
say("  production 선언: SR_geo %.4f · CAGR %.4f · MDD %.4f · Calmar %.4f · PORT_t %.4f · IR %.4f",
    J$SR_geo, J$CAGR, J$MDD, J$Calmar, J$PORT_t_NW_lag3, J$net_active_IR_arith)
say("  ★재현 차 (IR): %+.6f", bm_ir(inc$active) - J$net_active_IR_arith)

say("################ B. 기전 — 직교성이 유일 레버 ################")
set.seed(7)
o <- rnorm(nrow(inc)); o <- o - as.numeric(lm(o ~ inc$active)$fitted.values)
o <- o/sd(o)*sd(inc$active) + mean(inc$active)
r_orth <- bm_delta_ir(inc[, .(date, ret_net = benchmark_ret + o)], weight = 0.20)
r_same <- bm_delta_ir(inc[, .(date, ret_net = benchmark_ret + inc$active)], weight = 0.20)
set.seed(42)
r_nois <- bm_delta_ir(inc[, .(date, ret_net = benchmark_ret + rnorm(nrow(inc), 0, sd(inc$active)))], weight = 0.20)
say("  무상관+IR동등 (cor %+.3f) : ΔIR **%+.4f**", r_orth$correlation_with_incumbent, r_orth$delta_ir)
say("  상관 1.0                  : ΔIR **%+.4f**", r_same$delta_ir)
say("  순수 잡음                 : ΔIR **%+.4f**", r_nois$delta_ir)

say("################ C. 정렬 offset (4중 증거 재현) ################")
M <- readRDS(file.path(OUT,"mkt.rds"))
CB <- as.data.table(M$bench)[, .(Date, BM_Ret)][, m := mi(Date)]
Bm <- copy(inc)[, m := mi(date)]
EW <- as.data.table(M$ret)[!is.na(Ret_1m), .(ew = mean(Ret_1m)), by = Date][, m := mi(Date)]
say("  %8s %10s %10s %14s", "offset", "벤치상관", "부호일치", "수익계열상관")
for (k in 0:3) {
  X <- merge(Bm[, .(m, bm = benchmark_ret)], copy(CB)[, .(m = m+k, cand = BM_Ret)], by="m")
  Y <- merge(Bm[, .(m, bm = benchmark_ret)], copy(EW)[, .(m = m+k, ew)], by="m")
  say("  %+8d %10.4f %9.1f%% %14.4f", k, cor(X$bm,X$cand),
      100*mean(sign(X$bm)==sign(X$cand)), cor(Y$bm,Y$ew))
}
w <- merge(Bm[, .(m, bm=benchmark_ret)], copy(CB)[, .(m=m+2L, cand=BM_Ret)], by="m")
say("  2008-11 위기월: PG2 %+.4f · 후보(m-2) %+.4f",
    inc[format(date,"%Y-%m")=="2008-11", benchmark_ret], CB[m == 2008L*12L+11L-2L, BM_Ret])

say("################ D. 계약 슬리브 실측 ################")
BB <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(BB,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R  <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(BB,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(BB,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(BB,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
rr <- suppressWarnings(canonical_screen_bt(S, R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)],
      BM[,.(Date,BM_Ret)], top_n=25L, cost_bps_oneway=15, run_id="V", strategy_id="V",
      diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)]))
PR <- as.data.table(rr$period_returns)
u <- bm_delta_ir(PR[, .(date, ret_net)], weight = 0.20)
say("  [무조건부] %d개월 · 상관 %+.3f · 슬리브IR %+.3f · **ΔIR %+.4f**",
    u$n_overlap, u$correlation_with_incumbent, u$sleeve_standalone_ir, u$delta_ir)
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, r := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
sw <- bm_delta_ir_sweep(X[, .(date, ret_net = r)])
g <- bm_delta_ir(X[, .(date, ret_net = r)], weight = 0.20)
say("  [국면규칙] %d개월 · ON %d · 에피소드 %d · 상관 %+.3f · 슬리브IR %+.3f · **ΔIR %+.4f**",
    g$n_overlap, sum(Mru$regime), sum(diff(c(0L,as.integer(Mru$regime)))==1L),
    g$correlation_with_incumbent, g$sleeve_standalone_ir, g$delta_ir)
say("  weight sweep:")
for (i in seq_len(nrow(sw))) say("    w %.2f → ΔIR %+.4f (%s)", sw$weight[i], sw$delta_ir[i],
                                 if (isTRUE(sw$beats[i])) "통과" else "미달")

say("################ E. 증거 두께 ################")
ov <- merge(copy(inc)[, m := mi(date)], X[, .(m = mi(date)+2L, sl = r)], by="m")
say("  겹침창 PG2 IR %.4f vs 전기간 %.4f (차 %+.4f)", bm_ir(ov$active), bm_ir(inc$active),
    bm_ir(ov$active) - bm_ir(inc$active))
L <- nrow(ov); a <- inc$active
w73 <- vapply(seq_len(length(a)-L+1L), function(i) bm_ir(a[i:(i+L-1L)]), numeric(1))
say("  %d개월 롤링창 %d개 PG2 IR 중앙 %.3f → 겹침창 백분위 **%.1f%%**",
    L, length(w73), median(w73), 100*mean(w73 < bm_ir(ov$active)))
set.seed(99)
bs <- replicate(2000L, { i <- sample.int(nrow(ov), nrow(ov), TRUE)
  bm_ir(0.8*ov$ret_net[i] + 0.2*ov$sl[i] - ov$benchmark_ret[i]) - bm_ir(ov$active[i]) })
bs <- bs[is.finite(bs)]
say("  부트스트랩(2000, iid): 중앙 %+.4f · [5%%,95%%] [%+.4f, %+.4f] · >=0.05 유지 **%.1f%%**",
    median(bs), quantile(bs,.05), quantile(bs,.95), 100*mean(bs>=0.05))
say("  ⚠iid 라 에피소드 군집 무시 = 낙관 편향. 실제 CI 는 더 넓다.")
say("################ 재현 검증 완료 — 위 값만 보고한다 ################")
