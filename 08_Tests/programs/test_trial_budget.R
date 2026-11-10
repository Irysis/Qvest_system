# test_trial_budget.R -- 시행 예산 계산 도구(programs/trial_budget.R) (2026-11-10 · v10.2)
#
# 지키는 것:
#   라운드 설계 때 '몇 칸까지 재도 되는가'를 등급 계약의 DSR 함수 그대로 계산한다. 이 도구가 계약과 다른 식을 쓰거나
#   시행 수를 반영하지 않으면 계획 수치가 판정과 어긋나고, 변형 수 상한의 근거가 거짓이 된다.
#
# 축:
#   A  계약 연결 — DSR 함수를 계약 소스에서 꺼낸다 · 관문 값은 정본 설정에서 읽는다
#   B  왕복 — 최소 SR 에서 DSR = 관문 값(오차 1e-6) · 시행 1회면 최소 SR 0
#   C  단조 — 시행 수가 늘면 필요한 SR 이 오른다 · 관측이 길면 내린다
#   D  최대 시행 수 — 돌려준 N 에서는 통과 · N + 1 에서는 미달 · (a)(b) 정합
#   E  [위반 주입] 시행 수를 무시하는 DSR 사본을 넣으면 C 가 깨진다(이 검사가 그 결함을 본다)
#
# 방식: 계산만(파일 쓰기 없음 · 측정 없음).

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
root <- gsub("\\\\", "/", root)

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
done <- function() {
  cat(sprintf('{"test":"trial_budget","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
  if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L)
}

TOOL <- file.path(root, "02_Infrastructure", "programs", "trial_budget.R")
CFG  <- file.path(root, "02_Infrastructure", "worktask", "constraint_defaults.json")
if (!file.exists(TOOL) || !file.exists(CFG)) { ng("대상 소스 · 설정 부재"); done() } else {
  E <- new.env(parent = globalenv()); sys.source(TOOL, envir = E)

  cat("== A 계약 연결 ==\n")
  fn <- tryCatch(E$tb_load_dsr(root), error = function(e) e)
  chk(is.function(fn) && all(c("sr_ann", "n_obs", "n_trials", "skew", "kurt") %in% names(formals(fn))), "A1 DSR 함수를 계약 소스에서 꺼냈다")
  dm <- tryCatch(E$tb_dsr_min(root), error = function(e) NA_real_)
  cfg <- jsonlite::fromJSON(CFG, simplifyVector = FALSE)$tier_graduation$min_deflated_sharpe_ratio
  chk(is.finite(dm) && identical(as.numeric(dm), as.numeric(cfg)), sprintf("A2 관문 값 = 정본 설정(%s)", as.character(cfg)))
  chk(inherits(tryCatch(E$tb_load_dsr(file.path(tempdir(), "no_such_root")), error = function(e) e), "error"), "A3 계약이 없으면 멈춘다(식을 지어내지 않는다)")

  if (!is.function(fn) || !is.finite(dm)) { done() } else {
    N_OBS <- 300L
    cat("== B 왕복 ==\n")
    for (n in c(5L, 50L, 250L)) {
      s <- E$tb_min_sr(n, N_OBS, dsr_min = dm, dsr_fn = fn)
      chk(is.finite(s) && abs(fn(s, N_OBS, n, 0, 3, A = 12) - dm) < 1e-6, sprintf("B1 시행 %d — 최소 SR %.3f 에서 DSR = 관문 값", n, s))
    }
    chk(identical(E$tb_min_sr(1L, N_OBS, dsr_min = dm, dsr_fn = fn), 0), "B2 시행 1회(스윕 아님)면 최소 SR 0")

    cat("== C 단조 ==\n")
    Ns <- c(1L, 5L, 20L, 100L, 250L, 1000L)
    ms <- vapply(Ns, function(n) E$tb_min_sr(n, N_OBS, dsr_min = dm, dsr_fn = fn), numeric(1))
    chk(all(diff(ms) > 0), sprintf("C1 시행 수가 늘면 필요한 SR 이 오른다(%s)", paste(sprintf("%.3f", ms), collapse = " < ")))
    chk(E$tb_min_sr(250L, 600L, dsr_min = dm, dsr_fn = fn) < E$tb_min_sr(250L, 300L, dsr_min = dm, dsr_fn = fn), "C2 관측이 길면 필요한 SR 이 내린다")

    cat("== D 최대 시행 수 ==\n")
    for (s in c(0.4, 0.5, 0.6)) {
      n <- E$tb_max_trials(s, N_OBS, dsr_min = dm, dsr_fn = fn)
      chk(n >= 1 && fn(s, N_OBS, n, 0, 3, A = 12) >= dm && fn(s, N_OBS, n + 1, 0, 3, A = 12) < dm, sprintf("D1 활성 SR %.1f — N = %d 통과 · N + 1 미달", s, as.integer(n)))
    }
    chk(E$tb_max_trials(E$tb_min_sr(100L, N_OBS, dsr_min = dm, dsr_fn = fn) + 1e-9, N_OBS, dsr_min = dm, dsr_fn = fn) >= 100, "D2 (a)에서 구한 SR 로 (b)를 구하면 그 시행 수 이상")
    chk(identical(E$tb_max_trials(-0.5, N_OBS, dsr_min = dm, dsr_fn = fn), 0), "D3 SR 이 음수면 0(한 칸도 못 잰다는 뜻이 아니라 DSR 관문을 넘을 수 없다)")
    tb <- tryCatch(E$tb_table(N_OBS, root = root), error = function(e) NULL)
    chk(is.data.frame(tb) && all(c("n_trials", "min_active_sr_ann", "approx_t") %in% names(tb)) && all(diff(tb$approx_t) > 0), "D4 표 — 시행 수 · 최소 SR · 근사 t(단조)")

    cat("== E 위반 주입 ==\n")
    blind <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, A = 12) fn(sr_ann, n_obs, 1, skew, kurt, A = A)   # 시행 수를 버린다
    mb <- vapply(Ns, function(n) E$tb_min_sr(n, N_OBS, dsr_min = dm, dsr_fn = blind), numeric(1))
    chk(!all(diff(mb) > 0), "E1 시행 수를 무시하는 DSR 사본이면 필요한 SR 이 오르지 않는다 — C1 이 이것을 잡는다")
    done()
  }
}
