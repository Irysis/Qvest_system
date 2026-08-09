## n8 — ★insider 신호 book-marginal 측정 (사전등록 insider_preregistration.json 대로)
## 1급 = (rho, sleeve IR) vs 요구조건 지도 · 2급 = ΔIR(verdict_ci)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n8] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent(); m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w = 0.20) {
  f <- function(x) { mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i)
    v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
    mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_)
  tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_)
}
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]

I <- as.data.table(read_parquet("stage_artifacts/WT_D20260718_002/insider_sell_panel.parquet"))
SIG <- grep("^cnv_", names(I), value=TRUE)
for (s in SIG) I[[s]] <- suppressWarnings(as.numeric(I[[s]]))
say("=== 입력 실측 === %d행 · %d개월 · %d종목 · 신호 %d종",
    nrow(I), uniqueN(I$ym), uniqueN(I$Ticker), length(SIG))

## ★사전등록 신호 구성: 월내 **비영** 종목만 · 1e12 winsorize · **오름차순**(매도 낮을수록 상위)
TH <- 1e12
build <- function(sig, include_zero = FALSE) {
  D <- I[, .(Date = as.Date(Date), Ticker, v = get(sig))]
  D <- D[is.finite(v)]
  if (!include_zero) D <- D[v != 0]
  D[, vw := pmin(pmax(v, -TH), TH)]
  ## 오름차순 = 매도 강도 낮을수록 score 높게 → -vw 로 랭킹
  D[, score := frank(-vw, ties.method = "average"), by = Date]
  D[, .(Date, Ticker, score)]
}

mk <- function(S, parked) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="INS",
        strategy_id="INS", diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))),
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
  o <- bm_delta_ir(PR, weight = 0.20, incumbent = inc, B_boot = 600L)
  if (is.null(o$delta_ir)) return(NULL)
  o$port_t <- r$portfolio_alpha_t_nw_lag3
  o
}

say("=== ★1급 판정: (rho, IR) vs 요구조건 지도 ===")
say("  통과 조건(사전등록) = rho <= 0.277 ∧ IR >= need_ir(rho)")
say("  대조 기준 = 계약 슬리브 실측 (rho 0.140 · IR 0.758)")
say("  %-14s %-8s %5s %8s %8s %9s %9s %-14s", "신호","arm","n","rho","IR","필요IR","부족분","verdict_ci")
rows <- list()
for (s in SIG) for (pk in c(FALSE, TRUE)) {
  o <- mk(build(s), pk)
  if (is.null(o)) { say("  %-14s %-8s (측정 실패)", s, if (pk) "parked" else "uncond"); next }
  nd <- need_ir(o$correlation_with_incumbent)
  say("  %-14s %-8s %5d %+8.3f %+8.3f %9s %+9.3f %-14s", s, if (pk) "parked" else "uncond",
      o$n_overlap, o$correlation_with_incumbent, o$sleeve_standalone_ir,
      if (is.na(nd)) "불가" else sprintf("%.3f", nd),
      if (is.na(nd)) NA_real_ else nd - o$sleeve_standalone_ir, o$verdict_ci)
  rows[[length(rows)+1L]] <- data.table(signal=s, arm=if (pk) "parked" else "uncond",
    n=o$n_overlap, rho=o$correlation_with_incumbent, ir=o$sleeve_standalone_ir,
    need=nd, short=if (is.na(nd)) NA_real_ else nd - o$sleeve_standalone_ir,
    dIR=o$delta_ir, ci_lo=o$delta_ir_ci$lo, ci_hi=o$delta_ir_ci$hi,
    verdict=o$verdict_ci, port_t=o$port_t)
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★요약 ===")
say("  rho <= 0.277 인 셀: **%d/%d**", sum(R$rho <= 0.277, na.rm=TRUE), nrow(R))
say("  1급 통과(rho<=0.277 ∧ IR>=need): **%d/%d**",
    sum(R$rho <= 0.277 & R$ir >= R$need, na.rm=TRUE), nrow(R))
say("  부족분 최소 %.3f (%s %s) · 331 최소 0.142 대비 %s",
    min(R$short, na.rm=TRUE), R[which.min(short), signal], R[which.min(short), arm],
    if (min(R$short, na.rm=TRUE) < 0.142) "★개선" else "미달")
say("  verdict_ci: BEATS_PG2 %d · UNRESOLVED %d · 그 외 %d",
    sum(R$verdict=="BEATS_PG2"), sum(R$verdict=="UNRESOLVED"),
    sum(!R$verdict %in% c("BEATS_PG2","UNRESOLVED")))
say("  ΔIR 최대 %+.4f (CI [%+.4f, %+.4f])", max(R$dIR, na.rm=TRUE),
    R[which.max(dIR), ci_lo], R[which.max(dIR), ci_hi])

say("=== 2급 민감도: 0 포함 판본 (사건 부재를 최저 매도로 취급) ===")
for (s in c("cnv_all_12","cnv_off_12")) for (pk in c(FALSE, TRUE)) {
  o <- mk(build(s, include_zero = TRUE), pk)
  if (is.null(o)) next
  say("  %-14s %-8s rho %+.3f · IR %+.3f · ΔIR %+.4f · %s", s, if (pk) "parked" else "uncond",
      o$correlation_with_incumbent, o$sleeve_standalone_ir, o$delta_ir, o$verdict_ci)
}
say("=== 부호 점검 (1급 아님 — 방향 사전선언 검증용) ===")
for (s in c("cnv_all_12")) for (pk in c(FALSE, TRUE)) {
  D <- build(s); D[, score := -score]
  o <- mk(D, pk)
  if (is.null(o)) next
  say("  역방향 %-12s %-8s rho %+.3f · IR %+.3f (선언 방향이 옳으면 여기 IR 이 더 낮아야)",
      s, if (pk) "parked" else "uncond", o$correlation_with_incumbent, o$sleeve_standalone_ir)
}
fwrite(R, file.path(OUT,"n8_insider.csv"))
say("=== n8 완료 → n8_insider.csv ===")
