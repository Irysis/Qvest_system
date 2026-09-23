#==============================================================================
# emission_report_gate.R — emission_report_{ym}.json 의 **첫 reader** (W-02, 2026-09-23)
#
# 사고: emission_guard.R 는 factor_db_202609 빌드에서 "회귀 27종"(V01~V24·S01·S02·L26 —
#   RAWDATA.Size 100% 결측의 하류)을 정확히 판정해 emission_report_202609.json 에 남겼다.
#   그런데 그 파일을 읽는 코드가 0곳이었다 — 판정은 있었고 **소비자가 없었다**. 빌더는
#   설계상 멈추지 않으므로(emission_guard 원칙 ①) 경보는 누군가 읽어야만 경보가 된다.
#   이 스크립트가 daily_refresh [6a] 직후 그 판정을 읽어 DR_FAILED 에 싣는다.
#
# 판정 = class_R_regression(직전 관측 빌드에선 났는데 지금 0행) 의 개수. 문턱은 없다 —
#   회귀는 vintage 무관하게 항상 이상이라는 것이 emission_guard 의 정의다(헤더 ② 참조).
#
# CLI: Rscript emission_report_gate.R [--ym YYYYMM] [--dir <factor_db dir>] [--top 5]
#   stdout 마지막 줄: EMISSION_GATE status=<OK|REGRESS|UNMEASURED> ym=<ym> n=<N> top=<a,b,..>
#   exit 0 = OK · 3 = REGRESS · 2 = UNMEASURED(보고서 부재·판독 실패 — OK 로 접지 않는다)
#   --top 기본값 5 = W-02 처방 §4 "이름 상위 5개를 텔레그램에" (도훈 승인 처방의 표시 개수)
#
# 검사: 08_Tests/data/test_rawdata_size_guard.R (emission 픽스처 class_R=1 → REGRESS)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))

#' 순수 판독 — 보고서 1개 → list(status, ym, n, names, verdict, generated)
emission_gate_read <- function(path) {
  if (!file.exists(path))
    return(list(status = "UNMEASURED", reason = paste0("보고서 부재: ", path), n = NA_integer_,
                names = character(0)))
  r <- tryCatch(fromJSON(path, simplifyVector = TRUE), error = function(e) e)
  if (inherits(r, "error"))
    return(list(status = "UNMEASURED", reason = paste0("판독 실패: ", conditionMessage(r)),
                n = NA_integer_, names = character(0)))
  if (!"class_R_regression" %in% names(r))
    return(list(status = "UNMEASURED", reason = "class_R_regression 키 부재(스키마 변경)",
                n = NA_integer_, names = character(0)))
  nm <- sort(as.character(unlist(r$class_R_regression)))
  nm <- nm[!is.na(nm) & nzchar(nm)]
  list(status = if (length(nm)) "REGRESS" else "OK", ym = as.character(r$ym %||% NA),
       n = length(nm), names = nm, verdict = as.character(r$verdict %||% NA))
}

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

emission_gate_line <- function(g, ym, top = 5L) {
  if (identical(g$status, "UNMEASURED"))
    return(sprintf("EMISSION_GATE status=UNMEASURED ym=%s n=NA top=- reason=%s", ym, gsub("\\s+", "_", g$reason)))
  sprintf("EMISSION_GATE status=%s ym=%s n=%d top=%s", g$status, ym, g$n,
          if (g$n) paste(head(g$names, top), collapse = ",") else "-")
}

if (sys.nframe() == 0L && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  .arg <- function(k) { i <- match(k, args); if (is.na(i) || i == length(args)) NULL else args[i + 1L] }
  root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", unset = getwd()))
  ym  <- .arg("--ym") %||% format(Sys.Date(), "%Y%m")
  dir <- .arg("--dir") %||% file.path(root, ".cache", "factor_db")
  top <- as.integer(.arg("--top") %||% 5L)
  g <- emission_gate_read(file.path(dir, sprintf("emission_report_%s.json", ym)))
  if (identical(g$status, "REGRESS"))
    cat(sprintf("[emission_gate] ★%s 회귀 %d종 — 직전 빌드에선 났는데 이번엔 0행: %s\n",
                ym, g$n, paste(g$names, collapse = ", ")))
  cat(emission_gate_line(g, ym, top), "\n", sep = "")
  quit(save = "no", status = switch(g$status, OK = 0L, REGRESS = 3L, 2L))
}
