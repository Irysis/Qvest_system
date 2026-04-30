#==============================================================================
# OpenDataLoader PDF parser (Hancom, Apache 2.0) — Korean PDF 우선 도구
# Author: Q-Lead (2026-04-30)
#
# Source: https://github.com/opendataloader-project/opendataloader-pdf
# v2.4.0 Java jar — sudo 불필요, Java 11+ 만 필요.
#
# 강점:
#   - 한글 OCR 정식 지원 (--ocr-lang ko,en)
#   - 표 추출 TEDS 0.928 (open-source 최상위, DART 재무제표 등에 유리)
#   - JSON metadata (bounding box, page number, type)
#   - 로컬 처리 (prohibitions §12 — 데이터 외부 전송 금지 정합)
#
# 단점 / 주의:
#   - 38 page 처리 ~3.6 sec (pdftools 0.26 sec 대비 14× 느림)
#   - 단순 텍스트 추출만 필요하면 pdftools::pdf_text() 가 빠름
#   - 차트 위주 paper 는 false positive table detection 발생 가능
#
# 권장 사용 시점:
#   - 한글 paper / DART 사업보고서 표 정확 추출 필요 시
#   - JSON metadata (구조 + bounding box) 활용 시
#   - 영문 + 단순 텍스트만 필요하면 pdftools 사용
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

ODL_JAR_DEFAULT <- "/tmp/odl/opendataloader-pdf-cli-2.4.0.jar"

odl_check <- function(jar_path = ODL_JAR_DEFAULT) {
  if (!file.exists(jar_path)) {
    stop(sprintf("[odl] jar not found: %s. Download from https://github.com/opendataloader-project/opendataloader-pdf/releases",
                 jar_path))
  }
  java_v <- suppressWarnings(system2("java", "-version", stdout = TRUE, stderr = TRUE))
  if (length(java_v) == 0L) stop("[odl] java not found in PATH")
  invisible(TRUE)
}

# 핵심 함수: PDF parse → list(json/markdown/text/dir)
parse_pdf_hancom <- function(pdf_path,
                              format = c("json", "markdown", "text"),
                              out_dir = NULL,
                              ocr = FALSE,
                              ocr_lang = "ko,en",
                              jar_path = ODL_JAR_DEFAULT,
                              keep_files = TRUE,
                              timeout_sec = 600L) {
  odl_check(jar_path)

  if (!file.exists(pdf_path)) stop(sprintf("[odl] PDF not found: %s", pdf_path))

  if (is.null(out_dir)) {
    out_dir <- tempfile("odl_")
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  } else {
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  }

  fmt_arg <- paste(format, collapse = ",")
  args <- c("-jar", shQuote(jar_path),
            "--format", fmt_arg,
            "-o", shQuote(out_dir),
            if (ocr) c("--force-ocr", "--ocr-lang", ocr_lang),
            shQuote(pdf_path))

  t0 <- Sys.time()
  rc <- system2("java", args, stdout = TRUE, stderr = TRUE, timeout = timeout_sec)
  elapsed_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  base_name <- tools::file_path_sans_ext(basename(pdf_path))
  files <- list(
    json = file.path(out_dir, paste0(base_name, ".json")),
    markdown = file.path(out_dir, paste0(base_name, ".md")),
    text = file.path(out_dir, paste0(base_name, ".txt")),
    images_dir = file.path(out_dir, paste0(base_name, "_images"))
  )

  json_data <- NULL
  if ("json" %in% format && file.exists(files$json)) {
    json_data <- tryCatch(jsonlite::fromJSON(files$json, simplifyVector = FALSE),
                          error = function(e) {
                            warning(sprintf("[odl] JSON parse failed: %s", e$message))
                            NULL
                          })
  }

  text_chr <- NULL
  if ("text" %in% format && file.exists(files$text)) {
    text_chr <- readLines(files$text, warn = FALSE, encoding = "UTF-8")
  }

  result <- list(
    pdf_path = pdf_path,
    out_dir = out_dir,
    files = files,
    elapsed_sec = elapsed_sec,
    json = json_data,
    text = text_chr,
    log = rc
  )

  if (!keep_files) {
    on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  }

  result
}

# 보조: JSON tree 에서 type 별 노드 카운트 (table/paragraph 등)
odl_count_types <- function(json_node, counts = list()) {
  if (is.list(json_node)) {
    if (!is.null(json_node$type)) {
      t <- as.character(json_node$type)
      counts[[t]] <- (counts[[t]] %||% 0L) + 1L
    }
    for (child in json_node) counts <- odl_count_types(child, counts)
  }
  counts
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[pdf_parser_hancom] Loaded. parse_pdf_hancom(pdf_path, format=c('json','markdown','text'), ocr=FALSE)\n")
