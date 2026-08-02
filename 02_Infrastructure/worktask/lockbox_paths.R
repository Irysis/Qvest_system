#==============================================================================
# lockbox_paths.R — Lockbox audit-trail 경로 계약 (R 측 단일 정의)
# 2026-08-02
#
# ─── 왜 별도 파일인가 (r-portability.md 금칙 ③) ──────────────────────────────
# `/tmp` 는 두 런타임에서 **다른 디렉토리로 해석된다**:
#   bash(MSYS)   → C:\Users\<user>\AppData\Local\Temp
#   Windows R    → C:/tmp   (선행 `/` 를 현재 드라이브 기준으로 해석)
#
# lockbox 접근 기록은 **훅(bash)이 쓰고 감사(R)가 읽는** 구조다. 두 런타임이 같은
# 리터럴을 공유하면 읽는 쪽은 영원히 빈 손이고, 그 공허함이 "위반 없음"으로 읽히면
# 감사가 죽는다. 2026-08-02 실측:
#   - bash /tmp 에 qvest_lockbox_access_*.log 4건 존재, C:/tmp 에 0건
#   - `audit_p2_data_separation()` 이 237/237 WT 전부 pass=TRUE "no_lockbox_access"
#   - 즉 P2 Data Separation 은 **구조적으로 실패할 수 없었다**
#
# 수리 방향(도훈 지시): `/tmp` 를 버리고 **프로젝트-상대 경로**로 옮긴다. 그러면 양쪽이
# 각자 프로젝트 루트를 marker 로 검증해 해석하므로 같은 디렉토리에 도달한다.
#
# bash 측 짝 = `02_Infrastructure/hooks/lockbox_paths.sh`.
# 두 파일의 하위경로 리터럴이 같은지 + 실제로 한쪽이 쓰고 다른 쪽이 읽는지는
# `08_Tests/hooks/test_lockbox_audit_path.R` 가 **위반 주입**으로 못박는다.
# (문서 규율이 아니라 검사기가 드리프트를 막는다 — 이 계통의 재발 기전이 정확히
#  "두 곳에서 같은 값을 만들면서 정합 검사를 안 만든 것"이다.)
#==============================================================================

# ★공유 리터럴 — 이 값은 lockbox_paths.sh 의 QVEST_LOCKBOX_SUBDIR 과 반드시 같아야 한다.
QVEST_LOCKBOX_SUBDIR <- ".cache/lockbox"

# 트레일이 살아 있는지의 양성 신호. 훅이 발화할 때마다 갱신한다.
# 이게 없으면 "기록 0건"과 "검출기 사망"을 구별할 수 없다 — 구 P2 가 죽은 방식이 바로 그것.
QVEST_LOCKBOX_HEARTBEAT <- "_trail_heartbeat"

# 정체성 marker (r-portability.md 금칙 ③ — `dir.exists()` 존재검사로 대체 금지)
QVEST_ROOT_MARKER <- "02_Infrastructure/hooks/qvest_hook_router.py"

.qvest_lb_norm <- function(p) {
  if (!nzchar(p)) return("")
  # 역슬래시는 **판정 전에** 정규화 (2026-08-01 실사고: 역슬래시 QM_ROOT 가 R 소스문자열에서 `\U` 파싱)
  normalizePath(gsub("\\\\", "/", p), winslash = "/", mustWork = FALSE)
}

.qvest_lb_root_ok <- function(cand) {
  if (is.null(cand) || !nzchar(cand)) return("")
  p <- .qvest_lb_norm(cand)
  if (file.exists(file.path(p, QVEST_ROOT_MARKER))) p else ""
}

.qvest_lb_root_cache <- NULL

# 프로젝트 루트 해석 — 우선순위는 표준 계열(r-portability.md 금칙 ④):
#   CLAUDE_PROJECT_DIR → QM_ROOT → getwd() 상향 탐색.
# 모든 tier 는 marker 로 정체성을 검사하고, 미충족 후보는 **수락이 아니라 다음 tier 로 낙하**시킨다.
qvest_project_root <- function(force = FALSE) {
  if (!force && !is.null(.qvest_lb_root_cache)) return(.qvest_lb_root_cache)

  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  for (cand in cands) {
    hit <- .qvest_lb_root_ok(cand)
    if (nzchar(hit)) {
      assign(".qvest_lb_root_cache", hit, envir = .GlobalEnv)
      return(hit)
    }
    if (nzchar(cand)) {
      message(sprintf("[lockbox_paths] 후보 '%s' 기각 — marker 부재(%s). 다음 tier 로 해석합니다.",
                      cand, QVEST_ROOT_MARKER))
    }
  }

  here <- .qvest_lb_norm(getwd())
  repeat {
    if (file.exists(file.path(here, QVEST_ROOT_MARKER))) {
      assign(".qvest_lb_root_cache", here, envir = .GlobalEnv)
      return(here)
    }
    parent <- dirname(here)
    if (identical(parent, here)) break
    here <- parent
  }
  stop(sprintf("[lockbox_paths] project root 미발견 — marker(%s) 를 가진 후보 0건. CLAUDE_PROJECT_DIR 또는 QM_ROOT 를 설정하세요.",
               QVEST_ROOT_MARKER))
}

# ─── Trail 경로 ──────────────────────────────────────────────────────────────
qvest_lockbox_dir <- function(root = NULL, create = FALSE) {
  if (is.null(root)) root <- qvest_project_root()
  d <- file.path(root, QVEST_LOCKBOX_SUBDIR)
  if (create && !dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

qvest_lockbox_log <- function(wt_id, root = NULL, create_dir = FALSE) {
  file.path(qvest_lockbox_dir(root = root, create = create_dir),
            sprintf("qvest_lockbox_access_%s.log", wt_id))
}

qvest_lockbox_heartbeat_path <- function(root = NULL) {
  file.path(qvest_lockbox_dir(root = root), QVEST_LOCKBOX_HEARTBEAT)
}

# 트레일 발화 사실 — "기록 0건"과 "검출기 사망"의 구별자.
#   list(live=TRUE/FALSE, last=<chr|NA>, dir=<path>)
#
# ★liveness 판정은 **heartbeat 파일**이지 디렉토리 존재가 아니다.
#   디렉토리는 아무나(격리 사본 배치·`mkdir -p` 부수효과·클론) 만들 수 있어서
#   존재검사로 정체성검사를 대신하는 순간 "발화한 적 없는데 live" 가 되고,
#   그건 이 수리가 걷어내려던 바로 그 결함(결손을 정상값으로 내려앉힘)의 재발이다.
qvest_lockbox_trail_state <- function(root = NULL) {
  d <- qvest_lockbox_dir(root = root)
  hb <- file.path(d, QVEST_LOCKBOX_HEARTBEAT)
  last <- NA_character_
  live <- file.exists(hb)
  if (live) {
    l <- tryCatch(readLines(hb, warn = FALSE), error = function(e) character(0))
    if (length(l)) last <- trimws(l[length(l)])
  }
  list(live = live, last = last, dir = d)
}

# ─── 레거시 위치 (읽기 전용 — 잔여 writer 탐지용) ────────────────────────────
# 구 구현이 `/tmp/qvest_lockbox_access_*.log` 를 썼다. 그 리터럴이 두 런타임에서
# 갈렸으므로 레거시 후보도 두 곳이다. 여기에 **새 파일이 생기면** 아직 수리 안 된
# writer 가 남아 있다는 뜻이므로, 감사가 이를 WARN 으로 표면화한다.
# (판정 evidence 로는 쓰지 않는다 — 2026-08-02 이전 잔재는 합성 검증 산물이라
#  자본 판정에 섞으면 안 된다. 격리 사본: .cache/lockbox/_legacy_quarantine_20260802/)
qvest_lockbox_legacy_dirs <- function() {
  wd <- .qvest_lb_norm(getwd())
  drv <- regmatches(wd, regexpr("^[A-Za-z]:", wd))
  out <- character(0)
  # ① Windows R 이 선행 `/` 를 해석하던 곳 (<drive>:/tmp)
  if (length(drv) == 1L) out <- c(out, file.path(drv, "tmp"))
  # ② bash(MSYS) 가 `/tmp` 로 보던 곳
  for (v in c("TEMP", "TMP")) {
    e <- Sys.getenv(v, unset = "")
    if (nzchar(e)) out <- c(out, .qvest_lb_norm(e))
  }
  unique(out[dir.exists(out)])
}

qvest_lockbox_legacy_logs <- function() {
  dirs <- qvest_lockbox_legacy_dirs()
  if (!length(dirs)) return(character(0))
  unlist(lapply(dirs, function(d) {
    list.files(d, pattern = "^qvest_lockbox_access_.*\\.log$", full.names = TRUE)
  }), use.names = FALSE)
}

cat("[lockbox_paths.R] Loaded. QVEST_LOCKBOX_SUBDIR =", QVEST_LOCKBOX_SUBDIR, "\n")
