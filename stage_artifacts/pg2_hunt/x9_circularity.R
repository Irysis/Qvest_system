## x9 — ★★계약 특이성이 **순환**인가: mega_spread 는 계약 데이터에서 유도된 라벨이다
## 위험: "계약 신호가 mega_spread ON 월에서 직교한다" 가 신호 성질이 아니라
##   **라벨-신호 공통 원천**의 산물일 수 있다(선별과 검정이 같은 데이터 = 순환).
## x5 는 8재료 x 3라벨을 쟀지만 **정작 계약 슬리브 자신이 그 24셀에 없었다** — 이 라운드가 그 공백을 메운다.
##
## ★판정 규칙 (측정 전 고정):
##  - 계약 슬리브의 ON월 rho 를 **독립 라벨**(unified_Category · jump_JM_State — 둘 다 계약 데이터 무관)에서 산출
##  - 독립 라벨에서도 무작위 대비 5% 아래면 → **직교성은 신호 성질**(순환 아님)
##  - mega_spread 에서만 낮으면 → **순환** — 계약 후보의 직교성 주장 철회
##  - 대조: 같은 라벨·같은 발화율 무작위 타이밍 200회 + 계약유니버스 무작위 신호
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x9] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]

## 라벨 3종 (월말 → 익월 적용)
mklab <- function(dt, col) {
  d <- as.data.table(dt); dc <- names(d)[which(tolower(names(d)) %in% c("date","ym"))[1]]
  d[, .dd := as.Date(as.character(get(dc)))]
  mo <- d[!is.na(.dd)][order(.dd)][, .(v = last(get(col))), by = .(m = mi(.dd))]
  mo[, m_apply := m + 1L]
  v <- mo$v
  lv <- if (is.numeric(v)) (v > median(v, na.rm=TRUE)) else (v == names(sort(table(v), decreasing=TRUE))[1])
  data.table(m = mo$m_apply, on = as.logical(lv))[!is.na(on)]
}
LABS <- list()
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)
if (length(f1)) LABS[["unified_Category(독립)"]] <- mklab(read_parquet(f1[1]), "Category")
f2 <- list.files(".", pattern="^regime_jump_daily\\.parquet$", recursive=TRUE, full.names=TRUE)
if (length(f2)) LABS[["jump_JM_State(독립)"]] <- mklab(read_parquet(f2[1]), "JM_State")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LABS[["mega_spread(계약유도)"]] <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))

act_of <- function(S) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
        run_id="X9", strategy_id="X9", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)])),
        error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net, benchmark_ret)]
  PR[, m := mi(date) + 2L]
  merge(PR, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")[, a_s := ret_net - inc_bm][]
}
X <- act_of(SC)
say("=== 입력 실측 === 계약 슬리브 %d개월 (%s ~ %s) · 전체 rho %+.3f",
    nrow(X), min(X$date), max(X$date), cor(X$a_s, X$inc_act))

UNIV <- unique(SC[, .(Date, Ticker)])
set.seed(20260809)
say("=== ★계약 슬리브의 ON월 rho — 라벨 3종 (독립 2 + 계약유도 1) ===")
say("  %-24s %5s %9s %11s %11s %10s", "label", "ON", "ON rho", "무작위타이밍", "무작위신호", "판정")
rows <- list()
for (k in names(LABS)) {
  Z <- merge(X, LABS[[k]], by = "m")
  on <- Z[on %in% TRUE]
  if (nrow(on) < 12L) { say("  %-24s %5d (ON<12 판정불가)", k, nrow(on)); next }
  r_on <- cor(on$a_s, on$inc_act)
  ## 대조1: 같은 발화율 무작위 타이밍 (신호 유지)
  kk <- nrow(on); nn <- nrow(Z)
  t1 <- vapply(seq_len(200L), function(i) { idx <- sample.int(nn, kk)
    cor(Z$a_s[idx], Z$inc_act[idx]) }, numeric(1)); t1 <- t1[is.finite(t1)]
  ## 대조2: 같은 라벨 + 무작위 신호 (계약유니버스 안에서)
  t2 <- vapply(seq_len(40L), function(i) {
    S2 <- copy(UNIV)[, score := runif(.N)]
    Y <- act_of(S2); if (is.null(Y)) return(NA_real_)
    W <- merge(Y, LABS[[k]], by="m")[on %in% TRUE]
    if (nrow(W) < 12L) return(NA_real_)
    cor(W$a_s, W$inc_act) }, numeric(1)); t2 <- t2[is.finite(t2)]
  p1 <- mean(t1 < r_on); p2 <- if (length(t2)) mean(t2 < r_on) else NA_real_
  say("  %-24s %5d %+9.3f %8.0f%%(p) %8.0f%%(s) %10s", k, kk, r_on, 100*p1, 100*p2,
      if (is.finite(p2) && p1 < 0.05 && p2 < 0.05) "★직교" else if (p1 < 0.05 || (is.finite(p2)&&p2<0.05)) "부분" else "구분안됨")
  rows[[length(rows)+1L]] <- data.table(label=k, n_on=kk, r_on=r_on,
    pct_timing=100*p1, pct_signal=100*p2,
    indep = grepl("독립", k), pass = p1 < 0.05 && is.finite(p2) && p2 < 0.05)
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★★순환 판정 ===")
ind <- R[indep == TRUE]; dep <- R[indep == FALSE]
say("  독립 라벨 %d개 중 직교 통과 **%d**", nrow(ind), sum(ind$pass, na.rm=TRUE))
say("  계약유도 라벨(mega_spread) 통과 %d/%d", sum(dep$pass, na.rm=TRUE), nrow(dep))
say("  독립 라벨 ON rho 중앙 %+.3f vs 계약유도 %+.3f",
    median(ind$r_on), if (nrow(dep)) median(dep$r_on) else NA_real_)
say("  ⇒ %s",
  if (nrow(ind) && sum(ind$pass, na.rm=TRUE) > 0)
    "★★독립 라벨에서도 직교 — **순환 아님**. 계약 직교성은 신호 성질이다." else
  if (nrow(dep) && sum(dep$pass, na.rm=TRUE) > 0)
    "★★★계약유도 라벨에서만 직교 — **순환 의심 확정**. 계약 후보의 직교성 주장은 철회 대상." else
    "★어느 라벨에서도 통과 없음 — x2 의 백분위 0% 와 불일치, 측정 경로 점검 필요")
say("  ⚠x2 대조: 계약+mega_spread ON rho **+0.186** · 백분위 0%% (당시 무작위 신호 40회 기준)")
fwrite(R, file.path(OUT,"x9_circularity.csv"))
say("=== x9 완료 ===")
