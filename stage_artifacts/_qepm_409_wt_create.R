#!/usr/bin/env Rscript
# QEPM WT 생성 — 409-batch 검증 후보 3종 (de-contaminated 레시피 + 약점 타깃)
suppressWarnings(suppressMessages({ library(jsonlite) }))
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a
source(file.path(QM, "02_Infrastructure/worktask/worktask_manager.R"))

INCUMBENT <- "STR_1715_AR_on_M4_R05_overlay_PG2 (book IR 1.5754, 100% weight)"

specs <- list(
  list(
    title = "QEPM409-VAL_DIVERSIFIER: 밸류 4팩터 diversifier sleeve (cluster28 decontam)",
    desc = paste0(
      "[검증출처] 409-batch cluster28 대표 EN_61_paradigm_rot. 라벨('FF5앙상블')은 codegen 오염 — ",
      "실제 레시피=밸류 4팩터 EW 콤보 V01_BM+V03_CFP+V10_FCF_Yield+V11_Shareholder_Yield, n=30, monthly. ",
      "[실측 baseline] CAGR 15.86% / Sharpe 0.676 / IR 0.354 / MDD 64.3% / TO 113.9% / severe45=3 / corr_core 0.713(=409 중 유일 진짜 diversifier). ",
      "[약점] (1) MDD 64% 구조적 (2) standalone SR 0.68 (목표 2.5 미달) (3) 밸류 단일축 crowding. ",
      "[QEPM 목표] risk-research: Σ+tail+crowding(밸류 군집)+incumbent 상관진단 / optimizer: CVaR·risk-budget으로 MDD 64%->대폭 축소 + 25종 long-only / governor: incumbent ", INCUMBENT,
      " 대비 book-marginal ΔIR>=0.05 검증(밸류틸트가 quality/momentum core를 분산하는가). KR VALUE corr~0.76 기확립 진실 정합 확인."),
    theme = "value_diversifier"
  ),
  list(
    title = "QEPM409-CORE_COMPOSITE: 10팩터 풀복합 core (cluster12 decontam, grade A)",
    desc = paste0(
      "[검증출처] 409-batch cluster12 대표 RC_16_disp_vol_dual (유일 standalone-filter 통과, hurdle grade A / auth essence grade C). ",
      "라벨('Dispersion×Vol')은 오염 — 실제=10팩터 EW 복합 D01_IdioVol+D02_Beta+M07_IndMom+M01_Mom_12_1+M05_Trended_Mom+Q01_GPA+Q04_Piotroski_F+Q09_CFOA+Q07_Earnings_Stability+V01_BM, n=30, monthly. ",
      "[실측 baseline] CAGR 17.24% / Sharpe 0.803 / IR 0.438 / MDD 48.4% / TO 121.6% / severe45=1 / corr_core 1.00(사실상 incumbent와 동일 스트림). ",
      "[약점] (1) MDD 48% (2) SR 0.80 (목표 2.5 미달) (3) incumbent corr 1.0 = book-marginal 0 위험. ",
      "[QEPM 목표] risk/optimizer가 MDD를 overlay/risk-budget로 축소해 risk-adjusted 개선 가능한지 + incumbent ", INCUMBENT,
      " 대비 우열/중복 정직판정. 예상: standalone admit 불가(=incumbent), 진단 가치는 'core를 QEPM이 얼마나 개선하나' 기준점."),
    theme = "core_composite"
  ),
  list(
    title = "QEPM409-QUAL_DEFENSE: 퀄리티 4팩터 저MDD 방어 sleeve (cluster23 decontam)",
    desc = paste0(
      "[검증출처] 409-batch cluster23 대표 ML_12_svm. 라벨('SVM')은 codegen 오염 — ",
      "실제=퀄리티 4팩터 EW 콤보 Q01_GPA+Q04_Piotroski_F+Q09_CFOA+Q07_Earnings_Stability, n=30, monthly. ",
      "[실측 baseline] CAGR 12.2% / Sharpe 0.61 / IR 0.105 / MDD 46.7%(409 중 최저급) / TO 108.9% / severe45=1 / corr_core 0.87. ",
      "[약점] (1) IR 0.105 매우 약함 (2) 저수익(CAGR 12%) (3) corr_core 0.87 분산효과 제한. 강점=저MDD·저TO. ",
      "[QEPM 목표] 저MDD 퀄리티를 방어 sleeve로 — optimizer가 risk-budget로 IR 끌어올리고 incumbent ", INCUMBENT,
      " 대비 book-marginal ΔIR>=0.05(방어 보완) 검증. AX-001 v2 방어형 조건부평가(crisis_alpha + Core 대비 MDD 완화) 적용."),
    theme = "quality_defense"
  )
)

ids <- character(0)
for (s in specs) {
  wt <- wt_create(
    hypothesis_title = s$title,
    theme = s$theme,
    wt_type = "discovery",
    hypothesis_description = s$desc,
    universe = "KOSPI200_KOSDAQ150_intersection",
    benchmark = "KOSPI200_total_return"
  )
  id <- if (is.list(wt)) (wt$task_id %||% wt$wt_id %||% wt$id) else wt
  if (is.null(id)) id <- as.character(wt)
  ids <- c(ids, id)
  cat("CREATED:", id, "|", s$theme, "\n")
}
cat("\nALL_WT_IDS:", paste(ids, collapse=","), "\n")
writeLines(jsonlite::toJSON(list(wt_ids=ids, themes=sapply(specs,`[[`,"theme"),
           incumbent_book_ir=1.5754, incumbent=INCUMBENT), auto_unbox=TRUE, pretty=TRUE),
           file.path(QM, "stage_artifacts/_qepm_409_wt_map.json"))
