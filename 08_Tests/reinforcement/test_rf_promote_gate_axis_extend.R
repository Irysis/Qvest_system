#!/usr/bin/env Rscript
#==============================================================================
# test_rf_promote_gate_axis_extend.R — 승격 상한의 **조건부 연장** 검사 (도훈 결정 2026-09-21, 안 2번)
#
# 왜: 22632_combo 사슬은 세 세대가 전부 부모를 넘었는데(PORT_t 3.202→3.592→3.806→4.349)
#   depth 4 에서 `depth_cap` 으로 잘렸다. 상한의 원 사유는 성능 포화가 아니라 예산 공정성이었다.
#   그래서 판정 축을 깊이에서 **게이트 축(Calmar)의 개선**으로 옮겼다 — 포화가 스스로 상한이 된다.
#
# 이 검사가 지키는 것 둘:
#   ① 연장이 **열린다** (개선 중이면) — 그리고 **닫힌다** (포화·하락·확인불가·하드상한·스위치off)
#   ② 게이트 축 값이 **실제로 실린다** — best$calmar 와 parent$best_calmar 배선이 빠지면
#      판정은 영원히 gate_axis_unknown 으로 떨어져 "기능은 있는데 한 번도 안 열리는" 상태가 된다.
#      (없는 것은 grep 에 안 걸린다 — AST 로 재도출한다)
#
# ★R 문법: 최상위에서 `if (...)` 다음 줄에 `else` 를 두면 파싱이 깨진다. 단정은 chk() 한 줄로 한다.
# 실행: cd <ROOT> && Rscript 08_Tests/reinforcement/test_rf_promote_gate_axis_extend.R
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R")))

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m_ok, m_ng, detail = "") if (isTRUE(cond)) ok(m_ok) else ng(m_ng, detail)
.d <- function(r) sprintf("ok=%s reason=%s depth=%s", r$ok, r$reason, r$depth)

CFG  <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = TRUE)
SPEC <- file.path(ROOT, "08_Tests/reinforcement/test_rf_promote_gate_axis_extend.R")  # 존재하는 파일이면 족하다
HARD <- as.integer(CFG$promote_max_depth_hard %||% 6L)

# 이번 사슬의 실측을 픽스처로 쓴다 — 합성 숫자보다 판별력이 높다(promo2 0.490 → promo3 0.501)
.entry <- function(depth = 3L, pt = 3.806, pc = 0.490, drop_calmar = FALSE) {
  par <- list(base_id = "X_promo3", depth = depth, best_port_t = pt, best_calmar = pc)
  if (drop_calmar) par$best_calmar <- NULL
  list(base_id = "X_promo3", parent = par, handed_off = FALSE)
}
.best <- function(pt = 4.349, cal = 0.501, grade = "B")
  list(grade = grade, port_t = pt, calmar = cal, cell_code = "B1_3", spec = SPEC)
.dec <- function(e, b, cfg = CFG) rf_promote_decide(e, b, cfg, existing_ids = character(0))

cat("== 승격 연장 (게이트 축) ==\n")

r <- .dec(.entry(depth = 1L), .best())
chk(isTRUE(r$ok) && identical(r$reason, "ok"),
    "A 상한 안(depth 2)은 기존 경로 그대로 'ok'", "A 상한 안 경로 변질", .d(r))

# [양성 대조] 실측 — Calmar 0.490 → 0.501 (+0.011 > min_delta 0.01) 이면 depth 4 가 열린다
r <- .dec(.entry(), .best())
chk(isTRUE(r$ok) && identical(r$reason, "ok_extended") && identical(r$depth, 4L),
    "B [양성] 실측 Δcalmar +0.011 → depth 4 연장 허용", "B 연장이 안 열린다", .d(r))

# [음성] 포화 — 개선이 min_delta 이하면 닫힌다 (포화가 스스로 상한이 된다)
r <- .dec(.entry(), .best(cal = 0.495))
chk(!isTRUE(r$ok) && identical(r$reason, "gate_axis_no_improvement"),
    "C [음성] Δcalmar +0.005 (< 0.01) → 연장 거부", "C 포화를 통과시켰다", .d(r))

# [음성] 게이트 축 하락 — PORT_t 가 올라도 막힌다 (축을 바꾼 것의 요점)
r <- .dec(.entry(), .best(cal = 0.470))
chk(!isTRUE(r$ok) && identical(r$reason, "gate_axis_no_improvement"),
    "D [음성] PORT_t 는 올랐지만 Calmar 하락 → 연장 거부", "D Calmar 하락을 통과시켰다", .d(r))

# [음성] 확인 불가 — 구판 entry 는 parent 에 게이트 축 값이 없다
r <- .dec(.entry(drop_calmar = TRUE), .best())
chk(!isTRUE(r$ok) && identical(r$reason, "gate_axis_unknown"),
    "E [음성] 부모에 게이트 축 없음 → 확인 못 하는 것을 통과시키지 않는다", "E 미지 값을 통과시켰다", .d(r))

# [돌연변이 통제] 스위치를 끄면 구판 동작(depth_cap)으로 돌아가는가 — 검사가 스위치를 실제로 재는지
cfg_off <- CFG; cfg_off$promote_extend_on_gate_axis <- FALSE
r <- .dec(.entry(), .best(), cfg_off)
chk(!isTRUE(r$ok) && identical(r$reason, "depth_cap"),
    "F [돌연변이] 스위치 off → 구판 depth_cap 으로 복귀", "F 스위치가 무력", .d(r))

# [예산 방어선] 개선이 이어져도 하드 상한은 막는다
r <- .dec(.entry(depth = HARD), .best())
chk(!isTRUE(r$ok) && identical(r$reason, "depth_cap_hard"),
    sprintf("G 하드 상한(%d) 초과는 개선 중이어도 막힌다 — 예산 방어선 생존", HARD), "G 하드 상한 무력", .d(r))

# [회귀] 조건 ①(부모 PORT_t 초과)은 연장 경로에서도 살아 있다
r <- .dec(.entry(), .best(pt = 3.500))
chk(!isTRUE(r$ok) && identical(r$reason, "no_improvement_over_parent"),
    "H [회귀] 부모 PORT_t 미달은 연장 경로에서도 막힌다", "H 조건 ① 붕괴", .d(r))

# ── I [배선 재도출] 게이트 축 값이 실제로 실리는가 — 빠지면 영원히 unknown ───
NP <- parse(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"))
.names_near <- function(exprs, want) {
  hit <- character(0)
  walk <- function(x) {
    if (is.call(x)) {
      if (identical(as.character(x[[1]])[1], "list")) {
        nm <- names(as.list(x))[-1]
        if (length(nm) && want %in% nm) hit <<- unique(c(hit, nm))
      }
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    } else if (is.pairlist(x) || is.list(x)) {
      for (i in seq_along(x)) if (!is.null(x[[i]])) try(walk(x[[i]]), silent = TRUE)
    }
  }
  for (e in exprs) walk(e)
  hit
}
bn <- .names_near(NP, "port_t")        # best   <- list(... port_t ...)
pn <- .names_near(NP, "best_port_t")   # parent =  list(... best_port_t ...)
chk("calmar" %in% bn, "I-1 best 에 게이트 축(calmar) 이 실린다",
    "I-1 best 에 calmar 미배선 — 판정이 영원히 gate_axis_unknown", paste(bn, collapse = ","))
chk("best_calmar" %in% pn, "I-2 parent 에 best_calmar 가 실린다(다음 세대가 읽는다)",
    "I-2 parent 에 best_calmar 미배선", paste(pn, collapse = ","))

# ── J 배송된 설정이 실제로 켜져 있는가 (선언 ≠ 배송 방지) ────────────────────
chk(isTRUE(CFG$promote_extend_on_gate_axis) &&
      identical(as.character(CFG$promote_gate_axis), "calmar") &&
      is.finite(suppressWarnings(as.numeric(CFG$promote_extend_min_delta))),
    sprintf("J 배송 설정 — axis=%s · min_delta=%s · hard=%s",
            CFG$promote_gate_axis, CFG$promote_extend_min_delta, HARD),
    "J 설정 미배송")

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L)
