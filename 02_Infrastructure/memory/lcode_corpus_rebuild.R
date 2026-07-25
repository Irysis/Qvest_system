# lcode_corpus_rebuild.R — v7.2.1 Sprint 4
#
# 4 source 통합:
#   - qepm/memory/methodology_memory.md
#   - qepm/memory/methodology_memory_v55_extensions.md
#   - external /home/quant/.claude/.../memory/methodology_active.md
#   - external /home/quant/.claude/.../memory/methodology_archive.md
#   - 00_Lawbook/**/*.md
#
# 출력: .cache/lcode_corpus.json
# Schema (lcodes list-of-objects 유지 — promote.R:44 + review.R:43 호환):
#   {
#     "schema_version": "v7.2.1_lcode_corpus",
#     "ran_at": "...",
#     "lcodes": [{"l_code": "L-130", ...}, ...],   # list, NOT map
#     "source_map": {"L-130": ["..."], ...},        # 별도 field
#     "summary": {...}
#   }

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# v8.0 Windows-native: 죽은 WSL 경로(/home/quant/...) 제거. 환경변수 우선 + Windows 메모리 dir fallback.
# (methodology_active/archive.md가 해당 경로에 없으면 extract_lcodes_from_file이 MISSING 처리 — line 143-146.)
EXTERNAL_BASE <- Sys.getenv("QVEST_MEMORY_DIR",
                            "C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory")

SOURCE_FILES <- c(
  file.path(PROJ_ROOT, "qepm/memory/methodology_memory.md"),
  file.path(PROJ_ROOT, "qepm/memory/methodology_memory_v55_extensions.md"),
  file.path(EXTERNAL_BASE, "methodology_active.md"),
  file.path(EXTERNAL_BASE, "methodology_archive.md")
)

# Lawbook md 추가
LAWBOOK_DIR <- file.path(PROJ_ROOT, "00_Lawbook")

# ─── L-code 추출 ──────────────────────────────────────────────────

extract_lcodes_from_file <- function(path) {
  if (!file.exists(path)) {
    # 2026-07-25: 조용한 빈 반환 금지 — 부재 소스가 "0건 추출"과 구분되지 않아
    # 선언 소스 4개 중 3개가 사라진 채로 코퍼스가 정상 재구축된 것처럼 보였다.
    warning(sprintf("[lcode_corpus_rebuild] 소스 부재 — 추출 생략: %s", path),
            call. = FALSE)
    return(list())
  }
  lines <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character()
  )
  if (length(lines) == 0L) return(list())

  # ^L-NNN 또는 ## L-NNN 또는 ### L-NNN 헤더 탐지
  header_pat <- "^#{0,4}\\s*L-([0-9]{3})\\b"
  header_idx <- grep(header_pat, lines, perl = TRUE)

  result <- list()
  if (length(header_idx) == 0L) {
    # body 내 인용만 — fallback: 정규식 unique L-NNN
    matches <- regmatches(
      paste(lines, collapse = "\n"),
      gregexpr("L-[0-9]{3}", paste(lines, collapse = "\n"))
    )[[1]]
    for (lc in unique(matches)) {
      result[[lc]] <- list(
        l_code = lc,
        title = sprintf("(referenced only) %s in %s", lc, basename(path)),
        body = "",
        source = path,
        is_reference_only = TRUE
      )
    }
    return(result)
  }

  for (i in seq_along(header_idx)) {
    start <- header_idx[i]
    end <- if (i < length(header_idx)) header_idx[i + 1] - 1 else length(lines)
    block <- lines[start:min(end, start + 50)]  # cap body 50 lines
    title <- trimws(gsub("^#+\\s*", "", lines[start]))
    body <- paste(block, collapse = "\n")
    m <- regmatches(title, regexec("L-([0-9]{3})", title))
    if (length(m[[1]]) >= 2) {
      lc <- paste0("L-", m[[1]][2])
      # extract grade tag (Grade A/B/C/F)
      grade <- ""
      if (grepl("Grade A_NOVEL", body)) grade <- "A_NOVEL"
      else if (grepl("Grade A\\b", body)) grade <- "A"
      else if (grepl("Grade B\\b", body)) grade <- "B"
      else if (grepl("Grade C\\b", body)) grade <- "C"
      else if (grepl("Grade F\\b", body)) grade <- "F"

      # extract family
      family <- ""
      fam_m <- regmatches(body,
                          regexec("family[=:]\\s*([a-z_]+)",
                                  body, ignore.case = TRUE))
      if (length(fam_m[[1]]) >= 2) family <- fam_m[[1]][2]

      # extract strategy_id (STR_NNNN)
      str_m <- regmatches(body,
                          regexec("STR_[0-9]{3,5}[A-Za-z_]*", body))
      strategy_id <- if (length(str_m[[1]]) >= 1) str_m[[1]][1] else ""

      result[[lc]] <- list(
        l_code = lc,
        title = substr(title, 1, 200),
        body = substr(body, 1, 2000),
        source = path,
        family = family,
        grade = grade,
        strategy_id = strategy_id,
        is_reference_only = FALSE
      )
    }
  }
  result
}

cat("=== lcode_corpus_rebuild.R v7.2.1 Sprint 4 ===\n")
cat(sprintf("PROJ_ROOT: %s\n\n", PROJ_ROOT))

all_sources <- SOURCE_FILES

# Lawbook md 추가
if (dir.exists(LAWBOOK_DIR)) {
  lb_files <- list.files(LAWBOOK_DIR, pattern = "\\.md$",
                         full.names = TRUE, recursive = TRUE)
  all_sources <- c(all_sources, lb_files)
}

cat(sprintf("Source files: %d\n", length(all_sources)))

# ── 명시 결손 승격 (2026-07-25 도훈 승인) ──────────────────────────────────
# 종전: 선언 소스가 없어도 조용히 건너뛰어, 4개 중 3개 부재 상태에서도 재구축이
# "성공"으로 보였다. sg_sync_methodology_memory 와 동일 부류 결함이라 동일하게 수리한다.
# 판정 자체는 불차단(AX-000/INV-7 정합) — 표면화 + 결손 원장까지만.
.report_missing_sources <- function(missing_declared) {
  if (length(missing_declared) == 0) return(invisible(NULL))
  msg <- sprintf(
    "[lcode_corpus_rebuild] 선언 소스 %d/%d 부재 — 코퍼스가 부분 소스로 재구축됨: %s",
    length(missing_declared), length(SOURCE_FILES),
    paste(basename(missing_declared), collapse = ", "))
  cat(msg, "\n")
  warning(msg, call. = FALSE)
  tryCatch({
    dir.create(file.path(PROJ_ROOT, ".cache"), recursive = TRUE, showWarnings = FALSE)
    writeLines(jsonlite::toJSON(list(
      detected_at       = as.character(Sys.time()),
      defect            = "declared_source_absent",
      declared_sources  = SOURCE_FILES,
      missing           = missing_declared,
      surviving         = setdiff(SOURCE_FILES, missing_declared)
    ), auto_unbox = TRUE, pretty = TRUE),
    file.path(PROJ_ROOT, ".cache", "lcode_rebuild_defect.json"))
  }, error = function(e) invisible(NULL))
}

# ─── Merge ─────────────────────────────────────────────────────

merged <- list()  # named list keyed by l_code
source_map <- list()
source_counts <- list()

missing_declared <- character(0)   # 선언 소스(SOURCE_FILES) 중 부재분 — 명시 결손 대상

for (src in all_sources) {
  if (!file.exists(src)) {
    cat(sprintf("  MISSING: %s\n", src))
    if (src %in% SOURCE_FILES) missing_declared <- c(missing_declared, src)
    next
  }
  rel_src <- if (startsWith(src, PROJ_ROOT)) {
    sub(paste0(PROJ_ROOT, "/?"), "", src)
  } else {
    src
  }
  extracted <- extract_lcodes_from_file(src)
  source_counts[[rel_src]] <- length(extracted)

  for (lc in names(extracted)) {
    item <- extracted[[lc]]
    item$source <- rel_src
    if (is.null(merged[[lc]])) {
      # first occurrence wins (real header > reference_only)
      merged[[lc]] <- item
    } else if (isTRUE(merged[[lc]]$is_reference_only) &&
               !isTRUE(item$is_reference_only)) {
      # upgrade: reference-only → real definition
      merged[[lc]] <- item
    }
    if (is.null(source_map[[lc]])) source_map[[lc]] <- character(0)
    source_map[[lc]] <- unique(c(source_map[[lc]], rel_src))
  }
}

.report_missing_sources(missing_declared)

# ─── Convert merged map → list-of-objects (CRITICAL: promote.R 호환) ───

lcodes_list <- list()
for (lc in names(merged)) {
  item <- merged[[lc]]
  item$sources <- source_map[[lc]]
  item$primary_source <- item$source
  item$source <- NULL
  lcodes_list[[length(lcodes_list) + 1]] <- item
}

# Sort by L-code numeric
lcode_order <- order(vapply(lcodes_list, function(x) {
  as.integer(sub("^L-", "", x$l_code))
}, integer(1)))
lcodes_list <- lcodes_list[lcode_order]

# ─── Summary ───────────────────────────────────────────────────

all_codes <- vapply(lcodes_list, function(x) x$l_code, character(1))
nums <- as.integer(sub("^L-", "", all_codes))
max_id <- if (length(nums) > 0) sprintf("L-%03d", max(nums)) else "L-000"

# outliers — gap > 50 between consecutive
sorted_nums <- sort(nums)
gaps <- diff(sorted_nums)
outliers <- character()
if (any(gaps > 50)) {
  for (i in which(gaps > 50)) {
    outliers <- c(outliers, sprintf("L-%03d", sorted_nums[i + 1]))
  }
}

# lawbook-only (only source from 00_Lawbook)
lawbook_only <- character()
for (item in lcodes_list) {
  srcs <- item$sources %||% character(0)
  if (all(grepl("^00_Lawbook", srcs))) {
    lawbook_only <- c(lawbook_only, item$l_code)
  }
}

corpus <- list(
  schema_version = "v7.2.1_lcode_corpus",
  ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  lcodes = lcodes_list,
  source_map = source_map,
  summary = list(
    total = length(lcodes_list),
    max_id = max_id,
    outliers = outliers,
    lawbook_only = lawbook_only,
    source_counts = source_counts
  )
)

# Write
# v8.0: 출력 경로 분리. lcode_harvester.py(v53_ax_p0, lcodes+grade/strategy_id)가
# `.cache/lcode_corpus.json` canonical 단독 소유 — promote.R/review.R가 grade/strategy_id를
# 요구하므로 그 스키마가 권위. 본 rebuild(v7.2.1_lcode_corpus, methodology 4-source +
# summary.outliers)는 별도 파일로 써서 clobber race 제거(과거: 둘이 같은 파일 경합 → harvester
# 가 이겨 rebuild 출력 매 부팅 파괴). memory_knowledge_health.R의 outlier 체크가 본 파일을 읽음.
out_path <- file.path(PROJ_ROOT, ".cache", "lcode_corpus_methodology.json")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
write_json(corpus, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("\n[OK] lcode_corpus_methodology.json written: %s\n", out_path))
cat(sprintf("  total: %d unique L-codes\n", length(lcodes_list)))
cat(sprintf("  max_id: %s\n", max_id))
cat(sprintf("  outliers (gap>50): %d\n", length(outliers)))
cat(sprintf("  lawbook_only: %d\n", length(lawbook_only)))
cat("\nSource counts:\n")
for (s in names(source_counts)) {
  cat(sprintf("  %s: %d\n", basename(s), source_counts[[s]]))
}

# Compatibility selftest
cat("\n=== Compatibility selftest (promote.R:44 + review.R:43 호환) ===\n")
test_corpus <- jsonlite::fromJSON(out_path, simplifyVector = FALSE)
stopifnot(is.list(test_corpus$lcodes))
stopifnot(length(test_corpus$lcodes) > 0)
first <- test_corpus$lcodes[[1]]
stopifnot(!is.null(first$l_code))
stopifnot(grepl("^L-[0-9]{3}", first$l_code))
cat(sprintf("  PASS — lcodes is list-of-objects, first$l_code=%s\n",
            first$l_code))

# promote.R style access pattern
idx <- which(vapply(test_corpus$lcodes,
                    function(x) x$l_code == first$l_code, logical(1)))
stopifnot(length(idx) >= 1)
cat(sprintf("  PASS — promote.R style which() access works (idx=%d)\n",
            idx[1]))
