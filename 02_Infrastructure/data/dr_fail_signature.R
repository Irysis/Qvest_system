#==============================================================================
# dr_fail_signature.R — Daily Refresh [7] 실패 서명 게이트 (v10.4 2026-09-24 · 도훈 "의미없는거 같으면 없애버려도 돼")
#
# 왜: [7] 은 실패가 있으면 매 실행 "★부분실패 — <스텝>" 을 **푸시로** 보냈다. 원인이 같아도 매일 새 경보였다
#   — 실측 consensus 정체 6일 연속 같은 내용(08-28~09-20), 2주 ★부분실패 8회. 진짜 결함을 알리는 채널이라 없애지
#   않고 소음만 뺀다: 서명이 **바뀔 때만** 푸시 경보, 같은 서명 반복은 무음 요약(disable_notification — 채팅엔 남는다),
#   서명이 비면 "해소" 1회.
#
# 서명 = 정렬된 {스텝명} ∪ {stale:<항목명>}. ★숫자(lag·rc·개수·빌드월)는 서명에서 뺀다 — lag 가 매일 +1 되면
#   같은 원인이 매일 "새 서명"이 된다(v10.1 stranded 경보의 교훈). 헤더 본문에는 숫자를 그대로 싣는다(정보는 보존).
#
# 상태 = .cache/dr_fail_signature.json {signature, since, last_sent_at}. ★발송이 ok 로 반환된 뒤에만 커밋한다 —
#   발송 실패·수동 실행(QVEST_REFRESH_TG=0)이 상태를 소모하면 다음 정기 실행의 "신규" 경보가 무음으로 묻힌다.
#
# 호출: daily_refresh.sh [7/7] run_r 블록. 검사: 08_Tests/data/test_dr_fail_signature.R
#==============================================================================

# 실패 목록 문자열(dr_fail_summary — 공백 구분) + stale 항목명 → 정렬된 서명 토큰
dr_sig_items <- function(fails, stale_names = "") {
  f <- unlist(strsplit(trimws(paste(fails, collapse = " ")), "[[:space:]]+"))
  f <- f[nzchar(f) & f != "없음"]                     # "없음" = dr_fail_summary 의 빈 값
  f <- gsub("\\((?:[A-Za-z_]*rc=-?[0-9]+,?)+\\)", "", f, perl = TRUE)   # (rc=1) · (gate_rc=1,updater_rc=0)
  f <- gsub(":[0-9]+", "", f)                                   # :202608:3 (빌드월·개수)
  s <- unlist(strsplit(trimws(paste(stale_names, collapse = " ")), "[[:space:],]+"))
  s <- sub("\\(.*$", "", s[nzchar(s)])                           # benchmark(STALE,lag=3d) → benchmark
  sort(unique(c(f[nzchar(f)], if (length(s)) paste0("stale:", s))))
}

# ★(2026-11-13 · 도훈 "리프레시 실패 … 원천해결해" — 실패가 조용히 다음 날로 넘어가지 않게) 측정 관문 자료의 낡음은 날마다 한 번 소리 내 알린다.
#   1계층 측정 관문(round_core fresh-check)은 rawdata · benchmark 두 항목만 본다(v3/freshness.R → freshness_audit.R --items rawdata,benchmark).
#   그 둘이 낡은 채 같은 원인이 반복되면 측정이 하루 더 멈춘다 — 소음이 아니다(11-13 밤 [7] = '지속 1일째(같은 원인 · 무음)' · 자가 복구 보고도 무음).
#   서명에 stale:rawdata 또는 stale:benchmark 가 있고 오늘 아직 소리 낸 적이 없으면(last_loud 날짜 < 오늘) 반복이어도 푸시한다.
#   같은 날 두 번째 보고(밤 실행 뒤 자가 복구 등)는 종전대로 무음이다. 상태에 last_loud(마지막으로 소리 낸 날)를 더한다 — 없는 옛 상태는 since 로 읽는다.
DR_SIG_GATE_ITEMS <- c("stale:rawdata", "stale:benchmark")

dr_sig_read <- function(path) {
  st <- tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.list(st)) list(signature = "", since = NA_character_) else st
}

# 판정 — kind ∈ ok/new/changed/repeat/resolved · mute · hdr · state(발송 성공 후 커밋할 값, NULL = 상태 불변)
dr_sig_decide <- function(fails, stale_names = "", prev = list(signature = ""), today = Sys.Date()) {
  sig  <- paste(dr_sig_items(fails, stale_names), collapse = " ")
  psig <- as.character(prev$signature %||% "")
  if (length(psig) != 1L || is.na(psig)) psig <- ""
  since <- suppressWarnings(tryCatch(as.Date(as.character(prev$since %||% NA)), error = function(e) as.Date(NA)))
  fs <- trimws(paste(fails, collapse = " "))
  if (!nzchar(sig)) {
    if (nzchar(psig))
      return(list(kind = "resolved", mute = FALSE, sig = sig,
                  hdr = sprintf("[Daily Refresh v2 완료 — 해소: %s]", psig),
                  state = list(signature = "", since = NA_character_)))
    return(list(kind = "ok", mute = FALSE, sig = sig, hdr = "[Daily Refresh v2 완료]", state = NULL))
  }
  if (identical(sig, psig) && length(since) == 1L && !is.na(since)) {
    n <- as.integer(as.Date(today) - since) + 1L
    loud <- suppressWarnings(tryCatch(as.Date(as.character(prev$last_loud %||% NA)), error = function(e) as.Date(NA)))
    if (length(loud) != 1L || is.na(loud)) loud <- since
    gate <- any(dr_sig_items(fails, stale_names) %in% DR_SIG_GATE_ITEMS)
    if (gate && as.Date(today) > loud) {
      return(list(kind = "repeat_gate", mute = FALSE, sig = sig,
                  hdr = sprintf("[Daily Refresh v2 ★부분실패 지속 %d일째 — 측정 관문 자료 낡음(같은 원인 · 하루 한 번 알림) — %s]", n, fs),
                  state = list(signature = sig, since = format(since), last_loud = format(as.Date(today)))))
    }
    return(list(kind = "repeat", mute = TRUE, sig = sig,
                hdr = sprintf("[Daily Refresh v2 부분실패 지속 %d일째(같은 원인 · 무음) — %s]", n, fs),
                state = list(signature = sig, since = format(since), last_loud = format(loud))))
  }
  kind <- if (nzchar(psig)) "changed" else "new"
  list(kind = kind, mute = FALSE, sig = sig,
       hdr = sprintf("[Daily Refresh v2 ★부분실패 — %s (%s)]", fs,
                     if (kind == "new") "신규" else "원인 변경"),
       state = list(signature = sig, since = format(as.Date(today)), last_loud = format(as.Date(today))))
}

# 원자 쓰기 — 발송 ok 뒤에만 호출
dr_sig_commit <- function(path, state) {
  if (is.null(state)) return(invisible(FALSE))
  state$last_sent_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp", Sys.getpid())
  writeLines(jsonlite::toJSON(state, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE), tmp, useBytes = TRUE)
  invisible(file.rename(tmp, path) || file.copy(tmp, path, overwrite = TRUE))
}
