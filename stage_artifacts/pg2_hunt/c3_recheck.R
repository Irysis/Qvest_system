## c3 — ★고친 계약(CI-기반 verdict)으로 오늘 보고분 전량 재판정
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c3] ", fmt, "\n"), ...)); flush.console() }
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
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
r <- suppressWarnings(canonical_screen_bt(S, R[!is.na(Ret_1m),.(Date,Ticker,Ret_1m)], BM[,.(Date,BM_Ret)],
      top_n=25L, cost_bps_oneway=15, run_id="C3", strategy_id="C3", diag_dual_basis=FALSE,
      size_dt=US[,.(Date,Ticker,Size)]))
PR <- as.data.table(r$period_returns)
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, rr := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]

say("=== ★계약 국면규칙 슬리브 — 고친 계약으로 재판정 ===")
sw <- bm_delta_ir_sweep(X[, .(date, ret_net = rr)])
say("  %6s %9s %9s %9s %8s %-18s %-14s", "w", "ΔIR", "CI하단", "CI상단", "se", "verdict_ci", "verdict(점)")
for (i in seq_len(nrow(sw))) say("  %6.2f %+9.4f %+9.4f %+9.4f %8.4f %-18s %-14s",
  sw$weight[i], sw$delta_ir[i], sw$ci_lo[i], sw$ci_hi[i], sw$se[i], sw$verdict_ci[i], sw$verdict_point[i])
say("  ★CI 기준 통과 **%d/5** · 점추정 기준 통과 %d/5", sum(sw$beats), sum(sw$beats_point))
say("  ★UNRESOLVED %d/5", sum(sw$unresolved))

say("=== ★오늘 내 보고의 정정 ===")
say("  내가 쓴 것: 'ΔIR +0.0740 → BEATS_PG2 · w=0.15/0.20/0.30 세 지점에서 문턱 통과'")
say("  실제      : 점추정은 그렇지만 **CI 하단이 전 weight 에서 문턱 미달** → verdict_ci = %s",
    paste(unique(sw$verdict_ci), collapse="/"))
say("  ⇒ 정직한 라벨 = **UNRESOLVED** (통과도 미달도 단정 불가). 'PG2 를 이겼다' 는 주장 불가.")
say("  ⇒ 라우팅(오버레이 후보 + 증거 누적 대기)은 **불변** — 결론은 같고 근거가 정확해졌다.")

say("=== 참고: 48재료 탈락 판정은 여전히 유효한가 ===")
say("  48재료 ΔIR 중앙 -0.1888 · 269개월 se ~0.046 → 중앙값은 문턱에서 **%.1f se** 아래",
    (0.05 - (-0.1888))/0.046)
say("  ⇒ ★탈락 판정은 CI 로도 유지된다(비대칭 확인). 통과 판정만 해상도에 걸린다.")
saveRDS(sw, file.path(OUT, "c3_recheck.rds")); fwrite(sw, file.path(OUT,"c3_recheck.csv"))
say("=== c3 완료 ===")
