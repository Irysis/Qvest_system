## round_core v1 · driver — 단계 실행(라운드별 measure.sh · evaluate.R · notify.R · close_round.R 대체)
##   CLI: Rscript 04_Research/programs/_lib/round_core/v1/driver.R <round_dir> <단계> [인자]
##     check            사양 검사 · 규칙 문장 · 핀 계산 가능 여부(쓰기 없음)
##     precheck         등록 확인(R2) · 핀 재대조 — 측정 직전(불일치 = 종료 코드 3)
##     plan             측정할 칸 목록(엔진 · 칸 · 역할) — round.sh 가 읽는다
##     draft            사전등록 초안(.json + .md) · drafts.json 판 추가
##     reviewed <v> <점검 파일> <ok|revise>   격리 교차 점검 기록
##     register         등록(조건 ①~⑧) — 끝나면 커밋 명령을 출력
##     evaluate [--cells-only] [--shard=i/K]   칸 평가(내용 주소 캐시) → 판정(verdict.json · evaluation_visible.json)
##     evaluate --pairs-only --shard=i/K · evaluate --merge   짝 판정 템플릿(P2 · P3) 최종 판정의 짝 평가 샤딩 → 병합 종합(P1 은 무시)
##     report [--send] [--next "<다음 단계>"]  보고(기본 dry-run)
##     close --note "<해석>" --probe "<다음 탐침>" --probe "<…>" [--lesson "<교훈>"]… [--r7 noise|signal] [--p2 <id>] [--t2 <id>]
##           종료 기록(등록부 + 결과 원장 06_Registry/round_outcomes.jsonl) · 탐침 2개 미만이면 --no-probes "<사유>" · 글에 τ_D 뒤 날짜가 있으면 멈춤
##     fresh-check      측정 경로 데이터 신선도(v1/freshness.R · 종료 0 신선 · 6 낡음 · 판독 불가)
##     P4 강화 사슬(v1/p4.R · <round_dir> = 사슬 디렉터리): p4-pool [--out f] · p4-base-spec --key <풀 key> --out f · p4-check ·
##       p4-register --p1 <철학 P1 id> --t1 <판단 T1 id> · p4-design [--out f] ·
##       p4-base-measure(기준 칸 k = 0 · 걸음 전 필수 · 종료 0 · 4 배리어 · 1 실패 · 판 표식 변경/불명 = 1) ·
##       p4-step-open --k --hypothesis --mechanism --block --cell --parent --generator · p4-step-measure --k(종료 0 측정 · 4 배리어 · 1 실패) ·
##       p4-step-decide --k [--artifacts](측정 기록과 같아야 한다) · p4-status ·
##       p4-close --note --probe ×2 [--lesson] [--r7] [--no-probes] [--regrade-write] --p2 <철학 P2 id> --t2 <판단 T2 id> · p4-generator-review [--out f]
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
  } else if (spec[["template"]] %in% c("p2_device", "p3_construction"))            # 짝 판정 템플릿(WP1-b) — 판정어별 칸 수가 든 라벨
    list(label = V$verdict_label, verdict = V$verdict, n_judged = V$n_judged, n_total = V$n_total, validated = as.list(V$validated %||% character(0)))
  else list(label = "요약 없음(템플릿 미지원)")
}

## 짝 판정 템플릿(P2 · P3)의 칸 평가 = 보는 창 / 사람 쪽 분리판(내용 주소 키 · MC8 카드 캐시)
.rc_pair_templates <- c("p2_device", "p3_construction")
rc_eval_cell_pairtpl <- function(root, round_dir, c, env, tau) {
  env$mc8_cache <- TRUE
  rc_eval_cell_split(root, file.path(round_dir, "results"), list(code = c[["code"]], engine = c[["engine"]], component = c[["component"]],
                                                                 diagnostic = identical(c[["role"]], "diagnostic"), path = c[["spec"]]), env, tau, cache = "key")
}
##   pairs_only + shard = 최종 판정의 짝 평가 샤드(워커 · RDS) · merge = 샤드 결과 병합 뒤 종합(P1 템플릿에서는 무시)
rc_evaluate <- function(round_dir, root = rc_root(), cells_only = FALSE, shard = NULL, registry_path = NULL, pairs_only = FALSE, merge = FALSE) {
  spec <- rc_spec_load(file.path(round_dir, "round_spec.json"), root = root); P <- rc_paths(round_dir, spec, root)
  pre <- rc_registered(spec, P, root, registry_path)
  mm <- rc_pins_mismatches(pre$pins, root)
  if (length(mm)) stop("[round_core evaluate] 핀 불일치 — 판정하지 않는다:\n", paste(mm, collapse = "\n"))
  pairtpl <- spec[["template"]] %in% .rc_pair_templates
  if (isTRUE(pairs_only)) {
    if (!pairtpl) return(invisible(TRUE))
    fn <- switch(spec[["template"]], p2_device = rc_p2_evaluate, p3_construction = rc_p3_evaluate)
    return(invisible(fn(spec, pre, root, round_dir, P, shard = shard, merge = FALSE)))
  }
  env <- rc_eval_env(root, spec[["behavior_card_cfg"]]); tau <- as.Date(spec[["tau_d"]])
  own <- rc_shard_cells(Filter(function(c) !is.null(c[["spec"]]), spec[["cells"]]), shard)
  cell_fn <- if (pairtpl) rc_eval_cell_pairtpl else rc_eval_cell
  for (c in own) {
    t0 <- Sys.time()
    ev <- rc_safe(cell_fn, root, round_dir, c, env, tau, what = c[["code"]])
    rc_perf_log(spec[["round_id"]], "eval_cell", difftime(Sys.time(), t0, units = "secs"), list(code = c[["code"]], ok = ev$ok), root = root)
    cat(sprintf("[평가] %s %s\n", c[["code"]], if (ev$ok) ev$value$status %||% "?" else paste("미시험 —", ev$error)))
  }
  if (cells_only) return(invisible(TRUE))
  t0 <- Sys.time()
  V <- switch(spec[["template"]],
              p1_qualification = rc_p1_evaluate(spec, pre$rules_resolved, root),
              p2_device = rc_p2_evaluate(spec, pre, root, round_dir, P, merge = merge),
              p3_construction = rc_p3_evaluate(spec, pre, root, round_dir, P, merge = merge),
              stop("[round_core evaluate] 이 템플릿의 판정은 아직 코어에 없다: ", spec[["template"]]))
  V$prereg_md5 <- rc_md5(P$prereg); V$summary <- rc_summary(spec, V)
  rc_json_write(V, file.path(P$results, "verdict.json"))
  if (!isTRUE(V$writes_visible)) {                                               # 짝 판정 템플릿은 보는 창 · 사람 쪽 파일을 스스로 쓴다(전수 검사 뒤)
    vis <- V; vis$table <- V$table[, !grepl("_test$", names(V$table)), with = FALSE]; vis$rules <- NULL
    vis <- rc_redact_after_tau(vis, tau)
    lk <- rc_after_tau_leaks(vis, tau)
    if (length(lk)) stop("[round_core evaluate] 보는 창 파일에 τ_D 이후 날짜가 남았다: ", paste(head(lk, 5), collapse = ","))
    vis$audience <- "보는 창(τ_D 이전) — 시험 창 열 제외 · 처방 · 리뷰 레인 열람 가능"
    rc_json_write(vis, file.path(P$results, "evaluation_visible.json"))
  }
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
    evaluate = { if (!is.na(sh)) data.table::setDTthreads(1L)                  # 샤드 워커 = 1스레드(K 병렬 과다 구독 방지 · PERFORMANCE.md)
                 rc_evaluate(rd, ROOT, cells_only = flag("--cells-only"), shard = if (is.na(sh)) NULL else sh,
                             pairs_only = flag("--pairs-only"), merge = flag("--merge")) },
    report = rc_report(rd, ROOT, send = flag("--send"), next_step = opt("--next")),
    close = { multi <- function(k) { i <- which(rest == k); i <- i[i < length(rest)]; if (length(i)) rest[i + 1L] else character(0) }   # 되풀이 인자
              rc_close(rd, note = opt("--note") %||% stop("--note 필요"), philosophy_p2 = opt("--p2") %||% NA_character_,
                       superfan_t2 = opt("--t2") %||% NA_character_, root = ROOT, probes = multi("--probe"), lessons = multi("--lesson"),
                       r7 = opt("--r7") %||% NA_character_, no_probes_reason = opt("--no-probes"))
              cat("[close] 등록부 · 결과 원장 기록\n") },
    ## ── P4 강화 사슬(v1/p4.R · <round_dir> = 사슬 디렉터리 · p4-pool · p4-generator-review 는 '-' 도 된다) ──
    "p4-pool" = { P <- rc_p4_base_pool(ROOT)
                  if (!is.null(opt("--out"))) rc_json_write(list(schema = RC_P4_POOL_SCHEMA, at = rc_now(), pool_md5 = rc_p4_pool_md5(P), table = P), opt("--out"))
                  cat(sprintf("[p4-pool] 엔진 %d · 자격 %d · 풀 md5 %s\n", nrow(P), sum(P$eligible), substr(rc_p4_pool_md5(P), 1, 8)))
                  for (i in seq_len(nrow(P))) cat(sprintf("  %s %s · %s\n", if (P$eligible[i]) "[자격]" else "[제외]", P$key[i], if (nzchar(P$reason[i])) P$reason[i] else "—")) },
    "p4-check" = { rr <- rc_p4_chain_check(rc_json_read(rc_p4_spec_path(rd)), ROOT)
                   cat(paste0("- ", rc_rules_sentences(rr)), sep = "\n"); cat("[p4-check] 사슬 판 검사 통과\n") },
    "p4-base-spec" = { out <- rc_p4_base_cell_spec(opt("--key") %||% stop("--key 필요"), rc_p4_base_pool(ROOT), ROOT, opt("--out") %||% stop("--out 필요"))
                       cat(sprintf("[p4-base-spec] %s → %s · md5 %s\n", opt("--key"), rc_rel(out, ROOT), rc_md5(out))) },
    "p4-register" = { rc_p4_chain_register(rd, rc_p4_base_pool(ROOT), ROOT, p1 = opt("--p1"), t1 = opt("--t1")); cat("[p4-register] 사슬 판 등록(원장 첫 줄)\n") },
    "p4-base-measure" = { r <- rc_p4_base_measure(rd, ROOT)
                          cat(sprintf("[p4-base-measure] 기준 칸 — %s%s\n", r$status, if (!is.null(r$reason)) paste0(" · ", r$reason) else ""))
                          quit(status = switch(r$status, measured = 0L, already = 0L, barrier_held = 4L, data_stale = 6L, busy = 7L, 1L)) },
    "p4-step-measure" = { r <- rc_p4_step_measure(rd, opt("--k") %||% stop("--k 필요"), ROOT)
                          cat(sprintf("[p4-step-measure] 걸음 %s — %s%s\n", r$k, r$status, if (!is.null(r$reason)) paste0(" · ", r$reason) else ""))
                          quit(status = switch(r$status, measured = 0L, already = 0L, barrier_held = 4L, data_stale = 6L, busy = 7L, 1L)) },
    "p4-design" = { txt <- rc_p4_design_input(ROOT, rd, pool = rc_p4_base_pool(ROOT), out = opt("--out") %||% file.path(rd, "design_input.md"))
                    cat(sprintf("[p4-design] 설계 입력 %d줄 → %s\n", length(strsplit(txt, "\n")[[1]]), rc_rel(opt("--out") %||% file.path(rd, "design_input.md"), ROOT))) },
    "p4-step-open" = { rc_p4_step_open(rd, opt("--k"), opt("--hypothesis"), opt("--mechanism"), opt("--block"), opt("--cell"), opt("--parent"),
                                       opt("--generator"), ROOT, pool = rc_p4_base_pool(ROOT), probe_ref = opt("--probe-ref")); cat("[p4-step-open] 걸음 원장 기록\n") },
    "p4-quarantine" = { q <- rc_p4_steps_quarantine(rd, opt("--line") %||% stop("--line 필요"), opt("--reason") %||% stop("--reason 필요"))
                        cat(sprintf("[p4-quarantine] 걸음 원장 줄 %s 격리(md5 %s) — 사본 chain_steps.quarantine.jsonl\n", q$line, substr(q$line_md5, 1, 8))) },
    "outcomes-quarantine" = { m <- rc_outcomes_quarantine(opt("--path") %||% rc_outcomes_path(ROOT), opt("--line") %||% stop("--line 필요"), opt("--reason") %||% stop("--reason 필요"))
                              cat(sprintf("[outcomes-quarantine] 결과 원장 줄 격리(md5 %s)\n", substr(m, 1, 8))) },
    "p4-step-decide" = { r <- rc_p4_step_decide(rd, opt("--k"), opt("--artifacts"), ROOT)
                         cat(sprintf("[p4-step-decide] 걸음 %s — %s(산출 출처 %s)\n", r$k, r$decision, r$artifacts_source)) },
    "p4-step-abandon" = { rc_p4_step_abandon(rd, opt("--k") %||% stop("--k 필요"), opt("--reason") %||% stop("--reason 필요"), ROOT); cat("[p4-step-abandon] 걸음 포기 기록(기각 · 산출 없음)\n") },
    "p4-workdir" = { if (!exists("rx_toolbox_md", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/rx_round.R")))))
                     fs <- rc_p4_generator_workdir(rd, opt("--out") %||% stop("--out 필요(사슬 디렉터리 밖 빈 폴더)"), ROOT, pool = rc_p4_base_pool(ROOT))
                     cat(sprintf("[p4-workdir] 생성기 작업 디렉터리 %d파일 → %s\n", length(fs), dirname(fs[1]))) },
    "fresh-check" = { f <- rc_data_freshness(ROOT)
                      cat(sprintf("[신선도] %s · 기준일 %s · %s\n", f$state, f$as_of, f$reason))
                      quit(status = if (isTRUE(f$ok)) 0L else 6L) },
    "p4-status" = writeLines(rc_p4_status(rd, ROOT)),
    "p4-close" = { multi <- function(k) { i <- which(rest == k); i <- i[i < length(rest)]; if (length(i)) rest[i + 1L] else character(0) }
                   ## 닫기는 한 번뿐이다 — 재채점 쓰기 여부를 명시해야 닫는다(11-10 · 드라이런으로 닫으면 권위 등급 재채점 · 관문 · 등재를 다시 할 길이 없다)
                   if (flag("--regrade-write") == flag("--regrade-dry-run")) stop("p4-close: --regrade-write(운영) 또는 --regrade-dry-run(시험) 중 하나를 명시한다")
                   r <- rc_p4_close(rd, note = opt("--note") %||% stop("--note 필요"), probes = multi("--probe"), lessons = multi("--lesson"),
                                    r7 = opt("--r7") %||% NA_character_, no_probes_reason = opt("--no-probes"), root = ROOT, regrade_write = flag("--regrade-write"),
                                    philosophy_p2 = opt("--p2") %||% NA_character_, superfan_t2 = opt("--t2") %||% NA_character_)
                   cat(sprintf("[p4-close] %s · 마감 %s\n", r$label, r$finalize$status)) },
    "p4-generator-review" = { r <- rc_p4_generator_review(ROOT, out = opt("--out")); cat(r$md, sep = "\n") },
    stop("모르는 단계: ", st))
}
