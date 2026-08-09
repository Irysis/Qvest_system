## A2 — 검정력 바 (측정 순서 ① : 사전등록 *전에* 산출)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source("02_Infrastructure/contracts/required_effect_size.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A2] ", fmt, "\n"), ...))

## 실측 창 후보 (a1 산출 기준. 확정치는 a3 에서 갱신)
cands <- list(
  list(lab = "층3 단독(λ=0) 전창",            n = 284L),
  list(lab = "infl 가용창(expanding z 36m)",   n = 246L),
  list(lab = "결합창(β_s 가용, 예상)",         n = 211L)
)
say("=== 전표본 설계의 필요 효과 (t=2.0, sd=%.4f 25EW쌍 실측, NW k=%.2f) ===",
    SPREAD_SD_MONTHLY_25EW, NW_INFLATION_DEFAULT)
tab <- rbindlist(lapply(cands, function(c0) {
  r <- required_effect(n = c0$n, design = "full")
  data.table(design = c0$lab, n = c0$n, eff_n = r$effective_n,
             req_monthly = r$required_monthly, req_annual_pct = r$required_annual*100)
}))
print(tab)

say("")
say("=== 참고 — 분할/상호작용을 했을 때 (본 라운드는 분할 금지, 대비용) ===")
tab2 <- rbindlist(lapply(c(0.40, 0.25, 0.10, 0.05), function(f) {
  r <- required_effect(n = 209L, design = "interaction", regime_frac = f)
  data.table(regime_frac = f, eff_n = r$effective_n, req_annual_pct = r$required_annual*100)
}))
print(tab2)

say("")
say("=== HARD 3종 문턱의 implied 효과 (n=209, cap-w active) ===")
say("PORT_t 2.95 도달 필요 월효과 = %.4f (연 %.2f%%)",
    required_effect(209L, t_threshold = 2.95)$required_monthly,
    required_effect(209L, t_threshold = 2.95)$required_annual*100)

say("")
say("★ 사전등록 규칙(측정 전 고정): 본 라운드의 '기각' 라벨은 F4 플라시보 paired 차이 sd 를")
say("  외부 기준으로 재산출한 required_effect 대비 관측/필요 비 >= 1.0 인 검정에서만 발동한다.")
say("  플라시보 sd 는 infl 순열 arm 에서만 나오므로 실측 증분을 보기 전에 확정 가능하다(FQ-165 선례).")
say("  미충족이면 판정 = INCONCLUSIVE_UNDERPOWERED — 소비면 종료 근거로 쓰지 않는다(FQ-172 비대칭 방지).")

write_json(list(
  generated_at = as.character(Sys.time()),
  sd_reference = list(value = SPREAD_SD_MONTHLY_25EW,
                      source = "top-25 EW 바스켓 쌍 월수익차 실측(required_effect_size.R)",
                      band = SPREAD_SD_BAND),
  nw_inflation = NW_INFLATION_DEFAULT,
  bars = tab, interaction_reference = tab2,
  rule = "기각 라벨은 F4 플라시보 paired sd 기준 관측/필요 >= 1.0 에서만 발동"
), "stage_artifacts/WT-D20260809_004/a2_power_bar.json", pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("저장 완료")
