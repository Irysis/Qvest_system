# install_r46_packages.R — R 4.6.2 사용자 라이브러리(win-library/4.6)에 4.5 사용자 라이브러리 패키지 전부 재설치 · 2026-11-08
#   계획서 = 같은 폴더 PLAN.md · RDCOMClient(CRAN 4.6 바이너리 없음 · 코드 사용처 0)는 뺀다.
#   ★도구 세션 밖에서(일회용 예약 작업) — %LOCALAPPDATA% 쓰기 가상화. 실행기 = install_r46_packages.ps1
args <- commandArgs(trailingOnly = TRUE)
out_dir <- args[1]
log <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n", file = file.path(out_dir, "r46_packages.result.txt"), append = TRUE)
stopifnot(getRversion() >= "4.6.0")
lib46 <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", "4.6")
lib45 <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", "4.5")
dir.create(lib46, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib46, .Library))
ip45 <- installed.packages(lib.loc = lib45, priority = NA_character_)   # 사용자 라이브러리 · base/recommended 제외
want <- setdiff(rownames(ip45), c("RDCOMClient"))
log("start R", R.version.string, "| lib46", lib46, "| want", length(want))
repos <- c(CRAN = "https://cloud.r-project.org")
options(repos = repos, timeout = 600, install.packages.compile.from.source = "never")
have <- rownames(installed.packages(lib.loc = lib46))
todo <- setdiff(want, have)
if (length(todo)) {
  utils::install.packages(todo, lib = lib46, type = "binary", dependencies = c("Depends", "Imports", "LinkingTo"), quiet = TRUE)
}
ip46 <- installed.packages(lib.loc = c(lib46, .Library))
missing <- setdiff(want, rownames(ip46))
log("installed in lib46:", nrow(installed.packages(lib.loc = lib46)), "| missing:", length(missing), if (length(missing)) paste(missing, collapse = ",") else "")
key <- c("data.table", "arrow", "readxl", "openxlsx", "jsonlite", "PerformanceAnalytics", "xts", "zoo", "Rcpp", "bbdetection",
         "quadprog", "glmnet", "xgboost", "ranger", "fixest", "ggplot2", "dplyr", "httr", "curl", "lubridate")
for (k in key) {
  r <- tryCatch({ suppressPackageStartupMessages(library(k, character.only = TRUE, lib.loc = c(lib46, .Library))); as.character(packageVersion(k, lib.loc = c(lib46, .Library))) },
                error = function(e) paste("LOAD_FAIL", conditionMessage(e)))
  log("  ", k, r)
}
cpp <- tryCatch({ Rcpp::cppFunction("int qv_add(int a, int b) { return a + b; }"); qv_add(2L, 3L) }, error = function(e) paste("CPP_FAIL", conditionMessage(e)))
log("Rcpp compile (Rtools45):", cpp)
log("done")
