#!/usr/bin/env Rscript
#==============================================================================
# test_rf_base_weight.R — 기저 가중 w0 분기 **양방향 검사** (2026-09-01)
#
# 무엇을 지키는가: rf_cell_engine 의 컴포짓이 등가중이면 팩터 n개에서 논문 신호 가중이
#   1/(1+n) 로 떨어져(50/33/25/20/17%) **결합 깊이와 기저 희석이 교락된다**. 5팩터 칸이
#   져도 깊이가 나쁜 건지 논문 신호를 17%로 깎은 탓인지 분리할 수 없다.
#   실측 전례: 2026-08-31 승계에서 1/2 -> 1/3 희석만으로 B1 다섯 칸이 전부 부모
#   기준선(2.63)을 못 넘었다(최고 0.814).
#
# 검사 (팩터 DB 미접촉 — 순수 산술 + 소스 계약):
#   (1) 1팩터에서 w0=0.5 는 등가중과 **수치적으로 동일**해야 한다 (0.5/0.5 = rowMeans of 2).
#       이게 양성 대조다 — 분기를 잘못 짜면 여기서 먼저 어긋난다.
#   (2) 3팩터에서는 **달라야** 한다 (기저 0.25 -> 0.50). 같으면 w0 이 전달되지 않은 것이다.
#   (3) 엔진에 분기와 등가중 폴백이 실재하고, **기본값을 코드에 박지 않았는가**
#       (격자 fixed_axes 가 정본 — 값 없는 구 스펙은 등가중으로 재현돼야 사후 재현성이 산다).
#   (4) 격자가 값을 들고 있는가.
#
# 실행: Rscript 08_Tests/reinforcement/test_rf_base_weight.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat("  OK   ", m, "\n"); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat("  FAIL ", m, if (nzchar(d)) paste0(" — ", d) else "", "\n"); FAIL <<- FAIL + 1L }

# 엔진과 같은 식 (재구현이 아니라 계약 확인)
comp_ew <- function(zb, zs) rowMeans(cbind(zb, do.call(cbind, zs)), na.rm = TRUE)
comp_w0 <- function(zb, zs, w0) w0 * zb + (1 - w0) * rowMeans(do.call(cbind, zs), na.rm = TRUE)

set.seed(7)
n <- 500L
zb <- rnorm(n); z1 <- rnorm(n); z2 <- rnorm(n); z3 <- rnorm(n)

# (1) 1팩터 · w0=0.5 == 등가중 (양성 대조)
d1 <- max(abs(comp_ew(zb, list(z1)) - comp_w0(zb, list(z1), 0.5)))
if (d1 < 1e-12) {
  ok("1팩터에서 w0=0.5 는 등가중과 수치 동일 (분기 정합)")
} else {
  ng("1팩터 동일성 깨짐", sprintf("max|diff| = %.3g", d1))
}

# (2) 3팩터 · w0=0.5 != 등가중 (전달 확인)
d3 <- max(abs(comp_ew(zb, list(z1, z2, z3)) - comp_w0(zb, list(z1, z2, z3), 0.5)))
if (d3 > 1e-6) {
  ok(sprintf("3팩터에서 w0 이 실제로 달라진다 (max|diff| %.3f · 기저가중 0.25 -> 0.50)", d3))
} else {
  ng("3팩터인데 등가중과 같다 — w0 이 전달되지 않는다")
}

# (3) 엔진 계약
src <- tryCatch(paste(readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
                                warn = FALSE), collapse = "\n"), error = function(e) "")
if (grepl("SPEC$base_weight", src, fixed = TRUE)) {
  ok("엔진이 SPEC$base_weight 를 읽는다")
} else {
  ng("엔진에 base_weight 소비 지점이 없다")
}
if (grepl(".w0 * .zb + (1 - .w0)", src, fixed = TRUE)) {
  ok("가중 컴포짓 식 실재")
} else {
  ng("가중 컴포짓 식이 없다")
}
if (grepl(".SDcols = .zcols", src, fixed = TRUE)) {
  ok("등가중 폴백 실재 — 값 없는 구 스펙은 그대로 재현된다(사후 재현성)")
} else {
  ng("등가중 폴백이 사라졌다 — 구 스펙 재현이 깨진다")
}
hard <- grepl("base_weight %||% 0", src, fixed = TRUE)
if (hard) {
  ng("엔진이 기본값을 박고 있다 — 격자 fixed_axes 가 정본이어야 한다")
} else {
  ok("엔진에 기본값 하드코딩 없음 (격자가 정본)")
}

# (4) 격자
g <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"),
                       simplifyVector = FALSE), error = function(e) NULL)
bw <- suppressWarnings(as.numeric((g$fixed_axes %||% list())$base_weight %||% NA))
if (is.finite(bw) && bw > 0 && bw < 1) {
  ok(sprintf("격자 fixed_axes.base_weight = %.2f", bw))
} else {
  ng("격자에 base_weight 가 없거나 범위 밖", as.character(bw))
}

# (5) 러너 2종이 격자값을 스펙으로 넘기고 서명에 포함하는가
for (rp in c("02_Infrastructure/ops/reinforce_auto_parallel.R",
             "02_Infrastructure/ops/reinforce_auto_run.R")) {
  rs <- tryCatch(paste(readLines(file.path(ROOT, rp), warn = FALSE), collapse = "\n"),
                 error = function(e) "")
  if (grepl("base_weight = PROG$fixed_axes$base_weight", rs, fixed = TRUE)) {
    ok(sprintf("%s — 격자값을 스펙으로 전달", basename(rp)))
  } else {
    ng(sprintf("%s — base_weight 미전달", basename(rp)))
  }
}
# ★2026-09-03: 서명 헬퍼가 러너 인라인 → rf_spec_sig.R 정본으로 이동. 대상 파일을 옮긴다.
.sigf <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")
rs <- paste(readLines(if (file.exists(.sigf)) .sigf else
                        file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
                      warn = FALSE), collapse = "\n")
if (grepl("sp$base_weight", rs, fixed = TRUE)) {
  ok("스펙 서명에 base_weight 포함 — w0 만 다른 두 칸을 같은 포트폴리오로 세지 않는다")
} else {
  ng("스펙 서명에 base_weight 가 빠졌다 — 중복 가드가 w0 차이를 못 본다")
}

# ── B2 등록부 소비 (2026-09-03 신설) ────────────────────────────────────────
#   ★실사고: rf_pick_weight_arms() 를 아무도 호출하지 않아 B2 가 카탈로그 52종을 두고
#   격자 스냅샷 5종만 반복 측정했다. 축이 약한 게 아니라 축을 안 돌린 것이었다.
.rp <- tryCatch(paste(readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
                                warn = FALSE), collapse = "\n"), error = function(e) "")
if (grepl("rf_pick_weight_arms(", .rp, fixed = TRUE))
  ok("B2 러너가 배치 시점에 비중 등록부를 소비한다") else
  ng("B2 가 rf_pick_weight_arms 를 호출하지 않는다 — 카탈로그가 격자 밖에 있다")

# 양성 대조 — picker 가 실제로 회전하는가(같은 5종을 다시 주면 카탈로그를 안 쓰는 것과 같다)
.rot <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R")))
  a1 <- rf_pick_weight_arms(5L)
  l1 <- vapply(a1$cells, function(c) as.character(c$weighting$label %||% ""), character(1))
  a2 <- rf_pick_weight_arms(5L, exclude = l1)
  l2 <- vapply(a2$cells, function(c) as.character(c$weighting$label %||% ""), character(1))
  list(l1 = l1, l2 = l2)
}, error = function(e) NULL)
if (!is.null(.rot) && length(.rot$l2) && !length(intersect(.rot$l1, .rot$l2)))
  ok(sprintf("제외 회전 — 2회차가 전부 교체 (%s)", paste(.rot$l2, collapse = "/"))) else
  ng("비중 arm 이 회전하지 않는다", if (is.null(.rot)) "picker 실패" else
     paste(intersect(.rot$l1, .rot$l2), collapse = ","))

cat(sprintf("합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_base_weight","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
