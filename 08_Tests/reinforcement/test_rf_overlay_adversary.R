#!/usr/bin/env Rscript
# test_rf_overlay_adversary.R — 오버레이 적대 반증 양방향 검사 (G2 · 2026-09-17)
#
# 재는 것:
#   A 해석적 양성 대조 — 지연 정보로 짠 진짜 타이밍(합성 2국면 시장)은 T3·T4 를 통과한다
#   B 같은 평균 노출의 임의 타이밍은 T3 에서 떨어진다 · 돌연변이(분위 대신 **평균**과 비교)는 그 칸을 통과시킨다 = 검사가 잡는다
#   C 정적 디레버리지(상수 E)는 T4 에서 떨어진다(T3 도)
#   D 블록 길이 규칙 · 원형 블록 순열의 다중집합 보존 · Calmar 식이 계약(backtest_result_contract)과 같은 식
#   E T1/T2 변형 스펙 — 필드가 서고 원본은 불변 · 자기 층 제거가 `$` 부분 일치에 안 걸린다
#   F 원장 writer(격리 사본) — 없는 attempt/entry 거부 · 다른 필드(essence·grade) 보존 · 이력 누적
#   G 전체 파이프라인(격리 root · 합성 산출물) — 후보 선정 · 바닥 서명 식별 · not_candidate 기록 · dry_run 원장 무접촉 ·
#     live 기록 · 엔진 미지원 시 T1 skipped → verdict error(조용한 통과 없음)
#   H T3b 횡단면 placebo — 지연 정보 배분은 통과 · 임의 배분은 실패 (합성 RAWDATA 주입)
#   I T1/T2 종단 — 엔진 옵션·L-code 스위치가 서 있을 때만(아니면 SKIP 명시)
# 부작용 없음: 픽스처 전부 tempdir. 운영 원장·산출물·설정 무접촉.
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
skip <- function(m, why) { SKIP <<- SKIP + 1L; cat("  SKIP", m, "—", why, "\n") }

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R")))))
.adv_load_deps(ROOT)

# ── 합성 시장: 2국면 마코프(평온 μ+ σ낮음 / 스트레스 μ− σ높음) ──────────────────────
#   ★장기 CAGR 이 양수여야 한다(정상 지속 0.995 · 스트레스 0.98 → 평온 몫 ≈ 80%). 첫 판(대칭 0.97)은 CAGR 이
#   음수라 Calmar 가 "높을수록 좋다" 가 아니었다 — 낙폭을 줄이면 음의 Calmar 가 **더** 음수가 되어 진짜 타이밍이
#   placebo 에 졌다(A1·A2 실패 2026-09-17). 국면 지속(스트레스 ≈ 50거래일)이 있어야 한 달 지연 정보에 예측력이 생긴다.
mk_market <- function(seed, n_months = 240L, p_calm = 0.995, p_stress = 0.98) {
  set.seed(seed)
  days <- seq(as.Date("2005-01-03"), by = "day", length.out = n_months * 31L)
  days <- days[as.integer(format(days, "%w")) %in% 1:5]
  ym <- format(days, "%Y-%m"); days <- days[ym %in% unique(ym)[seq_len(n_months)]]
  n <- length(days); s <- integer(n); s[1] <- 1L
  for (i in 2:n) { p <- if (s[i - 1L] == 1L) p_calm else p_stress; s[i] <- if (runif(1) < p) s[i - 1L] else 3L - s[i - 1L] }
  mu <- ifelse(s == 1L, 0.0010, -0.0020); sd <- ifelse(s == 1L, 0.009, 0.025)
  r <- rnorm(n, mu, sd)
  exec <- days[!duplicated(format(days, "%Y-%m"))]               # 월 첫 거래일 = 집행일
  list(days = days, r = r, exec = exec, state = s)
}
# 지연 정보 타이밍: 기간 p 의 노출 = 직전 달 실현변동성이 확장창 중앙값보다 높으면 낮춘다
lagged_timing <- function(M) {
  pid <- findInterval(M$days, M$exec); P <- length(M$exec)
  vol <- vapply(seq_len(P), function(k) stats::sd(M$r[pid == k]), numeric(1))
  E <- rep(1, P)
  for (k in 2:P) { med <- stats::median(vol[1:(k - 1L)]); E[k] <- min(1, max(0.1, med / vol[k - 1L])) }
  E
}
prep <- function(M) { px <- .adv_period_index(M$days, M$exec)
  list(r = M$r[px$keep], pid = px$pid[px$keep], exec_pos = match(px$exec_pos, which(px$keep))) }

cat("=== A. 양성 대조 — 지연 정보 타이밍 ===\n")
M <- mk_market(11L); P <- prep(M); E_true <- lagged_timing(M)
t3 <- adv_t3_placebo(P$r, P$pid, E_true, P$exec_pos, 0.0015, n_placebo = 200L, alpha = 0.05, seed = 1L)
t4 <- adv_t4_static(P$r, P$pid, E_true, P$exec_pos, 0.0015, obs_calmar = t3$obs_calmar)
if (identical(t3$status, "pass")) ok(sprintf("A1 T3 pass — obs %.3f > q95 %.3f (p %.3f · b=%d)", t3$obs_calmar, t3$placebo_q, t3$p_value, t3$block_len)) else
  ng("A1 진짜 타이밍이 placebo 를 못 넘었다", sprintf("obs %.3f q %.3f", t3$obs_calmar, t3$placebo_q))
if (identical(t4$status, "pass")) ok(sprintf("A2 T4 pass — obs %.3f > const %.3f (E̅ %.3f)", t4$obs_calmar, t4$const_calmar, t4$mean_E)) else
  ng("A2 진짜 타이밍이 정적 등가를 못 넘었다")
fl <- adv_calmar_from_ret(P$r)
if (t3$obs_calmar > fl$calmar) ok(sprintf("A3 근사 경로 Calmar %.3f > 바닥 %.3f (개선이 있어야 후보다)", t3$obs_calmar, fl$calmar)) else ng("A3 픽스처가 개선을 못 만든다")
if (abs(mean(t3$placebo) - mean(t3$placebo)) < 1e-12 && length(t3$placebo) == 200L) ok("A4 placebo 200개 산출") else ng("A4 placebo 개수")
t5 <- adv_t5_episode(P$r, adv_exposure_path(P$r, P$pid, E_true, P$exec_pos, 0.0015), M$days[.adv_period_index(M$days, M$exec)$keep])
if (is.finite(t5$share_largest) && t5$n_episodes >= 1L && nzchar(t5$largest$peak)) ok(sprintf("A5 T5 보고 — 에피소드 %d · 최대 %s→%s · 몫 %.2f", t5$n_episodes, t5$largest$peak, t5$largest$trough, t5$share_largest)) else ng("A5 T5 보고 결측")

cat("=== B. 임의 타이밍 — 같은 평균 노출 ===\n")
# 여러 시드에서 재 본다: 정확한 규칙은 5% 근방만 통과시켜야 하고, 돌연변이(평균 비교)는 절반 가까이 통과시킨다
res_b <- lapply(1:20, function(s) { set.seed(100L + s); Er <- sample(E_true)
  z <- adv_t3_placebo(P$r, P$pid, Er, P$exec_pos, 0.0015, n_placebo = 200L, alpha = 0.05, seed = s)
  list(real = identical(z$status, "pass"), mutant = is.finite(z$obs_calmar) && z$obs_calmar > mean(z$placebo, na.rm = TRUE),
       mean_E_same = abs(mean(Er) - mean(E_true)) < 1e-12) })
n_real <- sum(vapply(res_b, `[[`, logical(1), "real")); n_mut <- sum(vapply(res_b, `[[`, logical(1), "mutant"))
if (all(vapply(res_b, `[[`, logical(1), "mean_E_same"))) ok("B1 순열 노출의 평균은 원본과 같다(노출 짝맞춤)") else ng("B1 평균 노출이 달라졌다")
if (n_real <= 3L) ok(sprintf("B2 임의 타이밍 20건 중 T3 통과 %d (≤3 · 명목 5%%)", n_real)) else ng("B2 임의 타이밍이 너무 자주 통과", as.character(n_real))
if (n_mut >= 6L && n_mut > n_real) ok(sprintf("B3 돌연변이(평균 비교)는 %d/20 통과 — 분위 규칙과 갈린다 = 검사가 잡는다", n_mut)) else
  ng("B3 돌연변이가 정확한 규칙과 구분되지 않는다", sprintf("mutant %d real %d", n_mut, n_real))
if (grepl("quantile", t3$decision_rule, fixed = TRUE) && !grepl("mean(placebo", t3$decision_rule, fixed = TRUE)) ok("B4 결정 규칙 문자열이 분위를 명시한다") else ng("B4 결정 규칙 서술")

cat("=== C. 정적 디레버리지 ===\n")
E_c <- rep(mean(E_true), length(E_true))
t3c <- adv_t3_placebo(P$r, P$pid, E_c, P$exec_pos, 0.0015, n_placebo = 50L, seed = 2L)
t4c <- adv_t4_static(P$r, P$pid, E_c, P$exec_pos, 0.0015, obs_calmar = t3c$obs_calmar)
if (identical(t4c$status, "fail") && abs(t4c$obs_calmar - t4c$const_calmar) < 1e-9) ok("C1 상수 노출은 T4 에서 떨어진다(obs == const)") else ng("C1 상수 노출이 T4 를 통과", t4c$status)
if (identical(t3c$status, "fail")) ok("C2 상수 노출은 T3 에서도 떨어진다(순열이 자기 자신)") else ng("C2 상수 노출이 T3 통과")

cat("=== D. 블록 길이 · 순열 · Calmar 식 ===\n")
bl <- adv_block_len(numeric(259), rule = "hhj1995")
if (identical(bl$b, 7L) && grepl("hhj1995", bl$rule)) ok("D1 HHJ(1995) n=259 → b=7 = ceiling(259^(1/3))") else ng("D1 블록 길이", paste(bl$b, bl$rule))
bla <- adv_block_len(E_true, rule = "auto")
if (bla$b >= 1L && nzchar(bla$rule)) ok(sprintf("D2 auto 규칙 → %s (b=%d · np 설치=%s)", bla$rule, bla$b, requireNamespace("np", quietly = TRUE))) else ng("D2 auto 규칙")
set.seed(5L); x <- rnorm(101); y <- adv_circular_block_perm(x, 7L)
if (length(y) == 101L && isTRUE(all.equal(sort(x), sort(y))) && !identical(x, y)) ok("D3 원형 블록 순열 — 길이·다중집합 보존 · 순서는 바뀐다") else ng("D3 순열 성질")
# 블록 안 인접쌍은 보존된다: 원본 인접쌍 집합의 대부분이 순열에도 남는다
pairs <- function(v) paste(head(v, -1), tail(v, -1))
if (mean(pairs(y) %in% pairs(x)) > 0.8) ok("D4 블록 안 자기상관 보존(인접쌍 80%+ 유지)") else ng("D4 인접쌍 보존율 낮음")
cm <- adv_calmar_from_ret(c(0.1, -0.2, 0.15, 0.05), ann = 252)
nav <- cumprod(1 + c(0.1, -0.2, 0.15, 0.05)); exp_cagr <- nav[4]^(252 / 4) - 1; exp_mdd <- max(1 - nav / cummax(nav))
if (abs(cm$cagr - exp_cagr) < 1e-12 && abs(cm$mdd - exp_mdd) < 1e-12 && abs(cm$calmar - exp_cagr / exp_mdd) < 1e-9)
  ok("D5 Calmar = (NAV_end)^(ann/n)−1 / maxDD — backtest_result_contract.R:401-448 과 같은 식") else ng("D5 Calmar 식")
if (requireNamespace("PerformanceAnalytics", quietly = TRUE)) {
  rr <- xts::xts(P$r, order.by = M$days[.adv_period_index(M$days, M$exec)$keep])
  pa <- as.numeric(PerformanceAnalytics::maxDrawdown(rr))
  if (abs(pa - fl$mdd) < 1e-9) ok("D6 MDD 가 PerformanceAnalytics::maxDrawdown 과 일치") else ng("D6 MDD 불일치", sprintf("%.6f vs %.6f", pa, fl$mdd))
}
pe <- adv_exposure_path(c(0.01, 0.02, 0.03, 0.04), c(1L, 1L, 2L, 2L), c(1, 0.5), c(1L, 3L), 0.0015)
if (isTRUE(all.equal(pe, c(0.01, 0.02, 0.5 * 0.03 - 0.5 * 0.0015, 0.5 * 0.04)))) ok("D7 노출 경로 — E×r · 집행일 |ΔE|×cost · 첫 ΔE 0") else ng("D7 노출 경로", paste(pe, collapse = ","))

cat("=== E. 변형 스펙 · 자기 층 제거 ===\n")
spec0 <- list(code = "B5_16", label = "x", idea = "[무인 병렬 B5_16] x", block = "B5", base_weight = 0.5,
              factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"),
              overlay = list(kind = "dd_brake", arm_id = "dd_brake_q"), overlay_basis = "LLM 설계 · 낙폭",
              base_signal = list(kind = "engine", path = "C:/x/engine.R"))
v1 <- .adv_make_variant_spec(spec0, "T1"); v2 <- .adv_make_variant_spec(spec0, "T2")
if (identical(v1$overlay_shift, 1L) && is.null(v1$overlay_strict) && identical(v1$code, "B5_16") && identical(v1$overlay, spec0$overlay)) ok("E1 T1 스펙: overlay_shift=1 · 코드·오버레이 보존") else ng("E1 T1 스펙")
if (isTRUE(v2$overlay_strict) && is.null(v2$overlay_shift)) ok("E2 T2 스펙: overlay_strict=TRUE") else ng("E2 T2 스펙")
if (is.null(spec0$overlay_shift) && is.null(spec0$overlay_strict) && !grepl("ADVERSARY", spec0$idea)) ok("E3 원본 불변") else ng("E3 원본이 바뀌었다")
if (grepl("^\\[ADVERSARY T1\\]", v1$idea) && identical(v1$adversary$of_code, "B5_16")) ok("E4 표식(idea 접두 · adversary 블록)") else ng("E4 표식")
own <- .adv_own_layers(spec0, NULL)
s0 <- .adv_strip_own(spec0, own)
fl_spec <- spec0; fl_spec$overlay <- NULL; fl_spec$overlay_basis <- NULL
if (length(own) == 1L && is.null(s0$overlay) && "overlay" %in% names(s0) && identical(.adv_norm_sig(s0), .adv_norm_sig(fl_spec)))
  ok("E5 자기 층 제거 후 서명 == 바닥 서명 (overlay_basis 부분 일치 회피)") else ng("E5 서명 불일치", paste(.adv_norm_sig(s0), "|", .adv_norm_sig(fl_spec)))
bad <- spec0; bad$overlay <- NULL
if (!identical(.spec_sig(bad), .spec_sig(fl_spec))) ok("E6 대조 — `$overlay <- NULL` 은 overlay_basis 를 집어 서명이 어긋난다(회피 이유 실증)") else ng("E6 부분 일치 함정이 재현되지 않는다")
carry <- list(kind = "vol_scale", arm_id = "vol_median")
stacked <- spec0; stacked$overlay <- .ov_stack(carry, spec0$overlay)
own2 <- .adv_own_layers(stacked, carry)
if (length(own2) == 1L && identical(own2[[1]]$arm_id, "dd_brake_q")) ok("E7 carry 층은 자기 층이 아니다") else ng("E7 carry 분리")
stacked$overlay_cell <- list(kind = "dd_brake", arm_id = "dd_brake_q")
if (length(.adv_own_layers(stacked, NULL)) == 1L) ok("E8 overlay_cell 이 있으면 그것이 자기 층이다") else ng("E8 overlay_cell")

cat("=== F. 원장 writer (격리 사본) ===\n")
SBX <- file.path(tempdir(), sprintf("rf_adv_%d", Sys.getpid())); dir.create(file.path(SBX, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
mk_ledger <- function(path, extra_attempts = list()) {
  led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
              entries = list(list(base_id = "RP_FIXT_adv", paper_key = "fixture", status = "active", base_grade = "C",
                                  attempts_used = 2L + length(extra_attempts),
                                  attempts = c(list(list(n = 1L, cell_code = "B1_1", grade = "B", essence = list(cell_code = "B1_1", port_t = 2.5, calmar = 0.40)),
                                                    list(n = 2L, cell_code = "B5_16", grade = "B", essence = list(cell_code = "B5_16", port_t = 2.4, calmar = 0.45))),
                                               extra_attempts))))
  write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null"), path)
}
LP <- file.path(SBX, "06_Registry", "reinforce_ledger_l1.json"); mk_ledger(LP)
rd <- function() fromJSON(LP, simplifyVector = FALSE)
r1 <- tryCatch(rf_record_adversary(1L, "RP_FIXT_adv", 2L, list(schema = "rf_overlay_adversary_v1", verdict = "fail", at = "t1", reason = "T3"), root = SBX), error = function(e) e)
a2 <- rd()$entries[[1]]$attempts[[2]]
if (!inherits(r1, "error") && identical(a2$adversary$verdict, "fail") && identical(a2$essence$calmar, 0.45) && identical(a2$grade, "B"))
  ok("F1 adversary 기록 · essence/grade 불변(AX-008)") else ng("F1 기록 실패", if (inherits(r1, "error")) conditionMessage(r1) else "")
if (nzchar(a2$adversary$recorded_at %||% "") && length(a2$adversary$history) == 0L) ok("F2 첫 기록 — history 비어 있음 · recorded_at 존재") else ng("F2 첫 기록 메타")
invisible(rf_record_adversary(1L, "RP_FIXT_adv", 2L, list(verdict = "pass", at = "t2"), root = SBX))
a2 <- rd()$entries[[1]]$attempts[[2]]
if (identical(a2$adversary$verdict, "pass") && length(a2$adversary$history) == 1L && identical(a2$adversary$history[[1]]$verdict, "fail")) ok("F3 덮어써도 직전 판정은 history 에 남는다") else ng("F3 이력 누적")
e1 <- tryCatch({ rf_record_adversary(1L, "RP_FIXT_adv", 99L, list(verdict = "pass"), root = SBX); NULL }, error = function(e) e)
if (inherits(e1, "error") && grepl("attempt", conditionMessage(e1))) ok("F4 없는 attempt 거부") else ng("F4 없는 attempt 통과")
e2 <- tryCatch({ rf_record_adversary(1L, "RP_NOPE", 2L, list(verdict = "pass"), root = SBX); NULL }, error = function(e) e)
if (inherits(e2, "error") && grepl("entry", conditionMessage(e2))) ok("F5 없는 entry 거부") else ng("F5 없는 entry 통과")
e3 <- tryCatch({ rf_record_adversary(1L, "RP_FIXT_adv", 2L, list(note = "no verdict"), root = SBX); NULL }, error = function(e) e)
if (inherits(e3, "error") && grepl("verdict", conditionMessage(e3))) ok("F6 verdict 없는 레코드 거부") else ng("F6 verdict 없는 레코드 통과")
if (identical(rd()$entries[[1]]$attempts[[1]]$essence$port_t, 2.5)) ok("F7 다른 attempt 무변") else ng("F7 다른 attempt 변경")

cat("=== G. 전체 파이프라인 (격리 root · 합성 산출물) ===\n")
FR <- file.path(SBX, "root"); for (d in c("06_Registry", ".cache/rf_parallel", "02_Infrastructure/reinforcement/overlay_arms",
                                          "02_Infrastructure/alpha_search", "02_Infrastructure/ops", "stage_artifacts/replication"))
  dir.create(file.path(FR, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# stub", file.path(FR, "02_Infrastructure/config.R"))
writeLines(c("# stub engine — overlay 없음", "x <- 1"), file.path(FR, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
writeLines(c("# stub runner", "y <- 1"), file.path(FR, "02_Infrastructure/alpha_search/run_paper_replication.R"))
write(toJSON(list(id = "tilt_x", family = "cross_sectional", basis = "b"), auto_unbox = TRUE), file.path(FR, "02_Infrastructure/reinforcement/overlay_arms/tilt_x.arm.json"))
write(toJSON(list(id = "brake_s", family = "drawdown", basis = "b"), auto_unbox = TRUE), file.path(FR, "02_Infrastructure/reinforcement/overlay_arms/brake_s.arm.json"))
write(toJSON(list(fixed_axes = list(commission_bps = 15)), auto_unbox = TRUE), file.path(FR, "06_Registry/reinforce_program.json"))
write(toJSON(list(overlay_adversary = list(enabled = TRUE, alpha = 0.05, n_placebo = 100, max_candidates = 2), worker_timeout_sec = 60), auto_unbox = TRUE),
      file.path(FR, "06_Registry/reinforce_auto_config.json"))
BIDF <- "RP_FIXT_pipe"
# 산출물 — 바닥(E=1) 과 세 셀: true(진짜 타이밍) · rand(임의) · low(바닥 이하 calmar 로 등록)
tk <- sprintf("T%02d", 1:10); nT <- length(tk)
write_art <- function(name, E_vec = NULL, e_mat = NULL) {
  d <- file.path(FR, "stage_artifacts/replication", name); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  keep <- .adv_period_index(M$days, M$exec)$keep
  pr <- data.table(run_id = name, strategy_id = name, date = M$days[keep], frequency = "daily", ret_gross = M$r[keep], ret_net = M$r[keep])
  fwrite(pr, file.path(d, "03_period_returns.csv"))
  H <- CJ(date = M$exec, ticker = tk); H[, target_weight := 1 / nT]
  if (!is.null(E_vec)) H[, target_weight := target_weight * E_vec[match(date, M$exec)]]
  if (!is.null(e_mat)) H[, target_weight := target_weight * e_mat[cbind(match(date, M$exec), match(ticker, tk))]]
  H[, actual_weight := target_weight]
  fwrite(H[target_weight > 0], file.path(d, "04_holdings.csv"))
  d
}
set.seed(77L); E_rand <- sample(E_true)
art_floor <- write_art("art_floor"); art_true <- write_art("art_true", E_true); art_rand <- write_art("art_rand", E_rand); art_low <- write_art("art_low", E_true)
mk_spec <- function(code, block, overlay = NULL) {
  s <- list(code = code, label = code, idea = sprintf("[fixt %s]", code), block = block, base_weight = 0.5,
            factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"),
            base_signal = list(kind = "engine", path = "C:/x/engine.R"))
  if (!is.null(overlay)) { s$overlay <- overlay; s$overlay_basis <- "fixture basis" }
  p <- file.path(FR, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, BIDF))
  write(toJSON(s, auto_unbox = TRUE, pretty = TRUE, null = "null"), p); p
}
sp_floor <- mk_spec("B1_1", "B1"); sp_true <- mk_spec("B5_16", "B5", list(kind = "brake_s", arm_id = "brake_s"))
sp_rand <- mk_spec("B5_17", "B5", list(kind = "brake_s", arm_id = "brake_s")); sp_low <- mk_spec("B5_18", "B5", list(kind = "brake_s", arm_id = "brake_s"))
sp_no <- mk_spec("B5_19", "B5")   # 오버레이 없는 B5 칸(무처치) — 후보가 아니어야 한다
cal_floor <- fl$calmar
led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, current_axis = "n_max_25",
            entries = list(list(base_id = BIDF, paper_key = "fixture", status = "active", base_grade = "C", attempts_used = 5L,
              attempts = list(
                list(n = 1L, cell_code = "B1_1", grade = "B", artifacts = art_floor, essence = list(cell_code = "B1_1", port_t = 2.5, calmar = cal_floor, spec = sp_floor)),
                list(n = 2L, cell_code = "B5_16", grade = "B", artifacts = art_true, essence = list(cell_code = "B5_16", port_t = 2.4, calmar = t3$obs_calmar, spec = sp_true)),
                list(n = 3L, cell_code = "B5_17", grade = "B", artifacts = art_rand, essence = list(cell_code = "B5_17", port_t = 2.3, calmar = cal_floor + 0.01, spec = sp_rand)),
                list(n = 4L, cell_code = "B5_18", grade = "C", artifacts = art_low, essence = list(cell_code = "B5_18", port_t = 1.0, calmar = cal_floor - 0.05, spec = sp_low)),
                list(n = 5L, cell_code = "B5_19", grade = "C", artifacts = art_floor, essence = list(cell_code = "B5_19", port_t = 1.0, calmar = cal_floor + 0.02, spec = sp_no))))))
LPF <- file.path(FR, "06_Registry/reinforce_ledger_l1.json"); write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), LPF)
md0 <- tools::md5sum(LPF)
S <- tryCatch(rf_overlay_adversary_run(BIDF, "B5", 1L, root = FR, dry_run = TRUE, reruns = "auto"), error = function(e) e)
if (inherits(S, "error")) ng("G0 파이프라인이 죽었다", conditionMessage(S)) else {
  if (nrow(S) == 4L) ok("G1 B5 칸 4개 전부 레코드") else ng("G1 레코드 수", as.character(nrow(S)))
  g <- function(cd) S[code == cd]
  if (isTRUE(g("B5_16")$candidate) && isTRUE(g("B5_17")$candidate) && !isTRUE(g("B5_18")$candidate) && !isTRUE(g("B5_19")$candidate))
    ok("G2 후보 = 자기 층 있음 ∧ calmar > 바닥 (B5_16·B5_17) · 바닥 이하(B5_18)·무처치(B5_19)는 아님") else ng("G2 후보 선정", paste(S$candidate, collapse = ","))
  if (identical(g("B5_18")$verdict, "not_candidate") && identical(g("B5_18")$reason, "calmar_not_above_floor") &&
      identical(g("B5_19")$reason, "no_own_overlay_layers")) ok("G3 not_candidate 사유가 구분된다(미검정 ≠ 실패)") else ng("G3 not_candidate 사유", paste(g("B5_18")$reason, g("B5_19")$reason))
  if (identical(g("B5_16")$floor_code, "B1_1") && abs(g("B5_16")$floor_calmar - cal_floor) < 1e-12) ok("G4 바닥 = 서명 일치 B1_1") else ng("G4 바닥 식별", g("B5_16")$floor_code %||% "NA")
  J16 <- fromJSON(g("B5_16")$json, simplifyVector = FALSE); J17 <- fromJSON(g("B5_17")$json, simplifyVector = FALSE)
  if (identical(J16$floor$match, "sig")) ok("G5 바닥 식별 경로 = sig (port_t 폴백 아님)") else ng("G5 바닥 경로", J16$floor$match %||% "NA")
  if (identical(J16$tests$T3$status, "pass") && identical(J16$tests$T4$status, "pass") && identical(J16$analytic_verdict, "pass")) ok("G6 진짜 타이밍 칸 — 해석적 pass") else ng("G6 진짜 타이밍 해석적", J16$analytic_verdict %||% "NA")
  if (identical(J17$analytic_verdict, "fail") && identical(J17$tests$T3$status, "fail")) ok("G7 임의 타이밍 칸 — 해석적 fail (T3)") else ng("G7 임의 타이밍 해석적", paste(J17$analytic_verdict, J17$tests$T3$status))
  if (identical(J16$tests$T1$status, "skipped") && identical(J16$verdict, "error") && grepl("T1", J16$reason)) ok("G8 엔진 미지원 → T1 skipped → verdict error (조용한 통과 없음)") else ng("G8 미지원 처리", paste(J16$tests$T1$status, J16$verdict))
  if (identical(J17$verdict, "fail")) ok("G9 해석적 실패는 재실행 없이도 fail 로 닫힌다") else ng("G9 실패 확정", J17$verdict)
  if (identical(J16$tests$T3b$status, "not_computed") && !isTRUE(J16$vector_observed)) ok("G10 스칼라 칸은 T3b 미계산") else ng("G10 T3b 미계산", J16$tests$T3b$status %||% "NA")
  if (identical(J16$tests$T2$status, "not_applicable")) ok("G11 external_data 없음 → T2 not_applicable") else ng("G11 T2", J16$tests$T2$status %||% "NA")
  if (abs(J16$approximation$floor_approx_gap) < 1e-9) ok("G12 바닥 근사 Calmar == essence(E≡1 이면 정확히 재현)") else ng("G12 바닥 근사 격차", as.character(J16$approximation$floor_approx_gap))
  if (identical(md0, tools::md5sum(LPF))) ok("G13 dry_run — 원장 무변") else ng("G13 dry_run 이 원장을 썼다")
  if (file.exists(file.path(FR, ".cache/rf_overlay_adversary", BIDF, "B5_16", "adversary.json"))) ok("G14 adversary.json 경로 규약") else ng("G14 JSON 경로")
  S2 <- rf_overlay_adversary_run(BIDF, "B5", 1L, root = FR, dry_run = FALSE, reruns = "skip")
  L2 <- fromJSON(LPF, simplifyVector = FALSE)$entries[[1]]$attempts
  av <- function(n) L2[[n]]$adversary
  if (identical(av(2)$verdict, "error") && identical(av(3)$verdict, "fail") && identical(av(4)$verdict, "not_candidate") && identical(av(5)$verdict, "not_candidate"))
    ok("G15 live — 4칸 전부 원장 adversary 표식(pass 0 · fail 1 · error 1 · not_candidate 2)") else ng("G15 live 기록", paste(av(2)$verdict, av(3)$verdict, av(4)$verdict, av(5)$verdict))
  if (identical(av(2)$tests$T1$status, "skipped") && grepl("skipped_by_arg", av(2)$tests$T1$detail)) ok("G16 reruns='skip' 는 사유가 남는다") else ng("G16 skip 사유")
  # essence 는 .rf_write 의 digits=6 직렬화를 거치므로 6자리 동치로 본다(모든 원장 writer 공통 거동)
  if (is.null(av(3)$tests$T3$placebo) && abs(L2[[3]]$essence$calmar - (cal_floor + 0.01)) < 1e-5 && identical(L2[[3]]$grade, "B")) ok("G17 원장엔 placebo 벡터 제외 · essence/grade 불변") else
    ng("G17 원장 슬림·불변", sprintf("placebo null=%s calmar %s grade %s", is.null(av(3)$tests$T3$placebo), L2[[3]]$essence$calmar, L2[[3]]$grade))
  cfg_off <- rf_overlay_adversary_run(BIDF, "B5", 1L, root = FR, cfg = list(enabled = FALSE), dry_run = TRUE)
  if (nrow(cfg_off) == 0L) ok("G18 enabled=false → 무동작") else ng("G18 kill switch")
  # 엔진 지원 감지 — 옵션이 코드 줄에 있을 때만(주석은 안 센다)
  writeLines(c("# overlay_shift 는 주석", "x <- 1"), file.path(FR, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
  if (!isTRUE(.adv_engine_supports(FR)$overlay_shift)) ok("G19 주석 속 overlay_shift 는 지원으로 안 센다") else ng("G19 주석 오탐")
  writeLines(c(".shift <- as.integer(SPEC$overlay_shift %||% 0L)", ".strict <- isTRUE(SPEC$overlay_strict)"), file.path(FR, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
  s3 <- .adv_engine_supports(FR)
  if (isTRUE(s3$overlay_shift) && isTRUE(s3$overlay_strict)) ok("G20 코드 줄의 옵션은 지원으로 센다") else ng("G20 지원 감지")
  # 엔진은 지원하지만 러너가 L-code 스위치를 안 읽으면 → side_effect_guard 로 skipped (강제 재실행 아님)
  S3 <- rf_overlay_adversary_run(BIDF, "B5", 1L, root = FR, dry_run = TRUE, reruns = "auto")
  J16b <- fromJSON(S3[code == "B5_16"]$json, simplifyVector = FALSE)
  if (identical(J16b$tests$T1$status, "skipped") && grepl("side_effect_guard", J16b$tests$T1$detail)) ok("G21 L-code 스위치 미배선 → 재실행 거부(누출 방지) · verdict error") else ng("G21 부작용 가드", J16b$tests$T1$detail %||% J16b$tests$T1$status)
  writeLines(c('if (!identical(Sys.getenv("QVEST_RP_NO_LCODE", "0"), "1")) z <- 1'), file.path(FR, "02_Infrastructure/alpha_search/run_paper_replication.R"))
  if (isTRUE(.adv_rp_honors_lcode_switch(FR))) ok("G22 러너가 QVEST_RP_NO_LCODE 를 읽으면 감지된다") else ng("G22 스위치 감지")
}

cat("=== H. T3b 횡단면 placebo (합성 RAWDATA 주입) ===\n")
# 종목별 변동성 군집: 종목 i 의 국면은 시장 국면 + 종목 고유 국면. 지연 정보 배분 = 직전 달 종목 실현변동성 순위로 e_i 차등
mk_xs <- function(seed, p_calm = 0.995, p_stress = 0.98) {          # 시장과 같은 이유로 장기 CAGR 양수(평온 몫 ≈ 80%)
  set.seed(seed); n <- length(M$days)
  own <- lapply(seq_len(nT), function(i) { s <- integer(n); s[1] <- 1L
    for (t in 2:n) { p <- if (s[t - 1L] == 1L) p_calm else p_stress; s[t] <- if (runif(1) < p) s[t - 1L] else 3L - s[t - 1L] }; s })
  R <- rbindlist(lapply(seq_len(nT), function(i) {
    st <- own[[i]]; mu <- ifelse(st == 1L, 0.0008, -0.0025) + M$r * 0.5; sd <- ifelse(st == 1L, 0.010, 0.028)
    data.table(Date = M$days, Ticker = tk[i], Ret = rnorm(n, mu, sd)) }))
  R
}
RAW <- mk_xs(3L)
loader <- function(tickers, from, to) RAW[Ticker %in% tickers & Date >= as.Date(from) & Date <= as.Date(to)]
HF <- CJ(date = M$exec, ticker = tk)[, w := 1 / nT]
HP <- .adv_holding_period_returns(HF, M$days, loader)
# 지연 정보: 기간 k 의 e_i = 직전 기간 종목 실현변동성 순위 (높을수록 낮은 e) — 정보는 k−1 까지만
RAW[, pid := findInterval(Date, M$exec)]
V <- RAW[pid >= 1L, .(vol = stats::sd(Ret)), by = .(pid, ticker = Ticker)]
V[, rk := frank(vol) / .N, by = pid]; V[, pid := pid + 1L]     # 다음 기간에 적용 = 지연 1
Hh <- merge(HP, V[, .(pid, ticker, rk)], by = c("pid", "ticker"), all.x = TRUE)
Hh[, e := fifelse(is.finite(rk), 1 - 0.8 * rk, 1)]
Hh <- Hh[is.finite(R)]
z_true <- adv_t3b_xs(Hh, 0.0015, n_placebo = 150L, alpha = 0.05, seed = 9L)
if (identical(z_true$status, "pass")) ok(sprintf("H1 지연 정보 횡단면 배분 — T3b pass (obs %.3f > q %.3f · p %.3f)", z_true$obs_calmar, z_true$placebo_q, z_true$p_value)) else
  ng("H1 지연 정보 배분이 placebo 를 못 넘었다", sprintf("obs %.3f q %.3f", z_true$obs_calmar %||% NA, z_true$placebo_q %||% NA))
res_h <- vapply(1:12, function(s) { set.seed(500L + s); Hr <- copy(Hh); Hr[, e := e[sample.int(.N)], by = pid]
  identical(adv_t3b_xs(Hr, 0.0015, n_placebo = 100L, alpha = 0.05, seed = s)$status, "pass") }, logical(1))
if (sum(res_h) <= 2L) ok(sprintf("H2 임의 횡단면 배분 12건 중 통과 %d (≤2)", sum(res_h))) else ng("H2 임의 배분이 자주 통과", as.character(sum(res_h)))
Hs <- copy(Hh)[, e := mean(e), by = pid]
z_s <- adv_t3b_xs(Hs, 0.0015, n_placebo = 30L, seed = 4L)
if (identical(z_s$status, "fail")) ok("H3 날짜 안 균일 배율(스칼라)은 T3b 에서 떨어진다(순열 = 자기 자신)") else ng("H3 균일 배율", z_s$status)
# 노출 짝맞춤: 순열 뒤에도 Σ w e 는 기간마다 원본과 같다 — 함수 안 규칙을 밖에서 재현해 확인
set.seed(1L); g1 <- Hh[pid == 5L]; pe <- g1$e[sample.int(nrow(g1))]; pe <- pe * (sum(g1$w * g1$e) / sum(g1$w * pe))
if (abs(sum(g1$w * pe) - sum(g1$w * g1$e)) < 1e-12) ok("H4 순열 뒤 총노출 짝맞춤(Σ w e 보존)") else ng("H4 짝맞춤")
vo <- .adv_vector_observed(HF, merge(HF, Hh[pid == 5L, .(ticker, e)], by = "ticker")[, .(date, ticker, w = w * e)])   # pid 1 은 지연 정보가 없어 e≡1
if (isTRUE(vo$observed)) ok("H5 벡터 처치는 산출(날짜 안 e_i 산포)에서 관측된다") else ng("H5 벡터 관측")
vo2 <- .adv_vector_observed(HF, copy(HF)[, w := w * 0.7])
if (!isTRUE(vo2$observed)) ok("H6 스칼라 축소는 벡터로 안 읽힌다") else ng("H6 스칼라 오판")

cat("=== I. T1/T2 종단 (엔진 옵션 + L-code 스위치 필요) ===\n")
sup <- .adv_engine_supports(ROOT); honors <- .adv_rp_honors_lcode_switch(ROOT)
if (!isTRUE(sup$overlay_shift)) skip("I1 T1 lag-1 워커 재실행", "rf_cell_engine.R 에 overlay_shift 가 아직 없다(동시 패키지 대기)") else
if (!honors) skip("I1 T1 lag-1 워커 재실행", "run_paper_replication.R 이 QVEST_RP_NO_LCODE 를 읽지 않는다 — 재실행이 L-code 를 누출한다") else
if (!identical(Sys.getenv("QVEST_ADV_E2E", "0"), "1")) skip("I1 T1 lag-1 워커 재실행", "QVEST_ADV_E2E=1 일 때만(워커 ≈14분)") else {
  BIDL <- "RP_20260917_105807_22632_combo_rulefast"
  SL <- rf_overlay_adversary_run(BIDL, "B5", 1L, root = ROOT, dry_run = TRUE, reruns = "auto", cfg = list(max_candidates = 1))
  JL <- fromJSON(SL[candidate == TRUE]$json[1], simplifyVector = FALSE)
  if (JL$tests$T1$status %in% c("pass", "fail") && is.finite(JL$tests$T1$calmar_shift)) ok(sprintf("I1 T1 재실행 완료 — %s (calmar_shift %.3f)", JL$tests$T1$status, JL$tests$T1$calmar_shift)) else ng("I1 T1 재실행", JL$tests$T1$detail %||% "")
  if (!length(JL$tests$T1$side_effects$lcode_leak)) ok("I2 L-code 누출 0") else ng("I2 L-code 누출", paste(JL$tests$T1$side_effects$lcode_leak, collapse = ","))
}
if (!isTRUE(sup$overlay_strict)) skip("I3 T2 strict-PIT 워커 재실행", "rf_cell_engine.R 에 overlay_strict 가 아직 없다") else
  skip("I3 T2 strict-PIT 워커 재실행", "external_data=true arm 이 있는 후보에서만 · QVEST_ADV_E2E=1")

unlink(SBX, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d · 건너뜀 %d\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"rf_overlay_adversary","pass":%d,"fail":%d,"skip":%d,"total":%d}\n', PASS, FAIL, SKIP, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
