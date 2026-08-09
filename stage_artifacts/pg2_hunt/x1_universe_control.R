## x1 — ★★계약 슬리브의 낮은 상관(0.140)이 **신호**인가 **유니버스**인가
## 미실행 통제. 계약 패널은 130종목뿐이고 PG2 는 K200∪KQ150 top-25 다.
## 좁고 다른 유니버스에서 아무 25종목이나 뽑아도 상관이 낮을 수 있다 —
## 그렇다면 계약 신호의 "직교성" 은 신호가 아니라 **표본 아티팩트**다.
## ⇒ 세 arm 비교: A 계약신호 / B 계약유니버스 무작위 / C 전체유니버스 무작위
##   B 의 rho 가 0.14 근처면 유니버스가 설명하고, 0.4 근처면 신호가 설명한다.
## ★이 통제가 오늘 여러 판정을 뒤집었다(대조군은 base 가 아니라 동일강도 무작위).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
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

say("=== 입력 실측 ===")
say("  계약 신호 유니버스: %d종목 · %d개월 · 월평균 %.1f종목",
    uniqueN(SC$Ticker), uniqueN(SC$Date), nrow(SC)/uniqueN(SC$Date))
say("  전체 수익 유니버스: %d종목 · 월평균 %.1f종목",
    uniqueN(rt$Ticker), nrow(rt[Date %in% SC$Date])/uniqueN(SC$Date))

run <- function(S, parked = TRUE) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
        run_id="X", strategy_id="X", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)])),
        error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)
  if (parked) {
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
    if (nrow(X) < 12) return(NULL)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    PR <- X[, .(date, ret_net = r2)]
  } else PR <- PR[, .(date, ret_net)]
  bm_delta_ir(PR, weight = 0.20, incumbent = inc, bootstrap = FALSE)
}

say("=== A. 계약 신호 (기준) ===")
for (pk in c(FALSE, TRUE)) {
  o <- run(SC, pk)
  say("  %-8s rho **%+.3f** · IR %+.3f · ΔIR %+.4f · n %d",
      if (pk) "parked" else "uncond", o$correlation_with_incumbent,
      o$sleeve_standalone_ir, o$delta_ir, o$n_overlap)
}

say("=== B. ★계약 유니버스 안에서 무작위 25종목 (신호 무효화, 유니버스 보존) 100회 ===")
UNIV <- unique(SC[, .(Date, Ticker)])
set.seed(20260809)
sim <- function(pool, n = 100L, pk) {
  vapply(seq_len(n), function(i) {
    S <- copy(pool)[, score := runif(.N)]
    o <- run(S[, .(Date, Ticker, score)], pk)
    if (is.null(o) || is.null(o$correlation_with_incumbent)) c(NA_real_, NA_real_)
    else c(o$correlation_with_incumbent, o$sleeve_standalone_ir)
  }, numeric(2))
}
for (pk in c(FALSE, TRUE)) {
  m <- sim(UNIV, 100L, pk)
  rho <- m[1,][is.finite(m[1,])]; irr <- m[2,][is.finite(m[2,])]
  say("  %-8s rho 중앙 **%+.3f** [%.3f, %.3f] · IR 중앙 %+.3f",
      if (pk) "parked" else "uncond", median(rho), quantile(rho,.05), quantile(rho,.95), median(irr))
}

say("=== C. 전체 유니버스 무작위 25종목 (같은 월 집합) 100회 ===")
FULL <- unique(rt[Date %in% SC$Date, .(Date, Ticker)])
for (pk in c(FALSE, TRUE)) {
  m <- sim(FULL, 100L, pk)
  rho <- m[1,][is.finite(m[1,])]; irr <- m[2,][is.finite(m[2,])]
  say("  %-8s rho 중앙 **%+.3f** [%.3f, %.3f] · IR 중앙 %+.3f",
      if (pk) "parked" else "uncond", median(rho), quantile(rho,.05), quantile(rho,.95), median(irr))
}

say("=== ★판정 ===")
say("  B(계약유니버스 무작위) 의 rho 가 A(계약신호) 와 가까우면 → **유니버스가 직교성을 만든다**")
say("    ⇒ 계약 신호의 '특별함' 은 신호가 아니라 표본이고, 같은 효과를 아무 좁은 유니버스로도 얻는다")
say("  B 가 C 와 가깝고 A 만 낮으면 → **신호가 직교성을 만든다** (계약 후보 유지)")
say("  ★어느 쪽이든 IR 은 별개 축이다 — A 의 IR 0.758 이 B 대비 높은지 함께 본다")
say("=== x1 완료 ===")
