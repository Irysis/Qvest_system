# apply_catalog_dup_annotations.R — 2026-08-20 dup-hash 감사 결과의 module_catalog 반영
# ★기본 = dry-run (변경 계획만 출력, 파일 무수정). 적용은 도훈 confirm 후:
#   --apply             : 주석 반영 (meta$dup_hash_group / duplicate_of / label_class /
#                         actual_factor_names / label_audit) — fr_eligible 불변
#   --defr-nonrep       : (apply 와 함께만) 비대표 중복 100건 fr_eligible=false
#                         (근거: FR 입력면 210 중 128 이 복제본 — RCMA 가 같은 NAV 를
#                          다른 이름으로 중복 선정할 수 있는 상태의 해소)
#   --quarantine-mismatch: (apply 와 함께만) FALLBACK_SUBSTITUTION/OVERLAY_NOOP/MISMATCH
#                         계열을 module_quarantine 으로 이동 (June 감사 동일 옵션)
# 실행 전 module_catalog.json 백업(.bak_dup_audit_<ts>) 자동 생성.
# ★NAV/성과 수치는 건드리지 않는다 — 측정은 진짜였고(치환 콤보의 실측), 틀린 건 라벨이다.
# 선행: 2026-06-13 batch434_label_audit 의 patch_catalog_label_annotations.R (미적용 상태였음
#       + aud_dir 경로가 04_Research/audits/* 로 낙후 — 본 스크립트가 대체).
# 적용 후속 의무: build_module_performance.R 재실행 (FR 입력면 재생성) + improve-drain
#       standalone_track_queue 재빌드. README.md §후속 참조.

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

args  <- commandArgs(trailingOnly = TRUE)
APPLY <- "--apply" %in% args
DEFR  <- "--defr-nonrep" %in% args
QUAR  <- "--quarantine-mismatch" %in% args
if ((DEFR || QUAR) && !APPLY) stop("--defr-nonrep / --quarantine-mismatch 는 --apply 와 함께만 사용")

root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) {
  root <- Sys.getenv("QM_ROOT", "")
}
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) {
  cand <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  while (!file.exists(file.path(cand, "02_Infrastructure", "config.R"))) {
    parent <- dirname(cand); if (identical(parent, cand)) stop("project root not found"); cand <- parent
  }
  root <- cand
}

aud_dir <- file.path(root, "04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820")
plan <- fread(file.path(aud_dir, "catalog_patch_plan_20260820.csv"), encoding = "UTF-8")

cat_path <- file.path(root, "06_Registry/module_catalog.json")
cat_j <- fromJSON(cat_path, simplifyVector = FALSE)
plan <- plan[strategy_id %in% names(cat_j$modules)]

cat(sprintf("[plan] catalog 대상 %d건 | 주석 %d / 비대표 de-FR %d / 격리 후보(mismatch) %d\n",
            nrow(plan), nrow(plan), sum(plan$defr_nonrep), sum(plan$quarantine_mismatch)))
if (!APPLY) {
  cat("[dry-run] 파일 무수정. 적용 = 도훈 confirm 후 --apply (+ --defr-nonrep / --quarantine-mismatch)\n")
  quit(save = "no", status = 0)
}

bak <- paste0(cat_path, ".bak_dup_audit_", format(Sys.time(), "%Y%m%d_%H%M%S"))
if (!file.copy(cat_path, bak)) stop("backup 실패 — 중단")
cat(sprintf("[backup] %s\n", bak))

for (i in seq_len(nrow(plan))) {
  id <- plan$strategy_id[i]
  m <- cat_j$modules[[id]]
  if (is.null(m$meta)) m$meta <- list()
  m$meta$dup_hash_group <- plan$dup_hash_group[i]
  m$meta$label_class    <- plan$annotate_label_class[i]
  if (nzchar(plan$annotate_actual_factor_names[i]))
    m$meta$actual_factor_names <- plan$annotate_actual_factor_names[i]
  if (nzchar(plan$annotate_duplicate_of[i]))
    m$meta$duplicate_of <- plan$annotate_duplicate_of[i]
  m$meta$label_audit <- "04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820"
  if (DEFR && isTRUE(plan$defr_nonrep[i])) {
    m$fr_eligible <- FALSE
    m$contract$eligibility_reason <- sprintf(
      "DUP_HASH_NONREP: 동일 module_hash 산출물의 비대표 이명 (rep=%s, batch_434 감사 2026-08-20)",
      plan$cluster_rep[i])
  }
  cat_j$modules[[id]] <- m
}

moved <- character()
if (QUAR) {
  q_path <- file.path(root, "06_Registry/module_quarantine.json")
  qj <- if (file.exists(q_path)) fromJSON(q_path, simplifyVector = FALSE) else list(modules = list())
  if (is.null(qj$modules)) qj$modules <- list()
  for (id in plan[quarantine_mismatch == TRUE, strategy_id]) {
    e <- cat_j$modules[[id]]
    if (is.null(e)) next
    e$quarantine_reason <- sprintf(
      "label mismatch (batch_434 keyword-fallback 치환): 선언 가설 미검증 — 실측은 meta$actual_factor_names 의 콤보 (%s)",
      e$meta$label_class %||% "")
    e$fr_eligible <- FALSE
    qj$modules[[id]] <- e
    cat_j$modules[[id]] <- NULL
    moved <- c(moved, id)
  }
  qj$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  qj$n_modules <- length(qj$modules)
  writeLines(toJSON(qj, auto_unbox = TRUE, pretty = TRUE, null = "null"), q_path, useBytes = TRUE)
}

cat_j$n_modules <- length(cat_j$modules)
cat_j$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
writeLines(toJSON(cat_j, auto_unbox = TRUE, pretty = TRUE, null = "null"), cat_path, useBytes = TRUE)
cat(sprintf("[apply] 주석 %d건%s%s → 후속: build_module_performance.R 재실행 + standalone_track_queue 재빌드\n",
            nrow(plan),
            if (DEFR) sprintf(" + de-FR %d건", sum(plan$defr_nonrep)) else "",
            if (QUAR) sprintf(" + 격리 이동 %d건", length(moved)) else ""))
