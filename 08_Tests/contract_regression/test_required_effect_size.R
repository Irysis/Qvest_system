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

t_summary("test_required_effect_size")
