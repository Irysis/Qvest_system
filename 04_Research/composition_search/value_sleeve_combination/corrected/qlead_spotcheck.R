# Q-Lead 스팟체크 — 보정 정렬 무결성
suppressPackageStartupMessages(library(data.table))
D <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/value_sleeve_combination/corrected"
M <- as.data.table(readRDS(file.path(D, "aligned_series_corrected.rds")))
cat("n_months:", nrow(M), "| cols:", paste(names(M), collapse=","), "\n")
cat(sprintf("cor(book, bench) = %+.4f  (보정 후 정상이면 ~+0.57)\n", cor(M$book_ret, M$bench_ret)))
cat(sprintf("cor(value, book) = %+.4f  (보정 후 ~+0.31)\n", cor(M$value_ret, M$book_ret)))
ev <- M[realized_ym %in% c("2008-10","2020-03")]
print(ev[, .(realized_ym, book_ret=round(book_ret,4), bench_ret=round(bench_ret,4))])
R <- fread(file.path(D, "results_corrected.csv"))
print(R)
