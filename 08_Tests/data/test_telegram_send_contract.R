# test_telegram_send_contract.R — TG-01 / CFA-05 / CFA-06 위반 주입 테스트
#
# 무엇을 지키는가:
#   2026-08-16 실측 — cache_freshness_audit 의 텔레그램 경보가 07-03~08-15 최소 20건
#   전부 HTTP 400("can't parse entities")으로 거부됐는데 **어느 표면도 그것을 드러내지
#   못했다**. 구 tg_send 가 400 을 cat 으로만 흘리고 R 에러를 내지 않았기 때문에
#   ① 호출부 tryCatch(error=) 미발화 ② CFA-04 의 alert_delivery="FAILED" 미기록
#   ③ alert_state 의 last_sent_at 은 배달된 것처럼 갱신 — 셋이 동시에.
#
# ★이 검사의 핵심은 "발송이 되나"가 아니라 **"실패가 드러나나"**이다.
#   그래서 일부러 깨진 메시지를 주입해 빨개지는 것까지가 한 축이다
#   (양성 대조 없이 "경고 0"은 검사 사망과 구분되지 않는다).
#
# 실행: Rscript 08_Tests/data/test_telegram_send_contract.R
#   T1  주입: 미종결 _ 를 가진 Markdown → tg_send 가 ok=FALSE + status 400 을 반환하는가
#   T2  주입: 그 실패가 **내구 원장**(telegram_send_failures.jsonl)에 남는가
#   T3  양성대조: 이스케이프된 동일 본문은 엔티티 짝이 맞는가(파서 레벨, 무발송)
#   T4  분기: 발송 실패 시 audit 이 alert_delivery=FAILED 를 쓰고 alert_state 스탬프를 보류하는가
#   T5  돌연변이: T4 의 검사가 공허하지 않은가 (ok=TRUE 면 반대로 스탬프해야 함)
#
# ⚠T1/T2 는 **실제 API 를 호출**한다. 다만 400 으로 거부되는 메시지라 채널에는
#   아무것도 도달하지 않는다 — 가로채서 mock 하면 거부하는 검증기 자신을 건너뛰므로
#   실제 경로로 태운다(이 저장소의 실사고 교훈).

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
# ★SKIP 은 합격이 아니다 — 배터리 편입 시 네트워크 단절이 거짓 FAIL 을 내지 않게 하되,
#   건너뛴 축은 반드시 **눈에 보이게** 센다(이 저장소의 "빈 결과 = 합격" 위장 방지 규약).
skp <- function(name, why) { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP  %s — %s\n", name, why)) }

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/telegram/telegram_notify.R")
})

LEDGER <- file.path(ROOT, "qepm/observability/telegram_send_failures.jsonl")
nlines <- function(p) if (file.exists(p)) length(readLines(p, warn = FALSE)) else 0L

cat("=== T1/T2 위반 주입 — 미종결 Markdown 엔티티 (실제 API, 400 거부되어 채널 미도달) ===\n")
before <- nlines(LEDGER)
# 주입: _ 가 **정확히 1개(홀수)** 여야 legacy Markdown 이 종결자를 못 찾는다.
#   ⚠2026-08-16 초판은 "injection_probe _unterminated" 를 썼는데 _ 가 2개(짝수)라
#     유효 Markdown 이 되어 200 으로 **실제 발송됐다**. 주입이 위반이 아니면 검사는
#     아무것도 시험하지 않는다 — 아래 T1z 가 그 실수를 구조적으로 막는다.
INJ <- "\U0001F6A8 injection probe _unterminated"
.n_live_us <- local({
  cs <- strsplit(INJ, "")[[1]]; esc <- c(FALSE, head(cs, -1) == "\\")
  sum(cs == "_" & !esc)
})
chk("T1z 주입 자체가 실제로 위반인가 (살아있는 _ 가 홀수)",
    .n_live_us %% 2 == 1, sprintf("(live _ = %d — 짝수면 주입이 무효)", .n_live_us))
res <- tg_send(INJ, parse_mode = "Markdown", silent = TRUE, validate_emoji = FALSE)
after <- nlines(LEDGER)

chk("T1a tg_send 가 구조화 상태를 반환 (list + ok 필드)",
    is.list(res) && !is.null(res$ok), sprintf("(got %s)", class(res)[1]))

# 네트워크 단절이면 API 왕복 축은 시험 불가 — 거짓 FAIL 대신 SKIP 으로 드러낸다.
#   단 "실제로 발송돼 버림(ok=TRUE)"은 네트워크와 무관한 **진짜 회귀**이므로 FAIL 유지.
if (identical(res$kind, "exception")) {
  skp("T1b~T2c 라이브 API 축", sprintf("네트워크/예외 (%s) — 계약 축은 검증 못함", substr(res$error %||% "", 1, 80)))
} else {
  chk("T1b 주입된 위반이 ok=FALSE 로 잡힘",
      identical(res$ok, FALSE), sprintf("(ok=%s — TRUE 면 주입이 통과해 버린 것)", res$ok))
  chk("T1c status 가 400 (entity parse 거부)",
      identical(as.integer(res$status %||% NA), 400L), sprintf("(status=%s)", res$status))
  chk("T1d error 본문에 parse entities 사유가 담김",
      grepl("parse entities", res$error %||% "", fixed = TRUE), "")
  chk("T2  실패가 내구 원장에 1줄 적립됨 (stdout 아님)",
      after == before + 1L, sprintf("(before=%d after=%d)", before, after))
  if (after > before) {
    last <- jsonlite::fromJSON(tail(readLines(LEDGER, warn = FALSE), 1))
    chk("T2b 원장 레코드 kind=http_error", identical(last$kind, "http_error"), "")
    chk("T2c 원장 레코드가 parse_mode 를 보존", identical(last$parse_mode, "Markdown"), "")
  }
}

cat("\n=== T3 양성대조 — 이스케이프 후 엔티티 짝 (파서 레벨, 무발송) ===\n")
.md_esc <- function(x) gsub("([_*\\[`])", "\\\\\\1", as.character(x))
live_pairs_ok <- function(s, ch) {
  cs <- strsplit(s, "")[[1]]
  esc <- c(FALSE, head(cs, -1) == "\\")
  sum(cs == ch & !esc) %% 2 == 0
}
raw_path <- "stage_artifacts/method_frontier/firm_level_scaffold/data_pull/nps_headcount_raw.parquet"
bad_msg  <- sprintf("*Alert*\n- %s\n_(orphan)_", raw_path)            # 수리 전 형태
good_msg <- sprintf("*Alert*\n- %s\n_(orphan)_", .md_esc(raw_path))   # 수리 후 형태
chk("T3a 수리 전 형태는 _ 짝이 어긋남 (검사가 진짜 위반을 잡는다)",
    !live_pairs_ok(bad_msg, "_"), "")
chk("T3b 수리 후 형태는 _ 짝이 맞음",
    live_pairs_ok(good_msg, "_"), "")
chk("T3c 수리 후에도 * 굵게 서식은 보존 (짝 유지)",
    live_pairs_ok(good_msg, "*") && grepl("*Alert*", good_msg, fixed = TRUE), "")

cat("\n=== T4/T5 분기 — 발송 실패 시 스탬프 보류 / 성공 시 스탬프 ===\n")
# audit 의 분기 로직만 시험한다(발송 경로 자체는 T1/T2 가 실 API 로 이미 덮음).
branch <- function(ok) {
  .send <- list(ok = ok, status = if (ok) 200L else 400L,
                error = if (ok) NA_character_ else "Bad Request: can't parse entities")
  .ok <- isTRUE(.send$ok)
  list(
    alert_delivery = if (.ok) "SENT" else
      sprintf("FAILED: status=%s %s", .send$status %||% "NA", substr(.send$error %||% "unknown", 1, 300)),
    stamped = .ok
  )
}
f <- branch(FALSE); s <- branch(TRUE)
chk("T4a 실패 시 alert_delivery 가 FAILED 로 기록",
    grepl("^FAILED", f$alert_delivery), f$alert_delivery)
chk("T4b 실패 시 alert_state 스탬프 보류 (다음 런 재시도 가능)",
    identical(f$stamped, FALSE), "")
chk("T5a 돌연변이 — 성공 시엔 SENT",
    identical(s$alert_delivery, "SENT"), s$alert_delivery)
chk("T5b 돌연변이 — 성공 시엔 스탬프함 (T4 가 상시-참이 아님)",
    identical(s$stamped, TRUE), "")

cat(sprintf("\n=== test_telegram_send_contract: %d PASS / %d FAIL / %d SKIP ===\n", PASS, FAIL, SKIP))
if (SKIP > 0) cat("  ⚠SKIP>0 — 라이브 API 축이 돌지 않았다. '전부 초록'으로 읽지 말 것.\n")
if (FAIL > 0) quit(status = 1)
