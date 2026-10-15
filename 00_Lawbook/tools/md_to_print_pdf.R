## Markdown → 인쇄용 PDF — commonmark(GFM 표)로 HTML 을 만들고 Edge headless 로 인쇄한다.
## 서식 규칙 = 02_Infrastructure/docs/rules/pdf-output-style.md(도훈 2026-10-15): 글꼴 현대하모니 — 본문 L · 소제목 M · 굵은 글씨(제목 · 표 머리 포함) B.
##   글꼴은 설치 파일(사용자 · 시스템 글꼴 폴더의 현대하모니+L/M/B.ttf)을 HTML 에 base64 로 내장한다 — 설치 패밀리 이름이 제각각
##   (HDharmony B · 현대하모니 L · HDharmony M)이라 이름으로 찾지 않는다. 글꼴이 없으면 멈춘다(다른 글꼴로 조용히 대체하지 않는다).
##   코드 · 경로(code · pre)만 고정폭(Consolas — 열 정렬 보존)이고 그 안의 한글은 현대하모니 L 로 떨어진다.
## 실행: Rscript 00_Lawbook/tools/md_to_print_pdf.R <in.md> [out.pdf] [landscape|portrait]
a <- commandArgs(trailingOnly = TRUE)
if (!length(a)) stop("usage: md_to_print_pdf.R <in.md> [out.pdf] [landscape|portrait]")
src <- normalizePath(a[1], winslash = "/")
out <- if (length(a) >= 2L && nzchar(a[2])) a[2] else sub("\\.md$", ".pdf", src)
orient <- if (length(a) >= 3L) a[3] else "landscape"

## ── 글꼴 — 현대하모니 L(본문 300) · M(소제목 500) · B(굵게 700) ──
font_dirs <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
find_font <- function(w) {
  f <- file.path(font_dirs, sprintf("현대하모니+%s.ttf", w)); f <- f[file.exists(f)]
  if (!length(f)) stop(sprintf("[pdf] 현대하모니 %s 글꼴 파일이 없다(%s) — 서식 규칙 글꼴 미설치", w, paste(font_dirs, collapse = " · ")))
  f[1]
}
face <- function(w, weight) sprintf('@font-face { font-family: "HDH"; font-weight: %d; font-style: normal; src: url(data:font/ttf;base64,%s) format("truetype"); }',
                                    weight, jsonlite::base64_enc(readBin(find_font(w), "raw", file.size(find_font(w)))))
fonts_css <- paste(face("L", 300), face("M", 500), face("B", 700), sep = "\n")

md <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
body <- commonmark::markdown_html(md, extensions = TRUE, smart = FALSE)
title <- sub("^#\\s+", "", regmatches(md, regexpr("(?m)^#\\s+[^\n]+", md, perl = TRUE)))
## 쪽 나눔 금지 블록 — 제목(h1~h4)부터 다음 제목 전까지를 한 블록(section.blk · break-inside: avoid)으로 묶는다.
##   제목만 있는 조각(예: h2 바로 뒤 h3)은 다음 블록에 붙인다 — 제목이 쪽 끝에 홀로 남지 않게. 한 쪽보다 긴 블록은 브라우저가
##   어쩔 수 없이 나누므로 문서 쪽에서 표를 쪼갠다 — 생성 뒤 pdf_check.py 가 갈린 표를 잡는다.
.hpos <- as.integer(gregexpr("<h[1-4][ >]", body, perl = TRUE)[[1]])
if (length(.hpos) && .hpos[1] > 0L) {
  .st <- unique(c(1L, .hpos)); .en <- c(.st[-1] - 1L, nchar(body))
  .segs <- substring(body, .st, .en); .out <- character(0); .carry <- ""
  for (.sg in .segs) {
    .rest <- sub("^\\s*<h([1-4])[^>]*>.*?</h\\1>", "", .sg, perl = TRUE)
    if (grepl("^\\s*<h[1-4]", .sg, perl = TRUE) && !nzchar(trimws(.rest))) { .carry <- paste0(.carry, .sg); next }
    .x <- paste0(.carry, .sg); .carry <- ""
    .out <- c(.out, if (grepl("^\\s*<h[1-4]", .x, perl = TRUE)) paste0('<section class="blk">', .x, "</section>") else .x)
  }
  if (nzchar(.carry)) .out <- c(.out, .carry)
  body <- paste(.out, collapse = "")
}
## 검사 기대값 — 표마다 머리 행 문자열(갈린 표는 다음 쪽에 머리 행이 반복된다)
.th <- regmatches(body, gregexpr("(?s)<thead>.*?</thead>", body, perl = TRUE))[[1]]
expect_tables <- vapply(.th, function(x) gsub("<[^>]+>", "", x), character(1), USE.NAMES = FALSE)
css <- sprintf('
%s
@page { size: A4 %s; margin: 11mm 10mm 12mm 10mm; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font-family: "HDH", sans-serif; font-weight: 300; font-size: 8.8pt; line-height: 1.45; color: #111; }
strong, b, th, h1 { font-weight: 700; }
h2, h3, h4 { font-weight: 500; }
h1 { font-size: 15pt; margin: 0 0 4pt 0; border-bottom: 2px solid #222; padding-bottom: 3pt; }
h2 { font-size: 12pt; margin: 12pt 0 4pt 0; border-bottom: 1px solid #888; padding-bottom: 2pt; break-after: avoid; }
h3 { font-size: 10.4pt; margin: 9pt 0 3pt 0; break-after: avoid; }
h4 { font-size: 9.4pt; margin: 7pt 0 2pt 0; break-after: avoid; }
p, li { margin: 2pt 0; }
ul, ol { margin: 2pt 0 2pt 0; padding-left: 16pt; }
section.blk { break-inside: avoid; }
table { border-collapse: collapse; width: 100%%; margin: 4pt 0 6pt 0; table-layout: auto; break-inside: avoid; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th, td { border: 0.6pt solid #9a9a9a; padding: 2.2pt 3.5pt; vertical-align: top; text-align: left; word-break: keep-all; overflow-wrap: anywhere; }
th { background: #e9edf2; }
td:first-child { white-space: nowrap; }
td:first-child code { white-space: nowrap; }
td:nth-child(2) { min-width: 4.8em; }
tr:nth-child(even) td { background: #f8f9fb; }
code { font-family: "Consolas", "HDH"; font-weight: 400; font-size: 0.92em; background: #f1f1f1; padding: 0 2px; border-radius: 2px; }
pre { background: #f6f6f6; border: 0.6pt solid #ccc; padding: 5pt 7pt; font-size: 7.6pt; line-height: 1.32; white-space: pre-wrap; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 1em; }
strong code, th code { font-weight: 700; }
blockquote { margin: 3pt 0; padding: 2pt 8pt; border-left: 3px solid #bbb; color: #333; }
hr { border: 0; border-top: 0.6pt solid #bbb; margin: 8pt 0; }
', fonts_css, orient)
html <- sprintf('<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>%s</body></html>',
                title, css, body)
tmp_html <- file.path(tempdir(), "md_print.html"); writeLines(html, tmp_html, useBytes = TRUE)
edge <- c("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
          "C:/Program Files/Google/Chrome/Application/chrome.exe")
edge <- edge[file.exists(edge)][1]
if (is.na(edge)) stop("Edge/Chrome 없음")
out_abs <- normalizePath(out, winslash = "\\", mustWork = FALSE)
url <- paste0("file:///", normalizePath(tmp_html, winslash = "/"))
prof <- file.path(tempdir(), "edge_print_profile")
rc <- system2(edge, c("--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--no-first-run", "--disable-extensions",
                      "--virtual-time-budget=5000",
                      paste0("--user-data-dir=", shQuote(normalizePath(prof, winslash = "\\", mustWork = FALSE))),
                      paste0("--print-to-pdf=", shQuote(out_abs)), url), stdout = TRUE, stderr = TRUE)
if (!file.exists(out)) { cat(rc, sep = "\n"); stop("PDF 생성 실패") }
cat(sprintf("[pdf] %s · %.0f KB\n", out, file.size(out) / 1024))
## 생성 뒤 검사(서식 규칙) — 갈린 표 · 대체 글꼴. QVEST_PY(PyMuPDF) 가 없으면 건너뛴다고 적는다.
py <- Sys.getenv("QVEST_PY")
if (nzchar(py) && file.exists(py)) {
  ej <- file.path(tempdir(), "pdf_expect.json")
  writeLines(jsonlite::toJSON(list(tables = expect_tables, fonts_allowed = c("Consolas", "HDH")), auto_unbox = TRUE), ej, useBytes = TRUE)
  chk_py <- file.path(dirname(normalizePath(sub("--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/")), "pdf_check.py")
  res <- suppressWarnings(system2(py, c(shQuote(chk_py), shQuote(normalizePath(out, winslash = "/")), shQuote(ej)), stdout = TRUE, stderr = TRUE))
  cat("[pdf-check]", tail(res, 1), "\n")
  if (!is.null(attr(res, "status")) && attr(res, "status") != 0L) stop("[pdf-check] 실패 — 갈린 표 또는 대체 글꼴(위 JSON). md 에서 표를 쪼개거나 글꼴을 확인할 것")
} else cat("[pdf-check] 건너뜀 — QVEST_PY 없음(갈린 표 · 글꼴 검사 미실행)\n")
