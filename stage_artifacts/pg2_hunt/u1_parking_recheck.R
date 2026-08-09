## u1 — ★오늘 내내 인용한 "파킹 = 검증된 일반 레버" 주장의 창-정합 재검증
## 원 근거(48재료·전수 331): 상관 0.405 → 0.317, paired t −6.983 / 전수 −24.442, 304/328 인하.
## ★그런데 그 비교는 **무조건부 268개월 vs 파킹 73개월** — 창이 다르다.
##   방금 v1 이 "26/73 부분표본만으로 rho 가 ±0.2~0.3 흔들린다" 를 확정했다. 같은 함정일 수 있다.
## ⇒ **동일 73개월 창**에서 무조건부 vs 파킹을 재비교한다. 인하가 사라지면 '레버' 서술을 철회한다.
## ★신설 게이트 사용: assert_controls_agree / subsample_null
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[u1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
A <- readRDS(file.path(OUT,"factor_long.rds"))
M <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))

sers <- function(f) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net, benchmark_ret)][, m := mi(date)+2L]
  Z <- merge(PR, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")
  Z[, a_s := ret_net - inc_bm]
  merge(Z, LB, by="m", all.x=TRUE)
}
set.seed(7)
FS <- sample(unique(A$Factor_Name), 30L)
say("=== 표본 %d재료 · 3-arm 창-정합 비교 ===", length(FS))
say("  A 무조건부(전 기간 268m) · B 무조건부(**동일 73m 창**) · C 파킹(73m)")
say("  %-24s %9s %9s %9s | %9s %9s", "factor", "A rho", "B rho", "C rho", "C−A(구주장)", "C−B(정합)")
rows <- list()
for (f in FS) {
  Z <- sers(f); if (is.null(Z) || nrow(Z) < 60) next
  W <- Z[!is.na(on)]                       # 파킹 창
  if (nrow(W) < 40) next
  rA <- cor(Z$a_s, Z$inc_act)
  rB <- cor(W$a_s, W$inc_act)
  W2 <- copy(W); W2[, sw := c(0L, abs(diff(as.integer(on))))]
  W2[, a_p := ifelse(on, ret_net, benchmark_ret) - sw*15/1e4 - inc_bm]
  rC <- cor(W2$a_p, W2$inc_act)
  rows[[length(rows)+1L]] <- data.table(f=f, rA=rA, rB=rB, rC=rC, dCA=rC-rA, dCB=rC-rB)
  if (length(rows) <= 10)
    say("  %-24s %+9.3f %+9.3f %+9.3f | %+9.3f %+9.3f", substr(f,1,24), rA, rB, rC, rC-rA, rC-rB)
}
R <- rbindlist(rows)
say("  ... (총 %d재료 측정)", nrow(R))
say("=== ★판정 ===")
say("  A 전기간 rho 중앙 %+.3f · B 동일창 rho 중앙 %+.3f · C 파킹 rho 중앙 %+.3f",
    median(R$rA), median(R$rB), median(R$rC))
t1 <- t.test(R$rC, R$rA, paired=TRUE); t2 <- t.test(R$rC, R$rB, paired=TRUE)
say("  [구 주장] C−A: 중앙 %+.4f · paired t %+.3f · p %.5f · 인하 %d/%d",
    median(R$dCA), t1$statistic, t1$p.value, sum(R$dCA < 0), nrow(R))
say("  [창 정합] C−B: 중앙 %+.4f · paired t %+.3f · p %.5f · 인하 %d/%d",
    median(R$dCB), t2$statistic, t2$p.value, sum(R$dCB < 0), nrow(R))
say("  ★창 효과만의 몫 B−A: 중앙 %+.4f (전체 인하 %+.4f 중 %.0f%%)",
    median(R$rB - R$rA), median(R$dCA),
    100*median(R$rB - R$rA)/median(R$dCA))
say("=== ★★결론 ===")
if (t2$p.value < 0.05 && median(R$dCB) < 0) {
  say("  ★파킹 인하는 **창 정합 후에도 유효**하다 — '일반 레버' 서술 유지.")
  say("     단 크기는 %+.4f 로 구 주장(%+.4f)보다 %s.", median(R$dCB), median(R$dCA),
      if (abs(median(R$dCB)) < abs(median(R$dCA))) "작다" else "크다")
} else {
  say("  ★★**파킹 인하가 창 정합 후 사라진다** — 구 주장은 **창 차이의 산물**이었다.")
  say("     오늘 내내 인용한 '파킹 = 검증된 일반 레버' 서술을 **철회**해야 한다.")
}
say("=== 게이트 적용: 파킹 창(73m)이 전기간과 다른 창인가 ===")
z <- sers(FS[1]); z <- z[!is.na(a_s)]
sub <- !is.na(z$on)
g <- subsample_null(z$a_s, z$inc_act, sub, n_draw = 1000L)
if (isTRUE(g$available))
  say("  예시 %s: 창 Δrho %+.4f · 귀무 [%+.4f, %+.4f] · 백분위 %.1f%% · inside %s",
      substr(FS[1],1,20), g$delta, g$null_q05, g$null_q95, g$percentile, g$inside)
fwrite(R, file.path(OUT,"u1_parking.csv"))
say("=== u1 완료 ===")
