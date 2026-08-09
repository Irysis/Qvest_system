## z4 — ★희석 가설 정식 검정 (축·방향 확정 후)
## z3 확정: `Category == RISK_ON` ⟺ `Regime_Score` **하위 71.7%** — 일치 **100.0%** · phi **+1.000**.
##   ⇒ Regime_Score(low) 가 Category 의 **정확한 연속 원천**이다. 문턱을 조여 발화율을 낮출 수 있다.
## ★z3 자가 검거: `setorder(R, -phi)` 에서 **NA 가 최대처럼 정렬**돼 Cash_Pct(phi NA)를 1위로 뽑았다.
##   완벽한 축(phi 1.000)을 놓칠 뻔했다. ⇒ 정렬 전 NA 제거는 선택이 아니라 필수.
## 가설: 발화율을 71.7% → 50/35/20% 로 조이면 ON월 rho 인하 폭이 커지는가(계약 수준 0% 에 접근하는가).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[z4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1))
dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
mo <- U[!is.na(.dd)][order(.dd)][, .(cat = last(Category), rs = last(Regime_Score)), by = .(m = mi(.dd))]
mo[, m_apply := m + 1L]; mo <- mo[m_apply %in% inc$m]
say("=== 재현 확인 (착수 전 필수) ===")
th0 <- quantile(mo$rs, 0.717, na.rm = TRUE)
say("  Regime_Score 하위 71.7%% vs Category==RISK_ON 일치 **%.1f%%**",
    100*mean((mo$rs <= th0) == (mo$cat == "RISK_ON")))

say("=== ★착수 전 검정력 선언 ===")
RATES <- c(0.717, 0.50, 0.35, 0.20)
say("  %8s %8s %10s %14s", "목표율", "ON월", "에피소드", "판정 가능?")
LAB <- list()
for (p in RATES) {
  th <- quantile(mo$rs, p, na.rm = TRUE)
  on <- mo$rs <= th; on[is.na(on)] <- FALSE
  ep <- sum(rle(as.integer(on))$values == 1L)
  say("  %7.1f%% %8d %10d %14s", 100*p, sum(on), ep,
      if (sum(on) >= 24 && ep >= 8) "가능" else "★검정력 부족")
  if (sum(on) >= 24 && ep >= 8) LAB[[sprintf("rate%02.0f", 100*p)]] <- data.table(m = mo$m_apply, on = on)
}
say("  ★계약 대조: ON 26 · 에피소드 14 · 백분위 **0%%**")
if (!length(LAB)) { say("=== 전 발화율 검정력 부족 — 착수 불가 ==="); quit(status=0) }

TB <- fread(file.path(OUT,"c6_full_table.csv"))
top <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
set.seed(7); rnd <- sample(setdiff(unique(A$Factor_Name), top), 4)
FS <- c(top, rnd)
act_of <- function(f) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net)][, m := mi(date) + 2L]
  merge(PR, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")[, a_s := ret_net - inc_bm][]
}
say("=== ★희석 가설: 발화율 ↓ → ON월 rho 백분위 ↓ 인가 ===")
say("  %-24s %s", "factor", paste(sprintf("%10s", names(LAB)), collapse=""))
set.seed(20260809); rows <- list()
for (f in FS) {
  X <- act_of(f); if (is.null(X) || nrow(X) < 60) next
  out <- c()
  for (k in names(LAB)) {
    Z <- merge(X, LAB[[k]], by="m"); on <- Z[on %in% TRUE]
    if (nrow(on) < 12L) { out <- c(out, NA_real_); next }
    r_on <- cor(on$a_s, on$inc_act); kk <- nrow(on); nn <- nrow(Z)
    rr <- vapply(seq_len(100L), function(i) { idx <- sample.int(nn, kk)
      cor(Z$a_s[idx], Z$inc_act[idx]) }, numeric(1)); rr <- rr[is.finite(rr)]
    pc <- 100*mean(rr < r_on); out <- c(out, pc)
    rows[[length(rows)+1L]] <- data.table(factor=f, rate=k, n_on=kk, r_on=r_on, pct=pc)
  }
  say("  %-24s %s", substr(f,1,24), paste(sprintf("%9.0f%%", out), collapse=""))
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
mid <- R[, .(p = median(pct), n = n_on[1], pass5 = sum(pct<5), pass50 = sum(pct<50), k = .N), by = rate]
setorder(mid, -n)
for (i in seq_len(nrow(mid))) say("  %-8s ON %3d · 백분위 중앙 **%.0f%%** · <5%% %d/%d · <50%% %d/%d",
  mid$rate[i], mid$n[i], mid$p[i], mid$pass5[i], mid$k[i], mid$pass50[i], mid$k[i])
say("  실측 궤적(ON 많은→적은): %s", paste(sprintf("%.0f%%", mid$p), collapse=" → "))
trend <- if (nrow(mid) >= 3) suppressWarnings(cor(mid$n, mid$p, method="spearman")) else NA_real_
say("  ★ON월수 vs 백분위 spearman = %+.3f (양수면 조일수록 개선 = 희석 가설 지지)", trend)
say("  ⇒ %s", if (is.finite(trend) && trend > 0.5 && min(mid$p) < 20)
  "★★희석 가설 **지지** — 조일수록 rho 인하 폭이 커진다" else
  if (is.finite(trend) && trend > 0.5) "★방향은 지지하나 계약 수준(0%) 에 못 미침" else
  "★희석 가설 **미지지** — 발화율은 인하 폭을 설명하지 않는다")
fwrite(R, file.path(OUT,"z4_dilution.csv"))
say("=== z4 완료 ===")
