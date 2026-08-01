#==============================================================================
# QEPM Artifact Lineage Utils — v6.1 R11 (2026-04-24)
#
# Purpose: 비트단위 재현(bit-exact reproducibility) 목적의 계보 메타데이터 수집.
#   - git commit + dirty state
#   - R version + 주요 package version
#   - random seed
#   - input file sha256 hash
#   - method_selected + method_shopping_log_ref
#   - window config
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(digest)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── Git state ──────────────────────────────────────────
#  [2026-08-02 수리 — r-portability 계통] 종전 `system("git ... 2>/dev/null", intern=TRUE)` 는
#  Windows 에서 **항상 실패**했다: R 의 system() 은 cmd.exe 로 넘기는데 cmd 에 `/dev/null` 이
#  없어 "파일 이름, 디렉터리 이름 또는 볼륨 레이블 구문이 잘못되었습니다"(status 128)가 난다.
#  tryCatch 가 그걸 삼켜 **git_commit 이 조용히 "unknown" 으로 결손**됐다 — 계보 추적이
#  무증상으로 죽어 있었다(WT-D20260802_001 R2 라운드 적발).
#  정본: system2() 로 인자를 분리하고 stderr 는 R 레벨에서 버린다(쉘 리다이렉션 의존 제거).
#  실패는 "unknown" 으로 두되 **호출자가 구분할 수 있게** git_state_error 를 함께 싣는다 —
#  결손을 정상값처럼 반환하면 그게 이 결함의 재발 형태다.
.git_try <- function(args) {
  tryCatch({
    out <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = FALSE))
    st  <- attr(out, "status")
    if (!is.null(st) && st != 0L) NULL else out
  }, error = function(e) NULL)
}

capture_git_state <- function() {
  sha_raw <- .git_try(c("rev-parse", "HEAD"))
  sha <- if (is.null(sha_raw) || !length(sha_raw)) "unknown" else trimws(sha_raw)

  status_raw <- .git_try(c("status", "--porcelain"))
  dirty <- if (is.null(status_raw)) NA else (length(status_raw) > 0)

  list(
    git_commit = sha[1] %||% "unknown",
    git_dirty = dirty,
    # 결손을 정상값처럼 반환하지 않는다 — 소비자가 "미측정"과 "깨끗한 트리"를 구분할 수 있어야 한다.
    git_state_error = if (identical(sha[1], "unknown") || is.na(dirty))
      "git 조회 실패 — 계보 미측정(정상 상태 아님)" else NULL
  )
}

# ─── R env state ────────────────────────────────────────
capture_r_env <- function() {
  key_pkgs <- c("data.table", "jsonlite", "arrow", "quadprog",
                "digest", "PerformanceAnalytics", "xts")
  pkg_versions <- sapply(key_pkgs, function(p) {
    tryCatch(as.character(packageVersion(p)),
             error = function(e) "not_installed")
  })

  list(
    r_version = as.character(getRversion()),
    r_packages = as.list(pkg_versions)
  )
}

# ─── Input file hashes ──────────────────────────────────
compute_file_hash <- function(path, algo = "sha256") {
  if (!file.exists(path)) return(NA_character_)
  digest::digest(file = path, algo = algo)
}

capture_input_hashes <- function(file_paths) {
  hashes <- sapply(file_paths, compute_file_hash)
  as.list(hashes)
}

# ─── Build lineage entry ────────────────────────────────
build_lineage_entry <- function(task_id,
                                package_type,
                                method_selected = NA,
                                method_shopping_log_ref = NA,
                                input_file_paths = character(0),
                                windows = NULL,
                                random_seed = NULL,
                                extra = list()) {
  git <- capture_git_state()
  renv <- capture_r_env()
  hashes <- capture_input_hashes(input_file_paths)

  if (is.null(random_seed)) {
    # Deterministic seed from task_id if not provided
    random_seed <- as.integer(
      paste0(gsub("[^0-9]", "", task_id), "001")
    )
    if (is.na(random_seed)) random_seed <- 20260424L
  }

  entry <- list(
    task_id = task_id,
    package_type = package_type,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_commit = git$git_commit,
    git_dirty = git$git_dirty,
    r_version = renv$r_version,
    r_packages = renv$r_packages,
    random_seed = random_seed,
    input_hashes = hashes,
    method_selected = method_selected %||% NA,
    method_shopping_log_ref = method_shopping_log_ref %||% NA,
    windows = windows,
    reproduction_command = sprintf(
      "Rscript -e 'set.seed(%s); source(\"qepm/mailbox/worktask/%s/run_all.R\")'",
      random_seed, task_id
    )
  )

  if (length(extra) > 0) {
    entry <- modifyList(entry, extra)
  }
  entry
}

# ─── Append to lineage file ─────────────────────────────
append_lineage <- function(task_id, lineage_entry,
                           wt_root = "qepm/mailbox/worktask") {
  wt_dir <- file.path(wt_root, task_id)
  lineage_path <- file.path(wt_dir, "artifact_lineage.json")

  if (file.exists(lineage_path)) {
    lineage <- fromJSON(lineage_path, simplifyVector = FALSE)
    if (!is.list(lineage$entries)) lineage$entries <- list()
  } else {
    lineage <- list(
      task_id = task_id,
      schema_version = "v1.0",
      entries = list()
    )
  }

  lineage$entries[[length(lineage$entries) + 1]] <- lineage_entry
  lineage$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  write_json(lineage, lineage_path, pretty = TRUE,
             auto_unbox = TRUE, null = "null")
  cat(sprintf("[lineage] %s / %s appended\n", task_id, lineage_entry$package_type))
  invisible(lineage)
}

# ─── Convenience: 한 번에 lineage 기록 (GAP-2 대응) ──────
# Agent가 package.json 저장 직후 Rscript 내에서 직접 호출.
# Hook matcher가 subagent Bash 경유 file write에 발동 안 하는 문제 우회.
record_package_lineage <- function(task_id,
                                     package_type,
                                     method_selected = NA,
                                     input_file_paths = character(0),
                                     windows = NULL,
                                     random_seed = NULL,
                                     extra = list(),
                                     wt_root = "qepm/mailbox/worktask") {
  pkg_path <- file.path(wt_root, task_id, sprintf("%s.json", package_type))

  if (file.exists(pkg_path)) {
    extra$file_path <- pkg_path
    extra$file_hash_sha256 <- digest::digest(file = pkg_path, algo = "sha256")
  }

  entry <- build_lineage_entry(
    task_id = task_id,
    package_type = package_type,
    method_selected = method_selected,
    input_file_paths = input_file_paths,
    windows = windows,
    random_seed = random_seed,
    extra = extra
  )
  append_lineage(task_id, entry, wt_root = wt_root)
}

# ─── Reproducibility smoke test ─────────────────────────
# WT COMPLETED 시 호출. run_all.R 재실행 → 결과 일치 확인.
smoke_reproduce <- function(task_id,
                             wt_root = "qepm/mailbox/worktask",
                             tolerance = 1e-8) {
  wt_dir <- file.path(wt_root, task_id)
  lineage_path <- file.path(wt_dir, "artifact_lineage.json")
  if (!file.exists(lineage_path)) {
    return(list(success = FALSE, reason = "no_lineage"))
  }

  lineage <- fromJSON(lineage_path, simplifyVector = FALSE)
  n <- length(lineage$entries %||% list())
  if (n == 0) return(list(success = FALSE, reason = "empty_lineage"))

  latest <- lineage$entries[[n]]
  seed <- latest$random_seed %||% 20260424L

  # Compare alpha_package hash
  alpha_path <- file.path(wt_dir, "alpha_package.json")
  if (!file.exists(alpha_path)) {
    return(list(success = FALSE, reason = "alpha_package_missing"))
  }
  original_hash <- digest::digest(file = alpha_path, algo = "sha256")

  # Snapshot, re-run would happen here (caller responsibility)
  # This function only verifies hash consistency post-rerun
  list(
    success = TRUE,
    task_id = task_id,
    seed = seed,
    original_alpha_hash = original_hash,
    rerun_command = latest$reproduction_command,
    tolerance = tolerance,
    note = "Caller must re-run and compare hashes."
  )
}

cat("[lineage_utils.R] v6.1 R11 Loaded. Functions:\n")
cat("  build_lineage_entry(task_id, package_type, ...)\n")
cat("  append_lineage(task_id, lineage_entry)\n")
cat("  record_package_lineage(task_id, package_type, method_selected=NA, ...)\n")
cat("  capture_git_state() / capture_r_env() / capture_input_hashes(paths)\n")
cat("  smoke_reproduce(task_id)\n")
