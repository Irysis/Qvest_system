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
  guess <- if (grepl("완료|COMPLETE|complete|done|resolved|established|closed|negative|refuted", blob)) "complete"
           else if (grepl("CLAIMED|in_flight|in-flight|진행", blob) && !grepl("UNCLAIMED", blob)) "claimed"
           else if (grepl("dohoon_decision|도훈", blob)) "dohoon"
           else if (grepl("blocked|blocked_by|data_gate_closed", blob)) "blocked"
           else if (grepl("UNCLAIMED|미배정", blob)) "unclaimed"
           else "unknown"
  list(state = guess, source = "inferred(레거시 — 선언 필드 부재)",
       session = NA_character_, ts = NA_character_, note = own,
       ## ★추론은 안전측으로: unclaimed 로 **확신**될 때만 착수 허용
       safe_to_start = identical(guess, "unclaimed"))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 착수 전 게이트 — 안전하지 않으면 stop(). 호출부가 무시할 수 없게 예외로 던진다.
assert_can_start <- function(entry, id = NULL) {
  cs <- claim_state(entry)
  lab <- if (is.null(id)) (entry$id %||% "?") else id
  msg <- sprintf("[claim] %s state=%s (source=%s)%s", lab, cs$state, cs$source,
                 if (!is.na(cs$session)) paste0(" session=", cs$session) else "")
  message(msg)
  if (!isTRUE(cs$safe_to_start))
    stop(sprintf("[claim] ★착수 금지 — %s 의 배정 상태가 '%s' 다. %s\n  근거: %s",
                 lab, cs$state,
                 if (cs$source != "declared") "선언 필드가 없어 자유 문자열에서 추론했다 — 안전측으로 차단한다." else "",
                 substr(cs$note, 1, 200)))
  invisible(cs)
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
