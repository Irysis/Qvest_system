#==============================================================================
# test_overlay_probe.R — 오버레이 arm 오프라인 probe 계약 (v10.2 2026-09-03)
#
# 대상: 02_Infrastructure/reinforcement/overlay_probe.R
# ★양성 대조 + 위반 주입 5방향. 통과만 재는 검사는 방어선이 아니다 —
#   이 저장소는 "경고 0" 을 보고한 순간이 최고 위험이라는 걸 여러 번 실측했다.
# 부작용: overlay_arms/ 에 zz_probe_* 픽스처를 잠시 쓰고 지운다(함수 안 on.exit — 발화한다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source("02_Infrastructure/reinforcement/overlay_probe.R"))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

ADIR <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms")
inject <- function(kind, lines) {
  p <- file.path(ADIR, paste0(kind, ".R"))
  writeLines(lines, p)
  on.exit(unlink(p), add = TRUE)          # 함수 안이라 발화한다(최상위 on.exit 은 no-op)
  overlay_probe_arm(kind)
}
failed_at <- function(r) { z <- r$checks[status == "FAIL"]; if (nrow(z)) z$check[1] else NA_character_ }

# ── ① 양성 대조 — 정상 arm 은 통과해야 한다 ────────────────────────────────
r0 <- overlay_probe_arm("dbeta_tilt")
if (isTRUE(r0$ok) && identical(r0$axis, "cross_sectional"))
  ok(sprintf("① 양성 대조 — dbeta_tilt 통과 · 축 %s · 횡단면 sd %.3f", r0$axis, r0$x_var)) else
  ng("① 정상 arm 이 막혔다 — probe 가 과잉 차단", as.character(r0$reason))

# ── ② 위반 주입: 함수명 계약 위반 ──────────────────────────────────────────
r <- inject("zz_probe_nofn", c(
  "wrong_name <- function(H, t, ctx) 1"))
if (!isTRUE(r$ok) && identical(failed_at(r), "file"))
  ok("② 함수명 계약 위반 검출") else ng("② 함수명 위반 미검출", as.character(r$reason))

# ── ③ 위반 주입: 측정 누출(성과 필드 참조) ────────────────────────────────
r <- inject("zz_probe_leak", c(
  "# essence_score 를 보고 문턱을 정했다",
  "overlay_expo_zz_probe_leak <- function(H, t, ctx) {",
  "  q <- stats::ecdf(H$dd[is.finite(H$dd)])(H$dd[t])",
  "  max(0, min(1, 1 - q))",
  "}"))
if (!isTRUE(r$ok) && identical(failed_at(r), "leak"))
  ok("③ 측정 누출 검출 — 성과 필드를 본 흔적") else ng("③ 누출 미검출", as.character(r$reason))

# ── ④ 위반 주입: 임의 상수 문턱 ────────────────────────────────────────────
#   ★가장 흔한 형태가 인덱스를 낀 H$dd[t] > 0.2 다. 대괄호를 허용하지 않으면 통째로 샌다.
r <- inject("zz_probe_literal", c(
  "overlay_expo_zz_probe_literal <- function(H, t, ctx) {",
  "  if (H$dd[t] > 0.2) return(0.5)",
  "  1",
  "}"))
if (!isTRUE(r$ok) && identical(failed_at(r), "literal"))
  ok("④ 임의 상수 문턱 검출 (인덱스 낀 형태)") else ng("④ 리터럴 미검출", as.character(r$reason))

# ── ⑤ 위반 주입: 미래 참조 (신호일 t 의 fwd = 익월 수익) ──────────────────
r <- inject("zz_probe_future", c(
  "overlay_expo_zz_probe_future <- function(H, t, ctx) {",
  "  f <- H$fwd[t]",
  "  if (!is.finite(f)) return(1)",
  "  max(0, min(1, 1 - abs(f)))",
  "}"))
if (!isTRUE(r$ok) && identical(failed_at(r), "future"))
  ok("⑤ 미래 참조 검출 — fwd[t] 는 신호일에 미실현이다") else
  ng("⑤ 미래 참조 미검출 — 이게 뚫리면 PIT 가 뚫린다", as.character(r$reason))

# ── ⑥ 위반 주입: 처치 미전달(상시 1) ──────────────────────────────────────
r <- inject("zz_probe_flat", c(
  "overlay_expo_zz_probe_flat <- function(H, t, ctx) 1"))
if (!isTRUE(r$ok) && identical(failed_at(r), "treatment"))
  ok("⑥ 처치 미전달 검출 — 상수 노출") else ng("⑥ 상수 노출 미검출", as.character(r$reason))

# ── ⑦ 음성 대조: 확장창 추정만 쓰는 arm 은 리터럴 스캔에 안 걸린다 ────────
#   과잉 차단이면 생성기가 정당한 arm 을 못 낸다 — 검출력만큼 특이도도 재야 한다.
r <- inject("zz_probe_clean", c(
  "overlay_expo_zz_probe_clean <- function(H, t, ctx) {",
  "  h <- H$rv60[is.finite(H$rv60)]",
  "  if (length(h) < 24L) return(1)",
  "  tg <- stats::median(h)",
  "  v <- H$rv60[t]",
  "  if (!is.finite(v) || v <= 0) return(1)",
  "  max(0, min(1, tg / v))",
  "}"))
if (isTRUE(r$ok))
  ok("⑦ 음성 대조 — 확장창 추정만 쓴 arm 은 통과(과잉 차단 없음)") else
  ng("⑦ 정상 arm 오탐", as.character(r$reason))

# ── ⑧ 픽스처가 처치 기회를 실제로 만드는가 ────────────────────────────────
fx <- overlay_probe_fixture()
if (max(fx$M$dd, na.rm = TRUE) > 0.2 && length(unique(fx$hold$dbeta)) > 5L)
  ok(sprintf("⑧ 픽스처에 위기 구간 존재 (최대 낙폭 %.2f · dbeta 분산 있음)", max(fx$M$dd, na.rm = TRUE))) else
  ng("⑧ 픽스처가 밋밋하다 — 상수 노출이 arm 결함인지 픽스처 결함인지 구분 불가")

# ── ⑨ 잔여 픽스처 0 ────────────────────────────────────────────────────────
left <- list.files(ADIR, pattern = "^zz_probe_")
if (!length(left)) ok("⑨ 픽스처 잔여 0") else ng("⑨ 픽스처가 남았다", paste(left, collapse = ","))

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"overlay_probe","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
