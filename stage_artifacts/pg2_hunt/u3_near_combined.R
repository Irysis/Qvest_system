## u3 — 결합 레버를 **근접군**에 적용 (u2 는 무작위 40재료라 출발 IR −0.604 였다)
## x3 경고: 필터는 무작위군엔 +0.177 이나 **근접군엔 −0.048**(해롭다). 결합이 근접군에도 이득인가?
## 표적 셀: V18_AM 파킹 rho 0.243 · IR 0.576 · 필요 0.717 · **부족 0.142** (331 라운드 최소)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[u3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
m_i <- mean(inc$active); s_i <- sd(inc$active); ir_i <- bm_ir(inc$active)
need_ir <- function(rho, w=0.20) { f <- function(x) {
  mu <- (1-w)*m_i + w*(x/sqrt(12)*s_i); v <- (1-w)^2*s_i^2 + w^2*s_i^2 + 2*w*(1-w)*rho*s_i^2
  mu/sqrt(v)*sqrt(12) - ir_i - 0.05 }
  if (!is.finite(rho) || f(15) < 0) return(NA_real_); tryCatch(uniroot(f, c(-2,15))$root, error=function(e) NA_real_) }
A <- readRDS(file.path(OUT,"factor_long.rds"))
M <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
R0 <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/gridx_returns.parquet"))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
CU <- unique(merge(me, PA[,.(ym,Ticker)], by="ym", allow.cartesian=TRUE)[, .(Date, Ticker)])

meas <- function(S, parked) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="N", strategy_id="N",
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
  o <- bm_delta_ir(PR, weight=0.20, incumbent=inc, B_boot=600L)
  if (is.null(o$delta_ir)) return(NULL)
  ci <- o$delta_ir_ci
  c(rho=o$correlation_with_incumbent, ir=o$sleeve_standalone_ir, d=o$delta_ir,
    lo=if (isTRUE(ci$available)) ci$lo else NA_real_, hi=if (isTRUE(ci$available)) ci$hi else NA_real_)
}
TB <- fread(file.path(OUT,"c6_full_table.csv"))
FS <- TB[is.finite(short_best)][order(short_best)][1:8, factor]
say("=== 근접 %d재료 · 계약창 79개월 · B 파킹 vs D 파킹+필터 ===", length(FS))
say("  %-26s %8s %8s %8s | %8s %8s %8s %8s", "factor","B rho","B IR","B 부족","D rho","D IR","D 부족","ΔIR(D)")
rows <- list()
for (f in FS) {
  S0 <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% CU$Date]
  if (!nrow(S0)) next
  Sf <- merge(S0, CU, by=c("Date","Ticker"))
  b <- meas(S0, TRUE); d <- meas(Sf, TRUE)
  if (is.null(b) || is.null(d)) next
  nb <- need_ir(b["rho"]); nd <- need_ir(d["rho"])
  say("  %-26s %+8.3f %+8.3f %8.3f | %+8.3f %+8.3f %8.3f %+8.4f",
      substr(f,1,26), b["rho"], b["ir"], nb-b["ir"], d["rho"], d["ir"], nd-d["ir"], d["d"])
  rows[[length(rows)+1L]] <- data.table(f=f, B_rho=b["rho"], B_ir=b["ir"], B_short=nb-b["ir"],
    D_rho=d["rho"], D_ir=d["ir"], D_short=nd-d["ir"], D_d=d["d"], D_lo=d["lo"], D_hi=d["hi"])
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
say("  부족분 중앙: B 파킹 **%.3f** → D 결합 **%.3f** (변화 %+.3f)",
    median(R$B_short), median(R$D_short), median(R$D_short - R$B_short))
say("  ★필터가 근접군에 이득인가: 개선 %d/%d · IR 변화 중앙 %+.3f",
    sum(R$D_short < R$B_short), nrow(R), median(R$D_ir - R$B_ir))
say("  최소 부족분: B %.3f (%s) → D **%.3f** (%s)",
    min(R$B_short), R[which.min(B_short), f], min(R$D_short), R[which.min(D_short), f])
say("  ★통과(D_ir >= 필요): %d/%d · ΔIR CI 하단 >= 0.05: %d/%d",
    sum(R$D_short <= 0, na.rm=TRUE), nrow(R), sum(R$D_lo >= 0.05, na.rm=TRUE), nrow(R))
say("=== ★결론 ===")
say("  %s", if (median(R$D_short) < median(R$B_short))
  sprintf("★필터가 근접군에도 이득 — 부족분 %.3f → %.3f", median(R$B_short), median(R$D_short)) else
  sprintf("★★x3 경고 확인 — 필터가 근접군엔 **해롭다**(부족분 %.3f → %.3f). 결합은 약한 재료 전용 레버다",
          median(R$B_short), median(R$D_short)))
say("  ⇒ 최종 표적: 레버가 아니라 **출발 IR 0.7+ 재료**. 오늘 그런 재료는 계약(0.758) 하나뿐이었다.")
fwrite(R, file.path(OUT,"u3_near.csv"))
say("=== u3 완료 ===")
