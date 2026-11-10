# test_trial_budget_rc.R -- 시행 예산 v3.4 판(선택 현실 점검 기준 · programs/trial_budget.R tb_rc_*) (2026-11-10 · 감사 E1)
#   A 계약 연결 — 수치 = grade_v3.json::selection_bias(src_cfg) · 계약 정의 n_eff = log(1 − α)/log Φ(t) 의 역
#   B 정규 근사 — K = 1 = Φ⁻¹(1 − α) · rho 0 ≈ 독립 공식 · K 에 단조 증가 · rho 가 크면 요구 t 가 낮다 · rho 기본값 없음
#   C 최대 변형 수 — 돌려준 K 는 통과 · K + 1 은 미달
#   D 과거 시행 집합 → 계약 그대로(src_check_dirs) — 닮은 변형이면 환산 독립 시행 수 < 시행 수
#   E [돌연변이] rho 를 무시하는 사본이면 B 의 'rho 가 크면 낮다'가 깨진다
root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(root)
suppressPackageStartupMessages(library(data.table))
PASS <- 0L; FAIL <- 0L
chk <- function(ok, name) { if (isTRUE(ok)) { PASS <<- PASS + 1L; cat("  [ok]  ", name, "\n") } else { FAIL <<- FAIL + 1L; cat("  [FAIL]", name, "\n") } }
E <- new.env(); sys.source("02_Infrastructure/programs/trial_budget.R", envir = E)
cfg <- E$tb_rc_cfg(root); sb <- jsonlite::fromJSON("06_Registry/grade_v3.json")$selection_bias
chk(identical(cfg$alpha, sb$alpha) && identical(as.integer(cfg$resamples), as.integer(sb$resamples)), "A1 alpha · 재표집 수 = grade_v3.json::selection_bias")
t5 <- E$tb_rc_required_t(5, cfg$alpha); ne <- log(1 - cfg$alpha) / log(pnorm(t5))
chk(abs(ne - 5) < 1e-9, "A2 n_eff → 요구 t 는 계약 정의(selection_reality_check.R src_check)의 역 — 왕복 일치")
chk(abs(E$tb_rc_required_t_rho(1, 0.5, cfg) - qnorm(1 - cfg$alpha)) < 1e-12, "B1 K = 1 → Φ⁻¹(1 − α)")
r0 <- vapply(c(5, 20), function(k) E$tb_rc_required_t_rho(k, 0, cfg), 0); ind <- qnorm((1 - cfg$alpha)^(1 / c(5, 20)))
chk(all(abs(r0 - ind) < 0.08), sprintf("B2 rho 0 ≈ 독립 공식(몬테카를로 오차 < 0.08 · %s vs %s)", paste(round(r0, 3), collapse = ","), paste(round(ind, 3), collapse = ",")))
ks <- c(1, 2, 5, 10, 50); rk <- vapply(ks, function(k) E$tb_rc_required_t_rho(k, 0.5, cfg), 0)
chk(all(diff(rk) > 0), "B3 요구 t 는 변형 수에 단조 증가")
hi <- E$tb_rc_required_t_rho(20, 0.9, cfg); lo <- E$tb_rc_required_t_rho(20, 0, cfg)
chk(hi < lo - 0.3, sprintf("B4 닮은 변형(rho 0.9)이면 요구 t 가 낮다(%.3f < %.3f) — 닮은 변형은 독립 시행으로 세지 않는다", hi, lo))
chk(inherits(tryCatch(E$tb_rc_required_t_rho(5, NA, cfg), error = function(e) e), "error") && !("rho" %in% names(Filter(Negate(is.symbol), formals(E$tb_rc_required_t_rho)))),
    "B5 rho 는 입력 — 기본값 없음 · NA 거부")
kx <- E$tb_rc_max_variants(2.95, 0.5, cfg, K_max = 200L)
chk(kx >= 1L && E$tb_rc_required_t_rho(kx, 0.5, cfg) <= 2.95 && E$tb_rc_required_t_rho(kx + 1L, 0.5, cfg) > 2.95, sprintf("C1 최대 변형 수 %d — K 통과 · K + 1 미달", kx))
## D 과거 시행 집합(합성 산출 3개 — 둘은 거의 같은 변형)
SB <- gsub("\\\\", "/", tempfile("tbrc_")); dir.create(SB)
ME <- seq(as.Date("2010-02-01"), as.Date("2021-01-01"), by = "month") - 1L; set.seed(7); bm <- rnorm(length(ME), 0.005, 0.05); base <- 0.006 + bm + rnorm(length(ME), 0, 0.02)
mk <- function(nm, s) { d <- file.path(SB, nm); dir.create(d)
  fwrite(data.table(date = ME, ret_net = s), file.path(d, "03_period_returns.csv")); fwrite(data.table(date = ME, benchmark_ret = bm), file.path(d, "05_benchmark_returns.csv")); d }
D <- c(mk("a", base), mk("b", base + rnorm(length(ME), 0, 0.002)), mk("c", base + rnorm(length(ME), 0, 0.002)))
ft <- E$tb_rc_from_trials(D, D[1], root)
chk(ft$n_trials == 3L && is.finite(ft$effective_independent_trials) && ft$effective_independent_trials < 2, sprintf("D1 닮은 변형 3개 → 환산 독립 시행 %.2f < 2(계약 그대로)", ft$effective_independent_trials))
## E 돌연변이
src <- readLines("02_Infrastructure/programs/trial_budget.R", encoding = "UTF-8"); m <- sub("sqrt(rho) * z0 + sqrt(1 - rho) * ", "0 * z0 + 1 * ", src, fixed = TRUE)
fm <- tempfile(fileext = ".R"); writeLines(m, fm, useBytes = TRUE); EM <- new.env(); sys.source(fm, envir = EM)
chk(sum(m != src) == 1L && abs(EM$tb_rc_required_t_rho(20, 0.9, cfg) - EM$tb_rc_required_t_rho(20, 0, cfg)) < 1e-9, "E1 rho 를 무시하는 사본(치환 1곳)이면 B4 가 깨진다 — B4 가 그 결함을 본다")
unlink(SB, recursive = TRUE)
cat(sprintf('{"test":"trial_budget_rc","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL)); if (FAIL) quit(status = 1)
