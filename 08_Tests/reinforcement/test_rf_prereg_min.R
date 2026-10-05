#!/usr/bin/env Rscript
#==============================================================================
# test_rf_prereg_min.R — 유기체 정책 사전등록(rf_prereg.R 확장 · O0a 2026-09-25 · 설계 organic_design_final §3 G3)
#
#   전제: P2-01 판 rf_prereg.R + 06_Registry/prereg/prereg_config.json(선행 배포) — 없으면 FAIL(선행 미배포).
#   G1 [양성] 유기체 사전등록(등록본 직접) 쓰기 → 색인 sha256 · 관문 shadow_ok(ratio ≥ 착수 금지 문턱 · 문턱 출처 = prereg_config.json)
#   G2 같은 id 재기록 → 거부(P2-01 writer 덮어쓰기 거부 · 두 번째 writer 없음)
#   G3 파라미터 변경 = 새 sha → 사전등록 전 관문 refused · 등록하면 새 id 로 shadow_ok(옛 id 는 그대로)
#   G4 검정력 ratio < 문턱 → 관문 undetermined_only('미결 전용')
#   G5 등록본 바이트 변조 → 관문 refused(무결성)
#   G6 기재 sha ≠ 규칙·파라미터 재계산 → 검증 거부(쓰기 0)
#   G7 유기체 문맥(QVEST_ORGANIC_CTX=1) → 레버 스키마 쓰기 거부 · 유기체 스키마는 허용
#   G8 필수 항목(창 순서 · 멈춤 · 사전확률) 위반 → 검증 오류
#   X  돌연변이 — sha 재계산 검사 제거 → G6 red · 검정력 분기 제거 → G4 red · 문맥 봉쇄 제거 → G7 red
# 격리: 임시 root(설정·계약 사본) · 운영 06_Registry/prereg md5 불변.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_prereg_min","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL > 0L) 1L else 0L) }
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
Sys.unsetenv("QVEST_ORGANIC_CTX")
CFG_SRC <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
if (!file.exists(CFG_SRC)) { ng("전제 — P2-01 prereg_config.json 부재(선행 배포 필요)", CFG_SRC); finish() }
OPS_PRE <- list.files(file.path(ROOT, "06_Registry/prereg"), recursive = TRUE, full.names = TRUE)
md5_ops <- function() vapply(OPS_PRE, function(p) unname(tools::md5sum(p)), character(1))
M0 <- md5_ops()
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R")))))
if (!exists("rf_prereg_organic_gate")) { ng("rf_prereg_organic_gate 부재"); finish() }
mk_root <- function(tag) {
  d <- file.path(tempdir(), sprintf("rfpm_%s_%d", tag, Sys.getpid())); unlink(d, recursive = TRUE, force = TRUE)
  for (s in c("02_Infrastructure/contracts", "06_Registry/prereg")) dir.create(file.path(d, s), recursive = TRUE, showWarnings = FALSE)
  writeLines("# marker", file.path(d, "02_Infrastructure/config.R"))
  file.copy(CFG_SRC, file.path(d, "06_Registry/prereg/prereg_config.json"))
  file.copy(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"), file.path(d, "02_Infrastructure/contracts/required_effect_size.R"))
  normalizePath(d, winslash = "/")
}
mk_pr <- function(params = list(n_min = 1L, delta_sigma = 1), ratio = 0.8, rule = "pi_dorm: B2 arm 휴면 — P(a<-δ) > 1-dormant_p", pid = "pi_dorm") {
  sha <- rf_prereg_policy_sha(rule, params); ids <- rf_prereg_organic_id(pid, sha)
  list(schema = RF_PREREG_ORGANIC_SCHEMA, prereg_id = ids$prereg_id, family_id = ids$family_id, status = "registered",
       layer = "organic", organic_layer = "space", framing = "falsification_attempt",
       policy = list(policy_id = pid, rule = rule, params = params, sha = sha),
       hypothesis = list(statement = "B2 해로운 arm 휴면이 (τ₀,τ_D] S 를 악화시키지 않고 칸을 절약한다", mechanism = "블록 안 arm 효과 EB 축소"),
       metrics = list(primary = list(id = "S_tau", direction = "decrease"), secondary = list(list(id = "cells_saved", direction = "increase"))),
       windows = list(tau_0 = "2011-06-30", tau_D = "2016-11-21", source = "픽스처(O0b 재도출 전)"),
       power = list(ratio = ratio, expected_t = ratio * 2.8, power = 0.5, source = "rf_prereg_power(픽스처)"),
       replay_prior = list(policy_type = "dormancy", discovery = 0.58, unreachable = NA, source = "04_Research/meta/axiom_replay out/wp2_report.md(기술값)"),
       criteria = list(success = list("heldout_win >= pol_cfg"), failure = list("discovery_drop > pol_cfg")),
       stop = list("K1~K9 발화"), lookup = list(status = "attached", source = "hypothesis_index(픽스처)", queries = list()))
}

cat("=== G1 [양성] ===\n")
R <- mk_root("g1"); pr <- mk_pr()
w <- tryCatch({ invisible(capture.output(x <- rf_prereg_write(pr, "registered", root = R))); x }, error = function(e) conditionMessage(e))
g <- rf_prereg_organic_gate("pi_dorm", pr$policy$sha, root = R)
cfg <- rf_prereg_config(R)
chk(is.list(w) && file.exists(w$path) && identical(g$mode, "shadow_ok") && identical(g$threshold, cfg$power_gate$ratio_forbidden_below) &&
      grepl("prereg_config.json::power_gate.ratio_forbidden_below", g$threshold_source),
    "G1 등록 → 파일·색인 · 관문 shadow_ok · 문턱 = prereg_config.json power_gate.ratio_forbidden_below(단일 출처)", if (is.list(w)) g$why else w)
pw <- tryCatch(rf_prereg_power(0.004, se = 0.002, root = R), error = function(e) NULL)
chk(is.list(pw) && all(c("ratio", "expected_t", "power") %in% names(pw)), "G1b 검정력 3종은 P2-01 rf_prereg_power(MDE 단일 출처) 로 산출 가능")

cat("\n=== G2 · G3 · G4 · G5 ===\n")
e <- err_of(capture.output(rf_prereg_write(pr, "registered", root = R)))
chk(!is.na(e) && grepl("이미 등록|덮어쓰기", e), "G2 같은 id 재기록 거부(P2-01 writer)", e)
pr2 <- mk_pr(params = list(n_min = 2L, delta_sigma = 1))
g3a <- rf_prereg_organic_gate("pi_dorm", pr2$policy$sha, root = R)
invisible(capture.output(rf_prereg_write(pr2, "registered", root = R)))
g3b <- rf_prereg_organic_gate("pi_dorm", pr2$policy$sha, root = R)
chk(!identical(pr2$policy$sha, pr$policy$sha) && identical(g3a$mode, "refused") && identical(g3b$mode, "shadow_ok") &&
      !identical(pr2$prereg_id, pr$prereg_id) && identical(rf_prereg_organic_gate("pi_dorm", pr$policy$sha, root = R)$mode, "shadow_ok"),
    "G3 파라미터 변경 = 새 sha = 새 id — 등록 전 refused · 등록 뒤 shadow_ok · 옛 판 불변", g3a$why)
pr4 <- mk_pr(params = list(n_min = 3L), ratio = 0.1); invisible(capture.output(rf_prereg_write(pr4, "registered", root = R)))
g4 <- rf_prereg_organic_gate("pi_dorm", pr4$policy$sha, root = R)
chk(identical(g4$mode, "undetermined_only") && isTRUE(g4$ratio < g4$threshold), "G4 ratio 0.1 < 문턱 → undetermined_only(미결 전용 · live 불가)", g4$why)
p5 <- file.path(R, "06_Registry/prereg", paste0(pr4$prereg_id, ".json")); cat(" ", file = p5, append = TRUE)
g5 <- rf_prereg_organic_gate("pi_dorm", pr4$policy$sha, root = R)
chk(identical(g5$mode, "refused") && grepl("무결성|변조", g5$why), "G5 등록본 바이트 변조 → refused(무결성)", g5$why)

cat("\n=== G6 · G7 · G8 ===\n")
pr6 <- mk_pr(params = list(n_min = 9L)); pr6$policy$params$n_min <- 10L   # 기재 sha 는 9 판 — 재계산과 다르다
n_idx <- length(readLines(file.path(R, "06_Registry/prereg/prereg_index.jsonl")))
e6 <- err_of(capture.output(rf_prereg_write(pr6, "registered", root = R)))
chk(!is.na(e6) && grepl("sha 불일치", e6) && length(readLines(file.path(R, "06_Registry/prereg/prereg_index.jsonl"))) == n_idx,
    "G6 기재 sha ≠ 재계산 → 검증 거부 · 색인 불변", e6)
lever <- list(schema = "rf_prereg_v1", prereg_id = "PR-TEST-LEVER", family_id = "FAM-TEST-LEVER", status = "draft", draft_rev = 1, layer = 1)
Sys.setenv(QVEST_ORGANIC_CTX = "1")
e7 <- err_of(capture.output(rf_prereg_write(lever, "draft", root = R)))
pr7 <- mk_pr(params = list(n_min = 7L)); w7 <- err_of(capture.output(rf_prereg_write(pr7, "registered", root = R)))
Sys.unsetenv("QVEST_ORGANIC_CTX")
chk(!is.na(e7) && grepl("유기체 문맥", e7) && is.na(w7), "G7 유기체 문맥 → 레버 스키마 쓰기 거부 · 유기체 스키마 허용", paste(e7, w7))
bad <- mk_pr(params = list(n_min = 8L)); bad$windows$tau_0 <- "2017-01-01"; bad$stop <- list(); bad$replay_prior$discovery <- 1.5
v8 <- rf_prereg_validate(bad, "registered", root = R)
chk(!v8$ok && any(grepl("tau_0 < tau_D", v8$errors)) && any(grepl("stop", v8$errors)) && any(grepl("replay_prior", v8$errors)),
    "G8 창 순서·멈춤·사전확률 위반 → 검증 오류 3종", paste(v8$errors, collapse = " | "))
bad9 <- mk_pr(params = list(n_min = 11L)); bad9$policy$note <- list(essence = list(port_t = 3))
chk(!rf_prereg_validate(bad9, "registered", root = R)$ok, "G8b essence 객체를 실은 사전등록 거부(AX-008)")

cat("\n=== X 돌연변이 ===\n")
mut_fn <- function(f, from, to) { src <- deparse(f, width.cutoff = 500L); mut <- sub(from, to, src, fixed = TRUE)
  if (sum(src != mut) != 1L) return(NULL); g2 <- eval(parse(text = mut)); environment(g2) <- environment(f); g2 }
m1 <- mut_fn(.rfp_validate_organic, "if (!identical(po$sha, want))", "if (FALSE)")
if (is.null(m1)) ng("X1 돌연변이 주입 실패") else {
  keep <- .rfp_validate_organic; .rfp_validate_organic <- m1
  e <- err_of(capture.output(rf_prereg_write(pr6, "registered", root = R))); .rfp_validate_organic <- keep
  chk(is.na(e) || !grepl("sha 불일치", e), "X1 [돌연변이] sha 재계산 검사 제거 → 변조 sha 판이 통과(또는 다른 오류) = G6 이 이 결함을 잡는다", e)
}
m2 <- mut_fn(rf_prereg_organic_gate, "if (r < thr)", "if (FALSE)")
if (is.null(m2)) ng("X2 돌연변이 주입 실패") else {
  R2 <- mk_root("x2"); p2 <- mk_pr(params = list(n_min = 3L), ratio = 0.1); invisible(capture.output(rf_prereg_write(p2, "registered", root = R2)))
  chk(identical(m2("pi_dorm", p2$policy$sha, root = R2)$mode, "shadow_ok"), "X2 [돌연변이] 검정력 분기 제거 → 저검정력 정책이 shadow_ok = G4 가 이 결함을 잡는다")
}
m3 <- mut_fn(.rfp_organic_ctx_guard, 'if (identical(Sys.getenv("QVEST_ORGANIC_CTX", ""), "1")', 'if (FALSE')
if (is.null(m3)) ng("X3 돌연변이 주입 실패") else {
  keep <- .rfp_organic_ctx_guard; .rfp_organic_ctx_guard <- m3; Sys.setenv(QVEST_ORGANIC_CTX = "1")
  e <- err_of(capture.output(rf_prereg_write(lever, "draft", root = R))); Sys.unsetenv("QVEST_ORGANIC_CTX"); .rfp_organic_ctx_guard <- keep
  chk(is.na(e) || !grepl("유기체 문맥", e), "X3 [돌연변이] 문맥 봉쇄 제거 → 유기체 문맥이 레버 사전등록 경로에 들어간다 = G7 이 이 결함을 잡는다", e)
}
chk(identical(md5_ops(), M0), "Z1 운영 06_Registry/prereg 전 파일 md5 불변")
finish()
