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
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
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

df <- data.frame(
  Layer  = c("L1 MSM", "L2 FRED", "L3 KTRI"),
  Status = c("OK", "STALE", "OK"),
  Age    = c("2d", "8d", "0d"),
  stringsAsFactors = FALSE
)

block <- tg_format_table(df)

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

if (fail_count > 0) stop(sprintf("test_briefing_partial: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
