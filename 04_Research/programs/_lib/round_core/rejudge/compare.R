## 재판정 결과 대조 — 저장본(라운드 결과 폴더 · 그 판의 evaluate.R 산출) 대 코어 재판정 산출. 타임스탬프를 빼고 바이트 · 구조 대조.
##   제외(기록 필드 · 판정 무관): evaluated_at(시각) · fingerprint.eval / eval_record / groups.*.eval_matches_measure(평가 시점 데이터 지문 = 입력 판본 기록 —
##   오늘 다시 재면 지문이 다르다 · 판정 입력 아님). 그 밖의 차이는 전부 보고한다(차이 = 분류 대상).
## 사용: Rscript compare.R <저장 파일> <재판정 파일> [--json <요약 출력>]
suppressPackageStartupMessages({ library(jsonlite) })
RC_CMP_IGNORE <- c("^evaluated_at$", "^fingerprint\\.eval$", "^fingerprint\\.eval_record$", "^fingerprint\\.groups\\.[^.]+\\.eval_matches_measure$")
rc_json_diff <- function(a, b, path = "", ignore = RC_CMP_IGNORE, out = new.env()) {
  if (is.null(out$d)) out$d <- character(0)
  if (any(vapply(ignore, function(rx) grepl(rx, path), logical(1)))) return(invisible(out))
  add <- function(msg) out$d <- c(out$d, sprintf("%s: %s", if (nzchar(path)) path else "<root>", msg))
  if (is.list(a) && is.list(b)) {
    na <- names(a); nb <- names(b)
    if (!is.null(na) || !is.null(nb)) {
      if (!identical(na, nb)) add(sprintf("키 다름(저장 %s · 재판정 %s)", paste(setdiff(na, nb), collapse = ","), paste(setdiff(nb, na), collapse = ",")))
      if (!identical(na, nb) && setequal(na, nb)) add("키 순서 다름")
      for (k in intersect(na, nb)) rc_json_diff(a[[k]], b[[k]], if (nzchar(path)) paste0(path, ".", k) else k, ignore, out)
    } else {
      if (length(a) != length(b)) add(sprintf("길이 다름 %d ≠ %d", length(a), length(b)))
      for (i in seq_len(min(length(a), length(b)))) rc_json_diff(a[[i]], b[[i]], sprintf("%s[%d]", path, i), ignore, out)
    }
  } else if (!identical(a, b)) {
    sa <- paste(format(unlist(a), digits = 17), collapse = ","); sb <- paste(format(unlist(b), digits = 17), collapse = ",")
    add(sprintf("값 다름(저장 %s · 재판정 %s)", substr(sa, 1, 160), substr(sb, 1, 160)))
  }
  invisible(out)
}
## 텍스트 대조 — 제외 키가 든 줄을 뺀 나머지 줄이 바이트 동일한가(pretty JSON 은 키마다 한 줄)
rc_text_same <- function(fa, fb, drop_rx = '^\\s*"(evaluated_at|eval|eval_record|eval_matches_measure)":') {
  la <- readLines(fa, warn = FALSE, encoding = "UTF-8"); lb <- readLines(fb, warn = FALSE, encoding = "UTF-8")
  ka <- la[!grepl(drop_rx, la)]; kb <- lb[!grepl(drop_rx, lb)]
  list(same = identical(ka, kb), n_a = length(la), n_b = length(lb), n_kept = length(ka), first_diff = if (!identical(ka, kb)) { i <- which(ka[seq_len(min(length(ka), length(kb)))] != kb[seq_len(min(length(ka), length(kb)))])[1]
                                                                                                                           if (is.na(i)) min(length(ka), length(kb)) + 1L else i } else NA_integer_)
}
rc_compare_files <- function(fa, fb) {
  A <- fromJSON(fa, simplifyVector = FALSE); B <- fromJSON(fb, simplifyVector = FALSE)
  d <- rc_json_diff(A, B)$d
  tx <- rc_text_same(fa, fb)
  cells <- function(X) { cs <- X$cells; if (is.null(cs)) return(character(0)); if (!is.null(names(cs))) vapply(names(cs), function(k) sprintf("%s=%s", k, cs[[k]]$verdict %||% "-"), "") else character(0) }
  list(file_a = fa, file_b = fb, n_diff = length(d), diffs = d, text_same_except_ignored = tx$same, text = tx,
       verdict = c(stored = A$verdict %||% NA, core = B$verdict %||% NA), label = c(stored = A$verdict_label %||% NA, core = B$verdict_label %||% NA),
       cell_verdicts_same = identical(cells(A), cells(B)), n_cells = length(cells(A)))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  r <- rc_compare_files(a[1], a[2])
  i <- match("--json", a); if (!is.na(i)) writeLines(toJSON(r, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), a[i + 1L], useBytes = TRUE)
  cat(sprintf("[대조] %s\n  판정 %s / %s · 칸 판정 동일 %s(%d칸) · 구조 차이 %d · 텍스트(제외 줄 빼고) 동일 %s\n", basename(a[1]), r$label[1], r$label[2],
              r$cell_verdicts_same, r$n_cells, r$n_diff, r$text_same_except_ignored))
  if (r$n_diff) cat(paste0("  - ", utils::head(r$diffs, 30), collapse = "\n"), "\n")
}
