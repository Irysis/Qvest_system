# ============================================================================
# test_required_effect_size.R — contract regression for required_effect_size.R
# Target (read-only): 02_Infrastructure/contracts/required_effect_size.R
#
# Covered:
#   - audit_input 구조 가드: n 의 정체(seeds/names/trials 거부) · 출처 필드 필수
#     · 판정 필드에 요약 필드(next_action/title/hypothesis) 거부
#   - required_effect 단조성 (n 증가 -> 필요 효과 감소) 및 design 간 순서
#   - verdict_with_power 분기 (PASS / INCONCLUSIVE_UNDERPOWERED / NEGATIVE_POWERED)
#
# 위반 주입 근거: 2026-08-08 실제로 발생한 두 오류를 픽스처로 고정한다.
#   (1) 'n=20' 을 표본크기로 읽었으나 실제는 random25_null_n_seeds(시드 개수)
#   (2) 요약 필드(next_action)의 센 표현을 근거로 원장을 비판(판정 필드는 신중했음)
#
# ★루트 해석은 helpers.R::t_root() 경유(경로 정규화 함수 직접 호출 없음).
# ============================================================================
suppressPackageStartupMessages({ library(data.table) })

.here <- Sys.getenv("QVEST_TEST_DIR", "")
if (!nzchar(.here)) {
  .rt <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(.rt)) .rt <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(.rt)) .rt <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  .here <- file.path(.rt, "08_Tests/contract_regression")
}
stopifnot(dir.exists(.here))
source(file.path(.here, "helpers.R"))
ROOT <- t_root()
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))

errs <- function(expr) inherits(tryCatch({ expr; NULL }, error = function(e) e), "error")

# --- audit_input 구조 가드 (위반 주입: 오늘 실제로 낸 오류를 픽스처화) --------
t_check("audit_input: 시드수를 표본으로 투입 -> 차단",
        errs(audit_input(20, "seeds", "measure_result.random25_null_n_seeds",
                         "attribution_verdict", -0.018)))
t_check("audit_input: 종목수를 표본으로 투입 -> 차단",
        errs(audit_input(25, "names", "measure_result.n_names", "verdict", -0.018)))
t_check("audit_input: 시행수를 표본으로 투입 -> 차단",
        errs(audit_input(200, "trials", "measure_result.n_trials", "verdict", -0.018)))
t_check("audit_input: 요약 필드(next_action)를 판정 근거로 -> 차단",
        errs(audit_input(118, "months", "measure_result.n_months", "next_action", -0.018)))
t_check("audit_input: title 을 판정 근거로 -> 차단",
        errs(audit_input(118, "months", "measure_result.n_months", "title", -0.018)))
t_check("audit_input: n 출처 필드 누락 -> 차단",
        errs(audit_input(118, "months", "", "attribution_verdict", -0.018)))
t_check("audit_input: 정상 입력 -> 통과",
        !errs(audit_input(118, "months", "measure_result_20260726.n_months",
                          "attribution_verdict", -0.018)))

# --- required_effect 단조성 / design 간 순서 ---------------------------------
t_check("required_effect: n 증가 -> 필요 효과 감소",
        required_effect(269, design = "full")$required_annual <
          required_effect(28, design = "full")$required_annual)
t_check("required_effect: split > full (동일 n)",
        required_effect(80, design = "split")$required_annual >
          required_effect(80, design = "full")$required_annual)
t_check("required_effect: interaction(ON 35%) > split (동일 n)",
        required_effect(80, design = "interaction", regime_frac = 0.35)$required_annual >
          required_effect(80, design = "split")$required_annual)

# --- verdict_with_power 분기 -------------------------------------------------
t_check("verdict: t 문턱 통과 -> PASS",
        verdict_with_power(2.5, 0.02, 80)$verdict == "PASS")
t_check("verdict: 작은 효과 + t 미달 -> INCONCLUSIVE_UNDERPOWERED",
        verdict_with_power(1.2, 0.001, 28)$verdict == "INCONCLUSIVE_UNDERPOWERED")
t_check("verdict: 큰 효과 + t 미달 -> NEGATIVE_POWERED",
        verdict_with_power(1.2, 0.05, 269)$verdict == "NEGATIVE_POWERED")

# --- 바 퇴화 검출 (2026-08-08 WT-001 적대검증 렌즈1 적발) --------------------
# 위반 주입: arm 자신의 sd 를 바로 쓰면 NEGATIVE_POWERED 가 도달 불가해진다.
# WT-D20260808_001 P1/P2 실구성 재현 — sd_monthly = arm 자신의 delta sd.
local({
  n <- 295; sd_arm <- 0.02560
  se_arm <- sd_arm / sqrt(n)               # 실제 NW 팽창 없음(delta 계열 무상관)
  m_obs  <- 1.2 * se_arm                   # t = 1.2 (문턱 미달)
  v <- verdict_with_power(1.2, m_obs, n, sd_monthly = sd_arm)
  t_check("바 퇴화: arm 자신 sd -> INCONCLUSIVE_BAR_RESTATES_T",
          v$verdict == "INCONCLUSIVE_BAR_RESTATES_T")
  t_check("바 퇴화: NEGATIVE_POWERED 도달 불가 표기",
          isFALSE(v$negative_powered_reachable))
  t_check("바 퇴화: implied_t 가 문턱x팽창(2.5) 근방",
          abs(v$implied_t_threshold - 2.5) < 0.01)
})
# 음성 대조 1: 외부 기준 sd (배포 노이즈가 arm 보다 훨씬 큼) -> 기존 의미 유지
t_check("음성대조: 외부 기준 바 -> INCONCLUSIVE_UNDERPOWERED 유지",
        verdict_with_power(1.2, 0.001, 28)$verdict == "INCONCLUSIVE_UNDERPOWERED")
# 음성 대조 2: 바가 느슨 -> NEGATIVE_POWERED 정상 도달
local({
  v <- verdict_with_power(1.2, 0.05, 269)
  t_check("음성대조: 느슨한 바 -> NEGATIVE_POWERED 유지", v$verdict == "NEGATIVE_POWERED")
  t_check("음성대조: 느슨한 바는 도달 가능 표기", isTRUE(v$negative_powered_reachable))
})
# 음성 대조 3: PASS 경로도 진단 필드를 실는다
t_check("PASS 도 진단 필드 보유", is.finite(verdict_with_power(2.5, 0.02, 80)$implied_t_threshold))

t_summary("test_required_effect_size")
