source("02_Infrastructure/contracts/required_effect_size.R")
cat("=== 위반 주입: 오늘 실제로 낸 두 오류가 차단되는가 ===\n")
p <- 0L; f <- 0L
chk <- function(nm, expr, want_err) {
  e <- tryCatch({ expr; NULL }, error=function(x) conditionMessage(x))
  ok <- (!is.null(e)) == want_err
  cat(sprintf("  [%s] %-46s %s\n", if (ok) "PASS" else "FAIL", nm,
              if (is.null(e)) "통과" else paste0("차단: ", substr(e,1,58))))
  if (ok) p <<- p+1L else f <<- f+1L
}
chk("① 시드수를 표본으로 투입 → 차단",
    audit_input(20, "seeds", "measure_result.random25_null_n_seeds", "attribution_verdict", -0.018), TRUE)
chk("② 요약 필드를 판정 근거로 → 차단",
    audit_input(118, "months", "measure_result.n_months", "next_action", -0.018), TRUE)
chk("③ n_kind 누락 → 차단",
    audit_input(118, n_source_field="x", verdict_field="verdict", effect_annual=-0.018), TRUE)
chk("④ 출처 필드 누락 → 차단",
    audit_input(118, "months", "", "attribution_verdict", -0.018), TRUE)
chk("⑤ 정상 입력 → 통과",
    audit_input(118, "months", "measure_result_20260726.n_months", "attribution_verdict", -0.018), FALSE)
cat("\n=== 정상 경로 판정 (FQ-064 올바른 수치) ===\n")
ai <- audit_input(118, "months", "measure_result_20260726.n_months", "attribution_verdict", -0.018)
v  <- audit_verdict(ai, observed_t = -1.267)
cat(sprintf("  verdict=%s\n  필요 연 %+.2f%%\n  읽은 곳: %s\n", v$verdict, v$required$required_annual*100, v$read_from))
cat(sprintf("\n===== %d PASS / %d FAIL =====\n", p, f))
