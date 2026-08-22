# SCREEN_TIER 소급 후보 판정 — 격리 45건 중 '구조 사유 단독' 23건의 **신호 생존** 축.
#
# 분모 선언: 06_Registry/module_quarantine.json::modules 전수(45).
#   구조 단독 = f_grade_reasons 에 drawdown/mdd/turnover/calmar 만 있고 oos/overfit/ic 등 없음.
# 물음: 그중 몇이 `structural ∧ signal_alive` (auto_alpha_gate.R 의 SCREEN_TIER 조건)인가.
#   signal_alive 대리 = oos_retention >= 0.5 (screening tier 관례) ∧ PIT 위반 없음.
#   ★대리지표임을 명시한다 — 정본은 essence_score 재실행이고, 이건 사전 규모 추정이다.
suppressWarnings(suppressMessages({
  library(jsonlite)
}))
q <- fromJSON("06_Registry/module_quarantine.json", simplifyVector = FALSE)
ms <- q$modules
ids <- names(ms)

is_struct_only <- function(v) {
  r <- v$meta$f_grade_reasons
  if (is.null(r)) return(FALSE)
  txt <- paste(unlist(r), collapse = " | ")
  st <- grepl("drawdown|mdd|turnover|calmar|structural|집중|concentration", txt, ignore.case = TRUE)
  sg <- grepl("oos|overfit|placebo|robust|\\bic\\b|signal|port_t|alpha", txt, ignore.case = TRUE)
  st && !sg
}

cand <- ids[vapply(ms, is_struct_only, logical(1))]
cat(sprintf("구조 사유 단독 후보: %d건\n\n", length(cand)))

res <- list()
for (id in cand) {
  v <- ms[[id]]
  p <- v$bt_result_path
  if (is.null(p) || !nzchar(p)) { res[[id]] <- list(st = "경로없음"); next }
  if (!file.exists(p)) { res[[id]] <- list(st = "파일부재"); next }
  bt <- tryCatch(readRDS(p), error = function(e) NULL)
  if (is.null(bt)) { res[[id]] <- list(st = "읽기실패"); next }
  # metrics 에서 oos / port_t 추출
  oos <- NA_real_; pt <- NA_real_; mdd <- NA_real_
  m <- bt$metrics
  if (!is.null(m) && is.data.frame(m) && "metric_name" %in% names(m)) {
    gv <- function(pat) {
      hit <- grep(pat, m$metric_name, ignore.case = TRUE)
      if (length(hit)) suppressWarnings(as.numeric(m$metric_value[hit[1]])) else NA_real_
    }
    oos <- gv("oos"); mdd <- gv("max.*drawdown|^mdd")
  }
  bc <- bt$benchmark_compare
  if (!is.null(bc) && is.data.frame(bc) && "metric_name" %in% names(bc)) {
    hit <- grep("Portfolio_Alpha_t_NW", bc$metric_name)
    if (length(hit)) pt <- suppressWarnings(as.numeric(bc$active_value[hit[1]]))
  }
  res[[id]] <- list(st = "읽음", oos = oos, pt = pt, mdd = mdd)
}

ok <- vapply(res, function(x) identical(x$st, "읽음"), logical(1))
cat(sprintf("bt_result 읽기: 성공 %d · 실패 %d\n", sum(ok), sum(!ok)))
if (any(!ok)) {
  tb <- table(vapply(res[!ok], function(x) x$st, character(1)))
  cat("  실패 사유:", paste(sprintf("%s %d", names(tb), as.integer(tb)), collapse = " · "), "\n")
}
cat("\n")

if (sum(ok) > 0) {
  cat(sprintf("%-34s %8s %8s %8s\n", "strategy_id", "oos", "PORT_t", "mdd"))
  cat(strrep("-", 62), "\n")
  n_alive <- 0L; n_meas <- 0L
  for (id in names(res)[ok]) {
    x <- res[[id]]
    if (is.finite(x$oos)) n_meas <- n_meas + 1L
    alive <- is.finite(x$oos) && x$oos >= 0.5
    if (alive) n_alive <- n_alive + 1L
    cat(sprintf("%-34s %8s %8s %8s%s\n", substr(id, 1, 34),
                ifelse(is.finite(x$oos), sprintf("%.3f", x$oos), "—"),
                ifelse(is.finite(x$pt), sprintf("%.3f", x$pt), "—"),
                ifelse(is.finite(x$mdd), sprintf("%.3f", x$mdd), "—"),
                ifelse(alive, "  ★SCREEN_TIER 후보", "")))
  }
  cat("\n")
  cat(sprintf("★oos 측정 가능 %d/%d · 그중 >=0.5 (신호 생존) %d건\n", n_meas, sum(ok), n_alive))
  if (n_meas == 0) {
    cat("  ⇒ oos 가 bt_result 에도 없다 — SCREEN_TIER 자격은 essence_score 재실행이 필요하다.\n")
    cat("    **후보 부재가 아니라 미측정**이며, 재판정 비용이 규모 판단의 전제다.\n")
  }
}
