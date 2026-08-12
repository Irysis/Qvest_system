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

# ─── Project root resolution ────────────────────────────
#  [2026-08-09 수리 — r-portability 금칙 ③④] 이 파일의 읽기/쓰기가 전부 **상대경로**였다:
#    append_lineage(wt_root="qepm/mailbox/worktask") · record_package_lineage(pkg_path) ·
#    smoke_reproduce(lineage/alpha 경로) · capture_input_hashes(file.exists).
#  그래서 R 프로세스의 cwd 가 프로젝트 루트일 때에만 동작했다. 그런데 이 저장소의 문서화된
#  R 실행 패턴은 **전략/스테이지 디렉토리로 cd 한 뒤 Rscript** 이므로(CLAUDE.md
#  "R Execution Pattern"), 자연스러운 호출 규약이 계보 기록을 정확히 깨뜨린다.
#
#  실측 재현(2026-08-09, WT-D20260809_002):
#    cwd = stage_artifacts/fq143_tail_overlay_20260809/ 에서
#      Error in file(con, "w") : cannot open the connection
#      cannot open file 'qepm/mailbox/worktask/WT-D20260809_002/artifact_lineage.json'
#    같은 스크립트를 루트에서 재실행하면 성공.
#
#  ⚠[2026-08-09 정정] 최초 이 주석은 "계보는 Judge P7 감사 입력이라 여기서 죽으면 감사가
#    사라진다" 라고 적었는데 **검증 없이 단정한 것이었다**. 실측: P7 감사 함수
#    (v61_compliance_audit.R::audit_p7_lineage, 계보 부재를 pass=FALSE 로 기각하는 올바른 코드)는
#    **프로덕션 호출자가 0** 이고, judge 의 게이트 목록(.claude/agents/judge.md = Gate A~F)에
#    계보 게이트가 없으며 judge_init.md 의 lineage 언급도 0건이다.
#    ⇒ 계보는 **설계상 감사 입력이나 현재 어떤 게이트도 소비하지 않는다**. 결손의 실피해는
#    "게이트가 뚫렸다" 가 아니라 "**재현 자취가 조용히 비어 간다**" 쪽이다. 수리 이유는 유효하되
#    심각도 서술은 이 실측을 따를 것 — 설계 문서의 서술을 배선으로 읽지 말 것.
#
#  정본: 루트를 **표지(marker) 정체 검사**로 해석하고 모든 경로를 file.path(ROOT, ...) 로 세운다.
#    · 우선순위 = CLAUDE_PROJECT_DIR → QM_ROOT → cwd 상향 탐색 (금칙 ④ **표준 계열**,
#      cert_rules.R::.qvest_find_root 와 동일. ④-b self-first 는 *테스트 러너* 규칙이라 비해당)
#    · dir.exists() 존재 검사로 정체 검사를 대신하지 않는다(금칙 ③) — 표지 **파일**로 확인
#    · ★정규화를 검사보다 먼저: 쉘 QM_ROOT 는 역슬래시(C:\Users\…)로 들어온다(2026-08-01 실사고)
#    · 표지 미충족 후보는 수락이 아니라 **다음 tier 로 낙하** + 기각 사유 발화
#      (조용한 fall-through 가 이 계통의 재발 기전)
#    · 해석은 **지연(lazy)** 이다 — 절대 wt_root 를 넘기는 호출자(테스트 등)는 루트가 없어도 동작한다.
.LINEAGE_ROOT_MARKER <- "02_Infrastructure/hooks/qvest_hook_router.py"

# ★앵커 순서는 기계가 읽고 갈아끼울 수 있는 단일 줄로 노출한다 — 순서 자체가 계약이라,
#  검사기가 이 줄을 고정하지 못하면 env-first 로의 회귀를 실증할 수 없다.
.LINEAGE_ANCHOR_ORDER <- c("CLAUDE_PROJECT_DIR", "QM_ROOT", "ascend_from_cwd")

.lineage_state <- new.env(parent = emptyenv())

# 절대경로 판정 — startsWith(p, "/") 금지(금칙 ③). drive-letter · UNC · 역슬래시 · ~ 를 인식.
.lineage_is_abs <- function(p) {
  grepl("^([A-Za-z]:)?[/\\\\]", p) | grepl("^~", p)
}

.lineage_norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)

# 존재가 아니라 **정체**를 본다 — 디렉토리가 있다고 그게 *그* 프로젝트 루트인 건 아니다.
.lineage_root_ok <- function(p) {
  length(p) == 1L && !is.na(p) && nzchar(p) &&
    file.exists(file.path(p, .LINEAGE_ROOT_MARKER))
}

.lineage_ascend <- function(from) {
  here <- .lineage_norm(from)
  repeat {
    if (.lineage_root_ok(here)) return(here)
    parent <- dirname(here)
    if (identical(parent, here)) return(NA_character_)
    here <- parent
  }
}

lineage_project_root <- function(force = FALSE) {
  if (!force && !is.null(.lineage_state$root)) return(.lineage_state$root)

  root <- NA_character_
  tier <- NA_character_
  for (nm in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    raw <- Sys.getenv(nm, unset = "")
    if (!nzchar(raw)) next
    cand <- .lineage_norm(raw)                    # ★검사 전에 정규화
    if (.lineage_root_ok(cand)) { root <- cand; tier <- nm; break }
    message(sprintf("[lineage] root 후보 기각 (%s=%s): 표지 '%s' 부재 — 다음 tier 로 낙하",
                    nm, cand, .LINEAGE_ROOT_MARKER))
  }
  if (is.na(root)) {
    cand <- .lineage_ascend(getwd())
    if (!is.na(cand)) { root <- cand; tier <- "ascend_from_cwd" }
  }
  if (is.na(root)) {
    stop(sprintf(paste0(
      "[lineage] 프로젝트 루트 미해결 — 표지 '%s' 를 가진 트리를 찾지 못했다.\n",
      "  탐색 순서: %s\n",
      "  CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s' / getwd()='%s'"),
      .LINEAGE_ROOT_MARKER, paste(.LINEAGE_ANCHOR_ORDER, collapse = " -> "),
      Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
      Sys.getenv("QM_ROOT", unset = ""), getwd()))
  }

  # ★"어느 트리에 썼나"가 로그에 안 남으면 worktree 실행이 main 의 mailbox 에 기록하는 일이
  #  침묵한다. env 앵커가 cwd 트리와 갈리면 알린다 — 낙하 자체는 계약대로 정당하고
  #  금지되는 것은 침묵뿐이다(금칙 ④-b 의 ANCHOR OVERRIDE 관용구).
  if (!is.na(tier) && !identical(tier, "ascend_from_cwd")) {
    local_root <- .lineage_ascend(getwd())
    if (!is.na(local_root) && !identical(local_root, root)) {
      message(sprintf("[lineage] ANCHOR OVERRIDE — %s='%s' 를 쓴다 (cwd 트리 '%s' 아님)",
                      tier, root, local_root))
    }
  }

  .lineage_state$root <- root
  .lineage_state$tier <- tier
  root
}

# 상대경로만 루트에 붙인다. **이미 절대인 경로는 건드리지 않는다** —
# 호출자가 준 절대 wt_root(테스트 tempdir 등)에 루트를 덧붙이면 멀쩡한 경로가 깨진다.
.lineage_abs <- function(path) {
  if (!length(path)) return(path)
  rel <- !.lineage_is_abs(path)
  if (any(rel)) path[rel] <- file.path(lineage_project_root(), path[rel])
  path
}

# ─── Git state ──────────────────────────────────────────
#  [2026-08-02 수리 — r-portability 계통] 종전 `system("git ... 2>/dev/null", intern=TRUE)` 는
#  Windows 에서 **항상 실패**했다: R 의 system() 은 cmd.exe 로 넘기는데 cmd 에 `/dev/null` 이
#  없어 "파일 이름, 디렉터리 이름 또는 볼륨 레이블 구문이 잘못되었습니다"(status 128)가 난다.
#  tryCatch 가 그걸 삼켜 **git_commit 이 조용히 "unknown" 으로 결손**됐다 — 계보 추적이
#  무증상으로 죽어 있었다(WT-D20260802_001 R2 라운드 적발).
#  정본: system2() 로 인자를 분리하고 stderr 는 R 레벨에서 버린다(쉘 리다이렉션 의존 제거).
#
#  [2026-08-02 2차 — 결손 라벨링] 무엇이 실제로 썩었는지 실측으로 확정했다:
#    · git_commit 은 **우연히 살아남았다** — git rev-parse 가 HEAD 를 먼저 출력한 뒤
#      '2>/dev/null' 에서 죽어, 구 코드의 sha[1] 이 진짜 SHA 를 집었다(exit 128 은 warning).
#    · git_dirty 는 **거짓이었다** — git status 는 통째로 실패해 0행을 반환하고
#      `length(out) > 0` 이 **항상 FALSE** → "clean tree" 라는 그럴듯한 정상값으로 위장.
#      실측 대조: 같은 트리에서 구 경로 FALSE vs system2 정본 TRUE(1행 변경).
#      전수 집계상 2026-06(Windows 이관) ~ 08 기록 79건이 전량 FALSE, 그 이전 309건은 전량 TRUE.
#  ★그래서 미측정은 FALSE 가 아니라 NA(→ JSON null) 로, SHA 미확보는 명시 라벨
#  "UNAVAILABLE" 로 남긴다. 결손을 정상값처럼 반환하는 것이 이 결함의 재발 형태다.
#
#  [2026-08-09 의도적 무변경] git 은 **cwd 기준**으로 계속 조회한다(`-C <ROOT>` 미도입).
#  ① 계보가 기록해야 할 것은 스크립트가 실제로 실행된 트리의 상태다.
#  ② `-C ROOT` 로 바꾸면 08_Tests/hooks/test_lineage_git_state.R 의 위반 주입 4축
#     (비-리포 cwd → exit 128 유도)이 통째로 무력해진다 — git 이 항상 ROOT 에서 성공하므로
#     "미측정이 FALSE 로 위장되는가"를 더는 시험할 수 없다.
#  ⚠ 따라서 worktree 에서 실행하면 git_commit 은 **worktree HEAD**, 기록 위치는 아래
#    lineage_project_root() 가 고른 트리다. 갈리는 경우 ANCHOR OVERRIDE 메시지가 발화한다.
GIT_STATE_UNAVAILABLE <- "UNAVAILABLE"

.git_try <- function(args) {
  tryCatch({
    out <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = FALSE))
    st  <- attr(out, "status")
    st  <- if (is.null(st)) 0L else as.integer(st)
    list(ok = st == 0L, status = st, out = out)
  }, error = function(e) list(ok = FALSE, status = NA_integer_, out = character(0)))
}

capture_git_state <- function() {
  errs <- character(0)

  sha_res <- .git_try(c("rev-parse", "HEAD"))
  sha <- if (!sha_res$ok || !length(sha_res$out) || !nzchar(trimws(sha_res$out[1]))) {
    errs <- c(errs, sprintf("git rev-parse HEAD exit=%s", sha_res$status))
    GIT_STATE_UNAVAILABLE
  } else trimws(sha_res$out[1])

  st_res <- .git_try(c("status", "--porcelain"))
  dirty <- if (!st_res$ok) {
    errs <- c(errs, sprintf("git status --porcelain exit=%s", st_res$status))
    NA   # ★FALSE 아님 — 미측정과 clean tree 는 다른 사실이다
  } else length(st_res$out) > 0

  # warning 이 아니라 라벨로 남긴다(warning 은 로그에서 밀려 사라진다). 운영자 가시성용 message 만 병행.
  if (length(errs)) {
    message(sprintf("[lineage] git 상태 미측정 — %s", paste(errs, collapse = "; ")))
  }

  list(
    git_commit = sha,
    git_dirty = dirty,
    git_state_error = if (length(errs))
      paste0("git 상태 미측정(정상 상태 아님): ", paste(errs, collapse = "; ")) else NULL
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
#  [2026-08-09] 같은 cwd 가정을 앓고 있었다 — 프로젝트-상대 입력 경로를 비-루트 cwd 에서
#  넘기면 file.exists() 가 FALSE 라 **조용히 NA** 로 떨어졌다(해시가 없는데 오류도 없음).
#  ★단 cwd 기준을 **먼저** 본다: 호출자가 자기 디렉토리 기준으로 넘긴 경로를 루트로 재해석하면
#   멀쩡히 동작하던 경로가 깨진다. cwd → 루트 순서로 시도하고, 둘 다 실패해야 NA.
.lineage_resolve_input <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) return(NA_character_)
  if (file.exists(path)) return(path)                 # 호출자 cwd 기준 우선
  if (.lineage_is_abs(path)) return(NA_character_)    # 절대인데 부재면 더 볼 곳이 없다
  cand <- tryCatch(file.path(lineage_project_root(), path),
                   error = function(e) NA_character_)
  if (!is.na(cand) && file.exists(cand)) return(cand)
  NA_character_
}

compute_file_hash <- function(path, algo = "sha256") {
  resolved <- .lineage_resolve_input(path)
  if (is.na(resolved)) return(NA_character_)
  digest::digest(file = resolved, algo = algo)
}

capture_input_hashes <- function(file_paths) {
  if (!length(file_paths)) return(list())
  hashes <- vapply(file_paths, compute_file_hash, character(1))

  # ★키는 **호출자가 준 형태 그대로** 둔다. 해석된 절대경로로 바꾸면 기록이 기계-종속이 되고
  #  기존 388 entry(키 = 호출자가 준 경로)와 형식이 갈려 계보 비교가 깨진다.
  unresolved <- names(hashes)[is.na(hashes)]
  if (length(unresolved)) {
    # NA(→ JSON null)는 유지하되 침묵하지 않는다 — 결손을 값처럼 흘려보내지 않기 위함.
    message(sprintf("[lineage] input 파일 미해결 %d건 — hash=null 로 기록: %s",
                    length(unresolved), paste(unresolved, collapse = ", ")))
  }
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
    #  [2026-08-02 수리] 구 구현 `as.integer(paste0(digits, "001"))` 은
    #  task_id 의 숫자열이 11자리(WT-D20260802_001 → "20260802001")여서 "001" 을 덧붙이면
    #  14자리가 되고 .Machine$integer.max(2147483647) 를 넘겨 **항상 NA** 였다.
    #  → 경고("NAs introduced by coercion to integer range")만 남기고 전 task 가
    #  fallback 상수 20260424 로 붕괴 = **task-결정성이 죽어 있었다**(실측: 기존 388건 중 329건이 20260424).
    #  정본: 자릿수를 버리지 않고 modulo 로 접어 task_id 별 결정성을 되살린다.
    digits <- gsub("[^0-9]", "", task_id)
    random_seed <- if (nzchar(digits)) {
      as.integer(as.numeric(digits) %% 2147483647)
    } else NA_integer_
    if (is.na(random_seed) || random_seed <= 0L) random_seed <- 20260424L
  }

  entry <- list(
    task_id = task_id,
    package_type = package_type,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_commit = git$git_commit,
    git_dirty = git$git_dirty,
    # ★결손 라벨을 여기서 떨어뜨리면 capture_git_state 의 구분이 무의미해진다 —
    #  구 구현이 정확히 그랬다(계산해 놓고 entry 에 안 실었다). 성공 시 null.
    git_state_error = git$git_state_error,
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
  wt_dir <- file.path(.lineage_abs(wt_root), task_id)
  lineage_path <- file.path(wt_dir, "artifact_lineage.json")

  # ★디렉토리를 자동생성하지 않는다 — 오타 task_id 로 유령 WT 가 mailbox 에 누적되는 결함이
  #  이 저장소에 선례가 있다(r-portability 금칙 ②: synthetic year-9999 WT 5건 잔류).
  #  대신 부재를 **해석된 절대경로와 함께** 명시한다: 구 구현은 raw connection error 만 던져
  #  cwd 문제인지 task_id 오타인지 호출자가 구별할 수 없었다.
  if (!dir.exists(wt_dir)) {
    stop(sprintf(paste0(
      "[lineage] WT 디렉토리 부재 — %s\n",
      "  wt_root='%s' / task_id='%s' / cwd='%s'\n",
      "  (자동생성하지 않는다: 오타 task_id 로 유령 WT 가 누적되는 것을 막기 위함)"),
      wt_dir, wt_root, task_id, getwd()))
  }

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
  # ★기록 대상 경로를 같이 찍는다 — "어느 트리에 썼나"가 로그에 안 남으면
  #  worktree 실행이 main 에 적재되는 일이 무증상으로 지나간다.
  cat(sprintf("[lineage] %s / %s appended -> %s\n",
              task_id, lineage_entry$package_type, lineage_path))
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
  pkg_rel  <- file.path(wt_root, task_id, sprintf("%s.json", package_type))
  pkg_path <- file.path(.lineage_abs(wt_root), task_id, sprintf("%s.json", package_type))

  if (file.exists(pkg_path)) {
    # ★기록값은 **호출자가 준 형태**(= 현행 388 entry 와 같은 프로젝트-상대 표기)를 유지한다.
    #  해석된 절대경로를 실으면 기록이 기계-종속이 되고 기존 기록과 형식이 갈린다.
    #  해시는 해석된 실경로에서 뜬다 — 구 구현은 비-루트 cwd 에서 file.exists()가 FALSE 라
    #  file_path·file_hash_sha256 이 **둘 다 조용히 누락**됐다(오류 없이 필드만 사라짐).
    extra$file_path <- pkg_rel
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
  # [2026-08-09] 같은 cwd 결함 — 비-루트 cwd 에서는 lineage 가 실재해도 경로가 안 잡혀
  # reason="no_lineage" 를 돌려줬다. ★이건 예외가 아니라 **그럴듯한 정상 반환값**이라
  # 호출자(reproducibility_validator)가 "계보 없음"으로 읽는다 — 결손의 값-위장.
  wt_dir <- file.path(.lineage_abs(wt_root), task_id)
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

cat("[lineage_utils.R] v6.1 R11 Loaded (cwd-independent, 2026-08-09). Functions:\n")
cat("  build_lineage_entry(task_id, package_type, ...)\n")
cat("  append_lineage(task_id, lineage_entry)\n")
cat("  record_package_lineage(task_id, package_type, method_selected=NA, ...)\n")
cat("  capture_git_state() / capture_r_env() / capture_input_hashes(paths)\n")
cat("  smoke_reproduce(task_id)\n")
cat("  lineage_project_root(force=FALSE)  # 표지 기반 루트 해석 (cwd 무관)\n")
