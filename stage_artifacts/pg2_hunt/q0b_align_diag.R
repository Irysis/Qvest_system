## q0b — 정합 실패 원인 진단. corr ~0.11 은 "빈티지 차이"가 아니라 **정렬 실패** 지문이다.
## 두 KOSPI200 계열이 0.11 로 상관될 수는 없다. 위상을 넓히고 원계열을 나란히 본다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[q0b] ", fmt, "\n"), ...)); flush.console() }
OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")

pg2_dir <- file.path(ROOT, "05_Production/2.Factor_Model",
                     "2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results")
BR <- fread(file.path(pg2_dir, "05_benchmark_returns.csv"))
BR[, date := as.Date(date)]
A <- BR[, .(t = as.integer(format(date,"%Y"))*12L + as.integer(format(date,"%m")),
            ym = format(date,"%Y-%m"), pg2 = benchmark_ret)]

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
BC <- as.data.table(P$bench)
B <- BC[is.finite(BM_Ret), .(t = as.integer(format(Date,"%Y"))*12L + as.integer(format(Date,"%m")),
                             ym = format(Date,"%Y-%m"), cand = BM_Ret)]

say("=== 위상 스캔 확대 (k = 후보 t 에 더하는 오프셋; 상관 최대점이 참 위상) ===")
res <- rbindlist(lapply(-4:4, function(k) {
  Bk <- copy(B)[, t := t + k]
  X <- merge(A, Bk[, .(t, cand)], by = "t")
  data.table(k = k, n = nrow(X),
             corr = if (nrow(X) > 10) cor(X$pg2, X$cand) else NA_real_,
             exact = sum(abs(X$pg2 - X$cand) < 1e-10),
             max_abs = if (nrow(X)) max(abs(X$pg2 - X$cand)) else NA_real_)
}))
print(res)

say("=== 원계열 나란히 보기 (2008-07 ~ 2009-06, 위기 구간 — 라벨 위상은 극단월이 드러낸다) ===")
W <- merge(A[, .(t, ym_pg2 = ym, pg2)], B[, .(t, ym_cand = ym, cand)], by = "t", all = FALSE)
print(W[ym_pg2 >= "2008-06" & ym_pg2 <= "2009-07"])

say("=== 후보 계열 자체 점검: 극단월 위치 ===")
print(B[order(-abs(cand))][1:10])
say("=== PG2 벤치 극단월 위치 ===")
print(A[order(-abs(pg2))][1:10])

say("=== 후보 계열의 다른 이름 후보가 있는가 (P 요소 전수) ===")
say("  P 요소: %s", paste(names(P), collapse=", "))
for (nm in names(P)) {
  el <- P[[nm]]
  if (is.data.frame(el)) say("   - %s: %d행 · 컬럼 {%s}", nm, nrow(el), paste(names(el), collapse=","))
  else say("   - %s: %s len %d", nm, class(el)[1], length(el))
}
