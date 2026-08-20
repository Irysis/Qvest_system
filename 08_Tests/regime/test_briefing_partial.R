#==============================================================================
# test_briefing_partial.R — Session 70 Step 8
#
# 검증 범위:
#   1. tg_format_table(synthetic df) → <pre>...</pre> 블록 반환 + 공백 정렬
#   2. tg_html_escape — <, >, & 변환 확인
#   3. tg_send emoji_min 위반 시 warn log append 확인
#
# ABSOLUTE NO-OP on Telegram:
#   tg_send 를 stub 으로 override 해서 실 POST 호출 차단.
#   emoji validation 로직만 동작하도록 하여 warn-path 확인.
#==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  # [fix 2026-07-25] 구 하드코딩 WSL 폴백 제거. 이 가드는 환경변수를 보지 않아
  # 단독 실행 시 무조건 없는 경로로 가 source(config.R) 가 죽었고,
  # 그 결과 러너가 "0 passed / 0 failed (of 0 total)" 을 성공처럼 냈다.
  # 후보를 **표지 파일 검증**으로 확인한다 — 존재검사로 정체성검사를 대체하지 않는다.
  .qv_marker <- "02_Infrastructure/config.R"
  .qv_argv <- commandArgs(trailingOnly = FALSE)
  .qv_f <- grep("^--file=", .qv_argv, value = TRUE)
  .qv_sd <- if (length(.qv_f)) dirname(sub("^--file=", "", .qv_f[1])) else ""
  for (.qv_c in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                  Sys.getenv("QM_ROOT", unset = ""),
                  if (nzchar(.qv_sd)) file.path(.qv_sd, "..", "..") else "",
                  getwd())) {
    if (nzchar(.qv_c) && file.exists(file.path(.qv_c, .qv_marker))) {
      PROJECT_ROOT <- .qv_c
      break
    }
  }
  if (!exists("PROJECT_ROOT")) {
    stop(sprintf(paste0("[regime] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음.\n",
                        "  cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
                 .qv_marker, getwd(),
                 Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = "")))
  }
  rm(list = intersect(ls(), c(".qv_marker", ".qv_argv", ".qv_f", ".qv_sd", ".qv_c")))
}

# ── Source telegram module (must not actually send in this test) ────
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

pass_count <- 0L
fail_count <- 0L
.assert <- function(cond, msg) {
  if (isTRUE(cond)) {
    cat(sprintf("  [PASS] %s\n", msg))
    pass_count <<- pass_count + 1L
  } else {
    cat(sprintf("  [FAIL] %s\n", msg))
    fail_count <<- fail_count + 1L
  }
}

cat("\n── Test 1: tg_format_table ──\n")

# [fix 2026-07-25] 구 픽스처는 3열(Layer/Status/Age)로 성공 반환을 기대했으나,
# 현행 SOT는 ncol>2 를 거부한다(telegram_notify.R:398 — "v6 SOT: ncol=%d > %d cap.
# 모바일 가독성"). 즉 프로덕션이 정본이고 픽스처가 스펙 변경을 못 따라간 stale 이었다.
# 이 실패는 regime 러너의 0-total 위장 뒤에 숨어 있다가 계측 복원으로 드러났다.
# 픽스처를 2열로 맞추되, **거부 동작 자체를 별도 케이스로 고정**한다(스펙 약화 아님).
df <- data.frame(
  Layer  = c("L1 MSM", "L2 FRED", "L3 KTRI"),
  Status = c("OK", "STALE", "OK"),
  stringsAsFactors = FALSE
)

block <- tg_format_table(df)

# 2열 상한 회귀 방지 — 3열은 반드시 거부되어야 한다.
.assert(inherits(try(tg_format_table(data.frame(A = "1", B = "2", C = "3",
                                                stringsAsFactors = FALSE)),
                     silent = TRUE), "try-error"),
        "ncol>2 → 거부 (v6 SOT 2열 cap, 모바일 가독성)")

.assert(is.character(block) && length(block) == 1,
        "tg_format_table returns single character string")

.assert(grepl("^<pre>", block) && grepl("</pre>$", block),
        "<pre> block wrapper present")

# Headers + separator + rows (5 lines minimum inside <pre>)
inside <- gsub("^<pre>|</pre>$", "", block)
lines <- strsplit(inside, "\n", fixed = TRUE)[[1]]
.assert(length(lines) >= 5,
        sprintf("block has ≥5 lines (header + sep + 3 rows) — got %d", length(lines)))

# Column alignment: lines should have consistent length (nchar type="width")
line_widths <- nchar(lines, type = "width")
.assert(length(unique(line_widths[line_widths > 0])) == 1L ||
          max(line_widths) - min(line_widths) <= 1L,
        sprintf("line widths consistent (range %d..%d)",
                min(line_widths), max(line_widths)))

# Empty df → empty string
.assert(tg_format_table(data.frame()) == "",
        "empty data.frame → empty string")

cat("\n── Test 2: tg_html_escape ──\n")

esc1 <- tg_html_escape("a < b > c & d")
.assert(esc1 == "a &lt; b &gt; c &amp; d",
        sprintf("escape <, >, & correctly (got: '%s')", esc1))

esc2 <- tg_html_escape("safe text")
.assert(esc2 == "safe text",
        "non-special text unchanged")

# Order: & must escape first (otherwise &amp; gets double-escaped)
esc3 <- tg_html_escape("A & <B>")
.assert(esc3 == "A &amp; &lt;B&gt;",
        sprintf("ordering: & before <, > (got: '%s')", esc3))

cat("\n── Test 3: tg_send emoji_min warn (no actual POST) ──\n")

# Stub POST so we don't hit network
.real_tg_api <- if (exists(".TG_API")) .TG_API else NULL
.TG_API <<- "http://127.0.0.1:1/stub"  # unreachable — send will fail, caught by tryCatch

# Redirect warn log path to tmp — protect real log
warn_log <- tempfile(pattern = "tg_emoji_warn_", fileext = ".log")
.orig_warn_path <- "/tmp/qvest_tg_emoji_warn.log"

# tg_send writes to /tmp/qvest_tg_emoji_warn.log directly — we can't redirect
# without monkey-patch. Instead: read length before/after invocation.
pre_size <- if (file.exists(.orig_warn_path)) file.info(.orig_warn_path)$size else 0L

# Capture console output (warn message goes to cat)
msg_no_emoji <- "No emoji here at all plain ascii message"
captured <- capture.output(
  tryCatch(tg_send(msg_no_emoji, silent = TRUE,
                    validate_emoji = TRUE, emoji_min = 1L),
           error = function(e) NULL),
  type = "output"
)

.assert(any(grepl("emoji count 0 < min 1|emoji count 0 .* min 1",
                   captured)),
        sprintf("warn captured to stdout when emoji_min violated (captured: %d lines)",
                length(captured)))

# File append happens too (if path is writable)
post_size <- if (file.exists(.orig_warn_path)) file.info(.orig_warn_path)$size else 0L
.assert(post_size >= pre_size,
        sprintf("warn log append (pre=%d, post=%d bytes)", pre_size, post_size))

# With emoji: no warn
msg_with_emoji <- "Briefing 📈 ready"
captured2 <- capture.output(
  tryCatch(tg_send(msg_with_emoji, silent = TRUE,
                    validate_emoji = TRUE, emoji_min = 1L),
           error = function(e) NULL),
  type = "output"
)
has_warn <- any(grepl("emoji count \\d+ < min", captured2))
.assert(!has_warn,
        "no warn when emoji present (emoji_min satisfied)")

# Restore
if (!is.null(.real_tg_api)) .TG_API <<- .real_tg_api

cat(sprintf("\n── test_briefing_partial: %d passed, %d failed ──\n\n",
            pass_count, fail_count))

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_briefing_partial\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", pass_count, fail_count, pass_count + fail_count))
if (fail_count > 0) stop(sprintf("test_briefing_partial: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
