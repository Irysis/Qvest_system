## P2R03 측정 직전 대조 — 사양 · 운영 경로 md5 · 비중 카탈로그 엔트리(E3 lean:entropy) · 오버레이 카탈로그 arm 6종 · 패키지 · R 판 · 평가 경로 md5 ·
##   행동 카드 설정 사본 md5 가 사전등록 값과 같아야 측정한다. 대조 함수 = evaluate.R::p2_pin_mismatches(평가 시작부와 같은 함수).
##   하나라도 다르면 종료 코드 1(measure.sh 가 측정하지 않는다). 데이터 지문(fingerprint.sh — equality · record)을 함께 기록한다. 성과 수치 없음.
## 실행: Rscript precheck.R   (산출 = results/precheck.json)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
md5 <- function(f) unname(as.character(tools::md5sum(f)))
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay")
source(file.path(RD, "evaluate.R"))                                             # 도우미만(본 실행 블록은 sys.nframe 가드)
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json")
if (!file.exists(PR)) { cat("[precheck] 사전등록 없음 — 측정하지 않는다\n"); quit(status = 1L) }
pre <- fromJSON(PR, simplifyVector = FALSE)
bad <- c(if (!identical(pre$status, "registered")) "사전등록 status ≠ registered", p2_pin_mismatches(pre, ROOT))
out <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = md5(PR), ok = !length(bad), mismatches = bad,
            data_fingerprint = list(equality = p2_fingerprint(RD, "equality"), record = p2_fingerprint(RD, "record")),
            git_head = tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_))
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), file.path(RD, "results", "precheck.json"), useBytes = TRUE)
if (length(bad)) { cat("[precheck] 불일치 — 측정하지 않는다:\n", paste0("  · ", bad, collapse = "\n"), "\n"); quit(status = 1L) }
cat(sprintf("[precheck] 통과 — 사양 %d · 운영 경로 %d · 비중 카탈로그 %d · 오버레이 arm %d · 패키지 %d · 평가 경로 %d · 데이터 지문 기록\n",
            length(pre$cells), length(pre$operational_pins$files), length(pre$operational_pins$catalog_entries), length(pre$operational_pins$overlay_arms),
            length(pre$operational_pins$packages), length(pre$evaluation$files)))
