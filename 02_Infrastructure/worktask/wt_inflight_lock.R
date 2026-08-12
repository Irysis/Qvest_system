#==============================================================================
# wt_inflight_lock.R — WorkTask in-flight **실효 잠금**
#
# 2026-08-08 신설. 사건: FQ-122 / WT-D20260808_001 을 **두 alpha-research 실행이
#   병렬 수행**했다(challenge_note.md C-9/C-10). 피해 3건 전부 실파일:
#     ① stage_artifacts/.../preregistration.json 이 한 판본에서 다른 판본으로 **교체**
#        — 측정 전 사전등록이 교체 시점 추적 불가면 사전등록의 의미가 무너진다.
#     ② mailbox/.../alpha_package.json 이 2차 실행에 덮어쓰기 (원본 보존은 수리자의
#        선의였을 뿐 **계약이 아니었다**).
#     ③ alpha_frontier_queue.json 의 FQ-122 갱신이 두 번 유실.
#
# ★근본 원인 = v8.3 "hypothesis_index in-flight WT 인덱싱(병렬 중복실행 방지)" 가
#   **코드가 아니라 문장**이었다. 실측: `in_flight_since` 를 읽는 프로덕션 코드
#   **0건**(2026-08-08 전 저장소 grep — 적중은 challenge_note 산문 1건 + probe 1건뿐).
#   원장의 `owner`/`in_flight_since` 는 사람이 읽는 자문 문자열이고, 두 번째 실행을
#   멈춰 세우는 주체가 아무도 없었다. 이 저장소의 반복 계통 —
#   **"등재(존재) 를 판정(처분) 으로 읽는다"** — 의 또 하나의 사례다.
#
# 본 모듈은 그 문장을 **함수**로 옮긴다.
#
#------------------------------------------------------------------------------
# 계약
#------------------------------------------------------------------------------
#   wt_acquire_inflight(wt, agent)   ← **실행 시작 시 정확히 1회.** 이미 잠겨 있으면
#                                       stop() 으로 실행을 세우고 escalate 를 남긴다.
#   wt_assert_inflight(wt, token)    ← 같은 실행의 **후속 Rscript** 가 쓰는 재확인.
#                                       배타적이지 않다(잠금을 새로 잡지 않는다).
#   wt_release_inflight(wt, token)   ← 실행 종료 시. 토큰 불일치는 거부(force= 예외).
#   wt_inflight_state(wt)            ← 비파괴 조회. wt_inflight_list() = 전체 현황.
#
# ★acquire 와 assert 를 **다른 함수로 가른 것이 이 설계의 핵심**이다.
#   한 에이전트 실행은 Rscript 를 여러 번 띄우므로 pid 기반 재진입 판정은 성립하지
#   않는다(자기 잠금에 자기가 막힌다). 그렇다고 "같은 agent 이름이면 통과" 로 하면
#   FQ-122 가 **정확히 그 경우**라 아무것도 막지 못한다(양쪽 다 `alpha-research`).
#   그래서 배타성의 판정 시점을 **호출 지점**으로 옮겼다: 시작 시 1회 부르는
#   acquire 만 배타적이고, 그 반환 토큰을 가진 후속 호출은 assert 로 통과한다.
#   ⇒ 2차 실행은 자기 시작점에서 acquire 를 부르는 순간 막힌다.
#
#   ⚠ **알려진 잔여 구멍(정직 표기)**: 2차 실행이 acquire 를 **아예 부르지 않으면**
#     이 잠금은 그를 막지 못한다. 프로세스 밖에서 강제할 방법이 이 하네스엔 없다
#     (PreToolUse 훅은 R 의 write_json 을 못 본다 — C-10 에서 실증됐고, agent marker
#      기반 식별은 2026-07-03 감사가 구조적 불가로 확정했다). 그 층의 방어는
#     ① wt_create() 자동 acquire ② 에이전트 시작 규약 ③ 사후 검거
#     (`wt_inflight_audit()` — 잠금 기록 없이 산출물이 생긴 WT 를 적발) 3중이다.
#     ★이 파일이 있다고 병렬 실행이 불가능해지는 것이 **아니다**. 규약을 따르는
#       실행은 막히고, 따르지 않는 실행은 사후에 검거된다 — 그 이상을 주장하지 않는다.
#
#------------------------------------------------------------------------------
# 원자성
#------------------------------------------------------------------------------
# 잠금은 **디렉토리**다(`.inflight.lock/` + 내부 `owner.json`). 파일이 아니다:
#   R 의 file.create() 는 O_EXCL 이 아니라 기존 파일을 **truncate** 하므로
#   "존재 확인 후 생성" 이 원자적이지 않고, 경합 시 두 실행이 모두 성공한다
#   (= 잠금이 있는데 조용히 통과 = 이 사건이 두 번째로 일어나는 형태).
#   dir.create() 는 POSIX/Win32 공히 존재 시 실패하는 **원자적 배타 연산**이다.
#   같은 저장소 선례: cleaner_claim.R `.cc_acquire_mutex`, pipeline_trigger.sh LOCKDIR
#   (Git Bash 에 flock 부재 → 동일 폴백).
#
# 사용:
#   source("02_Infrastructure/worktask/wt_inflight_lock.R")
#   cl <- wt_acquire_inflight("WT-D20260808_001", agent = "alpha-research")
#   # ... 후속 스크립트에서:  wt_assert_inflight("WT-D20260808_001", cl$claim_token)
#   wt_release_inflight("WT-D20260808_001", cl$claim_token)
#==============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("wt_inflight_lock: jsonlite 필요")
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

WTL_STALE_HOURS_DEFAULT <- 6      # 도훈 지시 최소안: 6h 초과 = stale, 경고 후 승계 허용
WTL_LOCK_BASENAME       <- ".inflight.lock"
WTL_ESCALATION_LEDGER   <- "06_Registry/inflight_conflicts.jsonl"

# ── 루트 해석 ────────────────────────────────────────────────────────────────
#  r-portability.md ④ — CLAUDE_PROJECT_DIR 우선, 역슬래시 정규화는 **검사 전에**
#  (QM_ROOT 는 User scope 라 `C:\...` 형식으로 들어온다; 검사 뒤로 미루면 형식 오류가
#   존재 검사를 그냥 통과한다). 선행 "/" 하드코딩·절대경로 판정 금지.
.wtl_norm <- function(p) sub("/+$", "", gsub("\\\\", "/", p))
.wtl_root <- function(root = NULL) {
  if (!is.null(root) && nzchar(root)) {
    r <- .wtl_norm(root)
    if (dir.exists(r)) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v)) { v <- .wtl_norm(v); if (dir.exists(v)) return(v) }
  }
  .wtl_norm(getwd())
}

.wtl_mailbox_root <- function(root = NULL) file.path(.wtl_root(root), "qepm", "mailbox", "worktask")

# ── WT id 정규화 ─────────────────────────────────────────────────────────────
# ★표기 갈림이 잠금을 무력화하는 것을 막는다. 이 저장소는 2026-08-02 에 이미
#   같은 날 에이전트들이 `WT-D...`(하이픈) 과 `WT_D...`(언더스코어) 를 제각각 써서
#   Q-Lead 가 실존 산출물 13파일을 "산출 0" 으로 오판한 전례가 있다
#   (worktask_manager.R:78-85 주석). 두 표기가 **서로 다른 잠금**을 잡으면
#   잠금이 있는 채로 병렬 실행이 성립한다 — 검사기가 이 축을 못박는다.
.wtl_canonical_id <- function(wt_id, root = NULL) {
  wt_id <- as.character(wt_id)[1]
  if (!grepl("^WT[-_]", wt_id)) return(wt_id)          # WT 접두 아닌 id 는 그대로
  base   <- sub("^WT[-_]", "", wt_id)
  cands  <- c(paste0("WT-", base), paste0("WT_", base))
  mbroot <- .wtl_mailbox_root(root)
  for (cd in cands) if (dir.exists(file.path(mbroot, cd))) return(cd)
  cands[1]                                              # 미존재 시 하이픈형이 정본
}

.wtl_lock_dir <- function(wt_id, root = NULL)
  file.path(.wtl_mailbox_root(root), .wtl_canonical_id(wt_id, root), WTL_LOCK_BASENAME)

.wtl_owner_path <- function(lock_dir) file.path(lock_dir, "owner.json")

.wtl_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

.wtl_parse_ts <- function(x) {
  s <- as.character(x %||% "")
  if (!nzchar(s)) return(as.POSIXct(NA))
  suppressWarnings(as.POSIXct(substr(s, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = ""))
}

.wtl_token <- function() {
  # 실행 식별자. 재현성 요구가 없는 순수 식별용이라 시각+pid+난수로 충분하다.
  sprintf("%s-%d-%s", format(Sys.time(), "%Y%m%dT%H%M%S"), Sys.getpid(),
          paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = ""))
}

#' 잠금 나이(시간). owner.json 의 started_at 우선, 없으면 디렉토리 mtime.
#' ★owner.json 이 없어도 **나이를 알 수 없다고 해서 free 로 떨어뜨리지 않는다**
#'   (mtime 폴백). 결손을 정상값으로 내려앉히는 것이 이 저장소의 상시 실패 계통이다.
.wtl_age_hours <- function(lock_dir, owner) {
  ts <- .wtl_parse_ts(owner$started_at %||% NA)
  if (is.na(ts)) {
    info <- suppressWarnings(file.info(lock_dir))
    ts <- if (nrow(info) && !is.na(info$mtime[1])) info$mtime[1] else as.POSIXct(NA)
  }
  if (is.na(ts)) return(NA_real_)
  as.numeric(difftime(Sys.time(), ts, units = "hours"))
}

.wtl_read_owner <- function(lock_dir) {
  op <- .wtl_owner_path(lock_dir)
  if (!file.exists(op)) return(NULL)
  tryCatch(jsonlite::fromJSON(op, simplifyVector = TRUE), error = function(e) NULL)
}

.wtl_write_owner <- function(lock_dir, rec) {
  jsonlite::write_json(rec, .wtl_owner_path(lock_dir),
                       auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}

# ── escalate 원장 ────────────────────────────────────────────────────────────
#' 충돌·승계를 append-only 로 남긴다. Q-Lead 가 읽는 면.
#' 실패해도 잠금 판정을 뒤엎지 않는다(기록 실패가 게이트를 열어선 안 되지만,
#' 반대로 기록 실패로 정상 취득을 막을 이유도 없다 — 판정은 이미 내려졌다).
wt_inflight_escalate <- function(event, wt_id, detail = list(), root = NULL) {
  p <- file.path(.wtl_root(root), WTL_ESCALATION_LEDGER)
  rec <- c(list(ts = .wtl_now(), event = event, wt_id = wt_id, pid = Sys.getpid()), detail)
  line <- tryCatch(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null", na = "null"),
                   error = function(e) NULL)
  if (is.null(line)) return(invisible(FALSE))
  ok <- tryCatch({
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    con <- file(p, open = "a", encoding = "UTF-8"); on.exit(close(con), add = TRUE)
    writeLines(as.character(line), con, useBytes = TRUE); TRUE
  }, error = function(e) FALSE)
  invisible(ok)
}

# =============================================================================
# wt_inflight_state — 비파괴 조회
#   반환: list(held, wt_id, canonical_id, lock_dir, owner, age_hours, stale,
#              owner_readable)
#   ★held=TRUE 인데 owner_readable=FALSE 인 상태가 존재한다(디렉토리는 생겼고
#     owner.json 을 쓰기 직전인 마이크로초 창, 또는 비정상 종료). 이 상태는
#     **free 가 아니라 held** 로 판정한다 — 판별 불가를 통과로 바꾸면 그게 fail-open 이다.
# =============================================================================
wt_inflight_state <- function(wt_id, stale_hours = WTL_STALE_HOURS_DEFAULT, root = NULL) {
  cid <- .wtl_canonical_id(wt_id, root)
  ld  <- .wtl_lock_dir(wt_id, root)
  if (!dir.exists(ld)) {
    return(list(held = FALSE, wt_id = wt_id, canonical_id = cid, lock_dir = ld,
                owner = NULL, age_hours = NA_real_, stale = FALSE, owner_readable = NA))
  }
  own <- .wtl_read_owner(ld)
  age <- .wtl_age_hours(ld, own)
  list(held = TRUE, wt_id = wt_id, canonical_id = cid, lock_dir = ld,
       owner = own, age_hours = age,
       stale = isTRUE(!is.na(age) && age > stale_hours),
       owner_readable = !is.null(own))
}

# =============================================================================
# wt_acquire_inflight — **실행 시작 시 1회.** 배타적 취득.
#
#   on_conflict = "stop"  (기본) — 두 번째 실행을 실제로 세운다. 이것이 정본.
#               = "return"        — 검사기·조회용. list(status="BLOCKED") 반환.
#
#   status: ACQUIRED | TAKEOVER_STALE | BLOCKED
# =============================================================================
wt_acquire_inflight <- function(wt_id,
                                agent,
                                stale_hours = WTL_STALE_HOURS_DEFAULT,
                                on_conflict = c("stop", "return"),
                                note = NULL,
                                root = NULL) {
  on_conflict <- match.arg(on_conflict)
  if (missing(agent) || !nzchar(as.character(agent %||% "")))
    stop("[wt_lock] agent 는 필수다 — 소유자 없는 잠금은 승계 판단이 불가능하다.")

  cid <- .wtl_canonical_id(wt_id, root)
  ld  <- .wtl_lock_dir(wt_id, root)
  parent <- dirname(ld)
  if (!dir.exists(parent))
    stop(sprintf("[wt_lock] WT mailbox 부재: %s — wt_create() 먼저.", parent))

  mk <- function(status, takeover_of = NULL) {
    tok <- .wtl_token()
    rec <- list(wt_id = cid, agent = as.character(agent)[1], claim_token = tok,
                pid = Sys.getpid(), started_at = .wtl_now(),
                host = Sys.info()[["nodename"]] %||% NA,
                wd = .wtl_norm(getwd()), note = note %||% NA,
                takeover_of = takeover_of %||% NA)
    .wtl_write_owner(ld, rec)
    list(status = status, claim_token = tok, wt_id = cid, lock_dir = ld,
         agent = as.character(agent)[1], owner = rec)
  }

  # ── 원자적 취득 시도 ──────────────────────────────────────────────────────
  if (isTRUE(suppressWarnings(dir.create(ld, showWarnings = FALSE)))) {
    res <- mk("ACQUIRED")
    wt_inflight_escalate("ACQUIRED", cid, list(agent = res$agent, claim_token = res$claim_token), root)
    message(sprintf("[wt_lock] ACQUIRED %s — agent=%s token=%s", cid, res$agent, res$claim_token))
    return(invisible(res))
  }

  # ── 이미 잠겨 있다 ────────────────────────────────────────────────────────
  st  <- wt_inflight_state(wt_id, stale_hours = stale_hours, root = root)
  own <- st$owner
  age_txt <- if (is.na(st$age_hours)) "미상" else sprintf("%.2fh", st$age_hours)
  holder  <- own$agent %||% "(owner.json 판독 불가)"
  since   <- own$started_at %||% "(미상)"

  if (isTRUE(st$stale)) {
    # stale — 경고 후 승계 허용 (도훈 지시 최소안)
    wt_inflight_escalate("TAKEOVER_STALE", cid,
                         list(new_agent = as.character(agent)[1], prev_agent = holder,
                              prev_token = own$claim_token %||% NA, age_hours = st$age_hours), root)
    warning(sprintf(paste0("[wt_lock] ★stale 잠금 승계: %s\n",
                           "  이전 소유자 agent=%s · 시작=%s · 경과=%s (> %sh)\n",
                           "  이전 실행이 비정상 종료했을 수 있다 — 그 실행의 산출물이 ",
                           "중간 상태로 남아 있는지 확인할 것."),
                    cid, holder, since, age_txt, stale_hours), call. = FALSE)
    res <- mk("TAKEOVER_STALE", takeover_of = own$claim_token %||% "unknown")
    return(invisible(res))
  }

  # ── live 잠금 = 병렬 중복 실행 ────────────────────────────────────────────
  wt_inflight_escalate("BLOCKED", cid,
                       list(blocked_agent = as.character(agent)[1], holder_agent = holder,
                            holder_token = own$claim_token %||% NA,
                            holder_started_at = since, age_hours = st$age_hours), root)

  msg <- sprintf(paste0(
    "[wt_lock] ★STOP — %s 는 이미 in-flight 다 (병렬 중복 실행 차단).\n",
    "  보유자 : agent=%s · pid=%s · 시작=%s · 경과=%s\n",
    "  토큰   : %s\n",
    "  잠금   : %s\n",
    "  ── Q-Lead escalate 필요. 다음 중 하나를 **사람이** 고를 것:\n",
    "     (a) 본 실행을 폐기한다 (보유 실행이 정상 진행 중인 경우 — 기본값)\n",
    "     (b) 보유 실행이 죽었다면 %sh 경과 후 자동 승계되거나,\n",
    "         wt_release_inflight('%s', force=TRUE, reason=...) 로 즉시 해제한다\n",
    "     (c) 별개 가설이면 wt_create() 로 **새 WT** 를 발급받아 그쪽에서 진행한다\n",
    "  ★기록: %s"),
    cid, holder, own$pid %||% "?", since, age_txt,
    own$claim_token %||% "?", ld, stale_hours, cid, WTL_ESCALATION_LEDGER)

  if (identical(on_conflict, "stop")) stop(msg, call. = FALSE)
  message(msg)
  invisible(list(status = "BLOCKED", claim_token = NA_character_, wt_id = cid,
                 lock_dir = ld, agent = as.character(agent)[1], owner = own))
}

# =============================================================================
# wt_assert_inflight — 같은 실행의 후속 스크립트가 부르는 재확인 (비배타적)
#   토큰을 주면 소유권까지 확인한다. 안 주면 "잠금이 살아 있다"만 확인.
# =============================================================================
wt_assert_inflight <- function(wt_id, claim_token = NULL,
                               stale_hours = WTL_STALE_HOURS_DEFAULT, root = NULL) {
  st <- wt_inflight_state(wt_id, stale_hours = stale_hours, root = root)
  if (!isTRUE(st$held))
    stop(sprintf(paste0("[wt_lock] %s 에 in-flight 잠금이 없다 — 이 실행은 acquire 를 ",
                        "거치지 않았다.\n  wt_acquire_inflight('%s', agent=...) 로 시작할 것."),
                 st$canonical_id, st$canonical_id), call. = FALSE)
  if (!is.null(claim_token)) {
    held_tok <- st$owner$claim_token %||% NA
    if (!identical(as.character(held_tok), as.character(claim_token)))
      stop(sprintf(paste0("[wt_lock] ★토큰 불일치 — %s 의 잠금은 **다른 실행**이 갖고 있다.\n",
                          "  보유 token=%s (agent=%s) / 제시 token=%s\n",
                          "  당신의 실행이 승계당했거나, 병렬 실행이 진행 중이다. 즉시 중단."),
                   st$canonical_id, held_tok, st$owner$agent %||% "?", claim_token), call. = FALSE)
  }
  invisible(st)
}

# =============================================================================
# wt_release_inflight — 해제. 토큰 불일치 거부(force= 로만 우회, 사유 필수).
# =============================================================================
wt_release_inflight <- function(wt_id, claim_token = NULL, force = FALSE,
                                reason = NULL, root = NULL) {
  st <- wt_inflight_state(wt_id, root = root)
  if (!isTRUE(st$held)) {
    message(sprintf("[wt_lock] %s — 잠금 없음 (이미 해제됨).", st$canonical_id))
    return(invisible(list(status = "NOT_HELD", wt_id = st$canonical_id)))
  }
  held_tok <- st$owner$claim_token %||% NA
  if (!isTRUE(force)) {
    if (is.null(claim_token))
      stop(sprintf(paste0("[wt_lock] %s 해제에는 claim_token 이 필요하다 ",
                          "(보유 agent=%s).\n  남의 실행 잠금을 푸는 사고를 막는다 — ",
                          "의도적 강제해제는 force=TRUE + reason= 을 쓸 것."),
                   st$canonical_id, st$owner$agent %||% "?"), call. = FALSE)
    if (!identical(as.character(held_tok), as.character(claim_token)))
      stop(sprintf("[wt_lock] ★토큰 불일치 — 해제 거부. 보유=%s / 제시=%s",
                   held_tok, claim_token), call. = FALSE)
  } else {
    if (is.null(reason) || !nzchar(as.character(reason)))
      stop("[wt_lock] force=TRUE 에는 reason= 이 필수다 (강제해제는 기록에 남는다).")
    wt_inflight_escalate("FORCE_RELEASE", st$canonical_id,
                         list(holder_agent = st$owner$agent %||% NA,
                              holder_token = held_tok, reason = as.character(reason)[1]), root)
  }
  ok <- suppressWarnings(unlink(st$lock_dir, recursive = TRUE, force = TRUE)) == 0L
  if (!ok || dir.exists(st$lock_dir))
    stop(sprintf("[wt_lock] ★해제 실패 — 잠금 디렉토리가 남아 있다: %s", st$lock_dir))
  wt_inflight_escalate("RELEASED", st$canonical_id,
                       list(agent = st$owner$agent %||% NA, claim_token = held_tok,
                            forced = isTRUE(force)), root)
  message(sprintf("[wt_lock] RELEASED %s%s", st$canonical_id,
                  if (isTRUE(force)) " (강제)" else ""))
  invisible(list(status = "RELEASED", wt_id = st$canonical_id, forced = isTRUE(force)))
}

# =============================================================================
# wt_inflight_list — 현재 잡혀 있는 잠금 전체 (Q-Lead / bootstrap 소비면)
# =============================================================================
wt_inflight_list <- function(stale_hours = WTL_STALE_HOURS_DEFAULT, root = NULL) {
  mbroot <- .wtl_mailbox_root(root)
  if (!dir.exists(mbroot)) return(data.frame())
  wts <- list.dirs(mbroot, full.names = FALSE, recursive = FALSE)
  wts <- wts[nzchar(wts)]
  rows <- lapply(wts, function(w) {
    ld <- file.path(mbroot, w, WTL_LOCK_BASENAME)
    if (!dir.exists(ld)) return(NULL)
    own <- .wtl_read_owner(ld); age <- .wtl_age_hours(ld, own)
    data.frame(wt_id = w,
               agent = as.character(own$agent %||% NA),
               claim_token = as.character(own$claim_token %||% NA),
               pid = as.character(own$pid %||% NA),
               started_at = as.character(own$started_at %||% NA),
               age_hours = round(age, 2),
               stale = isTRUE(!is.na(age) && age > stale_hours),
               owner_readable = !is.null(own),
               stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

# =============================================================================
# wt_inflight_audit — **사후 검거**. acquire 를 부르지 않은 실행을 잡는 유일한 층.
#
#   잠금은 규약을 따르는 실행만 막는다(헤더의 잔여 구멍). 따르지 않은 실행은
#   "산출물은 있는데 잠금 기록이 없는 WT" 로 남는다 — escalate 원장에 해당 WT 의
#   ACQUIRED 가 한 건도 없는데 mailbox/stage 산출물이 존재하면 그것이 신호다.
#
#   ⚠ 소급 한계: 원장이 신설된 2026-08-08 **이전** WT 는 전부 "기록 없음" 이라
#     신호가 아니다. since= 로 기준일을 잘라 판정한다(기본 = 원장 최초 기록일).
# =============================================================================
wt_inflight_audit <- function(since = NULL, root = NULL) {
  rt <- .wtl_root(root)
  led <- file.path(rt, WTL_ESCALATION_LEDGER)
  seen <- character(0); first_ts <- NA_character_
  if (file.exists(led)) {
    lns <- readLines(led, warn = FALSE, encoding = "UTF-8")
    recs <- lapply(lns, function(l) tryCatch(jsonlite::fromJSON(l, simplifyVector = TRUE),
                                             error = function(e) NULL))
    recs <- Filter(Negate(is.null), recs)
    if (length(recs)) {
      first_ts <- as.character(recs[[1]]$ts %||% NA)
      acq <- Filter(function(r) identical(as.character(r$event %||% ""), "ACQUIRED"), recs)
      seen <- unique(vapply(acq, function(r) as.character(r$wt_id %||% ""), character(1)))
    }
  }
  cutoff <- .wtl_parse_ts(since %||% first_ts)
  mbroot <- .wtl_mailbox_root(root)
  if (!dir.exists(mbroot)) return(data.frame())
  wts <- list.dirs(mbroot, full.names = FALSE, recursive = FALSE)
  wts <- wts[grepl("^WT[-_]", wts)]
  rows <- lapply(wts, function(w) {
    d <- file.path(mbroot, w)
    arts <- list.files(d, pattern = "[.]json$")
    arts <- setdiff(arts, c("request.json", "status.json", "governance_log.json"))
    if (!length(arts)) return(NULL)
    info  <- file.info(file.path(d, arts))
    newest <- suppressWarnings(max(info$mtime, na.rm = TRUE))
    if (!is.na(cutoff) && !is.na(newest) && newest < cutoff) return(NULL)
    canon <- .wtl_canonical_id(w, root)
    if (canon %in% seen || w %in% seen) return(NULL)
    data.frame(wt_id = w, n_artifacts = length(arts),
               newest_artifact = format(newest, "%Y-%m-%dT%H:%M:%S"),
               finding = "산출물 존재 · ACQUIRED 기록 없음 (잠금 규약 미경유 의심)",
               stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}
