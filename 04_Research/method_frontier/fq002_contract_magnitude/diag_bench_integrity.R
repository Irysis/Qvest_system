# diag_bench_integrity.R — .cache/benchmark.parquet 무결성 진단 (2026-07 -91% 이상치)
suppressMessages({ library(data.table); library(arrow) })
setDTthreads(2)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
b <- as.data.table(read_parquet(".cache/benchmark.parquet"))
cat("[bench] cols:", paste(names(b), collapse = ","), "| rows:", nrow(b), "\n")
b[, Date := as.Date(Date)]
cat("[bench] 범위:", format(min(b$Date)), "~", format(max(b$Date)), "\n")
cat("[bench] BM_Ret NA:", sum(is.na(b$BM_Ret)), "\n")
b[, ym := format(Date, "%Y-%m")]
mm <- b[!is.na(BM_Ret), .(n = .N, mret = prod(1 + BM_Ret) - 1,
                          minr = min(BM_Ret), maxr = max(BM_Ret)), by = ym][order(ym)]
cat("\n[bench] 최근 18개월 월수익:\n"); print(tail(mm, 18))
cat("\n[bench] |일간| > 15% 인 날 (전기간):\n")
print(b[!is.na(BM_Ret) & abs(BM_Ret) > 0.15][order(Date)][, .(Date, BM_Ret)])
cat("\n[bench] 2026-07 일별:\n")
print(b[ym == "2026-07"][order(Date)][, .(Date, BM_Ret)])
# 중복 날짜
dup <- b[, .N, by = Date][N > 1]
cat("\n[bench] 중복 Date 행:", nrow(dup), "\n"); if (nrow(dup)) print(head(dup, 10))
