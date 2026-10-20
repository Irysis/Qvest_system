## 재판정 요약 — 라운드마다 저장본 대 코어 대조(판정 · 칸 판정 · 핵심 수치 · 구조 차이) + 작업 사본 패킷(β 짝 · 공통 창) 바이트 대조 + 실행 시간 → RESULTS.json
##   패킷 대조 제외 = created_at(시각) · provenance.source_dir / artifact(사본 경로 — 재판정 출력은 스크래치에 쓴다). 그 밖은 바이트 동일이어야 한다.
## 사용: Rscript summarize.R <재판정 출력 디렉터리> <RESULTS.json 경로> <라운드=저장 칸 산출 디렉터리>...
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
a <- commandArgs(trailingOnly = TRUE)
OUT <- gsub("\\\\", "/", a[1]); RES_JSON <- a[2]; pairs <- a[-(1:2)]
source(file.path(dirname(gsub("\\\\", "/", sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))), "compare.R"))
KEY_RX <- "^cells\\.[^.]+\\.(rules|non_inferiority|alpha_non_loss|decisive|beta_matched|verdict|pass|tested)(\\.|$)"
pk_strip <- function(p) { x <- fromJSON(p, simplifyVector = FALSE); x$created_at <- NULL; x$provenance$source_dir <- NULL; x$provenance$artifact <- NULL
                          as.character(toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA)) }
tm <- if (file.exists(file.path(OUT, "timing.jsonl"))) lapply(readLines(file.path(OUT, "timing.jsonl")), fromJSON) else list()
rounds <- list()
for (pr in pairs) {
  kv <- strsplit(pr, "=", fixed = TRUE)[[1]]; r <- kv[1]; RES <- gsub("\\\\", "/", kv[2]); O <- file.path(OUT, r)
  files <- intersect(c("evaluation_visible.json", "evaluation_full.json", "evaluation.json"), list.files(O))
  cmp <- lapply(setNames(files, files), function(f) if (file.exists(file.path(RES, f))) rc_compare_files(file.path(RES, f), file.path(O, f)) else NULL)
  cmp <- Filter(Negate(is.null), cmp)
  main <- cmp[["evaluation_visible.json"]] %||% cmp[["evaluation.json"]]
  diffs <- unlist(lapply(cmp, `[[`, "diffs"))
  key_d <- diffs[grepl(KEY_RX, sub(":.*$", "", diffs))]
  ## 작업 사본 패킷 — 코어 출력 아래 visible* 패킷마다 저장본 같은 경로와 대조
  pk <- list.files(O, pattern = "^diagnosis_packet\\.json$", recursive = TRUE)
  pk <- pk[!grepl("^\\.pairs/", pk)]
  pr_res <- lapply(pk, function(rel) { s <- file.path(RES, rel); if (!file.exists(s)) return(list(path = rel, stored = FALSE))
                                       list(path = rel, stored = TRUE, same = identical(pk_strip(s), pk_strip(file.path(O, rel)))) })
  ps <- Filter(function(z) isTRUE(z$stored), pr_res)
  t <- Filter(function(z) identical(z$round, r), tm)
  rounds[[r]] <- list(stored = RES, core = O, verdict_stored = main$label[["stored"]] %||% NA, verdict_core = main$label[["core"]] %||% NA,
                      verdict_same = identical(main$verdict[["stored"]], main$verdict[["core"]]) && identical(main$label[["stored"]], main$label[["core"]]),
                      cell_verdicts_same = isTRUE(main$cell_verdicts_same), n_cells = main$n_cells, key_numbers_same = !length(key_d),
                      n_structural_diffs = length(diffs), structural_diffs = utils::head(diffs, 100),
                      text_same_except_ignored = vapply(cmp, function(z) isTRUE(z$text_same_except_ignored), logical(1)),
                      packets_compared = length(ps), packets_same = sum(vapply(ps, function(z) isTRUE(z$same), logical(1))),
                      packets_differ = vapply(Filter(function(z) !isTRUE(z$same), ps), `[[`, "", "path"), packets_core_only = sum(!vapply(pr_res, function(z) isTRUE(z$stored), logical(1))),
                      timing = if (length(t)) t[[length(t)]] else NULL,
                      rules_crosscheck = if (file.exists(file.path(O, "rules_crosscheck.json"))) fromJSON(file.path(O, "rules_crosscheck.json"), simplifyVector = FALSE)[c("ok", "mismatches")] else NULL,
                      classification = if (!length(diffs)) "차이 없음(시각 · 평가 시점 데이터 지문 제외)" else "분류 필요")
}
old <- if (file.exists(RES_JSON)) fromJSON(RES_JSON, simplifyVector = FALSE) else list(rounds = list())
for (r in names(rounds)) {                                                      # 사람이 적은 분류(classification_note)는 보존한다
  if (!is.null(old$rounds[[r]]$classification_note)) rounds[[r]]$classification_note <- old$rounds[[r]]$classification_note
  if (!is.null(old$rounds[[r]]$classification) && !identical(rounds[[r]]$classification, "차이 없음(시각 · 평가 시점 데이터 지문 제외)") &&
      !identical(old$rounds[[r]]$classification, "분류 필요")) rounds[[r]]$classification <- old$rounds[[r]]$classification
  old$rounds[[r]] <- rounds[[r]]
}
old$schema <- "round_core_rejudge_results_v1"; old$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
old$ignored <- c("evaluated_at", "fingerprint.eval", "fingerprint.eval_record", "fingerprint.groups.*.eval_matches_measure", "packet created_at", "packet provenance.source_dir / artifact")
writeLines(toJSON(old, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), RES_JSON, useBytes = TRUE)
for (r in names(rounds)) with(rounds[[r]], cat(sprintf("[요약] %s — 판정 %s / %s · 칸 판정 동일 %s(%s칸) · 핵심 수치 동일 %s · 구조 차이 %d · 패킷 %d/%d 동일\n", r,
                                                       verdict_stored, verdict_core, cell_verdicts_same, n_cells, key_numbers_same, n_structural_diffs, packets_same, packets_compared)))
