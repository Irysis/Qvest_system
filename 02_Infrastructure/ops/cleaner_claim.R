# =============================================================================
# cleaner_claim.R — Cleaner 증류(distill) 선점 프로토콜 (2-pass 중복실행 방지)
#
# (2026-07-18 도훈 mandate W29 next_probe #4 — 07-06 병렬 중복실행 사고 ops 재현.
#  W29 증류에서 스폰된 Cleaner(task#89)와 메인 세션 자동 증류가 같은
#  cleaner_pending.json을 병행 소비 → 2-pass 중복실행. 착수 선점 표시 부재가 원인.)
#
# 설계:
#  - cleaner_pending.json(cleaner_pending_v2)에 distill_status(pending/in_progress/done)
#    + distill_owner + distill_claimed_at 필드 추가. weekly_cleaner_sweep.R가 pending 초기화.
#  - 지속 소유권 = JSON의 distill_status=in_progress (세션 전체 수명).
#  - claim 트랜잭션(read→check→write)의 짧은 임계구역만 mutex-dir(dir.create 원자성)로 직렬화.
#    → 두 소비자가 정확히 동시에 claim 시도해도 하나만 성공.
#  - stale 재점유: distill_claimed_at 이 stale_hours(기본 6h) 초과 in_progress = 크래시
#    세션으로 간주, 재점유 허용 (증류 세션은 sweep보다 길 수 있어 sweep-lock 2h보다 관대).
#  - 하위호환(v1 파일·distill_status 결측): status=="distilled"면 done, 아니면 pending.
#
# 규율: 파일 경유·단일스레드. book_state/05_Production 무변경. OneDrive temp+rename.
#       DART API 미접촉.
#
# 진입점:
#   cleaner_distill_state(root)                     — 현재 claim 상태 조회
#   cleaner_claim_distill(owner, root, stale_hours) — 착수 claim (atomic)
#   cleaner_release_distill(owner, final_status, ..) — 완료/포기 시 상태 전환
#
# 소비: .claude/skills/cleaner/SKILL.md §0.2 (선점 프로토콜).
# =============================================================================

suppressWarnings(suppressMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("cleaner_claim: jsonlite 필요")
}))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# ── 경로 해석 (weekly_cleaner_sweep.R / close_round.R 동일 패턴) ────────────────
.cc_root <- function(root = NULL) {
  if (!is.null(root) && nzchar(root) && dir.exists(root))
    return(sub("/+$", "", gsub("\\\\", "/", root)))
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(v)) return(sub("/+$", "", gsub("\\\\", "/", v)))
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) return(cand)
  getwd()
}

.cc_pending_path <- function(root) file.path(.cc_root(root), ".cache", "cleaner_pending.json")
.cc_mutex_path   <- function(root) file.path(.cc_root(root), ".cache", "cleaner_distill.claim.lock")

# ── 타임스탬프 파서 (format "%Y-%m-%d %H:%M:%S", 실패 시 NA) ────────────────────
.cc_parse_ts <- function(x) {
  s <- as.character(x %||% "")
  if (!nzchar(s)) return(as.POSIXct(NA))
  suppressWarnings(as.POSIXct(substr(s, 1, 19), format = "%Y-%m-%d %H:%M:%S", tz = ""))
}

# ── distill_status 정규화 (하위호환: 결측 필드 → status로 유도) ─────────────────
.cc_derive_status <- function(pj) {
  ds <- as.character(pj$distill_status %||% "")
  if (nzchar(ds)) return(ds)
  st <- as.character(pj$status %||% "")
  if (identical(st, "distilled")) return("done")
  "pending"
}

# ── 원자적 JSON 쓰기 (temp+rename, Windows/OneDrive 폴백) ───────────────────────
#   mutex 임계구역 내에서만 호출 → writer-writer 직렬화 보장. reader 부분읽기는
#   temp+rename로 최소화(Windows는 rename 실패 시 copy-overwrite 폴백; window 극소).
.cc_atomic_write <- function(obj, path) {
  tmp <- sprintf("%s.tmp.%d", path, Sys.getpid())
  jsonlite::write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  ok <- suppressWarnings(file.rename(tmp, path))     # POSIX/비존재 시 원자적
  if (!isTRUE(ok)) {                                  # Windows: 대상 존재 시 rename 실패
    ok <- suppressWarnings(file.copy(tmp, path, overwrite = TRUE))
    suppressWarnings(unlink(tmp))
  }
  isTRUE(ok)
}

# ── claim mutex (dir.create 원자성; stale steal 포함) ──────────────────────────
#   임계구역이 밀리초 단위라 stale_s는 방어적 상한(비정상 종료 대비).
.cc_acquire_mutex <- function(mutex_path, wait_s = 5, stale_s = 120) {
  dir.create(dirname(mutex_path), showWarnings = FALSE, recursive = TRUE)
  deadline <- Sys.time() + wait_s
  repeat {
    if (isTRUE(suppressWarnings(dir.create(mutex_path, showWarnings = FALSE)))) return(TRUE)
    info <- suppressWarnings(file.info(mutex_path))
    age  <- suppressWarnings(as.numeric(difftime(Sys.time(), info$mtime, units = "secs")))
    if (!is.na(age) && age > stale_s) { suppressWarnings(unlink(mutex_path, recursive = TRUE)); next }
    if (Sys.time() > deadline) return(FALSE)
    Sys.sleep(0.2)
  }
}
.cc_release_mutex <- function(mutex_path) suppressWarnings(unlink(mutex_path, recursive = TRUE))

# =============================================================================
# cleaner_distill_state — 현재 claim 상태 조회 (비파괴)
#   반환: list(exists, distill_status, distill_owner, distill_claimed_at, status,
#              age_hours(in_progress 시), stale(bool))
# =============================================================================
cleaner_distill_state <- function(root = NULL, stale_hours = 6) {
  pending <- .cc_pending_path(root)
  if (!file.exists(pending)) return(list(exists = FALSE, distill_status = NA,
                                         message = "cleaner_pending.json 부재 — 증류 대기 없음."))
  pj <- tryCatch(jsonlite::fromJSON(pending, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(pj)) return(list(exists = TRUE, distill_status = NA, message = "파싱 실패."))
  ds <- .cc_derive_status(pj)
  claimed_at <- .cc_parse_ts(pj$distill_claimed_at)
  age_h <- if (identical(ds, "in_progress") && !is.na(claimed_at))
    as.numeric(difftime(Sys.time(), claimed_at, units = "hours")) else NA_real_
  list(exists = TRUE, distill_status = ds,
       distill_owner = as.character(pj$distill_owner %||% NA),
       distill_claimed_at = as.character(pj$distill_claimed_at %||% NA),
       status = as.character(pj$status %||% NA), week_of = as.character(pj$week_of %||% NA),
       age_hours = age_h,
       stale = isTRUE(!is.na(age_h) && age_h > stale_hours),
       schema_has_field = nzchar(as.character(pj$distill_status %||% "")))
}

# =============================================================================
# cleaner_claim_distill — 증류 착수 claim (atomic; 선점 프로토콜의 핵심)
#   owner       : 착수 세션/에이전트 식별자 (예 "session_main" / "task#89" / pid).
#   stale_hours : in_progress가 이보다 오래면 크래시로 간주 재점유 (기본 6h).
#   반환: list(claimed(bool), reason, status, owner, message, ...)
#     reason ∈ {claimed, stale_reclaim, in_progress, already_done, no_pending,
#               parse_fail, contended}
# =============================================================================
cleaner_claim_distill <- function(owner, root = NULL, stale_hours = 6, wait_s = 5) {
  owner <- as.character(owner %||% "")
  if (!nzchar(owner)) stop("cleaner_claim_distill: owner 식별자 필수.")
  pending <- .cc_pending_path(root)
  if (!file.exists(pending))
    return(list(claimed = FALSE, reason = "no_pending",
                message = "cleaner_pending.json 부재 — 증류 대기 없음."))
  mutex <- .cc_mutex_path(root)
  if (!.cc_acquire_mutex(mutex, wait_s = wait_s))
    return(list(claimed = FALSE, reason = "contended",
                message = "claim mutex 획득 실패 (타 세션 claim 임계구역 진행 중) — 잠시 후 재시도."))
  on.exit(.cc_release_mutex(mutex), add = TRUE)

  pj <- tryCatch(jsonlite::fromJSON(pending, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(pj))
    return(list(claimed = FALSE, reason = "parse_fail", message = "cleaner_pending.json 파싱 실패."))

  ds <- .cc_derive_status(pj)
  now <- Sys.time()

  if (identical(ds, "done"))
    return(list(claimed = FALSE, reason = "already_done", status = "done",
                owner = as.character(pj$distill_owner %||% NA),
                message = "이미 증류 완료(done) — 재실행 불필요."))

  stale_note <- NULL
  if (identical(ds, "in_progress")) {
    claimed_at <- .cc_parse_ts(pj$distill_claimed_at)
    age_h <- if (is.na(claimed_at)) NA_real_ else as.numeric(difftime(now, claimed_at, units = "hours"))
    if (is.na(age_h) || age_h <= stale_hours)
      return(list(claimed = FALSE, reason = "in_progress", status = "in_progress",
                  owner = as.character(pj$distill_owner %||% NA),
                  claimed_at = as.character(pj$distill_claimed_at %||% NA),
                  age_hours = age_h,
                  message = sprintf(
                    "이미 다른 세션이 증류 중 (owner=%s, %s전 claim) — 중복 회피. 병합 정합만 수행(SKILL §0.2 fallback).",
                    as.character(pj$distill_owner %||% "?"),
                    if (is.na(age_h)) "?" else sprintf("%.1fh", age_h))))
    stale_note <- sprintf("stale in_progress(owner=%s, %.1fh > %.1fh 상한) 재점유",
                          as.character(pj$distill_owner %||% "?"), age_h, stale_hours)
  }

  # pending (또는 stale in_progress) → claim
  prev_owner <- as.character(pj$distill_owner %||% "")
  pj$distill_status     <- "in_progress"
  pj$distill_owner      <- owner
  pj$distill_claimed_at <- format(now, "%Y-%m-%d %H:%M:%S")
  if (!.cc_atomic_write(pj, pending))
    return(list(claimed = FALSE, reason = "write_fail", message = "pending 원자쓰기 실패."))
  list(claimed = TRUE,
       reason = if (!is.null(stale_note)) "stale_reclaim" else "claimed",
       status = "in_progress", owner = owner, claimed_at = pj$distill_claimed_at,
       prev_owner = if (nzchar(prev_owner)) prev_owner else NA,
       message = paste0(sprintf("claim 성공 (owner=%s) — 증류 착수.", owner),
                        if (!is.null(stale_note)) paste0(" [", stale_note, "]") else ""))
}

# =============================================================================
# cleaner_release_distill — 증류 완료(done) 또는 포기(pending) 시 상태 전환.
#   final_status = "done"    : 정상 완료 (기본). sync_status=TRUE면 status="distilled"도 동기화.
#   final_status = "pending" : claim 포기(재소비 가능하게 해제).
#   owner 불일치 시 force=FALSE면 거부(타 세션 소유권 보호).
#   읽기-수정-쓰기로 다른 필드(digest_path/distill_summary 등 SKILL ⑤ 기록분) 전부 보존.
# =============================================================================
cleaner_release_distill <- function(owner, root = NULL, final_status = "done",
                                    force = FALSE, sync_status = TRUE, wait_s = 5) {
  owner <- as.character(owner %||% "")
  final_status <- match.arg(final_status, c("done", "pending"))
  pending <- .cc_pending_path(root)
  if (!file.exists(pending))
    return(list(released = FALSE, reason = "no_pending", message = "cleaner_pending.json 부재."))
  mutex <- .cc_mutex_path(root)
  if (!.cc_acquire_mutex(mutex, wait_s = wait_s))
    return(list(released = FALSE, reason = "contended", message = "claim mutex 획득 실패."))
  on.exit(.cc_release_mutex(mutex), add = TRUE)

  pj <- tryCatch(jsonlite::fromJSON(pending, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(pj)) return(list(released = FALSE, reason = "parse_fail"))
  cur_owner <- as.character(pj$distill_owner %||% "")
  if (!isTRUE(force) && nzchar(cur_owner) && nzchar(owner) && !identical(cur_owner, owner))
    return(list(released = FALSE, reason = "owner_mismatch", owner = cur_owner,
                message = sprintf("distill_owner=%s ≠ %s — force=TRUE 아니면 해제 거부.", cur_owner, owner)))

  pj$distill_status <- final_status
  pj$distill_released_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  if (identical(final_status, "pending")) { pj$distill_owner <- NULL; pj$distill_claimed_at <- NULL }
  if (isTRUE(sync_status) && identical(final_status, "done")) pj$status <- "distilled"
  if (!.cc_atomic_write(pj, pending))
    return(list(released = FALSE, reason = "write_fail"))
  list(released = TRUE, distill_status = final_status, owner = owner,
       synced_status = isTRUE(sync_status) && identical(final_status, "done"),
       message = sprintf("release 성공 — distill_status=%s%s.", final_status,
                         if (isTRUE(sync_status) && identical(final_status, "done")) " (status=distilled 동기화)" else ""))
}

# ── 셀프테스트 (CLEANER_CLAIM_SELFTEST 환경변수 시에만 — import 부작용 없음) ─────
if (identical(environment(), globalenv()) && !interactive() &&
    nzchar(Sys.getenv("CLEANER_CLAIM_SELFTEST", ""))) {
  troot <- file.path(tempdir(), sprintf("cc_selftest_%d", Sys.getpid()))
  dir.create(file.path(troot, ".cache"), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(schema = "cleaner_pending_v2", status = "awaiting_distill",
                            distill_status = "pending"),
                       file.path(troot, ".cache", "cleaner_pending.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  c1 <- cleaner_claim_distill("A", root = troot)
  c2 <- cleaner_claim_distill("B", root = troot)
  r1 <- cleaner_release_distill("A", root = troot)
  c3 <- cleaner_claim_distill("C", root = troot)
  cat(sprintf("[cleaner_claim selftest] claim1=%s claim2=%s(%s) release=%s claim3=%s(%s)\n",
              c1$claimed, c2$claimed, c2$reason, r1$released, c3$claimed, c3$reason))
  stopifnot(isTRUE(c1$claimed), isFALSE(c2$claimed), identical(c2$reason, "in_progress"),
            isTRUE(r1$released), isFALSE(c3$claimed), identical(c3$reason, "already_done"))
  unlink(troot, recursive = TRUE)
  cat("  PASS (4 asserts)\n")
}
