#==============================================================================
# test_cdar_lp_solver_parity.R — CDaR_LP(calc_cdar_weights) 솔버 사슬 수리의 양방향 검사
# 2026-09-07 신규 (qepm:CDaR_LP 워커 시간초과 수리 검증)
#
# 검증 대상: 02_Infrastructure/portfolio/advanced_weights.R::calc_cdar_weights
#   수리 = 같은 CDaR LP 를 lpSolve(simplex)로 먼저 풀고, 판정 불가·실패 시 cccp → min-vol 로
#   수리 전과 동일하게 낙하한다. 추정량(목적함수·제약·창·alpha)은 바뀌지 않는다.
#   왜: cccp 밀집 콘 IPM 은 ~T³ (p=25: T=120 2.4 s · T=252 27~36 s). 번역층이 n_days=252 를
#   넘기므로 리밸 260회 × ~32 s ≈ 140 분 > 워커 상한 90 분 → 강화 B2 의 결정적 칸이 entry 마다
#   두 번씩 미측정(2026-09-06/07 실사고).
#
#   [T1] 양성 대조 — 1차 솔버가 실제로 lpSolve 다(.CDAR_LAST 재도출) · 폴백 문장 없음 · 제약 준수
#   [T2] 전후 동치 — 같은 입력에서 수리 전 경로(cccp 강제)와 대조.
#        ★1급 불변식은 **목적값**이다: LP 는 최적해가 유일하지 않을 수 있어(퇴화 평면) 두 솔버가
#        같은 CDaR 를 내는 다른 꼭짓점을 고를 수 있다. 실창 대조(260개월 · cccp 표본 44개월)에서
#        |목적값 차| ≤ 8.1e-8 인데 max|Δw| 는 3개월에서 2e-5~7.7e-5 였다 — 그게 그 모양이다.
#        그래서 목적값은 1e-6 로 조이고, 비중은 2e-5 로 재되 초과 시 목적값 차를 같이 보고해
#        "다른 최적점"과 "다른 문제"를 구분한다(고정 시드 fixture 라 판정은 결정론적).
#   [T3] 시간 상한(양방향) — lpSolve 경로 T=252·p=25 ≤ 3 s ∧ 같은 입력(T=120)에서 cccp 강제 경로가
#        lpSolve 경로보다 ≥ 5× 느리다(상한이 이빨이 있음 — 수리 전 코드는 T3 를 통과하지 못한다)
#   [T4] 위반 주입 — lpSolve 가 실패(status≠0)하면 조용히 넘기지 않고 '[cdar] lpSolve declined' 를
#        호명한 뒤 cccp 로 낙하해 같은 비중을 낸다(사슬 보존)
#   [T5] 감도 — alpha 를 바꾸면 비중이 바뀐다(동치 검사가 EW 퇴화로 초록이 되는 것을 배제)
#   [T6] 로드 로그 — 'Phase 2 pkgs' 줄이 lpSolve 가용 여부를 표시한다
#
# 실행:
#   Rscript 08_Tests/portfolio/test_cdar_lp_solver_parity.R
#   (다른 체크아웃 검증 시: QM_ROOT=<root> 지정)
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

# proj_root 해석 (worktree-aware, sibling test_mvo_turnover_penalty.R 와 동일 패턴)
proj_root <- local({
  marker <- "02_Infrastructure/portfolio/advanced_weights.R"
  cwd0 <- getwd()
  if (file.exists(file.path(cwd0, marker))) return(cwd0)
  r <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  if (file.exists(file.path(r, marker))) return(r)
  cwd0
})
setwd(proj_root)
cat(sprintf("[proj_root] %s\n", proj_root))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", paste(d, collapse = " "), "\n") }
.emit <- function() {
  cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", PASS, FAIL))
  cat(sprintf('{"test":"cdar_lp_solver_parity","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
}

if (!requireNamespace("cccp", quietly = TRUE) || !requireNamespace("lpSolve", quietly = TRUE)) {
  cat("  SKIP  cccp 또는 lpSolve 부재 — 두 경로를 대조할 수 없다\n"); .emit(); quit(save = "no", status = 0)
}

# 대상은 **사설 환경**에 싣는다 (weight_catalog.R::.wc_qepm_env 와 같은 적재 방식 — .CDAR_LAST 가
#   전역이 아니라 정의 환경에 남는지도 같이 본다).
E <- new.env(parent = globalenv())
load_log <- capture.output(sys.source("02_Infrastructure/portfolio/advanced_weights.R", envir = E))
f <- get("calc_cdar_weights", envir = E)

set.seed(20260907)
mk <- function(Tn, p = 25L) {
  fct <- rnorm(Tn, 0.0003, 0.012); beta <- runif(p, 0.6, 1.4)
  R <- matrix(rnorm(Tn * p, 0, 0.015), Tn, p) + outer(fct, beta)
  colnames(R) <- sprintf("A%02d", seq_len(p)); R
}
to_long <- function(R) {
  d <- as.Date("2026-08-31") - rev(seq_len(nrow(R)))
  data.table(Date = rep(d, times = ncol(R)), Ticker = rep(colnames(R), each = nrow(R)), Ret = as.numeric(R))
}
cdar_of <- function(w, R, alpha = 0.95) {   # LP 목적함수를 비중에서 직접 재계산 (솔버 무관)
  q <- 1 + cumsum(as.numeric(R %*% w)); D <- cummax(q) - q
  zs <- sort(unique(c(0, D)))
  min(vapply(zs, function(z) z + sum(pmax(D - z, 0)) / ((1 - alpha) * length(D)), numeric(1)))
}
valid_w <- function(w, tk, max_w) is.numeric(w) && length(w) == length(tk) && identical(names(w), tk) &&
  all(is.finite(w)) && all(w >= -1e-9) && all(w <= max_w + 1e-9) && abs(sum(w) - 1) < 1e-6
run <- function(R, alpha = 0.95, max_w = 1) {
  tk <- colnames(R); t0 <- proc.time()[["elapsed"]]
  lg <- capture.output(w <- f(tk, to_long(R), alpha = alpha, n_days = nrow(R), max_w = max_w))
  list(w = w, sec = proc.time()[["elapsed"]] - t0, log = lg, last = get0(".CDAR_LAST", envir = E, inherits = FALSE))
}
force_cccp <- function(expr) {   # 수리 전 경로 재현: 1차 솔버 플래그만 끈다(코드 경로는 동일)
  old <- get(".HAS_LPSOLVE", envir = E); assign(".HAS_LPSOLVE", FALSE, envir = E)
  on.exit(assign(".HAS_LPSOLVE", old, envir = E), add = TRUE)
  force(expr)
}

R120 <- mk(120L); R252 <- mk(252L)

cat("== [T1] 양성 대조 — 1차 솔버 = lpSolve · 폴백 문장 없음 · 제약 준수 ==\n")
a <- run(R252)
if (identical(a$last$solver, "lpSolve") && identical(as.integer(a$last$T), 252L) && identical(as.integer(a$last$p), 25L))
  ok(sprintf(".CDAR_LAST 재도출: solver=lpSolve T=252 p=25 (%.2fs)", a$last$sec)) else
  ng(".CDAR_LAST 가 lpSolve 를 가리키지 않는다", paste(names(a$last), unlist(a$last)))
if (!any(grepl("LP failed|declined", a$log))) ok("폴백/거절 문장 없음 — 1차에서 풀렸다") else ng("폴백 문장 출력", a$log)
if (valid_w(a$w, colnames(R252), 1)) ok("비중: 이름=티커 · long-only · Σw=1 · ≤max_w") else ng("비중 제약 위반", head(a$w))
if (!exists(".CDAR_LAST", envir = globalenv(), inherits = FALSE))
  ok(".CDAR_LAST 는 정의 환경(사설 env)에만 남는다 — 전역 오염 0") else ng(".CDAR_LAST 가 전역에 새었다")

cat("== [T2] 전후 동치 — 같은 입력 · cccp 강제 경로와 비중·목적값 일치 ==\n")
b_new <- run(R120); b_old <- force_cccp(run(R120))
if (identical(b_old$last$solver, "cccp")) ok("대조군 경로 = cccp (수리 전 유일 경로 재현)") else ng("대조군이 cccp 로 돌지 않았다", b_old$last$solver)
dw <- max(abs(as.numeric(b_new$w[colnames(R120)]) - as.numeric(b_old$w[colnames(R120)])))
dc <- abs(cdar_of(as.numeric(b_new$w[colnames(R120)]), R120) - cdar_of(as.numeric(b_old$w[colnames(R120)]), R120))
# ★목적값이 1급이다 — 비중이 갈려도 목적값이 같으면 그건 같은 LP 의 다른 최적점(퇴화 평면)이다.
if (is.finite(dc) && dc <= 1e-6) ok(sprintf("비중에서 재계산한 CDaR_0.95 목적값 차 = %.2e ≤ 1e-6 — 같은 추정량", dc)) else ng("목적값 불일치 — 다른 문제를 풀고 있다", dc)
if (is.finite(dw) && dw <= 2e-5) ok(sprintf("비중 max|Δw| = %.2e ≤ 2e-5", dw)) else
  ng(sprintf("전후 비중 불일치 (max|Δw| = %.2e · 동시 목적값 차 = %.2e — 목적값이 같으면 퇴화 평면의 다른 꼭짓점)", dw, dc), "")
# max_w 캡이 있는 축(카탈로그 probe fixture 는 ub=0.20)에서도 같은가
c_new <- run(R120, max_w = 0.20); c_old <- force_cccp(run(R120, max_w = 0.20))
dw2 <- max(abs(as.numeric(c_new$w[colnames(R120)]) - as.numeric(c_old$w[colnames(R120)])))
if (is.finite(dw2) && dw2 <= 2e-5 && valid_w(c_new$w, colnames(R120), 0.20)) ok(sprintf("max_w=0.20 에서도 max|Δw| = %.2e ≤ 2e-5 · 캡 준수", dw2)) else ng("max_w=0.20 전후 불일치", dw2)

cat("== [T3] 시간 상한 (양방향) ==\n")
if (a$sec <= 3) ok(sprintf("lpSolve 경로 T=252·p=25: %.2fs ≤ 3s (수리 전 27~36s)", a$sec)) else ng("lpSolve 경로가 느리다", a$sec)
ratio <- b_old$sec / max(b_new$sec, 1e-3)
if (is.finite(ratio) && ratio >= 5) ok(sprintf("같은 입력(T=120)에서 cccp 강제 %.2fs / lpSolve %.3fs = %.0f× ≥ 5× — 상한이 이빨이 있다", b_old$sec, b_new$sec, ratio)) else
  ng("cccp 와 lpSolve 시간 차가 5× 미만 — 상한 검사가 무엇을 재는지 재확인", ratio)

cat("== [T4] 위반 주입 — lpSolve 실패를 조용히 넘기지 않고 cccp 로 낙하 ==\n")
lp_orig <- get("lp", envir = asNamespace("lpSolve"))
assignInNamespace("lp", function(...) list(status = 2L, solution = numeric(0), objval = NA_real_), ns = "lpSolve")
d_inj <- tryCatch(run(R120), error = function(e) list(w = NULL, log = conditionMessage(e), last = NULL, sec = NA))
assignInNamespace("lp", lp_orig, ns = "lpSolve")
if (any(grepl("lpSolve declined", d_inj$log, fixed = TRUE)) && identical(d_inj$last$solver, "cccp"))
  ok("lpSolve status=2 주입 → '[cdar] lpSolve declined' 호명 후 cccp 가 풀었다") else
  ng("주입된 lpSolve 실패가 호명되지 않았거나 cccp 로 낙하하지 않았다", c(d_inj$last$solver, head(d_inj$log, 3)))
dw3 <- if (!is.null(d_inj$w)) max(abs(as.numeric(d_inj$w[colnames(R120)]) - as.numeric(b_old$w[colnames(R120)]))) else NA_real_
if (is.finite(dw3) && dw3 <= 1e-9) ok("낙하 산출 = cccp 강제 산출 (identical 수준)") else ng("낙하 산출이 cccp 경로와 다르다", dw3)
# 복원 확인 — 주입이 남아 있으면 이후 검사·세션이 오염된다
e_chk <- run(R120)
if (identical(e_chk$last$solver, "lpSolve")) ok("주입 복원 — 다시 lpSolve 로 돈다") else ng("주입이 복원되지 않았다", e_chk$last$solver)

cat("== [T5] 감도 — alpha 가 바뀌면 비중이 바뀐다 ==\n")
g <- run(R120, alpha = 0.80)
dw4 <- max(abs(as.numeric(g$w[colnames(R120)]) - as.numeric(b_new$w[colnames(R120)])))
if (is.finite(dw4) && dw4 > 1e-3) ok(sprintf("alpha 0.95→0.80: max|Δw| = %.3f > 1e-3 — 동치 검사는 퇴화 초록이 아니다", dw4)) else ng("alpha 변경에 비중이 안 움직인다", dw4)

cat("== [T6] 로드 로그 ==\n")
if (any(grepl("Phase 2 pkgs:.*lpSolve=", load_log))) ok("'Phase 2 pkgs' 줄이 lpSolve 상태를 표시한다") else ng("로드 로그에 lpSolve 상태 없음", grep("Phase 2 pkgs", load_log, value = TRUE))

.emit()
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
