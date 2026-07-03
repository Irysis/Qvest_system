#!/usr/bin/env Rscript
# Daily first-run paper recharge for alpha-search literature pool.

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.na(a)) return(b)
  a
}

args <- commandArgs(trailingOnly = TRUE)
arg_has <- function(flag) flag %in% args
arg_val <- function(prefix, default = "") {
  hit <- args[startsWith(args, paste0(prefix, "="))]
  if (length(hit)) sub(paste0("^", prefix, "="), "", hit[[1]]) else default
}

force <- arg_has("--force") || Sys.getenv("QVEST_PAPER_RECHARGE_FORCE", "0") %in% c("1", "true", "TRUE", "yes")
dry_run <- arg_has("--dry-run") || Sys.getenv("QVEST_PAPER_RECHARGE_DRY_RUN", "0") %in% c("1", "true", "TRUE", "yes")
no_tg <- arg_has("--no-telegram") || Sys.getenv("QVEST_PAPER_RECHARGE_NO_TG", "0") %in% c("1", "true", "TRUE", "yes")
max_new <- suppressWarnings(as.integer(Sys.getenv("QVEST_PAPER_RECHARGE_MAX_NEW", arg_val("--max-new", "0"))))
if (!is.finite(max_new)) max_new <- 0L

source("02_Infrastructure/config.R")
if (!dir.exists(PROJECT_ROOT)) stop("PROJECT_ROOT not found")
setwd(PROJECT_ROOT)
source(file.path(PROJECT_ROOT, "02_Infrastructure", "tools", "paper_summary_ko.R"))

today <- format(Sys.Date(), "%Y%m%d")
run_root <- file.path(PROJECT_ROOT, "01_Literature", "Alpha_Search_Recharge", today)
stage_root <- file.path(PROJECT_ROOT, "stage_artifacts", "paper_recharge")
stamp <- file.path(stage_root, sprintf("paper_recharge_%s.done", today))
log_path <- file.path(stage_root, sprintf("paper_recharge_%s.log", today))
dir.create(run_root, recursive = TRUE, showWarnings = FALSE)
dir.create(stage_root, recursive = TRUE, showWarnings = FALSE)

log_line <- function(...) {
  msg <- paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), " ", sprintf(...))
  cat(msg, "\n", sep = "")
  cat(msg, "\n", file = log_path, append = TRUE, sep = "")
}

if (file.exists(stamp) && !force) {
  log_line("[paper-recharge] already ran today: %s", stamp)
  quit(status = 0)
}

lock_dir <- file.path(stage_root, "daily.lock")
if (!dir.create(lock_dir, showWarnings = FALSE) && !force) {
  info <- suppressWarnings(file.info(lock_dir))
  age <- if (nrow(info) == 1L) as.numeric(difftime(Sys.time(), info$mtime, units = "secs")) else Inf
  if (is.finite(age) && age < 3600) {
    log_line("[paper-recharge] another run is active (age %.0fs)", age)
    quit(status = 0)
  }
  unlink(lock_dir, recursive = TRUE, force = TRUE)
  dir.create(lock_dir, showWarnings = FALSE)
}
on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

read_sources <- function(path) {
  if (!file.exists(path)) return(data.frame())
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")
}

load_registry <- function() {
  reg_path <- file.path(PROJECT_ROOT, "06_Registry", "paper_registry.json")
  registry <- if (file.exists(reg_path)) {
    fromJSON(reg_path, simplifyDataFrame = TRUE)
  } else {
    data.frame()
  }
  if (!is.data.frame(registry)) registry <- data.frame()
  registry
}

# ─── 영구 실패 다운로드 skip-list (2026-06-18 Q) ─────────────────────────────
# 죽은/철회된 arXiv ID(404/410)나 반복 실패 URL이 다운로드 실패 → 미등록 → 다음날
# "신규 후보"로 재등장 → 또 실패 하는 영구 실패 루프를 차단. 성공 시 자동 해제.
skip_path <- file.path(stage_root, "failed_skip.json")
MAX_FAIL <- suppressWarnings(as.integer(Sys.getenv("QVEST_PAPER_RECHARGE_MAX_FAIL", "3")))
if (length(MAX_FAIL) != 1L || !is.finite(MAX_FAIL) || MAX_FAIL < 1L) MAX_FAIL <- 3L
load_skip <- function() {
  if (!file.exists(skip_path)) return(list())
  obj <- tryCatch(fromJSON(skip_path, simplifyVector = FALSE), error = function(e) list())
  if (is.list(obj)) obj else list()
}
skip_state <- load_skip()
skip_is_permanent <- function(url) {
  e <- skip_state[[as.character(url)]]
  !is.null(e) && isTRUE(e$permanent)
}

is_pdf_file <- function(path, min_bytes = 50000L) {
  if (!file.exists(path)) return(FALSE)
  sz <- file.info(path)$size
  if (!is.finite(sz) || sz < min_bytes) return(FALSE)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  hdr <- rawToChar(readBin(con, "raw", 4L), multiple = FALSE)
  identical(hdr, "%PDF")
}

download_one <- function(row) {
  dest_dir <- file.path(run_root, row$dest_subdir %||% "")
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, row$file_name)
  min_bytes <- suppressWarnings(as.integer(row$min_bytes %||% 50000L))
  if (!is.finite(min_bytes)) min_bytes <- 50000L

  if (is_pdf_file(dest, min_bytes)) {
    return(list(status = "already_present", path = dest, bytes = file.info(dest)$size, error = "", http_code = 200L))
  }
  tmp <- paste0(dest, ".tmp")
  if (file.exists(tmp)) unlink(tmp)
  if (dry_run) {
    return(list(status = "dry_run", path = dest, bytes = 0L, error = "", http_code = NA_integer_))
  }
  # -w %{http_code} 로 HTTP 코드 캡처 (404/410 = 영구 사망 분류용, 2026-06-18 Q).
  cmd <- sprintf(
    "curl -L --fail --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 2 -A %s -o %s -w %s %s",
    shQuote("Mozilla/5.0 QvestPaperRecharge/1.0"),
    shQuote(tmp),
    shQuote("%{http_code}"),
    shQuote(row$source_url)
  )
  code_out <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
  http_code <- suppressWarnings(as.integer(tail(code_out[nzchar(code_out)], 1)))
  if (length(http_code) != 1L || !is.finite(http_code)) http_code <- NA_integer_
  ok <- !is.na(http_code) && http_code >= 200L && http_code < 300L
  if (!ok || !is_pdf_file(tmp, min_bytes)) {
    err <- if (file.exists(tmp)) {
      sprintf("downloaded invalid/small file (%s bytes, http=%s)", file.info(tmp)$size %||% NA, http_code)
    } else {
      sprintf("curl failed (http=%s)", http_code)
    }
    unlink(tmp, force = TRUE)
    return(list(status = "failed", path = dest, bytes = 0L, error = err, http_code = http_code))
  }
  file.rename(tmp, dest)
  list(status = "downloaded", path = dest, bytes = file.info(dest)$size, error = "", http_code = http_code)
}

relative_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- normalizePath(PROJECT_ROOT, winslash = "/", mustWork = FALSE)
  sub(paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", root), "/?"), "", path)
}

brief_text <- function(x, n = 72L) {
  x <- gsub("\\s+", " ", as.character(x %||% ""), perl = TRUE)
  x <- trimws(x)
  if (!nzchar(x)) return("")
  if (nchar(x) > n) paste0(substr(x, 1L, n - 1L), "…") else x
}

paper_comment <- function(provider, title, notes, n = 78L) {
  comment <- brief_text(notes, 42L)
  label <- sprintf("%s: %s", provider, title)
  out <- if (nzchar(comment)) sprintf("%s | %s", label, comment) else label
  brief_text(out, n)
}

registry_next_ids <- function(registry, n) {
  ids <- registry$id %||% character(0)
  nums <- suppressWarnings(as.integer(gsub("[^0-9]", "", ids)))
  start <- max(nums, na.rm = TRUE)
  if (!is.finite(start)) start <- 0L
  sprintf("P%04d", seq.int(start + 1L, start + n))
}

append_registry <- function(success_rows) {
  reg_path <- file.path(PROJECT_ROOT, "06_Registry", "paper_registry.json")
  registry <- load_registry()
  if (nrow(success_rows) == 0L) return(list(added = 0L, path = reg_path))

  existing_paths <- as.character(registry$path %||% character(0))
  existing_sources <- as.character(registry$source %||% character(0))
  keep <- !(success_rows$relative_path %in% existing_paths | success_rows$source_url %in% existing_sources)
  success_rows <- success_rows[keep, , drop = FALSE]
  if (nrow(success_rows) == 0L) return(list(added = 0L, path = reg_path))

  new_ids <- registry_next_ids(registry, nrow(success_rows))
  new_reg <- data.frame(
    id = new_ids,
    path = success_rows$relative_path,
    title = success_rows$title,
    category = success_rows$category,
    status = "downloaded",
    priority = as.character(success_rows$priority),
    source = success_rows$source_url,
    note = success_rows$notes,
    subcategory = success_rows$provider,
    note_path = "",
    idea_extracted = FALSE,
    year = "",
    journal = success_rows$provider,
    date_added = format(Sys.Date(), "%Y-%m-%d"),
    stringsAsFactors = FALSE
  )

  all_cols <- union(names(registry), names(new_reg))
  for (nm in setdiff(all_cols, names(registry))) registry[[nm]] <- NA
  for (nm in setdiff(all_cols, names(new_reg))) new_reg[[nm]] <- NA
  registry <- registry[, all_cols, drop = FALSE]
  new_reg <- new_reg[, all_cols, drop = FALSE]
  out <- rbind(registry, new_reg)
  if (!dry_run) {
    write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"), reg_path)
  }
  list(added = nrow(new_reg), path = reg_path, ids = new_ids)
}

register_existing_recharge_pdfs <- function(scan_root) {
  reg_path <- file.path(PROJECT_ROOT, "06_Registry", "paper_registry.json")
  registry <- load_registry()
  files <- list.files(scan_root, pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
  if (length(files) == 0L) return(list(added = 0L, path = reg_path, ids = character(0)))
  files <- files[vapply(files, is_pdf_file, logical(1), min_bytes = 50000L)]
  if (length(files) == 0L) return(list(added = 0L, path = reg_path, ids = character(0)))
  rels <- vapply(files, relative_path, character(1))
  existing_paths <- as.character(registry$path %||% character(0))
  rels <- setdiff(rels, existing_paths)
  if (length(rels) == 0L) return(list(added = 0L, path = reg_path, ids = character(0)))

  title_from_path <- function(p) {
    x <- sub("\\.pdf$", "", basename(p), ignore.case = TRUE)
    x <- gsub("^(ARXIV|MCP)_[0-9_]+_", "", x)
    x <- gsub("_", " ", x)
    brief_text(x, 120L)
  }
  new_ids <- registry_next_ids(registry, length(rels))
  new_reg <- data.frame(
    id = new_ids,
    path = rels,
    title = vapply(rels, title_from_path, character(1)),
    category = ifelse(grepl("/mcp_arxiv/|/ARXIV_", rels), "Alpha_Search_MCP", "Institutional_Research"),
    status = "downloaded",
    priority = "2",
    source = paste0("local_recharge:", rels),
    note = "Auto-registered from Alpha_Search_Recharge folder; source URL unavailable in recharge manifest.",
    subcategory = "Alpha_Search_Recharge",
    note_path = "",
    idea_extracted = FALSE,
    year = "",
    journal = "Recharge",
    date_added = format(Sys.Date(), "%Y-%m-%d"),
    stringsAsFactors = FALSE
  )
  all_cols <- union(names(registry), names(new_reg))
  for (nm in setdiff(all_cols, names(registry))) registry[[nm]] <- NA
  for (nm in setdiff(all_cols, names(new_reg))) new_reg[[nm]] <- NA
  out <- rbind(registry[, all_cols, drop = FALSE], new_reg[, all_cols, drop = FALSE])
  if (!dry_run) {
    write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"), reg_path)
  }
  list(added = nrow(new_reg), path = reg_path, ids = new_ids)
}

run_mcp_probe <- function() {
  out <- file.path(stage_root, sprintf("mcp_discovery_%s.json", today))
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) {
    write(toJSON(list(status = "python_unavailable"), pretty = TRUE, auto_unbox = TRUE), out)
    return(list(status = "python_unavailable", out = out, candidates = 0L))
  }
  script <- file.path(PROJECT_ROOT, "02_Infrastructure", "tools", "paper_recharge_mcp.py")
  cmd <- sprintf("%s %s --project-root %s --out %s --max-results-per-query 5",
                 shQuote(py), shQuote(script), shQuote(PROJECT_ROOT), shQuote(out))
  status <- system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
  obj <- tryCatch(fromJSON(out, simplifyVector = FALSE), error = function(e) list(status = "read_failed"))
  list(
    status = obj$status %||% sprintf("exit_%s", status),
    out = out,
    candidates = length(obj$candidates %||% list())
  )
}

mcp <- run_mcp_probe()
log_line("[paper-recharge] MCP probe: status=%s candidates=%s out=%s", mcp$status, mcp$candidates, relative_path(mcp$out))

mcp_candidate_sources <- function(mcp_out) {
  obj <- tryCatch(fromJSON(mcp_out, simplifyDataFrame = FALSE), error = function(e) list())
  candidates <- obj$candidates %||% list()
  if (length(candidates) == 0L) return(data.frame())
  rows <- lapply(candidates, function(cand) {
    title <- as.character(cand$title %||% "")
    arxiv_id <- as.character(cand$arxiv_id %||% "")
    pdf_url <- as.character(cand$pdf_url %||% "")
    if (!nzchar(pdf_url) && nzchar(arxiv_id)) {
      clean_id <- sub("^https?://arxiv\\.org/(abs|pdf)/", "", arxiv_id)
      pdf_url <- sprintf("https://arxiv.org/pdf/%s", clean_id)
    }
    if (!nzchar(pdf_url) || !nzchar(title)) return(NULL)
    safe_id <- if (nzchar(arxiv_id)) {
      gsub("[^A-Za-z0-9]+", "_", arxiv_id)
    } else {
      substr(gsub("[^A-Za-z0-9]+", "_", title), 1, 48)
    }
    data.frame(
      provider = "arXiv MCP",
      title = title,
      category = "Alpha_Search_MCP",
      priority = 1,
      source_url = pdf_url,
      dest_subdir = "mcp_arxiv",
      file_name = sprintf("MCP_%s.pdf", safe_id),
      min_bytes = 50000,
      tags = "mcp;arxiv;alpha_search",
      notes = sprintf("Discovered by MCP query: %s", as.character(cand$query %||% "")),
      summary_ko = paper_summary_ko(title),
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

source_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "config", "paper_recharge_sources.csv")
curated_sources <- read_sources(source_path)
if (nrow(curated_sources) == 0L) stop("paper_recharge_sources.csv is empty or missing")

# ── curated(기관/헤지펀드/저명저자) 링크 건강도 — 매 실행 점검 (도훈 mandate 2026-06-18) ──
# arxiv/MCP 논문은 매번 fresh fetch + 영구 skip-list로 처리되므로 대상 아님. 이미 받은 PDF도
# 원격 링크가 사후에 죽을 수 있어 다운로드 여부와 무관하게 HTTP liveness 를 매번 점검한다.
audit_curated_health <- function(curated) {
  if (!is.data.frame(curated) || nrow(curated) == 0L) return(data.frame())
  do.call(rbind, lapply(seq_len(nrow(curated)), function(i) {
    u <- as.character(curated$source_url[i]); tf <- tempfile()
    cmd <- sprintf("curl -sL --connect-timeout 12 --max-time 30 -r 0-0 -A %s -o %s -w %s %s",
                   shQuote("Mozilla/5.0 QvestPaperRecharge/1.0"), shQuote(tf), shQuote("%{http_code}"), shQuote(u))
    out <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE)); unlink(tf)
    code <- suppressWarnings(as.integer(tail(out[nzchar(out)], 1)))
    if (length(code) != 1L || is.na(code)) code <- 0L
    data.frame(provider = curated$provider[i], title = curated$title[i], file_name = curated$file_name[i],
               source_url = u, http_code = code, ok = (code >= 200L && code < 400L), stringsAsFactors = FALSE)
  }))
}
curated_health <- tryCatch(audit_curated_health(curated_sources),
  error = function(e) { log_line("[paper-recharge] curated health check error: %s", conditionMessage(e)); data.frame() })
n_curated <- nrow(curated_health)
n_curated_dead <- if (n_curated > 0L) sum(!curated_health$ok) else 0L
if (!dry_run && n_curated > 0L) {
  write(toJSON(curated_health, pretty = TRUE, auto_unbox = TRUE, na = "null"),
        file.path(stage_root, sprintf("curated_health_%s.json", today)))
}
log_line("[paper-recharge] curated link health: %d ok / %d dead (of %d)",
         n_curated - n_curated_dead, n_curated_dead, n_curated)
if (n_curated_dead > 0L) for (j in which(!curated_health$ok)) {
  log_line("[paper-recharge] DEAD curated link: %s (http=%s) %s",
           curated_health$file_name[j], curated_health$http_code[j], curated_health$source_url[j])
}

mcp_sources <- mcp_candidate_sources(mcp$out)
sources_all <- rbind(mcp_sources, curated_sources)

registry_snapshot <- load_registry()
existing_sources <- as.character(registry_snapshot$source %||% character(0))
existing_titles <- tolower(trimws(as.character(registry_snapshot$title %||% character(0))))
sources_all$title_key <- tolower(trimws(as.character(sources_all$title)))
sources_all$source_key <- as.character(sources_all$source_url)
source_dup <- duplicated(sources_all$source_key) | !nzchar(sources_all$source_key)
title_dup <- duplicated(sources_all$title_key) | !nzchar(sources_all$title_key)
already_registered <- sources_all$source_key %in% existing_sources | sources_all$title_key %in% existing_titles
# 영구 실패 skip-list 제외 (죽은 404/410 ID·반복 실패 URL의 재시도 루프 차단, 2026-06-18 Q)
perm_skip <- vapply(sources_all$source_key, skip_is_permanent, logical(1))
dup_reg_mask <- source_dup | title_dup | already_registered
skip_count <- sum(dup_reg_mask)
perm_skip_count <- sum(perm_skip & !dup_reg_mask)
sources <- sources_all[!(dup_reg_mask | perm_skip), , drop = FALSE]
sources$title_key <- NULL
sources$source_key <- NULL
if (max_new > 0L && nrow(sources) > max_new) sources <- head(sources, max_new)
log_line("[paper-recharge] candidate filter: total=%d mcp=%d skipped_duplicate_or_registered=%d perm_failed_skip=%d to_fetch=%d",
         nrow(sources_all), nrow(mcp_sources), skip_count, perm_skip_count, nrow(sources))

results <- vector("list", nrow(sources))
if (nrow(sources) > 0L) {
  for (i in seq_len(nrow(sources))) {
    row <- sources[i, , drop = FALSE]
    log_line("[paper-recharge] fetch %s — %s", row$provider, row$title)
    res <- download_one(row)
    results[[i]] <- c(as.list(row), res)
    log_line("[paper-recharge] %s | %s | bytes=%s", row$file_name, res$status, res$bytes)
  }
}

# skip-state 갱신: 실패 URL 누적(404/410=즉시 영구, 그 외 MAX_FAIL회 후 영구), 성공 URL 해제 (2026-06-18 Q)
for (r in results) {
  if (is.null(r)) next
  url <- as.character(r$source_url %||% "")
  if (!nzchar(url)) next
  st <- as.character(r$status %||% "")
  if (st %in% c("downloaded", "already_present")) {
    skip_state[[url]] <- NULL
  } else if (st == "failed") {
    code <- suppressWarnings(as.integer(r$http_code %||% NA))
    prev <- skip_state[[url]]
    attempts <- (if (!is.null(prev)) as.integer(prev$attempts %||% 0L) else 0L) + 1L
    permanent <- (length(code) == 1L && !is.na(code) && code %in% c(404L, 410L)) || attempts >= MAX_FAIL
    skip_state[[url]] <- list(
      attempts = attempts,
      last_http = if (length(code) == 1L && !is.na(code)) code else NULL,
      last_error = as.character(r$error %||% ""),
      last_date = today,
      permanent = permanent,
      title = as.character(r$title %||% "")
    )
    if (permanent) log_line("[paper-recharge] permanent-skip 등록: %s (http=%s attempts=%d)", url, code, attempts)
  }
}
if (!dry_run) {
  write(toJSON(skip_state, pretty = TRUE, auto_unbox = TRUE, na = "null"), skip_path)
}

summary_df <- if (length(results) > 0L) {
  do.call(rbind, lapply(results, function(x) {
    data.frame(
      provider = x$provider,
      title = x$title,
      category = x$category,
      priority = x$priority,
      source_url = x$source_url,
      file_name = x$file_name,
      path = x$path,
      relative_path = relative_path(x$path),
      status = x$status,
      bytes = as.numeric(x$bytes),
      error = x$error,
      tags = x$tags,
      notes = x$notes,
      summary_ko = as.character(x$summary_ko %||% ""),
      stringsAsFactors = FALSE
    )
  }))
} else {
  data.frame(
    provider = character(), title = character(), category = character(),
    priority = character(), source_url = character(), file_name = character(),
    path = character(), relative_path = character(), status = character(),
    bytes = numeric(), error = character(), tags = character(), notes = character(),
    summary_ko = character(),
    stringsAsFactors = FALSE
  )
}

success_status <- c("downloaded", "already_present")
success_rows <- summary_df[summary_df$status %in% success_status, , drop = FALSE]
registry <- append_registry(success_rows)
existing_registered <- register_existing_recharge_pdfs(run_root)
registry_added_total <- as.integer(registry$added %||% 0L) + as.integer(existing_registered$added %||% 0L)

# ===== 신규 논문 alpha-search 후보 트리아지 + 저명저자 리스트 자동 리프레시 (도훈 mandate 2026-06-18) =====
# 키워드 MCP가 가져온 신규 다운로드 논문을 KR 구현가능성(횡단면 주식 알파)으로 휴리스틱 채점 + 저명저자 가점.
# 상위 후보만 텔레그램 알림 (백테는 수동 — "자동 트리아지 후 알림"). 저명저자는 별도 수집이 아니라 *랭킹 신호*.
# 저자 리스트 = quant_sources.json seed ∪ 다운로드 저자빈도(notable_authors.json, count>=refresh_min_count) 자동 리프레시.
triage_df <- data.frame()
notable_set <- character(0)
dl_rows <- summary_df[summary_df$status == "downloaded", , drop = FALSE]
tryCatch({
  .norm <- function(x) trimws(gsub("[^a-z0-9]+", " ", tolower(as.character(x %||% ""))))
  qs <- tryCatch(fromJSON(file.path(PROJECT_ROOT, "02_Infrastructure", "docs", "quant_sources.json"), simplifyVector = FALSE), error = function(e) list())
  na_cfg <- qs$notable_authors %||% list()
  seed <- unlist(na_cfg$seed %||% list())
  min_cnt <- as.integer(na_cfg$refresh_min_count %||% 3L); if (!is.finite(min_cnt)) min_cnt <- 3L
  max_auth <- as.integer(na_cfg$max_authors %||% 24L); if (!is.finite(max_auth)) max_auth <- 24L
  na_path <- file.path(stage_root, "notable_authors.json")
  freq <- list()
  if (file.exists(na_path)) {
    prev <- tryCatch(fromJSON(na_path, simplifyVector = FALSE), error = function(e) list())
    for (a in (prev$authors %||% list())) if (!is.null(a$name)) freq[[a$name]] <- as.integer(a$count %||% 0L)
  }
  dyn <- Filter(function(n) (as.integer(freq[[n]] %||% 0L)) >= min_cnt, names(freq))
  notable_set <- unique(c(seed, unlist(dyn)))
  # discovery JSON → title 정규화 키별 abstract/categories/authors
  disc <- tryCatch(fromJSON(mcp$out, simplifyVector = FALSE), error = function(e) list())
  lut <- list()
  for (cd in (disc$candidates %||% list())) {
    k <- .norm(cd$title); if (!nzchar(k)) next
    lut[[k]] <- list(
      abstract = as.character((cd$raw$abstract %||% cd$abstract) %||% ""),
      cats = paste(unlist(cd$categories %||% cd$raw$categories %||% list()), collapse = " "),
      authors = unlist(cd$raw$authors %||% list())
    )
  }
  score_one <- function(title, abstract, cats, authors) {
    txt <- tolower(paste(title, abstract)); s <- 0L; why <- character(0)
    if (grepl("q-fin\\.pm|q-fin\\.st", tolower(cats))) { s <- s + 3L; why <- c(why, "포트/횡단면") }
    pos <- c("cross.?section","factor","momentum","\\bvalue\\b","quality","low.?vol","low.?risk","anomaly","stock selection","characteristic","portfolio optim","return predict","expected return")
    if (any(vapply(pos, function(p) grepl(p, txt), logical(1)))) { s <- s + 2L; why <- c(why, "팩터/알파") }
    if (grepl("machine learning|deep learning|neural|gradient boost", txt) && grepl("stock|return|factor|cross.?section|equity|asset pric", txt)) { s <- s + 2L; why <- c(why, "ML주식") }
    mid <- c("regime","drawdown","risk parity","earnings","analyst","volatility.?managed","\\btail\\b")
    if (any(vapply(mid, function(p) grepl(p, txt), logical(1)))) s <- s + 1L
    neg <- c("crypto","bitcoin","high.?frequency","market.?making","microstructure","limit order","option pricing","derivative pricing","credit default","\\bbond\\b","fixed income","\\bfx\\b","foreign exchange","commodit","intraday","tick data")
    if (any(vapply(neg, function(p) grepl(p, txt), logical(1)))) { s <- s - 2L; why <- c(why, "구현난(시장/빈도)") }
    ahit <- FALSE
    if (length(authors) && length(notable_set)) {
      al <- paste(tolower(authors), collapse = " | ")
      wbt <- function(tok) grepl(paste0("(^|[^a-z])", tok, "([^a-z]|$)"), al, perl = TRUE)  # word-bounded token
      for (nm in notable_set) {
        toks <- tolower(strsplit(trimws(nm), "\\s+")[[1]])
        toks <- toks[nchar(toks) >= 3L]                       # 이니셜/de/i 등 제거
        if (length(toks) == 0L) next
        sur <- tail(toks, 1L); others <- setdiff(toks, sur)
        # 성(word-boundary) + 다른 이름 토큰 1개 이상 동시 일치 → 흔한 성(Chen/Feng/Kelly) 오탐 방지
        if (wbt(sur) && (length(others) == 0L || any(vapply(others, wbt, logical(1))))) { ahit <- TRUE; break }
      }
    }
    if (ahit) { s <- s + 2L; why <- c(why, "저명저자") }
    list(score = s, why = paste(why, collapse = ","), author_hit = ahit)
  }
  if (nrow(dl_rows) > 0L) {
    rr <- lapply(seq_len(nrow(dl_rows)), function(i) {
      meta <- lut[[.norm(dl_rows$title[i])]] %||% list(abstract = "", cats = "", authors = character(0))
      sc <- score_one(dl_rows$title[i], meta$abstract, meta$cats, meta$authors)
      data.frame(title = dl_rows$title[i], score = sc$score, reasons = sc$why,
                 author_hit = sc$author_hit, authors = paste(meta$authors, collapse = "; "),
                 cats = meta$cats, stringsAsFactors = FALSE)
    })
    triage_df <- do.call(rbind, rr)
    triage_df <- triage_df[order(-triage_df$score), , drop = FALSE]
    # 저자빈도 리프레시 (다운로드 논문 저자 누적) → notable_authors.json (top max_auth)
    for (i in seq_len(nrow(dl_rows))) {
      au <- (lut[[.norm(dl_rows$title[i])]] %||% list())$authors %||% character(0)
      for (a in au) if (nzchar(a)) freq[[a]] <- (as.integer(freq[[a]] %||% 0L)) + 1L
    }
    if (length(freq) > 0L) {
      keep <- head(names(freq)[order(-unlist(freq))], max_auth)
      authors_out <- lapply(keep, function(n) list(name = n, count = as.integer(freq[[n]]),
                            source = if (n %in% seed) "seed" else "dynamic", last_seen = today))
      if (!dry_run) {
        write(toJSON(list(refreshed = today, min_count = min_cnt, authors = authors_out),
                     pretty = TRUE, auto_unbox = TRUE, na = "null"), na_path)
        write(toJSON(triage_df, pretty = TRUE, auto_unbox = TRUE, na = "null"),
              file.path(stage_root, sprintf("alpha_search_triage_%s.json", today)))
      }
    }
    log_line("[paper-recharge] triage: %d scored | top=%d | notable authors active=%d | author-hit=%d",
             nrow(triage_df), max(triage_df$score), length(notable_set), sum(triage_df$author_hit))
  }
}, error = function(e) log_line("[paper-recharge] triage error: %s", conditionMessage(e)))

manifest_csv <- file.path(run_root, sprintf("paper_recharge_manifest_%s.csv", today))
manifest_json <- file.path(run_root, sprintf("paper_recharge_manifest_%s.json", today))
manifest_md <- file.path(run_root, "README.md")
alpha_handoff_json <- file.path(stage_root, sprintf("alpha_search_handoff_%s.json", today))
alpha_handoff_md <- file.path(run_root, sprintf("ALPHA_SEARCH_HANDOFF_%s.md", today))
if (!dry_run) {
  write.csv(summary_df, manifest_csv, row.names = FALSE, fileEncoding = "UTF-8")
  write(toJSON(list(
    date = today,
    mcp = mcp,
    counts = list(
      sources = nrow(sources),
      skipped_duplicate_or_registered = skip_count,
      downloaded = sum(summary_df$status == "downloaded"),
      already_present = sum(summary_df$status == "already_present"),
      failed = sum(summary_df$status == "failed"),
      registry_added = registry_added_total,
      existing_pdf_registered = existing_registered$added
    ),
    items = summary_df
  ), pretty = TRUE, auto_unbox = TRUE, na = "null"), manifest_json)

  lines <- c(
    sprintf("# Alpha Search Paper Recharge — %s", today),
    "",
    sprintf("- MCP probe: `%s` (%s candidates)", mcp$status, mcp$candidates),
    sprintf("- Sources checked: %d", nrow(sources)),
    sprintf("- Skipped duplicate/registered: %d", skip_count),
    sprintf("- Downloaded now: %d", sum(summary_df$status == "downloaded")),
    sprintf("- Already present: %d", sum(summary_df$status == "already_present")),
    sprintf("- Failed: %d", sum(summary_df$status == "failed")),
    sprintf("- Registry added: %d", registry_added_total),
    sprintf("- Existing PDF registered: %d", existing_registered$added),
    "",
    "## Papers",
    vapply(seq_len(nrow(summary_df)), function(i) {
      r <- summary_df[i, ]
      sprintf("- [%s] %s — `%s` (%s)", r$provider, r$title, r$relative_path, r$status)
    }, character(1))
  )
  writeLines(lines, manifest_md, useBytes = TRUE)

  alpha_handoff <- list(
    schema_version = "qvest_paper_recharge_alpha_search_handoff_v1",
    date = today,
    run_root = relative_path(run_root),
    mcp_status = mcp$status,
    mcp_candidates = mcp$candidates,
    mcp_report = relative_path(mcp$out),
    manifest_csv = relative_path(manifest_csv),
    manifest_json = relative_path(manifest_json),
    counts = list(
      fetched = nrow(sources),
      skipped_duplicate_or_registered = skip_count,
      downloaded = sum(summary_df$status == "downloaded"),
      already_present = sum(summary_df$status == "already_present"),
      failed = sum(summary_df$status == "failed"),
      registry_added = registry_added_total,
      existing_pdf_registered = existing_registered$added
    ),
    downloaded_papers = success_rows[, intersect(names(success_rows), c("provider", "title", "relative_path", "source_url", "tags", "notes")), drop = FALSE],
    failed_papers = summary_df[summary_df$status == "failed", intersect(names(summary_df), c("provider", "title", "source_url", "error")), drop = FALSE],
    alpha_search_candidates_ranked = if (is.data.frame(triage_df) && nrow(triage_df) > 0L)
      triage_df[, intersect(names(triage_df), c("title", "score", "reasons", "author_hit", "authors", "cats")), drop = FALSE]
      else data.frame(),
    alpha_search_next_actions = c(
      "MCP 사용 가능 세션에서는 arxiv/jina/paper-search로 신규 후보를 먼저 발굴한다.",
      "신규 PDF는 Alpha Search에서 시그널/구성/검증기간을 추출할 수 있는지 우선 평가한다.",
      "이미 등록된 제목/source_url은 재적재하지 말고 paper_registry의 기존 항목을 참조한다.",
      "기관 리서치는 비용/회전율/용량/폭락 민감도 관점에서 전략화 가능성만 선별한다."
    )
  )
  write(toJSON(alpha_handoff, pretty = TRUE, auto_unbox = TRUE, na = "null"), alpha_handoff_json)
  writeLines(c(
    sprintf("# Alpha Search Handoff — %s", today),
    "",
    sprintf("- MCP status: `%s` (%s candidates)", mcp$status, mcp$candidates),
    sprintf("- Manifest: `%s`", relative_path(manifest_json)),
    sprintf("- Downloaded: %d", sum(summary_df$status == "downloaded")),
    sprintf("- Duplicate/registered skipped: %d", skip_count),
    "",
    "## Next Actions",
    paste0("- ", alpha_handoff$alpha_search_next_actions)
  ), alpha_handoff_md, useBytes = TRUE)
}

if (!dry_run) {
  writeLines(c(
    sprintf("date=%s", today),
    sprintf("run_root=%s", relative_path(run_root)),
    sprintf("downloaded=%d", sum(summary_df$status == "downloaded")),
    sprintf("already_present=%d", sum(summary_df$status == "already_present")),
    sprintf("failed=%d", sum(summary_df$status == "failed")),
    sprintf("skipped_duplicate_or_registered=%d", skip_count),
    sprintf("registry_added=%d", registry_added_total),
    sprintf("existing_pdf_registered=%d", existing_registered$added),
    sprintf("mcp_status=%s", mcp$status),
    sprintf("mcp_candidates=%s", mcp$candidates)
  ), stamp)
}

send_tg <- !no_tg && !dry_run
if (send_tg) {
  tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R")
  if (file.exists(tg_path)) {
    tryCatch({
      source(tg_path)
      top_providers <- paste(head(unique(success_rows$provider), 6), collapse = ", ")
      comment_rows <- success_rows[success_rows$status == "downloaded", , drop = FALSE]
      if (nrow(comment_rows) == 0L) {
        comment_rows <- head(success_rows, 6)
      }
      # 논문 1편 = 한글 한줄요약(≤20자). 영어 제목 표 폐지 (도훈 mandate 2026-06-13).
      pad_min2 <- function(x) if (length(x) >= 2L) x else c(x, "이상 적재 완료")
      # 논문명(제목) + 한글요약 같이 표시 (도훈 mandate 2026-06-18). relaxed=TRUE 로 길이·영어약어 가드 면제.
      make_paper_line <- function(title, ko) {
        title <- gsub("\\s+", " ", trimws(as.character(title %||% "")), perl = TRUE)
        ko <- trimws(as.character(ko %||% ""))
        if (!nzchar(title)) return(if (nzchar(ko)) ko else "제목 미상")
        if (nzchar(ko)) sprintf("%s (%s)", title, ko) else title
      }
      paper_items_all <- if (nrow(comment_rows) > 0L) {
        vapply(seq_len(nrow(comment_rows)), function(i) {
          make_paper_line(comment_rows$title[i],
                          paper_summary_ko(comment_rows$title[i], comment_rows$summary_ko[i]))
        }, character(1))
      } else {
        c("오늘 신규 적재 논문 없음", "기존 등록 항목만 확인함")
      }
      paper_items_all <- pad_min2(paper_items_all)
      chunk_size <- 8L
      chunk_starts <- seq(1L, length(paper_items_all), by = chunk_size)
      chunk_total <- length(chunk_starts)
      paper_items <- paper_items_all[seq_len(min(chunk_size, length(paper_items_all)))]
      # alpha-search 후보 트리아지 상위 (KR 구현가능성 채점 + 저명저자 가점, 백테는 수동)
      triage_items <- if (is.data.frame(triage_df) && nrow(triage_df) > 0L) {
        topk <- head(triage_df, 5L)
        vapply(seq_len(nrow(topk)), function(i)
          sprintf("[%d점%s] %s", topk$score[i],
                  if (isTRUE(topk$author_hit[i])) "·저명저자" else "", topk$title[i]),
          character(1))
      } else character(0)
      main_sections <- list(
        list(
          heading = "적재 요약",
          type = "kv",
          kv = list(
            "신규 저장" = sprintf("%d편", sum(summary_df$status == "downloaded")),
            "기존 보유" = sprintf("%d편", sum(summary_df$status == "already_present")),
            "중복 제외" = sprintf("%d건", skip_count),
            "등록 추가" = sprintf("%d건", registry_added_total),
            "실패 건수" = sprintf("%d건", sum(summary_df$status == "failed"))
          )
        ),
        list(
          heading = "탐색·링크 상태",
          type = "bullet",
          items = c(
            sprintf("MCP 탐색 상태: %s", mcp$status),
            sprintf("탐색 후보 수: %s건", mcp$candidates),
            sprintf("기관논문 링크: %d/%d 정상%s", n_curated - n_curated_dead, n_curated,
                    if (n_curated_dead > 0L)
                      sprintf(" · 깨짐 %d (%s)", n_curated_dead,
                              paste(sub("\\.pdf$", "", curated_health$file_name[!curated_health$ok]), collapse = ", "))
                    else "")
          )
        ),
        list(
          heading = "오늘 적재 논문 요약",
          type = "bullet",
          items = paper_items
        )
      )
      if (length(triage_items) >= 2L) {
        main_sections <- c(main_sections, list(list(
          heading = "🎯 alpha-search 후보 (KR 구현가능성 상위·백테 수동)",
          type = "bullet",
          items = triage_items
        )))
      }
      main_sections <- c(main_sections, list(list(
        heading = "저장 경로",
        type = "text",
        body = sprintf(
          "오늘 적재 폴더와 매니페스트에 원문 파일, 출처, 알파서치 인계 메모를 기록했습니다. 주요 제공사는 %s입니다.",
          if (nzchar(top_providers)) substr(top_providers, 1, 72) else "신규 없음"
        )
      )))
      tg_agent_brief(
        agent = "AlphaSearch",
        title = "논문풀 일일 적재 완료",
        as_of = format(Sys.Date(), "%Y-%m-%d"),
        force = TRUE,
        relaxed = TRUE,
        lock_scope = sprintf("paper_recharge_%s", today),
        sections = main_sections,
        footer = "➡️ Alpha Search paper pool recharge complete",
        emoji_min = 3L
      )
      if (chunk_total > 1L) {
        for (chunk_idx in seq.int(2L, chunk_total)) {
          idx <- chunk_starts[chunk_idx]:min(length(paper_items_all), chunk_starts[chunk_idx] + chunk_size - 1L)
          chunk_items <- pad_min2(paper_items_all[idx])
          tg_agent_brief(
            agent = "AlphaSearch",
            title = sprintf("논문풀 적재 상세 %d/%d", chunk_idx, chunk_total),
            as_of = format(Sys.Date(), "%Y-%m-%d"),
            force = TRUE,
            relaxed = TRUE,
            lock_scope = sprintf("paper_recharge_%s_detail_%02d", today, chunk_idx),
            sections = list(
              list(
                heading = "상세 구간",
                type = "kv",
                kv = list(
                  "현재 구간" = sprintf("%d/%d", chunk_idx, chunk_total),
                  "페이퍼 수" = sprintf("%d편", length(chunk_items))
                )
              ),
              list(
                heading = "적재 논문 요약",
                type = "bullet",
                items = chunk_items
              )
            ),
            footer = "➡️ Remaining paper comments",
            emoji_min = 3L
          )
        }
      }
    }, error = function(e) {
      log_line("[paper-recharge] telegram failed: %s", conditionMessage(e))
    })
  }
}

log_line("[paper-recharge] done downloaded=%d present=%d failed=%d registry_added=%d",
         sum(summary_df$status == "downloaded"),
         sum(summary_df$status == "already_present"),
         sum(summary_df$status == "failed"),
         registry_added_total)
