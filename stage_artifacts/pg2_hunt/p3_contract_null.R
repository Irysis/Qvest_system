## p3 — ★계약 국면규칙 슬리브(ΔIR +0.074) 의 귀무 대조
## 의심: OFF 월에 벤치를 보유하면 그 구간 active=0 이 된다. 이것만으로 상관이 낮아지고
##   PG2 노출이 희석돼 ΔIR 이 오를 수 있다 — **국면 라벨이 아니라 파킹 구조**의 효과일 가능성.
## ⇒ 세 귀무를 건다:
##   N1. 무작위 타이밍 — 같은 발화율(35.6%)로 ON 월을 무작위 선택 (라벨만 무효화, 구조는 동일)
##   N2. 신호 셔플   — 월내 종목 점수를 셔플 (선별력만 무효화, 타이밍은 동일)
##   N3. 블록 무작위 — ON 을 연속 블록으로 배치 (에피소드 구조 보존한 무작위)
## ★N1 이 결정적이다. 실측 ΔIR 이 N1 분포의 95 백분위를 못 넘으면 **후보 아님**.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R  <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S0 <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S0 <- merge(S0, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S0[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S0 <- S0[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]
inc <- bm_load_incumbent()
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]

base_pr <- function(S) {
  r <- suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
        run_id="N", strategy_id="N", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)]))
  as.data.table(r$period_returns)
}
PR <- base_pr(S0)

## 규칙 적용 → ΔIR (weight 고정 0.20)
apply_rule <- function(regime_vec, dates) {
  X <- merge(PR[, .(date, ret_net, benchmark_ret)],
             data.table(date = dates, regime = regime_vec), by = "date")
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  X[, r := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(X[, .(date, ret_net = r)], weight = 0.20, incumbent = inc)
  c(dIR = o$delta_ir %||% NA_real_, cor = o$correlation_with_incumbent %||% NA_real_,
    ir = o$sleeve_standalone_ir %||% NA_real_, n = o$n_overlap %||% NA_real_)
}
`%||%` <- function(a,b) if (is.null(a)) b else a

obs <- apply_rule(Mru$regime, Mru$date)
say("=== 실측 (사전등록 국면 라벨) ===")
say("  ΔIR %+.4f · 상관 %+.3f · 슬리브IR %+.3f · 겹침 %d",
    obs["dIR"], obs["cor"], obs["ir"], obs["n"])
k <- sum(Mru$regime); n <- nrow(Mru)
say("  ON %d/%d (%.1f%%) · 연속블록 %d개", k, n, 100*k/n,
    sum(diff(c(0L, as.integer(Mru$regime))) == 1L))

NDRAW <- 500L
say("=== N1. 무작위 타이밍 (같은 발화율, 라벨만 무효화) %d회 ===", NDRAW)
set.seed(20260809)
n1 <- t(vapply(seq_len(NDRAW), function(i) {
  rv <- rep(FALSE, n); rv[sample.int(n, k)] <- TRUE
  apply_rule(rv, Mru$date)
}, numeric(4)))
d1 <- n1[,"dIR"]; d1 <- d1[is.finite(d1)]
say("  귀무 ΔIR: 평균 %+.4f · 중앙 %+.4f · sd %.4f · [5%%, 95%%] [%+.4f, %+.4f]",
    mean(d1), median(d1), sd(d1), quantile(d1,.05), quantile(d1,.95))
say("  ★실측 %+.4f 의 백분위 = **%.1f%%** · 귀무 초과 비율 p = **%.4f**",
    obs["dIR"], 100*mean(d1 < obs["dIR"]), mean(d1 >= obs["dIR"]))
say("  ★귀무에서 ΔIR>=0.05 인 비율 = **%.1f%%** (구조만으로 통과하는 빈도)", 100*mean(d1 >= 0.05))
say("  귀무 상관 중앙 %+.3f (실측 %+.3f) · 귀무 슬리브IR 중앙 %+.3f (실측 %+.3f)",
    median(n1[,"cor"], na.rm=TRUE), obs["cor"], median(n1[,"ir"], na.rm=TRUE), obs["ir"])

say("=== N2. 신호 셔플 (선별력 무효화 · 타이밍 보존) 200회 ===")
set.seed(77)
d2 <- vapply(seq_len(200L), function(i) {
  Sx <- copy(S0)[, score := sample(score), by = Date]
  PRx <- base_pr(Sx)
  X <- merge(PRx[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
  X[, sw := c(0L, abs(diff(as.integer(regime))))]
  X[, r := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
  o <- bm_delta_ir(X[, .(date, ret_net = r)], weight = 0.20, incumbent = inc)
  o$delta_ir %||% NA_real_
}, numeric(1))
d2 <- d2[is.finite(d2)]
say("  귀무 ΔIR: 중앙 %+.4f · [5%%,95%%] [%+.4f, %+.4f] · >=0.05 비율 %.1f%%",
    median(d2), quantile(d2,.05), quantile(d2,.95), 100*mean(d2 >= 0.05))
say("  ★실측 백분위 **%.1f%%** · p = **%.4f**", 100*mean(d2 < obs["dIR"]), mean(d2 >= obs["dIR"]))

say("=== N3. 블록 무작위 (에피소드 구조 보존) 500회 ===")
rl <- rle(as.integer(Mru$regime)); blk <- rl$lengths[rl$values == 1L]
say("  실측 ON 블록 길이: %s", paste(blk, collapse=", "))
set.seed(303)
d3 <- vapply(seq_len(500L), function(i) {
  rv <- rep(FALSE, n)
  for (L in blk) { st <- sample.int(max(n - L + 1L, 1L), 1L); rv[st:min(st+L-1L, n)] <- TRUE }
  apply_rule(rv, Mru$date)["dIR"]
}, numeric(1))
d3 <- d3[is.finite(d3)]
say("  귀무 ΔIR: 중앙 %+.4f · [5%%,95%%] [%+.4f, %+.4f] · >=0.05 비율 %.1f%%",
    median(d3), quantile(d3,.05), quantile(d3,.95), 100*mean(d3 >= 0.05))
say("  ★실측 백분위 **%.1f%%** · p = **%.4f**", 100*mean(d3 < obs["dIR"]), mean(d3 >= obs["dIR"]))

say("=== ★종합 판정 ===")
p1 <- mean(d1 >= obs["dIR"]); p2 <- mean(d2 >= obs["dIR"]); p3 <- mean(d3 >= obs["dIR"])
say("  N1(타이밍) p=%.4f · N2(선별) p=%.4f · N3(블록) p=%.4f", p1, p2, p3)
pass <- all(c(p1,p2,p3) < 0.05)
say("  ⇒ %s", if (pass) "★★세 귀무 전부 통과 — 라벨·선별 둘 다 실질 기여" else
   sprintf("★귀무 미분리 %d/3 — 이 ΔIR 은 구조(파킹) 또는 우연으로 설명될 수 있다",
           sum(c(p1,p2,p3) >= 0.05)))
saveRDS(list(obs=obs, n1=d1, n2=d2, n3=d3, p=c(p1,p2,p3)), file.path(OUT,"p3_null.rds"))
say("=== p3 완료 ===")
