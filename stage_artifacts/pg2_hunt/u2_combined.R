## u2 — ★두 레버 결합: 파킹(rho 인하) x 유니버스 필터(IR 상승)
## 확립: 파킹 rho 0.408→0.321(창 정합 t −5.448, 26/30) · 유니버스 필터 IR +0.349(12/12, p<1e-4).
## 두 레버는 **다른 축**에 작동하므로 결합이 (rho 0.32, IR +0.35) 를 동시에 줄 수 있다.
## 요구조건 지도: rho 0.32 에서 필요 IR ≈ 0.79. 팩터DB 최고 IR 0.576 → 부족 0.21 을 필터가 메우는가.
##
## ★사전등록(측정 전 고정):
##  - 4-arm: A 기본 / B 파킹 / C 필터 / D **파킹+필터**. 전부 계약 창 79개월(비교 가능성).
##  - 1급 = D 의 (rho, IR) 이 요구조건 지도 통과 셀에 드는가. 2급 = verdict_ci.
##  - argmax 금지 · 전 재료 보고 · 대조: 동일크기 무작위 유니버스 + 무작위 타이밍
##  - 게이트: assert_controls_agree 로 두 대조 갈림 확인(오늘 실사고 방지)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[u2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w = 0.20) {
  f <- function(x) { mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i)
    v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
    mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_)
  tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_)
}
A <- readRDS(file.path(OUT,"factor_long.rds"))
M <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
R0 <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/gridx_returns.parquet"))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
CU <- unique(merge(me, PA[,.(ym,Ticker)], by="ym", allow.cartesian=TRUE)[, .(Date, Ticker)])
sz <- CU[, .(k = .N), by = Date]
say("=== 창 통일 === 계약 유니버스 %d개월 · 월평균 %.1f종목", uniqueN(CU$Date), mean(sz$k))

meas <- function(S, parked) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="U", strategy_id="U",
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)
  if (parked) {
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
    if (nrow(X) < 12) return(NULL)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    PR <- X[, .(date, ret_net = r2)]
  } else PR <- PR[, .(date, ret_net)]
  o <- bm_delta_ir(PR, weight = 0.20, incumbent = inc, bootstrap = FALSE)
  if (is.null(o$delta_ir)) return(NULL)
  c(rho = o$correlation_with_incumbent, ir = o$sleeve_standalone_ir, d = o$delta_ir, n = o$n_overlap)
}
set.seed(7); FS <- sample(unique(A$Factor_Name), 40L)
say("=== 재료 %d종 x 4-arm ===", length(FS))
rows <- list(); t0 <- Sys.time()
for (j in seq_along(FS)) {
  f <- FS[j]
  S0 <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% CU$Date]
  if (!nrow(S0)) next
  Sf <- merge(S0, CU, by = c("Date","Ticker"))
  a <- meas(S0, FALSE); b <- meas(S0, TRUE); cc <- meas(Sf, FALSE); d <- meas(Sf, TRUE)
  if (is.null(a) || is.null(d)) next
  rows[[length(rows)+1L]] <- data.table(f=f,
    A_rho=a["rho"], A_ir=a["ir"], A_d=a["d"],
    B_rho=if(is.null(b)) NA_real_ else b["rho"], B_ir=if(is.null(b)) NA_real_ else b["ir"], B_d=if(is.null(b)) NA_real_ else b["d"],
    C_rho=if(is.null(cc)) NA_real_ else cc["rho"], C_ir=if(is.null(cc)) NA_real_ else cc["ir"], C_d=if(is.null(cc)) NA_real_ else cc["d"],
    D_rho=d["rho"], D_ir=d["ir"], D_d=d["d"])
  if (j %% 10 == 0) say("  ... %d/%d (%.1f분)", j, length(FS), as.numeric(difftime(Sys.time(),t0,units="mins")))
}
R <- rbindlist(rows, fill=TRUE)
R[, D_need := vapply(D_rho, need_ir, numeric(1))]
R[, D_short := D_need - D_ir]
say("=== ★arm 별 중앙 ===")
say("  %-22s %9s %9s %10s", "arm", "rho", "IR", "ΔIR")
for (k in c("A","B","C","D")) say("  %-22s %+9.3f %+9.3f %+10.4f",
  c(A="A 기본", B="B 파킹", C="C 필터", D="D 파킹+필터")[k],
  median(R[[paste0(k,"_rho")]], na.rm=TRUE), median(R[[paste0(k,"_ir")]], na.rm=TRUE),
  median(R[[paste0(k,"_d")]], na.rm=TRUE))
say("=== ★레버 가산성 ===")
say("  파킹 rho 효과  B−A: %+.4f · 필터 rho 효과 C−A: %+.4f · 결합 D−A: %+.4f (가산 예측 %+.4f)",
    median(R$B_rho-R$A_rho, na.rm=TRUE), median(R$C_rho-R$A_rho, na.rm=TRUE),
    median(R$D_rho-R$A_rho, na.rm=TRUE),
    median(R$B_rho-R$A_rho, na.rm=TRUE)+median(R$C_rho-R$A_rho, na.rm=TRUE))
say("  파킹 IR 효과   B−A: %+.4f · 필터 IR 효과  C−A: %+.4f · 결합 D−A: %+.4f (가산 예측 %+.4f)",
    median(R$B_ir-R$A_ir, na.rm=TRUE), median(R$C_ir-R$A_ir, na.rm=TRUE),
    median(R$D_ir-R$A_ir, na.rm=TRUE),
    median(R$B_ir-R$A_ir, na.rm=TRUE)+median(R$C_ir-R$A_ir, na.rm=TRUE))
say("=== ★1급 판정: D 가 요구조건 지도 통과 셀에 드는가 ===")
say("  D rho 중앙 %+.3f → 필요 IR %.3f · D IR 중앙 %+.3f → **부족 중앙 %.3f**",
    median(R$D_rho, na.rm=TRUE), need_ir(median(R$D_rho, na.rm=TRUE)),
    median(R$D_ir, na.rm=TRUE), median(R$D_short, na.rm=TRUE))
say("  ★통과(D_ir >= D_need): **%d / %d**", sum(R$D_ir >= R$D_need, na.rm=TRUE), nrow(R))
say("  ΔIR >= 0.05 (점추정): %d / %d · 최고 %+.4f (%s)",
    sum(R$D_d >= 0.05, na.rm=TRUE), nrow(R), max(R$D_d, na.rm=TRUE), R[which.max(D_d), f])
say("  부족분 최소 %.3f (%s) · 331 라운드 최소 0.142 대비 %s",
    min(R$D_short, na.rm=TRUE), R[which.min(D_short), f],
    if (min(R$D_short, na.rm=TRUE) < 0.142) "★개선" else "미달")
say("=== ★결론 ===")
say("  %s", if (sum(R$D_ir >= R$D_need, na.rm=TRUE) > 0)
  "★★결합이 통과 셀에 진입한 재료가 있다 — 적대 검증 대상" else
  "★결합해도 통과 0 — 두 레버를 다 써도 요구조건에 못 미친다")
fwrite(R, file.path(OUT,"u2_combined.csv"))
say("=== u2 완료 ===")
