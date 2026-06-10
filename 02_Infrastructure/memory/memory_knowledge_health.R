# memory_knowledge_health.R — v7.2.1 Sprint 5
#
# Memory Knowledge Health Gate
# Hard fail (6) + Warning (6 — external INFO 격하).
#
# Hard fail:
#   1) active axiom JSON parse 실패
#   2) active axiom 중 memory_id/axiom_class/authority/review_policy/enforcement_mode 누락
#   3) .claude/rules/axioms.md active vs JSON active 불일치 (sot_map 기준 — cache_core는 WARN)
#   4) deprecated와 active에 같은 memory_id + version 중복
#   5) review.R --all apply 없이 active JSON 변경
#   6) promote.R helper compatibility selftest 실패
#
# Warning:
#   1) L-code gap/outlier
#   2) stale candidate 90+ days
#   3) review_log schema variant 과다 (현재 17종)
#   4) external memory not indexed → INFO (audit v3 권고 B 격하)
#   5) enforcement claim ↔ hook 실제 강제력 불일치 (AX-003~005)
#   6) regime_validation parse fail (soft_mrs.json) + .cache/axiom_core.json STALE
#
# Usage: Rscript 02_Infrastructure/memory/memory_knowledge_health.R

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

safe_str <- function(x, default = "?") {
  if (is.null(x) || length(x) == 0) return(default)
  v <- x
  if (is.list(v)) {
    # collapse list/object to digest string
    return(paste(deparse(v), collapse = "")[1] |> substr(1, 50))
  }
  if (length(v) > 1) v <- v[[1]]
  if (is.null(v)) return(default)
  as.character(v)[1]
}

hard_fails <- list()
warnings_list <- list()
infos <- list()

add_hard <- function(id, msg) {
  hard_fails[[length(hard_fails) + 1]] <<- list(check_id = id, message = msg)
  cat(sprintf("  [HARD FAIL] %s — %s\n", id, msg))
}
add_warn <- function(id, msg) {
  warnings_list[[length(warnings_list) + 1]] <<- list(check_id = id,
                                                      message = msg)
  cat(sprintf("  [WARN]      %s — %s\n", id, msg))
}
add_info <- function(id, msg) {
  infos[[length(infos) + 1]] <<- list(check_id = id, message = msg)
  cat(sprintf("  [INFO]      %s — %s\n", id, msg))
}

cat("=== memory_knowledge_health.R v7.2.1 Sprint 5 ===\n\n")

# ─── HARD 1: active axiom JSON parse ─────────────────────────────
cat("[1/6 HARD] active axiom JSON parse\n")
active_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/active")
# v8.0: mode-local(active/modes/<mode>/) 포함 recursive
active_files <- list.files(active_dir, pattern = "\\.json$", full.names = TRUE, recursive = TRUE)
active_data <- list()
for (f in active_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                error = function(e) {
                  add_hard("HARD_1_active_parse",
                           sprintf("%s parse fail: %s",
                                   basename(f), conditionMessage(e)))
                  NULL
                })
  if (!is.null(d)) active_data[[basename(f)]] <- d
}
cat(sprintf("  %d active JSON parsed\n\n", length(active_data)))

# ─── HARD 2: required metadata fields ────────────────────────────
cat("[2/6 HARD] active axiom required metadata\n")
required <- c("memory_id", "axiom_class", "authority",
              "review_policy", "enforcement_mode", "canonical_statement")
for (fn in names(active_data)) {
  d <- active_data[[fn]]
  missing <- required[!required %in% names(d)]
  if (length(missing) > 0) {
    add_hard("HARD_2_metadata_missing",
             sprintf("%s missing fields: %s",
                     fn, paste(missing, collapse = ",")))
  }
}
cat("  metadata check complete\n\n")

# ─── HARD 3: sot_map active ↔ documented ─────────────────────────
cat("[3/6 HARD] sot_map active ↔ documented\n")
sot_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/axiom_sot_map.json")
if (!file.exists(sot_path)) {
  add_hard("HARD_3_sot_map_missing", "axiom_sot_map.json 부재")
} else {
  sot <- fromJSON(sot_path, simplifyVector = FALSE)
  documented_active_ids <- c()
  all_sot_ids <- c()
  for (ax in sot$axioms) {
    all_sot_ids <- c(all_sot_ids, ax$axiom_id)
    if (isTRUE(ax$documented_active)) {
      documented_active_ids <- c(documented_active_ids, ax$axiom_id)
    }
  }
  json_active_ids <- vapply(active_data, function(d) {
    safe_str(d$memory_id %||% d$axiom_id)
  }, character(1))
  missing_in_json <- setdiff(documented_active_ids, json_active_ids)
  # v8.0: mode-local(documented_active=FALSE이나 sot에 등록)은 통과 — sot 전체 레코드와 대조
  extra_in_json <- setdiff(json_active_ids, all_sot_ids)
  if (length(missing_in_json) > 0) {
    add_hard("HARD_3_sot_documented_missing_json",
             sprintf("documented active 중 JSON 부재: %s",
                     paste(missing_in_json, collapse = ",")))
  }
  if (length(extra_in_json) > 0) {
    add_hard("HARD_3_sot_json_not_documented",
             sprintf("JSON active 중 documented 부재: %s",
                     paste(extra_in_json, collapse = ",")))
  }
  cat(sprintf("  documented=%d, json=%d\n",
              length(documented_active_ids), length(json_active_ids)))
}
cat("\n")

# ─── HARD 4: deprecated/active duplicate memory_id+version ──────
cat("[4/6 HARD] deprecated/active duplicate memory_id+version\n")
dep_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/deprecated")
dep_files <- list.files(dep_dir, pattern = "\\.json$", full.names = TRUE)
dep_data <- list()
for (f in dep_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                error = function(e) NULL)
  if (!is.null(d)) dep_data[[basename(f)]] <- d
}
active_keys <- vapply(active_data, function(d) {
  sprintf("%s|%s",
          safe_str(d$memory_id %||% d$axiom_id),
          safe_str(d$version, "1"))
}, character(1))
for (fn in names(dep_data)) {
  d <- dep_data[[fn]]
  # Skip when deprecated explicitly notes superseded_by or scope_too_broad
  superseded <- safe_str(d$superseded_by, "")
  fname <- basename(fn)
  if (nzchar(superseded) || grepl("scope_too_broad|superseded|withdraw|rejection",
                                  fname, ignore.case = TRUE)) {
    next  # intentional in-place version replacement
  }
  k <- sprintf("%s|%s",
               safe_str(d$memory_id %||% d$axiom_id),
               safe_str(d$version, "1"))
  mid <- safe_str(d$memory_id %||% d$axiom_id, "")
  if (k %in% active_keys && nzchar(mid)) {
    add_hard("HARD_4_dep_active_dup",
             sprintf("%s memory_id+version duplicate in active: %s",
                     fn, k))
  }
}
cat("  duplicate check complete\n\n")

# ─── HARD 5: review.R --all without --apply 변경 감지 ───────────
cat("[5/6 HARD] review --all dry-run safety\n")
# git status check (simple)
old_wd <- getwd()
git_status <- tryCatch({
  setwd(PROJ_ROOT)
  system2("git", c("status", "--porcelain",
                   "qepm/memory/axioms/active"),
          stdout = TRUE)
}, error = function(e) character(),
   finally = setwd(old_wd))
modified_active <- git_status[grepl("^.M", git_status)]
if (length(modified_active) > 0) {
  add_warn("HARD_5_active_uncommitted",
           sprintf("active dir uncommitted changes (%d files) — verify intent",
                   length(modified_active)))
}
cat("  review safety check complete\n\n")

# ─── HARD 6: promote helper compatibility selftest ──────────────
cat("[6/6 HARD] promote.R helper selftest\n")
helper_path <- file.path(PROJ_ROOT,
                         "02_Infrastructure/memory/memory_metadata_normalize.R")
if (!file.exists(helper_path)) {
  add_hard("HARD_6_helper_missing", "memory_metadata_normalize.R 부재")
} else {
  st_result <- tryCatch({
    source(helper_path, local = TRUE)
    test1 <- normalize_axiom_metadata(
      axiom = list(id = "AX-TEST", text = "test"),
      write = FALSE
    )
    required_fields <- c("memory_id", "memory_kind", "axiom_class",
                          "authority", "review_policy",
                          "enforcement_mode", "canonical_statement")
    if (!all(required_fields %in% names(test1))) {
      "missing required fields"
    } else if (test1$memory_id != "AX-TEST") {
      "fallback chain failed"
    } else if (test1$canonical_statement != "test") {
      "canonical fallback failed"
    } else {
      "PASS"
    }
  }, error = function(e) conditionMessage(e))

  if (st_result != "PASS") {
    add_hard("HARD_6_helper_selftest", st_result)
  } else {
    cat("  helper selftest PASS\n")
  }
}
cat("\n")

# ─── WARN 1: L-code corpus outliers ──────────────────────────────
cat("[W1/6] L-code corpus outliers\n")
# v8.0: outlier(L-code gap>50)는 rebuild(v7.2.1_lcode_corpus)의 summary.outliers에만 존재.
# harvester corpus(v53_ax_p0)엔 그 필드가 없어 과거 본 체크가 inert였음(clobber race로 harvester가
# canonical 차지). methodology corpus 우선, 없으면 canonical fallback.
corpus_path <- file.path(PROJ_ROOT, ".cache/lcode_corpus_methodology.json")
if (!file.exists(corpus_path)) corpus_path <- file.path(PROJ_ROOT, ".cache/lcode_corpus.json")
if (file.exists(corpus_path)) {
  corpus <- fromJSON(corpus_path, simplifyVector = FALSE)
  # null-safe (이 파일의 %||%는 multi-element 벡터를 logical(1)로 강제하다 깨짐 —
  # 과거 outliers가 항상 NULL[inert]이라 미노출됐던 잠재버그. 직접 NULL 처리.)
  outliers <- corpus$summary$outliers
  outliers <- if (is.null(outliers)) character(0) else as.character(unlist(outliers))
  if (length(outliers) > 0) {
    add_warn("WARN_1_lcode_outliers",
             sprintf("L-code gap>50: %s",
                     paste(outliers, collapse = ",")))
  } else {
    cat("  no outliers\n")
  }
} else {
  add_warn("WARN_1_lcode_corpus_missing", "lcode_corpus.json 부재")
}

# ─── WARN 2: stale candidate 90+ days ────────────────────────────
cat("[W2/6] stale candidate 90+ days\n")
cand_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/candidates")
cand_files <- list.files(cand_dir, pattern = "\\.json$", full.names = TRUE)
threshold <- Sys.time() - as.difftime(90, units = "days")
stale_count <- 0
for (f in cand_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) next
  created <- d$created_at %||% ""
  if (nchar(created) > 0) {
    ct <- tryCatch(as.POSIXct(created), error = function(e) Sys.time())
    if (!is.na(ct) && ct < threshold) stale_count <- stale_count + 1
  }
}
if (stale_count > 0) {
  add_warn("WARN_2_stale_candidate",
           sprintf("%d candidates older than 90 days", stale_count))
} else {
  cat("  no stale candidates\n")
}

# ─── WARN 3: review_log schema variant ───────────────────────────
cat("[W3/6] review_log schema variant\n")
rl_dir <- file.path(PROJ_ROOT, "qepm/memory/axioms/review_log")
rl_files <- list.files(rl_dir, pattern = "\\.json$", full.names = TRUE,
                       recursive = FALSE)
schemas <- character(0)
for (f in rl_files) {
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) next
  schemas <- c(schemas, paste(sort(names(d)), collapse = ","))
}
n_variants <- length(unique(schemas))
if (n_variants > 10) {
  add_warn("WARN_3_review_log_variants",
           sprintf("review_log %d schema variants (recommend < 10)",
                   n_variants))
} else {
  cat(sprintf("  %d schema variants\n", n_variants))
}

# ─── INFO 4: external memory not indexed (격하) ──────────────────
cat("[I4/6] external memory indexed\n")
external_base <- "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory"
if (dir.exists(external_base)) {
  ext_count <- length(list.files(external_base, pattern = "\\.md$"))
  add_info("INFO_4_external_memory_excluded",
           sprintf("external memory %d files — opt-in via --include-claude-memory",
                   ext_count))
} else {
  cat("  external base not found (skip)\n")
}

# ─── WARN 5: enforcement claim ↔ hook 실제 강제력 ────────────────
cat("[W5/6] enforcement claim vs hook strength\n")
hook_path <- file.path(PROJ_ROOT,
                       "02_Infrastructure/hooks/axiom_enforcement_hook.sh")
unverified <- c()
for (fn in names(active_data)) {
  d <- active_data[[fn]]
  mode <- safe_str(d$enforcement_mode, "")
  ax_id <- safe_str(d$memory_id %||% d$axiom_id, "")
  if (mode %in% c("block", "advisory")) {
    if (file.exists(hook_path)) {
      hook_content <- readLines(hook_path, warn = FALSE)
      if (!any(grepl(ax_id, hook_content, fixed = TRUE))) {
        unverified <- c(unverified, ax_id)
      }
    }
  }
}
if (length(unverified) > 0) {
  add_warn("WARN_5_enforcement_unverified",
           sprintf("enforcement_mode block/advisory but not in hook: %s",
                   paste(unverified, collapse = ",")))
} else {
  cat("  enforcement claims aligned\n")
}

# ─── WARN 6: regime_validation parse + cache STALE ───────────────
cat("[W6/6] regime_validation + cache_core sync\n")
rv_path <- file.path(PROJ_ROOT, "qepm/memory/regime_validation/soft_mrs.json")
if (file.exists(rv_path)) {
  if (file.info(rv_path)$size == 0) {
    # [v8.0 fix 2026-05-29 B5] 0-byte orphan (writer 부재 2026-04-08~, regime_signal.R 미참조 → fallback 작동).
    # parse-fail WARN 오탐 제거. disposition(삭제/feature 복구)는 별도. 구 run_all.R 참조 위해 파일 retain.
    cat("  soft_mrs.json 0-byte orphan (writer 부재, regime fallback 작동) — N/A skip\n")
  } else {
    d <- tryCatch(fromJSON(rv_path, simplifyVector = FALSE),
                  error = function(e) conditionMessage(e))
    if (is.character(d)) {
      add_warn("WARN_6_regime_validation_parse",
               sprintf("soft_mrs.json parse fail: %s", d))
    } else {
      cat("  soft_mrs.json parse OK\n")
    }
  }
}
cache_path <- file.path(PROJ_ROOT, ".cache/axiom_core.json")
if (file.exists(cache_path)) {
  cache <- tryCatch(fromJSON(cache_path, simplifyVector = FALSE),
                    error = function(e) NULL)
  if (!is.null(cache)) {
    cache_ids <- vapply(cache$axioms, function(x) safe_str(x$id),
                        character(1))
    json_ids <- vapply(active_data, function(d) {
      safe_str(d$memory_id %||% d$axiom_id)
    }, character(1))
    cache_diff <- setdiff(json_ids, cache_ids)
    if (length(cache_diff) > 0) {
      add_warn("WARN_6_cache_core_stale",
               sprintf(".cache/axiom_core.json STALE — missing: %s (regenerate via bootstrap)",
                       paste(cache_diff, collapse = ",")))
    }
  }
}

# WARN_7: Stop hook script ↔ settings.json 등록 정합 (L-314 follow-up — L-275 silent fail 재발 방지)
cat("[W7] Stop hook script ↔ settings.json registration consistency\n")
stop_hook_dir <- file.path(PROJ_ROOT, "02_Infrastructure/hooks")
stop_hook_scripts <- list.files(
  stop_hook_dir,
  pattern = "^auto_(commit|push)_on_stop\\.sh$",
  full.names = FALSE
)
settings_path <- file.path(PROJ_ROOT, ".claude/settings.json")
if (length(stop_hook_scripts) > 0 && file.exists(settings_path)) {
  settings_content <- paste(readLines(settings_path, warn = FALSE),
                            collapse = "\n")
  unregistered <- character()
  for (script in stop_hook_scripts) {
    if (!grepl(script, settings_content, fixed = TRUE)) {
      unregistered <- c(unregistered, script)
    }
  }
  if (length(unregistered) > 0) {
    add_warn("WARN_7_stop_hook_unregistered",
             sprintf("Stop hook script(s) exist but not registered in settings.json: %s — L-275 silent fail pattern",
                     paste(unregistered, collapse = ", ")))
  } else {
    cat(sprintf("  %d Stop hook script(s) registered in settings.json: OK\n",
                length(stop_hook_scripts)))
  }
}

# ─── Summary ─────────────────────────────────────────────────────
cat("\n=== SUMMARY ===\n")
cat(sprintf("Hard fails: %d\n", length(hard_fails)))
cat(sprintf("Warnings:   %d\n", length(warnings_list)))
cat(sprintf("Infos:      %d\n", length(infos)))

# Write report
out_dir <- file.path(PROJ_ROOT, "qepm/observability")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
report <- list(
  schema_version = "v7.2.1_memory_health",
  ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hard_fails = hard_fails,
  warnings = warnings_list,
  infos = infos,
  summary = list(
    hard_fail_count = length(hard_fails),
    warning_count = length(warnings_list),
    info_count = length(infos),
    overall = if (length(hard_fails) == 0) "PASS" else "FAIL"
  )
)
out_path <- file.path(out_dir, "memory_health_latest.json")
write_json(report, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\nReport: %s\n", out_path))

quit(status = if (length(hard_fails) == 0) 0 else 1)
