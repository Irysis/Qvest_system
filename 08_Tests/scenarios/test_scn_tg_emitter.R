# test_scn_tg_emitter.R — 텔레그램 발송기 운영 시나리오 시험 (2026-11-10 감사 레인 B)
#
# 실제 telegram_notify.R 을 임시 루트에서 source 하고 httr 의 POST 를 모의본으로 바꾼다(네트워크 0 · 실제 발송 0).
#   토큰 · 채팅 id = 가짜 값(환경변수에 먼저 넣어 .env 를 읽어도 덮이지 않게) · 루트 = 임시(원장 · 잠금 · 보관이 거기에만 쌓인다).
#
#   T1 4096 초과 — 긴 본문도 실제 요청 text 가 4096자 이하(길이 맞춤) · 포인터 줄 보존
#   T2 API 실패(400) — tg_agent_brief 가 ok=FALSE 반환 · 원장 1줄 · 잠금 미생성(다음 실행이 재발송) · 호출자 계속
#   T3 같은 내용 중복 — 성공 뒤 같은 표제 재발송 = DUPLICATE_DISPATCH_BLOCKED · 요청 0
#   T4 사진 없음 — tg_send_photo 가 ok=FALSE kind=photo_missing · 원장 1줄 · tg_agent_brief 결과에 charts_missing
#   T5 사진 거부(400) — ok=FALSE kind=photo_http_error · 원장 1줄 (11-10 수리 · 구판은 원장 0 · 반환 = httr 응답)
#   T6 한글 · 이모지 — 요청 본문 text 가 원문 한글 · 이모지를 그대로 담는다(UTF-8)
#   T7 섹션 규칙 위반 — skeleton 은 stop() → 호출자가 tryCatch 없이 부르면 죽는다(보고 실패가 측정을 죽이는 경로) — 사실 고정
#   T8 무음 — mute=TRUE 면 disable_notification=TRUE · 기본은 키 없음(본문 바이트 불변)
#   T9 돌연변이 — 소스 텍스트에서 사진 실패 원장 기록을 지운 사본은 T5 가 빨개진다(검사가 공허하지 않다)
#   T10 tg_regime_briefing 반환 계약 — 소스에 sent_ok 가 있고 mrs_regime_send.R 이 그것을 읽는다(정적)

real_root <- local({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  d <- if (length(f)) dirname(gsub("\\\\", "/", f[1])) else getwd()
  if (!grepl("^([A-Za-z]:)?/", d)) d <- file.path(gsub("\\\\", "/", getwd()), d)   # 상대 경로 → 절대(아래에서 setwd 한다)
  dirname(dirname(d))
})
stopifnot(file.exists(file.path(real_root, "02_Infrastructure/telegram/telegram_notify.R")))
NOTIFY <- file.path(real_root, "02_Infrastructure/telegram/telegram_notify.R")

tmp <- gsub("\\\\", "/", tempfile("scn_tg_")); dir.create(file.path(tmp, "02_Infrastructure"), recursive = TRUE)
Sys.setenv(TG_BOT_TOKEN = "TEST_TOKEN_NOT_REAL", TG_CHAT_ID = "0", CLAUDE_PROJECT_DIR = tmp, QM_ROOT = tmp,
           QVEST_TG_DRY_RUN = "", QVEST_TG_SERIAL_LOCK = "false", QVEST_TG_ARCHIVE_DIR = file.path(tmp, "archive"))
setwd(tmp)
LEDGER <- file.path(tmp, "qepm/observability/telegram_send_failures.jsonl")
nl <- function() if (file.exists(LEDGER)) length(readLines(LEDGER, warn = FALSE)) else 0L

P <- 0L; F <- 0L
chk <- function(nm, cond, why = "") {
  if (isTRUE(cond)) { P <<- P + 1L; cat("  PASS ", nm, "\n") } else { F <<- F + 1L; cat("  FAIL ", nm, " :: ", why, "\n") }
}

load_notify <- function(src = NOTIFY) {
  suppressMessages(suppressWarnings(capture.output(source(src, local = globalenv(), encoding = "UTF-8"))))
  ## 모의 httr — 전역에 정의하면 전역 함수(tg_send 등)가 attach 된 httr 보다 먼저 찾는다.
  assign("SENT", list(), envir = globalenv())
  assign("MODE", "ok", envir = globalenv())   # ok | 400 | photo400
  assign("POST", function(url, body = NULL, encode = NULL, ...) {
    SENT[[length(SENT) + 1L]] <<- list(url = url, body = body, encode = encode)
    st <- if (MODE == "400" && grepl("sendMessage$", url)) 400L else if (MODE == "photo400" && grepl("sendPhoto$", url)) 400L else 200L
    structure(list(status = st, txt = if (st == 200L) "{\"ok\":true}" else
      "{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: mock\"}"), class = "mockresp")
  }, envir = globalenv())
  assign("http_error", function(r) r$status >= 400L, envir = globalenv())
  assign("status_code", function(r) r$status, envir = globalenv())
  assign("content", function(r, ...) r$txt, envir = globalenv())
  assign("upload_file", function(p) p, envir = globalenv())
}
load_notify()

secs <- function(n_lines = 5L, line = "가나다라 마바사 아자차 카타파하 ") list(
  list(type = "summary", emoji = "\U0001F6A8", body = "시나리오 시험 본문입니다 — 한글과 이모지를 그대로 보낸다"),
  list(type = "text", heading = "긴 본문", body = paste(rep(line, n_lines), collapse = "\n")),
  list(type = "kv", heading = "상세", kv = list("항목" = "값 하나", "산출물:" = "04_Research/x/y")))
brief <- function(title, ..., n = 5L) tg_agent_brief(agent = "Q-Lead", title = title, sections = secs(n), relaxed = TRUE,
                                                   decode_jargon = FALSE, glossary = FALSE, ...)
sent_text <- function() { m <- Filter(function(x) grepl("sendMessage$", x$url), SENT); if (length(m)) m[[length(m)]]$body$text else NA_character_ }

cat("== T1 4096 초과 — 길이 맞춤 ==\n")
SENT <- list(); r <- brief("[무인] T1 긴 본문", n = 400L)
tx <- sent_text()
chk("T1a 발송 ok", isTRUE(r$ok), paste(r$error))
chk("T1b 실제 요청 text <= 4096자", !is.na(tx) && nchar(tx) <= 4096L, sprintf("%s자", nchar(tx)))
chk("T1c 절삭 표식 남김", grepl("길이 한계로 일부 생략", tx, fixed = TRUE), "")

cat("== T2 API 실패 400 — 반환 · 원장 · 잠금 ==\n")
MODE <- "400"; SENT <- list(); b0 <- nl()
r2 <- tryCatch(brief("[무인] T2 실패 주입"), error = function(e) list(ok = "THREW", error = conditionMessage(e)))
chk("T2a 예외 아님 · ok=FALSE 반환(호출자 계속)", identical(r2$ok, FALSE), paste(r2$ok))
chk("T2b 원장 1줄", nl() == b0 + 1L, sprintf("%d→%d", b0, nl()))
MODE <- "ok"; SENT <- list(); r2b <- brief("[무인] T2 실패 주입")
chk("T2c 실패 뒤 같은 표제 재발송 허용(잠금 미생성)", isTRUE(r2b$ok) && length(SENT) >= 1L, paste(r2b$error))

cat("== T3 같은 내용 중복 ==\n")
SENT <- list(); r3 <- brief("[무인] T2 실패 주입")
chk("T3a 중복 차단", identical(r3$error, "DUPLICATE_DISPATCH_BLOCKED"), paste(r3$error))
chk("T3b 요청 0", length(SENT) == 0L, sprintf("%d", length(SENT)))

cat("== T4 사진 없음 ==\n")
b0 <- nl(); p4 <- tg_send_photo(file.path(tmp, "nope.png"), caption = "없음")
chk("T4a ok=FALSE · kind=photo_missing", identical(p4$ok, FALSE) && identical(p4$kind, "photo_missing"), paste(p4$kind))
chk("T4b 원장 1줄", nl() == b0 + 1L, "")
SENT <- list(); r4 <- brief("[무인] T4 차트 누락", charts = c("없는 차트" = file.path(tmp, "nope.png")))
chk("T4c tg_agent_brief 결과에 charts_missing", identical(r4$charts_missing, "없는 차트"), paste(r4$charts_missing))

cat("== T5 사진 거부 400 ==\n")
png <- file.path(tmp, "c.png"); writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), png)
MODE <- "photo400"; b0 <- nl(); p5 <- tg_send_photo(png, caption = "거부")
chk("T5a ok=FALSE · kind=photo_http_error · status 400", identical(p5$ok, FALSE) && identical(p5$kind, "photo_http_error") && identical(p5$status, 400L), paste(p5$kind))
chk("T5b 원장 1줄", nl() == b0 + 1L, sprintf("%d→%d", b0, nl()))
MODE <- "ok"

cat("== T6 한글 · 이모지 ==\n")
SENT <- list(); r6 <- brief("[무인] T6 인코딩 \U0001F4CA")
tx <- sent_text()
chk("T6a 한글 원문 보존", grepl("한글과 이모지를 그대로", tx, fixed = TRUE), "")
chk("T6b 이모지 보존(U+1F6A8 · U+1F4CA)", grepl("\U0001F6A8", tx, fixed = TRUE) && grepl("\U0001F4CA", tx, fixed = TRUE), "")
chk("T6c UTF-8 유효", validUTF8(tx), "")

cat("== T7 섹션 규칙 위반 = stop ==\n")
r7 <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = "T7", sections = list(list(type = "text", body = "짧음"))),
               error = function(e) "THREW")
chk("T7 skeleton 은 stop() (호출자 tryCatch 의무 — 사실 고정)", identical(r7, "THREW"), "")

cat("== T8 무음 ==\n")
SENT <- list(); invisible(brief("[무인] T8 무음", mute = TRUE)); b8 <- Filter(function(x) grepl("sendMessage$", x$url), SENT)[[1]]$body
chk("T8a mute=TRUE → disable_notification", isTRUE(b8$disable_notification), "")
SENT <- list(); invisible(brief("[무인] T8 기본")); b8b <- Filter(function(x) grepl("sendMessage$", x$url), SENT)[[1]]$body
chk("T8b 기본 = 키 없음", is.null(b8b$disable_notification), "")

cat("== T9 돌연변이 — 사진 실패 원장 기록 제거 사본 ==\n")
src <- readLines(NOTIFY, encoding = "UTF-8", warn = FALSE)
hit <- grepl('.tg_record_send_failure("photo_http_error"', src, fixed = TRUE)
chk("T9a 치환 대상 1곳 존재", sum(hit) == 1L, sprintf("%d", sum(hit)))
mut <- src; mut[hit] <- "      invisible(NULL)  # MUTANT"
mf <- file.path(tmp, "telegram_notify_mutant.R"); writeLines(mut, mf, useBytes = TRUE)
load_notify(mf); MODE <- "photo400"; b0 <- nl(); invisible(tg_send_photo(png, caption = "거부"))
chk("T9b 돌연변이에서 원장 미기록(= T5b 가 잡는다)", nl() == b0, sprintf("%d→%d", b0, nl()))
load_notify(); MODE <- "ok"

cat("== T10 회귀 반환 계약(정적) ==\n")
chk("T10a tg_regime_briefing 이 sent_ok 반환", any(grepl("sent_ok = sent_ok", src, fixed = TRUE)), "")
mrs <- readLines(file.path(real_root, "02_Infrastructure/ops/morning_steps/mrs_regime_send.R"), encoding = "UTF-8", warn = FALSE)
chk("T10b mrs_regime_send 가 sent_ok 를 읽는다", any(grepl("sent_ok", mrs, fixed = TRUE)), "")
chk("T10c 운영 원장 무접촉(임시 루트)", !grepl(real_root, LEDGER, fixed = TRUE), LEDGER)

setwd(real_root); unlink(tmp, recursive = TRUE)
cat(sprintf('{"test":"scn_tg_emitter","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
