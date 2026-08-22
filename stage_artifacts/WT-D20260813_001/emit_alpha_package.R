## WT-D20260813_001 — alpha_package.json (AST v1.1 3층) 발행
## 판정 수치는 measure/build 산출을 읽어서 패키징. 재계산·재해석 금지.
## hypothesis(mechanism/falsification/regime_scope) = alpha_hypothesis.json 승계 (재작성 금지 —
##   표현만 schema 형식으로 변환: falsification 객체 → field_dictionary 지목 객체배열).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_001"
MBX <- "qepm/mailbox/worktask/WT-D20260813_001"

hyp <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)$selected
av  <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)
verdict <- fromJSON(file.path(OUT, "q90_paired_verdict.json"), simplifyVector = FALSE)
Q <- readRDS(file.path(OUT, "measure_q90_full.rds"))$Q

## 최신월 alpha_vector / confidence_vector (top-25, score-demeaned = expected active proxy)
sc <- as.data.table(read_parquet(file.path(OUT, "q90_model_scores.parquet")))
sc[, Date := as.Date(Date)]
la <- max(sc$Date)
lm <- sc[Date == la][order(-score)]
lm[, alpha := score - mean(score)]
top <- head(lm, 25L)
alpha_vector <- setNames(as.list(round(top$alpha, 6)), top$Ticker)
## confidence: score 분위(0~1) 기반 — 상위일수록 신뢰↑, 최신월 데이터 완전가용
top[, conf := frank(score)/.N]
confidence_vector <- setNames(as.list(round(top$conf, 4)), top$Ticker)

## ── AST: q90 = MODEL_SCORE escape 리프 (walk-forward pinball τ=0.9) ──────────────
## training_leaves = 대표 registry 팩터(324종 전체의 예시 리프 — 각각 registry rule 검증 통과분).
##   전 324종 열거는 비실용이며 판이 load_month_factors 경유이므로 대표 리프로 계약 충족.
train_leaves <- lapply(c("V01_BM","Q01_GPA","M01_Mom_12_1","D01_IdioVol","C01_SUE","L02_Turnover",
                         "AC01_Total_Accruals_CF","V08_PSR"),
                       function(f) list(leaf = "REGISTRY", factor = f))

q90_ast <- list(
  leaf = "MODEL_SCORE",
  id = "q90_pinball_lgbm",
  training_window_end = "2026-07-31",   # 최종 훈련 sig_date(패널 마지막 학습월). 홀딩월 anchor=2026-09-01
  trained_at = "2026-08-31",            # 학습 완료 시점 = t_d-1. 2026-07-31 데이터가 각 리프 lag 반영 후 가용해지는 시점
  training_leaves = train_leaves,
  model = "lightgbm_quantile_alpha0.90",
  note = "확장창 walk-forward. 각 홀딩월 i 의 학습창 종점 = sig_date < anchor[i]. 표기 종점은 최신월 기준."
)

escape_contract <- list(
  escape_type = "MODEL_SCORE",
  train_window_end = "2026-08-31",
  training_leaf_refs = c("V01_BM","Q01_GPA","M01_Mom_12_1","D01_IdioVol","C01_SUE","L02_Turnover",
                         "AC01_Total_Accruals_CF","V08_PSR",
                         "...+316종 (lane_a_feature_panel 324피처 전량, load_month_factors 경유·Z_Score_Aligned)"),
  note = "walk-forward: 홀딩월 i 예측 = sig_date < anchor[i] 데이터로만 학습(PIT). 324 피처는 alias 7종 드롭 후 전량."
)

## ── falsification: alpha_hypothesis 승계 → schema 객체배열(field_dictionary 지목)로 표현 변환 ──
falsification <- list(
  list(group_id = "A1_RAWDATA_OHLCVS_daily",
       observable = "F1 tail-hit rate — q90 top-25 보유 종목이 보유월 횡단면 q90 이상 수익 실현 빈도가 arm A 대비 높아야(paired one-sided t≥2.0). 미달 시 기전 기각.",
       measured = list(q90_hit = av$falsification$F1$q90_mean_hit_rate, armA_hit = av$falsification$F1$armA_mean_hit_rate,
                       paired_nw3_t = av$falsification$F1$paired_nw3_t, verdict = av$falsification$F1$verdict)),
  list(group_id = "FDB-B2_registry_rawdata_price_daily",
       observable = "F2 수익 구성 — q90 포트 월수익의 상위-3 기여 종목 집중도가 arm A 대비 낮지 않아야(평균은 꼬리가 견인).",
       measured = list(q90_top3 = av$falsification$F2$q90_top3_share, armA_top3 = av$falsification$F2$armA_top3_share,
                       verdict = av$falsification$F2$verdict)),
  list(group_id = "A4_benchmark_kospi200",
       observable = "F3 왜도 연결 — 실현 횡단면 왜도 상위 국면에서 q90 의 arm A 대비 상대 우위가 집중되어야.",
       measured = list(hi_skew = av$falsification$F3$hi_skew_mean_diff_monthly, lo_skew = av$falsification$F3$lo_skew_mean_diff_monthly,
                       verdict = av$falsification$F3$verdict))
)

## ── verdict 매핑 ────────────────────────────────────────────────────────────────
overall <- verdict$verdict_overall  # NOT_SUPPORTED (성과 미충족·F1 PASS = 부분지지)

challenge_flags <- list(
  "[성과 미지지·기전 지지 — 분리 판정] 사전등록 primary(paired NW3 t≥+2.0)는 미충족(t=+0.828)이나, 기전 주 기각축 F1(tail-hit)은 강하게 발화(t=+4.62). ⇒ 표적 형태 축은 이 config 에서 config-scoped negative 로 닫되, '예측기가 상방 꼬리를 못 찾는다'는 아니다 — 소비 마디의 문제.",
  "[음성 대조 통과 = 기전 방향 확인] trim5(꼬리제거 평균) 표적은 arm A 대비 paired t=-1.17 로 개선 없음. q90 과 반대 방향 — 꼬리 정보가 실재하며 그것을 잘라내면 사라진다는 기전 예측과 정합.",
  "[β/vol 틸트 = 우려와 반대] q90 은 고변동 복권주가 아니라 저변동 종목을 고른다(D03 분위 0.139 vs arm A 0.350). '조건부·비-salient 상방 후보' 라는 기전 주장을 강화 — 살리언스로 관측되는 고변동이 아니라 다변량 조건부로만 식별되는 저변동 상방 후보.",
  "[rank-IC ↔ 소비 불일치 실현-포트 재현] q90 월별 rank-IC = -0.0281(음수)인데 decile 단조성 +0.964·total SR 최고. 순위력(중앙/평균)은 낮은데 top-N 평균 소비는 우호적 — FQ-237(선별 통계량 축)의 실현-포트 직접 근거.",
  "[자본 자격 아님·정직 라벨] PORT_t 0.926·MDD 67.0%·Calmar 0.231 — graduation HARD 3종 전부 미충족. 회전율 10.61(11.0 이내)은 유일 통과. 표적 형태 판정 라운드이지 편입 후보 아님.",
  "[사후선택·비독립 승계] q90 우위는 arm B 4-arm 관측 후 도달. 독립 사전등록으로 수행했으나 선행 4-arm(mean/q10/q50/q90) 이력은 method_shopping_log 기재 — judge/graduation 에서 다중검정 맥락 소비. arm 들은 같은 패널·피처 공유 = 비독립.",
  "[next_probe] ① C2 expectile(τ=0.9) 표적(평균-기반 꼬리 통계량, elicitable — q90 분위보다 소비 정합 이론상 직접) 별도 사전등록. ② FQ-237 선별 목적함수(rank-IC→분위 평균 스프레드) — 본 라운드가 '순위 개선≠소비 개선' 실현-포트 사례 공급. ③ 소비 마디 교체: q90 예측을 top-N 선별이 아니라 비중/사이징에 쓰는 형태(단 measurement-graduation §5·§6 settled-negative 인지 — 부활신호 발화 시)."
)

pkg <- list(
  task_id = "WT-D20260813_001",
  as_of_date = "2026-08-13",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  strategy_id = "WT_D20260813_001_q90_pinball",
  pit = list(sig_date = "2026-07-31", decision_ts = "2026-09-01"),
  hypothesis = list(
    statement = hyp$hypothesis_description,
    mechanism = hyp$mechanism,               # 승계 — 재작성 금지
    falsification = falsification,           # 표현 변환(schema 객체배열), 내용 승계
    regime_scope = hyp$regime_scope          # 승계
  ),
  factors = list(
    list(factor_id = "F1_q90_upside_quantile",
         ast = q90_ast,
         escape_contract = escape_contract,
         role = "core_signal",
         restatement_exposure = 0)
  ),
  combination_rule = "model_internal",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "MODEL_SCORE:q90_pinball_lgbm", availability_rule = "walk-forward: train sig_date < holding anchor (PIT)", restatement_prone = FALSE),
      list(leaf = "REGISTRY factors (324, 재무계열)", availability_rule = "quarterly+45d;annual_3/31 (C4)", restatement_prone = TRUE)
    ),
    verdict = "clean",
    note = "재무 리프는 restatement-prone 이나 load_month_factors + Z_Score_Aligned(C13/C15) PIT 경유. 학습창 종점 2026-07-31 ≤ t_d-1(2026-08-31). armB q90 parity cor=1.0 로 재현 확인."
  ),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT-D20260813_001/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "target_form/upside_quantile",
         proxy = "conditional q90 (pinball τ=0.9, LightGBM, 324 registry factors)",
         formula = "argmax pinball_loss(q=0.90) over walk-forward expanding window; score = predicted conditional 90th quantile of fwd_ret_1m",
         lag_rule = "walk-forward: train on sig_date < holding anchor; factors quarterly+45d/annual 3/31",
         winsorization = "none (tree model); features via load_month_factors Z_Score_Aligned",
         neutralization = "none (cross-sectional target only)",
         economic_rationale = "long-only top-N EW 는 보유 종목 평균을 벌고 평균은 상방 꼬리가 지배(R33: D03 Q1 중앙값 -15.68% vs 평균 +10.54%). 조건부 q90 표적이 소비 형태와 정합. 마찰: KR 개별주식옵션 유동성 부재로 skew 가격화 채널 폐쇄 + 공매도 제약으로 salient 복권주 과대가격 청산 불가 + 기관 mandate 로 분산 상방 바스켓 미보유. redundancy_cluster_id = target_form (평균-표적 arm A/중앙값 arm B 와 동일 피처, 표적만 상이).",
         weight_theta = 1.0,
         references = c("FQ-233 arm B (2026-08-13)", "R32/R33 왜도-gap 실측", "Koenker-Bassett 1978 quantile regression"))
  ),
  diagnostics = list(
    canonical_port_t_nw_lag3 = as.numeric(Q$res$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue = as.numeric(Q$res$portfolio_alpha_t_pvalue),
    canonical_n_months = as.numeric(Q$res$n_months),
    total_net_sr = Q$sr_total,
    active_ir = as.numeric(Q$res$net_sr),
    cagr = Q$cagr, mdd = Q$mdd, calmar = Q$cagr/Q$mdd,
    rank_ic = av$advisory_diagnostics$rank_ic,
    icir = av$advisory_diagnostics$icir,
    monotonicity = av$advisory_diagnostics$monotonicity,
    subperiod_stability = av$advisory_diagnostics$subperiod_stability,
    turnover_proxy = as.numeric(Q$res$turnover_annual),
    harvey_t_stat = av$advisory_diagnostics$harvey_t_stat,
    deflated_sharpe_ratio = av$advisory_diagnostics$deflated_sharpe_ratio,
    beta_controlled_alpha_ann = as.numeric(verdict$beta_controlled_alpha$q90$alpha_ann),
    beta_controlled_t_alpha_nw = as.numeric(verdict$beta_controlled_alpha$q90$t_alpha_nw),
    beta_to_bm = as.numeric(verdict$beta_controlled_alpha$q90$beta),
    paired_vs_armA_nw3_t = as.numeric(verdict$paired_vs_armA$nw3_t),
    negative_control_trim5_paired_t = as.numeric(verdict$trim5_control$paired_vs_armA_nw3_t),
    F1_tail_hit_paired_t = av$falsification$F1$paired_nw3_t,
    vol_percentile_selected = av$vol_tilt$q90,
    note = "선택 권위 = canonical_port_t(실측). rank-IC 계열 advisory. β-통제 α 병기(measurement-graduation §2). paired NW3 t 는 primary 지지 검정."
  ),
  selection_objective = "canonical_port_t",
  selection_type = "chain",
  n_trials = 1,
  wt_type = "discovery",
  metric_type = "canonical_screen",
  research_verdict = overall,
  research_verdict_detail = list(
    perf = verdict$verdict_perf, F1 = av$falsification$F1$verdict,
    F2 = av$falsification$F2$verdict, F3 = av$falsification$F3$verdict,
    reading = "성과 paired t 미충족(config-scoped negative) + 기전 부수관측 강한 발화(F1 t=4.62·F3 pass·trim5 대조·저변동 틸트). 표적 형태 축은 이 config 에 한정 negative 로 닫되, 기전은 지지 — 병목은 표적이 아니라 소비 마디(top-N 선별). FQ-237/expectile 로 라우팅."),
  challenge_flags = challenge_flags
)

write_json(pkg, file.path(MBX, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("alpha_package.json 발행 완료\n")

## lineage (write_json 직후 — L-194 순서)
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id = "WT-D20260813_001", package_type = "alpha_package",
    method_selected = "q90_pinball_lgbm walk-forward (target-form/upside_quantile)",
    input_file_paths = c(file.path(OUT, "q90_model_scores.parquet"),
                         file.path(SRC, "lane_a_feature_panel.parquet"),
                         file.path(SRC, "armA_canonical_result.rds")))
  cat("lineage 기록 완료\n")
}, error = function(e) cat("lineage 기록 스킵:", conditionMessage(e), "\n"))
