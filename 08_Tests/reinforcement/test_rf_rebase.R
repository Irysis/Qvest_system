#!/usr/bin/env Rscript
#==============================================================================
# test_rf_rebase.R — P0-06 원장 rebase · 축 epoch + P0-12 원장 쪽(graduate · 결정 kind) 양방향 검사 (2026-09-24)
#
# 대상: reinforce_ledger.R::rf_rebase_essence(_batch) · rf_mark_axis_epoch(relabel_from · require_regime · claim) ·
#       rf_attempt_regime · rf_base_regime · rf_record_result(graduate=) · rf_graduate_entry · RF_DECISION_KINDS
# 계약(플랜 qvest-1-drifting-eclipse P0-06·P0-12 · 결정 EXEC-PRICE · PIT-C11-CONVENTIONS ⑧):
#   · 구 essence 는 essence_history[[구 regime]] 로 비트 그대로 이동(append-only · 덮어쓰기 거부) · 등급은 형제 판 essence_grade 만
#   · regime 이 다른 형제·형제 아닌 판·C11 표식 칸·핵심 지표 불일치·미측정 칸은 거부(원장 불변)
#   · 자식 parent$best_* 재계산 + parent_rebased_from · 러너 claim(idle) · CAS · 사후 재적재 대조(복원)
#   · 축 전환: 구판 무발화(원장 사본 재도출) → relabel_from 수리 · 새 축 자격 = 측정 칸 전부 regime · C11 칸은 목록화
#   · graduate=FALSE 면 A 기록 뒤에도 entry active 유지(양성 대조 TRUE = graduated)
#   · ★2026-09-24 수리(통합 검증 L-B1·L-B2): 실제 P0-05 판 모양(디렉터리 remeasure_<키> · measurement_regime{key, exec_price}
#     — regime 필드 없는 구 P0-05 판 포함)을 받는다(P16·P17) · 원장 essence = writer 조립(신원 키 + 형제 측정 키 · 구 보조 값 소멸)
#     · 측정 키 불일치(dsr 등)·허용 밖 키·신원 변조 거부(R17~R19) · essence_new 는 정본 조립기 rf_rebase_essence_from_sibling 로 만든다
# 격리: 합성 픽스처 root(tempdir)만 쓴다. QVEST_RF_CLAIM 을 지워 claim 도 픽스처 root/.cache 아래.
#       운영 원장은 **사본**만 읽는다(C 절 — 산출물 경로를 임시 거울로 옮긴 사본에 전수 rebase·전환 · 운영 md5 전후 불변).
# 구성:
#   S 정적(결정 kind · 서명) · G graduate · P 양성 대조 · R 위반 주입 · L 잠금·CAS·사후 검증 · A 축 전환
#   C 운영 원장 사본 재도출(구판 무발화 · 전수 rebase 수 = 대상 칸 수 · python 독립 비트 대조 · 결합 풀 크기 불변 · 축 skip 0)
#   M 돌연변이(자식 Rscript · RF_LEDGER_SRC=사본 · 병렬) → red · 대조(원본 사본) green
# env: RF_LEDGER_SRC(검사 대상 소스) · RF_REBASE_CORE_ONLY=1(자식: S/G/P/R/L/A 만) · QVEST_PY(python)
#==============================================================================
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- Sys.getenv("RF_LEDGER_SRC", file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
CORE <- identical(Sys.getenv("RF_REBASE_CORE_ONLY"), "1")
Sys.unsetenv("QVEST_RF_CLAIM")
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && nzchar(paste(why, collapse = ""))) paste0(" — ", paste(why, collapse = " ")) else "", "\n") }
sk <- function(m) { SKIP <<- SKIP + 1L; cat("  SKIP", m, "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d · 건너뜀 %d\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"rf_rebase","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
  quit(status = if (FAIL == 0L) 0L else 1L) }
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
md5 <- function(p) unname(tools::md5sum(p))
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
SEC <- { .s <- trimws(strsplit(Sys.getenv("RF_REBASE_ONLY", ""), ",", fixed = TRUE)[[1]]); .s[nzchar(.s)] }   # 자식 돌연변이: 표적 절만
run_sec <- function(x) !length(SEC) || x %in% SEC

invisible(capture.output(source(SRC, encoding = "UTF-8")))
if (!exists("rf_rebase_essence_batch") || !exists("rf_mark_axis_epoch")) { ng("S0 rebase/축 전환 writer 부재", SRC); finish() }

OP_L1 <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"); OP_L2 <- file.path(ROOT, "06_Registry/reinforce_ledger_l2.json")
OP_MD5 <- vapply(c(OP_L1, OP_L2), function(p) if (file.exists(p)) md5(p) else "", character(1))

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
wj <- function(x, f) { dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(x, auto_unbox = TRUE, digits = NA, null = "null", na = "null"), f, useBytes = TRUE) }
core <- function(pt, cm, sh = 0.9, cg = 0.21, dd = 0.52, oos = -0.1)
  list(portfolio_alpha_t_nw_lag3 = pt, net_sharpe = sh, cagr = cg, mdd = dd, calmar = cm, oos_retention = oos)
ess <- function(cc, pt, cm) list(cell_code = cc, block = sub("_.*$", "", cc), port_t = pt, net_sharpe = 0.978, cagr = 0.216,
                                 mdd = 0.571, calmar = cm, oos_retention = -0.387, dsr = 0.51, selection_type = "sweep",
                                 n_trials_cumulative = 45L, spec = "C:/x/.cache/rf_parallel/spec_FIX.json", source = "authoritative_remeasure.json")
att <- function(n, cc, grade, e, art, ...) { a <- list(n = as.integer(n), date = "20260920", cell_code = cc,
  idea = sprintf("[픽스처] %s — 모멘텀·가치", cc), keyword_axis = "multifactor", root_papers = list(), wt_id = NULL,
  evidence = "none", unmapped_families = list(), axiom_injected = TRUE, grade = grade, essence = e, artifacts = art,
  lessons = if (is.null(e)) NULL else sprintf("[%s] Grade %s · 교훈 서술", cc, grade),
  opened_at = "2026-09-20T10:00:00+0900", closed_at = "2026-09-20T10:30:00+0900")
  x <- list(...); for (k in names(x)) a[[k]] <- x[[k]]; a }
c11 <- list(list(flag = "pit_c11", verdict = "consumed", evidence = "픽스처 C11", source = "fix", policy = "p", marked_at = "2026-09-24T04:00:00+0900"))
mk_fx <- function(tag) {
  R <- file.path(tempdir(), sprintf("rfrb_%s_%d_%d", tag, Sys.getpid(), sample.int(1e6, 1L)))
  dir.create(file.path(R, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  R <- normalizePath(R, winslash = "/")
  A <- function(sub, mr = NULL) { d <- file.path(R, "art", sub); dir.create(d, recursive = TRUE, showWarnings = FALSE)
    x <- list(essence_grade = "B", strategy_name = sub); if (!is.null(mr)) x$measurement_regime <- mr
    wj(x, file.path(d, "authoritative_remeasure.json")); normalizePath(d, winslash = "/") }
  rem <- function(d, reg, cr, grade, mr = list(exec_price = reg), extra = list()) {
    x <- c(list(essence_grade = grade, essence = cr), extra); if (!is.null(mr)) x$measurement_regime <- mr
    wj(x, file.path(d, paste0("remeasure_", reg), "authoritative_remeasure.json")) }
  bP <- A("P_base"); rem(bP, "close_t1", core(1.2, 0.2), "C")
  p1 <- A("P1"); rem(p1, "close_t1", core(2.801, 0.402), "C"); rem(p1, "open_t1", core(2.905, 0.43), "B")
  p2 <- A("P2", mr = list(exec_price = "close_d_legacy", harness_md5 = "abc")); rem(p2, "close_t1", core(1.9, 0.28), "C")
  rem(p2, "open_t1", core(2.0, 0.29), "C", mr = list(exec_price = "close_t1"))          # 이름은 open_t1, 안은 close_t1 판
  p4 <- A("P4"); rem(p4, "close_t1", core(2.2, 0.31), "C")
  p5 <- A("P5"); rem(p5, "close_t1", core(2.3, 0.32), "B", extra = list(grade_base = "C"))
  p6 <- A("P6"); rem(p6, "close_t1", core(1.4, 0.19), "C")
  p7 <- A("P7"); rem(p7, "close_t1", core(1.6, 0.21), "C")
  p8 <- A("P8"); rem(p8, "close_t1", core(1.1, 0.15), "F", mr = NULL)
  p9 <- A("P9"); rem(p9, "close_t1", core(1.0, 0.16), "C")                    # measurement_regime 없는 형제
  c1 <- A("C1"); rem(c1, "close_t1", core(3.0, 0.44), "B")
  q1 <- A("Q1"); rem(q1, "close_t1", core(1.0, 0.1), "C")
  u1 <- A("U1")
  obj <- .rf_skeleton(1L)
  obj$current_axis <- "n_max_25"
  obj$axis_epochs <- list(list(epoch = "n_max_25", legacy = "legacy_double_selection_n3", switched_at = "2026-09-01T17:15:18+0900",
                               reason = "픽스처 구 전환", evidence = "e", entries_marked = 1L, note = "n"))
  ent <- function(bid, attempts, ...) { e <- list(base_id = bid, base_grade = "B", paper_key = "2002.06975", paper_id = "",
    base_artifacts = "", engine_path = "C:/x/engine.R", status = "exhausted", target_grade = "A", measurement_axis = "n_max_25",
    axis_valid = TRUE, attempts_used = length(attempts), attempts = attempts, judge = list(spawned = FALSE, verdict_path = NULL),
    opened_at = "2026-09-20T09:00:00+0900"); x <- list(...); for (k in names(x)) e[[k]] <- x[[k]]; e }
  obj$entries <- list(
    ent("FX_P", list(
      att(1, "B1_1", "B", ess("B1_1", 3.101, 0.451), p1),
      att(2, "B1_2", "C", ess("B1_2", 2.2, 0.3), p2),
      att(3, "B1_3", "NA (미결 — 픽스처)", NULL, NULL),
      att(4, "B1_4", "C", ess("B1_4", 2.5, 0.35), p4, vintage_flags = c11),
      att(5, "B2_6", "C", ess("B2_6", 2.4, 0.33), p5, grade_base = "F", retro = "rolling_defensive_v1",
          adversary = list(verdict = "fail", at = "2026-09-20T11:00:00+0900"),
          vintage_flags = list(list(flag = "fdb_202608_v1", verdict = "consumed", evidence = "e", source = "s", policy = "p", marked_at = "t"))),
      att(6, "B2_7", "C", ess("B2_7", 1.5, 0.2), p6,
          essence_history = list(close_d_legacy = list(essence = list(port_t = 9.999), grade = "Z", note = "선재 기록"))),
      att(7, "B2_8", "C", ess("B2_8", 1.7, 0.22), p7, vintage_flags = list(list(flag = "zz_qflag", verdict = "consumed", evidence = "e"))),
      att(8, "B2_9", "C", ess("B2_9", 1.3, 0.18), p8),
      att(9, "B4_23", "C", ess("B1_1", 1.2, 0.17), p9)),   # B4 결합 칸: 격자 좌표 ≠ essence 라벨(운영 원장 30칸 실측 형태)
      base_artifacts = bP),
    ent("FX_C", list(att(1, "B1_1", "B", ess("B1_1", 3.3, 0.47), c1)), status = "active",
        parent = list(base_id = "FX_P", depth = 1L, cell = "B1_1", best_port_t = 3.101, best_calmar = 0.451, promoted_at = "2026-09-20T12:00:00+0900"),
        carry = list(factors = list("M01"), source_cell = "B1_1")),
    ent("FX_Q", list(att(1, "B5_31", "C", ess("B5_31", 1.0, 0.12), q1, vintage_flags = c11))),
    ent("FX_U", list(att(1, "B1_1", "C", ess("B1_1", 0.9, 0.11), u1))),
    ent("FX_L", list(), measurement_axis = "legacy_double_selection_n3", axis_valid = FALSE, axis_marked_at = "2026-09-01T17:15:18+0900"))
  .rf_write(obj, 1L, R)
  list(R = R, p = .rf_path(1L, R), art = list(bP = bP, p1 = p1, p2 = p2, p4 = p4, p5 = p5, p6 = p6, p7 = p7, p8 = p8, p9 = p9, c1 = c1, q1 = q1, u1 = u1))
}
remp <- function(d, reg) file.path(d, paste0("remeasure_", reg), "authoritative_remeasure.json")
#' 드라이버(rf_rebase_driver.R)와 같은 방식 — 정본 조립기 rf_rebase_essence_from_sibling(구 essence, 형제 판)으로 essence_new.
#'   (구판 검사는 구 essence 에서 핵심 6지표만 바꿨다 — 그 모양이 곧 L-B2 결함(dsr 등 구 값 잔존)이라 이제 writer 가 거부한다: R17)
item <- function(F, bid, n, d, reg = "close_t1", path = remp(d, reg), tweak = NULL, ...) {
  L <- rf_load(1L, F$R); e <- L$entries[[.rf_find(L, bid)]]
  j <- if (identical(n, "base")) NA else which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  en <- if (identical(n, "base")) NULL else {
    old <- e$attempts[[j]][["essence"]]
    if (is.null(old)) NULL else if (file.exists(path)) rf_rebase_essence_from_sibling(old, path) else old }
  if (is.function(tweak)) en <- tweak(en)
  c(list(base_id = bid, n = n, essence_new = en, regime = reg, provenance = list(remeasure_path = path, producer = "test_rf_rebase")), list(...))
}
RB <- function(F, items, ...) rf_rebase_essence_batch(1L, items, root = F$R, wait_s = 1, poll_s = 0.2, ...)
EP <- function(F, ...) rf_mark_axis_epoch(1L, "exec_v2_close_t1", "n_max_25@close_d_legacy", "픽스처 전환", "픽스처 근거",
                                          root = F$R, wait_s = 1, poll_s = 0.2, ...)
getA <- function(L, bid, n) { e <- L$entries[[.rf_find(L, bid)]]; e$attempts[[which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))]] }
getE <- function(L, bid) L$entries[[.rf_find(L, bid)]]
#' 검사 자체 보호 투영(writer 의 .rf_rb_strip 과 독립 구현) — 허용 필드만 뺀다
proj <- function(L, att_keys = character(0), base_ids = character(0), kid_ids = character(0)) {
  L$last_updated <- NULL
  L$entries <- lapply(L$entries, function(e) {
    if (e$base_id %in% base_ids) e[c("base_grade", "base_measurement_regime", "base_remeasure", "base_essence_history", "base_rebase_log")] <- NULL
    if (e$base_id %in% kid_ids) { e$parent <- e$parent[!grepl("^best_", names(e$parent))]; e["parent_rebased_from"] <- NULL }
    e$attempts <- lapply(e$attempts, function(a) {
      if (paste0(e$base_id, "#", a$n) %in% att_keys)
        a[c("essence", "grade", "grade_base", "retro", "retro_inherited", "measurement_regime", "essence_history", "rebase_log")] <- NULL
      a })
    e })
  L
}
code_of <- function(e) if (is.character(e) && grepl("거부 #[0-9]+ [^ ]+ \\[[^]]+\\]", e)) sub(".*거부 #[0-9]+ [^ ]+ \\[([^]]+)\\].*", "\\1", e) else ""

OLD_EPOCH_SRC <- c(   # 수리 전 원문 표본(2026-09-24 이전 reinforce_ledger.R:451-476) — 무발화 재도출용. 운영 코드가 아니다.
'.old_mark_axis_epoch <- function(layer, epoch, legacy, reason, evidence, root = .rf_root()) {',
'  obj <- rf_load(layer, root); now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); n_marked <- 0L',
'  for (i in seq_along(obj$entries)) {',
'    if (is.null(obj$entries[[i]]$measurement_axis)) {',
'      obj$entries[[i]]$measurement_axis <- legacy; obj$entries[[i]]$axis_valid <- FALSE',
'      obj$entries[[i]]$axis_marked_at <- now; n_marked <- n_marked + 1L } }',
'  obj$axis_epochs <- c(obj$axis_epochs %||% list(), list(list(epoch = epoch, legacy = legacy, switched_at = now,',
'    reason = reason, evidence = evidence, entries_marked = n_marked)))',
'  obj$current_axis <- epoch; .rf_write(obj, layer, root); invisible(n_marked) }')
eval(parse(text = OLD_EPOCH_SRC))

# ══ S 정적 ═══════════════════════════════════════════════════════════════════
if (run_sec("S")) {
cat("\n=== S 결정 kind · 서명 ===\n")
chk(all(c("a_eligibility", "prereg_verdict") %in% RF_DECISION_KINDS), "S1 RF_DECISION_KINDS 에 a_eligibility · prereg_verdict")
Sd <- file.path(tempdir(), sprintf("rfrb_dec_%d", Sys.getpid())); dir.create(file.path(Sd, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
e1 <- err_of(rf_record_decision("a_eligibility", "FX_P", list(list(id = "B1_1", rank = 1L, reason = "held:legacy_regime")), "none",
                                rule = "rf_a_eligibility", root = Sd))
e2 <- err_of(rf_record_decision("prereg_verdict", "EXP_1", list(list(id = "confirmed", rank = 1L)), "confirmed", rule = "rf_prereg_verdict", root = Sd))
dl <- rf_read_decisions(Sd)
chk(is.na(e1) && is.na(e2) && length(dl) == 2L && identical(vapply(dl, function(x) x$kind, ""), c("a_eligibility", "prereg_verdict")),
    "S2 두 kind 가 샌드박스 jsonl 에 기록(미등재 stop 없음)", c(e1, e2))
fm <- formals(rf_record_result)
chk("graduate" %in% names(fm) && isTRUE(fm$graduate), "S3 rf_record_result(graduate = TRUE) 기본값 — 구판 비트 동일")
chk(identical(names(formals(rf_rebase_essence))[1:6], c("layer", "base_id", "n", "essence_new", "regime", "provenance")),
    "S4 rf_rebase_essence(layer, base_id, n, essence_new, regime, provenance) 서명")
chk(all(c("relabel_from", "require_regime", "claim", "dry_run") %in% names(formals(rf_mark_axis_epoch))), "S5 rf_mark_axis_epoch 수리 인자")
}

# ══ G graduate ═══════════════════════════════════════════════════════════════
if (run_sec("G")) {
cat("\n=== G graduate ===\n")
Gd <- file.path(tempdir(), sprintf("rfrb_g_%d", Sys.getpid())); dir.create(file.path(Gd, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
pp <- list(list(url = "https://arxiv.org/abs/2002.06975"))
invisible(capture.output({
  rf_open_entry(1L, "G_T", "B", root = Gd); rf_append_attempt(1L, "G_T", "a", "multifactor", pp, root = Gd)
  rf_record_result(1L, "G_T", 1L, "A", essence = list(port_t = 3.1), root = Gd)
  rf_open_entry(1L, "G_F", "B", root = Gd); rf_append_attempt(1L, "G_F", "a", "multifactor", pp, root = Gd)
  rf_record_result(1L, "G_F", 1L, "A", essence = list(port_t = 3.2), root = Gd, graduate = FALSE)
}))
LG <- rf_load(1L, Gd)
chk(identical(getE(LG, "G_T")$status, "graduated"), "G1 양성 대조 — graduate 기본(TRUE) A → graduated")
chk(identical(getE(LG, "G_F")$status, "active") && identical(getA(LG, "G_F", 1)$grade, "A") && isTRUE(getA(LG, "G_F", 1)$graduate_deferred),
    "G2 graduate=FALSE — A 기록 · entry active 유지 · graduate_deferred 표식")
e <- err_of(capture.output(rf_append_attempt(1L, "G_F", "다음 칸", "weighting", pp, root = Gd)))
chk(is.na(e) && getE(rf_load(1L, Gd), "G_F")$attempts_used == 2L, "G3 보류 A 의 entry 가 다음 칸을 등록(탐색 계속)", e)
invisible(capture.output(rf_record_result(1L, "G_F", 2L, "B", essence = list(port_t = 2), root = Gd, graduate = FALSE)))
chk(is.null(getA(rf_load(1L, Gd), "G_F", 2)$graduate_deferred), "G4 graduate=FALSE 라도 A 가 아니면 표식 없음")
chk(!is.na(err_of(rf_graduate_entry(1L, "G_F", 2L, "사유", root = Gd))), "G5 A 아닌 시도로 졸업 거부")
chk(!is.na(err_of(rf_graduate_entry(1L, "G_F", 1L, "", root = Gd))), "G6 사유 없는 졸업 거부")
invisible(capture.output(rf_graduate_entry(1L, "G_F", 1L, "적대검증 pass · 창 규칙 통과", root = Gd)))
LG <- rf_load(1L, Gd); g <- getE(LG, "G_F")
chk(identical(g$status, "graduated") && identical(g$graduated_by$from_status, "active") && nzchar(getA(LG, "G_F", 1)$graduate_released_at %||% ""),
    "G7 rf_graduate_entry — 보류 A 졸업(graduated_by · released_at)")
m0 <- md5(.rf_path(1L, Gd)); invisible(capture.output(rf_graduate_entry(1L, "G_F", 1L, "재호출", root = Gd)))
chk(identical(md5(.rf_path(1L, Gd)), m0), "G8 이미 graduated 면 멱등(쓰지 않음)")
invisible(capture.output({ rf_open_entry(1L, "G_P", "B", root = Gd); rf_append_attempt(1L, "G_P", "a", "multifactor", pp, root = Gd)
  rf_record_result(1L, "G_P", 1L, "A", essence = list(port_t = 3), root = Gd, graduate = FALSE); rf_park_entry(1L, "G_P", "도훈 결정", root = Gd) }))
chk(!is.na(err_of(rf_graduate_entry(1L, "G_P", 1L, "사유", root = Gd))), "G9 parked entry 는 졸업시키지 않는다")
}

# ══ P 양성 대조 ══════════════════════════════════════════════════════════════
if (run_sec("P")) {
cat("\n=== P 양성 대조 ===\n")
F <- mk_fx("p"); raw0 <- readLines(F$p, warn = FALSE, encoding = "UTF-8"); L0 <- rf_load(1L, F$R); m0 <- md5(F$p)
res <- NULL; e <- err_of(invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 1L, F$art$p1))))))
L1 <- rf_load(1L, F$R); a0 <- getA(L0, "FX_P", 1); a1 <- getA(L1, "FX_P", 1)
chk(is.na(e) && isTRUE(res$written) && res$n_rebased == 1L, "P1 rebase 1칸 기록", e)
h <- a1$essence_history$close_d_legacy
chk(identical(h$essence, a0$essence) && identical(h$grade, a0$grade) &&
    identical(as.character(toJSON(h$essence, auto_unbox = TRUE, digits = NA)), as.character(toJSON(a0$essence, auto_unbox = TRUE, digits = NA))),
    "P2 구 essence·grade → essence_history[[close_d_legacy]] 비트 동일(파싱 값 identical + JSON 텍스트 동일)")
chk(identical(a1$grade, "C") && isTRUE(abs(a1$essence$port_t - 2.801) < 1e-12) && isTRUE(abs(a1$essence$calmar - 0.402) < 1e-12) &&
    identical(a1$essence$spec, a0$essence$spec), "P3 새 essence = 형제 판 값 · 등급 = 형제 판 essence_grade(C) · 신원 필드(spec) 보존")
chk(is.null(a1$essence$dsr) && is.null(a1$essence$selection_type) && is.null(a1$essence$n_trials_cumulative) &&
    isTRUE(abs(h$essence$dsr - 0.51) < 1e-12) && identical(h$essence$n_trials_cumulative, 45L),
    "P3b ★L-B2 — 형제 판에 없는 측정 키(dsr·selection_type·N)는 새 essence 에서 빠진다(구 값 0.51·45 는 history 에만)",
    sprintf("dsr=%s N=%s", format(a1$essence$dsr %||% "NULL"), format(a1$essence$n_trials_cumulative %||% "NULL")))
chk(identical(a1$measurement_regime$regime, "close_t1") && identical(a1$measurement_regime$remeasure_md5, md5(remp(F$art$p1, "close_t1"))) &&
    identical(h$regime_basis, "pre_p0_01") && length(a1$rebase_log) == 1L, "P4 measurement_regime 갱신(regime·형제 md5) · 구 regime 재도출 근거 pre_p0_01 · rebase_log 1")
kc <- getE(L1, "FX_C")
chk(isTRUE(abs(kc$parent$best_port_t - 2.801) < 1e-12) && isTRUE(abs(kc$parent$best_calmar - 0.402) < 1e-12) &&
    length(kc$parent_rebased_from) == 1L && isTRUE(abs(kc$parent_rebased_from[[1]]$before$best_port_t - 3.101) < 1e-12) &&
    identical(kc$parent$cell, "B1_1") && identical(kc$parent$promoted_at, "2026-09-20T12:00:00+0900"),
    "P5 자식 parent$best_* 재계산 + parent_rebased_from(구값) · cell·promoted_at 불변")
chk(identical(proj(L1, "FX_P#1", kid_ids = "FX_C"), proj(L0, "FX_P#1", kid_ids = "FX_C")),
    "P6 검사 자체 보호 투영 — 허용 필드 밖(다른 칸·entry·축·결합 검토) 불변")
cl <- file.path(F$R, ".cache", "reinforce_auto.claim")
chk(!dir.exists(cl) || file.exists(file.path(cl, "released.json")), "P7 성공 후 claim 해제")
m1 <- md5(F$p); invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 1L, F$art$p1)))))
chk(res$n_already == 1L && !isTRUE(res$written) && identical(md5(F$p), m1), "P8 같은 판 재호출 = 멱등(쓰지 않음)")
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 1L, F$art$p1, reg = "open_t1")))))
L2 <- rf_load(1L, F$R); a2 <- getA(L2, "FX_P", 1)
chk(isTRUE(res$written) && identical(a2$essence_history$close_d_legacy, a1$essence_history$close_d_legacy) &&
    identical(a2$essence_history$close_t1$essence, a1$essence) && identical(a2$grade, "B") && length(a2$rebase_log) == 2L,
    "P9 두 번째 rebase(close_t1→open_t1) — 기존 history 비트 보존 + close_t1 판 추가(append-only)")
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 2L, F$art$p2)))))
a22 <- getA(rf_load(1L, F$R), "FX_P", 2)
chk(identical(a22$essence_history$close_d_legacy$regime_basis, "auth_exec_price"), "P10 P0-01 이후 auth 의 exec_price 로 구 regime 재도출")
a50 <- getA(L0, "FX_P", 5)
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 5L, F$art$p5)))))
a5 <- getA(rf_load(1L, F$R), "FX_P", 5)
chk(identical(a5$essence_history$close_d_legacy$retro, "rolling_defensive_v1") && identical(a5$essence_history$close_d_legacy$grade_base, "F") &&
    is.null(a5$retro) && identical(a5$grade_base, "C") && identical(a5$grade, "B") &&
    identical(a5$lessons, a50$lessons) && identical(a5$adversary, a50$adversary) && identical(a5$vintage_flags, a50$vintage_flags),
    "P11 구 규약 파생 필드(grade_base·retro)는 history 로 · lessons·adversary·vintage_flags 는 불변")
b0 <- getE(L0, "FX_P")$base_grade
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", "base", F$art$bP)))))
eb <- getE(rf_load(1L, F$R), "FX_P")
chk(isTRUE(res$written) && identical(eb$base_grade, "C") && identical(eb$base_essence_history$close_d_legacy$base_grade, b0) &&
    identical(eb$base_measurement_regime$regime, "close_t1") && identical(eb$base_remeasure$md5, md5(remp(F$art$bP, "close_t1"))),
    "P12 기저 rebase — base_grade = 형제 판 등급 · 구 base_grade → base_essence_history · base_remeasure(경로·md5)")
kb <- getE(rf_load(1L, F$R), "FX_C")
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 9L, F$art$p9)))))
ka <- getE(rf_load(1L, F$R), "FX_C")
chk(isTRUE(res$written) && res$n_children == 0L && identical(ka$parent, kb$parent) && length(ka$parent_rebased_from) == length(kb$parent_rebased_from),
    "P14 B4 칸(격자 B4_23 · essence B1_1) — essence 라벨로 대조해 rebase 허용 · 같은 라벨의 다른 칸(port_t 불일치)을 자식 승자로 오인하지 않음")
F2 <- mk_fx("dry"); m0 <- md5(F2$p)
invisible(capture.output(res <- RB(F2, list(item(F2, "FX_P", 1L, F2$art$p1)), dry_run = TRUE)))
chk(res$n_rebased == 1L && !isTRUE(res$written) && identical(md5(F2$p), m0) && !dir.exists(file.path(F2$R, ".cache", "reinforce_auto.claim")),
    "P13 dry_run — 검증·결과만(원장·claim 무접촉)")
# ── P15~P17 ★실제 P0-05 판 모양(L-B1) + 측정 키 전부 형제 값(L-B2) ──────────────────────────────────────────────
#   P0-05(remeasure_from_holdings.R) 판: 디렉터리 remeasure_<exec>_<md5 8> · measurement_regime{regime = key, key, exec_price, selection_type,
#   n_trials_cumulative} · 최상위 selection_type·n_trials_cumulative·dsr · essence{portfolio_alpha_t_nw_lag3, …, dsr, net_ir}
F3 <- mk_fx("p05")
KEY <- "close_t1_5562284e"
p05 <- function(d, key, with_regime = TRUE, dsr = 0.555, nt = 11L) {
  mr <- list(key = key, exec_price = sub("_[0-9a-f]{8}$", "", key), selection_type = "sweep", n_trials_cumulative = nt,
             n_trials_basis = "argument(D-A 재집계)")
  if (with_regime) mr$regime <- key
  x <- list(status = "OK", kind = "remeasure_from_holdings", essence_grade = "C", selection_type = "sweep", n_trials_cumulative = nt,
            dsr = dsr, essence = c(core(1.895, 0.301), list(dsr = dsr, net_ir = 0.44)), measurement_regime = mr)
  wj(x, file.path(d, paste0("remeasure_", key), "authoritative_remeasure.json"))
}
p05(F3$art$p1, KEY)
L0 <- rf_load(1L, F3$R)
it <- item(F3, "FX_P", 1L, F3$art$p1, reg = KEY)
e <- err_of(invisible(capture.output(res <- RB(F3, list(it)))))
a1 <- getA(rf_load(1L, F3$R), "FX_P", 1)
chk(is.na(e) && isTRUE(res$written) && identical(a1$measurement_regime$regime, KEY) && identical(a1$measurement_regime$exec_price, "close_t1"),
    "P15 ★L-B1 실제 P0-05 판(remeasure_<키> · regime=키) — regime 인자 = 키로 rebase · 원장 표식 regime=키 · exec_price=close_t1", e)
chk(isTRUE(abs(a1$essence$dsr - 0.555) < 1e-12) && identical(a1$essence$selection_type, "sweep") && identical(a1$essence$n_trials_cumulative, 11L) &&
    isTRUE(abs(a1$essence$net_ir - 0.44) < 1e-12) && identical(a1$essence$spec, getA(L0, "FX_P", 1)$essence$spec) &&
    isTRUE(abs(a1$essence_history$close_d_legacy$essence$dsr - 0.51) < 1e-12),
    "P16 ★L-B2 측정 키 전부 형제 값(dsr 0.555 · N 11 · sweep · net_ir) — 구 dsr 0.51 은 history 에만", sprintf("dsr=%s", format(a1$essence$dsr)))
F4 <- mk_fx("p05b"); p05(F4$art$p1, KEY, with_regime = FALSE)
e1 <- err_of(invisible(capture.output(RB(F4, list(item(F4, "FX_P", 1L, F4$art$p1, reg = KEY)), dry_run = TRUE))))
e2 <- err_of(invisible(capture.output(RB(F4, list(item(F4, "FX_P", 1L, F4$art$p1, reg = "close_t1", path = remp(F4$art$p1, KEY))), dry_run = TRUE))))
chk(is.na(e1) && identical(code_of(e2), "regime_dir_mismatch"),
    "P17 regime 필드 없는 P0-05 판(measurement_regime{key, exec_price}) — 키로 부르면 수락(key 폴백) · 규약명으로 부르면 디렉터리 불일치 거부",
    c(e1, e2))
}

# ══ R 위반 주입 ═════════════════════════════════════════════════════════════
if (run_sec("R")) {
cat("\n=== R 위반 주입 (원장 불변) ===\n")
F <- mk_fx("r"); m0 <- md5(F$p)
rj <- function(items, want, label, ...) {
  e <- err_of(invisible(capture.output(RB(F, items, ...))))
  chk(!is.na(e) && identical(code_of(e), want) && identical(md5(F$p), m0), sprintf("%s → 거부 [%s] · 원장 불변", label, want), e)
}
rj(list(item(F, "FX_P", 2L, F$art$p2, reg = "open_t1")), "regime_mismatch", "R1 regime 이 다른 형제(remeasure_open_t1 안의 close_t1 판)")
rj(list(item(F, "FX_P", 2L, F$art$p2, path = remp(F$art$p1, "close_t1"),
             tweak = function(x) { x$port_t <- 2.801; x$calmar <- 0.402; x }, regime_old = NULL)), "not_sibling", "R2 다른 칸의 형제 판")
rj(list(item(F, "FX_P", 4L, F$art$p4)), "blocked_flag:pit_c11", "R3 C11 표식 칸(결정 PIT-C11-CONVENTIONS ⑧ 비편입)")
rj(list(item(F, "FX_P", 2L, F$art$p2, tweak = function(x) { x$port_t <- x$port_t + 0.01; x })), "essence_mismatch", "R4 essence_new 가 형제 판과 다름")
rj(list(list(base_id = "FX_P", n = 3L, essence_new = ess("B1_3", 1, 0.1), regime = "close_t1",
             provenance = list(remeasure_path = remp(F$art$p1, "close_t1")))), "unmeasured", "R5 미측정 칸")
rj(list(item(F, "FX_P", 6L, F$art$p6)), "history_exists", "R6 history[[구 regime]] 선재 — 덮어쓰기")
rj(list(item(F, "FX_P", 2L, F$art$p2, regime_old = "open_t1")), "regime_old_conflict", "R7 호출자 regime_old 가 재도출과 다름")
rj(list(item(F, "FX_P", 2L, F$art$p2, tweak = function(x) { x$cell_code <- "B9_9"; x })), "cell_mismatch", "R8 essence_new cell_code 불일치")
rj(list(item(F, "FX_P", 8L, F$art$p8)), "remeasure_regime_absent", "R9 measurement_regime 없는 형제 판")
rj(list(item(F, "FX_P", 2L, F$art$p2), item(F, "FX_P", 4L, F$art$p4)), "blocked_flag:pit_c11", "R10 배치 원자성(정상+C11 → 전부 0 쓰기)")
e <- err_of(invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 2L, F$art$p2), item(F, "FX_P", 4L, F$art$p4)), skip_rejected = TRUE))))
LR <- rf_load(1L, F$R)
chk(is.na(e) && res$n_rebased == 1L && res$n_rejected == 1L && identical(res$items[[2]]$code, "blocked_flag:pit_c11") &&
    !is.null(getA(LR, "FX_P", 2)$essence_history) && is.null(getA(LR, "FX_P", 4)$essence_history),
    "R11 skip_rejected — 정상 칸만 쓰고 거부 칸은 사유 코드로 반환(조용한 배제 아님)", e)
m0 <- md5(F$p)
for (bad in list(list(k = "grade", v = "A"), list(k = "provenance", v = list(producer = "x")), list(k = "provenance", v = list(remeasure_path = "x", essence = list(port_t = 1))))) {
  it <- item(F, "FX_P", 1L, F$art$p1); it[[bad$k]] <- bad$v
  e <- err_of(invisible(capture.output(RB(F, list(it)))))
  chk(!is.na(e) && identical(md5(F$p), m0), sprintf("R12 형식 거부 — %s 주입(등급 전달·출처 경로 누락·출처에 essence)", bad$k), e)
}
wj(list(schema = "pit_quarantine_v1", quarantines = list(list(id = "Q1", flag = "zz_qflag", status = "active"))), file.path(F$R, "06_Registry/pit_quarantine.json"))
rj(list(item(F, "FX_P", 7L, F$art$p7)), "blocked_flag:zz_qflag", "R13 pit_quarantine.json active flag 칸")
wj(list(schema = "pit_quarantine_v1", quarantines = list(list(id = "Q1", flag = "zz_qflag", status = "released"))), file.path(F$R, "06_Registry/pit_quarantine.json"))
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 7L, F$art$p7)), dry_run = TRUE)))
chk(res$n_rebased == 1L, "R14 격리 released 면 그 flag 는 비편입 목록에서 빠진다(상수 pit_c11 은 남음)")
writeLines("{ broken", file.path(F$R, "06_Registry/pit_quarantine.json"))
e <- err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 7L, F$art$p7))))))
chk(!is.na(e) && grepl("파손", e) && identical(md5(F$p), m0), "R15 pit_quarantine.json 파손 = 거부(조용한 해제 금지)", e)
unlink(file.path(F$R, "06_Registry/pit_quarantine.json"))
invisible(capture.output(RB(F, list(item(F, "FX_P", 1L, F$art$p1)))))
x <- fromJSON(remp(F$art$p1, "close_t1"), simplifyVector = FALSE); x$essence_grade <- "B"; wj(x, remp(F$art$p1, "close_t1"))
m1 <- md5(F$p)
e <- err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 1L, F$art$p1))))))
chk(!is.na(e) && identical(code_of(e), "same_regime_overwrite") && identical(md5(F$p), m1), "R16 같은 regime 에 다른 판 = 덮어쓰기 거부", e)
# ── R17~R19 ★L-B2 위반 주입 — P0-05 모양 형제 판(dsr·net_ir·N 포함)에 대해 ─────────────────────────────────────
F <- mk_fx("r17"); m0 <- md5(F$p); KEY <- "close_t1_5562284e"
wj(list(status = "OK", kind = "remeasure_from_holdings", essence_grade = "C", selection_type = "sweep", n_trials_cumulative = 11L, dsr = 0.555,
        essence = c(core(1.895, 0.301), list(dsr = 0.555, net_ir = 0.44)),
        measurement_regime = list(regime = KEY, key = KEY, exec_price = "close_t1", selection_type = "sweep", n_trials_cumulative = 11L)),
   file.path(F$art$p1, paste0("remeasure_", KEY), "authoritative_remeasure.json"))
old_shape <- function(x) {   # 적대검증 B2 재현: 구 원장 essence 에서 핵심 6지표만 형제 값으로 바꾼 모양(dsr 0.51·N 45 잔존)
  o <- getA(rf_load(1L, F$R), "FX_P", 1)$essence
  for (k in c("port_t", "net_sharpe", "cagr", "mdd", "calmar", "oos_retention")) o[[k]] <- x[[k]]
  o }
rj(list(item(F, "FX_P", 1L, F$art$p1, reg = KEY, tweak = old_shape)), "essence_mismatch:dsr",
   "R17 ★적대검증 B2 재현 — 핵심 6지표만 바꾼 essence_new(구 dsr 0.51 ≠ 형제 0.555) 거부")
rj(list(item(F, "FX_P", 1L, F$art$p1, reg = KEY, tweak = function(x) { x$beta <- 0.8; x })), "essence_new_foreign_keys",
   "R18 essence_new 에 허용 밖 키(beta — 구 측정 보조 값) 거부")
rj(list(item(F, "FX_P", 1L, F$art$p1, reg = KEY, tweak = function(x) { x$spec <- "C:/other/spec.json"; x })), "identity_mismatch",
   "R19 essence_new 신원 키(spec) 변조 거부")
}

# ══ L 잠금 · CAS · 사후 검증 ═════════════════════════════════════════════════
if (run_sec("L")) {
cat("\n=== L 잠금 · CAS · 사후 검증 ===\n")
F <- mk_fx("l"); m0 <- md5(F$p); cl <- file.path(F$R, ".cache", "reinforce_auto.claim")
dir.create(cl, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(pid = 4L, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), auto_unbox = TRUE), file.path(cl, "owner.json"))
e <- err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 1L, F$art$p1))))))
chk(!is.na(e) && grepl("claim 획득 실패", e) && identical(md5(F$p), m0), "L1 다른 살아 있는 owner(pid 4) 가 claim 보유 → 대기 후 거부 · 원장 불변", e)
e <- err_of(invisible(capture.output(EP(F, relabel_from = "n_max_25"))))
chk(!is.na(e) && grepl("claim 획득 실패", e) && identical(md5(F$p), m0), "L2 축 전환도 같은 claim 아래에서만", e)
unlink(cl, recursive = TRUE)
.cle <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R"), envir = .cle)
ac <- .cle$rf_claim_acquire(cl)
e <- err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 1L, F$art$p1))))))
own <- tryCatch(fromJSON(file.path(cl, "owner.json")), error = function(e) NULL)
chk(isTRUE(ac$ok) && is.na(e) && !identical(md5(F$p), m0) && identical(as.integer(own$pid), as.integer(Sys.getpid())) &&
    !file.exists(file.path(cl, "released.json")), "L3 호출자(같은 프로세스)가 쥔 claim — 그대로 쓰고 풀지 않는다(드라이버 claim 유지)", e)
invisible(.cle$rf_claim_release(cl))
m1 <- md5(F$p)
hook <- function(pp) { x <- readLines(pp, warn = FALSE, encoding = "UTF-8"); writeLines(c(x, ""), pp, useBytes = TRUE) }
e <- err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 2L, F$art$p2)), .pre_write_hook = hook))))
chk(!is.na(e) && grepl("claim 밖 쓰기", e) && !identical(md5(F$p), m1) && is.null(getA(rf_load(1L, F$R), "FX_P", 2)$essence_history),
    "L4 CAS — 적재 뒤 외부 쓰기 → 덮어쓰지 않고 거부(외부 판 보존)", e)
F <- mk_fx("l5"); m0 <- md5(F$p)
.rf_write_orig <- .rf_write
.rf_write <- function(obj, layer, root = .rf_root()) { obj$entries[[1]]$attempts[[2]]$lessons <- "변조"; .rf_write_orig(obj, layer, root) }
e <- tryCatch(err_of(invisible(capture.output(RB(F, list(item(F, "FX_P", 1L, F$art$p1)))))), finally = assign(".rf_write", .rf_write_orig, envir = globalenv()))
chk(!is.na(e) && grepl("사후 재적재 대조 실패", e) && identical(md5(F$p), m0) && !file.exists(paste0(F$p, ".rebase_restore.tmp")),
    "L5 쓰기 경로 결함 주입 → 사후 대조가 잡고 원본 바이트 복원(md5 동일)", e)
F <- mk_fx("l6"); m0 <- md5(F$p); bk <- file.path(F$R, "bk.json"); sa <- file.path(F$R, "sa.json")
invisible(capture.output(res <- RB(F, list(item(F, "FX_P", 1L, F$art$p1)), backup_to = bk, snapshot_after_to = sa)))
chk(identical(md5(bk), m0) && identical(md5(sa), md5(F$p)) && identical(res$md5_after, md5(F$p)), "L6 backup_to = 쓰기 전 바이트 · snapshot_after_to = 쓴 직후 바이트")
}

# ══ A 축 전환 ════════════════════════════════════════════════════════════════
if (run_sec("A")) {
cat("\n=== A 축 전환 ===\n")
F <- mk_fx("a0")
n_old <- .old_mark_axis_epoch(1L, "exec_v2_close_t1", "x", "r", "e", root = F$R)
chk(identical(n_old, 0L) && identical(rf_load(1L, F$R)$current_axis, "exec_v2_close_t1"),
    "A0 수리 전 원문 — 전 entry 가 축 라벨을 가진 원장에서 0건 표시하고 current_axis 만 바꾼다(무발화 재현)")
F <- mk_fx("a1"); m0 <- md5(F$p)
e <- err_of(invisible(capture.output(EP(F))))
chk(!is.na(e) && grepl("무발화", e) && identical(md5(F$p), m0), "A1 수리판 — relabel_from 없이 0건이면 무발화 전환 거부", e)
e <- err_of(invisible(capture.output(EP(F, relabel_from = "zz_nothing"))))
chk(!is.na(e) && identical(md5(F$p), m0), "A2 relabel_from 이 현 축 밖/0건이면 거부", e)
L0 <- rf_load(1L, F$R)
invisible(capture.output(x <- EP(F, relabel_from = "n_max_25")))
LA <- rf_load(1L, F$R); axs <- vapply(LA$entries, function(e) paste(e$measurement_axis, e$axis_valid), "")
chk(x$n_marked == 4L && all(axs[1:4] == "n_max_25@close_d_legacy FALSE") && identical(axs[5], "legacy_double_selection_n3 FALSE") &&
    identical(LA$current_axis, "exec_v2_close_t1") && identical(LA$axis_epochs[[1]], L0$axis_epochs[[1]]) && length(LA$axis_epochs) == 2L,
    "A3 relabel_from='n_max_25' — 해당 4건 legacy 표시 · 다른 축 불변 · axis_epochs append-only", paste(axs, collapse = " | "))
axstrip <- function(L) { L$last_updated <- NULL; L$axis_epochs <- NULL; L$current_axis <- NULL
  L$entries <- lapply(L$entries, function(e) { e[c("measurement_axis", "axis_valid", "axis_marked_at", "axis_history", "axis_blocked_legacy")] <- NULL; e }); L }
chk(identical(axstrip(LA), axstrip(L0)), "A4 검사 자체 투영 — 축 필드 밖 불변")
F <- mk_fx("a5")
invisible(capture.output({ RB(F, list(item(F, "FX_P", 1L, F$art$p1), item(F, "FX_P", 2L, F$art$p2), item(F, "FX_P", 5L, F$art$p5),
                                     item(F, "FX_P", 6L, F$art$p6, regime_old = NULL), item(F, "FX_P", "base", F$art$bP)), skip_rejected = TRUE) }))
# FX_P: n6(history_exists)·n7·n8·n9(미 rebase)가 남아 off → legacy 여야 한다. n6~9 를 미측정으로 바꾼 판을 따로 만든다.
F2 <- mk_fx("a5b")
invisible(capture.output(RB(F2, list(item(F2, "FX_P", 1L, F2$art$p1), item(F2, "FX_P", 2L, F2$art$p2), item(F2, "FX_P", 5L, F2$art$p5),
                                      item(F2, "FX_P", "base", F2$art$bP), item(F2, "FX_C", 1L, F2$art$c1)))))
L2 <- rf_load(1L, F2$R)
for (n in 6:9) L2$entries[[1]]$attempts[[n]]["essence"] <- list(NULL)   # 픽스처 조정: 남은 구 규약 칸을 미측정(null)으로
invisible(.rf_write(L2, 1L, F2$R)); m0 <- md5(F2$p)
invisible(capture.output(x <- EP(F2, relabel_from = "n_max_25", require_regime = "close_t1", dry_run = TRUE)))
chk(identical(md5(F2$p), m0) && !isTRUE(x$written), "A5 dry_run — 계획만(원장 불변)")
invisible(capture.output(x <- EP(F2, relabel_from = "n_max_25", require_regime = "close_t1")))
LB <- rf_load(1L, F2$R); gE <- function(b) getE(LB, b)
chk(identical(gE("FX_P")$measurement_axis, "exec_v2_close_t1") && isTRUE(gE("FX_P")$axis_valid) &&
    identical(unlist(gE("FX_P")$axis_blocked_legacy), "4"), "A6 전 칸 rebase entry → 새 축 승계 · C11 칸(n4)은 axis_blocked_legacy 로 목록화")
chk(identical(gE("FX_C")$measurement_axis, "exec_v2_close_t1"), "A7 자식 entry(칸 rebase) → 새 축")
chk(identical(gE("FX_Q")$measurement_axis, "n_max_25@close_d_legacy") && isFALSE(gE("FX_Q")$axis_valid) &&
    identical(gE("FX_Q")$axis_history[[1]]$why, "blocked_only"), "A8 표식 칸만 가진 entry → legacy(blocked_only)")
chk(identical(gE("FX_U")$measurement_axis, "n_max_25@close_d_legacy") && identical(unlist(gE("FX_U")$axis_history[[1]]$off_regime), "n1:close_d_legacy"),
    "A9 rebase 안 된 칸이 남은 entry → legacy · off_regime 사유(n1:close_d_legacy)")
LF <- rf_load(1L, F$R); ef <- getE(LF, "FX_P")
st <- .rf_entry_regime_status(ef, "close_t1", rf_rebase_block_flags(F$R), F$R)
chk(identical(st$verdict, "legacy") && any(grepl("^n6:", st$off)) && any(grepl("^n7:", st$off)), "A10 한 칸이라도 구 규약이면 entry 자격 없음(n6·n7)", paste(st$off, collapse = ","))
invisible(capture.output(rf_open_entry(1L, "FX_NEW", "C", root = F2$R)))
chk(identical(getE(rf_load(1L, F2$R), "FX_NEW")$measurement_axis, "exec_v2_close_t1"), "A11 전환 뒤 개설 entry 는 새 축으로 태어난다")
m1 <- md5(F2$p); e <- err_of(invisible(capture.output(EP(F2, relabel_from = "n_max_25", require_regime = "close_t1"))))
chk(!is.na(e) && identical(md5(F2$p), m1), "A12 이미 전환된 원장(현 축 ∉ relabel_from) 재전환 거부", e)

chk(identical(rf_attempt_regime(list(n = 9L, essence_history = list(x = list(essence = list(port_t = 1)))), F2$R)$basis, "unmeasured"),
    "A13 essence 키 부재 + essence_history → 미측정(R $ 부분 일치 함정 — history 를 essence 로 읽지 않는다)")
}

if (CORE) finish()

# ══ C 운영 원장 사본 재도출 ════════════════════════════════════════════════════
cat("\n=== C 운영 원장 사본 재도출 ===\n")
C_ROOT <- normalizePath(file.path(tempdir(), sprintf("rfrb_copy_%d", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(file.path(C_ROOT, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(OP_L1)) { sk("C 운영 원장 부재"); finish() }
invisible(file.copy(OP_L1, file.path(C_ROOT, "06_Registry/reinforce_ledger_l1.json"), overwrite = TRUE))
if (file.exists(file.path(ROOT, "06_Registry/pit_quarantine.json")))
  invisible(file.copy(file.path(ROOT, "06_Registry/pit_quarantine.json"), file.path(C_ROOT, "06_Registry/pit_quarantine.json"), overwrite = TRUE))
CP <- file.path(C_ROOT, "06_Registry/reinforce_ledger_l1.json")
chk(identical(md5(CP), OP_MD5[[1]]), "C0 사본 = 운영 원장 바이트(md5)")
LC <- rf_load(1L, C_ROOT); CUR <- .rf_s1(LC$current_axis)
EPOCH_C <- if (identical(CUR, "exec_v2_close_t1")) "exec_v3_rebase_test" else "exec_v2_close_t1"
n_cur <- sum(vapply(LC$entries, function(e) identical(.rf_s1(e$measurement_axis), CUR), logical(1)))
n_null <- sum(vapply(LC$entries, function(e) is.null(e$measurement_axis), logical(1)))
cat(sprintf("  · 사본: entry %d · current_axis=%s(%d) · 축 라벨 없음 %d\n", length(LC$entries), CUR, n_cur, n_null))
tmpC <- file.path(C_ROOT, "old_epoch"); dir.create(file.path(tmpC, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(CP, file.path(tmpC, "06_Registry/reinforce_ledger_l1.json")))
n_old <- .old_mark_axis_epoch(1L, EPOCH_C, "x", "r", "e", root = tmpC)
chk(identical(n_old, as.integer(n_null)) && n_cur > 0L,
    sprintf("C1 재도출 — 수리 전 원문은 운영 원장 사본에서 %d건 표시(= 라벨 없는 entry %d) · 현 축 entry %d건은 한 건도 표시 못 함(무발화)", n_old, n_null, n_cur))
x <- NULL; e <- err_of(invisible(capture.output(x <- rf_mark_axis_epoch(1L, EPOCH_C, paste0(CUR, "@close_d_legacy"), "r", "e",
                                                                       root = C_ROOT, relabel_from = CUR, dry_run = TRUE))))
chk(is.na(e) && x$n_marked == n_cur, sprintf("C2 수리판 relabel_from='%s' 계획 = %d건(= 그 축 entry 수)", CUR, n_cur), e)

# 거울 — 칸·기저 산출물을 임시 디렉터리로 옮긴 사본(운영 산출물 무접촉). auth 는 measurement_regime 만(기저는 원본 전체 — 결합 풀이 읽는다)
MIR <- file.path(C_ROOT, "mir"); dir.create(MIR, showWarnings = FALSE)
perturb <- function(v, k) { v <- suppressWarnings(as.numeric(v)); if (!length(v) || !is.finite(v[1])) return(NULL)
  round(if (k == "port_t") v - 0.2 else if (k == "calmar") v * 0.93 else v, 6) }
syn_core <- function(es) { cr <- list(); for (k in names(RF_REBASE_CORE)) { v <- perturb(es[[k]], k)
  if (!is.null(v)) cr[[if (k == "port_t") "portfolio_alpha_t_nw_lag3" else k]] <- v }; cr }
syn_grade <- function(g) { g <- .rf_s1(g); if (g %in% c("A", "B", "C", "F")) g else "F" }
items <- list(); exp_rb <- 0L; exp_c11 <- 0L; exp_unres <- 0L; exp_base <- 0L; live_done <- 0L
for (i in seq_along(LC$entries)) {
  e <- LC$entries[[i]]
  bf <- .rf_auth_file(e$base_artifacts, ROOT)
  if (!nzchar(.rf_s1((if (is.list(e$base_measurement_regime)) e$base_measurement_regime else list())$regime)) &&
      !length(.rf_flags_hit(e$base_vintage_flags, "pit_c11")) && !is.na(bf) && file.exists(bf)) {
    d <- file.path(MIR, sprintf("b%03d", i)); dir.create(d, showWarnings = FALSE)
    invisible(file.copy(bf, file.path(d, "authoritative_remeasure.json")))
    bj <- fromJSON(bf, simplifyVector = FALSE)
    bcore <- list(); for (k in names(RF_REBASE_CORE)) { src <- RF_REBASE_CORE[[k]][1]
      v <- perturb(bj$essence[[src]] %||% bj$essence[[k]], k); if (!is.null(v)) bcore[[src]] <- v }
    if (length(bcore)) {
      wj(list(measurement_regime = list(exec_price = "close_t1", regime = "close_t1", source = "test_rf_rebase_synthetic"),
              essence_grade = syn_grade(bj$essence_grade), essence = bcore), remp(d, "close_t1"))
      LC$entries[[i]]$base_artifacts <- normalizePath(d, winslash = "/")
      items[[length(items) + 1L]] <- list(base_id = e$base_id, n = "base", essence_new = NULL, regime = "close_t1",
                                          provenance = list(remeasure_path = remp(normalizePath(d, winslash = "/"), "close_t1"), producer = "test_mirror"))
      exp_base <- exp_base + 1L
    }
  }
  for (j in seq_along(e$attempts)) {
    a <- e$attempts[[j]]; if (is.null(a$essence)) next
    if (nzchar(.rf_s1((if (is.list(a$measurement_regime)) a$measurement_regime else list())$regime))) { live_done <- live_done + 1L; next }
    if (length(.rf_flags_hit(a$vintage_flags, "pit_c11"))) {
      exp_c11 <- exp_c11 + 1L
      items[[length(items) + 1L]] <- list(base_id = e$base_id, n = as.integer(a$n), essence_new = a$essence, regime = "close_t1",
                                          provenance = list(remeasure_path = file.path(MIR, "c11", "remeasure_close_t1", "authoritative_remeasure.json")))
      next
    }
    af <- .rf_auth_file(a$artifacts, ROOT)
    if (is.list(a$artifacts) || is.na(af) || !file.exists(af)) {
      exp_unres <- exp_unres + 1L
      items[[length(items) + 1L]] <- list(base_id = e$base_id, n = as.integer(a$n), essence_new = a$essence, regime = "close_t1",
                                          provenance = list(remeasure_path = file.path(MIR, "none", "remeasure_close_t1", "authoritative_remeasure.json")))
      next
    }
    d <- file.path(MIR, sprintf("a%03d_%03d", i, j)); dir.create(d, showWarnings = FALSE)
    aj <- fromJSON(af, simplifyVector = FALSE)
    wj(if (is.null(aj$measurement_regime)) list(essence_grade = aj$essence_grade) else list(essence_grade = aj$essence_grade, measurement_regime = aj$measurement_regime),
       file.path(d, "authoritative_remeasure.json"))
    cr <- syn_core(a$essence)
    if (!length(cr)) { exp_unres <- exp_unres + 1L; next }
    wj(list(measurement_regime = list(exec_price = "close_t1", regime = "close_t1", source = "test_rf_rebase_synthetic"),
            essence_grade = syn_grade(a$grade), essence = cr), remp(d, "close_t1"))
    LC$entries[[i]]$attempts[[j]]$artifacts <- normalizePath(d, winslash = "/")
    en <- rf_rebase_essence_from_sibling(a[["essence"]], remp(normalizePath(d, winslash = "/"), "close_t1"))   # 드라이버와 같은 정본 조립기
    items[[length(items) + 1L]] <- list(base_id = e$base_id, n = as.integer(a$n), essence_new = en, regime = "close_t1",
                                        provenance = list(remeasure_path = remp(normalizePath(d, winslash = "/"), "close_t1"), producer = "test_mirror"))
    exp_rb <- exp_rb + 1L
  }
}
invisible(.rf_write(LC, 1L, C_ROOT))            # 거울 경로로 바꾼 사본(= rebase 전 판)
PRE <- file.path(C_ROOT, "pre.json"); invisible(file.copy(CP, PRE, overwrite = TRUE))
cat(sprintf("  · 대상: 칸 %d(비편입 C11 %d · 산출물 미해결 %d · 운영에서 이미 rebase %d) · 기저 %d\n", exp_rb, exp_c11, exp_unres, live_done, exp_base))

# 결합 풀 — 소비자(rf_combination_launch.R) 코드 그대로 파스 트리에서 꺼내 실행(술어 재작성 금지)
pool_of <- function(led) {
  ex <- parse(file.path(ROOT, "02_Infrastructure/ops/rf_combination_launch.R"), keep.source = FALSE)
  tx <- vapply(ex, function(z) paste(deparse(z, width.cutoff = 500L), collapse = " "), character(1))
  a <- which(startsWith(tx, "by_item <- list()")); b <- which(startsWith(tx, "P <- Filter("))
  if (length(a) != 1L || length(b) != 1L || b < a) stop("결합 풀 구간을 소비자 파스 트리에서 못 찾았다")
  env <- new.env(parent = globalenv()); env$led <- led; env$ROOT <- ROOT
  for (k in a:b) eval(ex[[k]], env)
  list(keys = sort(names(env$by_item)), P = sort(names(env$P)),
       rep = vapply(env$by_item, function(x) as.character(x$base_id %||% ""), character(1)))
}
neutral <- function(led) { led$entries <- lapply(led$entries, function(e) { e$axis_valid <- TRUE; e$measurement_axis <- led$current_axis; e }); led }
LPRE <- rf_load(1L, C_ROOT)
pool_pre <- pool_of(LPRE); ax_pre <- setdiff(pool_of(neutral(LPRE))$P, pool_pre$P)

t0 <- Sys.time(); res <- NULL
e <- err_of(invisible(capture.output(res <- rf_rebase_essence_batch(1L, items, root = C_ROOT, wait_s = 5, poll_s = 0.5, skip_rejected = TRUE))))
cat(sprintf("  · 전수 rebase %.1f초\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
if (!is.na(e) || is.null(res)) { ng("C3 전수 rebase 실패", e) } else {
  codes <- table(vapply(Filter(function(x) identical(x$status, "rejected"), res$items), function(x) x$code, ""))
  cat("  · 거부 코드:", paste(sprintf("%s=%d", names(codes), as.integer(codes)), collapse = " · "), "\n")
  chk(res$n_rebased == exp_rb + exp_base && res$n_already == 0L, sprintf("C3 rebase 수 %d = 대상 칸 %d + 기저 %d (재도출)", res$n_rebased, exp_rb, exp_base))
  chk(identical(as.integer(codes["blocked_flag:pit_c11"] %||% 0L), as.integer(exp_c11)) &&
      all(names(codes) %in% c("blocked_flag:pit_c11", "remeasure_absent", "artifacts_form", "artifacts_unresolvable")),
      sprintf("C4 C11 표식 %d칸 전부 비편입(blocked_flag:pit_c11) · 그 밖 거부 = 산출물 미해결 %d 뿐", exp_c11, exp_unres),
      paste(names(codes), as.integer(codes)))
  POST <- file.path(C_ROOT, "post.json"); invisible(file.copy(CP, POST, overwrite = TRUE))
  pool_mid <- pool_of(rf_load(1L, C_ROOT))                       # rebase 뒤 · 축 전환 전
  PY <- Sys.getenv("QVEST_PY", ""); if (!nzchar(PY)) PY <- Sys.which("python")
  pyf <- file.path(C_ROOT, "chk.py")
  writeLines(c(
    "import json, sys",
    "pre = json.load(open(sys.argv[1], encoding='utf-8')); post = json.load(open(sys.argv[2], encoding='utf-8')); old = sys.argv[3]",
    "AA = {'essence','grade','grade_base','retro','retro_inherited','measurement_regime','essence_history','rebase_log'}",
    "AE = {'base_grade','base_measurement_regime','base_remeasure','base_essence_history','base_rebase_log','parent_rebased_from','parent','attempts','last_updated'}",
    "c = lambda x: json.dumps(x, sort_keys=True, ensure_ascii=False)",
    "nr = nh = nb = nk = 0; bad = []",
    "for k in (set(pre) | set(post)) - {'entries', 'last_updated'}:",
    "    if c(pre.get(k)) != c(post.get(k)): bad.append(('top', k))",
    "for ep, en in zip(pre['entries'], post['entries']):",
    "    if ep['base_id'] != en['base_id']: bad.append(('order', ep['base_id'])); continue",
    "    for k in (set(ep) | set(en)) - AE:",
    "        if c(ep.get(k)) != c(en.get(k)): bad.append(('entry', en['base_id'], k))",
    "    f = lambda d: {k: v for k, v in (d or {}).items() if not k.startswith('best_')}",
    "    if c(f(ep.get('parent'))) != c(f(en.get('parent'))): bad.append(('parent', en['base_id']))",
    "    if en.get('parent_rebased_from'):",
    "        nk += 1; b = en['parent_rebased_from'][-1]['before']",
    "        if any(c(ep['parent'].get(k)) != c(v) for k, v in b.items()): bad.append(('parent_before', en['base_id']))",
    "    if en.get('base_essence_history'):",
    "        nb += 1",
    "        if c(en['base_essence_history'][old]['base_grade']) != c(ep.get('base_grade')): bad.append(('base_hist', en['base_id']))",
    "    elif c(ep.get('base_grade')) != c(en.get('base_grade')): bad.append(('base_grade', en['base_id']))",
    "    if len(ep['attempts']) != len(en['attempts']): bad.append(('n_att', en['base_id'])); continue",
    "    for ap, an in zip(ep['attempts'], en['attempts']):",
    "        if 'essence_history' in an and 'essence_history' not in ap:",
    "            nr += 1; h = an['essence_history'].get(old, {})",
    "            if c(h.get('essence')) == c(ap.get('essence')) and c(h.get('grade')) == c(ap.get('grade')): nh += 1",
    "            else: bad.append(('hist', en['base_id'], an['n']))",
    "            for k in ('grade_base', 'retro', 'retro_inherited'):",
    "                if k in ap and c(h.get(k)) != c(ap[k]): bad.append(('hist_field', en['base_id'], an['n'], k))",
    "            for k in (set(ap) | set(an)) - AA:",
    "                if c(ap.get(k)) != c(an.get(k)): bad.append(('att', en['base_id'], an['n'], k))",
    "        elif c(ap) != c(an): bad.append(('untouched', en['base_id'], an['n']))",
    "print(json.dumps({'n_rebased': nr, 'n_hist_ok': nh, 'n_base': nb, 'n_kids': nk, 'n_bad': len(bad), 'bad': bad[:10]}))"), pyf, useBytes = TRUE)
  if (!nzchar(PY) || !file.exists(PY)) sk("C5 python 부재 — 독립 대조 건너뜀") else {
    out <- tryCatch(system2(PY, c(shQuote(pyf), shQuote(PRE), shQuote(POST), "close_d_legacy"), stdout = TRUE, stderr = TRUE), error = function(e) conditionMessage(e))
    pj <- tryCatch(fromJSON(tail(out, 1)), error = function(e) NULL)
    chk(!is.null(pj) && pj$n_bad == 0L && pj$n_rebased == exp_rb && pj$n_hist_ok == exp_rb && pj$n_base == exp_base,
        sprintf("C5 python 독립 대조 — history 비트 보존 %s/%s · 기저 %s · 자식 parent %s · 허용 밖 변경 %s",
                pj$n_hist_ok %||% "?", exp_rb, pj$n_base %||% "?", pj$n_kids %||% "?", pj$n_bad %||% "?"), paste(tail(out, 3), collapse = " | "))
    kid_exp <- sum(vapply(LPRE$entries, function(e) { pr <- e$parent; if (!is.list(pr)) return(FALSE)
      pi <- .rf_find(LPRE, .rf_s1(pr$base_id)); if (is.na(pi)) return(FALSE); pe <- LPRE$entries[[pi]]
      any(vapply(pe$attempts, function(a) identical(.rf_s1(a$cell_code %||% (a$essence %||% list())$cell_code), .rf_s1(pr$cell)) && !is.null(a$essence) &&
                   !length(.rf_flags_hit(a$vintage_flags, "pit_c11")) && !is.list(a$artifacts) && grepl("/mir/", .rf_s1(a$artifacts)), logical(1))) }, logical(1)))
    chk(!is.null(pj) && pj$n_kids == kid_exp && res$n_children == kid_exp, sprintf("C6 자식 parent$best_* 갱신 %s = 승자 칸이 rebase 된 자식 %d (재도출)", pj$n_kids %||% "?", kid_exp))
  }
  invisible(capture.output(x <- rf_mark_axis_epoch(1L, EPOCH_C, paste0(CUR, "@close_d_legacy"), "사본 전환", "test_rf_rebase C",
                                                   root = C_ROOT, relabel_from = CUR, require_regime = "close_t1", wait_s = 5, poll_s = 0.5)))
  LPOST <- rf_load(1L, C_ROOT)
  pool_post <- pool_of(LPOST); ax_post <- setdiff(pool_of(neutral(LPOST))$P, pool_post$P)
  lg <- Filter(function(p) identical(p$to, "legacy") && !is.na(p$from) && identical(p$from, CUR), x$plan)
  cat(sprintf("  · 전환: 승계 %d · legacy %d%s\n", x$n_carried, x$n_marked,
              if (length(lg)) paste0(" (", paste(vapply(lg, function(p) sprintf("%s:%s", p$base_id, p$why), ""), collapse = ", "), ")") else ""))
  chk(identical(pool_post$keys, pool_pre$keys) && length(pool_pre$keys) > 0L,
      sprintf("C7 결합 재료 후보(소비자 by_item 키 — 상태·엔진·축 필터 통과) 불변 %d → %d", length(pool_pre$keys), length(pool_post$keys)),
      paste(setdiff(union(pool_pre$keys, pool_post$keys), intersect(pool_pre$keys, pool_post$keys)), collapse = ","))
  chk(identical(pool_post$P, pool_mid$P), sprintf("C7b 축 전환 자체가 결합 풀에서 뺀 재료 0 (전환 전 %d = 후 %d)", length(pool_mid$P), length(pool_post$P)),
      paste(setdiff(pool_mid$P, pool_post$P), collapse = ","))
  dP <- setdiff(union(pool_pre$P, pool_post$P), intersect(pool_pre$P, pool_post$P))
  expl <- vapply(dP, function(k) !identical(pool_pre$rep[[k]], pool_post$rep[[k]]), logical(1))
  chk(all(expl), sprintf("C7c rebase 전후 풀 차이 %d건 = 전부 값 변화로 대표 entry 가 바뀐 재료(원문 링크 판정은 대표 entry 의 것 · 축 배제 아님)", length(dP)),
      paste(dP[!expl], collapse = ","))
  chk(length(setdiff(ax_post, ax_pre)) == 0L, sprintf("C8 축 불일치 skip 으로 새로 배제된 재료 0 (전환 전 축 배제 %d · 후 %d)", length(ax_pre), length(ax_post)),
      paste(setdiff(ax_post, ax_pre), collapse = ","))
}
chk(identical(vapply(c(OP_L1, OP_L2), function(p) if (file.exists(p)) md5(p) else "", character(1)), OP_MD5), "C9 운영 원장 L1/L2 md5 전후 불변")

# ══ M 돌연변이 ═══════════════════════════════════════════════════════════════
cat("\n=== M 돌연변이 (자식 Rscript · 사본 소스 · 병렬) ===\n")
src_txt <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
EMPTY_ENV <- file.path(tempdir(), sprintf("rfrb_empty_%d.Renviron", Sys.getpid())); writeLines(character(0), EMPTY_ENV)
THIS <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/", mustWork = FALSE)
subst <- function(lines, from, to, expect) {
  hits <- sum(vapply(lines, function(l) lengths(regmatches(l, gregexpr(from, l, fixed = TRUE))), integer(1)))
  if (hits != expect) return(NULL)
  vapply(lines, function(l) gsub(from, to, l, fixed = TRUE), character(1), USE.NAMES = FALSE)
}
muts <- list(
  list(tag = "ctl", d = "대조(원본 사본)", s = list(), sec = ""),
  list(tag = "overwrite", sec = "R", d = "history 덮어쓰기(선재 키 검사 + append-only 대조 제거)",
       s = list(c("if (!is.null(H[[ro$regime]]))", "if (FALSE)", 2L),
                c("if (!.rf_rb_history_kept(orig, obj))", "if (FALSE)", 1L),
                c("!.rf_rb_history_kept(orig, .rt) ||", "FALSE ||", 1L))),
  list(tag = "hist_reset", sec = "P", d = "history 를 새 키 하나로 재설정(구 키 소실)",
       s = list(c("H2[[ro$regime]] <- rec", "H2 <- setNames(list(rec), ro$regime)", 2L),
                c("if (!.rf_rb_history_kept(orig, obj))", "if (FALSE)", 1L),
                c("!.rf_rb_history_kept(orig, .rt) ||", "FALSE ||", 1L))),
  list(tag = "regime", sec = "R", d = "형제 판 regime 키 대조 제거", s = list(c("if (!identical(rk$regime, it$regime))", "if (FALSE)", 1L))),
  list(tag = "sibling", sec = "R", d = "형제 위치 대조 제거", s = list(c("if (!.rf_same_path(dirname(dirname(f)), d))", "if (FALSE)", 1L))),
  list(tag = "c11", sec = "R", d = "C11 표식 거부 제거", s = list(c("hit <- .rf_flags_hit(a$vintage_flags, blocked)", "hit <- character(0)", 1L))),
  list(tag = "claim", sec = "L", d = "claim 획득 제거(항상 ok)", s = list(c("got <- .cl$rf_claim_acquire(claim, stale_hours = RF_LEDGER_CLAIM_STALE_H)", "got <- list(ok = TRUE)", 1L))),
  list(tag = "graduate", sec = "G", d = "graduate 인자 무시(항상 졸업)", s = list(c("if (isTRUE(graduate)) {", "if (TRUE) {", 1L))),
  list(tag = "parent", sec = "P", d = "자식 parent$best_* 갱신 제거", s = list(c("obj$entries[[k2]]$parent <- pr", "invisible(NULL)", 1L))),
  list(tag = "label", sec = "P", d = "칸 라벨을 격자 좌표로 대조(B4 칸 오거부)", s = list(c("  cc <- .cl_of(a)", "  cc <- .rf_s1(a$cell_code)", 1L))),
  list(tag = "dup", sec = "P", d = "같은 라벨 여러 칸의 승자 판별(port_t 대조) 제거", s = list(c("if (length(same_cell) > 1L) {", "if (FALSE) {", 1L))),
  list(tag = "relabel", sec = "A", d = "relabel_from 무시(구판 NULL 규칙만)", s = list(c("if (!(ax %in% rf_from)) return(", "if (TRUE) return(", 1L))),
  list(tag = "nullguard", sec = "A", d = "무발화(0건) 거부 제거", s = list(c("if (!length(rf_from) && (n_marked + n_carried) == 0L && !isTRUE(allow_empty))", "if (FALSE)", 1L))),
  list(tag = "blocked_only", sec = "A", d = "표식 칸만 가진 entry 도 새 축 승계", s = list(c("if (n_on >= 1L || n_meas == 0L) \"epoch\"", "if (TRUE) \"epoch\"", 1L))),
  list(tag = "kinds", sec = "S", d = "결정 kind 2종 제거", s = list(c("\"a_eligibility\", \"prereg_verdict\")", "\"base_gate_x\")", 1L))),
  list(tag = "cas", sec = "L", d = "CAS 제거(rebase·전환)", s = list(c("if (!identical(unname(tools::md5sum(p)), md5_a))", "if (FALSE)", 2L))),
  list(tag = "restore", sec = "L", d = "사후 대조 실패 시 원본 복원 제거", s = list(c(".rf_restore_bytes(p, raw_a, \"rebase\")", "invisible(NULL)", 1L))),
  list(tag = "protect", sec = "P", d = "보호 투영 가드 제거 + 보호 필드(lessons) 변조",
       s = list(c("obj$entries[[i]]$attempts[[j]] <- a", "a$lessons <- \"변조\"; obj$entries[[i]]$attempts[[j]] <- a", 1L),
                c("if (!identical(.rf_rb_strip(obj, att, base, kids), .rf_rb_strip(orig, att, base, kids)))", "if (FALSE)", 1L),
                c("if (!identical(.rf_rb_strip(.rt, att, base, kids), .rf_rb_strip(orig, att, base, kids)) ||", "if (FALSE ||", 1L))),
  list(tag = "compose", sec = "R", d = "★L-B2 writer 조립 제거(essence_new 그대로 씀 — 구판)",
       s = list(c("es_new <- .rf_rb_compose(a[[\"essence\"]], it$essence_new, sib)", "es_new <- it$essence_new", 1L))),
  list(tag = "meas_core", sec = "P", d = "★L-B2 측정 키를 핵심 6개로 축소(dsr·N·net_ir 형제 값 미반영)",
       s = list(c("net_ir = \"essence:net_ir\", dsr = c(\"essence:dsr\", \"top:dsr\"),", "", 1L),
                c("selection_type = c(\"top:selection_type\", \"mr:selection_type\"),", "", 1L),
                c("n_trials_cumulative = c(\"top:n_trials_cumulative\", \"mr:n_trials_cumulative\"))", "zz_unused = \"top:zz\")", 1L))),
  list(tag = "keyfb", sec = "P", d = "★L-B1 key 폴백 제거(regime → exec_price 만 — 구판)",
       s = list(c("r <- .rf_s1(mr[[\"key\"]]);        if (nzchar(r)) return(list(regime = r, basis = \"auth_key\"))", "invisible(NULL)", 1L))),
  list(tag = "guard_kept", sec = "P", d = "보호 필드 변조(가드 유지) → writer 자체 거부",
       s = list(c("obj$entries[[i]]$attempts[[j]] <- a", "a$lessons <- \"변조\"; obj$entries[[i]]$attempts[[j]] <- a", 1L))))
jobs <- list()
MAXPAR <- 6L   # 자식 동시 실행 상한 — 각 자식이 claim 기록마다 PowerShell(프로세스 시작시각)을 띄워 동시 19개면 경합으로 10분+
.alive <- function() sum(vapply(jobs, function(j) !.fin(j$out), logical(1)))
.fin <- function(o) { x <- if (file.exists(o)) tryCatch(readLines(o, warn = FALSE), error = function(e) character(0)) else character(0)
  any(grepl('^[{]"test":"rf_rebase"', x)) || any(grepl("Execution halted", x, fixed = TRUE)) }
for (mu in muts) {
  while (length(jobs) && .alive() >= MAXPAR) Sys.sleep(2)
  L2 <- src_txt; okk <- TRUE
  for (s in mu$s) { L2 <- subst(L2, s[1], s[2], as.integer(s[3])); if (is.null(L2)) { okk <- FALSE; break } }
  if (!okk) { ng(sprintf("M-%s 주입 실패(대상 문자열 수 불일치 — 소스가 바뀌었다)", mu$tag)); next }
  f <- file.path(tempdir(), sprintf("rfrb_mut_%s_%d.R", mu$tag, Sys.getpid())); writeLines(L2, f, useBytes = TRUE)
  o <- file.path(tempdir(), sprintf("rfrb_mut_%s_%d.out", mu$tag, Sys.getpid())); unlink(o)
  kv <- c(RF_LEDGER_SRC = normalizePath(f, winslash = "/"), RF_REBASE_CORE_ONLY = "1", RF_REBASE_ONLY = mu$sec %||% "",
          R_ENVIRON_USER = normalizePath(EMPTY_ENV, winslash = "/"), QM_ROOT = ROOT)
  old <- Sys.getenv(names(kv), unset = NA); do.call(Sys.setenv, as.list(kv))
  tryCatch(system2(file.path(R.home("bin"), "Rscript"), shQuote(THIS), stdout = o, stderr = o, wait = FALSE),
           finally = { for (k in names(kv)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) })
  jobs[[mu$tag]] <- list(mu = mu, out = o)
}
t0 <- Sys.time()
repeat {
  if (all(vapply(jobs, function(j) .fin(j$out), logical(1))) || as.numeric(difftime(Sys.time(), t0, units = "secs")) > 1500) break
  Sys.sleep(3)
}
for (tg in names(jobs)) {
  j <- jobs[[tg]]; out <- if (file.exists(j$out)) tryCatch(readLines(j$out, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0)) else character(0)
  jl <- tail(grep('^\\{"test":"rf_rebase"', out, value = TRUE), 1)
  s <- if (length(jl)) fromJSON(jl) else list(pass = NA, fail = NA)
  halted <- !length(jl) && any(grepl("Execution halted", out, fixed = TRUE))
  first <- c(grep("^  FAIL", out, value = TRUE), grep("^Error", out, value = TRUE))[1]
  if (identical(tg, "ctl")) {
    chk(identical(as.integer(s$fail), 0L) && isTRUE(s$pass > 0), sprintf("M0 대조 — 원본 사본으로 자식 검사 green (%s 통과)", s$pass),
        paste(tail(out, 4), collapse = " | "))
  } else if (identical(tg, "guard_kept")) {
    chk(any(grepl("FAIL P1 rebase 1칸 기록 +— .*보호 투영 불일치", out)), "M-guard_kept 보호 필드 변조(가드 유지) → writer 가 보호 투영 불일치로 스스로 거부",
        paste(head(grep("P1", out, value = TRUE), 2), collapse = " | "))
  } else {
    chk(isTRUE(s$fail > 0) || halted, sprintf("M-%s %s → [%s절] red (%s · 첫 실패: %s)", tg, j$mu$d, j$mu$sec,
                                                if (halted) "중단" else sprintf("실패 %s", s$fail), substr(trimws(first %||% "?"), 1, 90)),
        sprintf("pass=%s fail=%s", s$pass, s$fail))
  }
}
chk(identical(vapply(c(OP_L1, OP_L2), function(p) if (file.exists(p)) md5(p) else "", character(1)), OP_MD5), "X1 운영 원장 L1/L2 md5 최종 불변")
finish()
