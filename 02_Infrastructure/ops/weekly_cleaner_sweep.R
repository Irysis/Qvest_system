# =============================================================================
# weekly_cleaner_sweep.R — 주간 Cleaner 기계 스윕 (무인, 토 09:00 Task Scheduler)
#
# (2026-07-04 도훈 mandate — "정크 삭제 + 위클리 리서치 엑기스 추출·탑재".
#  설계: 스킬+스케줄러 하이브리드 — 무인 LLM 호출은 권한/판단 리스크로 배제.
#  기계 스윕만 여기서 무인 실행, LLM 증류는 다음 세션 /cleaner 스킬이 수행.)
#
# 단계 (전부 fail-soft — 한 단계 실패해도 나머지 계속):
#   [1] artifact_hygiene_audit.R 재사용 실행 (일간 정리 로직 — 중복 구현 금지, 시스템콜)
#   [2] 주간 추가 스윕 (일간보다 공격적):
#       2a. .cache 루트 '_' 접두 스크래치 7일+ 삭제 (일간 30일 → 주간 7일. keep-list 보호 유지)
#       2b. OS temp qm_/qvest_ 접두 *.log 30일+ 삭제 (일간 90일 → 주간 30일)
#       (빈 디렉토리는 [1] hygiene audit (a3)가 이미 처리 — 재구현 안 함)
#   [3] 주간 리서치 인벤토리 수집:
#       stage_artifacts 지난 7일 신규 엔트리 / hypothesis_index 델타 / 신규 L-code /
#       git log --since 요약
#   [3.5] 주간 axiom 사이클 (2026-07-04 — Cleaner 통합이 정규 경로, axiom_weekly.sh 대체):
#       lcode_harvester → cluster_extractor → promote 진단(candidate 순회, INV-4 hurdle)
#       + cleaner_pending.json에 axiom_candidates 섹션{n_pending, failing_axis_histogram, near_miss}
#       (engine-core 스크립트 호출만 — 중복 구현 금지. DRY 시 promote 생략·현황 집계만)
#   [4] .cache/cleaner_pending.json 기록 (schema cleaner_pending_v2)
#       {week_of, sweep_deleted_n, inventory, status:"awaiting_distill",
#        distill_status:"pending", distill_owner:null, distill_claimed_at:null}
#       → bootstrap.sh가 status 마커 감지해 "/cleaner 실행" WARN 노출 (증류는 세션에서)
#       → distill_status(pending/in_progress/done) = 증류 착수 선점 표시. /cleaner 세션이
#         cleaner_claim.R::cleaner_claim_distill()로 in_progress 점유해 2-pass 중복실행 방지
#         (W29 next_probe #4, 2026-07-18. 07-06 병렬 중복실행 사고 ops 재현).
#   [5] 텔레그램 알림 (tg_agent_brief 규약 재사용, 실패 fail-soft)
#
# 모든 삭제는 .cache/hygiene_manifest.log 에 kind=weekly_* 로 기록 (일간 감사와 동일 매니페스트).
# dry-run: QVEST_CLEANER_DRY=1 / 텔레그램 억제: QVEST_CLEANER_NO_TG=1
# 실행: Rscript 02_Infrastructure/ops/weekly_cleaner_sweep.R
#       (Task Scheduler: 02_Infrastructure/ops/scheduler/Qvest_WeeklyCleaner.bat)
# 규칙 SOT: 02_Infrastructure/docs/rules/artifact-storage.md §8 3선
# =============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

`%||%` <- function(a, b) if (is.null(a)) b else a

DRY <- Sys.getenv("QVEST_CLEANER_DRY", "0") == "1"
WEEKLY_SCRATCH_DAYS <- 7    # .cache 루트 '_' 스크래치 (일간 감사 30일보다 공격적)
WEEKLY_LOG_DAYS     <- 30   # OS temp qm_/qvest_ 로그 (일간 감사 90일보다 공격적)
INVENTORY_DAYS      <- 7
now <- Sys.time()

# ---- 경로 해석 (artifact_hygiene_audit.R 동일 패턴 — normalizePath 미사용) ----
root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root)) {
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  if (length(fa) == 1) {
    sd   <- gsub("\\\\", "/", dirname(sub("^--file=", "", fa)))
    root <- sub("/02_Infrastructure/ops/?$", "", sd)
  } else root <- getwd()
}
root <- sub("/+$", "", gsub("\\\\", "/", root))
if (!dir.exists(file.path(root, "02_Infrastructure")))
  stop("[cleaner] project root 미해석: ", root)
registry_zone <- if (dir.exists(file.path(root, "06_Registry"))) "06_Registry" else "07_Registry"

cat(sprintf("[cleaner] weekly sweep start @ %s root=%s dry_run=%s\n",
            format(now, "%Y-%m-%d %H:%M:%S"), root, DRY))

# ---- 스윕 실행 lock (bootstrap 6b 검사 인터페이스) ----
#   pid·ts(epoch) 기록 — 비정상 종료 잔존 lock은 소비측이 ts 기준 stale(>2h) 무시.
#   정상/오류 종료 공통 삭제: 말미 명시 unlink + R 종료 finalizer(top-level stop 대비) 이중.
sweep_lock_path <- file.path(root, ".cache", "cleaner_sweep.lock")
try({
  dir.create(dirname(sweep_lock_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(as.character(toJSON(list(
    pid = Sys.getpid(), ts = as.numeric(now),
    ts_human = format(now, "%Y-%m-%d %H:%M:%S"),
    script = "02_Infrastructure/ops/weekly_cleaner_sweep.R"), auto_unbox = TRUE)),
    sweep_lock_path)
}, silent = TRUE)
invisible(reg.finalizer(globalenv(),
                        local({ lp <- sweep_lock_path; function(e) suppressWarnings(unlink(lp)) }),
                        onexit = TRUE))

# ---- fail-soft 실행기: 단계별 오류를 status에 기록하고 계속 ----
#   주의: expr(promise)은 호출부(global) 환경에서 평가됨 — expr 안에서는 일반 `<-`로
#   전역을 직접 갱신한다 (`x$y <<-`는 global의 부모(패키지 경로)를 탐색해 not-found 오류).
step_status <- list()
run_step <- function(name, expr) {
  res <- tryCatch(expr, error = function(e) {
    cat(sprintf("[cleaner][WARN] step %s FAIL: %s (계속 진행)\n", name, conditionMessage(e)))
    structure(list(error = conditionMessage(e)), class = "cleaner_step_error")
  })
  step_status[[name]] <<- if (inherits(res, "cleaner_step_error"))
    paste0("FAIL: ", res$error) else "OK"
  invisible(res)
}

manifest_path <- file.path(root, ".cache", "hygiene_manifest.log")
log_deletion <- function(kind, path) {
  line <- sprintf("%s\t%s\t%s%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  kind, path, if (DRY) "\t[DRY]" else "")
  try(cat(line, "\n", sep = "", file = manifest_path, append = TRUE), silent = TRUE)
}

# =============================================================================
# [1] 일간 위생 감사 재사용 — artifact_hygiene_audit.R 시스템콜 (중복 구현 금지)
#     별도 R 프로세스로 실행: 감사 스크립트는 top-level 실행형이라 source 시
#     본 스크립트 전역과 섞임 — 시스템콜이 안전. dry 플래그 전파.
# =============================================================================
hygiene_deleted_n <- NA_integer_
# (2026-07-26 WCS-09) 일간 감사의 경고 필드를 주간 표면까지 운반 — 부분 소비로 위반이
#   소멸하던 경로. run_step 은 promise(global 평가)라 `<<-` 가 필요하므로 전역 선언.
hygiene_warn_n <- NA_integer_
hygiene_warn_top <- list()
run_step("hygiene_audit", {
  audit_r <- file.path(root, "02_Infrastructure", "ops", "artifact_hygiene_audit.R")
  if (!file.exists(audit_r)) stop("artifact_hygiene_audit.R 부재")
  # env는 Sys.setenv로 전달 (system2 env= 는 Windows에서 미지원 계열 — 자식은 부모 환경 상속)
  Sys.setenv(QM_ROOT = root, QVEST_HYGIENE_DRY = if (DRY) "1" else "0")
  out <- suppressWarnings(system2("Rscript", shQuote(audit_r), stdout = TRUE, stderr = TRUE))
  if (length(out)) cat(paste0("  | ", out, collapse = "\n"), "\n")
  st <- attr(out, "status")
  if (!is.null(st) && st != 0) stop(sprintf("audit exit=%s (출력 위 참조)", st))
  rep_path <- file.path(root, registry_zone, "hygiene_report.json")
  if (file.exists(rep_path)) {
    rep <- tryCatch(fromJSON(rep_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(rep)) {
      hygiene_deleted_n <- as.integer(rep$cleanup$n_deleted %||% NA)
      # (2026-07-26 WCS-09 수리) 구현은 n_deleted 만 읽고 경고 필드를 버려, 일간 감사가
      #   적발한 위생 위반이 주간 표면에서 **소멸**했다(부분 소비 = 정보 손실).
      hygiene_warn_n <<- as.integer(rep$cleanup$n_warnings %||% rep$n_warnings %||% NA)
      .hw <- rep$warnings %||% rep$cleanup$warnings %||% list()
      hygiene_warn_top <<- as.list(head(unlist(lapply(.hw, function(x) as.character(x)[1])), 5))
    }
  }
  invisible(TRUE)
})

# =============================================================================
# [2a] .cache 루트 '_' 접두 스크래치 7일+ 삭제 (주간 공격 정리 — keep-list 보호)
#      artifact-storage.md §3.1/§4: '_' 접두 = 재생성 가능 체크포인트 (canonical=outputs/).
#      keep-list는 artifact_hygiene_audit.R::CACHE_ROOT_KEEP 와 동기 유지.
# =============================================================================
CACHE_ROOT_KEEP <- c("update_file_last_processed.rds", "lens2_liq_sweep.rds")
weekly_deleted <- list(cache_scratch = character(0), temp_logs = character(0))
run_step("weekly_cache_scratch_7d", {
  cache_root <- file.path(root, ".cache")
  if (dir.exists(cache_root)) {
    rf <- list.files(cache_root, pattern = "^_.*\\.(rds|txt|out|log|R)$",
                     full.names = TRUE, all.files = TRUE, no.. = TRUE)
    rf <- rf[!(basename(rf) %in% CACHE_ROOT_KEEP)]
    if (length(rf)) {
      age <- suppressWarnings(as.numeric(difftime(now, file.info(rf)$mtime, units = "days")))
      old <- rf[!is.na(age) & age > WEEKLY_SCRATCH_DAYS]
      for (f in old) {
        ok <- if (DRY) TRUE else isTRUE(suppressWarnings(file.remove(f)))
        if (ok) { weekly_deleted$cache_scratch <- c(weekly_deleted$cache_scratch, f)
                  log_deletion("weekly_cache_scratch7d", f) }
      }
    }
  }
  invisible(TRUE)
})

# =============================================================================
# [2b] OS temp qm_/qvest_ 접두 *.log 30일+ 삭제 (주간 공격 정리)
# =============================================================================
run_step("weekly_temp_logs_30d", {
  log_dirs <- unique(Filter(function(d) nzchar(d) && dir.exists(d), c(
    gsub("\\\\", "/", Sys.getenv("TEMP", "")),
    gsub("\\\\", "/", Sys.getenv("TMP", "")),
    "C:/Users/99922/AppData/Local/Temp",
    "/tmp")))
  for (ld in log_dirs) {
    fs <- list.files(ld, pattern = "^(qm_|qvest_).*\\.log$", full.names = TRUE)
    if (!length(fs)) next
    age <- suppressWarnings(as.numeric(difftime(now, file.info(fs)$mtime, units = "days")))
    old <- fs[!is.na(age) & age > WEEKLY_LOG_DAYS]
    for (f in old) {
      ok <- if (DRY) TRUE else isTRUE(suppressWarnings(file.remove(f)))
      if (ok) { weekly_deleted$temp_logs <- c(weekly_deleted$temp_logs, f)
                log_deletion("weekly_log30d", f) }
    }
  }
  invisible(TRUE)
})

# =============================================================================
# [3] 주간 리서치 인벤토리 (지난 7일) — 증류 세션(/cleaner)의 입력
# =============================================================================
cutoff <- now - INVENTORY_DAYS * 86400
inventory <- list()

# (3a) stage_artifacts 신규 엔트리 — depth-2 (mode/run_id) 디렉토리 + depth-1 파일 mtime 7일 내
run_step("inv_stage_artifacts", {
  sa <- file.path(root, "stage_artifacts")
  recent <- character(0)
  if (dir.exists(sa)) {
    modes <- list.dirs(sa, recursive = FALSE, full.names = TRUE)
    for (m in modes) {
      subs <- c(list.dirs(m, recursive = FALSE, full.names = TRUE),
                list.files(m, full.names = TRUE)[!file.info(list.files(m, full.names = TRUE))$isdir])
      subs <- unique(subs)
      if (!length(subs)) next
      mt <- suppressWarnings(file.info(subs)$mtime)
      hit <- subs[!is.na(mt) & mt >= cutoff]
      if (length(hit))
        recent <- c(recent, sub(paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", root), "/"),
                                "", gsub("\\\\", "/", hit)))
    }
    f1 <- list.files(sa, full.names = TRUE)
    f1 <- f1[!file.info(f1)$isdir]
    if (length(f1)) {
      mt <- suppressWarnings(file.info(f1)$mtime)
      hit <- f1[!is.na(mt) & mt >= cutoff]
      if (length(hit))
        recent <- c(recent, sub(paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", root), "/"),
                                "", gsub("\\\\", "/", hit)))
    }
  }
  recent <- unique(recent)
  inventory$stage_artifacts_new <- list(n = length(recent), entries = as.list(head(recent, 100)))
  invisible(TRUE)
})

# (3b) hypothesis_index 델타 — 전 주 스냅샷(.cache/cleaner_last_state.json) 대비 엔트리 증감
run_step("inv_hypothesis_index", {
  hi_path <- file.path(root, registry_zone, "hypothesis_index.json")
  state_path <- file.path(root, ".cache", "cleaner_last_state.json")
  n_now <- NA_integer_
  if (file.exists(hi_path)) {
    hi <- tryCatch(fromJSON(hi_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(hi)) {
      ent <- hi$entries %||% hi$hypotheses %||% NULL
      n_now <- if (!is.null(ent)) length(ent) else NA_integer_
    }
  }
  n_prev <- NA_integer_
  if (file.exists(state_path)) {
    st <- tryCatch(fromJSON(state_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(st)) n_prev <- as.integer(st$hypothesis_index_n %||% NA)
  }
  inventory$hypothesis_index <- list(
    n_entries = n_now, n_prev_week = n_prev,
    delta = if (!is.na(n_now) && !is.na(n_prev)) n_now - n_prev else NA)
  if (!DRY) try(write_json(list(updated_at = format(now, "%Y-%m-%d %H:%M:%S"),
                                hypothesis_index_n = n_now),
                           state_path, auto_unbox = TRUE, pretty = TRUE, na = "null"),
                silent = TRUE)
  invisible(TRUE)
})

# (3c) 신규 L-code — stage_artifacts/l_code/ 하위 *.json mtime 7일 내
run_step("inv_new_lcodes", {
  lc_dir <- file.path(root, "stage_artifacts", "l_code")
  ids <- character(0)
  if (dir.exists(lc_dir)) {
    fs <- list.files(lc_dir, pattern = "\\.json$", recursive = TRUE, full.names = TRUE)
    if (length(fs)) {
      mt <- suppressWarnings(file.info(fs)$mtime)
      hit <- fs[!is.na(mt) & mt >= cutoff]
      for (f in hit) {
        j <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
        ids <- c(ids, if (!is.null(j$l_code)) as.character(j$l_code) else basename(f))
      }
    }
  }
  inventory$new_lcodes <- list(n = length(ids), l_codes = as.list(head(unique(ids), 50)))
  invisible(TRUE)
})

# (3d) git log --since 요약 (7일)
run_step("inv_git_log", {
  gl <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(root), "log", "--since=7.days",
                     "--oneline", "--no-color", "--no-merges"),
            stdout = TRUE, stderr = TRUE),
    error = function(e) character(0)))
  # (2026-07-26 WCS-02 수리) git 실패를 character(0) 으로 흡수하면 n_commits=0 이
  #   "커밋 없는 주"와 **구분 불가**(계측 실패를 정상값 0 으로 위장). 상태를 이름으로 남긴다.
  st <- attr(gl, "status")
  git_ok <- is.null(st) || st == 0
  if (!git_ok) gl <- character(0)
  inventory$git_log_7d <- list(
    n_commits = if (git_ok) length(gl) else NA_integer_,
    collect_status = if (git_ok) "ok" else sprintf("FAILED (git status=%s) — 0 아님, 미관측", st),
    head = as.list(head(gl, 30)))
  invisible(TRUE)
})

# =============================================================================
# [3.5] 주간 axiom 사이클 — harvester → cluster_extractor → promote 진단 (2026-07-04)
#       Cleaner 통합이 정규 경로 (axiom_weekly.sh 본문 retain — 헤더 참조).
#       engine-core 스크립트 호출만 (fail-soft run_step 규약). DRY 시 promote 생략.
# =============================================================================
axiom_candidates_summary <- NULL
promote_failures <- list()   # promote 순회 PASS/FAIL 미매칭(침묵 crash 의심) 보존 — pending JSON 노출
promote_n_crash <- 0L
run_step("axiom_weekly_cycle", {
  ax_dir <- file.path(root, "02_Infrastructure", "axiom")
  # bare python 금지 — venv(qvest_ml) 우선, QVEST_PY 환경변수로 override
  py <- Sys.getenv("QVEST_PY", file.path(root, ".venv_qvest_ml", "Scripts", "python.exe"))
  if (!file.exists(py)) py <- "python"  # 최후 폴백 (환경 미프로비저닝 시 fail-soft로 기록됨)
  Sys.setenv(CLAUDE_PROJECT_DIR = root, PYTHONUTF8 = "1")
  if (DRY) {
    # dry-run = axiom state 무변경 (corpus/candidates/review_log 미기록) — 집계 스텝만 수행
    cat("  | [axiom] harvester/cluster/promote 생략 (dry-run — axiom state 무변경)\n")
  } else {
    for (scr in c("lcode_harvester.py", "cluster_extractor.py")) {
      sp <- file.path(ax_dir, scr)
      if (!file.exists(sp)) stop(sprintf("%s 부재", scr))
      out <- suppressWarnings(system2(py, shQuote(sp), stdout = TRUE, stderr = TRUE))
      st <- attr(out, "status")
      cat(sprintf("  | [axiom] %s → %s\n", scr, if (is.null(st) || st == 0) "OK" else sprintf("exit=%s", st)))
      if (!is.null(st) && st != 0) stop(sprintf("%s exit=%s: %s", scr, st, paste(tail(out, 3), collapse = " | ")))
    }
    # promote 진단: pending candidate 순회 (INV-4 5축 hurdle — 미달은 review_log/AX-PENDING 기록)
    cands <- list.files(file.path(root, "qepm", "memory", "axioms", "candidates"),
                        pattern = "^CAND_.*\\.json$", full.names = TRUE)
    promote_r <- file.path(ax_dir, "promote.R")
    for (cand in cands) {
      out <- suppressWarnings(system2("Rscript", c(shQuote(promote_r), shQuote(cand)),
                                      stdout = TRUE, stderr = TRUE))
      hit <- grep("\\[promote\\].*(PASS|FAIL)", out, value = TRUE)
      if (!length(hit)) {
        # PASS/FAIL 미매칭 = 침묵 crash 의심 — stderr tail을 로그 + pending JSON에 보존
        #   (진단면 독립 확보: 원인 수리 여부와 무관하게 침묵 소실 재발 방지)
        st_code <- attr(out, "status")
        tail_txt <- paste(tail(out[nzchar(out)], 6), collapse = " | ")
        promote_n_crash <- promote_n_crash + 1L
        promote_failures[[length(promote_failures) + 1L]] <- list(
          candidate = basename(cand),
          exit = if (is.null(st_code)) 0L else as.integer(st_code),
          output_tail = substr(tail_txt, 1, 800),
          at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      }
      cat(sprintf("  | [axiom] promote %s: %s\n", basename(cand),
                  if (length(hit)) hit[1]
                  else sprintf("출력 미확인 (fail-soft) — exit=%s tail: %s",
                               if (is.null(attr(out, "status"))) "0" else attr(out, "status"),
                               substr(paste(tail(out[nzchar(out)], 3), collapse = " | "), 1, 300))))
    }
  }
  invisible(TRUE)
})

# [3.6] 지식 순차 인덱스 재생성 (2026-07-05 도훈 — "1부터 차례대로·증류돼도 구멍 없이")
#   안정 ID 불변, 활성 집합(Law/Distilled/L-code)을 1..N 뷰로 갱신. blast radius 0.
#   axiom 사이클 직후 실행 → 증류/강등 반영된 최신 활성 집합으로 재생성.
run_step("knowledge_index", {
  # (2026-07-26 WCS-06 수리, 도훈 승인) DRY 에서 실행하면 06_Registry/knowledge_index.{json,md}
  #   를 **실제로 재작성**한다(build_knowledge_index 에 dry 인자가 없음). 산출물 라벨이
  #   dry_run:true 인데 부작용이 나가면 라벨이 안전성을 위장하는 것 — dry-run 을 믿고 돌린
  #   사람이 정본 인덱스를 갈아버린다. DRY 에선 스킵하고 그 사실을 상태에 남긴다.
  # ★run_step 의 expr 은 **지연평가 promise** — caller(최상위) 환경에서 평가되므로
  #   블록 안 return() 은 "no function to return from" 으로 죽고(실측 2026-07-26),
  #   step_status 직접 할당도 run_step 이 직후 "OK" 로 덮는다. 조건 분기로만 쓴다.
  if (DRY) {
    cat("[cleaner] knowledge_index: SKIP (DRY — 정본 06_Registry/knowledge_index.* 재작성 방지)\n")
  } else {
    options(ki_no_autorun = TRUE)
    source(file.path(root, "02_Infrastructure", "ops", "build_knowledge_index.R"))
    build_knowledge_index(root = root)
  }
  invisible(TRUE)
})

# axiom 후보 현황 집계 (n_pending / failing_axis_histogram / near_miss) — 다이제스트 입력.
#   failing 축 데이터 = promote.R review_log(AX-PENDING_*.json failing_hurdles) 실기록만 소비.
run_step("axiom_candidates_summary", {
  cand_dir <- file.path(root, "qepm", "memory", "axioms", "candidates")
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  rl_dir <- file.path(root, "qepm", "memory", "axioms", "review_log")
  cand_fs <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  # 이미 승격된 candidate 제외 (active axiom promotion$source_candidate 대조)
  promoted_ids <- character(0)
  for (af in list.files(active_dir, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)) {
    aj <- tryCatch(fromJSON(af, simplifyVector = FALSE), error = function(e) NULL)
    sc <- aj$promotion$source_candidate %||% NULL
    if (!is.null(sc)) promoted_ids <- c(promoted_ids, as.character(sc))
  }
  hist_tab <- list(); near_miss <- list(); n_pending <- 0L; confirm_flags <- list()
  for (cf in cand_fs) {
    cj <- tryCatch(fromJSON(cf, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(cj)) next
    cid <- cj$candidate_id %||% sub("\\.json$", "", basename(cf))
    if (cid %in% promoted_ids) next
    n_pending <- n_pending + 1L
    # 해당 candidate의 최신 AX-PENDING 리뷰(failing_hurdles) — promote 실기록만
    rls <- list.files(rl_dir, pattern = paste0("^AX-PENDING_", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", cid), "_"),
                      full.names = TRUE)
    if (!length(rls)) next
    rl_path <- rls[order(rls, decreasing = TRUE)][1]
    rl <- tryCatch(fromJSON(rl_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(rl)) next
    failing <- unlist(rl$failing_hurdles %||% list())
    for (ax in failing) hist_tab[[ax]] <- (hist_tab[[ax]] %||% 0L) + 1L
    if (length(failing) == 1L)
      near_miss[[length(near_miss) + 1L]] <- list(
        candidate_id = cid, failing_axis = failing[1],
        weighted_score = rl$weighted_score %||% NA,
        statement_draft = substr(as.character(cj$statement_draft %||% ""), 1, 160))
    # confirm_flags: within_condition_axis(direction_consistency 2026-07-04 재정의) 적용 후보 —
    #   주간 confirm 의무(axiom-engine §5)의 도훈 표면 도달 경로 (review_log 실기록만 소비)
    dc_def <- as.character(rl$axes$independence$direction_consistency_definition %||% "")
    if (grepl("within_condition_axis", dc_def, fixed = TRUE))
      confirm_flags[[length(confirm_flags) + 1L]] <- list(
        candidate_id = cid,
        item = "conditional direction_consistency 재정의(within_condition_axis) 적용 — 주간 도훈 confirm 대상",
        detail = dc_def,
        review_log = basename(rl_path))
  }
  # Distilled 계층 잔량: pending_5axis(정제 대기) 최고령 + quarantined_evidence — 적체 가시화
  dist_dir <- file.path(root, "qepm", "memory", "axioms", "distilled")
  n_p5 <- 0L; p5_oldest_days <- NA_real_; p5_oldest_id <- NA_character_; n_quar <- 0L
  for (df_ in list.files(dist_dir, pattern = "^DIST-.*\\.json$", full.names = TRUE)) {
    dj <- tryCatch(fromJSON(df_, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(dj)) next
    dst <- dj$status %||% ""
    if (identical(dst, "pending_5axis")) {
      n_p5 <- n_p5 + 1L
      ca <- suppressWarnings(tryCatch(as.Date(substr(as.character(dj$created_at %||% ""), 1, 10)),
                                      error = function(e) NA))
      if (!is.na(ca)) {
        age <- as.numeric(Sys.Date() - ca)
        if (is.na(p5_oldest_days) || age > p5_oldest_days) {
          p5_oldest_days <- age
          p5_oldest_id <- dj$dist_id %||% basename(df_)
        }
      }
    } else if (identical(dst, "quarantined_evidence")) n_quar <- n_quar + 1L
  }
  # L-code corpus ID 무결성 (2026-07-25) — harvester가 충돌을 stderr WARN으로만 흘려
  #   매주 로그에 찍히고도 아무도 안 보는 구조였음(07-25 적발 시 5건 누적: L-160/166/601/602/789).
  #   충돌 시 harvester는 양쪽 레코드를 다 적재하므로 내용 손실은 없으나 ID 조회가 모호해짐.
  #   corpus 산출물의 n_id_collisions를 다이제스트에 실어 도훈 표면 도달을 보장.
  lc_corpus <- tryCatch(fromJSON(file.path(root, ".cache", "lcode_corpus.json"),
                                 simplifyVector = FALSE), error = function(e) NULL)
  lcode_integrity <- if (is.null(lc_corpus)) {
    list(status = "corpus_unreadable", n_entries = NA, n_unique_ids = NA, n_id_collisions = NA,
         duplicate_ids = list())
  } else {
    .rows <- lc_corpus$lcodes %||% list()
    .ids <- vapply(.rows, function(x) as.character(x$l_code %||% x$id %||% "")[1], character(1))
    .dup <- names(which(table(.ids) > 1))
    # 충돌 유형 자동 분류 (2026-07-25) — ID를 자동으로 바꾸지 않는다(위험). 조치 종류만 판정해
    #   도훈이 매번 같은 분류 노동을 반복하지 않게 한다. 판별은 결정적:
    #     서로 다른 strategy_id  → cross_strategy   : 최초 1건만 번호 유지, 나머지 신규 ID 발급
    #     같은 전략·같은 디렉토리 → same_dir_duplicate: 같은 교훈 이중 기록 — 정본 파일 선택
    #     같은 전략·다른 디렉토리 → cross_zone_variant: 루트 사본 vs 전략트리 사본 — 내용 병합
    .classify <- function(id) {
      idx <- which(.ids == id)
      strat <- unique(vapply(idx, function(i) as.character(.rows[[i]]$strategy_id %||% "")[1], character(1)))
      strat <- strat[nzchar(strat)]
      srcs <- vapply(idx, function(i) as.character(.rows[[i]]$source_file %||% .rows[[i]]$file %||% "")[1],
                     character(1))
      dirs <- unique(dirname(gsub("\\\\", "/", srcs)))
      kind <- if (length(strat) > 1) "cross_strategy"
              else if (length(dirs) == 1) "same_dir_duplicate"
              else "cross_zone_variant"
      list(id = id, kind = kind, n_records = length(idx),
           strategies = as.list(strat), source_dirs = as.list(dirs),
           action = switch(kind,
             cross_strategy     = "최초 1건만 번호 유지 · 나머지 미발급 번호로 신규 발급 (리넘버 아님)",
             same_dir_duplicate = "같은 교훈 이중 기록 — 정본 파일 1개 선택",
             cross_zone_variant = "루트 사본 vs 전략트리 사본 — 내용 병합 후 1건화"))
    }
    .cls <- lapply(.dup, .classify)
    list(status = if (length(.dup)) "COLLISIONS_PRESENT" else "clean",
         n_entries = length(.ids), n_unique_ids = length(unique(.ids)),
         n_id_collisions = as.integer(lc_corpus$n_id_collisions %||% length(.dup)),
         duplicate_ids = as.list(.dup),
         collisions = .cls,
         kind_counts = as.list(table(vapply(.cls, function(z) z$kind, character(1)))),
         review_doc = "06_Registry/lcode_id_collision_review_20260725.md",
         corpus_last_updated = as.character(lc_corpus$last_updated %||% NA))
  }
  # ★두 숫자는 다른 것을 센다 (2026-07-25 확인): n_id_collisions = harvester의 *충돌 이벤트*
  #   수(= 여분 레코드 수, 3-way면 2 증가) / duplicate_ids = 중복된 *ID 개수*.
  #   실측 예: ID 5개(L-601 3-way 포함) → 여분 레코드 6 = 416-410. 혼동 방지를 위해 병기.
  if (!is.null(lcode_integrity$duplicate_ids) && length(lcode_integrity$duplicate_ids))
    cat(sprintf("[cleaner][WARN] L-code ID 중복: ID %d개 / 여분 레코드 %d건 — %s (corpus %d항목, 고유 ID %d)\n",
                length(lcode_integrity$duplicate_ids),
                lcode_integrity$n_entries - lcode_integrity$n_unique_ids,
                paste(unlist(lcode_integrity$duplicate_ids), collapse = ", "),
                lcode_integrity$n_entries, lcode_integrity$n_unique_ids))

  axiom_candidates_summary <- list(
    n_candidates_total = length(cand_fs),
    n_pending = n_pending,
    n_promote_crash = promote_n_crash,
    promote_failures = promote_failures,
    lcode_integrity = lcode_integrity,
    failing_axis_histogram = hist_tab,
    near_miss = near_miss,
    confirm_flags = confirm_flags,
    pending_5axis = list(n = n_p5, oldest_age_days = p5_oldest_days, oldest_dist_id = p5_oldest_id),
    n_quarantined_evidence = n_quar,
    source = "promote.R review_log(AX-PENDING failing_hurdles) 실기록 집계 — 리뷰 없는 candidate는 histogram 미포함(정직)",
    note = if (DRY) "dry-run — promote 미실행, 기존 review_log 스냅샷 집계" else "step 3.5 promote 진단 직후 집계")
  cat(sprintf("[cleaner] axiom 후보 현황: total=%d pending=%d promote_crash=%d near_miss=%d confirm_flags=%d p5axis=%d(최고령 %s일) quarantined=%d (failing axes: %s)\n",
              length(cand_fs), n_pending, promote_n_crash, length(near_miss), length(confirm_flags),
              n_p5, as.character(p5_oldest_days), n_quar,
              if (length(hist_tab)) paste(sprintf("%s=%d", names(hist_tab), unlist(hist_tab)), collapse = " ") else "리뷰기록 없음"))
  invisible(TRUE)
})

# =============================================================================
# [3.7] Continuity Firewall 자가발전 — 차단 이력 + pending 신어 후보 (2026-07-15 도훈 mandate)
#   게이트가 잡은 신어(backstop 사전 밖·verdict_close로만 잡힌) 후보를 /cleaner가 정제 후 승격.
#   ★firewall의 'append_firewall_case caller 0건 → 코퍼스 성장 정지'(연구 T3) 실패를 반복하지
#   않는 실배선 caller. 이 스텝이 pending을 다이제스트에 실어 /cleaner 세션 도달을 보장한다.
# =============================================================================
continuity_review_summary <- NULL
run_step("continuity_review", {
  py <- Sys.getenv("QVEST_PY", file.path(root, ".venv_qvest_ml", "Scripts", "python.exe"))
  if (!file.exists(py)) py <- "python"
  gate <- file.path(root, "02_Infrastructure", "axiom", "continuity_gate.py")
  if (!file.exists(gate)) stop("continuity_gate.py 부재")
  Sys.setenv(CLAUDE_PROJECT_DIR = root, PYTHONUTF8 = "1")
  out <- suppressWarnings(system2(py, c(shQuote(gate), "--review"), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0) stop(sprintf("continuity --review exit=%s: %s", st, paste(tail(out, 2), collapse = " | ")))
  continuity_review_summary <<- tryCatch(fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE),
                                         error = function(e) list(raw = out))
  cat(sprintf("[cleaner] continuity firewall: blocks_logged=%s cases=%s pending_novel=%s\n",
              as.character(continuity_review_summary$n_blocks_logged %||% "?"),
              as.character(continuity_review_summary$n_cases %||% "?"),
              as.character(continuity_review_summary$n_pending_novel %||% 0)))
  invisible(TRUE)
})

# =============================================================================
# [4] cleaner_pending.json 기록 — /cleaner 증류 세션이 소비, bootstrap이 마커 감지
# =============================================================================
sweep_deleted_n <- length(weekly_deleted$cache_scratch) + length(weekly_deleted$temp_logs) +
  # (2026-07-26 WCS-04) NA(=hygiene 감사 산출 미판독)를 0 으로 흡수하면 "삭제 0건" 과
  #   구분 불가. 합계에는 0 을 쓰되 미관측 사실은 아래 pending 에 별도 필드로 남긴다.
  (if (is.na(hygiene_deleted_n)) 0L else hygiene_deleted_n)
# (2026-07-26 WCS-01 수리) DRY 에서도 canonical cleaner_pending.json 을 덮어써
#   /cleaner 소비 상태·mtime 을 건드렸고, sweep_deleted_n 이 '실삭제'인지 '삭제 예정'인지
#   구분되지 않았다. DRY 는 별 파일로 분기하고 집계 키를 이름으로 나눈다.
pending_path <- if (DRY) file.path(root, ".cache", "cleaner_pending_dryrun.json")
                else     file.path(root, ".cache", "cleaner_pending.json")
run_step("write_pending", {
  pending <- list(
    schema        = "cleaner_pending_v2",   # v2 (2026-07-18): distill 선점 필드 3종 추가 (W29 2-pass 방지)
    # (2026-07-26 WCS-07 수리) as.Date(POSIXct) 는 UTC 로 변환 — KST 새벽/심야 실행 시
    #   주(week)·날짜 라벨이 하루/한 주 어긋난다. POSIXct 를 로컬 tz 로 직접 포맷.
    week_of       = format(now, "%G-W%V"),
    generated_at  = format(now, "%Y-%m-%d %H:%M:%S"),
    generator     = "02_Infrastructure/ops/weekly_cleaner_sweep.R",
    rule_sot      = "02_Infrastructure/docs/rules/artifact-storage.md §8",
    dry_run       = DRY,
    # (2026-07-26 WCS-06) 단일 boolean 은 "무엇이 안 건드려졌나"를 말해주지 못했다 —
    #   스텝마다 dry 범위가 달라(삭제·axiom state 는 스킵, knowledge_index·pending·telegram 은
    #   실행) 산출물만 보고 부작용 집합을 알 수 없었다. 라벨이 실제와 1:1 대응하게 기록한다.
    dry_run_scope = if (DRY) list(
      deletions       = "skipped",
      axiom_promote   = "skipped",
      cleaner_state   = "skipped",
      knowledge_index = "skipped",
      telegram        = "skipped",
      pending_file    = "WRITTEN (이 파일 자체 — DRY 에서도 갱신됨)"
    ) else list(
      deletions       = "executed",
      axiom_promote   = "executed",
      cleaner_state   = "written",
      knowledge_index = "written",
      telegram        = "sent",
      pending_file    = "WRITTEN"
    ),
    # ── 증류 선점(claim) 필드 (cleaner_claim.R 소비 — 2-pass 중복실행 방지, W29 next_probe #4) ──
    #   초기값 pending. /cleaner 세션이 cleaner_claim_distill()로 in_progress 점유 → done 해제.
    #   status(awaiting_distill→distilled)는 bootstrap 마커용 불변; distill_status는 그 사이
    #   in_progress 중간상태를 표현해 두 소비자의 동시 착수를 차단한다.
    distill_status     = "pending",
    distill_owner      = NULL,
    distill_claimed_at = NULL,
    # WCS-01: DRY 는 삭제하지 않았으므로 실삭제 수를 null 로 두고 '예정' 을 별 키로 분리
    sweep_deleted_n   = if (DRY) NA_integer_ else sweep_deleted_n,
    would_delete_n    = if (DRY) sweep_deleted_n else NA_integer_,
    sweep_detail  = list(
      hygiene_audit_deleted_n     = hygiene_deleted_n,
      # (WCS-09) 일간 감사 경고를 /cleaner 증류가 소비할 수 있게 운반
      hygiene_n_warnings          = hygiene_warn_n,
      hygiene_warnings_top        = hygiene_warn_top,
      # (2026-07-26 WCS-04) 합계에 0 으로 들어간 것이 '삭제 0' 인지 '미관측' 인지 구분
      hygiene_audit_status        = if (is.na(hygiene_deleted_n))
        "UNMEASURED (hygiene 감사 산출 미판독 — 합계에는 0으로 계상됨)" else "measured",
      weekly_cache_scratch_7d     = as.list(weekly_deleted$cache_scratch),
      weekly_temp_logs_30d        = as.list(weekly_deleted$temp_logs),
      manifest                    = ".cache/hygiene_manifest.log"
    ),
    inventory     = inventory,
    axiom_candidates = axiom_candidates_summary,   # [3.5] 주간 axiom 사이클 후보 현황 (n_pending/failing_axis_histogram/near_miss)
    continuity_firewall = continuity_review_summary,  # [3.7] 포기 원천차단 게이트 — 차단 이력 + pending 신어 후보(승격 대상)
    step_status   = step_status,
    status        = "awaiting_distill",
    next_action   = "/cleaner 스킬 (다음 세션) — 주간 엑기스 증류 + L-code 적립 + axiom 후보 현황 검토(near-miss 정제) + continuity 신어 후보 승격(--append-case) + 잔재 무아카이브 삭제"
  )
  write_json(pending, pending_path, auto_unbox = TRUE, pretty = TRUE,
             null = "null", na = "null")
  cat(sprintf("[cleaner] pending → %s (%s=%d, status=awaiting_distill)\n",
              pending_path,
              if (DRY) "would_delete_n" else "sweep_deleted_n", sweep_deleted_n))
  invisible(TRUE)
})

# =============================================================================
# [5] 텔레그램 알림 — tg_agent_brief 규약 재사용 (fail-soft)
# =============================================================================
# (2026-07-26 WCS-06) DRY 에서도 force=TRUE 로 **실발송**되던 경로 — dry-run 은 관측이지
#   통보가 아니다. QVEST_CLEANER_NO_TG 와 별개로 DRY 자체가 억제 사유가 된다.
if (Sys.getenv("QVEST_CLEANER_NO_TG", "0") != "1" && !DRY) {
  run_step("telegram", {
    owd <- getwd(); setwd(root); on.exit(setwd(owd), add = TRUE)
    tg_ok <- tryCatch({
      suppressWarnings(source("02_Infrastructure/telegram/telegram_notify.R"))
      exists("tg_agent_brief")
    }, error = function(e) FALSE)
    if (!tg_ok) stop("telegram_notify.R 로드 실패")
    n_sa <- inventory$stage_artifacts_new$n %||% 0
    n_lc <- inventory$new_lcodes$n %||% 0
    n_gc <- inventory$git_log_7d$n_commits %||% 0
    secs <- list(
      list(type = "summary", heading = "주간 Cleaner 기계 스윕",
           body = sprintf("정크 %d건 자동 정리 + 주간 리서치 인벤토리 수집 완료. 증류(엑기스 추출·L-code 적립·잔재 삭제)는 다음 세션 /cleaner 대기.",
                          sweep_deleted_n)),
      list(type = "bullet", heading = "이번 주 인벤토리", items = c(
        sprintf("실험 신규 엔트리 %d건 (stage_artifacts 7일)", n_sa),
        sprintf("신규 교훈 L-code %d건", n_lc),
        sprintf("axiom 후보 대기 %s건 (near-miss %s건 — /cleaner에서 정제)",
                as.character(axiom_candidates_summary$n_pending %||% "?"),
                as.character(length(axiom_candidates_summary$near_miss %||% list()))),
        sprintf("커밋 %d건 (git log 7일)", n_gc),
        sprintf("삭제 기록: .cache/hygiene_manifest.log (%s)",
                if (DRY) "dry-run — 실삭제 없음" else "실삭제")
      ))
    )
    # L-code ID 무결성 — 충돌 있을 때만 섹션 추가 (2026-07-25. 종전 harvester stderr WARN만이라
    #   매주 로그에 찍히고도 표면 도달 0이었음)
    .li <- axiom_candidates_summary$lcode_integrity %||% NULL
    if (!is.null(.li) && length(.li$duplicate_ids %||% list()) > 0) {
      secs[[length(secs) + 1L]] <- list(
        type = "bullet", heading = "L-code ID 무결성 경고", items = c(
          sprintf("중복 ID %d개 (여분 레코드 %s건): %s", length(.li$duplicate_ids),
                  as.character(.li$n_entries - .li$n_unique_ids),
                  paste(unlist(.li$duplicate_ids), collapse = ", ")),
          sprintf("corpus %s항목 / 고유 ID %s (내용 손실은 없음 — 양쪽 다 적재됨)",
                  as.character(.li$n_entries), as.character(.li$n_unique_ids)),
          sprintf("유형: %s", if (length(.li$kind_counts %||% list()))
                    paste(sprintf("%s %s건", names(.li$kind_counts), unlist(.li$kind_counts)),
                          collapse = " / ") else "미분류"),
          sprintf("판정표: %s", .li$review_doc %||% "06_Registry/")
        ))
    }
    # agent는 telegram_notify.R 화이트리스트 내 값만 허용 — 전용 "Cleaner" 미등재라 Q-Lead 사용
    tg_agent_brief(agent = "Q-Lead", title = "주간 클리너 — 기계 스윕 완료·증류 대기",
                   relaxed = TRUE, force = TRUE,
                   # (WCS-07) as.Date(POSIXct)=UTC 변환 → 로컬 tz 직접 포맷
                   lock_scope = sprintf("weekly_cleaner_%s", format(now, "%Y%m%d")),
                   sections = secs)
    invisible(TRUE)
  })
} else step_status$telegram <- if (DRY) "SKIP (DRY — 실발송 억제)" else "SKIP (QVEST_CLEANER_NO_TG=1)"

# (2026-07-26 WCS-08 수리) pending 의 step_status 는 write_pending 스텝 *내부*에서
#   직렬화되므로 그 뒤 스텝(telegram·최종 정리)의 성패를 **담을 수 없는 슬롯**이었다.
#   전 스텝이 끝난 지금 시점 상태를 별 파일로 기록해 소비자가 최종본을 읽게 한다.
try({
  write_json(list(
    week_of = format(now, "%G-W%V"),
    finished_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    dry_run = DRY,
    step_status = step_status,
    n_fail_steps = length(names(step_status)[grepl("^FAIL", unlist(step_status))])),
    file.path(root, ".cache", "cleaner_sweep_status.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}, silent = TRUE)

fails <- names(step_status)[grepl("^FAIL", unlist(step_status))]
cat(sprintf("[cleaner] done — steps: %s%s\n",
            paste(sprintf("%s=%s", names(step_status),
                          sub(":.*$", "", unlist(step_status))), collapse = " "),
            if (length(fails)) sprintf(" (FAIL %d단계 — fail-soft 계속됨)", length(fails)) else ""))

# 스윕 lock 해제 (정상 종료 경로 — 오류 종료는 상단 finalizer가 처리)
try(unlink(sweep_lock_path), silent = TRUE)
