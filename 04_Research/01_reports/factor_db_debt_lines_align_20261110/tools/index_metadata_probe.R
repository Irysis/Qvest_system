suppressPackageStartupMessages({ library(data.table); library(arrow) })
set.seed(1)
D <- data.table(Ticker = sprintf("T%03d", sample(1:500, 2e5, TRUE)), Item = sample(c("a", "b", "c"), 2e5, TRUE), Value = runif(2e5))
setorder(D, Ticker, Item)                               # 병합기처럼 이미 정렬된 상태에서
x <- D[Item == "b", .N]                                 # .check_debt_lines 식 부분집합 → 자동 색인
setorder(D, Ticker, Item)                               # 쓰기 직전 setorder(이미 정렬 = 아무 일 없음)
cat("after no-op setorder:", paste(names(attributes(D)), collapse = ","), "| indices:", paste(indices(D), collapse = ","), "\n")
f <- tempfile(fileext = ".parquet"); write_parquet(D, f)
cat("file MB:", round(file.size(f) / 1e6, 2), "\n")
R <- as.data.table(read_parquet(f))
cat("read back attrs:", paste(names(attributes(R)), collapse = ","), "| indices:", paste(indices(R), collapse = ","), "\n")
cat(sprintf("subset same=%s\n", isTRUE(all.equal(R[R$Item == "b", sum(Value)], R[Item == "b", sum(Value)]))))
setindex(D, NULL); f2 <- tempfile(fileext = ".parquet"); write_parquet(D, f2)
cat("after setindex(D, NULL):", paste(names(attributes(D)), collapse = ","), "· file MB:", round(file.size(f2) / 1e6, 2), "\n")
