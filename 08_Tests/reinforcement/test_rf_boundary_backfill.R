#!/usr/bin/env Rscript
#==============================================================================
# test_rf_boundary_backfill.R — 블록 경계 처리 누락(7308 B5 사고) 재현·수리 양방향 검사 (B5FIX · 2026-09-26)
#
# 실물 러너(reinforce_auto_parallel.R) + 실물 기전 writer(rf_lcode_mechanism_lib.R merge) + 실물 B5 레인 writer(rf_b5_design_lib.R verify)를
# 샌드박스 root 에서 돌린다. 스텁 = 워커(합성 산출물) · G2(rf_overlay_adversary_run → 원장 rf_record_adversary 로 판정 기록) · 블록 L-code
# 발행기(rf_emit_block_lcode) · 기전 셸(LLM 대신 고정 기전 JSON → **실물 merge**) · 텔레그램(rf_auto_notify 호출 기록) · 팡파레 · 라운드 리뷰.
#   S1 [사고 재현] 레인 8칸 → tick 1 의 기전 백필(B6)이 B5 설계를 저장하려 한다 → 배치 B5_16..20 → tick 2 → tick 3
#      수리판: 레인 설계 보존 · 기전 백업 · tick 2 에 B5_21..23 측정 뒤 **정상 경계 1회**(G2·L-code·기전·텔레그램 각 1회) · 백필 0회
#      구판(red): 파일이 기전 5칸으로 덮이고 B5 경계 처리 0회(G2·L-code·텔레그램 없음) · B5 칸 5개만
#   S2 [사고 뒤 상태] 파일 = 기전 5칸 · B5_16..20 측정(판정 없음) · B7 측정 · B5 L-code·텔레그램 없음 · 예산 38 ≥ 격자(재도출 — B4-SIX 뒤 37)
#      수리판: tick 1 이 경계 백필 1회(G2 → L-code → 기전 → 지연 텔레그램 n=B5 마지막 칸) 뒤 B4 배치 · tick 2 백필 0회(멱등) ·
#      B4 마지막 배치 다음 tick = grid_consumed → 소진(halt_no_jobs 아님 · (d) 예산 44 vs 격자 41 과 같은 모양) — B4 칸 수는 격자가 정한다(10-03)
#   S3 [G2 실패 상한] G2 스텁이 예외 → tick 1·2 에 백필 2회(두 번째는 need=g2 만) · L-code·텔레그램은 1회씩
#   S4 [격자 재도출 대조] 기전 writer 관문을 뺀 판 + 경계 백필 끔: tick 1 에서 설계 파일이 바뀌면 배치를 열지 않고 닫는다 →
#      tick 2 가 새 격자(5칸)로 B5 를 재고 정상 경계 1회
#   U  [순수 함수] 텔레그램 흔적(구판 n 사상 · 신판 base_id·block) · 상한·포기 표식 · 완결 판정 · G2 필요 · 설계 대조
#   M  [돌연변이] 백필 삭제 → S2 red · 대조 삭제 → S4 red(사고 재발) · 완결의 격자 재도출 삭제 → S1 경계 중복(red) ·
#      텔레그램 흔적 무시 → S2 텔레그램 red
# 운영 무접촉: 검사 entry id(T_B5BF_)가 운영 원장·로그 꼬리·설계·L-code 에 나타나지 않는다(운영 러너는 이 검사 도중에도 정상적으로 쓴다).
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_boundary_backfill.R   (약 6~10분 — 러너 대기 루프 20초/tick)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
cat(sprintf("ROOT(코드) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- gsub("\\", "/", if (nzchar(Sys.getenv("QVEST_BF_SBX_DIR"))) Sys.getenv("QVEST_BF_SBX_DIR") else tempdir(), fixed = TRUE)   # 보존 디버그용(기본 = 세션 임시)
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)
ONLY <- strsplit(Sys.getenv("QVEST_BF_ONLY", ""), ",")[[1]]; run_sec <- function(k) !length(ONLY) || k %in% ONLY

OPS <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
LOG_OPS <- file.path(OPS, ".cache/reinforce_auto_log.jsonl")
LOG_N0 <- if (file.exists(LOG_OPS)) length(readLines(LOG_OPS, warn = FALSE)) else 0L
leak <- function() {
  hits <- character(0)
  l1 <- file.path(OPS, "06_Registry/reinforce_ledger_l1.json")
  if (file.exists(l1) && any(grepl("T_B5BF_", readLines(l1, warn = FALSE), fixed = TRUE))) hits <- c(hits, "ledger")
  if (file.exists(LOG_OPS)) { ll <- readLines(LOG_OPS, warn = FALSE); new <- if (length(ll) > LOG_N0) ll[(LOG_N0 + 1L):length(ll)] else character(0)
    if (any(grepl("T_B5BF_|tstarm_", new))) hits <- c(hits, "log") }
  if (length(list.files(file.path(OPS, ".cache/rf_block_design"), pattern = "^T_B5BF_"))) hits <- c(hits, "rf_block_design")
  if (length(list.files(file.path(OPS, ".cache/rf_b5_design"), pattern = "^T_B5BF_"))) hits <- c(hits, "rf_b5_design")
  if (length(list.files(file.path(OPS, "stage_artifacts/l_code/reinforcement"), pattern = "T_B5BF_"))) hits <- c(hits, "l_code")
  if (length(list.files(file.path(OPS, "qepm/mailbox"), pattern = "T_B5BF_"))) hits <- c(hits, "mailbox")
  hits
}
CUR <- local({ j <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
               as.character(j$execution$exec_price) })
ARMS <- sprintf("tstarm_%s", letters[1:13])            # a~h = 레인 · i~m = 기전
PRE_CODES <- c(sprintf("B1_%d", 1:5), sprintf("B2_%d", 6:10), sprintf("B3_%d", 11:15), sprintf("B6_%d", c(32, 33, 34, 36, 42)))

# ── 샌드박스 ──────────────────────────────────────────────────────────────────
mk_sbx <- function(tag, lib_override = NULL, runner_override = NULL, bb_lib_override = NULL) {
  S <- file.path(TMP, sprintf("b5bf_%s_%d", tag, Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
  for (d in c("02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/ops", "02_Infrastructure/contracts",
              "02_Infrastructure/worktask", "02_Infrastructure/portfolio", "06_Registry", "04_Research", ".cache/rf_parallel",
              ".cache/rf_block_design", ".cache/rf_lcode_mech", "stage_artifacts/replication", "stage_artifacts/l_code/reinforcement",
              "stage_artifacts/paper_recharge", "qepm/mailbox"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  cp <- function(from, to) invisible(file.copy(from, file.path(S, to), overwrite = TRUE))
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/reinforcement")
  cp(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.](R|sh)$", full.names = TRUE), "02_Infrastructure/ops")
  cp(list.files(file.path(ROOT, "02_Infrastructure/contracts"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/contracts")
  cp(list.files(file.path(ROOT, "02_Infrastructure/portfolio"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/portfolio")
  cp(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), "02_Infrastructure/worktask")
  cp(file.path(ROOT, "02_Infrastructure/config.R"), "02_Infrastructure")
  for (f in c("reinforce_program.json", "weight_catalog.json", "rf_arm_compat.json", "a_eligibility_gate.json"))
    if (file.exists(file.path(ROOT, "06_Registry", f))) cp(file.path(ROOT, "06_Registry", f), "06_Registry")
  if (!is.null(lib_override)) file.copy(lib_override, file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R"), overwrite = TRUE)
  if (!is.null(runner_override)) file.copy(runner_override, file.path(S, "02_Infrastructure/ops/reinforce_auto_parallel.R"), overwrite = TRUE)
  if (!is.null(bb_lib_override)) file.copy(bb_lib_override, file.path(S, "02_Infrastructure/reinforcement/rf_boundary_backfill.R"), overwrite = TRUE)
  arms <- lapply(seq_along(ARMS), function(i) list(id = ARMS[i], kind = sprintf("tstkind_%s", letters[i]), family = "test", basis = "synthetic", status = "active"))
  writeLines(toJSON(list(schema = "overlay_catalog_v1", arms = arms), auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/overlay_catalog.json"))
  # 스텁 — 텔레그램·팡파레·라운드 리뷰(호출 기록만 · 발송 0)
  writeLines(c('rf_auto_notify <- function(base_id, n, kind = "block", delayed = FALSE) {',
               '  cat(sprintf("%s\\t%s\\t%s\\t%s\\n", base_id, n, kind, isTRUE(delayed)), file = file.path(Sys.getenv("QM_ROOT"), "stub_notify.log"), append = TRUE); TRUE }',
               '.rf_target_label <- function(e, ...) as.character(e$base_id %||% "")', '.rf_target_items <- function(e, ...) as.character(e$base_id %||% "")'),
             file.path(S, "02_Infrastructure/ops/rf_auto_notify.R"))
  writeLines(c('rf_grade_fanfare <- function(...) TRUE', 'rf_fanfare_new_grade <- function(...) NA_character_'), file.path(S, "02_Infrastructure/ops/rf_grade_fanfare.R"))
  writeLines('rf_round_review <- function(...) TRUE', file.path(S, "02_Infrastructure/ops/rf_round_review.R"))
  # 스텁 — 블록 L-code 발행기(원장에서 n → 블록 · 파일만 쓴다)
  writeLines(c('`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a',
               'rf_emit_block_lcode <- function(base_id, n_used, root = Sys.getenv("QM_ROOT"), dry_run = FALSE) {',
               '  L <- jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)',
               '  e <- Filter(function(x) identical(x$base_id, base_id), L$entries)[[1]]',
               '  a <- Filter(function(x) identical(as.integer(x$n), as.integer(n_used)), e$attempts); if (!length(a)) return(invisible(NULL))',
               '  blk <- sub("_.*$", "", as.character(a[[1]]$cell_code %||% a[[1]]$essence$cell_code))',
               '  p <- file.path(root, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", base_id, blk))',
               '  writeLines(jsonlite::toJSON(list(l_code = sprintf("L-RF-STUB-%s-%s", blk, n_used), lesson_text = sprintf("[%s] stub", blk), mechanism = "",',
               '                                   next_probes = list("a", "b")), auto_unbox = TRUE, pretty = TRUE), p)',
               '  cat(sprintf("%s\\t%s\\t%s\\n", base_id, blk, n_used), file = file.path(root, "stub_lcode.log"), append = TRUE); invisible(p) }',
               'rf_next_block <- function(entry, bid, prog, root = "") list(id = NULL, order = character(0), src = "stub")'),
             file.path(S, "02_Infrastructure/ops/rf_block_lcode.R"))
  # 스텁 — 기전 셸(LLM 대신 고정 JSON → 실물 merge)
  writeLines(c('#!/usr/bin/env bash', 'BID="$1"; BLK="$2"; R="${QVEST_RF_ROOT:-$QM_ROOT}"',
               'printf "%s\\t%s\\n" "$BID" "$BLK" >> "$R/stub_mech.log"',
               'F="$R/stub_mech_${BLK}.json"; [ -f "$F" ] || exit 0',
               'OUT="$R/.cache/rf_lcode_mech/${BID:0:50}_${BLK}.mechanism.json"; cp "$F" "$OUT"',
               'Rscript --no-environ "$R/02_Infrastructure/ops/rf_lcode_mechanism_lib.R" merge "$BID" "$BLK" "$OUT" >> "$R/stub_mech.out" 2>&1', 'exit 0'),
             file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism.sh"))
  # 스텁 — G2(판정은 원장 writer 로 · 계획 = stub_g2_plan.json {mode: ok|error, verdict})
  writeLines(c('rf_overlay_adversary_run <- function(base_id, block = "B5", layer = 1L, root = Sys.getenv("QM_ROOT"), ...) {',
               '  cat(sprintf("%s\\t%s\\n", base_id, block), file = file.path(root, "stub_g2.log"), append = TRUE)',
               '  pl <- tryCatch(jsonlite::fromJSON(file.path(root, "stub_g2_plan.json"), simplifyVector = TRUE), error = function(e) list())',
               '  if (identical(pl$mode, "error")) stop("stub G2 error")',
               '  L <- rf_load(layer, root); e <- Filter(function(x) identical(x$base_id, base_id), L$entries)[[1]]',
               '  out <- list()',
               '  for (a in e$attempts) { cd <- as.character(a$cell_code %||% ""); if (!startsWith(cd, paste0(block, "_")) || is.null(a$essence)) next',
               '    rf_record_adversary(layer, base_id, a$n, list(schema = "rf_overlay_adversary_v1", verdict = pl$verdict %||% "not_candidate", block = block,',
               '                        n = a$n, code = cd, reason = "stub", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), root = root)',
               '    out[[length(out) + 1L]] <- data.frame(code = cd, verdict = pl$verdict %||% "not_candidate") }',
               '  if (length(out)) do.call(rbind, out) else data.frame(code = character(0), verdict = character(0)) }'),
             file.path(S, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"))
  # 스텁 워커 — 합성 산출물(현행 규약 · 창 이탈 0 · 등급 C)
  writeLines(c(
    'suppressMessages(library(jsonlite)); `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a',
    'a <- commandArgs(trailingOnly = TRUE); S <- Sys.getenv("QM_ROOT")',
    'sp <- fromJSON(a[1], simplifyVector = FALSE); n <- as.integer(a[2]); code <- sp$code',
    'art <- file.path(S, "stage_artifacts/replication", sprintf("%s_%d_%d", code, n, Sys.getpid())); dir.create(art, recursive = TRUE, showWarnings = FALSE)',
    sprintf('au <- list(status = "OK", essence_grade = "C", selection_type = "sweep", n_trials_cumulative = 20L, dsr = 0.1, measurement_regime = list(selection_type = "sweep", n_trials_cumulative = 20L, n_trials_basis = "stub", exec_price = "%s"))', CUR),
    'writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(art, "authoritative_remeasure.json"))',
    'pt <- 1 + n / 100; cal <- 0.2 + n / 1000',
    'writeLines(toJSON(list(n = n, code = code, block = sp$block, ok = TRUE, grade = "C", strategy_name = a[3], artifacts = art, spec = a[1],',
    '  essence = list(cell_code = code, block = sp$block, port_t = pt, net_sharpe = 0.5, cagr = 0.1, mdd = 0.4, calmar = cal, oos_retention = 0.5,',
    '                 dsr = 0.1, selection_type = "sweep", n_trials_cumulative = 20L, window_deviation_months = 0, spec = a[1], source = "stub")), auto_unbox = TRUE, null = "null"), a[4])'),
    file.path(S, "02_Infrastructure/ops/rf_cell_worker.R"))
  S
}
cfg_write <- function(S, extra = list()) {
  cfg <- list(enabled = TRUE, parallel_cells = 5L, daily_cap = 999L, claim_stale_hours = 6, cell_max_retry = 2L, worker_timeout_sec = 180L,
              promote_min_grade = "B", promote_max_depth = 3L, lcode_mechanism = list(enabled = TRUE), b1_design = list(enabled = FALSE),
              b5_design = list(enabled = TRUE, max_cells = 8L, min_cells = 3L, max_new_arms = 3L, max_layers = 3L, prior_entries = 12L,
                               guards = list(max_redesign_rounds = 1L, daily_arm_cap = 6L, stagnation_window = 2L, max_active_generated = 40L)))
  for (k in names(extra)) cfg[[k]] <- extra[[k]]
  writeLines(toJSON(cfg, auto_unbox = TRUE, pretty = TRUE), file.path(S, "rcfg.json"))
  file.copy(file.path(S, "rcfg.json"), file.path(S, "06_Registry/reinforce_auto_config.json"), overwrite = TRUE)
}
BID1 <- "T_B5BF_entry"
mk_att <- function(S, bid, n, code, opened = "2026-09-24T06:00:00+0900", overlay_cell = list(), adv = NULL) {
  blk <- sub("_.*$", "", code)
  art <- file.path(S, "stage_artifacts/replication", sprintf("%s_%s", bid, code)); dir.create(art, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(list(status = "OK", essence_grade = "C", measurement_regime = list(exec_price = CUR)), auto_unbox = TRUE), file.path(art, "authoritative_remeasure.json"))
  sp <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, substr(bid, 1, 48)))
  spec <- list(code = code, block = blk, factors = list(list(kind = "db", id = "F0"), list(kind = "db", id = sprintf("F%d", n))),
               weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), overlay_cell = overlay_cell)
  if (length(overlay_cell)) { spec$overlay <- overlay_cell; spec$floor_code <- "B2_10"; spec$floor_source <- "attempt" }
  writeLines(toJSON(spec, auto_unbox = TRUE, null = "null"), sp)
  a <- list(n = as.integer(n), cell_code = code, idea = sprintf("[무인 병렬 %s] stub", code), keyword_axis = "x", grade = "C",
            artifacts = art, opened_at = opened, closed_at = opened, measurement_regime = list(exec_price = CUR, regime = CUR),
            essence = list(cell_code = code, block = blk, port_t = 1 + n / 100, calmar = 0.2 + n / 1000, cagr = 0.1, mdd = 0.4,
                           net_sharpe = 0.5, oos_retention = 0.5, window_deviation_months = 0, spec = sp))
  if (!is.null(adv)) a$adversary <- adv
  a
}
mk_ledger <- function(S, entry) writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(entry),
  combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = ""),
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
mk_entry <- function(S, bid, codes, max_attempts, extra_atts = list()) {
  atts <- lapply(seq_along(codes), function(k) mk_att(S, bid, k, codes[k]))
  list(base_id = bid, status = "active", base_grade = "C", max_attempts = as.integer(max_attempts), attempts_used = length(codes) + length(extra_atts),
       paper_key = "t", paper_id = "t", engine_path = "", base_artifacts = "", opened_at = "2026-09-24T05:43:52+0900",
       block_order = list("B1", "B2", "B3", "B6", "B5", "B7", "B4"), block_order_reason = "stub", attempts = c(atts, extra_atts))
}
mk_lcode <- function(S, bid, blk, mech = "") writeLines(toJSON(list(l_code = sprintf("L-RF-FIX-%s", blk), lesson_text = sprintf("[%s] fixture", blk),
  mechanism = mech, next_probes = list("a", "b")), auto_unbox = TRUE, pretty = TRUE),
  file.path(S, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", bid, blk)))
log_tg <- function(S, n, ts = "2026-09-24T07:10:00+0900") cat(toJSON(list(ts = ts, event = "telegram_block", src = "parallel", n = as.integer(n), sent = TRUE),
  auto_unbox = TRUE), "\n", sep = "", file = file.path(S, ".cache/reinforce_auto_log.jsonl"), append = TRUE)
stub_mech <- function(S, blk, next_blk = NULL, picks = NULL) {
  M <- list(mechanism = sprintf("%s_%s 셀이 갈렸다 — 기전 stub.", blk, if (identical(blk, "B6")) "32" else if (identical(blk, "B5")) "16" else "37"),
            next_block_actions = list(list(action = "stub 처치", why = "stub", expect = "stub")), avoid = list(), confidence = "low")
  if (!is.null(next_blk)) M$next_block_design <- list(block = next_blk, cells = lapply(seq_along(picks), function(i) { pk <- picks[[i]]
    if (length(pk) > 1L) list(picks = as.list(pk), label = sprintf("mech %d", i), why = "stub") else list(pick = pk, label = sprintf("mech %d", i), why = "stub") }))
  writeLines(toJSON(M, auto_unbox = TRUE, pretty = TRUE), file.path(S, sprintf("stub_mech_%s.json", blk)))
}
MECH_B5 <- list(ARMS[9], ARMS[10], ARMS[11], ARMS[12], c(ARMS[13], ARMS[3]))
lane_write <- function(S, bid) {
  p <- file.path(S, "lane_design_r1.json")
  cells <- list(list(picks = list(ARMS[1]), label = "L1", why = "lane"), list(picks = list(ARMS[2]), label = "L2", why = "lane"),
                list(picks = list(ARMS[3]), label = "L3", why = "lane"), list(picks = list(ARMS[4]), label = "L4", why = "lane"),
                list(picks = list(ARMS[1], ARMS[2]), label = "L5", why = "lane"), list(picks = list(ARMS[1], ARMS[3]), label = "L6", why = "lane"),
                list(picks = list(ARMS[2], ARMS[3]), label = "L7", why = "lane"), list(picks = list(ARMS[1], ARMS[4]), label = "L8 음성 대조", why = "lane"))
  writeLines(toJSON(list(schema = "rf_b5_design_v1", base_id = bid, round = 1L, rationale = "stub", cells = cells, new_arms = list()),
                    auto_unbox = TRUE, pretty = TRUE), p)
  run_r(S, c(shQuote(file.path(S, "02_Infrastructure/ops/rf_b5_design_lib.R")), "verify", bid, shQuote(p), "1", "1", "-", "-"))
}
set_env <- function(S) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG", "QVEST_RF_CLAIM", "QVEST_RF_ROOT", "QVEST_RP_JLOG",
                      "QM_REFRESH_LOCKDIR", "QM_RAWDATA_WRITER_LOCKDIR", "QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_TG_DRY_RUN",
                      "QVEST_PY"), unset = NA)
  Sys.unsetenv(c("QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_RP_JLOG"))
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = EMPTY_RENV, QVEST_RF_CONFIG = file.path(S, "rcfg.json"),
             QVEST_RF_CLAIM = file.path(S, ".cache/claim_bf"), QVEST_RF_ROOT = S, QM_REFRESH_LOCKDIR = file.path(S, "no_refresh.lock"),
             QM_RAWDATA_WRITER_LOCKDIR = file.path(S, "no_writer.lock"), QVEST_TG_DRY_RUN = "1", QVEST_PY = file.path(S, "no_python.exe"))
  old
}
restore_env <- function(old) for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k]))
run_r <- function(S, args) { old <- set_env(S); on.exit(restore_env(old), add = TRUE)
  paste(suppressWarnings(system2("Rscript", c("--no-environ", args), stdout = TRUE, stderr = TRUE)), collapse = "\n") }
tick <- function(S) run_r(S, shQuote(file.path(S, "02_Infrastructure/ops/reinforce_auto_parallel.R")))
jl <- function(S) { p <- file.path(S, ".cache/reinforce_auto_log.jsonl"); if (!file.exists(p)) return(list())
  Filter(Negate(is.null), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL))) }
evn <- function(S, name, pred = function(r) TRUE) Filter(function(r) identical(as.character(r$event %||% ""), name) && isTRUE(pred(r)), jl(S))
stub_lines <- function(S, f) { p <- file.path(S, f); if (file.exists(p)) readLines(p, warn = FALSE) else character(0) }
led <- function(S) fromJSON(file.path(S, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
ent <- function(S, bid) Filter(function(e) identical(e$base_id, bid), led(S)$entries)[[1]]
codes_of <- function(e, blk) { v <- vapply(e$attempts, function(a) as.character(a$cell_code %||% ""), character(1)); sort(v[startsWith(v, paste0(blk, "_"))]) }
fp_b5 <- function(S, bid) file.path(S, ".cache/rf_block_design", sprintf("%s_B5.json", substr(bid, 1, 50)))
dsg <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
tail_out <- function(o, k = 500) substr(o, max(1, nchar(o) - k), nchar(o))

# ── 시나리오 빌더 ────────────────────────────────────────────────────────────
build_s1 <- function(tag, ...) {
  S <- mk_sbx(tag, ...); cfg_write(S)
  mk_ledger(S, mk_entry(S, BID1, PRE_CODES, 44L))
  for (b in c("B1", "B2", "B3")) mk_lcode(S, BID1, b, mech = sprintf("%s_1 fixture 기전", b))
  mk_lcode(S, BID1, "B6", mech = "")                                  # 기전 빈 블록 → 러너의 기전 백필 대상
  for (n in c(5, 10, 15, 20)) log_tg(S, n)
  stub_mech(S, "B6", "B5", MECH_B5); stub_mech(S, "B5"); stub_mech(S, "B7")
  o <- lane_write(S, BID1)
  list(S = S, lane_out = o)
}
build_s2 <- function(tag, g2_mode = "ok", ...) {
  S <- mk_sbx(tag, ...); cfg_write(S)
  b5 <- lapply(1:5, function(k) mk_att(S, BID1, 20 + k, sprintf("B5_%d", 15 + k), opened = "2026-09-25T22:19:54+0900",
                                         overlay_cell = list(kind = sprintf("tstkind_%s", letters[k]), arm_id = ARMS[k])))
  b7 <- lapply(1:5, function(k) mk_att(S, BID1, 25 + k, sprintf("B7_%d", 36 + k), opened = "2026-09-25T22:56:53+0900"))
  e <- mk_entry(S, BID1, PRE_CODES, 38L, extra_atts = c(b5, b7))
  e$b5_design <- list(rounds = list(list(round = 1L, source = "b5_design_lane", n_cells = 8L, fallback = FALSE)))
  mk_ledger(S, e)
  writeLines(toJSON(list(block = "B5", cells = lapply(seq_along(MECH_B5), function(i) { pk <- MECH_B5[[i]]
    if (length(pk) > 1L) list(picks = as.list(pk), label = sprintf("mech %d", i)) else list(pick = pk, label = sprintf("mech %d", i)) })),
    auto_unbox = TRUE, pretty = TRUE), fp_b5(S, BID1))
  for (b in c("B1", "B2", "B3", "B6", "B7")) mk_lcode(S, BID1, b, mech = sprintf("%s_1 fixture 기전", b))
  for (n in c(5, 10, 15, 20)) log_tg(S, n); log_tg(S, 30, ts = "2026-09-25T23:33:38+0900")
  stub_mech(S, "B5")
  writeLines(toJSON(list(mode = g2_mode, verdict = "not_candidate"), auto_unbox = TRUE), file.path(S, "stub_g2_plan.json"))
  S
}

# ── U. 순수 함수 ────────────────────────────────────────────────────────────
if (run_sec("U")) {
  cat("\n=== U. 판정 정본(rf_boundary_backfill.R) — 순수 함수 ===\n")
  U <- new.env()
  invisible(capture.output(suppressMessages({
    sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = U)
    sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), envir = U)
    sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_boundary_backfill.R"), envir = U) })))
  SU <- mk_sbx("u"); cfg_write(SU)
  b5 <- lapply(1:5, function(k) mk_att(SU, "T_B5BF_u", 20 + k, sprintf("B5_%d", 15 + k), opened = "2026-09-25T22:19:54+0900"))
  b7 <- lapply(1:5, function(k) mk_att(SU, "T_B5BF_u", 25 + k, sprintf("B7_%d", 36 + k), opened = "2026-09-25T22:56:53+0900"))
  EU <- mk_entry(SU, "T_B5BF_u", PRE_CODES, 38L, extra_atts = c(b5, b7))
  n_of <- stats::setNames(sub("_.*$", "", vapply(EU$attempts, function(a) a$cell_code, "")), vapply(EU$attempts, function(a) as.character(a$n), ""))
  ev <- function(n, ts, base_id = "", block = "", sent = TRUE, event = "telegram_block", src = "parallel")
    list(event = event, ts = ts, n = n, sent = sent, base_id = base_id, block = block, src = src)
  since5 <- U$.rfbb_ts("2026-09-25T22:19:54+0900")
  chk(isTRUE(U$rfbb_tg_seen(list(ev(20, "2026-09-24T07:10:00+0900")), "T_B5BF_u", "B6", 20, U$.rfbb_ts("2026-09-24T06:00:00+0900"), n_of)),
      "U1a 구판 이벤트(n 만) — n=20 → B6 · 시각 ≥ 블록 첫 시도 → 흔적 있음")
  chk(!isTRUE(U$rfbb_tg_seen(list(ev(30, "2026-09-25T23:33:38+0900")), "T_B5BF_u", "B5", 25, since5, n_of)),
      "U1b 구판 n=30(B7 칸) 은 B5 흔적이 아니다(n → 블록 사상)")
  chk(!isTRUE(U$rfbb_tg_seen(list(ev(25, "2026-09-20T00:00:00+0900")), "T_B5BF_u", "B5", 25, since5, n_of)),
      "U1c 구판 이벤트 시각 < 블록 첫 시도 → 다른 entry 의 것(흔적 아님)")
  chk(isTRUE(U$rfbb_tg_seen(list(ev(25, "2026-09-26T00:00:00+0900", base_id = "T_B5BF_u", block = "B5")), "T_B5BF_u", "B5", 25, since5, n_of)) &&
        !isTRUE(U$rfbb_tg_seen(list(ev(25, "2026-09-26T00:00:00+0900", base_id = "OTHER", block = "B5")), "T_B5BF_u", "B5", 25, since5, n_of)),
      "U2 신판 이벤트(base_id·block) — 같은 entry 면 흔적 · 다른 entry 면 아님")
  chk(!isTRUE(U$rfbb_tg_seen(list(ev(25, "2026-09-26T00:00:00+0900", base_id = "T_B5BF_u", block = "B5", sent = FALSE)), "T_B5BF_u", "B5", 25, since5, n_of)),
      "U2b 발송 실패(sent=false) 는 흔적이 아니다 — 재시도 대상")
  cells <- do.call(c, lapply(fromJSON(file.path(SU, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)$blocks,
                             function(b) lapply(b$cells, function(c) { c$block <- b$id; c })))
  lgp <- file.path(SU, "u_log.jsonl")
  wr_ev <- function(evs) writeLines(vapply(evs, function(e) as.character(toJSON(e, auto_unbox = TRUE)), ""), lgp)
  wr_ev(list(list(ts = "2026-09-26T09:00:00+0900", event = "boundary_backfill", src = "parallel", base_id = "T_B5BF_u", block = "B5"),
             list(ts = "2026-09-26T09:10:00+0900", event = "boundary_backfill", src = "parallel", base_id = "T_B5BF_u", block = "B5")))
  adv_fn <- function(a) "unverified"
  T1 <- U$rfbb_targets(EU, cells, SU, lgp, max_tries = 2L, adv_status = adv_fn)
  blks <- function(L) vapply(L, function(r) r$block, "")
  chk(!("B5" %in% blks(T1$todo)) && identical(blks(T1$gave_up), "B5"),
      "U3a B5 시작 표식 2건 = 상한 → B5 는 todo 밖 · 포기 표식 대상 B5(다른 블록은 각자 계수)",
      sprintf("todo=%s gave_up=%s", paste(blks(T1$todo), collapse = ","), paste(blks(T1$gave_up), collapse = ",")))
  wr_ev(list(list(ts = "2026-09-26T09:00:00+0900", event = "boundary_backfill", src = "parallel", base_id = "T_B5BF_u", block = "B5"),
             list(ts = "2026-09-26T09:10:00+0900", event = "boundary_backfill", src = "parallel", base_id = "T_B5BF_u", block = "B5"),
             list(ts = "2026-09-26T09:20:00+0900", event = "boundary_backfill_gave_up", src = "parallel", base_id = "T_B5BF_u", block = "B5")))
  T2 <- U$rfbb_targets(EU, cells, SU, lgp, max_tries = 2L, adv_status = adv_fn)
  chk(!("B5" %in% blks(T2$todo)) && !("B5" %in% blks(T2$gave_up)), "U3b 포기 표식이 있으면 B5 를 다시 안 찍는다(매 tick 소음 금지)")
  writeLines(character(0), lgp)
  T3 <- U$rfbb_targets(EU, cells, SU, lgp, max_tries = 2L, adv_status = adv_fn)
  st <- stats::setNames(T3$status, vapply(T3$status, function(r) r$block, ""))
  chk(isTRUE(st$B5$complete) && setequal(st$B5$need, c("g2", "lcode", "telegram")) && identical(st$B5$n_last, 25),
      "U4a B5 완결(격자 5칸 전부 시도) · need = g2+lcode+telegram · n_last = 25", paste(st$B5$why, paste(st$B5$need, collapse = "+"), st$B5$n_last))
  chk(!isTRUE(st$B4$complete) && startsWith(st$B4$why, "free:"), "U4b B4 = 빈 칸 → 미완결(백필 대상 아님)", st$B4$why)
  EUp <- EU; EUp$attempts[[length(EUp$attempts)]]$essence <- NULL
  st2 <- stats::setNames(U$rfbb_block_status(EUp, cells, SU, list(), adv_fn), vapply(U$rfbb_block_status(EUp, cells, SU, list(), adv_fn), function(r) r$block, ""))
  chk(!isTRUE(st2$B7$complete) && startsWith(st2$B7$why, "pending"), "U4c 미결(재개 대상) 칸이 있으면 미완결", st2$B7$why)
  st3 <- U$rfbb_block_status(EU, cells, SU, list(), function(a) "not_candidate")
  st3 <- stats::setNames(st3, vapply(st3, function(r) r$block, ""))
  chk(!("g2" %in% st3$B5$need), "U5 판정이 이미 있으면(not_candidate) G2 는 필요 없다")
  w <- list(B5 = list(list(code = "B5_16", label = "x")))
  dir.create(file.path(SU, ".cache/rf_block_design"), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(list(block = "B5", cells = list(list(pick = ARMS[1], label = "L1"))), auto_unbox = TRUE), fp_b5(SU, "T_B5BF_u"))
  was <- list(B5 = U$rfbd_cells(SU, "T_B5BF_u", "B5"))
  chk(!length(U$rfbb_design_drift(SU, "T_B5BF_u", was)), "U6a 설계 파일이 격자를 만든 설계와 같으면 대조 무발화")
  writeLines(toJSON(list(block = "B5", cells = list(list(pick = ARMS[2], label = "M1"))), auto_unbox = TRUE), fp_b5(SU, "T_B5BF_u"))
  chk(identical(U$rfbb_design_drift(SU, "T_B5BF_u", was), "B5"), "U6b tick 도중 파일이 바뀌면 그 블록을 낸다")
  unlink(SU, recursive = TRUE, force = TRUE)
}

# ── S1 사고 재현 ─────────────────────────────────────────────────────────────
s1_check <- function(S, label, quiet = FALSE) {
  f <- fp_b5(S, BID1); d0 <- dsg(f); m0 <- if (file.exists(f)) unname(tools::md5sum(f)) else ""
  o1 <- tick(S); o2 <- tick(S); o3 <- tick(S)
  e <- ent(S, BID1); d <- dsg(f)
  n5 <- codes_of(e, "B5"); g2 <- stub_lines(S, "stub_g2.log"); lc <- stub_lines(S, "stub_lcode.log"); nt <- stub_lines(S, "stub_notify.log")
  nt5 <- nt[vapply(strsplit(nt, "\t"), function(x) { n <- as.integer(x[2]); a <- Filter(function(z) identical(as.integer(z$n), n), e$attempts)
    length(a) && startsWith(as.character(a[[1]]$cell_code), "B5_") }, logical(1))]
  r <- list(
    kept = identical(d$source, "b5_design_lane") && length(d$cells) == 8L && identical(unname(tools::md5sum(f)), m0),
    backed = length(evn(S, "block_design_deferred", function(x) identical(x$reason, "b5_design_lane_priority"))) >= 1L,
    cells8 = identical(n5, sprintf("B5_%d", 16:23)),
    g2_once = sum(grepl("\tB5$", g2)) == 1L,
    lcode_b5 = sum(grepl("\tB5\t", lc)) == 1L && file.exists(file.path(S, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_B5.json", BID1))),
    tg_once = length(nt5) == 1L && !grepl("\tTRUE$", nt5[1]),
    no_backfill = !length(evn(S, "boundary_backfill", function(x) identical(x$block, "B5"))),
    no_fatal = !length(evn(S, "fatal", function(x) identical(x$src, "parallel"))))
  if (!quiet) {
    chk(isTRUE(lane_ok <- identical(d0$source, "b5_design_lane") && length(d0$cells) == 8L), sprintf("[%s] S1-0 레인 writer 8칸(source=b5_design_lane)", label))
    chk(r$kept, sprintf("[%s] S1a 3 tick 뒤에도 레인 설계 파일 불변(8칸 · source 유지)", label), sprintf("cells=%s src=%s | %s", length(d$cells), d$source %||% "NULL", tail_out(o1)))
    chk(r$backed, sprintf("[%s] S1b 기전(B6 백필)의 B5 설계는 block_design_deferred(레인 우선)로 백업", label))
    chk(r$cells8, sprintf("[%s] S1c B5 = 레인 8칸 전부 측정(B5_16..23)", label), paste(n5, collapse = ","))
    chk(r$g2_once, sprintf("[%s] S1d B5 G2 정확히 1회(경계 1회)", label), sprintf("g2=%s", paste(g2, collapse = "|")))
    chk(r$lcode_b5, sprintf("[%s] S1e B5 블록 L-code 1회 발행", label), paste(lc, collapse = "|"))
    chk(r$tg_once, sprintf("[%s] S1f B5 블록 텔레그램 1회(정상 경계 · 지연 아님)", label), paste(nt, collapse = "|"))
    chk(r$no_backfill, sprintf("[%s] S1g 정상 경로에서 경계 백필 0회(흔적이 있으면 안 돈다)", label))
    chk(r$no_fatal, sprintf("[%s] S1h 러너 fatal 0", label), paste(vapply(evn(S, "fatal", function(x) identical(x$src, "parallel")), function(x) as.character(x$err %||% ""), ""), collapse = " | "))
  }
  r
}
if (run_sec("S1")) {
  cat("\n=== S1. 사고 재현 — 레인 8칸 · tick 도중 기전이 B5 를 덮으려 한다 ===\n")
  b1 <- build_s1("s1"); r1 <- s1_check(b1$S, "설치본")
}

# ── S2 사고 뒤 상태 — 경계 백필 + 격자 소진 ─────────────────────────────────
## ★격자 칸 수 — 라벨용 재도출(B4-SIX 10-03 · 하드코딩 금지: 4축 시절 35 · 6축 37)
GRID_N <- tryCatch({ .pg <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
  as.integer(sum(vapply(.pg$blocks, function(b) as.integer(b$n %||% length(b$cells)), integer(1)))) }, error = function(e) NA_integer_)
s2_check <- function(S, label, quiet = FALSE) {
  o1 <- tick(S)
  bb1 <- evn(S, "boundary_backfill", function(x) identical(x$block, "B5"))
  g2 <- stub_lines(S, "stub_g2.log"); lc <- stub_lines(S, "stub_lcode.log"); nt <- stub_lines(S, "stub_notify.log"); mh <- stub_lines(S, "stub_mech.log")
  e1 <- ent(S, BID1)
  nb4_t1 <- length(evn(S, "batch_start", function(x) identical(x$block, "B4")))   # ★tick 1 만의 B4 배치(B4-SIX 10-03 — 7칸이면 B4 가 두 배치에 걸친다)
  .h1 <- length(evn(S, "halt_no_jobs"))
  o2 <- tick(S)
  bb2 <- evn(S, "boundary_backfill", function(x) identical(x$block, "B5"))
  ## ★소진 tick 을 tick 2 로 못박지 않는다(B4-SIX 10-03) — 결합 칸 수(격자 · 진단 블록 투영)가 병렬 칸 수보다 많으면 B4 가 두 배치에 걸치고
  ##   전 칸이 중복 승계인 배치 tick 은 halt_no_jobs 로 닫힌다(정상). 소진될 때까지(상한 4 tick) 돌려 **소진 tick** 의 사건만 잰다.
  o_ex <- o2; hnj_last <- length(evn(S, "halt_no_jobs")) > .h1
  for (.k in 1:2) { if (identical(ent(S, BID1)$status, "exhausted")) break
    .h0 <- length(evn(S, "halt_no_jobs")); o_ex <- tick(S); hnj_last <- length(evn(S, "halt_no_jobs")) > .h0 }
  e2 <- ent(S, BID1)
  r <- list(
    bb_once = length(bb1) == 1L && setequal(strsplit(as.character(bb1[[1]]$need), "+", fixed = TRUE)[[1]], c("g2", "lcode", "telegram")),
    g2 = sum(grepl("\tB5$", g2)) == 1L && all(vapply(Filter(function(a) startsWith(a$cell_code, "B5_"), e1$attempts), function(a)
      identical(as.character((a$adversary %||% list())$verdict %||% ""), "not_candidate"), logical(1))),
    lcode = sum(grepl("\tB5\t25$", lc)) == 1L,
    mech = sum(grepl("\tB5$", mh)) == 1L,
    tg_delayed = any(grepl(sprintf("^%s\t25\tblock\tTRUE$", BID1), nt)),
    ## ★칸 수는 격자가 정한다(다른 갈래의 구조 절단 규칙 — B3-STRUCTURAL-TRIM 이 B4 결합 칸을 줄일 수 있다 · 다중 키트 리허설 실측 2칸).
    ##   재는 것 = 백필이 tick 을 끝내지 않고 같은 tick 이 B4 배치를 연다는 사실.
    b4_ran = length(codes_of(e1, "B4")) >= 1L && nb4_t1 == 1L,
    idem = length(bb2) == 1L,
    grid_consumed = length(evn(S, "grid_consumed")) == 1L && length(evn(S, "exhaust_reached", function(x) identical(x$why, "grid"))) == 1L &&
      !isTRUE(hnj_last) && identical(e2$status, "exhausted"),
    no_fatal = !length(evn(S, "fatal", function(x) identical(x$src, "parallel"))))
  if (!quiet) {
    chk(r$bb_once, sprintf("[%s] S2a tick 1 경계 백필 1회(B5 · need=g2+lcode+telegram)", label), sprintf("n=%d | %s", length(bb1), tail_out(o1)))
    chk(r$g2, sprintf("[%s] S2b 백필 G2 1회 → B5 5칸 판정 기록(not_candidate)", label), paste(g2, collapse = "|"))
    chk(r$lcode, sprintf("[%s] S2c 백필 L-code = B5 마지막 측정 칸 n=25 기준 1회", label), paste(lc, collapse = "|"))
    chk(r$mech, sprintf("[%s] S2d 백필 L-code 뒤 기전 레인 1회(B5)", label), paste(mh, collapse = "|"))
    chk(r$tg_delayed, sprintf("[%s] S2e 지연 텔레그램 = rf_auto_notify(n=25 · kind=block · delayed=TRUE)", label), paste(nt, collapse = "|"))
    chk(r$b4_ran, sprintf("[%s] S2f 백필 뒤 같은 tick 이 B4 배치를 계속 연다(배치 1회 · 칸 수 = 격자)", label), paste(codes_of(e1, "B4"), collapse = ","))
    chk(r$idem, sprintf("[%s] S2g tick 2 백필 0회(흔적 생김 = 멱등)", label), sprintf("누적 %d", length(bb2)))
    chk(r$grid_consumed, sprintf("[%s] S2h (d) 예산 38 ≥ 격자 %d(재도출) → B4 마지막 배치 다음 tick grid_consumed → 소진(그 tick 에 halt_no_jobs 아님)", label, GRID_N),
        sprintf("status=%s | %s", e2$status, tail_out(o_ex, 300)))
    chk(r$no_fatal, sprintf("[%s] S2i 러너 fatal 0", label))
  }
  r
}
if (run_sec("S2")) {
  cat("\n=== S2. 사고 뒤 상태 — 경계 백필 · 멱등 · 격자 소진 ===\n")
  S2 <- build_s2("s2"); r2 <- s2_check(S2, "설치본")
}

# ── S3 G2 실패 — 상한 안에서 재시도 ─────────────────────────────────────────
if (run_sec("S3")) {
  cat("\n=== S3. G2 예외 — 상한 안 재시도(부품별) ===\n")
  S3 <- build_s2("s3", g2_mode = "error")
  tick(S3); tick(S3)
  bb <- evn(S3, "boundary_backfill", function(x) identical(x$block, "B5"))
  af <- evn(S3, "adversary_failed", function(x) identical(x$phase, "boundary_backfill"))
  lc <- stub_lines(S3, "stub_lcode.log"); nt <- stub_lines(S3, "stub_notify.log")
  chk(length(bb) == 2L && identical(as.character(bb[[2]]$need), "g2"), "S3a 백필 2회 — 두 번째는 need=g2 만(L-code·텔레그램은 흔적이 생겼다)",
      paste(vapply(bb, function(x) as.character(x$need), ""), collapse = " / "))
  chk(length(af) == 2L, "S3b G2 예외는 adversary_failed(phase=boundary_backfill)로 남고 러너는 계속 돈다", sprintf("n=%d", length(af)))
  chk(sum(grepl("\tB5\t", lc)) == 1L && sum(grepl("\t25\tblock\tTRUE$", nt)) == 1L, "S3c L-code·지연 텔레그램은 1회씩(부품별 흔적)")
  chk(!length(evn(S3, "fatal", function(x) identical(x$src, "parallel"))), "S3d 러너 fatal 0")
}

# ── S4 격자 재도출 대조 ─────────────────────────────────────────────────────
LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
RUN <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
BBL <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_boundary_backfill.R")
mutant <- function(path, tag, from, to, eol = "") {
  b <- readBin(path, "raw", file.info(path)$size); s <- rawToChar(b); Encoding(s) <- "UTF-8"
  crlf <- grepl("\r\n", s, fixed = TRUE); s <- gsub("\r\n", "\n", s, fixed = TRUE)
  k <- gregexpr(from, s, fixed = TRUE)[[1]]; if (length(k) != 1L || k[1] < 0) return(NULL)
  s <- sub(from, to, s, fixed = TRUE); if (crlf) s <- gsub("\n", "\r\n", s, fixed = TRUE)
  p <- file.path(TMP, sprintf("mut_%s_%d.%s", tag, Sys.getpid(), tools::file_ext(path)))
  writeBin(charToRaw(enc2utf8(s)), p); p
}
LIB_NOGUARD <- mutant(LIB, "lib_noguard", 'if (!length(ev)) return(list(refuse = FALSE, code = "", evidence = "no_lane_round"))',
                      'return(list(refuse = FALSE, code = "", evidence = "mutated"))')
s4_check <- function(S, label, quiet = FALSE) {
  o1 <- tick(S); dr <- evn(S, "tick_closed_design_drift"); e1 <- ent(S, BID1)
  o2 <- tick(S); e2 <- ent(S, BID1)
  g2 <- stub_lines(S, "stub_g2.log"); nt <- stub_lines(S, "stub_notify.log")
  r <- list(drift = length(dr) == 1L && identical(as.character(dr[[1]]$blocks), "B5") && !length(codes_of(e1, "B5")),
            measured5 = identical(codes_of(e2, "B5"), sprintf("B5_%d", 16:20)),
            boundary = sum(grepl("\tB5$", g2)) == 1L && sum(grepl(sprintf("^%s\t25\tblock\tFALSE$", BID1), nt)) == 1L)
  if (!quiet) {
    chk(r$drift, sprintf("[%s] S4a tick 1 — 설계 파일 변경 감지 → tick_closed_design_drift(B5) · 배치 0", label), tail_out(o1, 400))
    chk(r$measured5, sprintf("[%s] S4b tick 2 — 새 격자(기전 5칸)로 B5_16..20 측정", label), paste(codes_of(e2, "B5"), collapse = ","))
    chk(r$boundary, sprintf("[%s] S4c tick 2 — 정상 경계 1회(G2 · 텔레그램 n=25) = 경계 판정이 파일 격자와 일치", label),
        sprintf("g2=%s nt=%s | %s", paste(g2, collapse = "|"), paste(nt, collapse = "|"), tail_out(o2, 300)))
  }
  r
}
if (run_sec("S4")) {
  cat("\n=== S4. 격자 재도출 대조 — 저장 관문을 뺀 판 · 경계 백필 끔 ===\n")
  if (is.null(LIB_NOGUARD)) ng("S4 준비 실패 — 저장 관문 돌연변이 적용 불가") else {
    b4 <- build_s1("s4", lib_override = LIB_NOGUARD); cfg_write(b4$S, list(boundary_backfill = list(enabled = FALSE)))
    r4 <- s4_check(b4$S, "설치본")
  }
}

# ── M. 돌연변이 ─────────────────────────────────────────────────────────────
if (run_sec("M")) {
  cat("\n=== M. 돌연변이 — 방어가 실제로 가르는가 ===\n")
  m1 <- mutant(RUN, "run_nobf", "if (!identical(.bbc$enabled, FALSE)) tryCatch({", "if (FALSE) tryCatch({")
  if (is.null(m1)) ng("MB1 적용 실패(백필 줄 부재)") else {
    Sm <- build_s2("mb1", runner_override = m1); r <- s2_check(Sm, "MB1", quiet = TRUE)
    chk(!isTRUE(r$bb_once) && !isTRUE(r$tg_delayed), "MB1 [돌연변이] 경계 백필 삭제 → 사고 뒤 상태가 그대로 남는다 = S2a·S2e 가 잡는다") }
  m2 <- mutant(RUN, "run_nodrift", "if (length(.drift)) {", "if (FALSE) {")
  if (is.null(m2) || is.null(LIB_NOGUARD)) ng("MB2 적용 실패(대조 줄 부재)") else {
    bm <- build_s1("mb2", lib_override = LIB_NOGUARD, runner_override = m2); cfg_write(bm$S, list(boundary_backfill = list(enabled = FALSE)))
    r <- s4_check(bm$S, "MB2", quiet = TRUE)
    chk(!isTRUE(r$drift) && !isTRUE(r$boundary), "MB2 [돌연변이] 격자 대조 삭제(+ 저장 관문 없음 · 백필 끔) → 09-25 사고 재발(B5 경계 0회) = S4a·S4c 가 잡는다") }
  m3 <- mutant(BBL, "bb_nofree", "free <- setdiff(codes[nzchar(codes)], taken)", "free <- character(0)")
  if (is.null(m3)) ng("MB3 적용 실패(완결 재도출 줄 부재)") else {
    bm3 <- build_s1("mb3", bb_lib_override = m3); r <- s1_check(bm3$S, "MB3", quiet = TRUE)
    chk(!isTRUE(r$g2_once) || !isTRUE(r$no_backfill), "MB3 [돌연변이] 완결을 현재 격자에서 재도출하지 않음(빈 칸 무시) → 5/8 에서 조기 백필 · 경계 중복 = S1d·S1g 가 잡는다") }
  m4 <- mutant(BBL, "bb_tgseen", "if (!rfbb_tg_seen(events, bid, b, rec$n_last, since, n_of)) {", "if (FALSE) {")
  if (is.null(m4)) ng("MB4 적용 실패(텔레그램 흔적 줄 부재)") else {
    Sm4 <- build_s2("mb4", bb_lib_override = m4); r <- s2_check(Sm4, "MB4", quiet = TRUE)
    chk(!isTRUE(r$tg_delayed) && isTRUE(r$lcode), "MB4 [돌연변이] 텔레그램 흔적 판정 무력화 → 지연 텔레그램 0 · L-code 는 발행 = S2e 가 잡는다") }
}

cat("\n=== Z. 운영 무접촉 ===\n")
lk <- leak(); chk(!length(lk), "Z1 검사 표식(T_B5BF_ · tstarm_)이 운영 원장·로그·설계·L-code·mailbox 어디에도 없다", paste(lk, collapse = ","))
if (!nzchar(Sys.getenv("QVEST_BF_KEEP"))) unlink(list.files(TMP, pattern = "^b5bf_", full.names = TRUE), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_boundary_backfill","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
