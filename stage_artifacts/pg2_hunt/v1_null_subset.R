## v1 — ★★결정적 검정: ON월 26개월이 **특별한 창인가, 아무 26개월이나 그런가**
## w4/w5 확립: ON월 상관 하락은 전 재료 공통(Δrho −0.116~−0.183)이고 라벨엔 예측력이 없다(t-1 상관 −0.015).
## ⇒ 라벨이 예측력이 없다면 ON 26개월은 **준-무작위 부분집합**에 가깝다.
##    무작위 26개월 1000회에서 Δrho 귀무분포를 만들어 실측이 그 안인지 밖인지 가린다.
## ★분포 **안**이면 이 아크 전체가 **표본 산물**로 재분류된다. 밖이면 현상 확정.
## ★x2/x9 가 200회로 백분위 15%(무작위 타이밍)를 봤다 — 1000회로 재확인하고 전 재료로 확장한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[v1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
M <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
US <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/gridx_universe_size.parquet"))[, Date := as.Date(Date)]
R0 <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/gridx_returns.parquet"))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
PA <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt0 <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]
A <- readRDS(file.path(OUT,"factor_long.rds"))
TB <- fread(file.path(OUT,"c6_full_table.csv"))

pick <- function(S, N=25L) S[order(Date, -score), .SD[seq_len(min(N,.N))], by=Date][, .(Date, Ticker)]
series <- function(S, RT) {
  H <- pick(S)
  G <- merge(H, RT, by=c("Date","Ticker"))[, .(r = mean(Ret_1m)), by=Date][, m := mi(Date)+2L]
  Z <- merge(G, inc[, .(m, inc_act = active, bm = benchmark_ret)], by="m")
  Z[, a_s := r - bm]
  merge(Z, LB, by="m")
}
NDRAW <- 1000L
test1 <- function(Z, lab) {
  if (nrow(Z) < 40 || sum(Z$on) < 12) return(NULL)
  r_all <- cor(Z$a_s, Z$inc_act)
  r_on  <- cor(Z[on==TRUE, a_s], Z[on==TRUE, inc_act])
  k <- sum(Z$on); n <- nrow(Z)
  set.seed(20260809)
  d <- vapply(seq_len(NDRAW), function(i) { idx <- sample.int(n, k)
    cor(Z$a_s[idx], Z$inc_act[idx]) - r_all }, numeric(1))
  d <- d[is.finite(d)]
  obs <- r_on - r_all
  pct <- 100*mean(d < obs)
  say("  %-26s n %2d/%2d · 전체 %+.3f · ON %+.3f · **Δ %+.3f** · 귀무 [%.3f, %.3f] · **백분위 %.1f%%**",
      substr(lab,1,26), k, n, r_all, r_on, obs, quantile(d,.05), quantile(d,.95), pct)
  data.table(f=lab, k=k, n=n, r_all=r_all, r_on=r_on, dobs=obs,
             q05=quantile(d,.05), q95=quantile(d,.95), pct=pct, inside = pct > 5)
}
say("=== ★무작위 %d개월 부분집합 %d회 — Δrho 가 귀무분포 안인가 ===", sum(LB$on), NDRAW)
say("  (귀무 = 같은 계열에서 같은 개수의 월을 무작위로 뽑아 rho 를 다시 잼)")
rows <- list()
z <- series(SC, rt0); r <- test1(z, "★계약"); if (!is.null(r)) rows[[length(rows)+1L]] <- r
for (f in TB[is.finite(short_best)][order(short_best)][1:4, factor]) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% SC$Date]
  if (!nrow(S)) next
  zz <- series(S, ret[Date %in% SC$Date])
  rr <- test1(zz, f); if (!is.null(rr)) rows[[length(rows)+1L]] <- rr
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★★판정 ===")
say("  분포 **안**(백분위>5%%) : %d/%d", sum(R$inside), nrow(R))
say("  계약 백분위 **%.1f%%** — %s", R[f=="★계약", pct],
    if (R[f=="★계약", pct] > 5) "★★귀무분포 **안** — ON 26개월은 특별한 창이 아니다" else
    "★귀무분포 **밖** — ON 창이 특별하다")
say("  ⇒ %s", if (all(R$inside))
  paste0("★★★**전 재료가 귀무분포 안**이다. ON월 상관 하락(Δrho −0.116~−0.183)은 ",
         "**26개월 부분표본의 통상 변동** 범위이며 국면 라벨의 산물이 아니다. ",
         "⇒ 이 아크의 'ON월 직교' 현상은 **표본 산물로 재분류**한다.") else
  sprintf("★%d/%d 가 분포 밖 — 그 재료들에서는 창이 특별하다", sum(!R$inside), nrow(R)))
say("=== ★남는 사실 (재분류돼도 유효) ===")
say("  ①계약 파킹 슬리브의 IR 0.758 · ΔIR +0.074(CI 통과 1/5) — **성과 자체는 별개 측정**이다")
say("  ②x9 비대칭: 무작위 **타이밍** 대비 백분위 15%% vs 무작위 **신호** 대비 **0%%**")
say("     ⇒ 창이 특별한 게 아니라 **그 창에서 이 신호가 특별**하다는 뜻으로 읽힌다")
say("  ③유니버스 효과 IR +0.349(12/12, p<1e-4)는 이 재분류와 무관하게 유효")
fwrite(R, file.path(OUT,"v1_null_subset.csv"))
say("=== v1 완료 ===")
