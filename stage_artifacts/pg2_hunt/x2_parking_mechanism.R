## x2 — ★파킹 상호작용의 정체: uncond 에서 A≈B≈C 인데 parked 에서만 A 가 갈리는 이유
## 관측(x1): uncond rho A 0.564 ≈ B 0.581 ≈ C 0.558 / parked rho A **0.140** vs B 0.273 · C 0.277
##          parked IR A **0.758** vs B 0.062 · C -0.289
## 파킹 = ON 월엔 슬리브, OFF 월엔 벤치 ⇒ parked active = a_s x 1{ON}, OFF 월은 정확히 0.
## rho = cov(parked, a_i) / (sd_parked * sd_i) 이므로 세 경로로 갈릴 수 있다:
##   ①ON 월에서의 상관 자체가 낮다  ②ON 월 active 의 sd 가 커서 분모가 커진다
##   ③ON/OFF 배치가 PG2 의 active 와 특정 관계를 갖는다
## ★어느 것인지 직접 분해한다. 기전을 모르면 재현도 이식도 못 한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]

## 슬리브 active 계열(월별)을 PG2 정렬로 반환
act_of <- function(S) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
        run_id="M", strategy_id="M", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)])),
        error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net, benchmark_ret)]
  X <- merge(PR, Mru[, .(date, regime)], by="date")
  if (!nrow(X)) return(NULL)
  X[, m := mi(date) + 2L]
  X <- merge(X, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")
  X[, a_s := ret_net - inc_bm]                       # 슬리브 active (PG2 벤치 기준)
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  X[, a_p := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4 - inc_bm]  # 파킹 active
  X[]
}

A <- act_of(SC)
say("=== 입력 실측 === %d개월 · ON %d (%.1f%%)", nrow(A), sum(A$regime), 100*mean(A$regime))

decomp <- function(X, lab) {
  on <- X[regime %in% TRUE]; off <- X[regime %in% FALSE]
  r_all <- cor(X$a_s, X$inc_act); r_on <- cor(on$a_s, on$inc_act); r_off <- cor(off$a_s, off$inc_act)
  r_pk  <- cor(X$a_p, X$inc_act)
  say("  [%s]", lab)
  say("    슬리브 active   : 전체 rho %+.3f · **ON 월 rho %+.3f** · OFF 월 rho %+.3f", r_all, r_on, r_off)
  say("    파킹 active     : rho %+.3f · sd %.5f (슬리브 sd %.5f · 비율 %.3f)",
      r_pk, sd(X$a_p), sd(X$a_s), sd(X$a_p)/sd(X$a_s))
  say("    ON 월 sd: 슬리브 %.5f vs PG2 %.5f (비율 %.2f) · OFF 월 파킹 active sd %.5f",
      sd(on$a_s), sd(on$inc_act), sd(on$a_s)/sd(on$inc_act), sd(off$a_p))
  say("    평균: ON 슬리브 %+.5f · OFF 파킹 %+.5f · 전체 파킹 %+.5f",
      mean(on$a_s), mean(off$a_p), mean(X$a_p))
  say("    IR: 슬리브 %+.3f · 파킹 %+.3f", bm_ir(X$a_s), bm_ir(X$a_p))
  c(r_all=r_all, r_on=r_on, r_pk=r_pk, ir_pk=bm_ir(X$a_p))
}
say("=== 1. ★계약 신호 분해 ===")
dA <- decomp(A, "계약")

say("=== 2. 무작위 대조 (계약 유니버스, 40회) — 같은 분해 ===")
UNIV <- unique(SC[, .(Date, Ticker)])
set.seed(20260809)
mm <- t(vapply(seq_len(40L), function(i) {
  S <- copy(UNIV)[, score := runif(.N)]
  X <- act_of(S)
  if (is.null(X)) return(c(NA,NA,NA,NA))
  on <- X[regime %in% TRUE]
  c(cor(X$a_s, X$inc_act), cor(on$a_s, on$inc_act), cor(X$a_p, X$inc_act), bm_ir(X$a_p))
}, numeric(4)))
colnames(mm) <- c("r_all","r_on","r_pk","ir_pk")
for (k in colnames(mm)) {
  v <- mm[,k]; v <- v[is.finite(v)]
  say("  %-6s 무작위 중앙 %+.3f [%.3f, %.3f] · **계약 %+.3f** · 백분위 %.0f%%",
      k, median(v), quantile(v,.05), quantile(v,.95), dA[k], 100*mean(v < dA[k]))
}

say("=== 3. ★판정: 어느 경로가 갈랐나 ===")
say("  경로① ON 월 상관: 계약 %+.3f vs 무작위 중앙 %+.3f → %s",
    dA["r_on"], median(mm[,"r_on"], na.rm=TRUE),
    if (dA["r_on"] < quantile(mm[,"r_on"], .05, na.rm=TRUE)) "★계약이 유의하게 낮다" else "구분 안 됨")
say("  경로② 분모(sd) 확대: 파킹/슬리브 sd 비율로 확인 — 위 §1 출력 참조")
say("  경로③ ON/OFF 배치: OFF 월 파킹 active 는 전환비용 외 0 이므로 배치가 sd·평균을 함께 바꾼다")
say("  ⇒ ON 월 상관이 낮으면 **신호가 국면 ON 에서 직교 정보를 갖는다**(이식 가능)")
say("     ON 월 상관이 같으면 **파킹 구조와 신호의 우연한 상호작용**(이식 불가·재현 취약)")
saveRDS(list(A=A, dA=dA, mm=mm), file.path(OUT,"x2.rds"))
say("=== x2 완료 ===")
