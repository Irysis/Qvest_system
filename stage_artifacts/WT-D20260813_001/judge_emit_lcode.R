root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/axiom/lcode_emit.R"))

lc <- emit_qepm_lcode(
  strategy_id = "WT-D20260813_001",
  grade       = "F",
  source      = "judge_gate",
  metric_type = "backtested",
  lesson_text = paste0(
    "q90 상방-분위(pinball τ=0.9 LightGBM, 324 registry 피처) 표적을 arm A(평균 표적) 대비 ",
    "독립 사전등록·paired 판정. forge 실측 권위: PORT_t(NW lag-3)=0.837(<2.95), ",
    "β-통제 t(α)=1.207(|t|<2 → 알파 존재 주장 불가), oos_retention=-0.855(<0.7, 3분할 전부 음수 -0.486/-0.855/-0.927), ",
    "calmar=0.212(<0.64), MDD=66.9%(구조적 drawdown hard-fail: 55%+ episode 5·max underwater 39개월), ",
    "SR=0.578·CAGR=14.2%. no_signal_gate=INDISTINGUISHABLE_FROM_NO_SIGNAL(diff_ann +7.3%p·NW-t 0.972·control PORT_t -0.859) ",
    "= 성과가 시총상위 무신호 대조와 구별 불가, 신호 기여 미증명. graduation HARD 3종 전패 → Grade F(essence 권위). ",
    "그러나 병목은 표적이 아니라 소비 마디: F1 tail-hit paired t=+4.62(예측기가 상방 꼬리 종목을 실제로 식별) ",
    "∧ rank-IC=-0.028 ∧ decile-mono=+0.964 = rank-IC↔소비 불일치가 실현-포트에서 재현. ",
    "top-N EW 가 분포를 평균으로 접어 꼬리 정보를 소멸시킴. trim5(꼬리제거) 음성대조 paired t=-1.17 로 방향 정합. ",
    "선별 통계량 교체(FQ-237)는 표적 통계량만 개선(Pearson IC t↑)하고 PORT_t 는 악화 = 결합·이산 top-N 소비 마디가 벽. ",
    "config-scoped negative(target-form family 판결 아님, INV-7)."),
  mechanism_hypothesis = paste0(
    "long-only top-N EW 는 보유 종목 평균을 벌고 평균은 소수 종목의 상방 점프가 지배(R33: D03 Q1 중앙값 -15.68% vs 평균 +10.54%). ",
    "KR 개별주식옵션 유동성 부재로 skew 가격화 채널 폐쇄 + 공매도 제약 + 기관 mandate 마찰 → 비-salient 조건부 상방 후보 방치. ",
    "조건부 q90 표적이 소비 형태와 정합적이나, 소비 마디(평균 basis top-N EW)가 분포 정보를 흡수하지 못해 표적 정합이 성과로 전이 실패."),
  construction_type = "composite",
  portfolio_alpha_t = 0.8366,
  oos_retention     = -0.855,
  selection_type    = "chain",
  falsification_attempts = list(
    list(test = "primary paired NW3 t vs arm A (mean target)", result = "falsified", effect_retained = 0.828),
    list(test = "F1 tail-hit rate paired NW3 t (mechanism)",    result = "survived",  effect_retained = 4.622),
    list(test = "F2 top-3 contribution concentration",          result = "falsified", effect_retained = -0.0091),
    list(test = "F3 skew-linkage (hi-lo skew regime)",          result = "survived",  effect_retained = 1.694),
    list(test = "trim5 negative control (tail-removed mean)",   result = "survived",  effect_retained = -1.171),
    list(test = "no_signal_gate vs top-N mega-cap control",     result = "falsified", effect_retained = 0.972)
  ),
  metrics = list(sharpe = 0.578, mdd_pct = 66.9, cagr_pct = 14.2)
)
cat("L_CODE_PATH:", if (is.list(lc)) (lc$path %||% lc$l_code_path %||% lc$file %||% "") else as.character(lc), "\n")
cat("L_CODE_OBJ:\n"); str(lc, max.level = 1)
saveRDS(lc, file.path(root, "stage_artifacts/WT-D20260813_001/judge_lcode_obj.rds"))
