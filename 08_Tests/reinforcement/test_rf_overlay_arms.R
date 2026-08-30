#==============================================================================
# test_rf_overlay_arms.R — 오버레이 등록부 소비 검사 (2026-08-30)
#
# 왜: 도훈 "오버레이 방법론을 특정하는건 별로인데". 격자에 방법을 박으면 새 방법이
#   등록돼도 아무도 안 쓰고 같은 다섯 개만 반복 측정한다(weight_catalog 가 이미 진단한 병:
#   "안 붙은 이유는 계약 충돌이 아니라 아무도 한 줄을 안 썼기 때문").
#   그래서 격자는 축만 선언하고 칸은 등록부에서 뽑는다. 이 검사는 그 배선이 살아있는지,
#   그리고 선정 규칙(계열 다양성·제외 회전)이 실제로 작동하는지 양방향으로 본다.
# 부작용 없음.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

A <- rf_overlay_catalog(ROOT)
if (is.null(A) || !nrow(A)) {
  ng("등록부 부재", "06_Registry/overlay_catalog.json")
} else {
  ok(sprintf("등록부 %d팔 · %d계열", nrow(A), length(unique(A$family))))
  if (all(nzchar(A$basis))) {
    ok("전 팔이 method(방법) 근거를 갖는다")
  } else ng("근거 없는 팔", paste(A[!nzchar(basis)]$id, collapse = ", "))
}

p <- rf_pick_overlay_arms(5L, root = ROOT)
if (is.null(p) || !length(p$cells)) {
  ng("선정 실패")
} else {
  if (length(unique(p$picked_ids)) == length(p$picked_ids)) {
    ok(sprintf("5팔 선정 · 중복 0 (%s)", paste(p$picked_ids, collapse = ", ")))
  } else ng("선정 중복", paste(p$picked_ids, collapse = ", "))
  # 계열 다양성 — 같은 계열을 두 번 뽑으면 같은 축을 반복 측정한다(B2 실측 교훈)
  fam2 <- A[match(p$picked_ids, A$id)]$family
  if (length(unique(fam2)) == length(fam2)) {
    ok(sprintf("계열 다양성 강제 (%s)", paste(fam2, collapse = ", ")))
  } else ng("계열 중복", paste(fam2, collapse = ", "))
  # 구속 축 우선 — 지금 막고 있는 것이 낙폭이다
  if (identical(fam2[1], "drawdown")) {
    ok("구속 축(drawdown) 계열을 앞세운다")
  } else ng("우선순위", paste("첫 팔 계열 =", fam2[1]))
}

# 제외 회전 — 이미 측정한 팔은 다시 뽑지 않는다(같은 것을 두 번 재지 않는다)
ex <- p$picked_ids[1:2]
p2 <- rf_pick_overlay_arms(5L, exclude = ex, root = ROOT)
if (!is.null(p2) && !any(ex %in% p2$picked_ids)) {
  ok(sprintf("제외 회전 — %s 빠지고 %s 로 대체", paste(ex, collapse = "/"),
             paste(setdiff(p2$picked_ids, p$picked_ids), collapse = "/")))
} else ng("제외 미작동", "이미 측정한 팔을 또 뽑는다")

# 격자가 등록부를 소비한다고 선언하는가 + 러너가 배치 시점에 다시 뽑는가
g <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
b5 <- Filter(function(b) identical(b$id, "B5"), g$blocks)
if (length(b5) && identical(b5[[1]]$source, "overlay_catalog")) {
  ok("격자 B5 가 등록부 소비를 선언")
} else ng("B5 source 선언 부재", "격자에 박힌 값이 정본으로 오인된다")
rr <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE)
if (any(grepl("rf_pick_overlay_arms", rr, fixed = TRUE))) {
  ok("러너가 배치 시점에 등록부에서 다시 뽑는다")
} else ng("런타임 선정 미배선", "격자 스냅샷이 사실상 고정 목록이 된다")

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
