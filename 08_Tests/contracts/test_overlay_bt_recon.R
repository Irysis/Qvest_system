#!/usr/bin/env Rscript
## ============================================================================
## test_overlay_bt_recon.R — 재구성 어댑터 위반 주입 검사기 (v9.2 §8-S2 [8])
##
## 규약 "검사기는 양방향으로 재라"(feedback-verify-both-directions-always):
##   양성 대조(T1~T6, T11) + **위반 주입**(T7~T10). "경고 0" 보고 순간이 최고 위험이다.
##
## ★T6 이 이 파일의 심장이다 — 원판(daily_native) MDD 와 재구성판(monthly_recon) MDD 의
##   차가 0.05 를 넘는다는 **실재 사실**을 못박는다. 이 사실이 basis 방화벽의 근거이고,
##   방화벽이 없으면 오버레이가 아무 일도 하지 않아도 ΔMDD ≤ −0.03 문턱을 통과한다.
##   T6 이 깨진다면 방화벽 전제가 바뀐 것이므로 사다리 판정 규약을 다시 봐야 한다.
##
## ★마지막 줄은 반드시 JSON 요약이다 — 러너가 JSON 만 집계한다.
##   (2026-08-23 실측: 텍스트만 낸 27건이 UNREPORTED 로 실패 계상됐다.)
##
## 실행: Rscript 08_Tests/contracts/test_overlay_bt_recon.R
##   고정 fixture 교체: OBR_TEST_BASE=<bt_result.rds 경로>
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite); library(arrow)
})

.t_root <- local({
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/contracts/overlay_bt_recon.R"))]
  if (!length(hit)) stop("[test_overlay_bt_recon] project root 미발견")
  hit[1]
})
setwd(.t_root)

Sys.setenv(QVEST_DRAIN_NORUN = "1")     # drain 어댑터는 로더만 재사용(CLI 미발화)
suppressMessages({
  source("02_Infrastructure/regime/overlay_candidate_drain.R")
  source("02_Infrastructure/contracts/overlay_bt_recon.R")
})

## ── 채점기 ──────────────────────────────────────────────────────────────────
.RES <- list()
ok <- function(id, desc, cond, detail = "") {
  pass <- isTRUE(cond)
  .RES[[length(.RES) + 1L]] <<- list(id = id, pass = pass, desc = desc, detail = detail)
  cat(sprintf("[%s] %-4s %s%s\n", if (pass) "PASS" else "FAIL", id, desc,
              if (nzchar(detail)) paste0(" — ", detail) else ""))
  invisible(pass)
}
try_case <- function(id, desc, fn) {
  r <- tryCatch(fn(), error = function(e) structure(list(msg = conditionMessage(e)), class = "tcerr"))
  if (inherits(r, "tcerr")) ok(id, desc, FALSE, paste("예외:", r$msg)) else invisible(r)
}

## data.table 참조 의미론 차단 — 주입 케이스가 서로를 오염시키지 않게 깊은 사본
.tcopy <- function(bt) {
  out <- lapply(bt, function(x) if (data.table::is.data.table(x)) data.table::copy(x) else x)
  class(out) <- class(bt)
  out
}
.chk <- function(bt, nm) {
  A <- as.data.table(bt$audit)
  r <- A[check_name == nm]
  if (!nrow(r)) return(list(status = NA_character_, severity = NA_character_))
  list(status = as.character(r$status[1]), severity = as.character(r$severity[1]))
}
.metric <- function(bt, nm) {
  v <- as.data.table(bt$metrics)[metric_name == nm, metric_value]
  if (!length(v)) NA_real_ else as.numeric(v[1])
}

## ── fixture ────────────────────────────────────────────────────────────────
## 기본값은 플랜 §8-S2 가 basis 착시를 실측한 바로 그 런이다(MDD 0.5854 → 0.4947).
## 부재 시 최신 런으로 낙하하되 **어떤 fixture 를 썼는지 반드시 출력**한다.
BASE <- Sys.getenv("OBR_TEST_BASE", "stage_artifacts/alpha_search/20260823_171019_40176/bt_result.rds")
if (!file.exists(BASE)) {
  cand <- Sys.glob("stage_artifacts/alpha_search/*/bt_result.rds")
  if (!length(cand)) stop("[test_overlay_bt_recon] fixture 부재 — bt_result.rds 가 하나도 없다 (빈 결과 = 합격 아님)")
  BASE <- cand[order(file.mtime(cand), decreasing = TRUE)][1]
}
cat(sprintf("[fixture] %s\n", BASE))

base_bt <- readRDS(BASE)
dat <- drain_load_bt_result(list(adapter = "bt_result_rds", bt_result_path = BASE))
PR  <- dat$pr_monthly                     # data.table(date, ret_net, benchmark_ret) — 월간

recon <- overlay_bt_recon(PR, BASE, scenario = "bare", strategy_id = "LADDER_TEST_bare",
                          exposure_source = "identity(exposure=1) — basis 대조 전용",
                          pin_tag = "test_fixture")
BT <- recon$bt

## ── T1: bare 재구성이 입력과 all.equal ───────────────────────────────────────
try_case("T1", "bare 재구성 period_returns$ret_net == 입력 월간 ret_net", function() {
  cmp <- all.equal(as.numeric(BT$period_returns$ret_net), as.numeric(PR$ret_net))
  ok("T1", "bare 재구성 period_returns$ret_net == 입력 월간 ret_net", isTRUE(cmp),
     sprintf("n=%d, %s", nrow(BT$period_returns), if (isTRUE(cmp)) "identical" else paste(cmp, collapse = "; ")))
})

## ── T2: 감사 상태 — 재구성 산출물이 계약 감사를 통과한다 ─────────────────────
## ★2026-08-24 원복: 사양(플랜)의 `integrity_status == "PASS"` 로 되돌린다.
##   우회했던 이유가 사라졌다 — audit_bt_result Check 15(lookahead_detector_self_scan)가
##   정의되지 않은 `scan_lookahead` 를 불러 항상 스킵 WARN 을 냈고, 그래서 **모든** 산출물이
##   상시 integrity="WARNING" 이었다(base fixture 자신도 PASS 17 / WARN 1 — PASS 도달 불가).
##   Check 15 를 detect_lookahead 로 배선하면서 PASS 가 실제로 도달 가능해졌다
##   (위반 주입 검사기 = 08_Tests/contracts/test_audit_check15_lookahead_self_scan.R).
##   ★약한 형태(비-PASS ⊆ base 비-PASS)도 **함께** 단언한다 — 문턱이 다시 도달 불가가 되면
##     "무엇이 악화됐는가"를 문턱 실패와 분리해 보여주기 위해서다(우회 재발 방지).
try_case("T2", "integrity_status == PASS ∧ 비-PASS 체크 ⊆ base 비-PASS 체크", function() {
  A <- as.data.table(BT$audit); Ab <- as.data.table(base_bt$audit)
  bad_new  <- sort(unique(A[status != "PASS" & status != "PASS_WITH_NOTES"]$check_name))
  bad_base <- sort(unique(Ab[status != "PASS" & status != "PASS_WITH_NOTES"]$check_name))
  integ <- as.character(BT$manifest$integrity_status[1])
  ok("T2", "integrity_status == PASS ∧ 비-PASS 체크 ⊆ base 비-PASS 체크",
     identical(integ, "PASS") && all(bad_new %in% bad_base),
     sprintf("integrity=%s | recon 비-PASS={%s} | base 비-PASS={%s}", integ,
             paste(bad_new, collapse = ","), paste(bad_base, collapse = ",")))
})

## ── T3: critical FAIL 0 ─────────────────────────────────────────────────────
try_case("T3", "critical & FAIL 0건 ∧ 어댑터 status=OK", function() {
  ok("T3", "critical & FAIL 0건 ∧ 어댑터 status=OK",
     identical(recon$audit_summary$critical_fail_n, 0L) && identical(recon$status, "OK"),
     sprintf("critical_fail_n=%s status=%s", recon$audit_summary$critical_fail_n, recon$status))
})

## ── T4: metric_type 유일값 "backtested" ─────────────────────────────────────
try_case("T4", "metrics$metric_type 유일값 == 'backtested' (enum 준수)", function() {
  u <- unique(as.character(BT$metrics$metric_type))
  ok("T4", "metrics$metric_type 유일값 == 'backtested' (enum 준수)",
     length(u) == 1L && identical(u, "backtested"), sprintf("{%s}", paste(u, collapse = ",")))
})

## ── T5: 사이드카 basis ──────────────────────────────────────────────────────
try_case("T5", "overlay_provenance$basis == 'monthly_recon' ∧ 자본-인용 금지 명기", function() {
  p <- BT$overlay_provenance
  ok("T5", "overlay_provenance$basis == 'monthly_recon' ∧ 자본-인용 금지 명기",
     identical(p$basis, "monthly_recon") && grepl("자본 tier 판정 근거로 인용 불가", p$basis_warning, fixed = TRUE),
     sprintf("basis=%s base_basis=%s", p$basis, p$base_basis))
})

## ── T6: ★basis 차가 실재한다 ────────────────────────────────────────────────
try_case("T6", "원판 daily MDD 와 monthly_recon MDD 차 > 0.05 (basis 착시 실재)", function() {
  mdd_d <- .metric(base_bt, "MDD"); mdd_m <- .metric(BT, "MDD")
  d <- abs(as.numeric(mdd_d) - as.numeric(mdd_m))
  ok("T6", "원판 daily MDD 와 monthly_recon MDD 차 > 0.05 (basis 착시 실재)",
     is.finite(d) && d > 0.05,
     sprintf("daily=%.4f monthly_recon=%.4f diff=%.4f — 오버레이 0 인데도 ΔMDD 문턱(0.03)의 %.1f배",
             mdd_d, mdd_m, d, d / 0.03))
})

## ── T7 (주입): metric_type enum 위반 → Check 10 critical FAIL ───────────────
try_case("T7", "주입 metric_type='overlay_applied_monthly' → Check 10 critical FAIL", function() {
  b <- .tcopy(BT)
  b$metrics[, metric_type := "overlay_applied_monthly"]
  b <- suppressMessages(audit_bt_result(b))
  c10 <- .chk(b, "estimated_metrics_separated_from_backtested")
  ok("T7", "주입 metric_type='overlay_applied_monthly' → Check 10 critical FAIL",
     identical(c10$status, "FAIL") && identical(c10$severity, "critical"),
     sprintf("status=%s severity=%s integrity=%s", c10$status, c10$severity,
             as.character(b$manifest$integrity_status[1])))
})

## ── T8 (주입): annualization_factor=252 → Check 11 FAIL ────────────────────
try_case("T8", "주입 annualization_factor=252 (monthly) → Check 11 critical FAIL", function() {
  b <- .tcopy(BT)
  b$metrics[, annualization_factor := 252]
  b <- suppressMessages(audit_bt_result(b))
  c11 <- .chk(b, "frequency_cadence_consistency")
  ok("T8", "주입 annualization_factor=252 (monthly) → Check 11 critical FAIL",
     identical(c11$status, "FAIL") && identical(c11$severity, "critical"),
     sprintf("status=%s severity=%s", c11$status, c11$severity))
})

## ── T9 (주입): benchmark 한 값 -0.9 → Check 17b FAIL ───────────────────────
try_case("T9", "주입 benchmark_ret[1]=-0.9 → Check 17b(values_plausible) critical FAIL", function() {
  b <- .tcopy(BT)
  b$benchmark_returns[1L, benchmark_ret := -0.9]
  b <- suppressMessages(audit_bt_result(b))
  c17 <- .chk(b, "benchmark_values_plausible")
  ok("T9", "주입 benchmark_ret[1]=-0.9 → Check 17b(values_plausible) critical FAIL",
     identical(c17$status, "FAIL") && identical(c17$severity, "critical"),
     sprintf("status=%s severity=%s", c17$status, c17$severity))
})

## ── T10 (주입): 한 날짜 26종 → Check 18 FAIL ───────────────────────────────
try_case("T10", "주입 holdings 한 날짜 26종 → Check 18(holdings_cap) FAIL", function() {
  b <- .tcopy(BT)
  H <- b$holdings
  d0 <- H[, .N, by = date][which.max(N)]$date[1]
  extra <- copy(H[date == d0][1L])
  extra[, ticker := "AZZZZZZ_INJECT"]
  b$holdings <- rbindlist(list(H, extra), use.names = TRUE, fill = TRUE)
  n_inj <- b$holdings[date == d0, uniqueN(ticker)]
  b <- suppressMessages(audit_bt_result(b))
  c18 <- .chk(b, "holdings_cap")
  ok("T10", "주입 holdings 한 날짜 26종 → Check 18(holdings_cap) FAIL",
     identical(c18$status, "FAIL"),
     sprintf("injected date=%s n_ticker=%d status=%s severity=%s",
             format(d0), n_inj, c18$status, c18$severity))
})

## ── T11: carry_holdings=FALSE → Check 3·18 WARN, critical FAIL 0 ───────────
try_case("T11", "carry_holdings=FALSE → Check 3·18 WARN ∧ critical FAIL 0", function() {
  r2 <- overlay_bt_recon(PR, BASE, scenario = "bare_noholdings",
                         strategy_id = "LADDER_TEST_bare_nohold", carry_holdings = FALSE)
  c3 <- .chk(r2$bt, "rebalance_path_executed"); c18 <- .chk(r2$bt, "holdings_cap")
  ok("T11", "carry_holdings=FALSE → Check 3·18 WARN ∧ critical FAIL 0",
     identical(c3$status, "WARN") && identical(c18$status, "WARN") &&
       identical(r2$audit_summary$critical_fail_n, 0L),
     sprintf("check3=%s check18=%s critical_fail_n=%s status=%s",
             c3$status, c18$status, r2$audit_summary$critical_fail_n, r2$status))
})

## ── 요약 ────────────────────────────────────────────────────────────────────
n_pass <- sum(vapply(.RES, function(x) isTRUE(x$pass), logical(1)))
n_tot  <- length(.RES)
n_fail <- n_tot - n_pass
cat(sprintf("\n[test_overlay_bt_recon] %d/%d PASS (fixture=%s)\n", n_pass, n_tot, BASE))
if (n_fail > 0L)
  for (x in .RES) if (!isTRUE(x$pass)) cat(sprintf("  ✗ %s %s — %s\n", x$id, x$desc, x$detail))

## ★마지막 줄 = JSON 요약 (러너 집계 대상)
cat(sprintf('{"test":"overlay_bt_recon","pass":%d,"fail":%d,"total":%d}\n', n_pass, n_fail, n_tot))
quit(status = if (n_fail > 0L) 1L else 0L)
