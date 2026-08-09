## p2 — [팩터 DB 밖] 계약수주 신호를 슬리브로 만들어 PG2 대비 ΔIR 측정
## 왜 유력한가: 비-return 원천이라 PG2(STR_1715 = return/가격 파생 팩터 조합)와 **직교할 가능성**이 크다.
##   오늘 확립: 무조건부 PORT_t +0.581(약함) · 국면-조건부 +2.204 · DiD 연 +26.09%(t 3.705).
##   ★standalone 문턱(2.95)은 못 넘었지만 **book-marginal 은 다른 문턱**이다 —
##     실측 기전상 상관이 낮으면 약한 알파도 ΔIR 을 만든다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R  <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]          # 물리불가 제거(2026 벤치 결함 계열)
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
S <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
S <- merge(S, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
S[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]   # 정본 정의(diag_fq125:44)
S <- S[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]
say("=== 입력 실측 ===")
say("  계약 신호 %d행 · %d개월 (%s ~ %s) · %d종목",
    nrow(S), uniqueN(S$Date), min(S$Date), max(S$Date), uniqueN(S$Ticker))
inc <- bm_load_incumbent()
say("  PG2 %d개월 (%s ~ %s)", nrow(inc), min(inc$date), max(inc$date))

mk <- function(cost = 15) {
  r <- suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=cost,
        run_id="C", strategy_id="C", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)]))
  list(pr = as.data.table(r$period_returns), t = r$portfolio_alpha_t_nw_lag3, ir = r$information_ratio)
}
A <- mk(15)
say("=== 1. 무조건부 계약 슬리브 ===")
say("  %d개월 · 슬리브 PORT_t %+.3f · IR %+.3f (후보 벤치 기준 · 진단용)",
    nrow(A$pr), A$t, A$ir)
sw1 <- bm_delta_ir_sweep(A$pr[, .(date, ret_net)])
print(sw1)
o1 <- bm_delta_ir(A$pr[, .(date, ret_net)], weight = 0.20)
say("  ★정렬 offset %+d (%s) · 겹침 %d", o1$align_offset, o1$align_basis, o1$n_overlap)
say("  ★incumbent 와 상관 **%+.3f** · 슬리브 standalone IR %+.3f",
    o1$correlation_with_incumbent, o1$sleeve_standalone_ir)
say("  ★best ΔIR %+.4f (weight %.2f) → %s",
    max(sw1$delta_ir, na.rm=TRUE), sw1[which.max(delta_ir), weight],
    if (any(sw1$beats, na.rm=TRUE)) "**BEATS_PG2**" else "미달")

say("=== 2. 국면-조건부 규칙 슬리브 (FQ-191 정본: ON=전략 · OFF=벤치 보유) ===")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
say("  규칙 %d개월 · 국면 ON %d (%.1f%%)", nrow(Mru), sum(Mru$regime), 100*mean(Mru$regime))
X <- merge(A$pr[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, r_rule := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
say("  규칙 적용 %d개월 · 전환 %d회 (연 %.1f회)", nrow(X), sum(X$sw), sum(X$sw)/(nrow(X)/12))
sw2 <- bm_delta_ir_sweep(X[, .(date, ret_net = r_rule)])
print(sw2)
o2 <- bm_delta_ir(X[, .(date, ret_net = r_rule)], weight = 0.20)
say("  ★겹침 %d · incumbent 상관 **%+.3f** · 슬리브 IR %+.3f",
    o2$n_overlap, o2$correlation_with_incumbent, o2$sleeve_standalone_ir)
say("  ★best ΔIR %+.4f → %s", max(sw2$delta_ir, na.rm=TRUE),
    if (any(sw2$beats, na.rm=TRUE)) "**BEATS_PG2**" else "미달")

say("=== 3. ★진단: 왜 되는가/안 되는가 ===")
for (nm in c("무조건부","국면규칙")) {
  o <- if (nm == "무조건부") o1 else o2
  say("  [%s] 상관 %+.3f · 슬리브IR %+.3f · incumbent IR(겹침창) %+.3f · book IR %+.3f · ΔIR %+.4f",
      nm, o$correlation_with_incumbent, o$sleeve_standalone_ir,
      o$incumbent_ir_on_overlap, o$book_ir, o$delta_ir)
}
say("  ⇒ 요구조건 대조: 상관 rho 에서 ΔIR>=0.05 를 넘으려면 슬리브 IR 이 얼마여야 하는가")
say("     (합성 실측: 무상관·IR동등 → +0.301 / 상관1 → 0 / 잡음 → -0.082)")

say("=== 4. 겹침 창 정직 표기 ===")
say("  계약 신호는 %d개월뿐이라 PG2 269개월 중 일부만 덮는다.", nrow(A$pr))
say("  ★ΔIR 은 **겹침 창에서 incumbent IR 을 재계산**해 비교한다(전기간 1.416 과 직접 비교 금지).")
say("  겹침창 incumbent IR = %+.3f (전기간 1.416 대비 %+.3f)",
    o1$incumbent_ir_on_overlap, o1$incumbent_ir_on_overlap - 1.416)

saveRDS(list(uncond = list(sw = sw1, o = o1), rule = list(sw = sw2, o = o2)),
        file.path(OUT, "p2_contract.rds"))
say("=== p2 완료 ===")
