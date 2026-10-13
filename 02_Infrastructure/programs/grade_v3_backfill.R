#!/usr/bin/env Rscript
#==============================================================================
# grade_v3_backfill.R — 저장된 권위 산출물의 등급을 등급 v3 로 소급한다 (MC7 · v10.01 2026-10-13)
#
# 왜: 등급 v3 가 권위 등급이 됐다(decision_register GRADE-V3-PROMOTE). 새 측정은 essence_score 가 v3 를 내지만,
#   저장된 authoritative_remeasure.json 의 essence_grade 는 구 5조건 판정(v921)이다. 소비자(2계층 풀 B+ 하한 ·
#   재채점 일치 검사 · 보고)가 같은 등급 체계를 읽도록 저장분을 v3 로 다시 적는다.
# 무엇을 쓰나(파일당): essence_grade ← v3 · grade_scheme = "grade_v3" · grade_v921 ← 직전 essence_grade ·
#   grade_v3 ← 근거 블록(essence_score 와 같은 형식) · reasons 앞에 v3 요약 · grade_v3_backfill ← 출처(직전 md5 · 시각 · 도구).
# 규칙: 계약 미경유(직전 essence_grade 결측) = 그대로 · judge hard_fail 주입 = F · 스윕형 선정이면 저장된 DSR 로 A 관문(gates) ·
#   이미 grade_scheme = grade_v3 = 건너뜀(멱등) · 동결된 QEPM WT 산출물(stage_artifacts/WT_*) = 제외 · 채점 재료 없는 파일 = 제외.
# 안전: 기본 드라이런 · --write 일 때만 쓴다 · 쓰기 전 원본 전문을 gz JSONL 보관본에 넣는다 · 파일은 임시 파일 → 이름 바꾸기.
#   (저장소가 git 으로 추적하므로 git 이력도 원본을 갖는다 — 보관본은 그 위의 두 번째 사본.)
# 사용: Rscript 02_Infrastructure/programs/grade_v3_backfill.R [--root R] [--workers 6] [--limit N] [--write]
# 산출: s0_grade_v3/backfill_manifest.csv · (쓰기 시) s0_grade_v3/backfill_originals_<날짜>.jsonl.gz
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(parallel) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
argv <- function(k, d = NULL) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }
WRITE <- "--write" %in% args
ROOT0 <- argv("--root", NULL)
for (p in c(ROOT0, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || !nzchar(p)) next
  if (file.exists(file.path(p, "02_Infrastructure/contracts/grade_v3.R"))) { ROOT0 <- gsub("\\\\", "/", p); break }
}
source(file.path(ROOT0, "02_Infrastructure/contracts/grade_v3.R"))
ROOT <- .gv3_root(ROOT0)
OUT <- argv("--out", file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3"))
WORKERS <- as.integer(argv("--workers", "6")); LIMIT <- as.integer(argv("--limit", "0"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── 1) 대상 ──
all_ar <- list.files(file.path(ROOT, "stage_artifacts"), pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
all_ar <- gsub("\\\\", "/", all_ar)
rel <- sub(paste0("^", ROOT, "/"), "", all_ar)
keep <- !grepl("^stage_artifacts/WT_", rel)
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv", "07_benchmark_compare.csv")
has <- vapply(dirname(all_ar), function(d) all(file.exists(file.path(d, need))), logical(1))
todo <- all_ar[keep & has]
cat(sprintf("[backfill] 권위 산출물 %d · WT 제외 %d · 재료 없음 %d · 대상 %d · 모드 %s\n", length(all_ar), sum(!keep),
            sum(keep & !has), length(todo), if (WRITE) "쓰기" else "드라이런"))
if (LIMIT > 0L) todo <- head(todo, LIMIT)

# ── 2) 파일 1개 → 새 JSON 문안(병렬 · 쓰기는 주 프로세스만) ──
one <- function(p) tryCatch({
  txt <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  A <- fromJSON(txt, simplifyVector = FALSE)
  old <- if (is.null(A$essence_grade)) NA_character_ else as.character(A$essence_grade)
  base <- list(path = p, old_grade = old, old_md5 = unname(as.character(tools::md5sum(p))))
  if (identical(A$grade_scheme, "grade_v3")) return(c(base, status = "already", new_grade = old))
  if (is.na(old)) return(c(base, status = "no_contract", new_grade = NA_character_))
  hf <- isTRUE(A$hard_fail)
  gates <- NULL
  if (isTRUE(A$dsr_gate_applied)) {
    dv <- suppressWarnings(as.numeric(A$dsr %||% NA)[1])
    gates <- c(dsr_sweep = isTRUE(is.finite(dv) && dv >= DSR_MIN))
  }
  v3 <- if (hf) NULL else gv3_score_dir(dirname(p), ROOT, CTX, gates = gates)
  rec <- if (hf) list(status = "not_applicable", reason = "hard_fail 주입(judge)") else
    E$.essence_v3_record(v3, TRUE, FALSE)
  new <- if (hf) "F" else as.character(v3$grade_v3)
  if (!hf && (length(new) != 1L || is.na(new))) return(c(base, status = "v3_na", new_grade = NA_character_))
  pre <- if (hf) "" else sprintf("v3: S %.3f · B 경계 %.3f · 띠 %s · CR %s(시험 창 %s) · 노치 %+d%s | v921 %s: ",
                                  v3$S, v3$S_B, v3$band, as.character(v3$card$cr), as.character(v3$card$cr_test),
                                  as.integer(v3$notch),
                                  if (length(v3$blocked_by)) paste0(" · A 아님 사유 ", paste(v3$blocked_by, collapse = ",")) else "", old)
  A$essence_grade <- new
  A$grade_scheme <- "grade_v3"
  A$grade_v921 <- old
  A$grade_v3 <- rec
  A$reasons <- paste0(pre, as.character(A$reasons %||% ""))
  A$grade_v3_backfill <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), tool = "02_Infrastructure/programs/grade_v3_backfill.R",
                              decision = "decision_register GRADE-V3-PROMOTE", prior_essence_grade = old,
                              prior_md5 = base$old_md5)
  nt <- toJSON(A, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  chk <- fromJSON(nt, simplifyVector = FALSE)
  if (!identical(as.character(chk$essence_grade), new) || !identical(chk$grade_scheme, "grade_v3"))
    stop("왕복 검증 실패")
  c(base, status = "ok", new_grade = new, S = if (hf) NA_real_ else v3$S, band = if (hf) NA_character_ else v3$band,
    notch = if (hf) 0L else v3$notch, old_text = txt, new_text = as.character(nt))
}, error = function(err) list(path = p, status = "error", err = conditionMessage(err)))

init_worker <- quote({
  suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
  source(file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R"))
  .e <- .gv3_deps(ROOT); E <- .e
  CTX <- gv3_ctx(ROOT)
  DSR_MIN <- .e$.graduation_params(refresh = TRUE, root = ROOT)$dsr_min
  NULL })
t0 <- Sys.time()
res <- if (WORKERS > 1L) {
  cl <- makeCluster(WORKERS)
  tryCatch({
    clusterExport(cl, c("ROOT", "%||%", "init_worker"))
    invisible(clusterEvalQ(cl, eval(init_worker)))
    parLapplyLB(cl, todo, one)
  }, finally = stopCluster(cl))
} else { eval(init_worker, envir = globalenv()); lapply(todo, one) }
cat(sprintf("[backfill] 채점 %d건 · %.1f분\n", length(res), as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ── 3) 쓰기(주 프로세스) ──
st <- vapply(res, function(z) as.character(z$status), "")
if (WRITE) {
  arc <- file.path(OUT, sprintf("backfill_originals_%s.jsonl.gz", format(Sys.time(), "%Y%m%d_%H%M%S")))
  gz <- gzfile(arc, open = "w", encoding = "UTF-8")
  n_w <- 0L
  tryCatch({
    for (z in res[st == "ok"]) {
      writeLines(toJSON(list(path = sub(paste0("^", ROOT, "/"), "", z$path), md5 = z$old_md5, text = z$old_text), auto_unbox = TRUE), gz)
    }
  }, finally = close(gz))
  for (i in which(st == "ok")) {
    z <- res[[i]]
    if (!identical(unname(as.character(tools::md5sum(z$path))), z$old_md5)) { res[[i]]$status <- "changed_since_read"; next }
    tmp <- paste0(z$path, ".tmp_gv3")
    writeLines(z$new_text, tmp, useBytes = TRUE)
    if (!file.rename(tmp, z$path)) { unlink(tmp); res[[i]]$status <- "write_failed"; next }
    res[[i]]$new_md5 <- unname(as.character(tools::md5sum(z$path))); n_w <- n_w + 1L
  }
  cat(sprintf("[backfill] 씀 %d · 원본 보관 %s\n", n_w, arc))
}
man <- rbindlist(lapply(res, function(z) data.table(path = sub(paste0("^", ROOT, "/"), "", z$path), status = z$status,
                                                     old_grade = z$old_grade %||% NA_character_, new_grade = z$new_grade %||% NA_character_,
                                                     S = as.numeric(z$S %||% NA), band = as.character(z$band %||% NA), notch = as.integer(z$notch %||% NA),
                                                     old_md5 = z$old_md5 %||% NA_character_, new_md5 = z$new_md5 %||% NA_character_,
                                                     err = z$err %||% NA_character_)), fill = TRUE)
fwrite(man, file.path(OUT, if (WRITE) "backfill_manifest.csv" else "backfill_manifest_dryrun.csv"))
cat("[backfill] 상태:", paste(names(table(man$status)), table(man$status), sep = "=", collapse = " · "), "\n")
ok <- man[status %in% c("ok")]
if (nrow(ok)) { cat("[backfill] 전이(구 → v3):\n"); print(dcast(ok[, .N, by = .(old_grade, new_grade)], old_grade ~ new_grade, value.var = "N", fill = 0)) }
