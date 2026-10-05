#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b5_design_priority.R — 기전 경로의 다음 블록 설계 **저장 관문** 양방향 검사 (B5FIX · 2026-09-26)
#
# 실사고 09-25 (RP_20260924_052517_7308_adapted_rulefast): B5 설계 레인이 8칸을 검증·기록(원장 b5_design.rounds r1 · 파일
#   source=b5_design_lane)한 뒤 같은 tick 의 기전 백필(B6)이 lcm_merge 로 같은 파일을 5칸으로 덮었다(SKILL §0.1 B5 행 우선순위 역전).
# 판정 정본 = 02_Infrastructure/ops/rf_lcode_mechanism_lib.R::lcm_design_guard · 저장 = lcm_merge.
#   P1 [사고 재현] 레인이 실제 writer(rf_b5_design_lib.R::b5_verify_and_write)로 8칸을 쓴 뒤 기전 B5 5칸 → 저장 거부 · 파일 sha 불변 ·
#      백업(.cache/rf_b5_design/<BID>/mechanism_deferred/) · jlog block_design_deferred(reason=b5_design_lane_priority) · 기전·처방은 병합
#   P2 [사고 뒤 상태] 파일은 이미 기전 5칸(source 없음) · 원장 레인 라운드만 → 거부(증거 = 원장 라운드 · 파일 source 에 기대지 않는다)
#   P3 [기록 직전 창] 파일 source=b5_design_lane · 원장 라운드 없음 → 거부(증거 = 파일 source)
#   P4 [양성 대조] 레인 증거 없음 → 저장(block_design_saved · 파일 = 기전 설계)
#   P5 [폴백 라운드] 원장 라운드 fallback=true(n_cells 0)만 → 저장(레인이 설계를 안 냈다)
#   P6 [사후 설계 금지 일반화] B2 에 시도가 있으면 기전의 B2 설계 거부 + 백업(.cache/rf_lcode_mech/deferred) · 시도가 없으면 저장
#   P7 [반대 방향 불변] 기전 설계 파일 위에 레인 round 1 → 레인이 백업(<BID>_B5.mech.json)하고 덮는다(기존 동작)
#   P8 [원장 판독 불가] 기존 파일이 있으면 보존(거부) · 없으면 저장
#   M1~M4 [돌연변이] 레인 판정 삭제 → P1 red · 원장 증거 삭제 → P2 red · 사후 설계 일반화 삭제 → P6 red · 백업 삭제 → P1 백업 red
# 합성 카탈로그(overlay_catalog.json 사본 아님 — arm 상태가 바뀌어도 검사가 흔들리지 않게) · 자식 Rscript 는 R_ENVIRON_USER=빈 파일 ·
# QM_ROOT/QVEST_RF_ROOT = 샌드박스 · 운영 원장·로그·설계 디렉터리 전후 md5 대조.
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_b5_design_priority.R   (약 1분)
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
# ★운영 무접촉은 **이 검사의 표식**으로 잰다 — 운영 러너는 이 검사 도중에도 원장·로그를 정상적으로 쓴다(전후 md5 는 오탐).
#   검사 entry id(T_B5PRIO_entry)와 합성 arm 접두(tstarm_)가 운영 원장·로그 꼬리·설계 디렉터리에 나타나면 누출이다.
OPS <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
LOG_OPS <- file.path(OPS, ".cache/reinforce_auto_log.jsonl")
LOG_N0 <- if (file.exists(LOG_OPS)) length(readLines(LOG_OPS, warn = FALSE)) else 0L
leak <- function() {
  hits <- character(0)
  l1 <- file.path(OPS, "06_Registry/reinforce_ledger_l1.json")
  if (file.exists(l1) && any(grepl("T_B5PRIO_entry", readLines(l1, warn = FALSE), fixed = TRUE))) hits <- c(hits, "ledger")
  if (file.exists(LOG_OPS)) { ll <- readLines(LOG_OPS, warn = FALSE); new <- if (length(ll) > LOG_N0) ll[(LOG_N0 + 1L):length(ll)] else character(0)
    if (any(grepl("T_B5PRIO_entry|tstarm_", new))) hits <- c(hits, "log") }
  if (length(list.files(file.path(OPS, ".cache/rf_block_design"), pattern = "^T_B5PRIO"))) hits <- c(hits, "rf_block_design")
  if (dir.exists(file.path(OPS, ".cache/rf_b5_design/T_B5PRIO_entry"))) hits <- c(hits, "rf_b5_design")
  if (length(list.files(file.path(OPS, ".cache/rf_lcode_mech/deferred"), pattern = "^T_B5PRIO"))) hits <- c(hits, "rf_lcode_mech")
  if (length(list.files(file.path(OPS, "stage_artifacts/l_code/reinforcement"), pattern = "T_B5PRIO"))) hits <- c(hits, "l_code")
  hits
}

BID <- "T_B5PRIO_entry"
ARMS <- sprintf("tstarm_%s", letters[1:13])            # a~h = 레인 · i~m = 기전
mk_sbx <- function(tag, code_lib = NULL) {
  S <- file.path(TMP, sprintf("b5prio_%s_%d", tag, Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
  for (d in c("02_Infrastructure/reinforcement", "02_Infrastructure/ops", "02_Infrastructure/portfolio", "06_Registry", "04_Research",
              "stage_artifacts/l_code/reinforcement", ".cache/rf_lcode_mech", ".cache/rf_block_design"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  cp <- function(from, to) invisible(file.copy(from, file.path(S, to), overwrite = TRUE))
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/reinforcement")
  for (f in c("rf_lcode_mechanism_lib.R", "rf_b5_design_lib.R", "rf_b1_design_lib.R", "rf_claim.R", "rf_block_lcode.R"))
    cp(file.path(ROOT, "02_Infrastructure/ops", f), "02_Infrastructure/ops")
  cp(list.files(file.path(ROOT, "02_Infrastructure/portfolio"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/portfolio")
  if (!is.null(code_lib)) file.copy(code_lib, file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R"), overwrite = TRUE)
  for (f in c("reinforce_program.json", "weight_catalog.json")) cp(file.path(ROOT, "06_Registry", f), "06_Registry")
  arms <- lapply(seq_along(ARMS), function(i) list(id = ARMS[i], kind = sprintf("tstkind_%s", letters[i]), family = "test",
                                                     basis = "synthetic", status = "active"))
  writeLines(toJSON(list(schema = "overlay_catalog_v1", arms = arms), auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/overlay_catalog.json"))
  cfg <- list(enabled = TRUE, lcode_mechanism = list(enabled = TRUE),
              b5_design = list(enabled = TRUE, max_cells = 8L, min_cells = 3L, max_new_arms = 3L, max_layers = 3L, prior_entries = 12L,
                               guards = list(max_redesign_rounds = 1L, daily_arm_cap = 6L, stagnation_window = 2L, max_active_generated = 40L)))
  writeLines(toJSON(cfg, auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
  S
}
att <- function(n, code, measured = TRUE) {
  a <- list(n = as.integer(n), cell_code = code, idea = sprintf("[무인 병렬 %s] stub", code), keyword_axis = "x", grade = if (measured) "C" else NULL)
  if (measured) a$essence <- list(cell_code = code, block = sub("_.*$", "", code), port_t = 1, calmar = 0.3, cagr = 0.1, mdd = 0.4)
  a
}
mk_ledger <- function(S, attempts, b5_design = NULL) {
  e <- list(base_id = BID, status = "active", base_grade = "C", max_attempts = 44L, attempts_used = length(attempts),
            paper_key = "t", engine_path = "", base_artifacts = "", opened_at = "2026-09-24T05:43:52+0900",
            block_order = list("B1", "B2", "B3", "B6", "B5", "B7", "B4"), attempts = attempts)
  if (!is.null(b5_design)) e$b5_design <- b5_design
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(e),
                         combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = ""),
                    auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
}
pre_b5_attempts <- function() { k <- 0L; out <- list()
  for (cd in c(sprintf("B1_%d", 1:5), sprintf("B2_%d", 6:10), sprintf("B3_%d", 11:15), sprintf("B6_%d", c(32, 33, 34, 36, 42)))) {
    k <- k + 1L; out[[k]] <- att(k, cd) }
  out }
mk_lcode <- function(S, blk) writeLines(toJSON(list(l_code = sprintf("L-RF-TEST-%s", blk), lesson_text = sprintf("[%s] stub", blk),
                                                    mechanism = "", next_probes = list("a", "b")), auto_unbox = TRUE, pretty = TRUE),
                                        file.path(S, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", BID, blk)))
mech_json <- function(S, from_blk, next_blk, picks) {
  p <- file.path(S, ".cache/rf_lcode_mech", sprintf("%s_%s.mechanism.json", BID, from_blk))
  cells <- lapply(seq_along(picks), function(i) { pk <- picks[[i]]
    if (length(pk) > 1L) list(picks = as.list(pk), label = sprintf("mech %d", i), why = "stub") else list(pick = pk, label = sprintf("mech %d", i), why = "stub") })
  writeLines(toJSON(list(mechanism = sprintf("%s_%s 셀이 갈렸다 — 기전 stub.", from_blk, if (identical(from_blk, "B6")) "32" else "6"),
                         next_block_actions = list(list(action = "다음 블록에서 stub 처치", why = "stub", expect = "stub")),
                         avoid = list(), next_block_design = list(block = next_blk, cells = cells), confidence = "low"),
                    auto_unbox = TRUE, pretty = TRUE), p)
  p
}
lane_out <- function(S) {
  p <- file.path(S, "lane_design_r1.json")
  cells <- list(list(picks = list(ARMS[1]), label = "L1", why = "lane"), list(picks = list(ARMS[2]), label = "L2", why = "lane"),
                list(picks = list(ARMS[3]), label = "L3", why = "lane"), list(picks = list(ARMS[4]), label = "L4", why = "lane"),
                list(picks = list(ARMS[1], ARMS[2]), label = "L5", why = "lane"), list(picks = list(ARMS[1], ARMS[3]), label = "L6", why = "lane"),
                list(picks = list(ARMS[2], ARMS[3]), label = "L7", why = "lane"), list(picks = list(ARMS[1], ARMS[4]), label = "L8 음성 대조", why = "lane"))
  writeLines(toJSON(list(schema = "rf_b5_design_v1", base_id = BID, round = 1L, rationale = "stub", cells = cells, new_arms = list()),
                    auto_unbox = TRUE, pretty = TRUE), p)
  p
}
MECH_B5 <- list(ARMS[9], ARMS[10], ARMS[11], ARMS[12], c(ARMS[13], ARMS[3]))
rscript <- function(S, args) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_ROOT", "QVEST_RP_JLOG", "QVEST_RF_CONFIG", "QVEST_B5_CODE_ROOT"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.unsetenv(c("QVEST_RP_JLOG", "QVEST_RF_CONFIG", "QVEST_B5_CODE_ROOT"))
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = EMPTY_RENV, QVEST_RF_ROOT = S)
  paste(suppressWarnings(system2("Rscript", c("--no-environ", args), stdout = TRUE, stderr = TRUE)), collapse = "\n")
}
merge_run <- function(S, from_blk, mp) rscript(S, c(shQuote(file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")), "merge", BID, from_blk, shQuote(mp)))
lane_verify <- function(S) rscript(S, c(shQuote(file.path(S, "02_Infrastructure/ops/rf_b5_design_lib.R")), "verify", BID, shQuote(lane_out(S)), "1", "1", "-", "-"))
fp_of <- function(S, blk) file.path(S, ".cache/rf_block_design", sprintf("%s_%s.json", substr(BID, 1, 50), blk))
evs <- function(S) { p <- file.path(S, ".cache/reinforce_auto_log.jsonl"); if (!file.exists(p)) return(list())
  Filter(Negate(is.null), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL))) }
ev_of <- function(S, name) Filter(function(r) identical(as.character(r$event %||% ""), name), evs(S))
design <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
md5 <- function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent"
lcode_mech <- function(S, blk) as.character(design(file.path(S, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", BID, blk)))$mechanism %||% "")

run_suite <- function(code_lib = NULL, label = "설치본", quiet = FALSE) {
  res <- list()
  # ── P1 사고 재현 ──
  S <- mk_sbx(paste0("p1", label), code_lib); mk_ledger(S, pre_b5_attempts()); mk_lcode(S, "B6")
  o0 <- lane_verify(S); f <- fp_of(S, "B5"); d0 <- design(f); m0 <- md5(f)
  res$lane_ok <- identical(d0$source, "b5_design_lane") && length(d0$cells) == 8L
  if (!quiet) chk(res$lane_ok, sprintf("[%s] P1-0 레인 writer(b5_verify_and_write) 8칸 · source=b5_design_lane", label), substr(o0, max(1, nchar(o0) - 400), nchar(o0)))
  o1 <- merge_run(S, "B6", mech_json(S, "B6", "B5", MECH_B5))
  d1 <- design(f); de <- ev_of(S, "block_design_deferred")
  bk <- if (length(de)) as.character(de[[length(de)]]$backup %||% "") else ""
  res$p1_kept <- identical(md5(f), m0) && identical(d1$source, "b5_design_lane") && length(d1$cells) == 8L
  res$p1_event <- length(de) == 1L && identical(as.character(de[[1]]$reason), "b5_design_lane_priority")
  res$p1_backup <- nzchar(bk) && file.exists(bk) && grepl("/mechanism_deferred/", bk, fixed = TRUE) &&
    length(design(bk)$design$cells) == 5L && identical(design(bk)$reason, "b5_design_lane_priority")
  res$p1_merged <- grepl("B6_32", lcode_mech(S, "B6"), fixed = TRUE) && !length(ev_of(S, "block_design_saved"))
  if (!quiet) {
    chk(res$p1_kept, sprintf("[%s] P1a 레인 설계 파일 sha 불변(8칸 · source 유지) — 기전 5칸이 덮지 못한다", label),
        sprintf("cells=%s source=%s | %s", length(d1$cells), d1$source %||% "NULL", substr(o1, max(1, nchar(o1) - 400), nchar(o1))))
    chk(res$p1_event, sprintf("[%s] P1b jlog block_design_deferred 1건(reason=b5_design_lane_priority)", label), sprintf("n=%d", length(de)))
    chk(res$p1_backup, sprintf("[%s] P1c 기전 설계 백업(레인 디렉터리 mechanism_deferred/ · 5칸 · 무성 폐기 아님)", label), bk)
    chk(res$p1_merged, sprintf("[%s] P1d 기전·처방은 L-code 에 병합(설계만 거부) · block_design_saved 0건", label))
  }
  # ── P2 사고 뒤 상태 — 파일은 기전 5칸 · 원장 레인 라운드만 ──
  S2 <- mk_sbx(paste0("p2", label), code_lib)
  mk_ledger(S2, pre_b5_attempts(), b5_design = list(rounds = list(list(round = 1L, source = "b5_design_lane", n_cells = 8L, fallback = FALSE))))
  mk_lcode(S2, "B6"); f2 <- fp_of(S2, "B5")
  writeLines(toJSON(list(block = "B5", cells = list(list(pick = ARMS[9], label = "old mech"))), auto_unbox = TRUE), f2); m2 <- md5(f2)
  merge_run(S2, "B6", mech_json(S2, "B6", "B5", MECH_B5))
  res$p2 <- identical(md5(f2), m2) && length(ev_of(S2, "block_design_deferred")) == 1L
  if (!quiet) chk(res$p2, sprintf("[%s] P2 원장 레인 라운드만(파일 source 없음) → 거부 · 파일 불변", label))
  # ── P3 기록 직전 창 — 파일 source 만 ──
  S3 <- mk_sbx(paste0("p3", label), code_lib); mk_ledger(S3, pre_b5_attempts()); mk_lcode(S3, "B6"); f3 <- fp_of(S3, "B5")
  writeLines(toJSON(list(block = "B5", source = "b5_design_lane", round = 1L, cells = list(list(picks = list(ARMS[1]), label = "L1"))),
                    auto_unbox = TRUE), f3); m3 <- md5(f3)
  merge_run(S3, "B6", mech_json(S3, "B6", "B5", MECH_B5))
  res$p3 <- identical(md5(f3), m3) && length(ev_of(S3, "block_design_deferred")) == 1L
  if (!quiet) chk(res$p3, sprintf("[%s] P3 파일 source=b5_design_lane · 원장 라운드 없음 → 거부 · 파일 불변", label))
  # ── P4 양성 대조 — 레인 증거 없음 ──
  S4 <- mk_sbx(paste0("p4", label), code_lib); mk_ledger(S4, pre_b5_attempts()); mk_lcode(S4, "B6")
  o4 <- merge_run(S4, "B6", mech_json(S4, "B6", "B5", MECH_B5)); d4 <- design(fp_of(S4, "B5"))
  res$p4 <- length(d4$cells) == 5L && length(ev_of(S4, "block_design_saved")) == 1L && !length(ev_of(S4, "block_design_deferred"))
  if (!quiet) chk(res$p4, sprintf("[%s] P4 [양성] 레인 증거 없음 → 기전 설계 저장(5칸 · block_design_saved)", label), substr(o4, max(1, nchar(o4) - 300), nchar(o4)))
  # ── P5 폴백 라운드만 ──
  S5 <- mk_sbx(paste0("p5", label), code_lib)
  mk_ledger(S5, pre_b5_attempts(), b5_design = list(rounds = list(list(round = 1L, n_cells = 0L, fallback = TRUE, fallback_reason = "stub"))))
  mk_lcode(S5, "B6"); merge_run(S5, "B6", mech_json(S5, "B6", "B5", MECH_B5))
  res$p5 <- length(design(fp_of(S5, "B5"))$cells) == 5L && length(ev_of(S5, "block_design_saved")) == 1L
  if (!quiet) chk(res$p5, sprintf("[%s] P5 폴백 라운드(fallback=true · n_cells 0)만 → 저장(레인이 설계를 안 냈다)", label))
  # ── P6 사후 설계 금지 일반화 (B2) ──
  ## B2 카탈로그 id 는 **샌드박스 안에서** 설계 검증과 같은 함수(rfbd_catalog)로 뽑는다 — 검사 프로세스에서 뽑으면 생성 어댑터
  ##   (methods/adapters/gen) 유무가 달라 샌드박스 검증이 모르는 id 를 고르게 된다(첫 판 실측).
  S6 <- mk_sbx(paste0("p6", label), code_lib)
  q6 <- file.path(S6, "q_b2ids.R")
  writeLines(c('suppressMessages(source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/reinforcement/rf_block_design.R")))',
               'x <- rfbd_catalog("B2", Sys.getenv("QM_ROOT")); cat("B2IDS=", paste(vapply(x, function(z) z$id, ""), collapse = "|"), "\\n", sep = "")'), q6)
  o6 <- rscript(S6, shQuote(q6)); ln6 <- grep("^B2IDS=", strsplit(o6, "\n")[[1]], value = TRUE)
  wc <- if (length(ln6)) strsplit(sub("^B2IDS=", "", trimws(ln6[1])), "|", fixed = TRUE)[[1]] else character(0)
  if (length(wc) < 2L) { ng(sprintf("[%s] P6 준비 실패 — 샌드박스 B2 카탈로그 판독 불가", label), substr(o6, 1, 300)); res$p6 <- FALSE } else {
    mk_ledger(S6, list(att(1, "B1_1"), att(2, "B1_2"), att(3, "B2_6", measured = FALSE))); mk_lcode(S6, "B1")
    f6 <- fp_of(S6, "B2"); m6 <- md5(f6)
    merge_run(S6, "B1", mech_json(S6, "B1", "B2", as.list(wc[1:2])))
    de6 <- ev_of(S6, "block_design_deferred"); bk6 <- if (length(de6)) as.character(de6[[1]]$backup %||% "") else ""
    S6b <- mk_sbx(paste0("p6b", label), code_lib); mk_ledger(S6b, list(att(1, "B1_1"), att(2, "B1_2"))); mk_lcode(S6b, "B1")
    merge_run(S6b, "B1", mech_json(S6b, "B1", "B2", as.list(wc[1:2])))
    res$p6 <- identical(md5(f6), m6) && length(de6) == 1L && identical(as.character(de6[[1]]$reason), "block_design_refused_post_measure") &&
      nzchar(bk6) && file.exists(bk6) && grepl("rf_lcode_mech/deferred", bk6, fixed = TRUE)
    res$p6b <- length(design(fp_of(S6b, "B2"))$cells) == 2L
    if (!quiet) {
      chk(res$p6, sprintf("[%s] P6a B2 시도가 이미 있으면 기전 B2 설계 거부(block_design_refused_post_measure) + 백업", label), bk6)
      chk(res$p6b, sprintf("[%s] P6b [양성] B2 시도가 없으면 저장", label))
    }
  }
  # ── P7 반대 방향 불변 — 레인이 기전 설계를 백업하고 덮는다 ──
  S7 <- mk_sbx(paste0("p7", label), code_lib); mk_ledger(S7, pre_b5_attempts()); f7 <- fp_of(S7, "B5")
  writeLines(toJSON(list(block = "B5", cells = list(list(pick = ARMS[9], label = "mech"), list(pick = ARMS[10], label = "mech2"),
                                                    list(pick = ARMS[11], label = "mech3"))), auto_unbox = TRUE), f7)
  lane_verify(S7); d7 <- design(f7)
  mb <- file.path(S7, ".cache/rf_b5_design", BID, sprintf("%s_B5.mech.json", substr(BID, 1, 50)))
  res$p7 <- identical(d7$source, "b5_design_lane") && length(d7$cells) == 8L && file.exists(mb) && length(design(mb)$cells) == 3L
  if (!quiet) chk(res$p7, sprintf("[%s] P7 반대 방향 불변 — 레인 round 1 이 기전 설계를 백업(.mech.json)하고 덮는다", label))
  # ── P8 원장 판독 불가 ──
  S8 <- mk_sbx(paste0("p8", label), code_lib); mk_lcode(S8, "B6"); f8 <- fp_of(S8, "B5")
  writeLines("{ broken", file.path(S8, "06_Registry/reinforce_ledger_l1.json"))
  writeLines(toJSON(list(block = "B5", cells = list(list(pick = ARMS[1], label = "x"))), auto_unbox = TRUE), f8); m8 <- md5(f8)
  merge_run(S8, "B6", mech_json(S8, "B6", "B5", MECH_B5))
  S8b <- mk_sbx(paste0("p8b", label), code_lib); mk_lcode(S8b, "B6"); writeLines("{ broken", file.path(S8b, "06_Registry/reinforce_ledger_l1.json"))
  merge_run(S8b, "B6", mech_json(S8b, "B6", "B5", MECH_B5))
  res$p8 <- identical(md5(f8), m8) && length(ev_of(S8, "block_design_deferred")) == 1L
  res$p8b <- length(design(fp_of(S8b, "B5"))$cells) == 5L
  if (!quiet) {
    chk(res$p8, sprintf("[%s] P8a 원장 판독 불가 + 기존 파일 → 보존(거부 · design_guard_ledger_unreadable)", label))
    chk(res$p8b, sprintf("[%s] P8b 원장 판독 불가 + 파일 없음 → 저장(덮을 것이 없다)", label))
  }
  unlink(c(S, S2, S3, S4, S5, S7, S8, S8b, if (exists("S6")) S6, if (exists("S6b")) S6b), recursive = TRUE, force = TRUE)
  res
}

cat("\n=== P. 저장 관문 — 설치본 ===\n")
R0 <- run_suite(NULL, "설치본")

cat("\n=== M. 돌연변이 — 관문이 실제로 가르는가 ===\n")
LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
mutant <- function(tag, from, to) {
  s <- readLines(LIB, warn = FALSE, encoding = "UTF-8"); hit <- grep(from, s, fixed = TRUE)
  if (length(hit) != 1L) return(NULL)
  s[hit] <- sub(from, to, s[hit], fixed = TRUE); p <- file.path(TMP, sprintf("mut_%s_%d.R", tag, Sys.getpid())); writeLines(s, p, useBytes = TRUE); p
}
m1 <- mutant("lane", 'if (!length(ev)) return(list(refuse = FALSE, code = "", evidence = "no_lane_round"))',
             'return(list(refuse = FALSE, code = "", evidence = "mutated"))')
if (is.null(m1)) ng("M1 돌연변이 적용 실패(레인 판정 줄 부재)") else {
  r <- run_suite(m1, "M1", quiet = TRUE); chk(!isTRUE(r$p1_kept), "M1 [돌연변이] 레인 판정 삭제 → 기전 5칸이 레인 설계를 덮는다 = P1a 가 잡는다") }
m2 <- mutant("ledger", 'if (length(rr)) ev <- c(ev,', 'if (FALSE) ev <- c(ev,')
if (is.null(m2)) ng("M2 돌연변이 적용 실패(원장 증거 줄 부재)") else {
  r <- run_suite(m2, "M2", quiet = TRUE); chk(!isTRUE(r$p2) && isTRUE(r$p3), "M2 [돌연변이] 원장 라운드 증거 삭제 → P2(사고 뒤 상태) red · P3(파일 source) 는 green = 증거 2종이 각자 일한다") }
m3 <- mutant("post", 'if (length(st)) return(list(refuse = TRUE, code = "block_design_refused_post_measure",',
             'if (FALSE) return(list(refuse = TRUE, code = "block_design_refused_post_measure",')
if (is.null(m3)) ng("M3 돌연변이 적용 실패(사후 설계 줄 부재)") else {
  r <- run_suite(m3, "M3", quiet = TRUE); chk(!isTRUE(r$p6), "M3 [돌연변이] 사후 설계 일반화 삭제 → 시도 있는 B2 설계가 덮인다 = P6a 가 잡는다") }
m4 <- mutant("backup", '.bk <- lcm_backup_deferred(ROOT, base_id, .nb, block_id, .nd, .dg, rfbd_path(ROOT, base_id, .nb))', '.bk <- ""')
if (is.null(m4)) ng("M4 돌연변이 적용 실패(백업 줄 부재)") else {
  r <- run_suite(m4, "M4", quiet = TRUE); chk(!isTRUE(r$p1_backup) && isTRUE(r$p1_kept), "M4 [돌연변이] 백업 삭제 → 무성 폐기 = P1c 가 잡는다(보존 자체는 유지)") }

cat("\n=== Z. 운영 무접촉 ===\n")
lk <- leak(); chk(!length(lk), "Z1 검사 표식(T_B5PRIO_entry · tstarm_)이 운영 원장·로그·설계·L-code 어디에도 없다", paste(lk, collapse = ","))
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_b5_design_priority","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
