#!/usr/bin/env Rscript
#==============================================================================
# rf_fidelity_audit_lib.R — 적대적 충실도 감사의 스키마 검증과 판정 소비 (2026-09-04)
#
# 왜 생겼나 (도훈 질문 "논문 충실 구현하는지 적대적 검증자를 넣을 필요는 없을까"):
#   무인 충실구현의 검증 4관문은 전부 **산출물**을 본다 — 계약 산출물 유무·고정 축·PIT·원장.
#   "논문대로 구현했는가" 만은 재도출되지 않았고, FIDELITY.json 은 **에이전트의 진술**이었다.
#   저장소는 이 병으로 이미 데였다: 2608.23944 는 하지도 않은 변경(ρ 음수 확장)을 스스로
#   신고했고 원문 대조로만 잡혔다.
#
#   그리고 진짜 대가는 A등급 쪽이 아니라 **F 쪽**이다. 측정이 F 면 rf_replication_verify 가
#   ledger_consumed 로 그 논문을 **영구 소비**한다("selector 가 이 논문을 다시 집지 않는다").
#   구현이 틀려서 F 였다면 논문이 잘못된 이유로 영영 버려진다 — 반전 전략을 부호 반대로
#   이식하면 t -3.438 같은 강한 음수가 정확히 그렇게 생긴다.
#
# 경계: 감사자는 **등급을 못 건드린다**(AX-008). 하는 일은 둘뿐이다 —
#   ①귀속 라벨 정정 ②소비 보류(+자동 재구현 1회). 측정은 계약이, 판정은 essence 가 한다.
#
# 사용: Rscript rf_fidelity_audit_lib.R verify <audit.json>
#   verify(R) 는 rf_audit_gate() 만 부른다 — 스폰·읽기·처분·미실행 재스폰이 한 자리에 있다(2026-09-06).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
## ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그를 오염시켰다)
LOG <- Sys.getenv("QVEST_RP_JLOG", file.path(ROOT, ".cache/reinforce_auto_log.jsonl"))
dir.create(dirname(LOG), recursive = TRUE, showWarnings = FALSE)
.fa_log <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "fidelity_audit"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG, append = TRUE)
  cat(sprintf("[fid_audit] %s\n", event))
}

RF_AUDIT_VERDICTS <- c("faithful", "adapted", "misdeclared", "unverifiable")

#' 감사 산출물 스키마 검증 — 형식만 본다. 옳고 그름은 여기서 판정하지 않는다.
rf_audit_verify <- function(audit_p) {
  bad <- function(why) { .fa_log("audit_rejected", why = why, path = audit_p)
                         unlink(audit_p, force = TRUE); return(FALSE) }
  if (!file.exists(audit_p) || file.size(audit_p) == 0L) return(bad("감사 파일 부재"))
  A <- tryCatch(fromJSON(audit_p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(A)) return(bad("JSON 파싱 실패"))
  v <- as.character(A$verdict %||% "")
  if (!v %in% RF_AUDIT_VERDICTS)
    return(bad(sprintf("verdict '%s' 은 허용값 아님(%s)", v, paste(RF_AUDIT_VERDICTS, collapse = "/"))))
  # ★misdeclared 는 근거 없이 낼 수 없다 — 적대적 감사가 근거 없는 기각을 하면
  #   그건 감사가 아니라 잡음이다(반대 방향의 침묵과 같은 값어치).
  if (identical(v, "misdeclared")) {
    n <- length(A$undeclared_changes %||% list()) + length(A$signal_mismatch %||% list())
    if (n < 1L) return(bad("misdeclared 인데 지적 항목이 0건 — 근거 없는 기각"))
    if (!nzchar(as.character(A$evidence %||% ""))) return(bad("misdeclared 인데 원문 근거가 없다"))
    # ★채움 항목 차단 — 실측(2026-09-04): 감사가 signal_mismatch 배열에 "신호 불일치 없음" 을
    #   넣었다. 근거 게이트가 **배열 길이**로 서있으므로 그런 비발견 하나가 게이트를 열어준다.
    #   휴리스틱이다: 지적은 위치·원문을 가리키므로 짧을 수 없다. 전부 짧으면 근거로 안 센다.
    .items <- c(vapply(A$undeclared_changes %||% list(), function(x) as.character(x)[1], character(1)),
                vapply(A$signal_mismatch    %||% list(), function(x) as.character(x)[1], character(1)))
    if (!any(nchar(.items) >= 25L))
      return(bad("misdeclared 인데 지적이 전부 25자 미만 — 비발견 채움 항목으로 보인다"))
  }
  # ★unverifiable 은 faithful 이 아니다 — 원문을 못 읽었으면 "확인 못 함" 으로 남긴다.
  .fa_log("audit_verified", verdict = v,
       undeclared = length(A$undeclared_changes %||% list()),
       mismatch = length(A$signal_mismatch %||% list()))
  TRUE
}

#' 감사 판정 읽기 (파일이 없거나 깨졌으면 unverifiable — 침묵을 통과로 읽지 않는다)
#' ★`reason` 은 **이 함수가 판정을 못 읽었을 때만** 실린다 — 감사자 파일의 필드는 옮기지 않는다.
#'   rf_audit_disposition 이 그 유무로 "감사자의 unverifiable(원문 판독 실패)" 과 "미실행·파손" 을 가른다.
#'   정상 분기에 reason 을 넣으면 그 구분이 죽는다(양방향 검사 test_rf_audit_disposition_required.R).
rf_audit_read <- function(audit_p) {
  if (!file.exists(audit_p)) return(list(verdict = "unverifiable", reason = "감사 미실행"))
  A <- tryCatch(fromJSON(audit_p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(A)) return(list(verdict = "unverifiable", reason = "감사 파일 파손"))
  v <- as.character(A$verdict %||% "unverifiable")
  if (!v %in% RF_AUDIT_VERDICTS) v <- "unverifiable"
  list(verdict = v,
       undeclared_changes = A$undeclared_changes %||% list(),
       signal_mismatch = A$signal_mismatch %||% list(),
       evidence = as.character(A$evidence %||% ""),
       confidence = as.character(A$confidence %||% ""),
       note = as.character(A$note %||% ""))
}

#' 처분 — 도훈 선택 2026-09-04: **자동 재구현 1회 + 소비 보류**
#' @return list(action = "audit_required"|"proceed"|"reimplement"|"proceed_suspect", feedback = <재구현 지적사항>)
rf_audit_disposition <- function(aud, retries_done = 0L) {
  # ★미실행·파손 ≠ 판독 실패 (2026-09-05~06 실사고). 구판은 파일 부재를 감사자의 unverifiable 과 같은 칸
  #   (proceed)에 넣었다 — 킬스위치·CLI 부재·병합 즉사('\U')로 감사가 **안 돈** 논문 3건이 감사 없이
  #   소비·개설됐다. 감사자가 원문을 못 읽어 낸 unverifiable(reason 없음)은 정직한 판정이라 proceed 를 유지한다.
  if (identical(aud$verdict, "unverifiable") && !is.null(aud$reason))
    return(list(action = "audit_required", reason = as.character(aud$reason)[1]))
  if (!identical(aud$verdict, "misdeclared")) return(list(action = "proceed"))
  items <- c(vapply(aud$undeclared_changes %||% list(), function(x) paste0("- 미신고 변경: ", as.character(x)), character(1)),
             vapply(aud$signal_mismatch    %||% list(), function(x) paste0("- 신호 불일치: ", as.character(x)), character(1)))
  fb <- paste(c(items, if (nzchar(aud$evidence)) paste0("원문 근거: ", aud$evidence)), collapse = "\n")
  if (as.integer(retries_done) < 1L)
    list(action = "reimplement", feedback = fb)
  else
    # ★재구현도 기각되면 소비하되 꼬리표를 단다. 무한 재시도는 예산을 태우고,
    #   조용한 소비는 논문을 잘못된 이유로 버린다 — 둘 다 피한다.
    list(action = "proceed_suspect", feedback = fb)
}

#' 감사 관문 — 스폰 → 읽기 → 처분. 미실행(audit_required)이면 최대 max_retries 회 더 스폰한다 (2026-09-06).
#' ★verify 는 이 함수만 부른다: "감사 없이 개설 불가" 의 판정이 한 자리에 있어야 검사가 그 자리를 잰다.
#' ★스폰 전에 낡은 fidelity_audit.json 을 지운다 — 감사 레인이 게이트(halt_*)에서 나가면 자기 rm -f 에
#'   못 닿아, 같은 wdir 의 앞 판 감사가 이번 엔진의 감사로 읽힐 수 있다(재구현 2회차가 같은 wdir 을 쓴다).
#' @param spawn_fn     인자 없는 함수 — 감사 레인을 한 번 돌리고 rc(정수)를 돌려준다. 파일을 쓰는 건 레인이다.
#' @param max_retries  첫 스폰 뒤 추가 스폰 상한(총 스폰 = 1 + max_retries)
#' @param retries_done 재구현 횟수(요청 파일 audit_retries) — rf_audit_disposition 에 그대로 넘긴다
#' @param log_fn       jlog 형 함수(event, ...) — 재스폰마다 fidelity_audit_retry · 스폰 예외는 fidelity_audit_spawn_failed
#' @return list(aud, disp, spawns, retries, last_rc, reason) — reason 은 최종이 audit_required 일 때만
rf_audit_gate <- function(wdir, spawn_fn, max_retries = 2L, retries_done = 0L, log_fn = NULL) {
  aud_p <- file.path(wdir, "fidelity_audit.json")
  .log <- function(...) if (is.function(log_fn)) log_fn(...)
  .spawn <- function() {
    unlink(aud_p, force = TRUE)
    rc <- tryCatch(suppressWarnings(as.integer(spawn_fn())[1]),
                   error = function(e) { .log("fidelity_audit_spawn_failed", err = conditionMessage(e)); -1L })
    if (!length(rc) || is.na(rc)) -1L else rc       # -1 = 레인이 rc 를 안 돌려줬거나 던졌다
  }
  max_retries <- max(0L, suppressWarnings(as.integer(max_retries)), na.rm = TRUE)
  spawns <- 0L; rc <- -1L
  repeat {
    rc <- .spawn(); spawns <- spawns + 1L
    aud  <- rf_audit_read(aud_p)
    disp <- rf_audit_disposition(aud, retries_done = retries_done)
    if (!identical(disp$action, "audit_required") || spawns > max_retries) break
    .log("fidelity_audit_retry", n = spawns, max = max_retries, rc = rc, reason = disp$reason)
  }
  list(aud = aud, disp = disp, spawns = spawns, retries = spawns - 1L, last_rc = rc,
       reason = if (identical(disp$action, "audit_required")) disp$reason else NULL)
}

if (!interactive()) {
  a <- commandArgs(TRUE)
  if (length(a) >= 2L && identical(a[1], "verify"))
    quit(status = if (isTRUE(rf_audit_verify(a[2]))) 0L else 1L)
}
