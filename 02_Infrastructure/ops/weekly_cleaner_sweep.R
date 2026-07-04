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
#   [4] .cache/cleaner_pending.json 기록
#       {week_of, sweep_deleted_n, inventory, status:"awaiting_distill"}
#       → bootstrap.sh가 마커 감지해 "/cleaner 실행" WARN 노출 (증류는 세션에서)
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
    if (!is.null(rep)) hygiene_deleted_n <- as.integer(rep$cleanup$n_deleted %||% NA)
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
  st <- attr(gl, "status")
  if (!is.null(st) && st != 0) gl <- character(0)
  inventory$git_log_7d <- list(n_commits = length(gl), head = as.list(head(gl, 30)))
  invisible(TRUE)
})

# =============================================================================
# [4] cleaner_pending.json 기록 — /cleaner 증류 세션이 소비, bootstrap이 마커 감지
# =============================================================================
sweep_deleted_n <- length(weekly_deleted$cache_scratch) + length(weekly_deleted$temp_logs) +
  (if (is.na(hygiene_deleted_n)) 0L else hygiene_deleted_n)
pending_path <- file.path(root, ".cache", "cleaner_pending.json")
run_step("write_pending", {
  pending <- list(
    schema        = "cleaner_pending_v1",
    week_of       = format(as.Date(now), "%G-W%V"),
    generated_at  = format(now, "%Y-%m-%d %H:%M:%S"),
    generator     = "02_Infrastructure/ops/weekly_cleaner_sweep.R",
    rule_sot      = "02_Infrastructure/docs/rules/artifact-storage.md §8",
    dry_run       = DRY,
    sweep_deleted_n = sweep_deleted_n,
    sweep_detail  = list(
      hygiene_audit_deleted_n     = hygiene_deleted_n,
      weekly_cache_scratch_7d     = as.list(weekly_deleted$cache_scratch),
      weekly_temp_logs_30d        = as.list(weekly_deleted$temp_logs),
      manifest                    = ".cache/hygiene_manifest.log"
    ),
    inventory     = inventory,
    step_status   = step_status,
    status        = "awaiting_distill",
    next_action   = "/cleaner 스킬 (다음 세션) — 주간 엑기스 증류 + L-code 적립 + 잔재 무아카이브 삭제"
  )
  write_json(pending, pending_path, auto_unbox = TRUE, pretty = TRUE,
             null = "null", na = "null")
  cat(sprintf("[cleaner] pending → %s (sweep_deleted_n=%d, status=awaiting_distill)\n",
              pending_path, sweep_deleted_n))
  invisible(TRUE)
})

# =============================================================================
# [5] 텔레그램 알림 — tg_agent_brief 규약 재사용 (fail-soft)
# =============================================================================
if (Sys.getenv("QVEST_CLEANER_NO_TG", "0") != "1") {
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
        sprintf("커밋 %d건 (git log 7일)", n_gc),
        sprintf("삭제 기록: .cache/hygiene_manifest.log (%s)",
                if (DRY) "dry-run — 실삭제 없음" else "실삭제")
      ))
    )
    # agent는 telegram_notify.R 화이트리스트 내 값만 허용 — 전용 "Cleaner" 미등재라 Q-Lead 사용
    tg_agent_brief(agent = "Q-Lead", title = "주간 클리너 — 기계 스윕 완료·증류 대기",
                   relaxed = TRUE, force = TRUE,
                   lock_scope = sprintf("weekly_cleaner_%s", format(as.Date(now), "%Y%m%d")),
                   sections = secs)
    invisible(TRUE)
  })
} else step_status$telegram <- "SKIP (QVEST_CLEANER_NO_TG=1)"

fails <- names(step_status)[grepl("^FAIL", unlist(step_status))]
cat(sprintf("[cleaner] done — steps: %s%s\n",
            paste(sprintf("%s=%s", names(step_status),
                          sub(":.*$", "", unlist(step_status))), collapse = " "),
            if (length(fails)) sprintf(" (FAIL %d단계 — fail-soft 계속됨)", length(fails)) else ""))
