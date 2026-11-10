#!/usr/bin/env Rscript
#==============================================================================
# test_rx_generator_scorecard.R — P4 생성기 성적표(02_Infrastructure/programs/rx_generator_scorecard.R · 2026-11-10 감사 레인 E2)
#   합성 걸음 원장(사슬 3개 · 판 2개)으로 척도를 손계산과 대조 · 보는 창 규율(시험 창 열 거부) · 입력 결함 거부 ·
#   p4.R 원장 필드 이름과의 배선(정적) · 돌연변이(소스 텍스트 치환 · 성사 단정).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(if (!is.na(me)) dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure/programs/rx_generator_scorecard.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
SRC <- file.path(ROOT, "02_Infrastructure/programs/rx_generator_scorecard.R")
E <- new.env(parent = globalenv()); sys.source(SRC, envir = E, keep.source = FALSE)
pass <- 0L; fail <- 0L
chk <- function(name, cond) { ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L; cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name)) }
eq <- function(a, b) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-9))
errm <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))

## ── 합성 원장 ────────────────────────────────────────────────────────────────
reg <- function(cid, g) list(schema = "rc_p4_chain_steps_v1", event = "chain_registered", chain_id = cid, generator = list(id = g))
base <- function(S, uc, dd) list(event = "base_measured", k = 0L, metrics = list(S_vis = S, uc_vis = uc, dd_capture_median_vis = dd))
op <- function(k, bt, ax, g) list(event = "step_open", k = k, block_type = bt, changed_axes = as.list(ax), generator_version = g, parent = 0L)
rs <- function(k, dec, dS, S, uc, dd, r7, reasons = list())
  list(event = "step_result", k = k, decision = dec, r7 = r7, reasons = reasons,
       table = list(S_vis = S, dS_vis = dS, uc_vis = uc, dd_capture_median_vis = dd, d_uc_vis = NA, d_dd_capture_median_vis = NA),
       metrics = list(S_vis = S, uc_vis = uc, dd_capture_median_vis = dd))
CA <- list(reg("P4C01_a", "g1"), base(0.80, 0.70, 0.95),
           op(1L, "weighting", "weighting", "g1"), rs(1L, "reject", -0.02, 0.78, 0.70, 0.95, "noise", list("R_dS: 미달")),
           op(2L, "weighting", "weighting", "g1"), rs(2L, "reject", 0.01, 0.81, 0.70, 0.94, "noise", list("R_dS: 미달")),
           op(3L, "regime_exposure", "overlay", "g1"), rs(3L, "accept", 0.10, 0.90, 0.68, 0.85, "signal"),
           op(4L, "defense_sleeve", "defense_sleeve", "g1"))
CB <- list(reg("P4C02_b", "g1"), base(1.00, 0.90, 1.00),
           op(1L, "blend", "base_signal", "g1"), rs(1L, "accept", 0.05, 1.05, 0.92, 0.98, "signal"),
           list(event = "step_measure_failed", k = 2L),
           op(2L, "weighting", "weighting", "g1"), rs(2L, "reject", -0.03, 1.02, 0.91, 0.99, "noise", list("R_dS: 미달", "R_uc: 미달")))
CC <- list(reg("P4C03_c", "g2"), base(0.80, 0.70, 0.95),
           op(1L, "construction", "cap_core", "g2"), rs(1L, "accept", 0.20, 1.00, 0.72, 0.80, "signal"),
           op(2L, "rebalance", "rebalance", "g2"), rs(2L, "accept", 0.05, 1.05, 0.73, 0.78, "signal"))
sc <- E$rxg_scorecard(list(P4C01_a = CA, P4C02_b = CB, P4C03_c = CC))
g1 <- sc$by_generator$g1; g2 <- sc$by_generator$g2

chk("S01 판 2개(g1 · g2) · 사슬 수 2 · 1 · 스키마", identical(names(sc$by_generator), c("g1", "g2")) && g1$n_chains == 2L && g2$n_chains == 1L &&
      identical(sc$schema, "rxg_scorecard_v1"))
chk("S02 g1 걸음 6(열림) · 판정 5 · 채택 2 · 채택률 0.4(미판정 걸음은 판정에서 뺀다)", g1$n_steps == 6L && g1$n_decided == 5L && g1$n_accept == 2L && eq(g1$accept_rate, 0.4))
chk("S03 걸음당 개선(주 척도) = Σ 채택 dS / 판정 = (0.10 + 0.05) / 5 = 0.03 · g2 = 0.25 / 2", eq(g1$gain_per_step, 0.03) && eq(g2$gain_per_step, 0.125))
chk("S04 dS 평균 · 중앙(판정 걸음) = mean(−0.02, 0.01, 0.10, 0.05, −0.03) · median", eq(g1$dS_mean, mean(c(-0.02, 0.01, 0.10, 0.05, -0.03))) && eq(g1$dS_median, 0.01))
chk("S05 누적 개선 = 사슬 머리(마지막 채택) − 기준 칸: A 0.10 · B 0.05 → 평균 0.075 · 상승 포착 차 평균 (−0.02 + 0.02)/2 · 위기 포착 차 (−0.10 − 0.02)/2",
    eq(g1$cum_dS_mean, 0.075) && eq(g1$cum_duc_mean, 0) && eq(g1$cum_ddd_mean, -0.06) && eq(g2$cum_dS_mean, 0.25))
chk("S06 새 블록 비율 — A: weighting(새) · weighting · regime_exposure(새) · defense_sleeve(새) · B: blend(새) · weighting(새) → 5/6",
    eq(g1$new_block_rate, 5 / 6) && eq(g2$new_block_rate, 1))
chk("S07 되풀이 기각 = 같은 사슬에서 이미 기각된 (블록 · 축)을 또 낸 걸음 — A 걸음 2 한 개", g1$repeat_fail == 1L && g2$repeat_fail == 0L &&
      identical(sc$steps[repeat_fail == TRUE]$k, 2L))
chk("S08 최장 연속 잡음 — A 2(걸음 1 · 2) · B 1 → 최대 2 · 평균 1.5", g1$noise_streak_max == 2L && eq(g1$noise_streak_mean, 1.5))
chk("S09 기각 사유 빈도 R_dS 3 · R_uc 1 · 측정 실패 1(진단)", identical(as.integer(g1$reasons$R_dS), 3L) && identical(as.integer(g1$reasons$R_uc), 1L) && g1$measure_fail == 1L)
se1 <- stats::sd(c(0.10 / 3, 0.05 / 2)) / sqrt(2)
chk("S10 주 척도의 사슬 단위 표준오차 — g1 사슬별 (0.10/3 · 0.05/2) · g2 사슬 1개 = NA", eq(g1$gain_per_step_chain_se, se1) && is.na(g2$gain_per_step_chain_se))
cp <- E$rxg_scorecard_compare(sc, "g1", "g2")
chk("S11 비교 g2 − g1 — 주 척도 차 0.095 · 표준오차 NA(한쪽 사슬 1 · 비교 불가 표시) · 판정 문턱 없음",
    eq(cp$delta$gain_per_step, 0.095) && is.na(cp$gain_per_step_se) && is.na(cp$gain_per_step_z) && grepl("판정 문턱 없음", cp$note))
chk("S12 블록 유형별 표 — g1 weighting 걸음 3 · 채택 0", { B <- g1$blocks; B[block == "weighting"]$steps == 3L && B[block == "weighting"]$accept == 0L })
chk("S13 md 표 — 판별 한 줄씩 · 주 척도 열", { m <- E$rxg_scorecard_md(sc); grepl("| g1 | 2 | 6 | 5 | 0.400 | 0.030 |", m, fixed = TRUE) && grepl("| g2 | 1 |", m, fixed = TRUE) })

## ── 입력 결함 · 보는 창 규율 ─────────────────────────────────────────────────
bad <- CA; bad[[4]]$table$S_test <- 1.2
chk("S14 [보는 창] step_result 표에 시험 창 열(S_test)이 있으면 멈춘다", grepl("시험 창", errm(E$rxg_scorecard(list(P4C01_a = bad)))))
badb <- CA; badb[[2]]$metrics$cagr_full <- 0.2
chk("S15 [보는 창] 기준 칸 지표에 전 기간 열(cagr_full)이 있으면 멈춘다", grepl("시험 창", errm(E$rxg_scorecard(list(P4C01_a = badb)))))
chk("S16 사슬 이름 ≠ 등록 chain_id · 같은 사슬 두 번 · 판 모름 → 멈춘다",
    grepl("chain_id", errm(E$rxg_scorecard(list(WRONG = CA)))) && grepl("두 번", errm(E$rxg_scorecard(list(CA, CA)))) &&
      grepl("생성기 판을 모르는", errm(E$rxg_scorecard(list(P4C09_x = list(base(1, 1, 1)))))))
s0 <- E$rxg_scorecard(list())
chk("S17 빈 입력 = 판 0 · 오류 없음", !length(s0$by_generator) && nrow(s0$steps) == 0L)
chk("S18 이름 없는 목록 = 등록 기록의 chain_id 로 이름을 정한다", identical(E$rxg_scorecard(list(CA))$chains$chain, "P4C01_a"))

## ── 배선(정적) — p4.R 원장 필드 · 금지 지표 규칙과 같은가 ────────────────────────
p4 <- file.path(ROOT, "04_Research/programs/_lib/round_core/v1/p4.R")
if (file.exists(p4)) {
  pt <- paste(readLines(p4, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  rx <- regmatches(pt, regexpr('RC_P4_FORBIDDEN_METRIC_RX <- "[^"]+"', pt))
  chk("S19 금지 지표 규칙 = p4.R RC_P4_FORBIDDEN_METRIC_RX 사본", length(rx) == 1L && identical(sub('^.*<- "', "", sub('"$', "", rx)), E$RXG_SC_FORBIDDEN_RX))
  chk("S20 p4.R 원장 기록 필드(step_open: block_type · changed_axes · generator_version / step_result: table · decision · reasons · r7 / base_measured: metrics)",
      all(vapply(c('event = "step_open"', "block_type = block_type", "changed_axes = as.list", "generator_version = generator_version",
                   'event = "step_result"', "table = as.list(T[1])", 'decision = if (accept) "accept" else "reject"', "r7 = r7",
                   'event = "base_measured"', "list(metrics = m,"), function(s) grepl(s, pt, fixed = TRUE), logical(1))))
} else { cat("  [SKIP] p4.R 없음 — S19 · S20 생략\n") }

## ── 돌연변이(소스 텍스트 치환 · 성사 단정) ─────────────────────────────────────
st <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mutate <- function(from, to, probe) {
  n <- lengths(regmatches(st, gregexpr(from, st, fixed = TRUE))); if (n != 1L) return(NA)
  f <- tempfile(fileext = ".R"); writeLines(sub(from, to, st, fixed = TRUE), f, useBytes = TRUE)
  M <- new.env(parent = globalenv()); sys.source(f, envir = M, keep.source = FALSE); unlink(f)
  isTRUE(tryCatch(probe(M), error = function(e) FALSE))
}
m1 <- mutate("new_block = !(bt %in% seen_blocks)", "new_block = TRUE", function(M) eq(M$rxg_scorecard(list(P4C01_a = CA, P4C02_b = CB))$by_generator$g1$new_block_rate, 5 / 6))
m2 <- mutate("if (identical(dec, \"reject\")) rejected_sig <- c(rejected_sig, sig)", "invisible(NULL)",
             function(M) M$rxg_scorecard(list(P4C01_a = CA))$by_generator$g1$repeat_fail == 1L)
m3 <- mutate("  bad <- ks[grepl(RXG_SC_FORBIDDEN_RX, ks, perl = TRUE)]", "  bad <- character(0)",
             function(M) grepl("시험 창", errm(M$rxg_scorecard(list(P4C01_a = bad)))))
chk("S21 [돌연변이 red] 새 블록 판정 · 되풀이 기각 기록 · 보는 창 검사를 각각 지우면 S06 · S07 · S14 가 깨진다(치환 성사)",
    identical(m1, FALSE) && identical(m2, FALSE) && identical(m3, FALSE))

## ── 측정 실패 포기 걸음(11-10 적대적 검토 2차 R1) — 가설 기각이 아니다 ─────────────────
ab <- function(k) list(event = "step_result", k = k, decision = "reject", abandoned = TRUE, artifacts = NA, r7 = NA, reasons = list("measure_failed: 측정 실패 2회 — 워커"))
CD <- list(reg("P4C04_d", "g3"), base(0.80, 0.70, 0.95),
           op(1L, "weighting", "weighting", "g3"), ab(1L),
           op(2L, "weighting", "weighting", "g3"), rs(2L, "accept", 0.10, 0.90, 0.70, 0.90, "signal"))
g3 <- E$rxg_scorecard(list(P4C04_d = CD))$by_generator$g3
chk("S22 포기 걸음 = 판정 · 채택률 분모 밖 · 따로 셈(n_abandoned) · 되풀이 기각 아님 · 기각 사유 빈도 밖",
    g3$n_decided == 1L && eq(g3$accept_rate, 1) && g3$n_abandoned == 1L && g3$repeat_fail == 0L && !length(g3$reasons) && eq(g3$gain_per_step, 0.10))
m4 <- mutate("else if (isTRUE(r$abandoned)) \"abandoned\" ", "", function(M) M$rxg_scorecard(list(P4C04_d = CD))$by_generator$g3$n_decided == 1L)
chk("S23 [돌연변이 red] 포기 판별을 지우면 S22 가 깨진다(치환 성사)", identical(m4, FALSE))

cat(sprintf("\n%s\n", toJSON(list(test = "test_rx_generator_scorecard", pass = pass, fail = fail, total = pass + fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
