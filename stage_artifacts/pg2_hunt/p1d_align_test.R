## p1d — 정렬 수리 검증 (두 번째 데이터원 = **수익 계열**. 벤치와 독립)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1d] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

B <- bm_load_incumbent(); M <- readRDS(file.path(OUT,"mkt.rds"))
ret <- as.data.table(M$ret)

say("=== 1. [독립 데이터원] 후보 유니버스 EW 총수익 vs PG2 벤치 — offset 별 상관 ===")
EW <- ret[!is.na(Ret_1m), .(ew = mean(Ret_1m)), by = Date][, m := mi(Date)]
Bm <- copy(B)[, m := mi(date)]
for (k in -2:4) {
  X <- merge(Bm[, .(m, bm = benchmark_ret)], copy(EW)[, .(m = m + k, ew)], by = "m")
  if (nrow(X) < 24) next
  say("  offset %+d : n=%3d · 상관 %+.4f · 부호일치 %.1f%%", k, nrow(X),
      cor(X$bm, X$ew), 100*mean(sign(X$bm) == sign(X$ew)))
}
say("  ⇒ ★벤치와 **독립인 수익 계열**에서도 같은 offset 이 최대면 정렬 확증")

say("=== 2. 실제 슬리브로 겹침 복구 확인 (수리 전 0 → 수리 후 ?) ===")
A <- readRDS(file.path(OUT, "factor_long.rds"))
f <- "M26_Revenue_Mom"
if (!(f %in% unique(A$Factor_Name))) f <- sort(unique(A$Factor_Name))[1]
S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
say("  테스트 팩터 %s · %d행 · %d개월", f, nrow(S), uniqueN(S$Date))
r <- suppressWarnings(canonical_screen_bt(S, ret[!is.na(Ret_1m)], as.data.table(M$bench),
      top_n = 25L, cost_bps_oneway = 15, liq_dt = as.data.table(M$liq), liq_min = 2e8,
      run_id = "T", strategy_id = "T", diag_dual_basis = FALSE,
      size_dt = as.data.table(M$size_dt)))
pr <- as.data.table(r$period_returns)[, .(date, ret_net)]
say("  슬리브 period_returns %d개월 · 날짜 예시 %s", nrow(pr), paste(head(as.character(pr$date),3), collapse=", "))
say("  슬리브 PORT_t(후보 벤치 기준, 진단용) %+.3f", r$portfolio_alpha_t_nw_lag3)

o <- bm_delta_ir(pr, weight = 0.20)
say("  ★자동정렬 결과: offset %+d (%s)", o$align_offset, o$align_basis)
say("  status %s · 겹침 %s · ΔIR %s · 상관 %s", o$status, o$n_overlap,
    if (is.null(o$delta_ir)) "NA" else sprintf("%+.4f", o$delta_ir),
    if (is.null(o$correlation_with_incumbent)) "NA" else sprintf("%+.3f", o$correlation_with_incumbent))

say("=== 3. ★정렬 민감도 — 틀린 offset 은 다른 답을 준다(그래서 중요하다) ===")
for (k in c(0L, 1L, 2L, 3L)) {
  oo <- bm_delta_ir(pr, weight = 0.20, align_offset = k)
  say("  offset %+d : 겹침 %3s · ΔIR %8s · 슬리브IR %7s · 상관 %7s", k, oo$n_overlap,
      if (is.null(oo$delta_ir)||is.na(oo$delta_ir)) "NA" else sprintf("%+.4f", oo$delta_ir),
      if (is.null(oo$sleeve_standalone_ir)) "NA" else sprintf("%+.3f", oo$sleeve_standalone_ir),
      if (is.null(oo$correlation_with_incumbent)) "NA" else sprintf("%+.3f", oo$correlation_with_incumbent))
}
say("  ⇒ ★offset 이 판정을 바꾼다면 이 필드는 **선언 의무**다 (align_offset 이 산출에 기록됨)")

say("=== 4. 양성/음성 대조 재확인 (정렬 수리가 배관을 안 깼는가) ===")
p1 <- bm_delta_ir(B[, .(date, ret_net)], weight = 0.20)
say("  [양성] incumbent 자신 → offset %+d · ΔIR %+.2e → %s", p1$align_offset, p1$delta_ir,
    if (abs(p1$delta_ir) < 1e-9) "PASS" else "★FAIL")
set.seed(7)
orth <- rnorm(nrow(B)); orth <- orth - as.numeric(lm(orth ~ B$active)$fitted.values)
orth <- orth/sd(orth)*sd(B$active) + mean(B$active)
p2 <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + orth)], weight = 0.20)
say("  [양성] 직교 슬리브 → ΔIR %+.4f → %s", p2$delta_ir, if (p2$delta_ir > 0.05) "PASS" else "★FAIL")
p3 <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret)], weight = 0.20)
say("  [음성] 벤치 슬리브 → ΔIR %+.4f → %s", p3$delta_ir, if (p3$delta_ir <= 0) "PASS" else "★FAIL")
