#!/usr/bin/env Rscript
#==============================================================================
# test_rf_notify_block_asof.R — 경계 백필의 **지난 블록** 텔레그램이 그 블록 보고인가 (B5FIX · 2026-09-26)
#
# 결함: rf_auto_notify(kind="block") 은 표제·'배운 것'·순위 블록을 표의 **마지막 칸**에서 읽는다(tab[n == max(tab$n)]). 정상 경로는
#   n = 방금 쓴 attempts_used 라 같은 뜻이지만, 경계 백필이 7308 B5(n=31)의 보고를 B7(n=36) 측정 뒤에 보내면 B7 보고가 나간다.
# 수리(rf_auto_notify.R): kind=block 이고 n < 표의 최대 n 이면 표를 n 까지로 자르고 위치도 n · delayed=TRUE 면 표제·상황 줄에 지연 표기.
#   A1 [수리] n=B5 마지막 칸 · delayed → 표제 = '무인 블록 완료(지연 발송 · 경계 백필) — 리스크오버레이' · 'n/max' = B5 시점 ·
#      '배운 것' = B5 L-code 기전(표식 ALPHA) · B7 기전(OMEGA) 없음 · 상황 줄 '지연 발송'
#   A2 [양성 대조] n=최대(B7) · delayed 없음 → 표제에 지연 없음 · B7 L-code 기전(OMEGA) · ALPHA 없음(정상 경로)
#   A3 [정상 경로 비트 동일 — 계기] 정상 경로 출력에 이 수리가 넣는 문자열(지연 발송)이 없다
# 실물 rf_auto_notify.R · telegram_notify.R(QVEST_TG_DRY_RUN=1 — 발송 0 · 샌드박스엔 .env 없음) · 샌드박스 원장.
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_notify_block_asof.R   (약 30초)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
cat(sprintf("ROOT(코드) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- normalizePath(tempdir(), winslash = "/")
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)
BID <- "T_B5BF_asof"
S <- file.path(TMP, sprintf("b5asof_%d", Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "02_Infrastructure/telegram", "06_Registry", ".cache/rf_parallel",
            "stage_artifacts/l_code/reinforcement", "stage_artifacts/replication"))
  dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
for (f in c("rf_auto_notify.R", "rf_perf_summary.R", "rf_block_insights.R")) file.copy(file.path(ROOT, "02_Infrastructure/ops", f), file.path(S, "02_Infrastructure/ops"))
file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
file.copy(list.files(file.path(ROOT, "02_Infrastructure/telegram"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/telegram"))
for (f in c("reinforce_program.json", "weight_catalog.json")) file.copy(file.path(ROOT, "06_Registry", f), file.path(S, "06_Registry"))
writeLines(toJSON(list(schema = "overlay_catalog_v1", arms = list()), auto_unbox = TRUE), file.path(S, "06_Registry/overlay_catalog.json"))
att <- function(n, code) {
  sp <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, BID))
  writeLines(toJSON(list(code = code, block = sub("_.*$", "", code), factors = list(list(kind = "db", id = "F0")),
                         weighting = list(kind = "ew"), universe = list(kind = "k200_kq150")), auto_unbox = TRUE), sp)
  list(n = as.integer(n), cell_code = code, grade = "C", idea = code, opened_at = "2026-09-25T22:00:00+0900",
       essence = list(cell_code = code, block = sub("_.*$", "", code), port_t = 0.5 + n / 100, calmar = 0.2 + n / 1000, cagr = 0.1,
                      mdd = 0.4, net_sharpe = 0.5, oos_retention = 0.5, spec = sp))
}
codes <- c(sprintf("B1_%d", 1:5), sprintf("B5_%d", 16:20), sprintf("B7_%d", 37:41))
E <- list(base_id = BID, status = "active", base_grade = "C", max_attempts = 44L, attempts_used = 15L, paper_key = "t", engine_path = "",
          base_artifacts = "", block_order = list("B1", "B5", "B7", "B4"), attempts = lapply(seq_along(codes), function(k) att(k, codes[k])))
writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(E)), auto_unbox = TRUE,
                  pretty = TRUE, null = "null", digits = 6), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
lc <- function(blk, mark) writeLines(toJSON(list(l_code = sprintf("L-RF-ASOF-%s", blk), lesson_text = "stub",
  mechanism = sprintf("%s_%s 기전 표식 %s.", blk, if (blk == "B5") "16" else "37", mark),
  next_block_actions = list(list(action = sprintf("처방 %s", mark), why = "stub", expect = "stub"))), auto_unbox = TRUE, pretty = TRUE),
  file.path(S, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", BID, blk)))
lc("B5", "ALPHA"); lc("B7", "OMEGA")
drv <- file.path(S, "drv.R")
writeLines(c('a <- commandArgs(TRUE); n <- as.integer(a[1]); dl <- identical(a[2], "1")',
             'suppressMessages(source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/ops/rf_auto_notify.R")))',
             'r <- if (dl) rf_auto_notify("T_B5BF_asof", n, kind = "block", delayed = TRUE) else rf_auto_notify("T_B5BF_asof", n, kind = "block")',
             'cat("\\nRESULT=", isTRUE(r), "\\n", sep = "")'), drv)
run <- function(n, delayed) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_TG_DRY_RUN"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = EMPTY_RENV, QVEST_TG_DRY_RUN = "1")
  owd <- setwd(S); on.exit(setwd(owd), add = TRUE)
  paste(suppressWarnings(system2("Rscript", c("--no-environ", shQuote(drv), n, if (delayed) "1" else "0"), stdout = TRUE, stderr = TRUE)), collapse = "\n")
}
first_msg <- function(o) { k <- regexpr("=== dry_run output", o, fixed = TRUE); if (k < 0) "" else substr(o, k, nchar(o)) }
title_of <- function(o) { m <- strsplit(first_msg(o), "\n")[[1]]; t <- grep("1계층·강화", m, value = TRUE); if (length(t)) t[1] else "" }

cat("\n=== A. 지난 블록 보고 = 그 블록 시점 표 ===\n")
o1 <- run(10L, TRUE); t1 <- title_of(o1); m1 <- first_msg(o1)
chk(grepl("RESULT=TRUE", o1, fixed = TRUE) && nzchar(m1), "A0 드라이런 본문 생성(발송 0)", substr(o1, max(1, nchar(o1) - 400), nchar(o1)))
chk(grepl("무인 블록 완료(지연 발송 · 경계 백필)", t1, fixed = TRUE) && grepl("리스크오버레이", t1, fixed = TRUE) && grepl("10/44", t1, fixed = TRUE),
    "A1a 표제 = 지연 표기 · B5(리스크오버레이) · 위치 10/44", t1)
chk(grepl("ALPHA", m1, fixed = TRUE) && !grepl("OMEGA", m1, fixed = TRUE), "A1b '배운 것' = B5 L-code 기전(ALPHA) · B7(OMEGA) 없음")
chk(grepl("지연 발송 — 이 블록의 경계 처리가 누락돼", m1, fixed = TRUE), "A1c 상황 줄 '지연 발송' 표기")
o2 <- run(15L, FALSE); t2 <- title_of(o2); m2 <- first_msg(o2)
chk(nzchar(t2) && !grepl("지연", t2, fixed = TRUE) && grepl("15/44", t2, fixed = TRUE) && grepl("B7", t2, fixed = TRUE),
    "A2a [양성] 정상 경로(n=최대) 표제 = 지연 없음 · B7 · 15/44", t2)
chk(grepl("OMEGA", m2, fixed = TRUE) && !grepl("ALPHA", m2, fixed = TRUE), "A2b [양성] 정상 경로 '배운 것' = B7 기전(OMEGA)")
chk(!grepl("지연 발송", m2, fixed = TRUE), "A3 정상 경로 본문에 지연 문자열 0(이 수리는 정상 경로를 바꾸지 않는다)")
o4 <- run(10L, FALSE); t4 <- title_of(o4); m4 <- first_msg(o4)
chk(grepl("B7", t4, fixed = TRUE) && grepl("OMEGA", m4, fixed = TRUE) && !grepl("지연", t4, fixed = TRUE),
    "A4 delayed 없이 n < 최대 → 구판처럼 마지막 블록(B7) 보고 — 기존 호출자(n 자리표시 · test_rf_notify_rank_distinct 의 n=5)는 불변", t4)
unlink(S, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_notify_block_asof","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
