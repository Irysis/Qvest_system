## p4 — ★배포 형태로 재측정: "이걸 북에 넣으면 실제로 뭐가 달라지나"
## p2/p3 는 **겹침 73개월**에서 쟀다. 실배포는 269개월 북에 얹는 것이고,
## 계약 신호가 없는 190개월엔 슬리브가 PG2 를 그대로 보유(= 기여 0)한다.
## ★이게 정직한 질문이다: 짧은 창의 국소 ΔIR 이 아니라 **전 기간 북 IR 변화**.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R  <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
r <- suppressWarnings(canonical_screen_bt(S, R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)],
      BM[,.(Date,BM_Ret)], top_n=25L, cost_bps_oneway=15, run_id="D", strategy_id="D",
      diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)]))
PR <- as.data.table(r$period_returns)
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, r_rule := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
X[, m := mi(date) + 2L]                       # 확정 정렬

inc <- bm_load_incumbent(); inc[, m := mi(date)]
say("=== 입력 실측 ===")
say("  PG2 %d개월 · 계약규칙 %d개월 · 겹침 %d개월 (%.1f%%)",
    nrow(inc), nrow(X), nrow(merge(inc[,.(m)], X[,.(m)], by="m")),
    100*nrow(merge(inc[,.(m)], X[,.(m)], by="m"))/nrow(inc))

## ★배포 형태: 슬리브가 없는 달엔 북 = PG2 단독 (기여 0)
say("=== ★배포 형태 ΔIR (전 기간 269개월) ===")
say("  %6s %10s %10s %10s %12s", "weight", "book IR", "inc IR", "ΔIR", "판정")
rows <- list()
for (w in c(0.05, 0.10, 0.15, 0.20, 0.30)) {
  Z <- merge(inc[, .(m, date, ret_net, benchmark_ret, active)],
             X[, .(m, sleeve = r_rule)], by = "m", all.x = TRUE)
  Z[, book := ifelse(is.na(sleeve), ret_net, (1-w)*ret_net + w*sleeve)]
  ir_b <- bm_ir(Z$book - Z$benchmark_ret); ir_i <- bm_ir(Z$active)
  d <- ir_b - ir_i
  say("  %6.2f %10.4f %10.4f %+10.4f %12s", w, ir_b, ir_i, d,
      if (d >= 0.05) "BEATS_PG2" else if (d > 0) "양수-미달" else "무개선")
  rows[[length(rows)+1L]] <- data.table(weight=w, book_ir=ir_b, inc_ir=ir_i, dIR=d,
                                        beats = d >= 0.05)
}
D <- rbindlist(rows)
say("  ★best ΔIR %+.4f (w %.2f) — %s", max(D$dIR), D[which.max(dIR), weight],
    if (any(D$beats)) "**전 기간 기준으로도 문턱 통과**" else "전 기간 기준으론 미달")
say("  ⇒ 겹침창(73개월) ΔIR +0.0740 과 비교: 희석 효과 %+.4f",
    max(D$dIR) - 0.0740)

say("=== 참고 지표 변화 (전 기간, w=0.20) ===")
w <- 0.20
Z <- merge(inc[, .(m, date, ret_net, benchmark_ret, active)], X[, .(m, sleeve = r_rule)], by="m", all.x=TRUE)
Z[, book := ifelse(is.na(sleeve), ret_net, (1-w)*ret_net + w*sleeve)]
nav_i <- cumprod(1 + Z$ret_net); nav_b <- cumprod(1 + Z$book)
dd <- function(nv) min(nv / cummax(nv) - 1)
say("  net SR   : PG2 %.4f → book %.4f (%+.4f)",
    mean(Z$ret_net)/sd(Z$ret_net)*sqrt(12), mean(Z$book)/sd(Z$book)*sqrt(12),
    mean(Z$book)/sd(Z$book)*sqrt(12) - mean(Z$ret_net)/sd(Z$ret_net)*sqrt(12))
say("  MDD      : PG2 %.4f → book %.4f (%+.4f)", dd(nav_i), dd(nav_b), dd(nav_b)-dd(nav_i))
say("  월평균    : PG2 %+.5f → book %+.5f", mean(Z$ret_net), mean(Z$book))
say("  ★위 SR/MDD 는 **진단용 참고**다 — 계약 문턱 판정은 build_bt_result 경유가 권위.")
say("    (cumprod 은 낙폭 궤적 진단 목적. 성과 주장에 쓰지 않는다.)")

say("=== ★정직 경계 ===")
say("  1) 슬리브가 실제로 작동하는 구간은 **73/269 = 27.1%%** 뿐이다.")
say("  2) 그 73개월 안에서도 ON 은 26개월(연속블록 14개) — 유효 에피소드가 적다.")
say("  3) ΔIR 은 weight 에 조건부다. w<0.15 에서는 겹침창에서도 미달이었다.")
say("  4) 자본 편입은 governor 수동(도훈) 이며 이 라운드는 **판정 근거**일 뿐이다.")
fwrite(D, file.path(OUT, "p4_deploy.csv")); saveRDS(list(D=D, Z=Z), file.path(OUT,"p4.rds"))
say("=== p4 완료 ===")
