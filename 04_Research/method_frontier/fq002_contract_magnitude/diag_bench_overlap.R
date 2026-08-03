suppressMessages({ library(data.table); library(arrow) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
setwd(.rt()); OUT <- "04_Research/method_frontier/fq002_contract_magnitude"
p <- as.data.table(read_parquet(file.path(OUT, "grid_bench.parquet")));  p[, Date := as.Date(Date)]
n <- as.data.table(read_parquet(file.path(OUT, "gridx_bench.parquet"))); n[, Date := as.Date(Date)]
m <- merge(p, n, by = "Date", suffixes = c("_pin", "_new"))
m[, d := BM_Ret_new - BM_Ret_pin]
print(m[abs(d) > 1e-9][, .(Date, BM_Ret_pin, BM_Ret_new, d)])
cat("\n확장 전용 구간(2019-11~2022-12) 월수익 요약:\n")
print(n[Date < as.Date("2023-01-01")][order(Date)][, .(Date, BM_Ret)])
