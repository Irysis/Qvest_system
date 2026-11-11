## 날짜 격자만 비교한다(개수 · 날짜) — 같은 엔진의 기저 캐시 두 판(레인 시드 · 셀 엔진 실행)
suppressMessages({ library(data.table) })
args <- commandArgs(trailingOnly = TRUE)
a <- as.data.table(readRDS(args[1])); b <- as.data.table(readRDS(args[2]))
for (x in list(a, b)) {
  x[, Date := as.Date(Date)]
  d <- sort(unique(x$Date))
  cat(sprintf("rows %d · 날짜 %d · 처음 %s · 둘째 %s · 끝 %s · 출처 속성 %s\n", nrow(x), length(d), format(d[1]), format(d[2]), format(d[length(d)]),
              paste(as.character(attr(x, "rf_base_seeded_from")), collapse = "")))
}
da <- sort(unique(as.Date(a$Date))); db <- sort(unique(as.Date(b$Date)))
cat("공통 날짜 수:", length(intersect(as.character(da), as.character(db))), " / A", length(da), " B", length(db), "\n")
