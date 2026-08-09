## n9 — ★양성 대조: 이 스크립트 경로가 알려진 양성을 여전히 검출하는가
## 사전등록 필수 통제. insider 가 0/12 로 떨어졌는데, 그것이 **측정 경로 고장**이면 음성이 무의미하다.
## 알려진 양성 = 계약 슬리브 (rho 0.140 · IR 0.758 · ΔIR +0.0740 @w0.20, 파킹 arm)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n9] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]

## --- 계약 슬리브 재현 (n8 과 동일한 mk() 구조) ---
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
r <- suppressWarnings(canonical_screen_bt(S, R0[!is.na(Ret_1m),.(Date,Ticker,Ret_1m)], BM[,.(Date,BM_Ret)],
      top_n=25L, cost_bps_oneway=15, run_id="PC", strategy_id="PC", diag_dual_basis=FALSE,
      size_dt=US[,.(Date,Ticker,Size)]))
PR <- as.data.table(r$period_returns)
X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
o <- bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc, B_boot = 600L)

say("=== ★양성 대조: 계약 슬리브 재현 ===")
say("  기대(오늘 확정): rho 0.140 · IR 0.758 · ΔIR +0.0740 · n 73")
say("  실측            : rho %+.3f · IR %+.3f · ΔIR %+.4f · n %d",
    o$correlation_with_incumbent, o$sleeve_standalone_ir, o$delta_ir, o$n_overlap)
d_rho <- abs(o$correlation_with_incumbent - 0.140); d_ir <- abs(o$sleeve_standalone_ir - 0.758)
say("  차이: rho %+.4f · IR %+.4f · ΔIR %+.4f",
    o$correlation_with_incumbent-0.140, o$sleeve_standalone_ir-0.758, o$delta_ir-0.0740)
ok <- d_rho < 0.01 && d_ir < 0.02
say("  ⇒ %s", if (ok) "★재현 성공 — 측정 경로 정상. insider 음성은 **경로 고장이 아니라 실제 결과**다"
   else "★★재현 실패 — insider 음성 판정을 신뢰할 수 없다. 경로 점검 필요")

say("=== 요구조건 대조: 계약이 통과 셀에 있는가 ===")
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (f(15) < 0) NA_real_ else uniroot(f, c(-2,15))$root }
nc <- need(o$correlation_with_incumbent)
say("  계약: rho %+.3f → 필요 IR %.3f · 실측 IR %+.3f → **여유 %+.3f**",
    o$correlation_with_incumbent, nc, o$sleeve_standalone_ir, o$sleeve_standalone_ir - nc)
say("  insider 최선(cnv_all_6 parked): rho +0.329 → 필요 0.832 · 실측 +0.222 → 부족 0.609")
say("  팩터DB 최선(V18_AM parked)     : rho +0.243 → 필요 0.717 · 실측 +0.576 → 부족 0.142")

say("=== ★판정 재구성 ===")
say("  내가 앞서 쓴 것: '병목은 재료 — 비-return 원천이 답'")
say("  ★정정: insider **도** 비-return 원천인데 rho 0.291~0.470 으로 팩터DB 와 다르지 않고 IR 도 미달이다.")
say("     ⇒ '비-return 이면 통과' 가 아니다. **계약수주 신호 하나가 특별**한 것이다.")
say("     비-return 은 지지집합 밖으로 나가기 위한 **필요조건이지 충분조건이 아니다**.")
say("  ★그러면 계약의 무엇이 특별한가 — 이것이 다음 라운드의 질문이다.")
say("     후보: ①사건-구동(수주 공시)이라 가격/수급과 독립 ②국면-조건부가 상관을 0.564→0.140 으로 낮춤")
say("     (insider 도 사건-구동인데 파킹 후 rho 0.291 — ①만으로는 설명 안 됨)")
saveRDS(o, file.path(OUT,"n9_poscontrol.rds"))
say("=== n9 완료 ===")
