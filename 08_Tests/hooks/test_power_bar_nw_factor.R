#==============================================================================
# test_power_bar_nw_factor.R — 검정력 바의 NW 인자 계약 검사기
#
# 계약: 02_Infrastructure/contracts/required_effect_size.R
#   ① 바는 **무엇을 가정했는지 항상 신고**한다 (nw_inflation_source)
#   ② 계열이 주어지면 **실측이 가정을 이긴다**
#   ③ 실측 불가는 조용히 넘어가지 않고 source 에 낙하 사실을 남긴다
#
# 배경 (2026-08-09 실측): NW_INFLATION_DEFAULT=1.25 는 가정치인데 월간 횡단면 스프레드
#   10계열(266개월)에서 실측 NW3 SE/iid SE 중앙값 **0.986** (범위 0.900~1.063, 1.25 초과 0건).
#   AR(1) 이 -0.054~+0.146 으로 거의 0 이라 팽창이 애초에 발생하지 않는다.
#   ⇒ 1.25 를 쓰면 바가 중앙값 27% 과대 → 라운드가 과하게 기각된다.
#   실사례: FQ-170 관문에서 관측 +5.62%p(NW3 t=2.361)가 1.25-바(6.17%p)에 미달로 읽혔다.
#
# ★상수를 0.99 로 갈아끼우지 **않는** 것이 이 수리의 핵심이다 — 위 10계열은 전부 월간
#   횡단면 스프레드이고, NAV/오버레이/일간 계열은 자기상관이 실재해 1.25 가 맞을 수 있다.
#   그래서 검사기도 "상수가 옳은가" 가 아니라 **"실측 경로가 살아 있고 자기 신고하는가"** 를 잰다.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.qv_norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
.QV_MARKER <- "02_Infrastructure/hooks/qvest_hook_router.py"
.qv_ok <- function(p) length(p) == 1L && !is.na(p) && nzchar(p) &&
                      file.exists(file.path(p, .QV_MARKER))
# 앵커 self-first (금칙 ④-b: 테스트 러너는 공유 resolver 와 반대 규칙)
.qv_self <- function() {
  ca <- commandArgs(trailingOnly = FALSE); f <- ca[grepl("^--file=", ca)]
  if (!length(f)) return(NA_character_)
  .qv_norm(file.path(dirname(sub("^--file=", "", f[1])), "..", ".."))
}
PROJ <- local({
  for (p in c(.qv_self(), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.na(p) || !nzchar(p)) next
    p <- .qv_norm(p); if (.qv_ok(p)) return(p)
  }
  stop("project root 미발견")
})
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
.m1 <- function(m) { m <- as.character(m); if (!length(m) || is.na(m[1])) "<없음>" else m[1] }
ok  <- function(n, m = "") { m <- .m1(m); PASS <<- PASS + 1L
  cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m) && m != "<없음>") paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L
  cat(sprintf("  FAIL: %s — %s\n", n, .m1(m))) }

invisible(capture.output(suppressMessages({
  source(file.path(PROJ, "02_Infrastructure/contracts/canonical_screen_bt.R"))
  source(file.path(PROJ, "02_Infrastructure/contracts/required_effect_size.R"))
})))

cat("=== power bar : NW inflation contract ===\n")

set.seed(20260809L)
N <- 266L
white <- rnorm(N, mean = 0.004, sd = 0.033)            # 자기상관 없음
ar    <- as.numeric(stats::filter(rnorm(N, 0.001, 0.02), 0.6, method = "recursive")) + 0.004
ar    <- ar[is.finite(ar)]

# ─── 1) 기본 동작 불변 (기존 호출자 회귀) ────────────────────────────────────
r0 <- required_effect(N)
expect <- 2.0 * (SPREAD_SD_MONTHLY_25EW / sqrt(N)) * NW_INFLATION_DEFAULT * 12
if (isTRUE(all.equal(r0$required_annual, expect))) {
  ok("backward_compat_default", sprintf("%.4f%%p", 100 * r0$required_annual))
} else {
  bad("backward_compat_default", sprintf("기본 바가 바뀌었다: %.6f vs %.6f", r0$required_annual, expect))
}

# ─── 2) 바가 무엇을 가정했는지 신고하는가 ────────────────────────────────────
if (identical(r0$nw_inflation_source, "assumed_default") &&
    isTRUE(all.equal(r0$nw_inflation, NW_INFLATION_DEFAULT))) {
  ok("source_reported_assumed", r0$nw_inflation_source)
} else {
  bad("source_reported_assumed", sprintf("source=%s", r0$nw_inflation_source))
}
r_c <- required_effect(N, nw_inflation = 1.0)
if (identical(r_c$nw_inflation_source, "caller_supplied")) {
  ok("source_reported_caller")
} else {
  bad("source_reported_caller", sprintf("source=%s", r_c$nw_inflation_source))
}

# ─── 3) 위반 주입: 자기상관이 **실재**하는 계열을 못 잡으면 계측 사망 ────────
f_ar <- nw_inflation_measured(ar)
if (is.finite(f_ar) && f_ar > 1.10) {
  ok("detects_real_autocorrelation", sprintf("AR(0.6) 계열 인자 %.3f > 1.10", f_ar))
} else {
  bad("detects_real_autocorrelation",
      sprintf("자기상관 계열인데 인자 %.3f — 측정기가 팽창을 못 본다", f_ar))
}

# ─── 4) 오검출 통제: 백색잡음을 팽창으로 읽으면 안 된다 ──────────────────────
f_w <- nw_inflation_measured(white)
if (is.finite(f_w) && abs(f_w - 1) < 0.15) {
  ok("white_noise_not_inflated", sprintf("백색잡음 인자 %.3f ≈ 1", f_w))
} else {
  bad("white_noise_not_inflated", sprintf("백색잡음인데 인자 %.3f", f_w))
}

# ─── 5) 실측이 가정을 이긴다 + 바가 실제로 움직인다 ──────────────────────────
r_m <- required_effect(N, series = white)
if (!identical(r_m$nw_inflation_source, "measured")) {
  bad("measured_overrides_assumed", sprintf("source=%s", r_m$nw_inflation_source))
} else if (r_m$required_annual < r0$required_annual) {
  ok("measured_overrides_assumed",
     sprintf("바 %.3f%%p → %.3f%%p (인자 %.3f)", 100*r0$required_annual,
             100*r_m$required_annual, r_m$nw_inflation))
} else {
  bad("measured_overrides_assumed", "백색잡음 실측인데 바가 안 내려갔다")
}
# ★돌연변이 등가: series 를 무시하는 구판이면 이 차이가 0 이 된다.
if (abs(r_m$required_annual - r0$required_annual) > 1e-9) {
  ok("series_actually_consumed", "series 인자가 바를 움직인다")
} else {
  bad("series_actually_consumed",
      "series 를 넘겼는데 바가 그대로 — 인자가 소비되지 않는다(구판 동작)")
}

# ─── 6) 실측 불가는 **조용히** 넘어가지 않는다 ───────────────────────────────
r_s <- required_effect(N, series = white[1:5])
if (grepl("unmeasurable", r_s$nw_inflation_source, fixed = TRUE) &&
    isTRUE(all.equal(r_s$required_annual, r0$required_annual))) {
  ok("unmeasurable_falls_back_loudly", r_s$nw_inflation_source)
} else {
  bad("unmeasurable_falls_back_loudly",
      sprintf("source=%s (짧은 계열이 조용히 통과하면 안 된다)", r_s$nw_inflation_source))
}

# ─── 7) 가정 대조값 동봉 (바를 읽는 사람이 과대율을 계산할 수 있어야) ────────
if (isTRUE(all.equal(r_m$nw_inflation_assumed_default, NW_INFLATION_DEFAULT))) {
  ok("assumed_default_disclosed", sprintf("%.2f", r_m$nw_inflation_assumed_default))
} else {
  bad("assumed_default_disclosed", "가정 대조값이 산출물에 없다")
}

cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "power_bar_nw_factor", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
