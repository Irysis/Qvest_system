# patch_catalog_label_annotations.R — 감사 결과의 module_catalog 반영 (도훈 confirm 후 실행)
# 기본 = dry-run (변경 계획만 출력, 파일 무수정)
#   --apply               : 주석 반영 (meta.actual_factor_names / label_class / label_suspect / duplicate_of)
#   --quarantine-mismatch : MISMATCH 계열 catalog 엔트리를 module_quarantine.json으로 이동 (apply와 함께만)
# 실행 전 06_Registry/module_catalog.json 백업본(.bak_label_audit)을 자동 생성.
# 주의: NAV/성과 수치는 건드리지 않음 — 라벨링 무결성 주석만 (metric_type=backtested 유지가 맞음).

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
APPLY <- "--apply" %in% args
QUAR  <- "--quarantine-mismatch" %in% args
if (QUAR && !APPLY) stop("--quarantine-mismatch는 --apply와 함께만 사용")

root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) {
  cand <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  while (!file.exists(file.path(cand, "02_Infrastructure", "config.R"))) {
    parent <- dirname(cand); if (identical(parent, cand)) stop("root not found"); cand <- parent
  }
  root <- cand
}
aud_dir <- file.path(root, "04_Research/audits/batch434_label_audit_20260613")
audit <- fread(file.path(aud_dir, "audit_runs.csv"), encoding = "UTF-8")

cat_path <- file.path(root, "06_Registry/module_catalog.json")
cat_j <- fromJSON(cat_path, simplifyVector = FALSE)

targets <- audit[in_catalog == TRUE & strategy_id %in% names(cat_j$modules)]
# NAV 클러스터 대표 선정: catalog 등재분 중 registered_at 최솟값 (없으면 run_dir 사전순 첫째)
targets[, registered_at := sapply(strategy_id, function(id) cat_j$modules[[id]]$registered_at %||% "")]
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
targets[, cluster_rep := strategy_id[order(registered_at, run_dir)][1], by = nav_md5]

plan <- targets[, .(strategy_id, label_class, actual_factor_names, actual_engine,
                    nav_md5, nav_cluster_size, cluster_rep,
                    is_duplicate = strategy_id != cluster_rep & nav_cluster_size > 1L,
                    is_mismatch = grepl("MISMATCH", label_class))]
fwrite(plan, file.path(aud_dir, "catalog_patch_plan.csv"), bom = TRUE)

cat(sprintf("[plan] catalog 대상 %d건: 주석 %d / 중복(비대표) %d / MISMATCH(격리 후보) %d\n",
            nrow(plan), nrow(plan), sum(plan$is_duplicate), sum(plan$is_mismatch)))

if (!APPLY) {
  cat("[dry-run] 파일 무수정. 실행하려면 --apply (격리 이동까지는 --apply --quarantine-mismatch)\n")
  quit(save = "no", status = 0)
}

# ── apply ──
bak <- paste0(cat_path, ".bak_label_audit_", format(Sys.time(), "%Y%m%d_%H%M%S"))
file.copy(cat_path, bak)
cat(sprintf("[backup] %s\n", bak))

moved <- character()
for (i in seq_len(nrow(plan))) {
  id <- plan$strategy_id[i]
  m <- cat_j$modules[[id]]
  if (is.null(m$meta)) m$meta <- list()
  m$meta$actual_factor_names <- plan$actual_factor_names[i]
  m$meta$actual_engine <- plan$actual_engine[i]
  m$meta$label_class <- plan$label_class[i]
  m$meta$label_suspect <- plan$is_mismatch[i]
  m$meta$label_audit <- "04_Research/audits/batch434_label_audit_20260613"
  if (plan$is_duplicate[i]) m$meta$duplicate_of <- plan$cluster_rep[i]
  cat_j$modules[[id]] <- m
}

if (QUAR) {
  q_path <- file.path(root, "06_Registry/module_quarantine.json")
  qj <- if (file.exists(q_path)) fromJSON(q_path, simplifyVector = FALSE) else list(modules = list())
  if (is.null(qj$modules)) qj$modules <- list()
  mis_ids <- plan[is_mismatch == TRUE, strategy_id]
  for (id in mis_ids) {
    e <- cat_j$modules[[id]]
    e$quarantine_reason <- sprintf("label mismatch (batch434 codegen fallback): %s — 가설 미검증, 실측은 actual_factor_names의 것",
                                   e$meta$label_class %||% "")
    e$fr_eligible <- FALSE
    qj$modules[[id]] <- e
    cat_j$modules[[id]] <- NULL
    moved <- c(moved, id)
  }
  qj$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  writeLines(toJSON(qj, auto_unbox = TRUE, pretty = TRUE, null = "null"), q_path, useBytes = TRUE)
}

cat_j$n_modules <- length(cat_j$modules)
cat_j$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
writeLines(toJSON(cat_j, auto_unbox = TRUE, pretty = TRUE, null = "null"), cat_path, useBytes = TRUE)
cat(sprintf("[apply] 주석 %d건 반영%s\n", nrow(plan),
            if (QUAR) sprintf(" + 격리 이동 %d건", length(moved)) else " (격리 이동 없음)"))
