## s9 — 1급 통과 3건 적대 검증 (오늘 만든 게이트 전부 적용)
## 통과: STR_1675_QRebal_Hybrid(rho −0.116·IR 0.530·부족 −0.317) · STR_1675_B_monthly(−0.151·0.464·−0.303)
##       · WT_D20260424_009_pilot11(−0.015·0.541·−0.182)
## ★검증 4축: ①중복(두 STR_1675 변형이 같은 것인가) ②무작위 파킹 대조 ③귀무 창(subsample_null)
##            ④창 이동(연도별 안정성)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s9] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
TG <- c("STR_1675_QRebal_Hybrid","STR_1675_B_monthly","WT_D20260424_009_pilot11")

getW <- function(nm) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) return(NULL)
  S <- INV$ser[[j]]
  X <- merge(inc[, .(m, date, benchmark_ret, active)], S[, .(m, r)], by="m")
  W <- merge(X, LB, by="m")[order(m)]
  W[, sw := c(0L, abs(diff(as.integer(on))))]
  W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  W[]
}
say("=== ① 중복 검사 (두 STR_1675 변형) ===")
Wa <- getW(TG[1]); Wb <- getW(TG[2]); Wc <- getW(TG[3])
J <- merge(Wa[, .(m, ra = r)], Wb[, .(m, rb = r)], by="m")
say("  STR_1675 두 변형: 겹침 %d · Pearson %.6f · Spearman %.6f · 최대절대차 %.6f",
    nrow(J), cor(J$ra, J$rb), cor(J$ra, J$rb, method="spearman"), max(abs(J$ra-J$rb)))
J2 <- merge(Wa[, .(m, ra = r)], Wc[, .(m, rc = r)], by="m")
say("  QRebal vs pilot11: 겹침 %d · Pearson %.6f", nrow(J2), cor(J2$ra, J2$rc))
say("  ⇒ %s", if (cor(J$ra, J$rb) > 0.95) "★두 STR_1675 변형은 사실상 중복 — 독립 후보는 2건" else "구분됨")

say("=== ② 무작위 파킹 대조 (같은 발화율 200회) ===")
say("  %-30s %10s %12s %10s", "strategy", "실측 ΔIR", "무작위 중앙", "백분위")
set.seed(20260809)
for (nm in TG) {
  W <- getW(nm); if (is.null(W)) next
  o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
  k <- sum(W$on); n <- nrow(W)
  d <- vapply(seq_len(200L), function(i) {
    v <- rep(FALSE, n); v[sample.int(n, k)] <- TRUE
    W2 <- copy(W)[, on2 := v][, sw2 := c(0L, abs(diff(as.integer(on2))))]
    W2[, rp2 := ifelse(on2, r, benchmark_ret) - sw2*15/1e4]
    oo <- bm_delta_ir(W2[, .(date, ret_net = rp2)], weight=0.20, incumbent=inc, bootstrap=FALSE)
    if (is.null(oo$delta_ir)) NA_real_ else oo$delta_ir }, numeric(1))
  d <- d[is.finite(d)]
  say("  %-30s %+10.4f %+12.4f %9.1f%%", substr(nm,1,30), o$delta_ir, median(d), 100*mean(d < o$delta_ir))
}
say("  ★95%% 초과여야 라벨이 실질 — 아니면 구조(파킹) 효과")

say("=== ③ 귀무 창 게이트 (subsample_null) ===")
for (nm in TG) {
  W <- getW(nm); if (is.null(W)) next
  a_s <- W$r - W$benchmark_ret
  g <- subsample_null(a_s, W$active, W$on, n_draw = 1000L)
  if (!isTRUE(g$available)) { say("  %-30s 산출 불가: %s", substr(nm,1,30), g$note); next }
  say("  %-30s ON월 rho Δ %+.4f · 귀무 [%+.4f, %+.4f] · 백분위 %.1f%% · inside %s",
      substr(nm,1,30), g$delta, g$null_q05, g$null_q95, g$percentile, g$inside)
}
say("  ★inside TRUE 면 ON 창이 특별하지 않다(파킹 이득은 구조에서 온다)")

say("=== ④ 창 이동 안정성 (연도별 제외) ===")
for (nm in TG) {
  W <- getW(nm); if (is.null(W)) next
  W[, yr := (m-1L)%/%12L]
  yrs <- sort(unique(W$yr))
  ds <- vapply(yrs, function(y) {
    Z <- W[yr != y]
    if (nrow(Z) < 55) return(NA_real_)
    o <- bm_delta_ir(Z[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)
    if (is.null(o$delta_ir)) NA_real_ else o$delta_ir }, numeric(1))
  ds <- ds[is.finite(ds)]
  say("  %-30s 연도제외 ΔIR [%+.4f, %+.4f] · 부호유지 %d/%d",
      substr(nm,1,30), min(ds), max(ds), sum(ds > 0), length(ds))
}
say("=== ★종합 ===")
say("  ①중복 · ②무작위 파킹 · ③귀무 창 · ④창 이동 — 위 4축을 함께 읽어 판정")
say("  ★CI 기준은 이미 0/12(73개월에서 문턱 0.05 는 se ~0.093) — **자본 주장 불가**가 전제")
say("=== s9 완료 ===")
