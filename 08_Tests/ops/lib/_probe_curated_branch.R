# 빈 curated 분기만 떼어 실행 — 즉사하지 않고 경보를 남기는가.
PROJECT_ROOT <- commandArgs(trailingOnly = TRUE)[1]
log_line <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")
source_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "config", "paper_recharge_sources.csv")
curated_sources <- data.frame(provider = character(0), title = character(0))

src <- readLines("02_Infrastructure/tools/paper_recharge_daily.R", warn = FALSE)
i <- grep("^if \\(nrow\\(curated_sources\\) == 0L\\) \\{", src)[1]
if (is.na(i)) { cat("  ★분기 못 찾음\n"); quit(status = 1) }
j <- i
while (j <= length(src) && !identical(trimws(src[j]), "}")) j <- j + 1
blk <- paste(src[i:j], collapse = "\n")
cat("  추출 줄수:", j - i + 1, "\n")

res <- tryCatch({ eval(parse(text = blk)); "정상 진행(즉사 안 함)" },
                error = function(e) paste("★즉사:", conditionMessage(e)))
cat("  결과:", res, "\n")
cat("  nrow(curated_sources) =", nrow(curated_sources), "\n")
n <- length(list.files(file.path(PROJECT_ROOT, ".cache", "scheduler_alerts"),
                       pattern = "curated_sources_missing"))
cat("  경보 마커:", n, "건\n")
