#==============================================================================
# test_lineage_git_state.R — artifact lineage 의 git 상태 기록 계약 검사기
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md 금칙 ⑤ (쉘 문법 argv 주입)
#       + "결손을 정상값으로 위장하지 말 것"
#
# 배경 (2026-08-02 실측, WT-D20260802_001 R2 에서 적발):
#   구 capture_git_state() 는 system("git status --porcelain 2>/dev/null", intern=TRUE) 였다.
#   Windows R 은 셸을 경유하지 않아 git 이 '2>/dev/null' 을 pathspec 으로 받고 exit 128 →
#   출력 0행 → `length(out) > 0` 이 **항상 FALSE** → "clean tree" 라는 정상값으로 위장.
#   전수 집계: 2026-06(Windows 이관)~08 기록 79건 전량 FALSE / 그 이전 309건 전량 TRUE.
#
# ★이 검사기는 정상경로만 재지 않는다. git 이 실패하는 상황을 **실제로 만들어**
#   (=위반 주입) 그 실패가 JSON 까지 명시 라벨로 도달하는지 본다.
#   구 구현의 진짜 실패는 "라벨을 계산해 놓고 entry 에 안 실은 것"이었으므로,
#   함수 반환값이 아니라 **직렬화된 파일**을 읽어 판정한다.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))

cat("=== lineage git-state contract ===\n")

# ─── 1) 정상 경로: 리포지토리 안에서는 실측이 나와야 한다 ────────────────────
g <- capture_git_state()
if (grepl("^[0-9a-f]{40}$", g$git_commit)) {
  ok("live_sha_is_real", substr(g$git_commit, 1, 12))
} else {
  bad("live_sha_is_real", sprintf("40-hex SHA 가 아님: %s", g$git_commit))
}
if (is.logical(g$git_dirty) && !is.na(g$git_dirty)) {
  ok("live_dirty_measured", sprintf("git_dirty = %s", g$git_dirty))
} else {
  bad("live_dirty_measured", sprintf("리포 안인데 미측정(NA): %s", g$git_dirty))
}
if (is.null(g$git_state_error)) {
  ok("live_no_error_label")
} else {
  bad("live_no_error_label", sprintf("정상경로인데 오류 라벨: %s", g$git_state_error))
}

# ─── 2) 위반 주입: git 이 실패하는 상황을 실제로 만든다 ──────────────────────
# 비-리포지토리 디렉토리에서 호출 → git rev-parse / status 가 exit 128.
# (최상위 on.exit 은 금칙 ② 이므로 함수 프레임 안에서만 등록한다.)
inject_non_repo <- function() {
  d <- file.path(tempfile("nonrepo_"))
  dir.create(d, recursive = TRUE)
  old <- getwd()
  on.exit({ setwd(old); unlink(d, recursive = TRUE) }, add = TRUE)
  setwd(d)
  # git 이 상위 디렉토리 리포를 주워오지 않도록 탐색을 차단
  old_ceil <- Sys.getenv("GIT_CEILING_DIRECTORIES", unset = NA)
  old_disc <- Sys.getenv("GIT_DISCOVERY_ACROSS_FILESYSTEM", unset = NA)
  Sys.setenv(GIT_CEILING_DIRECTORIES = dirname(d))
  on.exit({
    if (is.na(old_ceil)) Sys.unsetenv("GIT_CEILING_DIRECTORIES") else Sys.setenv(GIT_CEILING_DIRECTORIES = old_ceil)
    if (is.na(old_disc)) Sys.unsetenv("GIT_DISCOVERY_ACROSS_FILESYSTEM") else Sys.setenv(GIT_DISCOVERY_ACROSS_FILESYSTEM = old_disc)
  }, add = TRUE)
  suppressMessages(capture_git_state())
}
gi <- inject_non_repo()

if (identical(gi$git_commit, "UNAVAILABLE")) {
  ok("injected_sha_labeled", "git_commit = UNAVAILABLE (명시 라벨)")
} else {
  bad("injected_sha_labeled",
      sprintf("git 실패인데 SHA 자리에 %s — 결손이 값으로 위장됨", gi$git_commit))
}
# ★핵심 회귀 가드: 미측정이 FALSE 로 내려앉으면 구 결함의 재발이다.
if (isFALSE(gi$git_dirty)) {
  bad("injected_dirty_not_false",
      "git 실패인데 git_dirty=FALSE — 'clean tree' 로 위장(구 결함 재발)")
} else if (is.na(gi$git_dirty)) {
  ok("injected_dirty_not_false", "git_dirty = NA (미측정)")
} else {
  bad("injected_dirty_not_false", sprintf("예상 밖 값: %s", gi$git_dirty))
}
if (!is.null(gi$git_state_error) && nzchar(gi$git_state_error)) {
  ok("injected_error_label", gi$git_state_error)
} else {
  bad("injected_error_label", "실패 사유 라벨이 없음")
}

# ─── 3) 직렬화 관통: 라벨이 JSON 파일까지 도달하는가 ─────────────────────────
# 구 구현의 실제 실패는 라벨을 **계산해 놓고 entry 에 싣지 않은 것**이었다.
# 그래서 반환값이 아니라 기록된 파일을 읽어 판정한다.
roundtrip_injected <- function() {
  root <- file.path(tempfile("wtroot_"))
  tid  <- "WT-D20260802_001"
  dir.create(file.path(root, tid), recursive = TRUE)
  d <- file.path(tempfile("nonrepo2_"))
  dir.create(d, recursive = TRUE)
  old <- getwd()
  old_ceil <- Sys.getenv("GIT_CEILING_DIRECTORIES", unset = NA)
  on.exit({
    setwd(old)
    if (is.na(old_ceil)) Sys.unsetenv("GIT_CEILING_DIRECTORIES") else Sys.setenv(GIT_CEILING_DIRECTORIES = old_ceil)
    unlink(c(root, d), recursive = TRUE)
  }, add = TRUE)
  Sys.setenv(GIT_CEILING_DIRECTORIES = dirname(d))
  setwd(d)
  e <- suppressMessages(build_lineage_entry(task_id = tid, package_type = "alpha_package"))
  suppressMessages(capture.output(append_lineage(tid, e, wt_root = root)))
  fromJSON(file.path(root, tid, "artifact_lineage.json"), simplifyVector = FALSE)$entries[[1]]
}
rt <- roundtrip_injected()

if (identical(as.character(rt$git_commit), "UNAVAILABLE")) {
  ok("json_sha_labeled", "직렬화된 git_commit = UNAVAILABLE")
} else {
  bad("json_sha_labeled", sprintf("JSON git_commit = %s", as.character(rt$git_commit)))
}
if (is.null(rt$git_dirty)) {
  ok("json_dirty_null", "직렬화된 git_dirty = null (미측정)")
} else if (isFALSE(rt$git_dirty)) {
  bad("json_dirty_null", "JSON git_dirty=false — 미측정이 clean 으로 기록됨(구 결함 재발)")
} else {
  bad("json_dirty_null", sprintf("JSON git_dirty = %s", as.character(rt$git_dirty)))
}
if (!is.null(rt$git_state_error)) {
  ok("json_error_label_present", "결손 사유가 entry 에 실림")
} else {
  bad("json_error_label_present",
      "git_state_error 가 JSON 에 없음 — capture 단계에서 계산해 놓고 entry 에서 떨어뜨림(구 결함)")
}

# ─── 4) seed 결정성: task_id 별로 달라야 한다 ────────────────────────────────
# 구 구현은 as.integer(paste0(digits,"001")) 가 integer 범위를 넘겨 **항상 NA** →
# 전 task 가 fallback 상수 20260424 로 붕괴했다(기존 388건 중 329건 실측).
seed_of <- function(tid) {
  suppressMessages(build_lineage_entry(task_id = tid, package_type = "alpha_package"))$random_seed
}
s1 <- seed_of("WT-D20260802_001"); s2 <- seed_of("WT-D20260424_005")
if (is.na(s1) || is.na(s2)) {
  bad("seed_not_na", sprintf("seed 가 NA (%s / %s)", s1, s2))
} else if (s1 == 20260424L && s2 == 20260424L) {
  bad("seed_task_deterministic",
      "두 task_id 가 같은 fallback 상수 20260424 로 붕괴 — task-결정성 사망(구 결함)")
} else if (s1 == s2) {
  bad("seed_task_deterministic", sprintf("서로 다른 task_id 가 같은 seed: %s", s1))
} else {
  ok("seed_task_deterministic", sprintf("%s / %s (서로 다름, integer 범위 내)", s1, s2))
}
if (!is.na(s1) && s1 == seed_of("WT-D20260802_001")) {
  ok("seed_stable", "같은 task_id 재호출 시 동일 seed")
} else {
  bad("seed_stable", "같은 task_id 인데 seed 가 바뀜 — 결정성 없음")
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "lineage_git_state", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
