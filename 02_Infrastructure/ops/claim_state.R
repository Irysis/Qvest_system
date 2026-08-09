# =============================================================================
# claim_state.R — 세션 간 배정 상태를 **선언 필드**로 판정 (자유 문자열 부분 일치 폐기)
#
# 왜 (2026-08-09 실사고):
#   내가 만든 배정 규약이 owner **자유 문자열**을 `grepl("CLAIMED", owner)` 로 판정했다.
#   병렬 세션이 FQ-165 를 끝내며 owner 에 **"완료 — Q-Lead session cee0bdd0"** 를 썼는데
#   "CLAIMED" 가 없어 가드가 통과시켰고, 나는 **중복 착수 직전까지 갔다**.
#   (스크립트가 owner 를 출력하도록 만들어 둔 덕에 눈으로 보고 멈췄다 — 자동 가드는 실패.)
#
#   ★계통: 같은 날 아침 메모리에 적힌 [[project-status-freetext-substring-predicates-20260808]]
#     ("status 는 enum 이 아니다 — 부분 일치 술어가 양방향으로 틀린다") 를 **내 가드가 그대로 밟았다**.
#     원장 164 항목에 고유 89종 자유 문자열이 있었던 그 결함의 배정 판본이다.
#
# 정본: 판정은 **선언 필드 `claim`** 로만 한다. 자유 문자열 owner 는 사람이 읽는 메모로만 남긴다.
#   `claim = {state, session, ts, note}` · state ∈ .CLAIM_STATES
#
# 자매: 02_Infrastructure/ops/frontier_queue_io.R (정본 writer)
# =============================================================================

.CLAIM_STATES <- c(
  "unclaimed",   # 아무도 안 잡음 — 착수 가능
  "claimed",     # 특정 세션이 진행 중 — 착수 금지
  "complete",    # 완료 — 재착수 금지(결과는 result_ref)
  "blocked",     # 선행 조건 미충족 — 착수 불가(사유 note)
  "dohoon"       # 도훈 결정 대기 — 세션 임의 착수 금지
)

#' 항목의 배정 상태를 판정한다. **선언 필드 우선, 없으면 자유 문자열에서 추론하되 그 사실을 표시**.
#' @return list(state, source, session, ts, note, safe_to_start)
claim_state <- function(entry) {
  cl <- entry$claim
  if (!is.null(cl) && !is.null(cl$state) && as.character(cl$state)[1] %in% .CLAIM_STATES) {
    st <- as.character(cl$state)[1]
    return(list(state = st, source = "declared", session = cl$session %||% NA_character_,
                ts = cl$ts %||% NA_character_, note = cl$note %||% NA_character_,
                safe_to_start = st == "unclaimed"))
  }
  ## 레거시 추론 — ★판정에 쓰지 말고 '선언 필드 부재' 를 알리는 용도
  own <- if (is.null(entry$owner)) "" else paste(entry$owner, collapse = " ")
  sts <- if (is.null(entry$status)) "" else as.character(entry$status)[1]
  blob <- paste(own, sts)
  ## ★2026-08-09 수리 — 초판이 **거울상 결함**을 만들었다(FQ-164 false positive).
  ##   owner="UNCLAIMED — ... **도훈 지시** 2026-08-09" 가 bare `도훈` 패턴에 걸려 'dohoon' 으로 오분류됐다.
  ##   원인 2가지: ①명시 선언(UNCLAIMED)을 **부수 언급보다 나중에** 검사 ②`도훈` 패턴이 너무 넓음
  ##     — 원장 전체가 "도훈 지시/mandate/confirm" 을 **출처 표기**로 쓴다. 상태 토큰은 `dohoon_decision` 뿐.
  ##   ⇒ ①명시 선언을 **최우선** ②상태 토큰만 좁게 매칭.
  ##   (같은 계통: [[feedback-identify-before-existence-check]] "수리가 새 오답을 낳는다")
  guess <- if (grepl("^\\s*(UNCLAIMED|미배정)|\\bUNCLAIMED\\b|^\\s*미배정", blob)) "unclaimed"
           else if (grepl("\\[COMPLETE\\]|완료|\\bdone\\b|resolved|established|closed|refuted|_negative", blob)) "complete"
           else if (grepl("\\[CLAIMED\\]|\\bCLAIMED\\b|in_flight|in-flight", blob)) "claimed"
           else if (grepl("dohoon_decision|dohoon_confirm|도훈 결정 대기|도훈 confirm 대기", blob)) "dohoon"
           else if (grepl("blocked_by|blocked_until|data_gate_closed|^blocked", blob)) "blocked"
           else "unknown"
  ## ★2026-08-09 3차 수리 — **상태 충돌 검출**.
  ##   census 에서 FQ-139 가 owner="미배정" ∧ status="done" 인데 착수 가능으로 나왔다.
  ##   owner 와 status 가 서로 다른 이야기를 하면 **조용히 한쪽을 고르면 안 된다** — 그게 중복 착수를 만든다.
  ##   ⇒ 충돌이면 unknown 으로 강등하고 사유를 note 에 실어 **안전측 차단**.
  own_says   <- grepl("UNCLAIMED|미배정", own)
  stat_says  <- grepl("done|complete|COMPLETE|완료|resolved|established|closed|refuted|_negative|quarantine", sts)
  conflict   <- own_says && stat_says
  if (conflict) guess <- "unknown"

  list(state = guess, source = "inferred(레거시 — 선언 필드 부재)",
       session = NA_character_, ts = NA_character_,
       note = if (conflict) sprintf("★상태 충돌 — owner='%s' 는 미배정인데 status='%s' 는 완료다. 안전측 차단.",
                                     substr(own, 1, 60), substr(sts, 1, 40)) else own,
       conflict = conflict,
       ## ★추론은 안전측으로: unclaimed 로 **확신**될 때만 착수 허용
       safe_to_start = identical(guess, "unclaimed"))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 착수 전 게이트 — 안전하지 않으면 stop(). 호출부가 무시할 수 없게 예외로 던진다.
#'
#' @param my_session 내 세션 식별자. ★**재진입 허용**에 쓴다 —
#'   state="claimed" 인데 그 claim 이 **내 것**이면 같은 라운드의 재실행이므로 통과시킨다.
#'   (2026-08-09 실전 적발: 스크립트가 claim 을 쓴 뒤 후단에서 죽자, 재실행이 **자기 claim 에 막혔다**.
#'    "남이 잡음" 과 "내가 잡음" 을 구별하지 않은 설계 결함.)
#'   ★단 complete/dohoon/blocked 는 내 것이어도 통과시키지 않는다 — 재착수 자체가 금지 대상이다.
assert_can_start <- function(entry, id = NULL, my_session = NULL) {
  cs <- claim_state(entry)
  lab <- if (is.null(id)) (entry$id %||% "?") else id
  reentry <- identical(cs$state, "claimed") && !is.null(my_session) &&
             !is.na(cs$session) && identical(as.character(cs$session), as.character(my_session))
  message(sprintf("[claim] %s state=%s (source=%s)%s%s", lab, cs$state, cs$source,
                  if (!is.na(cs$session)) paste0(" session=", cs$session) else "",
                  if (reentry) " ★재진입(내 claim)" else ""))
  if (!isTRUE(cs$safe_to_start) && !reentry)
    stop(sprintf("[claim] ★착수 금지 — %s 의 배정 상태가 '%s' 다.%s%s\n  근거: %s",
                 lab, cs$state,
                 if (cs$source != "declared") " 선언 필드가 없어 자유 문자열에서 추론했다 — 안전측으로 차단한다." else "",
                 if (identical(cs$state, "claimed") && !is.null(my_session))
                   sprintf(" (내 세션 '%s' ≠ claim 세션 '%s')", my_session, cs$session) else "",
                 substr(cs$note, 1, 200)))
  invisible(c(cs, list(reentry = reentry)))
}

#' 배정 선언 — 착수 시 호출. 자유 문자열 owner 는 사람용 메모로 함께 갱신한다.
make_claim <- function(entry, state, session, note = NA_character_, ts = NULL) {
  stopifnot(state %in% .CLAIM_STATES)
  entry$claim <- list(state = state, session = session,
                      ts = ts %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
                      note = note)
  entry$owner <- sprintf("[%s] %s — %s", toupper(state), session,
                         if (is.na(note)) "" else note)
  entry
}

cat("[claim_state.R] Loaded — claim_state() / assert_can_start() / make_claim()\n")
cat("  ★규약: 배정 판정은 선언 필드 `claim$state` 로만. owner 자유 문자열 부분 일치 판정 폐기.\n")
