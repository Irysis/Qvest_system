suppressMessages({ library(data.table); library(arrow) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
setwd(.rt())
b <- as.data.table(read_parquet(".cache/benchmark.parquet")); b[, Date := as.Date(Date)]
cat("[close] 2026-07 BM_Close:\n"); print(b[Date >= as.Date("2026-07-20")][, .(Date, BM_Close, BM_Ret)])
# 파일럿 pinned bench (월수익) 와 대조
OUT <- "04_Research/method_frontier/fq002_contract_magnitude"
pb <- as.data.table(read_parquet(file.path(OUT, "grid_bench.parquet"))); pb[, Date := as.Date(Date)]
cat("\n[close] pinned grid_bench 마지막 6행 (Date=시그널일, BM_Ret=익월 홀딩):\n"); print(tail(pb, 6))
# BM_Close 로 월수익 재산출 (Ret 열 무시) — 정합 검사
b2 <- b[order(Date)]
b2[, ym := format(Date, "%Y-%m")]
me <- b2[, .SD[.N], by = ym][, .(ym, Date, BM_Close)]
me[, mret_from_close := BM_Close / shift(BM_Close) - 1]
cat("\n[close] BM_Close 기반 월수익 최근 8개월:\n"); print(tail(me, 8))
