#==============================================================================
# rf_boundary_backfill.R — 블록 **경계 처리 누락** 백필의 판정 정본 (B5FIX · 2026-09-26 · 도훈 승인 "1번 진행")
#
# ★왜 생겼나 (실사고 2026-09-25 · RP_20260924_052517_7308_adapted_rulefast):
#   러너(reinforce_auto_parallel.R)는 배치를 기록한 뒤 "이 블록에 빈 칸이 남았나" 로 경계를 판정한다(.blk_now/.blk_left). 그 격자는
#   **tick 머리에 읽은** 설계로 만든다. 22:07:51 에 B5 8칸(레인 설계)을 읽은 tick 이 22:08 기전 백필(B6)을 동기로 돌리는 사이 같은
#   설계 파일이 5칸으로 덮였고(22:16:13) 앞 5칸 배치를 기록한 뒤 경계 판정은 메모리의 8칸으로 '3칸 남음' 을 셌다 — B5 G2(적대검증) ·
#   블록 L-code · 블록 텔레그램이 전부 없었다. 다음 tick 은 파일의 5칸으로 격자를 만들어 B5 를 **완결**로 읽고 B7 로 넘어갔다.
#   경계 처리는 배치 끝 한 자리에서 한 번만 불리므로, 그 순간을 놓치면(설계 파일이 tick 도중 바뀜 · 러너가 경계 도중 죽음 · 텔레그램
#   실패 · 적대검증 예외) 다시 돌 길이 없었다. 09-24 07:04 같은 entry 의 B6 도 러너가 기전 레인 도중 멈춰 블록 텔레그램이 없다.
#
# ★판정 — "칸은 다 쟀는데 경계 처리의 흔적이 없는 블록" 을 **현재 격자·원장·산출물·로그에서 재도출**한다(진술 아님):
#   완결  = 현재 격자(설계 파일에서 재도출한 칸 목록)의 그 블록 코드가 전부 시도로 차 있다 ∧ 그 블록에 미결(재개 대상) 시도가 없다 ∧
#           측정된 시도가 하나 이상(측정 0 이면 러너 경계도 서지 않는다 — nb > 0 조건과 같다).
#   흔적  = ① G2(B5 만): 측정된 B5 시도 중 rf_adversary_status(자기 층 기준) 가 'unverified' 인 칸이 없다
#           ② L-code: stage_artifacts/l_code/reinforcement/l_code_<BID>_<BLK>.json 실재(rf_block_lcode.R::emit 경로 · 기전 백필과 같은 규약)
#           ③ 텔레그램: 로그 telegram_block(sent=true · src=parallel) 중 이 블록 것 — 신판 이벤트는 base_id·block 필드로, 구판(n 만)은
#              n → 이 entry 시도의 블록으로 사상하고 n ≥ 블록 마지막 측정 n ∧ 시각 ≥ 블록 첫 시도 시각일 때만 센다.
#   상한  = 로그 boundary_backfill(시작 표식) 수가 max_tries 이상이면 멈춘다(결정론적 실패의 출구 · 기전 백필 상한 2 와 같은 형태).
#   멱등  = 부품마다 자기 흔적으로 갈린다 — 흔적이 생기면 다시 안 돈다(두 번 돌려도 같은 결과).
#   ★재도출 대상은 **현재 격자**다: 격자를 tick 머리 스냅샷이나 격자 파일(program)에서 읽으면 이번 사고와 같은 어긋남을 백필도 되풀이한다.
#
# 제공: rfbb_read_events · rfbb_block_status · rfbb_tg_seen · rfbb_targets · rfbb_design_drift(격자 재도출 대조)
# 요구: rf_spec_sig.R(.rf_attempt_code · .rf_taken_codes) · rf_block_design.R(rfbd_cells · RFBD_BLOCKS — 대조) · (G2 판정)
#       rf_runner_gates.R::rf_adversary_status — 러너 안에서는 이미 적재돼 있다.
# 부작용 없음 — 읽기만. 부작용(G2 실행·L-code·기전·텔레그램·로그)은 러너가 한다.
# 검사: 08_Tests/reinforcement/test_rf_boundary_backfill.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RFBB_EVENT_START   <- "boundary_backfill"          # 시작 표식 — 상한 계수의 정본(시도 1회 = 1줄)
RFBB_EVENT_GAVE_UP <- "boundary_backfill_gave_up"  # 상한 도달 1회 표식(매 tick 소음 금지)
RFBB_BLOCK_NA      <- "RFBB_NO_BLOCK"

.rfbb_s1 <- function(x) { x <- suppressWarnings(as.character(unlist(x %||% ""))); if (!length(x) || is.na(x[1])) "" else x[1] }
.rfbb_ts <- function(x) {
  s <- .rfbb_s1(x); if (!nzchar(s)) return(NA_real_)
  s <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", s)          # 파이썬 레인의 +09:00 → +0900
  v <- suppressWarnings(as.numeric(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")))
  if (length(v) == 1L) v else NA_real_
}
.rfbb_num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x %||% NA_real_))); if (length(v)) v[1] else NA_real_ }
.rfbb_code <- function(a) .rfbb_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_))
.rfbb_measured <- function(a) is.list(a$essence) && is.finite(.rfbb_num(a$essence$port_t))

#' 러너 로그에서 판정에 쓰는 이벤트만 읽는다(문자열 선별 뒤 파싱 — 러너 로그는 수만 줄이다).
#' @return list of list(event, ts, n, sent, base_id, block, src)
rfbb_read_events <- function(log_path) {
  if (!nzchar(.rfbb_s1(log_path)) || !file.exists(log_path)) return(list())
  ln <- tryCatch(readLines(log_path, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  ln <- ln[grepl("\"(telegram_block|boundary_backfill|boundary_backfill_gave_up)\"", ln)]
  out <- lapply(ln, function(l) {
    r <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(r)) return(NULL)
    ev <- .rfbb_s1(r$event)
    if (!(ev %in% c("telegram_block", RFBB_EVENT_START, RFBB_EVENT_GAVE_UP))) return(NULL)
    list(event = ev, ts = .rfbb_s1(r$ts), n = .rfbb_num(r$n), sent = isTRUE(as.logical(.rfbb_s1(r$sent))) || isTRUE(r$sent),
         base_id = .rfbb_s1(r$base_id), block = .rfbb_s1(r$block), src = .rfbb_s1(r$src))
  })
  Filter(Negate(is.null), out)
}

#' 이 블록의 블록 텔레그램이 나갔는가 — ③ 흔적.
#' @param n_of 이 entry 시도의 n → 블록 코드(구판 이벤트 사상용 named character)
rfbb_tg_seen <- function(events, base_id, block, n_last, since, n_of) {
  for (e in events) {
    if (!identical(e$event, "telegram_block") || !isTRUE(e$sent)) next
    if (nzchar(e$src) && !identical(e$src, "parallel")) next
    if (!is.finite(e$n) || !is.finite(n_last) || e$n < n_last) next
    if (nzchar(e$base_id)) {                                   # 신판 — 필드가 곧 증거
      if (!identical(e$base_id, base_id)) next
      blk <- if (nzchar(e$block)) e$block else .rfbb_s1(n_of[as.character(e$n)])
      if (identical(blk, block)) return(TRUE)
      next
    }
    blk <- .rfbb_s1(n_of[as.character(e$n)])                   # 구판 — n → 이 entry 시도의 블록 · 시각 하한
    t <- .rfbb_ts(e$ts)
    if (identical(blk, block) && is.finite(t) && is.finite(since) && t >= since) return(TRUE)
  }
  FALSE
}

#' 블록별 경계 상태 — 현재 격자·원장·산출물·로그에서 재도출(순수 · 읽기만)
#' @param E        원장 entry(tick 시작 판독)
#' @param cells    러너 격자 칸 목록(설계·상주 적용 뒤) — 완결 판정의 정본
#' @param root     데이터 루트(L-code 디렉터리)
#' @param events   rfbb_read_events() 결과
#' @param adv_status function(a) → rf_adversary_status 의 status 문자열(러너가 carry 오버레이를 묶어 넘긴다). NULL 이면 G2 판정 안 함.
#' @return list of list(block, complete, why, n_last, n_measured, codes, need = c("g2","lcode","telegram")[...], tries, gave_up_logged, evidence)
rfbb_block_status <- function(E, cells, root, events = list(), adv_status = NULL) {
  bid <- .rfbb_s1(E$base_id)
  atts <- E$attempts %||% list()
  acode <- vapply(atts, .rfbb_code, character(1))
  n_of <- stats::setNames(sub("_.*$", "", acode), vapply(atts, function(a) .rfbb_s1(a$n), character(1)))
  taken <- tryCatch(.rf_taken_codes(atts), error = function(e) unique(acode[nzchar(acode)]))
  cblk <- vapply(cells %||% list(), function(c) .rfbb_s1(c$block), character(1))
  ccode <- vapply(cells %||% list(), function(c) .rfbb_s1(c$code), character(1))
  lcd <- file.path(root, "stage_artifacts/l_code/reinforcement")
  out <- list()
  for (b in unique(cblk[nzchar(cblk)])) {
    codes <- ccode[cblk == b]
    ab <- atts[startsWith(acode, paste0(b, "_"))]
    meas <- Filter(.rfbb_measured, ab)
    pend <- Filter(function(a) !.rfbb_measured(a) && !isTRUE(a$terminal), ab)
    free <- setdiff(codes[nzchar(codes)], taken)
    why <- if (length(free)) sprintf("free:%s", paste(utils::head(free, 4L), collapse = ","))
           else if (length(pend)) sprintf("pending:%d", length(pend))
           else if (!length(meas)) "no_measured" else "complete"
    rec <- list(block = b, complete = identical(why, "complete"), why = why, codes = codes, n_measured = length(meas),
                n_last = if (length(meas)) max(vapply(meas, function(a) .rfbb_num(a$n), numeric(1))) else NA_real_,
                need = character(0), evidence = character(0),
                tries = sum(vapply(events, function(e) identical(e$event, RFBB_EVENT_START) && identical(e$base_id, bid) &&
                                     identical(e$block, b), logical(1))),
                gave_up_logged = any(vapply(events, function(e) identical(e$event, RFBB_EVENT_GAVE_UP) && identical(e$base_id, bid) &&
                                              identical(e$block, b), logical(1))))
    if (rec$complete) {
      if (identical(b, "B5") && is.function(adv_status)) {
        unv <- Filter(function(a) identical(.rfbb_s1(tryCatch(adv_status(a), error = function(e) "unverified")), "unverified"), meas)
        if (length(unv)) { rec$need <- c(rec$need, "g2")
          rec$evidence <- c(rec$evidence, sprintf("g2_unverified=%s", paste(vapply(unv, .rfbb_code, character(1)), collapse = ","))) }
      }
      lp <- file.path(lcd, sprintf("l_code_%s_%s.json", bid, b))
      if (!file.exists(lp)) { rec$need <- c(rec$need, "lcode"); rec$evidence <- c(rec$evidence, "lcode_absent") }
      since <- suppressWarnings(min(vapply(ab, function(a) .rfbb_ts(a$opened_at), numeric(1)), na.rm = TRUE))
      if (!is.finite(since)) since <- .rfbb_ts(E$opened_at)
      if (!rfbb_tg_seen(events, bid, b, rec$n_last, since, n_of)) {
        rec$need <- c(rec$need, "telegram"); rec$evidence <- c(rec$evidence, "telegram_absent") }
    }
    out[[length(out) + 1L]] <- rec
  }
  out
}

#' 격자 재도출 대조 — 지금 설계 파일에서 다시 읽은 블록 설계(rf_block_design.R::rfbd_cells — 러너가 격자를 만든 바로 그 함수)가
#'   이 tick 격자를 만든 설계(러너 .blk_design)와 다른 블록. 다르면 격자가 낡았다 — 러너는 배치를 열지 않고 tick 을 닫는다.
#'   ★비교 대상은 칸 목록 전체(코드·처치·서술)다. 격자 파일(program)이나 tick 머리 스냅샷끼리 비교하면 이번 사고의 어긋남을 못 본다.
#' @param was 러너 .blk_design(블록 → rfbd_cells 결과 · 설계 없는 블록은 NULL)
#' @return 달라진 블록 id(없으면 character(0))
rfbb_design_drift <- function(root, base_id, was) {
  if (!exists("rfbd_cells", mode = "function") || !exists("RFBD_BLOCKS")) stop("rf_block_design.R 미적재 — rfbd_cells/RFBD_BLOCKS")
  key <- function(cc) if (is.null(cc) || !length(cc)) "" else as.character(toJSON(cc, auto_unbox = TRUE, null = "null", digits = NA))
  out <- character(0)
  for (b in RFBD_BLOCKS) {
    now <- rfbd_cells(root, base_id, b)
    if (!identical(key(now), key((was %||% list())[[b]]))) out <- c(out, b)
  }
  out
}

#' 백필 대상 — 완결 ∧ 흔적 누락 ∧ 상한 미만. 순서 = entry 의 블록 순서(원장) → 격자 순서.
#' @return list(todo = 대상 레코드들, gave_up = 상한 도달·미표식 레코드들, status = 전 블록 레코드)
rfbb_targets <- function(E, cells, root, log_path, max_tries = 2L, adv_status = NULL) {
  mt <- suppressWarnings(as.integer(max_tries)); if (length(mt) != 1L || is.na(mt) || mt < 1L) mt <- 2L
  st <- rfbb_block_status(E, cells, root, rfbb_read_events(log_path), adv_status)
  miss <- Filter(function(r) isTRUE(r$complete) && length(r$need), st)
  ord <- as.character(unlist(E$block_order %||% list())); ord <- ord[nzchar(ord)]
  if (length(miss) && length(ord)) {
    k <- match(vapply(miss, function(r) r$block, character(1)), ord); k[is.na(k)] <- 99L
    miss <- miss[order(k, seq_along(miss))]
  }
  list(todo = Filter(function(r) r$tries < mt, miss),
       gave_up = Filter(function(r) r$tries >= mt && !isTRUE(r$gave_up_logged), miss),
       status = st, max_tries = mt)
}
