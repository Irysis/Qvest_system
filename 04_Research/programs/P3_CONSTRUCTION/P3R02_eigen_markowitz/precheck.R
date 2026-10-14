## P3R02 측정 직전 대조(격리 교차 점검 ② R6 ④) — 사양 · 어댑터 · 운영 경로 md5 · 카탈로그 엔트리 · quadprog 판이 사전등록 값과 같아야 측정한다.
##   하나라도 다르면 종료 코드 1(measure.sh 가 측정하지 않는다). 데이터 지문(RAWDATA · 벤치 캐시 mtime · 크기)을 함께 기록한다(판본 대조 record ⑥).
## 실행: Rscript precheck.R   (산출 = results/precheck.json — 성과 수치 없음)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
md5 <- function(f) unname(as.character(tools::md5sum(f)))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz")
PR <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/prereg.json")
if (!file.exists(PR)) { cat("[precheck] 사전등록 없음 — 측정하지 않는다\n"); quit(status = 1L) }
pre <- fromJSON(PR, simplifyVector = FALSE)
bad <- character(0)
if (!identical(pre$status, "registered")) bad <- c(bad, "사전등록 status ≠ registered")
for (c in pre$cells) if (!identical(md5(file.path(ROOT, c$path)), c$md5)) bad <- c(bad, paste("사양 md5:", c$code))
for (f in pre$operational_pins$files) if (!identical(md5(file.path(ROOT, f$path)), f$md5)) bad <- c(bad, paste("운영 경로 md5:", f$path))
wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
ent <- Filter(function(z) identical(z$catalog_id, "paper:EigenCleanMarkowitz"), wc)
pin <- pre$operational_pins$catalog_entry
if (!length(ent) || !identical(ent[[1]]$status, pin$status) || !identical(ent[[1]]$resolver, pin$resolver)) bad <- c(bad, "카탈로그 엔트리(상태 · resolver)")
if (!identical(as.character(utils::packageVersion("quadprog")), pre$operational_pins$quadprog)) bad <- c(bad, "quadprog 판")
if (!identical(R.version.string, pre$operational_pins$r_version)) bad <- c(bad, "R 판")
for (f in pre$evaluation$files %||% list()) if (!identical(md5(file.path(ROOT, f$path)), f$md5)) bad <- c(bad, paste("평가 경로 md5:", f$path))
fp <- lapply(c("RAWDATA.parquet", "benchmark.parquet"), function(n) { p <- file.path(ROOT, ".cache", n); i <- file.info(p)
  list(file = n, exists = file.exists(p), size = if (file.exists(p)) i$size else NA, mtime = if (file.exists(p)) format(i$mtime, "%Y-%m-%dT%H:%M:%S%z") else NA) })
out <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = md5(PR), ok = !length(bad), mismatches = bad, data_fingerprint = fp,
            git_head = tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_))
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), file.path(RD, "results", "precheck.json"), useBytes = TRUE)
if (length(bad)) { cat("[precheck] 불일치 — 측정하지 않는다:\n", paste0("  · ", bad, collapse = "\n"), "\n"); quit(status = 1L) }
cat(sprintf("[precheck] 통과 — 사양 %d · 운영 경로 %d · 카탈로그 엔트리 · quadprog %s · 데이터 지문 기록\n",
            length(pre$cells), length(pre$operational_pins$files), pre$operational_pins$quadprog))
