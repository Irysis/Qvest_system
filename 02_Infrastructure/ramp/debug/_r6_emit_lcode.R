## _r6_emit_lcode.R — R6 L-code 적립 (mode=ramp, backtested, performance)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/ramp/ramp_loop.R")

lesson <- paste0(
 "RAMP R6: 선별 기질을 relevance(R4/R5)에서 realized-PORT_t(trailing 배포권 실측 성과)로 교체 = R5 부활신호 발화. ",
 "결과: 기질 교체는 실재 선별 신호 — P-pure(top-K풀 EW) best Ppure_W36_K20 cap-w PORT_t=2.61(RAMP 사상 최고, base_all11 1.02·ctrl_all102 0.24 대비), ",
 "paired NW-t vs base_all11 +2.25(K20 both>=2.0), vs ctrl_all102(동일 substrate, 순수 선별격리) +3.01 — R4/R5 relevance 계열이 base 대비 flat~음(-2.5~+0.18)이던 것과 대비되는 첫 양(+) 선별 신호. ",
 "기전: trailing PORT_t rank 자기상관 0.86(W36)/0.92(W60) 매우 높음(선별 예측력 실재). 풀=Value 지배(0.31~0.35, LowRisk 0.03 — R4 방어 과선별과 정반대). ",
 "그러나 자본 졸업 FALSE: HARD 3종 미달(best PORT_t 2.61<2.95·oos_retention -0.08<0.7·calmar 0.45<0.64; DSR 1.95 통과). 개선은 pre-2017 집중(paired pre +2.05/+3.99, post +1.27/+0.61)·post-2017 절대 SR은 -0.56→-0.11로 개선하나 여전히 음 → 2017+ decay 전이 벽이 binding. ",
 "Boruta 한계 기여=음: P-boruta vs P-pure paired -2.58/-3.25(R4 '과선별 손해' 재현 — PORT_t-풀서도 Value 과집중). ",
 "판정: KILL=FALSE(선별-정렬 축 미소진 — RAMP 최강 선별 레버) + graduation=FALSE(screen-tier: 신호 실재·자본 미달) + Boruta-on-PORT_t-pool 소진(음). ",
 "pin_ok=TRUE(base_all11_W36==R4 base_W36_EW bit-identical Δ0). n_trials family=16(R4 4+R5 6+R6 6). vintage r4r5_session_20260711."
)

res <- ramp_document(
  strategy_id = "RAMP_R6_PORTT_BORUTA_20260711",
  grade = "C",
  lesson_text = lesson,
  construction_type = "composite",
  selection_type = "sweep",
  mechanism_hypothesis = paste0(
    "trailing realized-PORT_t 상위 팩터 풀 선별(PIT trailing-only NW-t lag3) = R4/R5 relevance-objective 선별의 ",
    "부활신호 치료. 기질(라벨)을 rank-relevance에서 배포권 실현 성과로 교체하면 선별이 base breadth 대비 개선되나, ",
    "return-derived substrate의 post-2017 decay가 자본 졸업을 막는다(선별 효율↑ ≠ 벽 극복)."),
  core_reference = "L-RAMP-20260711_181539(R4)·L-RAMP-20260711_184155(R5)·measurement-graduation §6·project-factor-of-factors-scoping",
  portfolio_alpha_t = 2.61,
  oos_retention = -0.08,
  oos_months = 24,
  falsification_attempts = 6,
  metrics = list(
    round = "R6",
    best_ppure_model = "Ppure_W36_K20",
    best_ppure_pt_capwt = 2.61, best_ppure_pt_EWuni = 3.92,
    best_ppure_calmar = 0.45, best_ppure_dsr = 1.95, best_ppure_post17_sr = -0.11,
    base_all11_W36_pt_capwt = 1.02, ctrl_all102_W36_pt_capwt = 0.24,
    max_paired_trait_vs_base11 = 2.25, max_paired_selection_vs_all102 = 3.01,
    max_paired_boruta_vs_pure = -2.58, min_paired_boruta_vs_pure = -3.25,
    best_pboruta_pt_capwt = 1.29,
    trailing_rank_autocorr_W36 = 0.86, trailing_rank_autocorr_W60 = 0.92,
    pool_value_share_W36 = 0.31, pool_lowrisk_share_W36 = 0.04,
    kill = FALSE, kill_pure = FALSE, kill_boruta = TRUE, graduation = FALSE, pin_ok = TRUE,
    n_trials_r6 = 6, n_trials_family = 16, n_pool_factors = 102,
    config_hash_ref = "r6_portt_boruta_prereg_20260711.json",
    verdict = "screen_tier_selection_axis_open_substrate_decay_binding"
  ),
  dry_run = FALSE
)
cat("EMIT_DONE l_code=", res$l_code %||% res$lcode$l_code %||% "?", "\n")
str(res, max.level=1)
