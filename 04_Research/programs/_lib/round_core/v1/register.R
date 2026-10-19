## round_core v1 · register — 사전등록 초안 · 점검 기록 · 등록 · 종료 기록(라운드마다 쓰던 register.R · close_round.R 대체)
##   검사는 P2R04 register.R 의 등록 조건을 그대로 일반화했다:
##   ① 등록할 초안 = 마지막으로 격리 점검(ok)을 받은 판(md5) ② 사양 · 칸 사양 md5 = 초안 ③ 핀(판정에 닿는 전체) 재대조 ④ 라운드 시험 통과
##   ⑤ 리허설 기록 ⑥ 철학 Superfan P1 수령 · 도전 응답 · 열린 보류 요청 없음(건너뛸 수 없음) ⑦ 고정 대상 미커밋 없음 ⑧ 두 사본 + 등록부(실패 시 되돌림).
##   점검본 사본(reviewed_v*.json — P2R04 507K) 대신 drafts.json 에 (판 · md5 · 점검 파일 · 판정 · git HEAD)를 남긴다 — 같은 규칙, 사본 없음.

RC_LEDGER_DEFAULT <- "06_Registry/q_judgment_ledger.json"

## RC_SA_ROOT = 사전등록 정본(stage_artifacts) 위치의 뿌리 — 기본 = 저장소. 검사는 임시 디렉터리로 돌려 실제 저장소에 쓰지 않는다
rc_paths <- function(round_dir, spec, root = rc_root()) {
  sa <- file.path("stage_artifacts/programs", spec[["program"]], spec[["round_id"]])
  sar <- Sys.getenv("RC_SA_ROOT", root)
  list(round_dir = round_dir, spec = file.path(round_dir, "round_spec.json"),
       draft = file.path(round_dir, "prereg_draft.json"), draft_md = file.path(round_dir, "prereg_draft.md"),
       drafts = file.path(round_dir, "drafts.json"), prereg_rel = file.path(sa, "prereg.json"),
       prereg = file.path(sar, sa, "prereg.json"), prereg_copy = file.path(round_dir, "prereg.json"),
       results = file.path(round_dir, "results"), sa_dir = file.path(sar, sa))
}
rc_round_tag <- function(round_id) sub("_.*$", "", round_id)   # P2R04_defensive_holdings → P2R04

.rc_git <- function(root, args) {
  o <- suppressWarnings(system2("git", c("-C", root, args), stdout = TRUE, stderr = FALSE))
  st <- attr(o, "status"); if (!is.null(st) && !identical(as.integer(st), 0L)) structure(character(0), git_failed = TRUE) else o
}
rc_git_head <- function(root = rc_root()) { h <- .rc_git(root, c("rev-parse", "HEAD")); if (length(h)) h[1] else NA_character_ }

## 사전등록 사람 쪽 문서(md) — 청정 레인은 성과 키가 든 json 을 못 읽으므로 점검자 · 감독에게는 이 문서를 준다
rc_prereg_md <- function(pre) {
  s <- pre$spec
  cells <- vapply(pre$cells, function(c) sprintf("| %s | %s | %s | %s |", c$code, c$engine, c$role, c$spec %||% paste("공유:", c$source_results)), character(1))
  c(sprintf("# %s 사전등록 초안 v%d (%s)", pre$round_id, pre$draft_version, pre$program),
    "", sprintf("- 코어 %s · 매니페스트 %s · 사양 md5 %s · τ_D %s", pre$core$version, substr(pre$core$manifest_md5, 1, 8), substr(pre$spec_md5, 1, 8), s$tau_d),
    "", "## 목적 · 가설", "", s$purpose %||% "", "", s$hypothesis %||% "",
    "", "## 칸", "", "| 칸 | 엔진 | 역할 | 사양 |", "|---|---|---|---|", cells,
    "", "## 규칙(선언에서 생성 — 판정 코드와 같은 출처)", "", paste0("- ", unlist(pre$sentences)),
    "", rc_rules_table_md(pre$rules_resolved),
    "", "## 선택 규칙", "", jsonlite::toJSON(s$selection, auto_unbox = TRUE, pretty = TRUE),
    "", "## 노출(τ_D)", "", paste0("- ", unlist(s$exposures) %||% "(없음)"),
    "", "## 결론 범위", "", paste0("- ", unlist(s$conclusion_scope) %||% "(없음)"),
    "", "## 핀", "", sprintf("- 파일 %d · 패키지 %s · %s", length(pre$pins$files),
                             paste(names(pre$pins$packages), unlist(pre$pins$packages), collapse = " · "), pre$pins$r_version))
}

## 초안 — 사양 검사 · 규칙 해석 · 문장 생성 · 핀 계산 · (선택) 리허설 → prereg_draft.json + .md · drafts.json 에 판 추가
rc_draft <- function(round_dir, root = rc_root(), rehearse = NULL) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root)
  P <- rc_paths(round_dir, spec, root)
  rules <- rc_rules_resolve(spec[["rules"]], root)
  pins <- rc_pins_compute(spec, root)
  D <- if (file.exists(P$drafts)) rc_json_read(P$drafts) else list(round_id = spec[["round_id"]], versions = list())
  v <- length(D$versions) + 1L
  sp <- spec; sp$.path <- NULL; sp$.md5 <- NULL
  pre <- list(schema = "round_core_prereg_v1", program = spec[["program"]], round_id = spec[["round_id"]], status = "draft",
              draft_version = v, drafted_at = rc_now(), core = pins$core[c("version", "manifest_md5")], spec_md5 = spec$.md5, spec = sp,
              rules_resolved = rules, sentences = as.list(rc_rules_sentences(rules)), pins = pins,
              cells = lapply(spec[["cells"]], function(c) c(c, if (!is.null(c[["spec"]])) list(md5 = rc_md5(rc_abs(c[["spec"]], root))))),
              behavior_card_cfg = if (!is.null(spec[["behavior_card_cfg"]])) list(path = spec[["behavior_card_cfg"]], md5 = rc_md5(rc_abs(spec[["behavior_card_cfg"]], root))))
  if (is.function(rehearse)) pre$rehearsal <- rc_safe(rehearse, spec, rules, what = "리허설")[c("ok", "value", "error")]
  rc_json_write(pre, P$draft); writeLines(rc_prereg_md(pre), P$draft_md, useBytes = TRUE)
  D$versions[[v]] <- list(version = v, md5 = rc_md5(P$draft), md5_md = rc_md5(P$draft_md), at = pre$drafted_at, review = NULL)
  rc_json_write(D, P$drafts)
  invisible(list(version = v, md5 = rc_md5(P$draft), draft = P$draft, md = P$draft_md))
}

## 점검 기록 — 지금 디스크의 초안이 그 판이어야 기록한다(점검받지 않은 초안을 점검받은 것으로 적지 않게)
rc_mark_reviewed <- function(round_dir, version, review_file, verdict = c("ok", "revise"), root = rc_root()) {
  verdict <- match.arg(verdict)
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root, check_files = FALSE); P <- rc_paths(round_dir, spec, root)
  D <- rc_json_read(P$drafts); v <- as.integer(version)
  if (v < 1L || v > length(D$versions)) stop("[round_core register] 그런 초안 판이 없다: v", v)
  if (!identical(rc_md5(P$draft), D$versions[[v]]$md5)) stop("[round_core register] 디스크의 초안이 v", v, " 가 아니다 — 점검받은 판을 기록할 수 없다")
  if (!file.exists(rc_abs(review_file, root))) stop("[round_core register] 점검 기록 파일 없음: ", review_file)
  D$versions[[v]]$review <- list(file = rc_rel(rc_abs(review_file, root), root), file_md5 = rc_md5(rc_abs(review_file, root)), verdict = verdict,
                                 at = rc_now(), git_head = rc_git_head(root))
  rc_json_write(D, P$drafts)
  invisible(D$versions[[v]])
}

## 철학 Superfan P1 수령 확인(P2R04 .p1_check 일반화) — 원장에 이 라운드의 P1 리뷰가 있고 파일이 실재 · 도전 · 정지 항목 모두 응답 · 열린 보류 요청 없음
rc_p1_check <- function(round_id, root = rc_root(), ledger = file.path(root, RC_LEDGER_DEFAULT), review_root = root) {
  L <- tryCatch(rc_json_read(ledger), error = function(e) NULL)
  if (is.null(L)) return(list(ok = FALSE, why = "판단 원장 판독 실패"))
  rx <- sprintf("^04_Research/programs/_supervision/superfan/philosophy/[0-9]{8}_[0-9]{4}_P1_%s\\.md$", rc_round_tag(round_id))
  rv <- Filter(function(r) identical(r$role, "philosophy") && identical(r$trigger, "P1") && identical(r$round, round_id), L$reviews %||% list())
  if (!length(rv)) return(list(ok = FALSE, why = sprintf("이 라운드(%s)의 철학 P1 리뷰가 원장에 없다", round_id)))
  fl <- vapply(rv, function(r) as.character(r$file %||% NA_character_), character(1))
  bad <- fl[is.na(fl) | !grepl(rx, fl, perl = TRUE) | !file.exists(file.path(review_root, fl))]
  if (length(bad)) return(list(ok = FALSE, why = paste("P1 리뷰 파일이 없거나 이름 형식이 아니다:", paste(bad, collapse = ","))))
  ids <- unique(unlist(lapply(rv, function(r) unlist(r$challenges))))
  ch <- Filter(function(c) c$id %in% ids && (c$grade %||% "") %in% c("challenge", "stop"), L$challenges %||% list())
  open <- vapply(Filter(function(c) identical(c$status, "open") || !length(c$responses), ch), function(c) c$id, character(1))
  hold <- vapply(Filter(function(c) isTRUE(c$hold_request) && !(c$status %in% c("accepted", "withdrawn", "escalated", "settled")), ch), function(c) c$id, character(1))
  if (length(open)) return(list(ok = FALSE, why = paste("응답 없는 도전:", paste(open, collapse = ","))))
  if (length(hold)) return(list(ok = FALSE, why = paste("열린 보류 요청:", paste(hold, collapse = ","))))
  list(ok = TRUE, reviews = vapply(rv, function(r) r$id, character(1)), files = fl, n_challenges = length(ch), checked_at = rc_now())
}

## 고정 대상 미커밋 — 라운드 디렉터리(초안 · 점검 목록 · 결과 제외) · 코어 판 · 칸 사양 · 라운드 고유 규칙
rc_uncommitted <- function(round_dir, spec, root = rc_root()) {
  paths <- unique(c(rc_rel(round_dir, root), rc_rel(RC_DIR, root), unlist(lapply(spec[["cells"]], function(c) c[["spec"]])), spec[["ext"]]))
  s <- .rc_git(root, c("status", "--porcelain", "--", paths))
  if (isTRUE(attr(s, "git_failed"))) stop("[round_core register] git status 실패 — 커밋 상태를 확인할 수 없다")
  s <- s[nzchar(s)]; s[!grepl("prereg_draft|drafts[.]json|/results/|rehearsal/out", s)]
}

## 등록 — 조건 ①~⑧ · 실패 시 두 사본을 되돌리고 등록부에 쓰지 않는다
rc_register <- function(round_dir, root = rc_root(), registry_path = NULL, ledger = file.path(root, RC_LEDGER_DEFAULT),
                        check_git = TRUE, run_tests = TRUE, review_root = root) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root); P <- rc_paths(round_dir, spec, root)
  if (!file.exists(P$draft) || !file.exists(P$drafts)) stop("[round_core register] 초안이 없다 — draft 먼저")
  D <- rc_json_read(P$drafts); last <- D$versions[[length(D$versions)]]
  if (is.null(last$review)) stop("[round_core register] 마지막 초안 v", last$version, " 이 격리 점검을 받지 않았다")
  if (!identical(last$review$verdict, "ok")) stop("[round_core register] 마지막 점검 판정이 ok 가 아니다(", last$review$verdict, ") — 반영 뒤 새 초안 · 점검")
  if (!identical(rc_md5(P$draft), last$md5)) stop("[round_core register] 디스크 초안 md5 ≠ 마지막 점검받은 판 — 점검받지 않은 초안은 등록하지 않는다")
  pre <- rc_json_read(P$draft)
  if (!identical(spec$.md5, pre$spec_md5)) stop("[round_core register] 사양이 초안 뒤에 바뀌었다 — 새 초안 · 점검")
  for (c in pre$cells) if (!is.null(c$spec) && !identical(rc_md5(rc_abs(c$spec, root)), c$md5)) stop("[round_core register] 칸 사양 md5 ≠ 초안: ", c$code)
  mm <- rc_pins_mismatches(pre$pins, root)
  if (length(mm)) stop("[round_core register] 핀 불일치(초안 뒤 판정 경로가 바뀌었다):\n", paste(mm, collapse = "\n"))
  if (!is.null(pre$rehearsal) && !isTRUE(pre$rehearsal$ok)) stop("[round_core register] 리허설 실패 기록: ", pre$rehearsal$error %||% "")
  tests <- list()
  if (run_tests) for (t in unlist(spec[["tests"]])) {
    o <- suppressWarnings(system2("Rscript", shQuote(rc_abs(t, root)), stdout = TRUE, stderr = TRUE))
    j <- grep('^\\{"test"', o, value = TRUE); r <- if (length(j)) jsonlite::fromJSON(j[length(j)]) else list(pass = NA, fail = NA)
    if (!identical(as.integer(r$fail), 0L)) stop("[round_core register] 라운드 시험 실패: ", t)
    tests[[length(tests) + 1L]] <- list(path = t, md5 = rc_md5(rc_abs(t, root)), pass = r$pass, fail = r$fail)
  }
  p1 <- rc_p1_check(spec[["round_id"]], root, ledger, review_root)
  if (!isTRUE(p1$ok)) stop("[round_core register] 철학 Superfan P1 조건 미충족 — 등록하지 않는다: ", p1$why)
  if (check_git) { unc <- rc_uncommitted(round_dir, spec, root)
    if (length(unc)) stop("[round_core register] 커밋되지 않은 고정 대상 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n")) }
  pre$status <- "registered"; pre$registered_at <- rc_now(); pre$draft_md5 <- rc_md5(P$draft)
  pre$reviewed_drafts <- Filter(function(z) !is.null(z$review), D$versions); pre$philosophy_p1 <- p1; pre$tests <- tests
  pre$git_head_at_register <- rc_git_head(root)
  dir.create(dirname(P$prereg), recursive = TRUE, showWarnings = FALSE)
  variants <- vapply(Filter(function(c) identical(c$role, "variant"), pre$cells), function(c) c$code, character(1))
  tryCatch({
    rc_json_write(pre, P$prereg)
    if (!isTRUE(file.copy(P$prereg, P$prereg_copy, overwrite = TRUE)) || !identical(rc_md5(P$prereg_copy), rc_md5(P$prereg))) stop("라운드 디렉터리 사본 쓰기 실패")
    pr_record_round(spec[["program"]], list(round_id = spec[["round_id"]], prereg = P$prereg_rel, prereg_md5 = rc_md5(P$prereg), status = "registered",
                                           core = pre$core$version, n_variants = length(variants), variants = as.list(unname(vapply(pre$cells, function(c) c$code, character(1))))),
                    root = root, path = registry_path)
  }, error = function(e) { unlink(c(P$prereg, P$prereg_copy)); stop("[round_core register] 등록 중단 — 두 사본을 되돌렸다(등록부 미기록): ", conditionMessage(e)) })
  invisible(list(prereg = P$prereg_rel, md5 = rc_md5(P$prereg), head = pre$git_head_at_register))
}

## 종료 기록 — verdict.json(판정 단일 출처)에서 등록부 결과를 만든다 · 해석 메모 · 리뷰 id 는 Q 가 넘긴다
rc_close <- function(round_dir, note, philosophy_p2 = NA_character_, superfan_t2 = NA_character_, extra = list(),
                     root = rc_root(), registry_path = NULL) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root, check_files = FALSE); P <- rc_paths(round_dir, spec, root)
  V <- rc_json_read(file.path(P$results, "verdict.json"))
  if (!identical(V$prereg_md5, rc_md5(P$prereg))) stop("[round_core close] 판정이 지금 사전등록(md5)으로 난 것이 아니다(R2)")
  pr_record_round(spec[["program"]], c(list(round_id = spec[["round_id"]], prereg = P$prereg_rel, prereg_md5 = rc_md5(P$prereg), status = "complete",
                                           verdict = c(V$summary, list(note = note)), philosophy_p2 = philosophy_p2, superfan_t2 = superfan_t2,
                                           report = rc_rel(file.path(P$results, "verdict.json"), root)), extra),
                  root = root, path = registry_path)
  invisible(TRUE)
}
