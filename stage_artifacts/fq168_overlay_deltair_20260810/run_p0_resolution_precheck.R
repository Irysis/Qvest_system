## FQ-168 P0 — 착수 전 확인: 이 라운드가 **낼 수 있는 결론의 종류**
## 사전등록(측정 전 고정, 이 주석이 정본):
##  FQ-168 = "섹터-중립 역전 신호를 PG2 오버레이(하위 25% long 축소)로 소비 → **ΔIR 측정**".
##  ★08-09 실측(메모리 [[project-delta-ir-threshold-below-measurement-resolution-20260809]]):
##    블록부트 se = 73m 0.094 / **269m 0.046** ⇒ 문턱 ΔIR>=0.05 는 **1.09 se** =
##    **해상도 아래**. 2se 도달에 **911개월(76년)**. ⇒ **탈락 판정은 유효(5.2se 밖), 통과 판정은 불가.**
##  ⇒ 착수 전에 이 라운드가 무엇을 확정할 수 있는지 못박는다. 오늘 '착수 전 확인' 4/4 적중.
##  산출: ①현 창(266m)에서의 ΔIR se 와 문턱 대비 배수 ②유의하게 검출 가능한 최소 ΔIR
##        ③가능한 결론 목록(무엇을 주장할 수 있고 무엇을 못 하는가)
##  판정:
##   D1_PASS_UNAVAILABLE : 문턱 0.05 가 2se 미만 → **통과 주장 불가**. 라운드는 '탈락 또는 미해결' 만 낸다
##   D2_PASS_AVAILABLE   : 0.05 >= 2se → 통과 주장 가능
##  ★자본 주장 없음. base 명시: incumbent = STR_1715_on_M4gAE_R05_noLayer4_PG2 (IR 1.416,
##    ir_convention=net_active_recon_v1) — H2 가 원장에서 재구성 확인한 값.
##  ★read-only(계산만).
suppressPackageStartupMessages({ library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## 08-09 실측 앵커 (블록부트, block=12)
SE_269 <- 0.046; N_269 <- 269L
SE_73  <- 0.094; N_73  <- 73L
THRESH <- 0.05                      # §4 admission 문턱
N_NOW  <- 266L                      # FQ-168 가용 창

## se 는 대략 1/sqrt(n) 로 스케일 — 두 앵커로 상수 추정 후 현 창에 적용(외삽 아님, 내삽)
k1 <- SE_269 * sqrt(N_269); k2 <- SE_73 * sqrt(N_73)
k  <- mean(c(k1, k2))
cat(sprintf("[앵커] se*sqrt(n): 269m %.3f · 73m %.3f → 상수 %.3f (일치도 %.1f%%)\n",
            k1, k2, k, 100*(1 - abs(k1-k2)/k)))
se_now <- k / sqrt(N_NOW)
cat(sprintf("[현 창] n=%d ⇒ 추정 se(ΔIR) = **%.4f**\n", N_NOW, se_now))
ratio <- THRESH / se_now
cat(sprintf("\n★문턱 %.2f 는 **%.2f se** 에 해당\n", THRESH, ratio))
min_detect <- 2 * se_now
cat(sprintf("  유의(2se) 검출 가능한 **최소 ΔIR = %.4f**  (문턱의 %.1f배)\n", min_detect, min_detect/THRESH))
n_needed <- (k / (THRESH/2))^2
cat(sprintf("  문턱 0.05 를 2se 로 만들려면 **n ≈ %.0f 개월 (%.0f년)**\n", n_needed, n_needed/12))

pass_ok <- ratio >= 2
verdict <- if (pass_ok) "D2_PASS_AVAILABLE" else "D1_PASS_UNAVAILABLE"
cat(sprintf("\n판정: %s\n", verdict))
cat("\n=== 이 라운드가 낼 수 있는 결론 ===\n")
if (!pass_ok) {
  cat("  ✓ **탈락**: ΔIR 점추정이 -2se 밖이면 '기여 없음' 을 주장할 수 있다 (유효)\n")
  cat(sprintf("  ✓ **미해결**: |ΔIR| < %.4f 면 verdict_ci=UNRESOLVED — **'통과' 로 읽지 말 것**\n", min_detect))
  cat("  ✗ **통과 불가**: ΔIR >= 0.05 가 나와도 그것은 **해상도 아래**라 admission 근거가 못 된다\n")
  cat("  ⇒ 사전등록에 이 3분류를 못박고, 결과를 '통과' 로 서술하지 않는다\n")
}
cat("\n[base 명시] incumbent = STR_1715_on_M4gAE_R05_noLayer4_PG2 · IR 1.416 · net_active_recon_v1\n")
cat("  (H2 가 book_state 원장에서 재구성 확인. ΔIR 은 base 조건부이므로 이 명시가 필수)\n")
cat("⚠se 추정은 두 앵커의 1/sqrt(n) 내삽이다 — 실측 시 블록부트로 재산출할 것\n")
write_json(list(verdict = verdict, se_estimated = se_now, threshold = THRESH,
                threshold_in_se = ratio, min_detectable_delta_ir = min_detect,
                months_needed_for_2se = n_needed,
                anchors = list(list(n=N_269, se=SE_269), list(n=N_73, se=SE_73)),
                incumbent = list(id = "STR_1715_on_M4gAE_R05_noLayer4_PG2",
                                 ir = 1.416, convention = "net_active_recon_v1",
                                 source = "book_state.json via H2")),
           file.path(OUT, "p0_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
