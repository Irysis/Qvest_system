## z1 — ①V18 사전등록 명시 폐기 ②unified_Category **희석 가설** 검정 (착수 전 검정력 선언 포함)
##
## ①V18_AM 심화 사전등록(v18_preregistration.json) 폐기 사유:
##   워크플로 종합이 근접군의 **함의 t** 를 산출했다 — 파킹 arm 최대 1.420(V18_AM),
##   에피소드(14) 보정 시 **0.622**. |t|>2 인 파킹 재료는 328 중 1건뿐.
##   ⇒ "V18_AM 이 1위" 라는 순위 자체가 **잡음 위에서 매긴 순위**다. 심화는 잡음 추적이 된다.
##   ★사전등록을 쓰고 안 돌렸으면 **명시적으로 폐기**한다(방치 금지).
##
## ②희석 가설: unified_Category 는 8/8 전건 rho 인하(이항 p 0.0039)인데 발화율 **71.7%**(에피소드 29)로
##   계약 mega_spread(35.6%/14)보다 훨씬 완만하다. 발화율을 조이면 인하 폭이 커지는가?
##   ★조이면 ON 월수가 줄어 검정력이 함께 떨어진다 — **착수 전 선언 의무**(FQ-206 에 내가 적어둔 조건).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[z1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]

## unified 원시 신호 (Category 는 이산 → 연속 축이 필요하다. Active_Layers 를 강도로 사용)
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1))
say("=== unified 원시 === %d행 · 컬럼 %s", nrow(U), paste(names(U), collapse=", "))
dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
## ★강도 축 선정 — 초판 버그 자가 검거:
##   초판은 `Active_Layers` **하나만** 확인하고 "수치 강도 컬럼 부재"로 착수 불가 선언했다.
##   실제 컬럼에는 연속 축이 7개 있었다(MSM_Crisis_Prob·FRED_MRS·KTRI_Score·VEA_Score·
##   Regime_Score·Regime_Score_smooth·Cash_Pct). **한 이름을 찾고 없다고 결론** = 존재 검사 오용.
##   ⇒ 수치형 컬럼을 **전수 열거**하고 그중 선언적으로 고른다.
numcols <- names(U)[vapply(U, is.numeric, TRUE)]
numcols <- setdiff(numcols, c("YM"))
numcols <- numcols[vapply(numcols, function(c0) uniqueN(U[[c0]]) >= 10, TRUE)]   # 이산 제외
say("  수치 강도 후보 %d개: %s", length(numcols), paste(numcols, collapse=", "))
## 선언적 우선순위: 국면 강도의 정본 축
pref <- c("Regime_Score_smooth", "Regime_Score", "MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score")
intens <- pref[pref %in% numcols][1]
if (is.na(intens)) intens <- numcols[1]
say("  ★선택 강도 축: **%s** (선언 우선순위 기준)", intens)
if (is.na(intens)) { say("=== ★수치 축 0개 — 착수 불가 ==="); quit(status = 0) }
mo <- U[!is.na(.dd)][order(.dd)][, .(v = last(get(intens))), by = .(m = mi(.dd))]
mo[, m_apply := m + 1L]
mo <- mo[m_apply %in% inc$m]
say("  월별 강도: %d개월 · 범위 [%.2f, %.2f] · 중앙 %.2f · 고유값 %d",
    nrow(mo), min(mo$v), max(mo$v), median(mo$v), uniqueN(mo$v))

say("=== ★착수 전 검정력 선언 (발화율별 ON 월수) ===")
RATES <- c(0.717, 0.50, 0.35, 0.20)
say("  %8s %8s %12s %14s", "목표율", "ON월", "실효 에피소드", "판정 가능?")
LAB <- list()
for (p in RATES) {
  th <- quantile(mo$v, 1 - p, na.rm = TRUE)
  on <- mo$v >= th
  rl <- rle(as.integer(on)); ep <- sum(rl$values == 1L)
  say("  %7.1f%% %8d %12d %14s", 100*p, sum(on), ep,
      if (sum(on) >= 24 && ep >= 8) "가능" else "★검정력 부족")
  if (sum(on) >= 24 && ep >= 8) LAB[[sprintf("rate%02.0f", 100*p)]] <- data.table(m = mo$m_apply, on = on)
}
say("  ★계약 mega_spread 대조: ON 26 · 에피소드 14 (이 수준이 목표)")
if (!length(LAB)) { say("=== ★전 발화율에서 검정력 부족 — 착수 불가 ==="); quit(status=0) }

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
say("=== ★희석 가설 검정: 발화율 ↓ → rho 인하 폭 ↑ 인가 ===")
say("  %-24s %10s %10s %10s %10s", "factor", names(LAB)[1],
    if (length(LAB)>1) names(LAB)[2] else "", if (length(LAB)>2) names(LAB)[3] else "",
    if (length(LAB)>3) names(LAB)[4] else "")
set.seed(20260809); rows <- list()
for (f in FS) {
  X <- act_of(f); if (is.null(X) || nrow(X) < 60) next
  r_all <- cor(X$a_s, X$inc_act); out <- c()
  for (k in names(LAB)) {
    Z <- merge(X, LAB[[k]], by="m"); on <- Z[on %in% TRUE]
    if (nrow(on) < 12L) { out <- c(out, NA_real_); next }
    r_on <- cor(on$a_s, on$inc_act)
    kk <- nrow(on); nn <- nrow(Z)
    rr <- vapply(seq_len(100L), function(i) { idx <- sample.int(nn, kk)
      cor(Z$a_s[idx], Z$inc_act[idx]) }, numeric(1))
    out <- c(out, 100*mean(rr[is.finite(rr)] < r_on))
    rows[[length(rows)+1L]] <- data.table(factor=f, rate=k, n_on=kk, r_on=r_on, r_all=r_all,
      pct=100*mean(rr[is.finite(rr)] < r_on))
  }
  say("  %-24s %s", substr(f,1,24), paste(sprintf("%9.0f%%", out), collapse=" "))
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
for (k in names(LAB)) { s <- R[rate == k]
  say("  %-10s ON %3d · 백분위 중앙 **%.0f%%** · <5%% 통과 %d/%d · <50%% %d/%d",
      k, s$n_on[1], median(s$pct), sum(s$pct<5), nrow(s), sum(s$pct<50), nrow(s)) }
say("  ★희석 가설 = 발화율을 조이면 백분위가 내려간다")
mid <- R[, .(p = median(pct), n = n_on[1]), by = rate][order(-n)]
say("  실측 궤적(ON 많은 순): %s", paste(sprintf("%s(ON %d) %.0f%%", mid$rate, mid$n, mid$p), collapse=" → "))
say("  ⇒ %s", if (nrow(mid) >= 2 && mid$p[nrow(mid)] < mid$p[1])
  "★희석 가설 지지 방향 — 조일수록 백분위 하락" else "★희석 가설 미지지 — 조여도 개선 없음")
say("  ★계약 대조: ON 26 에서 백분위 **0%%**. 위 궤적이 그 수준에 도달했는가로 판정.")
fwrite(R, file.path(OUT,"z1_dilution.csv"))
say("=== z1 완료 ===")
