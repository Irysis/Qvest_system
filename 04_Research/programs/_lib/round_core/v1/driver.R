## round_core v1 · driver — 단계 실행(라운드별 measure.sh · evaluate.R · notify.R · close_round.R 대체)
##   CLI: Rscript 04_Research/programs/_lib/round_core/v1/driver.R <round_dir> <단계> [인자]
##     check            사양 검사 · 규칙 문장 · 핀 계산 가능 여부(쓰기 없음)
##     precheck         등록 확인(R2) · 핀 재대조 — 측정 직전(불일치 = 종료 코드 3)
##     plan             측정할 칸 목록(엔진 · 칸 · 역할) — round.sh 가 읽는다
##     draft            사전등록 초안(.json + .md) · drafts.json 판 추가
##     reviewed <v> <점검 파일> <ok|revise>   격리 교차 점검 기록
##     register         등록(조건 ①~⑧) — 끝나면 커밋 명령을 출력
##     evaluate [--cells-only] [--shard=i/K]   칸 평가(내용 주소 캐시) → 판정(verdict.json · evaluation_visible.json)
##     report [--send] [--next "<다음 단계>"]  보고(기본 dry-run)
##     close --note "<해석>" [--p2 <id>] [--t2 <id>]   종료 기록(등록부)
##   수치는 R 계약 산출만 · 판정은 등록 때 해석된 규칙(rules_resolved)으로만(R2) · 시험 창 열은 보는 창 파일에 싣지 않는다(τ_D).

rc_shard_cells <- function(cells, shard) {
  if (is.null(shard)) return(cells)
  v <- suppressWarnings(as.integer(strsplit(shard, "/", fixed = TRUE)[[1]]))
  if (length(v) != 2L || anyNA(v) || v[2] < 1L || v[1] < 1L || v[1] > v[2]) stop("[round_core] --shard=i/K 형식 오류: ", shard)
  cells[(seq_along(cells) - 1L) %% v[2] == (v[1] - 1L)]
}

## 등록 상태 확인(R2) — 사전등록 파일이 있고 md5 가 등록부 값과 같아야 측정 · 판정한다
rc_registered <- function(spec, P, root = rc_root(), registry_path = NULL) {
  if (!file.exists(P$prereg)) stop("[round_core] 등록 전이다 — register 먼저(R2: 측정 전 등록)")
  reg <- pr_load(root, registry_path)
  rr <- Filter(function(r) identical(r$round_id, spec[["round_id"]]), pr_get(reg, spec[["program"]])$rounds %||% list())
  if (!length(rr) || !identical(rr[[1]]$prereg_md5, rc_md5(P$prereg))) stop("[round_core] 사전등록 md5 ≠ 등록부(R2)")
  rc_json_read(P$prereg)
}

## 판정 요약(템플릿별) — 보고 · 종료 기록 · 등록부가 이 한 곳을 읽는다(판정 기록 단일 출처)
rc_summary <- function(spec, V) {
  if (identical(spec[["template"]], "p1_qualification")) {
    T <- V$table; ne <- sum(T$status == "evaluated")
    list(label = sprintf("자격 %d/%d(평가 %d)%s", length(V$qualified), nrow(T), ne,
                         if (length(V$qualified)) paste0(" — ", paste(V$qualified, collapse = " · ")) else ""),
         qualified = as.list(V$qualified), n_cells = nrow(T), n_evaluated = ne)
  } else list(label = "요약 없음(템플릿 미지원)")
}

rc_evaluate <- function(round_dir, root = rc_root(), cells_only = FALSE, shard = NULL, registry_path = NULL) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root); P <- rc_paths(round_dir, spec, root)
  pre <- rc_registered(spec, P, root, registry_path)
  mm <- rc_pins_mismatches(pre$pins, root)
  if (length(mm)) stop("[round_core evaluate] 핀 불일치 — 판정하지 않는다:\n", paste(mm, collapse = "\n"))
  env <- rc_eval_env(root, spec[["behavior_card_cfg"]]); tau <- as.Date(spec[["tau_d"]])
  own <- rc_shard_cells(Filter(function(c) !is.null(c[["spec"]]), spec[["cells"]]), shard)
  for (c in own) {
    t0 <- Sys.time()
    ev <- rc_safe(rc_eval_cell, root, round_dir, c, env, tau, what = c[["code"]])
    rc_perf_log(spec[["round_id"]], "eval_cell", difftime(Sys.time(), t0, units = "secs"), list(code = c[["code"]], ok = ev$ok), root = root)
    cat(sprintf("[평가] %s %s\n", c[["code"]], if (ev$ok) ev$value$status %||% "?" else paste("미시험 —", ev$error)))
  }
  if (cells_only) return(invisible(TRUE))
  t0 <- Sys.time()
  V <- switch(spec[["template"]],
              p1_qualification = rc_p1_evaluate(spec, pre$rules_resolved, root),
              stop("[round_core evaluate] 이 템플릿의 판정은 아직 코어에 없다: ", spec[["template"]]))
  V$prereg_md5 <- rc_md5(P$prereg); V$summary <- rc_summary(spec, V)
  rc_json_write(V, file.path(P$results, "verdict.json"))
  vis <- V; vis$table <- V$table[, !grepl("_test$", names(V$table)), with = FALSE]; vis$rules <- NULL
  vis <- rc_redact_after_tau(vis, tau)
  lk <- rc_after_tau_leaks(vis, tau)
  if (length(lk)) stop("[round_core evaluate] 보는 창 파일에 τ_D 이후 날짜가 남았다: ", paste(head(lk, 5), collapse = ","))
  vis$audience <- "보는 창(τ_D 이전) — 시험 창 열 제외 · 처방 · 리뷰 레인 열람 가능"
  rc_json_write(vis, file.path(P$results, "evaluation_visible.json"))
  rc_perf_log(spec[["round_id"]], "judge", difftime(Sys.time(), t0, units = "secs"), root = root)
  cat(sprintf("[판정] %s — %s\n", spec[["round_id"]], V$summary$label))
  invisible(V)
}

rc_report <- function(round_dir, root = rc_root(), send = FALSE, next_step = NULL) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root, check_files = FALSE); P <- rc_paths(round_dir, spec, root)
  V <- rc_json_read(file.path(P$results, "verdict.json"))
  if (!exists("prep_send", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure/programs/program_report.R")))))
  prep_send(program = spec[["program_name"]] %||% spec[["program"]], target = spec[["target_name"]] %||% spec[["round_id"]],
            status = list(stage = "판정", position = spec[["round_id"]], previous = spec[["previous"]] %||% ""),
            verdict_line = V$summary$label, next_step = next_step %||% spec[["next_step"]] %||% "",
            artifact = rc_rel(P$results, root), push = isTRUE(send), dry_run = !isTRUE(send), root = root)
}

## CLI
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) < 2L) stop("usage: driver.R <round_dir> <stage> [args]")
  source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "04_Research/programs/_lib/round_core/v1/load.R"))
  ROOT <- rc_root(); setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
  rd <- rc_abs(a[1], ROOT); st <- a[2]; rest <- a[-(1:2)]
  opt <- function(k) { i <- match(k, rest); if (is.na(i) || i == length(rest)) NULL else rest[i + 1L] }
  flag <- function(k) k %in% rest
  sh <- sub("^--shard=", "", grep("^--shard=", rest, value = TRUE)[1])
  switch(st,
    check = { s <- rc_spec_load(file.path(rd, "round_spec.json"), ROOT); rr <- rc_rules_resolve(s[["rules"]], ROOT)
              cat(paste0("- ", rc_rules_sentences(rr)), sep = "\n"); p <- rc_pins_compute(s, ROOT)
              cat(sprintf("[check] %s · 칸 %d · 핀 파일 %d · 코어 %s/%s\n", s[["round_id"]], length(s[["cells"]]), length(p$files),
                          p$core$version, substr(p$core$manifest_md5, 1, 8))) },
    precheck = { s <- rc_spec_load(file.path(rd, "round_spec.json"), ROOT); pre <- rc_registered(s, rc_paths(rd, s, ROOT), ROOT)
                 mm <- rc_pins_mismatches(pre$pins, ROOT)
                 if (length(mm)) { cat("[precheck] 핀 불일치 — 측정하지 않는다:
", paste(mm, collapse = "
"), "
"); quit(status = 3) }
                 cat(sprintf("[precheck] %s 등록 · 핀 %d 일치
", s[["round_id"]], length(pre$pins$files))) },
    plan = { s <- rc_spec_load(file.path(rd, "round_spec.json"), ROOT)
             for (c in s[["cells"]]) if (!is.null(c[["spec"]])) cat(c[["engine"]], c[["code"]], c[["role"]], "\n") },
    draft = { d <- rc_draft(rd, ROOT); cat(sprintf("[draft] v%d · md5 %s · %s\n", d$version, d$md5, rc_rel(d$md, ROOT))) },
    reviewed = { r <- rc_mark_reviewed(rd, rest[1], rest[2], rest[3], ROOT); cat(sprintf("[reviewed] v%s · %s\n", r$version, r$review$verdict)) },
    register = { r <- rc_register(rd, ROOT); cat(sprintf("[register] %s · md5 %s · HEAD %s\n다음: git add 사전등록 두 사본 · 등록부 → 커밋 → measure\n",
                                                         r$prereg, r$md5, substr(r$head, 1, 9))) },
    evaluate = rc_evaluate(rd, ROOT, cells_only = flag("--cells-only"), shard = if (is.na(sh)) NULL else sh),
    report = rc_report(rd, ROOT, send = flag("--send"), next_step = opt("--next")),
    close = { rc_close(rd, note = opt("--note") %||% stop("--note 필요"), philosophy_p2 = opt("--p2") %||% NA_character_,
                       superfan_t2 = opt("--t2") %||% NA_character_, root = ROOT); cat("[close] 등록부 기록\n") },
    stop("모르는 단계: ", st))
}
