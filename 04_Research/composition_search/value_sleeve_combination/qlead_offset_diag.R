# Q-Lead 진단 — period_returns_layer5.csv realized_ym 1개월 오프셋 주장 독립 확인
suppressPackageStartupMessages({ library(data.table); library(arrow) })
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
M <- as.data.table(readRDS(file.path(PROJECT_ROOT,
  "04_Research/composition_search/value_sleeve_combination/aligned_series.rds")))

# aligned_series: realized_ym 기준 join (book label m <-> bench calendar m)
c0 <- cor(M$book_ret, M$bench_ret)
# shift: book label m+1 <-> bench m  (= book 라벨이 실제 m-1월이라는 가설)
n <- nrow(M)
c1 <- cor(M$book_ret[2:n], M$bench_ret[1:(n-1)])
cat(sprintf("cor(book_m, bench_m)      = %+.4f\n", c0))
cat(sprintf("cor(book_{m+1}, bench_m)  = %+.4f\n", c1))

# value sleeve도 동일 shift 대조 (value는 달력월 기준 빌드)
v0 <- cor(M$value_ret, M$book_ret)
v1 <- cor(M$value_ret[1:(n-1)], M$book_ret[2:n])
cat(sprintf("cor(value_m, book_m)      = %+.4f  (Stage1 사용치)\n", v0))
cat(sprintf("cor(value_m, book_{m+1})  = %+.4f  (정렬 보정 시)\n", v1))

# value <-> bench (둘 다 달력월이면 shift 없이 양의 상관이어야 정상)
vb0 <- cor(M$value_ret, M$bench_ret)
vb1 <- cor(M$value_ret[2:n], M$bench_ret[1:(n-1)])
cat(sprintf("cor(value_m, bench_m)     = %+.4f (동월 — 정상이면 양수 큼)\n", vb0))
cat(sprintf("cor(value_{m+1}, bench_m) = %+.4f (어긋난 조합 — 정상이면 작음)\n", vb1))

# Lehman/COVID 이벤트 행
ev <- M[realized_ym %in% c("2008-09","2008-10","2008-11","2020-02","2020-03","2020-04")]
print(ev[, .(realized_ym, book_ret = round(book_ret,4), value_ret = round(value_ret,4),
             bench_ret = round(bench_ret,4))])
cat("DONE\n")
