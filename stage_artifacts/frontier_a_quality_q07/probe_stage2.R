ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts); library(arrow) })

cat("===== sleeve active (qual_caution_active.rds) =====\n")
sl <- readRDS("stage_artifacts/frontier_a_quality_q07/qual_caution_active.rds")
cat("class:", paste(class(sl), collapse=","), "\n")
str(sl)
if (is.data.frame(sl) || is.data.table(sl)) { cat("names:", paste(names(sl), collapse=" | "), "\n"); print(head(sl)); print(tail(sl)) }
if (inherits(sl, "xts")) { cat("colnames:", paste(colnames(sl), collapse=" | "), "\n"); print(head(sl)); print(tail(sl)) }
if (is.numeric(sl) && !is.null(names(sl))) { cat("named numeric length", length(sl), "\n"); print(head(sl)); print(tail(sl)) }

cat("\n===== book variant_returns_xts.rds =====\n")
bk <- readRDS("04_Research/pg2_forensics/intermediate/variant_returns_xts.rds")
cat("class:", paste(class(bk), collapse=","), "\n")
if (inherits(bk, "xts")) {
  cat("colnames:\n"); print(colnames(bk))
  cat("index range:", format(range(index(bk))), "\n")
  cat("nrow:", nrow(bk), "\n")
  print(head(bk[,1:min(4,ncol(bk))]))
} else {
  str(bk)
}

cat("\n===== benchmark.parquet =====\n")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
cat("names:", paste(names(bm), collapse=" | "), "\n")
print(head(bm)); print(tail(bm))
