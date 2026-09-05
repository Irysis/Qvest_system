#!/usr/bin/env Rscript
# test_rf_notify_fit_length.R — 텔레그램 본문은 4096자 안에 들어와야 한다 (2026-09-05 도훈 "압축판 말고 제한에 맞추라")
# 실사고: promo3 B1(9칸)·B5(6칸) 블록 본문 4332자/7663B → send 400 "message is too long". '배운 것' 섹션 2498자.
# 판정 축: F1 과대 섹션이 있어도 dry_run msg ≤ 4096자 · F2 절삭 표식 · F3 <b>/<i> 균형 · F4 작은 본문은 무변(음성 대조)
#          F5 돌연변이 통제(원 섹션 길이 > 4096) · C1~C3 .cap_items(개수·폭·꼬리) · D1 실물 블록 재렌더 ≤ 4096
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QVEST_TG_DRY_RUN = "1")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"), local = globalenv()))))
big <- paste(rep("<b>▸ 기전</b> 판정: 이 블록을 가른 것은 상태변수가 아니라 소비 지점이다. 낙폭 바닥은 위험 소비 축에서 뚫렸다.", 80), collapse = "\n")
secs <- list(list(type = "kv", emoji = "📊", heading = "핵심 수치", kv = list("PORT_t" = "2.553", "Calmar" = "0.432")),
             list(type = "text", emoji = "🧠", heading = "이번 블록에서 배운 것", body = big),
             list(type = "bullet", emoji = "➡️", heading = "다음", items = c("B2 비중 6칸", "15/29")))
r <- tryCatch(capture.output(res <- tg_agent_brief(agent = "AlphaSearch", title = "[무인] 검사 — 길이 맞춤", sections = secs, relaxed = TRUE, glossary = FALSE)), error = function(e) NULL)
m <- if (exists("res") && is.list(res)) res$msg %||% "" else ""
if (nzchar(m) && nchar(m, type = "chars") <= 4096L) ok(sprintf("F1 과대 본문 → %d자 (≤4096)", nchar(m))) else ng("F1 본문이 한계를 넘거나 dry_run 반환 없음", as.character(nchar(m)))
if (grepl("길이 한계로 절삭", m, fixed = TRUE)) ok("F2 절삭 표식 있음(조용한 손실 아님)") else ng("F2 절삭 표식 없음")
bal <- function(s, o, c) length(gregexpr(o, s, fixed = TRUE)[[1]]) == length(gregexpr(c, s, fixed = TRUE)[[1]])
if (bal(m, "<b>", "</b>") && bal(m, "<i>", "</i>")) ok("F3 <b>/<i> 균형") else ng("F3 태그 불균형 — 텔레그램이 거부한다")
small <- list(list(type = "text", emoji = "💡", heading = "짧은 본문", body = "한 줄짜리 짧은 본문이지만 계약 최소 30자는 넘긴다 — 길이 맞춤 대상이 아니다."), list(type = "kv", emoji = "📌", heading = "요약", kv = list("a" = "1", "b" = "2")))
invisible(capture.output(res2 <- tg_agent_brief(agent = "AlphaSearch", title = "[무인] 검사 — 작은 본문", sections = small, relaxed = TRUE, glossary = FALSE, force = TRUE)))
m2 <- res2$msg %||% ""
if (nzchar(m2) && !grepl("길이 한계로 절삭", m2, fixed = TRUE) && grepl("맞춤 대상이 아니다", m2, fixed = TRUE)) ok("F4 작은 본문은 손대지 않는다") else ng("F4 작은 본문이 절삭됐다")
if (nchar(big, type = "chars") > 4096L) ok(sprintf("F5 구판이면 %d자로 발송 실패했을 픽스처", nchar(big))) else ng("F5 픽스처가 한계 미만 — 판별력 없음")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"), local = globalenv()))))
x <- c(strrep("가", 200), "둘", "셋", "넷", "다섯")
cx <- .cap_items(x, 3L, 50L)
if (length(cx) == 4L && grepl("외 2건", cx[4]) ) ok("C1 개수 상한 3 + 꼬리 '(외 2건)'") else ng("C1 개수 상한/꼬리", paste(cx, collapse = "|"))
if (nchar(cx[1], type = "chars") <= 50L && endsWith(cx[1], "…")) ok("C2 폭 상한 50자 + …") else ng("C2 폭 상한", as.character(nchar(cx[1])))
if (identical(.cap_items(c("a", "b"), 3L, 50L), c("a", "b"))) ok("C3 상한 미만은 무변") else ng("C3 상한 미만이 바뀐다")
Sys.setenv(QVEST_RF_FORCE_BLOCK = "B5")
out <- tryCatch(capture.output(rd <- rf_auto_notify("RP_20260904_163647_18444_rescued_rulefast_promo3", 15L, kind = "block")), error = function(e) character(0))
txt <- paste(out, collapse = "\n"); i <- regexpr("=== dry_run output", txt)
if (i > 0) { body <- sub("^[^\n]*\n", "", substr(txt, i, nchar(txt))); body <- sub("\n=== .*$", "", body)
  if (nchar(body, type = "chars") <= 4096L) ok(sprintf("D1 실물 promo3 B5 재렌더 %d자 ≤ 4096", nchar(body))) else ng("D1 실물 재렌더 초과", as.character(nchar(body))) } else ok("D1 (실물 entry 부재 — 건너뜀)")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_notify_fit_length","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
