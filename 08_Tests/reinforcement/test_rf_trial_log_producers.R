#!/usr/bin/env Rscript
#==============================================================================
# test_rf_trial_log_producers.R — 시행 로그 생산자 7곳 종단 검사 (O0a · 2026-09-25 · 설계 organic_design_final §3 G1 · §8.1 O0a 완료 판정)
#
# 러너(reinforce_auto_parallel.R)·이월(reinforce_auto_next_paper.R)·결합(rf_combination_launch.R)을 샌드박스 root 에서 실제 Rscript 로 돌린다.
#   스텁 = 워커(합성 산출물) · 텔레그램 · 팡파레 · 라운드 리뷰 · 기전 레인 · 픽커 3종(팩터·비중·오버레이 — 재료 DB 없이 결정론 후보를 낸다).
#   나머지(원장 writer · 관문 · 승자·바닥 해석 · 시행 로그 writer · 결정 기록 · claim)는 설치본 그대로.
#   P1 B1 배치(픽커 as-of) → b1_factor_pick 1건 · cell_registered(design rule_asof) = 등록 칸 전수 · 원장 attempt$design 일치
#   P2 B1 배치(픽커 미산출 → 격자 스냅샷 폴백) → b1_factor_pick(chosen = 격자 칸 팩터 집합) · 칸 출처 rule_full_ic
#   P3 B2 배치 → b2_weight_pick · block_winner(B1) · floor — 선택을 원장에서 **독립 재도출**(B1 port_t argmax · 바닥 = 자격 칸 argmax)과 대조
#   P4 B5 배치 → b5_overlay_pick · 칸 출처 rule_catalog · floor 기각 사유(유니버스 처치 칸 = 자격 미달)
#   P5 B4 배치 → block_winner = 이 tick 에 조립된 B4 칸 use 합집합(로그 b4_axes · 격자 B4 use − 진단 블록과 대조 · 10-03 P5A) ·
#      B5 는 적대검증 pass 칸만 · floor 기록 없음(B4 는 바닥을 소비하지 않는다)
#   P6 승격(next_paper) → promote(chosen promote · 자식 entry 실재) / 비승격(chosen no_promote · 사유)
#   P7 결합(rf_combination_launch) → combination(chosen = 발행 요청의 setkey)
#   P8 조인 — 모든 샌드박스에서 결정 ↔ 시행 조인 100% · 등록 칸 ↔ cell_registered 100% · trial_log_failed 0
#   P9 rf_reopen_entry 종단 — 격자 절단으로 소진(grid_consumed) → 격자 복원 + 사람 호출 reopen → 다음 tick 이 잘렸던 칸을 배치(멱등 포함)
#   M  돌연변이(샌드박스 러너 사본) — cell_registered 기록 줄 삭제 → P8 등록 조인 red · 승자 선택 메모 삭제 → P3 재도출 대조 red
# 부작용 없음: 운영 원장·로그·결정 기록·시행 로그 무접촉(전후 md5). 자식 Rscript 는 R_ENVIRON_USER=빈 파일.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
cat(sprintf("ROOT = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- normalizePath(tempdir(), winslash = "/")
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)
PROD <- file.path(ROOT, c("06_Registry/reinforce_ledger_l1.json", "06_Registry/rf_decisions.jsonl", "06_Registry/rf_trial_log.jsonl",
                          "06_Registry/replication_request.json", ".cache/reinforce_auto_log.jsonl"))
md5_prod <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
PROD0 <- md5_prod()
CUR <- local({ j <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
               as.character(j$execution$exec_price) })
AXIS <- c(B1 = "multifactor", B2 = "weighting", B3 = "universe", B4 = "combination", B5 = "risk_overlay", B6 = "execution_cadence", B7 = "structural_defense")

mk_sbx <- function(tag, pick_mode = "asof") {
  S <- file.path(TMP, sprintf("rftp_%s_%d", tag, Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
  for (d in c("02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/ops", "02_Infrastructure/contracts", "02_Infrastructure/utils",
              "02_Infrastructure/worktask", "06_Registry", ".cache/rf_parallel", "stage_artifacts/replication",
              "stage_artifacts/l_code/reinforcement", "stage_artifacts/paper_recharge", "qepm/mailbox", "engines"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  cp <- function(from, to) invisible(file.copy(from, file.path(S, to), overwrite = TRUE))
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/reinforcement")
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms"), full.names = TRUE), "02_Infrastructure/reinforcement/overlay_arms")
  cp(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.](R|sh)$", full.names = TRUE), "02_Infrastructure/ops")
  cp(list.files(file.path(ROOT, "02_Infrastructure/contracts"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/contracts")
  cp(list.files(file.path(ROOT, "02_Infrastructure/utils"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/utils")
  cp(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), "02_Infrastructure/worktask")
  cp(file.path(ROOT, "02_Infrastructure/config.R"), "02_Infrastructure")
  for (f in c("reinforce_program.json", "overlay_catalog.json", "weight_catalog.json", "rf_arm_compat.json", "a_eligibility_gate.json", "pit_quarantine.json"))
    if (file.exists(file.path(ROOT, "06_Registry", f))) cp(file.path(ROOT, "06_Registry", f), "06_Registry")
  writeLines(c('rf_auto_notify <- function(...) TRUE', '.rf_target_label <- function(e) as.character(e$base_id %||% "")',
               '.rf_target_items <- function(e, ...) as.character(e$base_id %||% "")'), file.path(S, "02_Infrastructure/ops/rf_auto_notify.R"))
  writeLines('rf_grade_fanfare <- function(...) TRUE', file.path(S, "02_Infrastructure/ops/rf_grade_fanfare.R"))
  writeLines('rf_round_review <- function(...) TRUE', file.path(S, "02_Infrastructure/ops/rf_round_review.R"))
  writeLines(c("#!/usr/bin/env bash", "exit 0"), file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism.sh"))
  # 픽커 스텁 — 재료 DB 없이 결정론 후보(선정 기저 as-of) · pick_mode="null" 이면 팩터 픽커 미산출(격자 폴백 경로)
  writeLines(c(
    sprintf('.PICK_MODE <- "%s"', pick_mode),
    'rf_pick_factor_sets <- function(n, exclude = character(0), seed_offset = 0L, depths = NULL, fallback_paper = NULL, root = NULL) {',
    '  if (identical(.PICK_MODE, "null")) return(NULL)',
    '  cells <- lapply(seq_len(n), function(i) list(code = sprintf("B1_%d", i), label = sprintf("stub fset %d", i),',
    '    factors = list(list(kind = "db", id = "F0"), list(kind = "db", id = sprintf("S%02d", i))), basis = "stub as-of", selection_basis = "asof_ic", selection_asof = "2004-12-31"))',
    '  list(cells = cells, picked_ids = sprintf("S%02d", seq_len(n)), seed_id = "S01", seed_offset = seed_offset, n_available = 40L,',
    '       excluded_no_ic = c("XNOIC1", "XNOIC2"), excluded_axis = "XAXIS1", substrate_asof = "2004-12-31", selection_basis = "asof_ic", max_rho = 0.1) }',
    'rf_root_papers_for <- function(SPEC, base_paper = NULL, cell_paper = NULL, root = NULL) list(papers = list(), families = character(0), unmapped_families = character(0))'),
    file.path(S, "02_Infrastructure/ops/rf_factor_arms.R"))
  writeLines(c('rf_pick_weight_arms <- function(n = 5L, exclude = character(0)) {',
               '  L <- setdiff(c("hrp", "minvar", "erc", "cdar", "kelly", "entropy", "tailrp"), exclude)[seq_len(n)]',
               '  list(cells = lapply(L, function(l) list(code = "B2_x", label = l, weighting = list(kind = "catalog", catalog_id = paste0("qepm:", l), label = l))), n_available = 7L) }'),
             file.path(S, "02_Infrastructure/ops/rf_weight_arms.R"))
  writeLines(c('rf_pick_overlay_arms <- function(n = 5L, exclude = character(0), root = NULL) {',
               '  ids <- setdiff(sprintf("ov_stub_%d", 1:8), exclude)[seq_len(n)]',
               '  list(cells = lapply(ids, function(i) list(code = "B5_x", label = i, overlay = list(kind = "arm", arm_id = i), basis = "stub")), n_available = 8L, picked_ids = ids) }'),
             file.path(S, "02_Infrastructure/ops/rf_overlay_arms.R"))
  writeLines(c(   # 스텁 워커 — 계획표 없이 칸 코드로 결정론 지표(port_t = 1 + 칸번호/100)
    'suppressMessages(library(jsonlite)); `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a',
    'a <- commandArgs(trailingOnly = TRUE); S <- Sys.getenv("QM_ROOT")',
    'sp <- fromJSON(a[1], simplifyVector = FALSE); n <- as.integer(a[2]); code <- sp$code',
    'art <- file.path(S, "stage_artifacts/replication", sprintf("%s_%d_%d", code, n, Sys.getpid())); dir.create(art, recursive = TRUE, showWarnings = FALSE)',
    'dates <- seq(as.Date("2005-02-01"), as.Date("2026-08-01"), by = "month")',
    'saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1), period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(art, "bt_result.rds"))',
    sprintf('au <- list(status = "OK", essence_grade = "C", selection_type = "sweep", n_trials_cumulative = 20L, dsr = 0.5, essence = list(dsr = 0.5), measurement_regime = list(selection_type = "sweep", n_trials_cumulative = 20L, n_trials_basis = "stub", exec_price = "%s"))', CUR),
    'writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(art, "authoritative_remeasure.json"))',
    'pt <- 1 + as.integer(sub("^B[0-9]+_", "", code)) / 100',
    'writeLines(toJSON(list(n = n, code = code, block = sp$block, ok = TRUE, grade = "C", strategy_name = a[3], artifacts = art, spec = a[1],',
    '  essence = list(cell_code = code, block = sp$block, port_t = pt, net_sharpe = 0.5, cagr = 0.1, mdd = 0.4, calmar = 0.25, oos_retention = 0.5,',
    '                 window_deviation_months = 0, dsr = 0.5, selection_type = "sweep", n_trials_cumulative = 20L, spec = a[1], source = "stub")), auto_unbox = TRUE, null = "null"), a[4])'),
    file.path(S, "02_Infrastructure/ops/rf_cell_worker.R"))
  writeLines(toJSON(list(enabled = TRUE, parallel_cells = 5L, daily_cap = 999L, claim_stale_hours = 6, cell_max_retry = 2L,
                         worker_timeout_sec = 180L, promote_min_grade = "B", promote_max_depth = 3L,
                         lcode_mechanism = list(enabled = FALSE), b1_design = list(enabled = FALSE),
                         combination = list(enabled = TRUE)), auto_unbox = TRUE), file.path(S, "rcfg.json"))
  file.copy(file.path(S, "rcfg.json"), file.path(S, "06_Registry/reinforce_auto_config.json"), overwrite = TRUE)   # 결합 스크립트는 root 설정을 읽는다
  S
}
mk_att <- function(S, bid, n, code, pt, grade = "C", spec = list(), extra = list()) {
  blk <- sub("_.*$", "", code)
  art <- file.path(S, "stage_artifacts/replication", sprintf("%s_%s_%d", bid, code, n)); dir.create(art, recursive = TRUE, showWarnings = FALSE)
  dates <- seq(as.Date("2005-02-01"), as.Date("2026-08-01"), by = "month")
  saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1), period_returns = data.frame(date = dates, ret_net = 0.01)),
          file.path(art, "bt_result.rds"))
  writeLines(toJSON(list(status = "OK", essence_grade = grade, selection_type = "sweep", n_trials_cumulative = 6L, dsr = 0.5,
                         measurement_regime = list(selection_type = "sweep", n_trials_cumulative = 6L, exec_price = CUR)),
                    auto_unbox = TRUE, null = "null"), file.path(art, "authoritative_remeasure.json"))
  sp <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, bid))
  s <- list(code = code, block = blk, factors = list(list(kind = "db", id = "F0"), list(kind = "db", id = sprintf("F%s", code))),
            weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), overlay_cell = list())
  for (k in names(spec)) s[[k]] <- spec[[k]]
  writeLines(toJSON(s, auto_unbox = TRUE, null = "null"), sp)
  a <- list(n = as.integer(n), cell_code = code, idea = sprintf("stub %s", code), keyword_axis = AXIS[[blk]], grade = grade, artifacts = art,
            closed_at = "2026-09-24T00:00:00+0900",
            essence = list(cell_code = code, block = blk, port_t = pt, calmar = 0.2 + pt / 10, cagr = 0.1, mdd = 0.4, net_sharpe = 0.6,
                           oos_retention = 0.5, window_deviation_months = 0, spec = sp))
  for (k in names(extra)) a[[k]] <- extra[[k]]
  a
}
mk_entry <- function(bid, atts, status = "active", ...) c(list(base_id = bid, status = status, base_grade = "C", max_attempts = 35L,
  attempts_used = length(atts), paper_key = paste0("pk_", bid), paper_id = bid, engine_path = "", base_artifacts = "",
  block_order = list("B1", "B2", "B3", "B6", "B5", "B7", "B4"), block_order_reason = "stub", attempts = atts), list(...))
mk_ledger <- function(S, entries) writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L, entries = entries,
  current_axis = "exec_v2_close_t1", combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = ""),
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
b1_set <- function(S, bid, pts = c(1.10, 1.30, 1.50, 1.20, 1.40)) lapply(1:5, function(k) mk_att(S, bid, k, sprintf("B1_%d", k), pts[k]))
run_script <- function(S, script, timeout = 300) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG", "QVEST_RF_CLAIM", "QVEST_RF_ROOT",
                      "QM_REFRESH_LOCKDIR", "QM_RAWDATA_WRITER_LOCKDIR", "QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_RP_JLOG"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.unsetenv(c("QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_RP_JLOG"))
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, QVEST_RF_ROOT = S, R_ENVIRON_USER = EMPTY_RENV, QVEST_RF_CONFIG = file.path(S, "rcfg.json"),
             QVEST_RF_CLAIM = file.path(S, ".cache/claim_e2e"), QM_REFRESH_LOCKDIR = file.path(S, "no_refresh.lock"),
             QM_RAWDATA_WRITER_LOCKDIR = file.path(S, "no_writer.lock"))
  out <- suppressWarnings(system2("Rscript", shQuote(file.path(S, "02_Infrastructure/ops", script)), stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}
rdj <- function(p) if (!file.exists(p)) list() else Filter(Negate(is.null), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"),
  function(l) tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)))
ev  <- function(S) vapply(rdj(file.path(S, ".cache/reinforce_auto_log.jsonl")), function(z) as.character(z$event %||% ""), character(1))
dec <- function(S, kind = NULL) Filter(function(r) is.null(kind) || identical(r$kind, kind), rdj(file.path(S, "06_Registry/rf_decisions.jsonl")))
trl <- function(S, kind = NULL) Filter(function(r) is.null(kind) || identical(r$kind, kind), rdj(file.path(S, "06_Registry/rf_trial_log.jsonl")))
led <- function(S) fromJSON(file.path(S, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
ent <- function(S, bid) Filter(function(e) identical(e$base_id, bid), led(S)$entries)[[1]]
ch1 <- function(r) as.character(unlist(r$chosen$ids %||% r$chosen %||% list()))
# 등록 조인 — 이 실행에서 원장에 새로 등록된 attempt(n > n0) ↔ cell_registered(base_id·n·code·design_source)
reg_join <- function(S, bid, n0) {
  A <- Filter(function(a) as.integer(a$n) > n0, ent(S, bid)$attempts %||% list())
  Tr <- Filter(function(r) identical(r$base_id, bid), trl(S, "cell_registered"))
  key_a <- vapply(A, function(a) sprintf("%d|%s|%s", as.integer(a$n), a$cell_code %||% "", a$design$design_source %||% "<none>"), character(1))
  key_t <- vapply(Tr, function(r) { c <- r$cells[[1]]; sprintf("%d|%s|%s", as.integer(c$n), c$code %||% "", c$design_source %||% "") }, character(1))
  list(n_att = length(A), n_trial = length(Tr), missing = setdiff(key_a, key_t), extra = setdiff(key_t, key_a), att = A)
}
BADEV <- c("fatal", "trial_log_failed", "decision_record_failed", "append_failed")

cat("\n=== P1 B1 배치 — 픽커 as-of ===\n")
S1 <- mk_sbx("p1", "asof"); mk_ledger(S1, list(mk_entry("T1", list())))
o1 <- run_script(S1, "reinforce_auto_parallel.R")
d1 <- dec(S1, "b1_factor_pick"); t1 <- trl(S1, "b1_factor_pick"); j1 <- reg_join(S1, "T1", 0L)
chk(length(d1) == 1L && length(t1) == 1L && identical(d1[[1]]$decision_id, t1[[1]]$decision_id),
    "P1a b1_factor_pick 결정 1 · 시행 1 · 같은 decision_id", sprintf("dec=%d trial=%d | %s", length(d1), length(t1), substr(o1, max(1, nchar(o1) - 400), nchar(o1))))
if (length(t1)) chk(setequal(ch1(t1[[1]]), sprintf("F0+S%02d", 1:5)) && any(vapply(t1[[1]]$rejected, function(z) identical(z$id, "XNOIC1") && grepl("IC", z$reason), logical(1))),
    "P1b 선택 = 배치 팩터 집합 5 · 기각 = IC 없음·축 제외(사유 보존 · 기각된 제안까지 센다)")
chk(j1$n_att == 5L && !length(j1$missing) && !length(j1$extra) && all(vapply(j1$att, function(a) identical(a$design$design_source, "rule_asof"), logical(1))),
    "P1c 등록 칸 5 ↔ cell_registered 5 조인 100% · 원장 attempt$design = rule_asof(선정기 as-of)", paste(c(j1$missing, j1$extra), collapse = ","))

# 원장 재도출 — 등록된 칸의 측정 spec(원장 attempt → essence$spec)에서 픽 선택을 다시 만든다(기록과 독립)
spec_of <- function(a) tryCatch(fromJSON(a$essence$spec, simplifyVector = FALSE), error = function(e) NULL)
fset_of <- function(s) paste(sort(vapply(s$factors %||% list(), function(z) as.character(z$id %||% z$kind), character(1))), collapse = "+")
if (length(t1)) chk(setequal(vapply(j1$att, function(a) fset_of(spec_of(a)), character(1)), ch1(t1[[1]])),
    "P1d b1 픽 선택 = 원장 등록 칸의 측정 spec 팩터 집합(독립 재도출)")

cat("\n=== P2 B1 배치 — 픽커 미산출(격자 스냅샷 폴백) ===\n")
S2 <- mk_sbx("p2", "null"); mk_ledger(S2, list(mk_entry("T2", list())))
run_script(S2, "reinforce_auto_parallel.R")
t2 <- trl(S2, "b1_factor_pick"); j2 <- reg_join(S2, "T2", 0L)
chk(length(t2) == 1L && identical(t2[[1]]$scope$by, "full_sample_ic") && "factor_arms_fallback" %in% ev(S2),
    "P2a 폴백 경로도 b1_factor_pick 1건(by=full_sample_ic)")
chk(j2$n_att >= 1L && !length(j2$missing) && all(vapply(j2$att, function(a) identical(a$design$design_source, "rule_full_ic"), logical(1))),
    "P2b 폴백 칸 출처 = rule_full_ic(격자 스냅샷 = 전표본 선정) · 조인 100%", paste(j2$missing, collapse = ","))

cat("\n=== P3 B2 배치 — b2 pick · B1 승자 · 바닥 (원장 재도출 대조) ===\n")
S3 <- mk_sbx("p3"); mk_ledger(S3, list(mk_entry("T3", b1_set(S3, "T3"))))
o3 <- run_script(S3, "reinforce_auto_parallel.R")
t3p <- trl(S3, "b2_weight_pick"); t3w <- trl(S3, "block_winner"); t3f <- trl(S3, "floor"); j3 <- reg_join(S3, "T3", 5L)
E3 <- ent(S3, "T3"); B1a <- Filter(function(a) startsWith(a$cell_code, "B1_"), E3$attempts)
re_w1 <- B1a[[which.max(vapply(B1a, function(a) a$essence$port_t, numeric(1)))]]$cell_code
chk(length(t3p) == 1L && setequal(ch1(t3p[[1]]), c("hrp", "minvar", "erc", "cdar", "kelly")) &&
      all(vapply(j3$att, function(a) identical(a$design$design_source, "rule_catalog"), logical(1))) && j3$n_att == 5L && !length(j3$missing),
    "P3a b2_weight_pick 선택 = 배치 label 5 · 칸 출처 rule_catalog · 등록 조인 100%", sprintf("%d %s | %s", length(t3p), paste(j3$missing, collapse = ","), substr(o3, max(1, nchar(o3) - 300), nchar(o3))))
w1r <- Filter(function(r) identical(r$scope$block, "B1"), t3w)
chk(length(w1r) == 1L && identical(ch1(w1r[[1]]), re_w1) && identical(w1r[[1]]$scope$consumed_by, "B2"),
    sprintf("P3b block_winner(B1) 선택 = 원장 재도출 argmax port_t(%s) · consumed_by B2", re_w1), if (length(w1r)) ch1(w1r[[1]]) else "기록 없음")
if (length(t3p)) chk(setequal(vapply(j3$att, function(a) as.character(spec_of(a)$weighting$label %||% ""), character(1)), ch1(t3p[[1]])),
    "P3d b2 픽 선택 = 원장 등록 칸의 측정 spec weighting.label(독립 재도출)")
re_floor <- re_w1   # 이 entry 의 자격 칸 = B1 5칸(전부 현행 규약·k200_kq150·창 0) → 바닥 = port_t argmax
chk(length(t3f) == 1L && identical(ch1(t3f[[1]]), re_floor) && identical(t3f[[1]]$scope$floor_source, "attempt"),
    sprintf("P3c floor 선택 = 원장 재도출 자격 칸 argmax(%s) · floor_source attempt", re_floor), if (length(t3f)) ch1(t3f[[1]]) else "기록 없음")

cat("\n=== P4 B5 배치 — b5 pick · 바닥 기각 사유 ===\n")
S4 <- mk_sbx("p4")
a4 <- c(b1_set(S4, "T4"), lapply(6:10, function(k) mk_att(S4, "T4", k, sprintf("B2_%d", k), 1.2 + k / 100)),
        lapply(11:15, function(k) mk_att(S4, "T4", k, sprintf("B3_%d", k), 1.9, spec = list(universe = list(kind = "index", flag = "KQ150")))),
        lapply(c(32, 33, 34, 36, 42), function(k) mk_att(S4, "T4", k, sprintf("B6_%d", k), 1.0)))
for (i in seq_along(a4)) a4[[i]]$n <- i
mk_ledger(S4, list(mk_entry("T4", a4)))
run_script(S4, "reinforce_auto_parallel.R")
t4p <- trl(S4, "b5_overlay_pick"); t4f <- trl(S4, "floor"); j4 <- reg_join(S4, "T4", length(a4))
chk(length(t4p) == 1L && length(ch1(t4p[[1]])) >= 1L && all(startsWith(ch1(t4p[[1]]), "ov_stub_")) &&
      all(vapply(Filter(function(a) !isTRUE(grepl("B5_31", a$cell_code)), j4$att), function(a) identical(a$design$design_source, "rule_catalog"), logical(1))),
    "P4a b5_overlay_pick 선택 = 오버레이 arm · 칸 출처 rule_catalog", if (length(t4p)) paste(ch1(t4p[[1]]), collapse = ",") else "없음")
rej4 <- if (length(t4f)) vapply(t4f[[1]]$rejected, function(z) sprintf("%s=%s", z$id, z$reason), character(1)) else character(0)
chk(length(t4f) == 1L && all(sprintf("B3_%d", 11:15) %in% sub("=.*$", "", rej4)) && all(grepl("자격 미달", rej4[startsWith(rej4, "B3_")])),
    "P4b floor 기각에 B3 유니버스 처치 칸 5 · 사유 '바닥 자격 미달'(port_t 최고여도 소비 안 함)", paste(utils::head(rej4, 6), collapse = " | "))
chk(!length(j4$missing), "P4c 등록 조인 100%", paste(j4$missing, collapse = ","))
own_arms <- unlist(lapply(Filter(function(a) !grepl("B5_31", a$cell_code), j4$att), function(a) {
  ov <- spec_of(a)$overlay_cell %||% list(); L <- if (!is.null(ov$arm_id)) list(ov) else ov   # 단일 층(객체) · 층 리스트 모두
  vapply(L, function(z) as.character(z$arm_id %||% ""), character(1)) }))
if (length(t4p)) chk(setequal(own_arms, ch1(t4p[[1]])), "P4d b5 픽 선택 = 원장 등록 칸의 측정 spec overlay_cell arm(독립 재도출)",
                     paste(own_arms, collapse = ","))

cat("\n=== P5 B4 배치 — 승자 = 조립된 결합 축(로그·격자 재도출) · 바닥 기록 없음 ===\n")
S5 <- mk_sbx("p5")
pass <- list(adversary = list(verdict = "pass", at = "2026-09-24T00:00:00+0900"))
a5 <- c(b1_set(S5, "T5"), lapply(6:10, function(k) mk_att(S5, "T5", k, sprintf("B2_%d", k), 1.2 + k / 100)),
        lapply(11:15, function(k) mk_att(S5, "T5", k, sprintf("B3_%d", k), 1.1, spec = list(universe = list(kind = "index", flag = "K200")))),
        lapply(c(32, 33, 34, 36, 42), function(k) mk_att(S5, "T5", k, sprintf("B6_%d", k), 1.0)),
        lapply(16:20, function(k) mk_att(S5, "T5", k, sprintf("B5_%d", k), 1.3, spec = list(overlay = list(list(kind = "arm", arm_id = sprintf("ov%d", k))),
                                                                                              overlay_cell = list(list(kind = "arm", arm_id = sprintf("ov%d", k)))),
                                         extra = if (k == 18L) pass else list())),
        lapply(37:41, function(k) mk_att(S5, "T5", k, sprintf("B7_%d", k), 1.0)))
for (i in seq_along(a5)) a5[[i]]$n <- i
mk_ledger(S5, list(mk_entry("T5", a5)))
o5 <- run_script(S5, "reinforce_auto_parallel.R")
t5w <- trl(S5, "block_winner"); blks <- vapply(t5w, function(r) as.character(r$scope$block), character(1))
## ★기대값 = 소비자 재도출(10-03 P5A) — 리터럴 4건(B1·B2·B3·B5)은 B4-SIX(B6·B7 축)·B3 진단(exclude_axis)에서 틀린다.
##   ① 러너가 이 tick 에 실제 조립한 B4 칸의 use(로그 b4_axes · 칸마다 1줄) 합집합 ② 격자 B4 칸 use 합집합 − 진단 블록(로그 b4_combo_plan trimmed)
lg5 <- rdj(file.path(S5, ".cache/reinforce_auto_log.jsonl"))
use5 <- unique(unlist(lapply(Filter(function(z) identical(z$event, "b4_axes"), lg5), function(z) strsplit(as.character(z$use %||% ""), "+", fixed = TRUE)[[1]])))
use5 <- use5[nzchar(use5)]
trim5 <- unique(unlist(lapply(Filter(function(z) identical(z$event, "b4_combo_plan"), lg5), function(z) strsplit(as.character(z$trimmed %||% ""), ",", fixed = TRUE)[[1]])))
grid5 <- local({ pg <- fromJSON(file.path(S5, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
  b4 <- Filter(function(b) identical(as.character(b$id %||% "")[1], "B4"), pg$blocks)
  unique(unlist(lapply(if (length(b4)) b4[[1]]$cells else list(), function(c) as.character(unlist((c$combo %||% list())$use))))) })
chk(length(use5) >= 2L && setequal(blks, use5) && length(t5w) == length(use5) && all(vapply(t5w, function(r) identical(r$scope$consumed_by, "B4"), logical(1))),
    "P5a B4 배치 → block_winner = 조립된 B4 칸 use 합집합(로그 b4_axes) · 건수 일치 · consumed_by B4",
    sprintf("winner=%s | b4_axes use=%s", paste(sort(blks), collapse = ","), paste(sort(use5), collapse = ",")))
chk(length(grid5) >= 2L && setequal(use5, setdiff(grid5, trim5)),
    "P5d 조립 축 = 격자 B4 칸 use 합집합 − 진단 블록(b4_combo_plan trimmed · 격자 독립 재도출)",
    sprintf("grid=%s trimmed=%s use=%s", paste(sort(grid5), collapse = ","), paste(trim5, collapse = ","), paste(sort(use5), collapse = ",")))
w5 <- Filter(function(r) identical(r$scope$block, "B5"), t5w)
chk(length(w5) == 1L && identical(ch1(w5[[1]]), "B5_18") &&
      all(vapply(Filter(function(z) z$id != "B5_18", w5[[1]]$rejected), function(z) grepl("적대검증", z$reason), logical(1))),
    "P5b B5 승자 = 적대검증 pass 칸(B5_18) 하나 · 나머지 기각 사유 '적대검증 pass 아님'", if (length(w5)) ch1(w5[[1]]) else "없음")
chk(!length(trl(S5, "floor")), "P5c B4 배치는 floor 기록 없음(바닥을 소비하지 않는다)")

cat("\n=== P6 승격 · 비승격 (next_paper) ===\n")
S6 <- mk_sbx("p6")
a6 <- lapply(1:5, function(k) mk_att(S6, "T6", k, sprintf("B1_%d", k), 1.0 + k / 10, grade = if (k == 5) "B" else "C"))
mk_ledger(S6, list(mk_entry("T6", a6, status = "exhausted")))
o6 <- run_script(S6, "reinforce_auto_next_paper.R")
t6 <- trl(S6, "promote"); ids6 <- vapply(led(S6)$entries, function(e) e$base_id, character(1))
chk(length(t6) == 1L && identical(ch1(t6[[1]]), "promote") && "T6_promo1" %in% ids6 && identical(t6[[1]]$scope$new_base_id, "T6_promo1"),
    "P6a 승격 → promote(chosen promote · new_base_id = 원장에 실재하는 자식)", sprintf("%d %s | %s", length(t6), paste(ids6, collapse = ","), substr(o6, max(1, nchar(o6) - 300), nchar(o6))))
S6b <- mk_sbx("p6b")
mk_ledger(S6b, list(mk_entry("T6B", lapply(1:5, function(k) mk_att(S6b, "T6B", k, sprintf("B1_%d", k), 1.0 + k / 10)), status = "exhausted")))
run_script(S6b, "reinforce_auto_next_paper.R")
t6b <- trl(S6b, "promote")
chk(length(t6b) == 1L && identical(ch1(t6b[[1]]), "no_promote") && !("T6B_promo1" %in% vapply(led(S6b)$entries, function(e) e$base_id, character(1))) &&
      nzchar(Filter(function(z) identical(z$id, "promote"), t6b[[1]]$rejected)[[1]]$reason %||% ""),
    "P6b 등급 미달 → promote(chosen no_promote) · 자식 없음 · 기각된 '승격' 후보에 best 서술")

cat("\n=== P7 결합 (rf_combination_launch) ===\n")
S7 <- mk_sbx("p7")
mk_base <- function(S, bid, url) { art <- file.path(S, "stage_artifacts/replication", paste0("base_", bid)); dir.create(art, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(list(essence = list(port_t = 1.5), replication = list(source_paper = list(url = url, title = bid))), auto_unbox = TRUE), file.path(art, "authoritative_remeasure.json"))
  eng <- file.path(S, "engines", paste0(bid, ".R")); writeLines("# engine stub", eng); list(art = art, eng = eng) }
b7a <- mk_base(S7, "CA", "https://arxiv.org/abs/0000.00001"); b7b <- mk_base(S7, "CB", "https://arxiv.org/abs/0000.00002")
e7 <- function(bid, b) { e <- mk_entry(bid, list(mk_att(S7, bid, 1, "B1_1", 2.0)), status = "exhausted"); e$engine_path <- b$eng; e$base_artifacts <- b$art
  e$measurement_axis <- "exec_v2_close_t1"; e }
mk_ledger(S7, list(e7("CA", b7a), e7("CB", b7b)))
o7 <- run_script(S7, "rf_combination_launch.R")
t7 <- trl(S7, "combination"); rq <- tryCatch(fromJSON(file.path(S7, "06_Registry/replication_request.json"), simplifyVector = FALSE), error = function(e) NULL)
chk(length(t7) == 1L && !is.null(rq) && identical(ch1(t7[[1]]), rq$combo$setkey) && identical(t7[[1]]$base_id, "program"),
    "P7 결합 → combination(chosen = 발행 요청 setkey)", sprintf("%d %s | %s", length(t7), rq$combo$setkey %||% "요청 없음", substr(o7, max(1, nchar(o7) - 300), nchar(o7))))

cat("\n=== P8 조인 — 전 샌드박스 ===\n")
SB <- list(S1 = S1, S2 = S2, S3 = S3, S4 = S4, S5 = S5, S6 = S6, S6b = S6b, S7 = S7)
for (nm in names(SB)) {
  S <- SB[[nm]]
  D <- Filter(function(r) r$kind %in% c("block_winner", "floor", "b1_factor_pick", "b2_weight_pick", "b5_overlay_pick", "promote", "combination"), dec(S))
  Tt <- Filter(function(r) r$kind %in% c("block_winner", "floor", "b1_factor_pick", "b2_weight_pick", "b5_overlay_pick", "promote", "combination"), trl(S))
  dd <- vapply(D, function(r) r$decision_id, character(1)); tt <- vapply(Tt, function(r) r$decision_id %||% "", character(1))
  bad <- ev(S)[ev(S) %in% BADEV]
  chk(length(dd) >= 1L && setequal(dd, tt) && !anyDuplicated(dd) && !length(bad),
      sprintf("P8 %s 결정 %d ↔ 시행 %d 조인 100%% · 중복 id 0 · 실패 이벤트 0", nm, length(dd), length(tt)), paste(c(setdiff(dd, tt), setdiff(tt, dd), bad), collapse = ","))
}

cat("\n=== P9 rf_reopen_entry 종단 — 절단 소진 → 복원 + 되살림 → 잘렸던 칸 배치 ===\n")
S9 <- mk_sbx("p9")
prog <- fromJSON(file.path(S9, "06_Registry/reinforce_program.json"), simplifyVector = FALSE); prog_full <- prog
prog$blocks <- lapply(Filter(function(b) b$id %in% c("B1", "B2"), prog$blocks), function(b) { if (identical(b$id, "B2")) { b$cells <- b$cells[1]; b$n <- 1L }; b })
writeLines(toJSON(prog, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S9, "06_Registry/reinforce_program.json"))
a9 <- c(b1_set(S9, "T9"), list(mk_att(S9, "T9", 6, "B2_6", 1.2)))
mk_ledger(S9, list(mk_entry("T9", a9)))
run_script(S9, "reinforce_auto_parallel.R")
chk(identical(ent(S9, "T9")$status, "exhausted") && "grid_consumed" %in% ev(S9),
    "P9a 절단된 격자(B1 5 + B2 1)를 다 쓴 entry → grid_consumed → exhausted(러너가 실현한 효과)", ent(S9, "T9")$status)
writeLines(toJSON(prog_full, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S9, "06_Registry/reinforce_program.json"))   # 롤백 = 절단 이전 계획
led_env <- new.env(); invisible(capture.output(sys.source(file.path(S9, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = led_env)))
Sys.setenv(QVEST_RF_CLAIM = file.path(S9, ".cache/claim_e2e"))
invisible(capture.output(r9 <- led_env$rf_reopen_entry(1L, "T9", "절단 롤백(샌드박스 드릴)", "M-ORG-20260925T220000000-1-abcdef", root = S9)))
invisible(capture.output(r9b <- led_env$rf_reopen_entry(1L, "T9", "두 번째", "M-ORG-20260925T220000000-1-abcdef", root = S9)))
Sys.unsetenv("QVEST_RF_CLAIM")
chk(isTRUE(r9$written) && !isTRUE(r9b$written) && identical(ent(S9, "T9")$status, "active"), "P9b rf_reopen_entry → active · 두 번째 호출 멱등(쓰기 0)")
run_script(S9, "reinforce_auto_parallel.R")
E9 <- ent(S9, "T9"); new9 <- vapply(Filter(function(a) as.integer(a$n) > 6L, E9$attempts), function(a) a$cell_code, character(1))
chk(length(new9) >= 1L && all(startsWith(new9, "B2_")) && !("B2_6" %in% new9),
    "P9c 다음 tick 이 잘렸던 칸(B2_7…)을 배치·등록 — 롤백이 러너가 실현한 소진까지 되돌린다", paste(new9, collapse = ","))

cat("\n=== M 돌연변이 — 러너 사본의 기록 줄을 지우면 위 단정이 red ===\n")
mutate <- function(S, pat) { p <- file.path(S, "02_Infrastructure/ops/reinforce_auto_parallel.R"); s <- readLines(p, warn = FALSE, encoding = "UTF-8")
  hit <- grep(pat, s, fixed = TRUE); if (length(hit) != 1L) return(FALSE); s <- s[-hit]; writeLines(s, p, useBytes = TRUE); TRUE }
SM1 <- mk_sbx("m1"); mk_ledger(SM1, list(mk_entry("TM1", b1_set(SM1, "TM1"))))
if (!mutate(SM1, '.tl_try("cell_registered", rf_tp_cell_registered(')) ng("M1 돌연변이 적용 실패(cell_registered 줄)") else {
  run_script(SM1, "reinforce_auto_parallel.R"); jm <- reg_join(SM1, "TM1", 5L)
  chk(jm$n_att >= 1L && length(jm$missing) == jm$n_att, "M1 [돌연변이] cell_registered 기록 줄 삭제 → 등록 조인 0% = P1c·P3a·P8 이 이 결함을 잡는다",
      sprintf("att=%d missing=%d", jm$n_att, length(jm$missing)))
}
SM2 <- mk_sbx("m2"); mk_ledger(SM2, list(mk_entry("TM2", b1_set(SM2, "TM2"))))
if (!mutate(SM2, '.tlw_note(bid, "win", list(w), v = v, by = by)')) ng("M2 돌연변이 적용 실패(승자 메모 줄)") else {
  run_script(SM2, "reinforce_auto_parallel.R")
  wm <- Filter(function(r) identical(r$scope$block, "B1"), trl(SM2, "block_winner"))
  chk(length(wm) == 1L && !identical(ch1(wm[[1]]), "B1_3"), "M2 [돌연변이] 승자 선택 메모 삭제 → 기록 선택 ≠ 원장 재도출(B1_3) = P3b 가 이 결함을 잡는다",
      if (length(wm)) ch1(wm[[1]]) else "기록 없음")
}

cat("\n=== Z 운영 무접촉 ===\n")
chk(identical(md5_prod(), PROD0), "Z1 운영 원장·결정 기록·시행 로그·요청·러너 로그 md5 전후 동일")
unlink(c(S1, S2, S3, S4, S5, S6, S6b, S7, S9, SM1, SM2), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_trial_log_producers","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
