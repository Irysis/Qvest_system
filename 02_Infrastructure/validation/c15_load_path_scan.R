#!/usr/bin/env Rscript
#==============================================================================
# c15_load_path_scan.R — 운영 경로의 factor_db 로드 경로 감사 (C15)
#
# 왜 새로 만드는가 (2026-08-08, 칩 task_deabaca2 ③ 규명 결과):
#   기존 `audit_bt_result.R` Check 14 는 **`bt_result$strategy_spec$factor_engine_path` 한 파일만**
#   스캔한다. 매월 실행되는 배포·재계산 스크립트(forward_weights_*.R, _recompute_alpha_asof.R)는
#   factor_engine 으로 등록되지 않아 **애초에 시야 밖**이었다 — 그래서 C15 우회가 감사에 안 걸렸다.
#   본 스캐너는 그 사각을 덮는다. **판정 의미는 기존 게이트와 동일하게 유지**한다:
#     · 직접 read + align 호출 있음 → PASS_WITH_NOTES ("letter 위반, spirit 정합")
#     · 직접 read + align 없음      → FAIL (정렬조차 없으면 방향이 full-sample IC 로 샌다)
#     · 직접 read 없음              → PASS
#   ★관용의 근거는 실측이다: 2026-08-08 A/B 에서 직접-read 경로와 load_month_factors 가
#     R05 24개월 + 7팩터 12개월 = 108 조합 **전부 값 동일**(정렬 창 12 vs 36 차이가 방향을 안 바꿈).
#     그러나 커넥터 의미가 바뀌면 직접-read 만 조용히 갈라지므로 **NOTES 로 계속 노출**한다.
#
# 사용: Rscript 02_Infrastructure/validation/c15_load_path_scan.R [스캔루트 ...]
#       기본 스캔 대상 = 운영 경로(05_Production 배포 스크립트 + 02_Infrastructure/portfolio)
# 반환: 표 출력 + exit 1 (FAIL 존재 시)
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.c15_root <- function() {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("[c15] 프로젝트 루트 해석 실패 — CLAUDE_PROJECT_DIR/QM_ROOT 설정 필요")
  normalizePath(hit[1])
}

c15_scan_file <- function(path) {
  src <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  if (!length(src)) return(NULL)
  code <- src[!grepl("^\\s*#", src)]                       ## 주석 제외 — 주석 속 예시로 통과/탈락하지 않도록
  ## ① 같은 줄 패턴: read_parquet(".../factor_db/...")
  same_line <- grep("read_parquet\\s*\\(.*factor_db", code, value = TRUE)
  ## ★② 변수 경유 패턴: 경로를 변수에 담고 read_parquet(변수) 로 읽는 형태.
  ##   초판은 ①만 봐서 `forward_weights_R05_*.R`(fdb_path <- ...factor_db...; read_parquet(fdb_path))
  ##   을 통째로 놓쳤다 — 내 검사기의 사각지대였다(2026-08-08 자체 적발).
  has_fdb_path <- any(grepl("factor_db[^\"']*\\.parquet|factor_db/", code))
  has_read     <- any(grepl("read_parquet\\s*\\(", code))
  via_var      <- has_fdb_path && has_read && !length(same_line)
  direct_n <- length(same_line) + as.integer(via_var)
  lmf    <- grep("load_month_factors\\s*\\(", code, value = TRUE)
  align  <- grep("align_factor_direction\\s*\\(", code, value = TRUE)
  verdict <- if (!direct_n) "PASS"
             else if (length(align)) "PASS_WITH_NOTES"
             else "FAIL"
  data.table(file = path, direct_read = direct_n,
             evidence = if (length(same_line)) "same_line" else if (via_var) "via_var" else "",
             lmf = length(lmf), align = length(align), verdict = verdict)
}

c15_scan <- function(roots = NULL, quiet = FALSE) {
  R <- .c15_root()
  if (is.null(roots)) roots <- c(
    file.path(R, "05_Production/2.Factor_Model"),
    file.path(R, "02_Infrastructure/portfolio"))
  roots <- roots[dir.exists(roots)]
  if (!length(roots)) stop("[c15] 스캔 대상 디렉터리 없음 — 경로 확인")
  files <- unlist(lapply(roots, function(d) list.files(d, pattern = "\\.R$", recursive = TRUE, full.names = TRUE)))
  files <- files[!grepl("/(01_reproducible_code_backup|_logs)/", files)]
  if (!length(files)) stop("[c15] 스캔 대상 .R 파일 0 — 경로/패턴 확인(빈 결과를 합격으로 쓰지 않는다)")
  res <- rbindlist(Filter(Negate(is.null), lapply(files, c15_scan_file)), fill = TRUE)
  ## 루트 접두 제거는 **fixed=TRUE** 로 — 경로를 정규식으로 이스케이프하려다 TRE `{}` 컴파일 오류를
  ## 냈다(r-portability 계열 함정: 경로는 패턴이 아니다).
  res[, file := sub(paste0(R, "/"), "", file, fixed = TRUE)]
  setorder(res, -direct_read, file)
  if (!quiet) {
    cat(sprintf("[c15] 스캔 %d파일 | PASS %d · PASS_WITH_NOTES %d · FAIL %d\n",
                nrow(res), sum(res$verdict == "PASS"), sum(res$verdict == "PASS_WITH_NOTES"),
                sum(res$verdict == "FAIL")))
    hit <- res[verdict != "PASS"]
    if (nrow(hit)) { cat("\n[직접 read 보유 파일]\n"); print(hit[, .(file, direct_read, lmf, align, verdict)]) }
  }
  invisible(res)
}

if (sys.nframe() == 0 && !interactive()) {
  a <- commandArgs(trailingOnly = TRUE)
  r <- c15_scan(if (length(a)) a else NULL)
  quit(status = if (any(r$verdict == "FAIL")) 1L else 0L)
}
