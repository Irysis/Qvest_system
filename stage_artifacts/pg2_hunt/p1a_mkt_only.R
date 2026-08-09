## p1a — mkt.rds 만 선행 산출 (p1 의 팩터 루프와 독립 · 게이트 에이전트 언블록)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1a] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]
bench <- as.data.table(P$bench); liq <- as.data.table(P$liq); size_dt <- as.data.table(P$size_dt)
say("ret %d행 %d개월 · bench %d행 · liq %d행 · size %d행",
    nrow(ret), uniqueN(ret$Date), nrow(bench), nrow(liq), nrow(size_dt))

## ★벤치 정합 선행 확인 (게이트 A 를 여기서 1차 실측 — 에이전트가 독립 재확인)
B <- bm_load_incumbent()
X <- merge(B[, .(date, pg2_bm = benchmark_ret)],
           bench[, .(date = Date, cand_bm = BM_Ret)], by = "date")
say("=== 벤치 정합 1차 실측 ===")
say("  겹침 %d개월 (%s ~ %s)", nrow(X), min(X$date), max(X$date))
if (nrow(X)) {
  d <- X$pg2_bm - X$cand_bm
  say("  차이: 평균 %+.6f/월 · 최대절대 %.6f · 불일치(>1e-8) %d/%d (%.1f%%)",
      mean(d), max(abs(d)), sum(abs(d) > 1e-8), nrow(X), 100*mean(abs(d) > 1e-8))
  say("  연율 차이 %+.4f%%", mean(d)*12*100)
  if (sum(abs(d) > 1e-8) > 0) {
    say("  ★불일치 구간 상위:")
    print(X[abs(pg2_bm - cand_bm) > 1e-8][order(-abs(pg2_bm - cand_bm))][1:min(8,.N)])
  } else say("  ★완전 일치 — 두 벤치는 동일 계열")
} else say("  ★겹침 0 — 날짜 규약 불일치(월초 vs 월말) 의심")

saveRDS(list(ret = ret, bench = bench, liq = liq, size_dt = size_dt), file.path(OUT, "mkt.rds"))
say("=== mkt.rds 저장 완료 ===")
