## y1 — ★★계약 슬리브 rho 의 **표본 안정성**: 4개월 차이가 0.369 ↔ 0.564 를 만든다
## 불일치 발견: x2(파킹 창 73개월) 전체 rho **+0.369** vs x9(77개월) **+0.564**.
##   같은 슬리브·같은 정의인데 창 4개월 차이로 0.195 이동.
## ⇒ 26개월 ON 에서 잰 rho 0.186 에 후보 자격을 거는 것이 정당한가를 먼저 판정한다.
## ★순환 검정(x9)보다 이것이 선행이다 — 추정량이 불안정하면 순환이든 아니든 주장이 성립 안 한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[y1] ", fmt, "\n"), ...)); flush.console() }
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
r <- suppressWarnings(canonical_screen_bt(SC, R0[!is.na(Ret_1m),.(Date,Ticker,Ret_1m)], BM[,.(Date,BM_Ret)],
      top_n=25L, cost_bps_oneway=15, run_id="Y", strategy_id="Y", diag_dual_basis=FALSE,
      size_dt=US[,.(Date,Ticker,Size)]))
PR <- as.data.table(r$period_returns)[, .(date, ret_net, benchmark_ret)][, m := mi(date) + 2L]
X <- merge(PR, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")
X[, a_s := ret_net - inc_bm]
setorder(X, m)
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
Xp <- merge(X, data.table(m = mi(Mru$date)+2L, on = as.logical(Mru$regime)), by="m")

say("=== 1. 불일치 재현 ===")
say("  전체 %d개월 rho = **%+.4f**  (x9 보고 +0.564)", nrow(X), cor(X$a_s, X$inc_act))
say("  파킹창 %d개월 rho = **%+.4f**  (x2 보고 +0.369)", nrow(Xp), cor(Xp$a_s, Xp$inc_act))
d <- setdiff(X$m, Xp$m)
say("  ★차이 %d개월: %s", length(d), paste(sprintf("%04d-%02d", (d-1)%/%12, (d-1)%%12+1), collapse=", "))
if (length(d)) {
  ex <- X[m %in% d]
  say("  제외된 달의 슬리브 active: %s", paste(sprintf("%+.3f", ex$a_s), collapse=", "))
  say("  제외된 달의 북 active   : %s", paste(sprintf("%+.3f", ex$inc_act), collapse=", "))
  say("  ⇒ **%d개월이 rho 를 %+.3f 움직인다** — 표본이 작다는 직접 증거", length(d),
      cor(X$a_s, X$inc_act) - cor(Xp$a_s, Xp$inc_act))
}

say("=== 2. ★rho 추정량의 부트스트랩 신뢰구간 (블록=12) ===")
bs_rho <- function(a, b, B = 2000L, bl = 12L) {
  n <- length(a); nb <- ceiling(n/bl); st <- seq_len(max(n-bl+1L,1L))
  v <- vapply(seq_len(B), function(i) {
    idx <- unlist(lapply(sample(st, nb, TRUE), function(s) s:(s+bl-1L)))[seq_len(n)]
    idx <- idx[idx <= n]
    if (length(idx) < 12L) return(NA_real_)
    suppressWarnings(cor(a[idx], b[idx])) }, numeric(1))
  v[is.finite(v)]
}
for (nm in c("전체","파킹창")) {
  Z <- if (nm=="전체") X else Xp
  v <- bs_rho(Z$a_s, Z$inc_act)
  say("  %-6s n=%2d · rho %+.3f · CI [%+.3f, %+.3f] · 폭 **%.3f**",
      nm, nrow(Z), cor(Z$a_s, Z$inc_act), quantile(v,.05), quantile(v,.95),
      quantile(v,.95)-quantile(v,.05))
}
on <- Xp[on %in% TRUE]
v <- bs_rho(on$a_s, on$inc_act)
say("  %-6s n=%2d · rho %+.3f · CI [%+.3f, %+.3f] · 폭 **%.3f**",
    "ON월", nrow(on), cor(on$a_s, on$inc_act), quantile(v,.05), quantile(v,.95),
    quantile(v,.95)-quantile(v,.05))
say("  ★ON월 rho 0.186 의 CI 가 무작위 중앙(0.399)을 포함하면 '직교' 주장은 성립 불가")
say("     포함 여부: **%s**", quantile(v,.95) >= 0.399)

say("=== 3. leave-one-out: 한 달이 얼마나 움직이나 ===")
lo <- vapply(seq_len(nrow(on)), function(i) cor(on$a_s[-i], on$inc_act[-i]), numeric(1))
say("  ON월 26개 각각 제거 시 rho: [%+.3f, %+.3f] · 최대 이동 **%.3f**",
    min(lo), max(lo), max(abs(lo - cor(on$a_s, on$inc_act))))
w <- which.max(abs(lo - cor(on$a_s, on$inc_act)))
say("  가장 영향 큰 달: %s (슬리브 %+.3f · 북 %+.3f) — 제거 시 rho %+.3f",
    format(on$date[w]), on$a_s[w], on$inc_act[w], lo[w])

say("=== ★★판정 ===")
ci <- bs_rho(on$a_s, on$inc_act)
unstable <- (quantile(ci,.95) - quantile(ci,.05)) > 0.4
say("  ON월 rho CI 폭 %.3f · leave-one-out 최대 이동 %.3f",
    quantile(ci,.95)-quantile(ci,.05), max(abs(lo - cor(on$a_s, on$inc_act))))
say("  ⇒ %s", if (unstable)
  "★★**추정량이 불안정하다** — 26개월 ON 에서 잰 rho 에 후보 자격을 걸 수 없다. 순환 여부 이전의 문제." else
  "추정량은 안정 — 순환 검정(x9)이 유효한 다음 질문")
say("  ★x9 결과 재해석: 독립 라벨 2종에서 ON rho 0.338/0.657 로 무작위와 구분 안 됨(70%%/72%%).")
say("     mega_spread 에서만 0.186. 이것이 순환인지 표본 잡음인지 **이 폭에서는 가릴 수 없다**.")
saveRDS(list(X=X, Xp=Xp, on=on, ci=ci, lo=lo), file.path(OUT,"y1.rds"))
say("=== y1 완료 ===")
