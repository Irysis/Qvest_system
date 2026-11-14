#!/usr/bin/env Rscript
## 등급 v3.5 실데이터 드라이런 — 저장 기록 디렉터리를 한 계약 판으로 다시 채점해 표로 낸다(쓰기 없음 · 원본 기록 불변).
##   사용: Rscript dryrun_v35.R <contract_root> <data_root> <dirs.txt> <out.csv> <label>
##   contract_root = 계약 · 설정을 읽을 루트(운영 = v3.4 · 미러 = v3.5) · data_root = 저장 기록이 있는 운영 루트(읽기만)
##   관문(gates)은 재채점 도구(grade_v3_backfill.R)와 같은 규칙으로 저장 기록에서 만든다(선택 점검 = 저장 ok · DSR = 저장 dsr ≥ dsr_min).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
a <- commandArgs(trailingOnly = TRUE)
CROOT <- gsub("\\\\", "/", a[1]); DROOT <- gsub("\\\\", "/", a[2]); LST <- a[3]; OUT <- a[4]; LAB <- a[5]
stopifnot(identical(gsub("\\\\", "/", Sys.getenv("QM_ROOT")), CROOT), identical(gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR")), CROOT))
source(file.path(CROOT, "02_Infrastructure/contracts/grade_v3.R"))
ctx <- gv3_ctx(CROOT)
e <- .gv3_deps(CROOT)
DSR_MIN <- e$.graduation_params(refresh = TRUE, root = CROOT)$dsr_min
cat(sprintf("[%s] 계약 루트 %s · 규칙 판 %s · 선택 짝 %s · dsr_min %s\n", LAB, CROOT, ctx$cfg$rules_version,
            if (exists("gv3_selection_control")) gv3_selection_control(ctx$cfg) else "size_exposure(구 계약)", format(DSR_MIN)))
## 자료 판(사전등록 부록 1 §2 · 판단 T4 C-071 ③) — MC8 대조가 읽는 RAWDATA · 벤치 파일의 크기@수정 시각. 시작 · 끝에 재서 실행 중 바뀌면 경고한다.
vint <- function(f) { fi <- file.info(file.path(DROOT, ".cache", f)); if (is.na(fi$size)) NA_character_ else sprintf("%.0f@%s", fi$size, format(fi$mtime, "%Y-%m-%dT%H:%M:%S")) }
RAW0 <- vint("RAWDATA.parquet"); BEN0 <- vint("benchmark.parquet")
cat(sprintf("[%s] 자료 판 RAWDATA %s · 벤치 %s · 요인 md5 %s\n", LAB, RAW0, BEN0, as.character(ctx$fa$md5 %||% NA)))
dirs <- readLines(LST, warn = FALSE); dirs <- dirs[nzchar(dirs)]
rows <- vector("list", length(dirs)); t0 <- Sys.time()
for (i in seq_along(dirs)) {
  d <- dirs[i]; ad <- file.path(DROOT, d)
  t1 <- Sys.time()
  rows[[i]] <- tryCatch({
    A <- fromJSON(file.path(ad, "authoritative_remeasure.json"), simplifyVector = FALSE)
    if (isTRUE(A$hard_fail)) stop("hard_fail 기록(재채점 대상 아님)")
    gates <- NULL
    if (identical(as.character(A$selection_gate$mode %||% ""), "reality_check")) gates <- c(selection_rc = isTRUE(A$selection_gate$ok))
    else if (isTRUE(A$dsr_gate_applied)) { dv <- suppressWarnings(as.numeric(A$dsr %||% NA)[1]); gates <- c(dsr_sweep = isTRUE(is.finite(dv) && dv >= DSR_MIN)) }
    r <- gv3_score_dir(ad, CROOT, ctx, gates = gates)
    m <- r$mc8 %||% list()
    data.table(dir = d, label = LAB, rules_version = r$rules_version, stored_grade = as.character(A$essence_grade %||% NA),
               stored_rules = as.character(A$grade_v3$rules_version %||% NA), stored_cr_notch = as.character(A$grade_v3$cr_notch_basis %||% NA),
               grade = r$grade_v3, band = r$band, notch = r$notch, fa_notch = as.integer(r$fa_notch %||% 0L),
               cr = as.character(r$card$cr), cr_notch = as.character(r$cr_notch), basis = as.character(r$cr_notch_basis %||% NA),
               mc8_status = as.character(m$status %||% NA), mc8_label = as.character(m$label %||% NA),
               share_se = as.numeric(m$share_beats_size_exposure %||% NA), share_sb = as.numeric(m$share_beats_size_beta %||% NA),
               share_se_path = as.numeric(m$share_beats_size_exposure_path %||% NA), share_sb_path = as.numeric(m$share_beats_size_beta_path %||% NA),
               exposure_varies = as.logical(m$exposure_varies %||% NA)[1], label_size_beta = as.character(m$label_size_beta %||% NA),
               size_beta_status = as.character(m$size_beta_status %||% NA), beta_leg = as.numeric(m$beta_leg %||% NA), rho_median = as.numeric(m$rho_median %||% NA),
               card_beta = as.numeric(r$card$beta %||% NA), S = r$S, S_B = r$S_B, blocked_by = paste(r$blocked_by, collapse = ";"),
               factor_md5 = as.character(ctx$fa$md5 %||% NA), mc8_raw_source = as.character(m$raw_source %||% NA),   # 자료 판(판단 T4 C-071 ③)
               fa_t_min = as.numeric(r$fa$t_min %||% NA), fa_notch_applied = as.integer(r$fa_notch %||% 0L),
               rawdata_vintage = RAW0, bench_vintage = BEN0,
               secs = as.numeric(difftime(Sys.time(), t1, units = "secs")), err = NA_character_)
  }, error = function(err) data.table(dir = d, label = LAB, err = conditionMessage(err), secs = as.numeric(difftime(Sys.time(), t1, units = "secs"))))
  cat(sprintf("[%s] %d/%d %s · %s · %.0fs\n", LAB, i, length(dirs), d, rows[[i]]$grade %||% paste("ERR", rows[[i]]$err), rows[[i]]$secs))
}
res <- rbindlist(rows, fill = TRUE)
RAW1 <- vint("RAWDATA.parquet"); BEN1 <- vint("benchmark.parquet")
if (!identical(RAW0, RAW1) || !identical(BEN0, BEN1)) {
  cat(sprintf("[%s] ⚠ 실행 중 자료 판이 바뀌었다 — RAWDATA %s → %s · 벤치 %s → %s · 이 드라이런은 쓰지 말고 다시 돌린다\n", LAB, RAW0, RAW1, BEN0, BEN1))
  res[, vintage_changed_during_run := TRUE]
}
fwrite(res, OUT)
cat(sprintf("[%s] 끝 %d건 · %.1f분 → %s\n", LAB, nrow(res), as.numeric(difftime(Sys.time(), t0, units = "mins")), OUT))
