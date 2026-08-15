## WT-D20260813_005 · S4 — alpha_package.json (AST v1.1 3층) + alpha_validation.json 발행
## ★L-194 순서: alpha_package.json write_json → record_package_lineage (역순 시 judge WARN_SEQUENCE)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_005/s4_emit_package.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
OUT <- "stage_artifacts/WT-D20260813_005"
SRC <- "stage_artifacts/fq233_probe0_20260813"
MB  <- "qepm/mailbox/worktask/WT-D20260813_005"
WT  <- "WT-D20260813_005"

S1 <- readRDS(file.path(OUT,"s1_factor_month_stats.rds"))
S2 <- readRDS(file.path(OUT,"s2_walkforward_result.rds"))
S3 <- readRDS(file.path(OUT,"s3_diagnostics.rds"))
SC <- readRDS(file.path(OUT,"s2_scores_all_arms.rds"))
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector = FALSE)
RES <- S2$RES; PR <- S2$PR; DG <- S3$DG

## ── 라이브 α̂ 재산출: FM 기울기를 **전기간 trailing**(파라미터 없음)으로 ────────────
## 초판은 임의로 최근 10년 창을 썼고 그 창에서만 기울기가 음수(−0.000209)였다 —
## 창 선택이 자유 파라미터가 되는 자리라 제거한다. 전기간 +0.003815(NW3 t +1.658),
## 최근 5y +0.001011, 중앙값 +0.003383 — 부호는 창-민감(challenge_flags 기록).
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
fwd <- pan[anchor %in% S1$anchors, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)][is.finite(fwd)]
jj <- merge(SC$OBJ_MEAN, fwd, by=c("Date","Ticker"))
sl <- jj[, { ok <- is.finite(score)&is.finite(fwd)
   if (sum(ok)<30) NA_real_ else unname(coef(lm(fwd[ok] ~ score[ok]))[2]) }, by=Date]
b_full <- mean(sl$V1, na.rm=TRUE); b_10y <- mean(tail(sl$V1[order(sl$Date)],120), na.rm=TRUE)
## ★같은 경로를 read_parquet 로 읽고 다시 쓰면 Windows error 1224 (mmap 이 자기 경로를 잠금).
##   S3 가 남긴 RDS 에서 재구성한다 — 읽기-쓰기 경로 충돌 자체를 만들지 않는다.
live <- as.data.table(S3$live)[, .(Ticker, score, n_valid, confidence = conf)]
live[, alpha_hat := b_full * score]
live[, confidence := pmin(1, pmax(0, confidence))]
setorder(live, -alpha_hat)
write_parquet(live, file.path(OUT,"alpha_vector_live_202608.parquet"))
cat(sprintf("라이브 α̂ 재산출: b_full=%+.6f (10y %+.6f) · n=%d · 평균 %+.4f%%\n",
            b_full, b_10y, nrow(live), 100*mean(live$alpha_hat)))

LIVE_SEL <- DG$live$selected_factors
## restatement 노출 — 재무제표 파생 리프만 restatement_prone (가격/유동성 파생은 아님)
.rp <- function(f) grepl("^(AC|Q|V|GR|IN|XF_LL|XF_RI|XF_GD)", f)
rest_exp <- sum(.rp(LIVE_SEL))
cat(sprintf("라이브 선별 %s · restatement_exposure=%d\n", paste(LIVE_SEL, collapse=", "), rest_exp))

gv <- function(x) if (is.null(x) || !is.finite(x)) NULL else unname(round(as.numeric(x), 6))
A <- function(a) RES[[a]]

pkg <- list(
  task_id = WT, as_of_date = "2026-08-13", forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  ## ★승계층 — alpha_hypothesis.json 원문 그대로 (재작성 금지, Charter 원칙 8)
  ##  falsification 만 **형식 변환**: schema/ast_spec_gate 는 field_dictionary 필드를 지목하는
  ##  객체배열을 요구하는데 승계 원문은 서술 문자열 + field_dictionary_refs 분리 형태였다.
  ##  내용은 원문 그대로 옮기고(축 3개·reject_if 원문) 필드 지목만 기계가독으로 붙인다 —
  ##  재설계가 아니라 표현 변환. 승계 refs 7종 전부 field_dictionary 내 존재 확인함.
  pit = list(sig_date = "2026-07-31", decision_ts = "2026-08-01"),
  hypothesis = list(
    statement   = HYP$selected$hypothesis_description,
    mechanism   = HYP$selected$mechanism,
    falsification = list(
      list(axis = "①집합 분기", fields = list("FDB-B1_registry_fundamental_quarterly",
             "FDB-B2_registry_rawdata_price_daily", "FDB-B3_registry_consensus_daily",
             "FDB-B4_registry_investor_flow_monthly"),
           expectation = "walk-forward 각 시점의 S_mean(신 목적함수 선별집합)과 S_rank(rank-IC 선별집합)가 서로 다른 팩터 집합이어야 한다. 월별 Jaccard 중앙값 > 0.8 이면 두 통계량이 사실상 같은 집합을 골라 함수형 교체가 결과를 바꿀 물리적 여지가 없음 → 성과와 무관하게 기전 부재로 기각.",
           measured = "Jaccard 중앙 0.1111 · 미발화(통과)"),
      list(axis = "②왜도 프로파일 분기", fields = list("A1_RAWDATA_OHLCVS_daily"),
           expectation = "S_rank-단독 채택 팩터군의 분위 왜도기울기가 S_mean-단독 군보다 유의하게 더 음이어야 한다(R32 기전 방향: 왜도기울기 음 ↔ 중앙값−평균 gap 양). 방향 불일치 또는 NW-t 로 구분 불가면 갈림의 드라이버가 왜도 구조라는 기전 기각.",
           measured = "차이 −0.1043 · NW3 t −9.788 · 예측 방향 일치 · 미발화(통과)"),
      list(axis = "③특이성 대조(negative control)", fields = list("FDB-B1_registry_fundamental_quarterly",
             "FDB-B2_registry_rawdata_price_daily"),
           expectation = "중앙값 스프레드로 선별한 대조 arm 은 rank-IC arm 대비 개선이 없어야 한다. 대조군이 paired NW3 t >= +2.0 로 개선되면 개선이 mean-정합 특이적이지 않다(임의 통계량 교체 효과) → 기전 서사 기각.",
           measured = "OBJ_MED paired NW3 t −0.667 · 미발화(통과)"),
      list(axis = "④국면 경계 관측(승계 regime_scope 의 부수 관측)",
           fields = list("E5_msm_crisis_prob", "E7_unified_regime_3layer"),
           expectation = "기전이 참이면 crisis 에서 갈림이 축소되고 평균 추정 분산이 폭증해 mean-선별 이득이 소멸·역전해야 한다.",
           measured = "advisory — non-crisis paired t +2.147 / crisis −2.766 · 사전등록이 판정 축 아님으로 라벨(검정력 한계)")
    ),
    falsification_reject_if_verbatim = HYP$selected$falsification$reject_if,
    falsification_note_on_tautology  = HYP$selected$falsification$note_on_tautology,
    regime_scope = HYP$selected$regime_scope,
    inherited_from = "alpha_hypothesis.json (alpha-hypothesis, model=fable, 2026-08-13) — 내용 무수정 승계, falsification 은 스키마 요구 형식으로 변환만"
  ),

  factors = list(list(
    factor_id = "F1_selstat_mean_composite",
    ast = list(
      leaf = "SPECIAL_OP",
      escape_contract = list(
        escape_type = "SPECIAL_OP",
        op_code_path = "stage_artifacts/WT-D20260813_005/s2_walkforward_arms.R::sel_topK + build_scores",
        walk_forward = TRUE
      )
    ),
    role = "core_signal",
    restatement_exposure = rest_exp
  )),
  combination_rule = "z_score_aligned_equal_weight",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = c(
      lapply(LIVE_SEL, function(f) list(leaf = paste0("factor_registry:", f),
        availability_rule = if (.rp(f)) "fixed: quarterly 45d / annual 익년 3-31 (C4)" else "fixed: price t-1 (C10)",
        restatement_prone = .rp(f))),
      list(list(leaf = "SPECIAL_OP", availability_rule = "walk-forward 선별 — 홀딩월 T 의 선별은 anchor < T 인 실현 통계만 소비",
                restatement_prone = FALSE))),
    verdict = "clean",
    evidence = paste0(
      "①위반 주입 대조 실측: 선별창에 홀딩월 자신을 포함(1개월 누출)시키면 PORT_t 0.9899→3.4289, ",
      "paired NW3 t 0.4930→4.1557 — 성과 축이 1개월 누출에 민감함을 실증(검사 판별력 확인). ",
      "②lag1 스트레스(창을 T−2 까지로 물림) PORT_t 0.5269 — LAG1 < clean < LOOKAHEAD 의 단조 lag-반응은 ",
      "오염이 아니라 약한 실신호의 지문. ③m_* full-sample 통계 선별 입력 사용 0(전 통계 trailing 재산출)."
    )
  ),

  alpha_vector = setNames(as.list(round(live$alpha_hat, 6)), live$Ticker),
  confidence_vector = setNames(as.list(round(live$confidence, 4)), live$Ticker),
  signal_matrix_ref = "stage_artifacts/WT-D20260813_005/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "selection_statistic_alignment (meta — 320종 factor DB 위의 선별층)",
    proxy = "walk-forward top-K(K=5) 선별 · 선별 통계량 = trailing(36m) top-분위(Q5) EW 평균 활성의 NW lag-3 t",
    formula = "score_i,t = mean_k∈S_t( Z_Score_Aligned_i,k,t ),  S_t = argtop5_f NW3t( {meanspread_f,m}_{m∈[t-36, t-1]} )",
    lag_rule = "선별: anchor < 홀딩월 (실현 완료 통계만) / 팩터 z: load_month_factors sig_date = 홀딩월 직전 월말",
    winsorization = "none (Z_Score_Aligned 연결자 산출 그대로 — C13)",
    neutralization = "none (post-neutralization IC는 진단으로 별도 산출)",
    economic_rationale = paste0(
      "rank 통계(중앙값 근사)로 고르고 top-N EW 평균(꼬리 지배)으로 소비하는 함수형 불일치가, ",
      "KR 분위-조건부 왜도 구조(개인 복권 수요 + 공매도 제약으로 청산 불가)에서 체계적 오선별을 만든다는 ",
      "가설의 직접 구현. 선별 통계량을 소비 형태와 같은 함수형으로 교체한다."),
    weight_theta = 1.0,
    references = list("Harvey-Liu-Zhu 2016 (다중검정 hurdle)", "Bailey-Lopez de Prado 2014 (DSR)",
                      "R32/R33 수정프레임 실측 (본 저장소)", "RAMP R6 realized-PORT_t 정렬 선별")
  )),

  diagnostics = list(
    ## ★1급 (실측) — metric_type = canonical_screen
    canonical_port_t_nw_lag3 = gv(A("OBJ_MEAN")$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue  = gv(A("OBJ_MEAN")$portfolio_alpha_t_pvalue),
    canonical_n_months       = A("OBJ_MEAN")$n_months,
    ## advisory (게이트 아님 — measurement-graduation §3)
    rank_ic = gv(DG$advisory$OBJ_MEAN$rank_ic),
    icir    = gv(DG$advisory$OBJ_MEAN$icir),
    monotonicity = gv(DG$advisory$OBJ_MEAN$monotonicity),
    subperiod_stability = gv(DG$advisory$OBJ_MEAN$subperiod$stability),
    turnover_proxy = gv(A("OBJ_MEAN")$turnover_annual),
    harvey_t_stat = gv(DG$advisory$OBJ_MEAN$harvey_t),
    post_neutralization_ic = gv(DG$advisory$OBJ_MEAN$post_neutralization_ic),
    ## 본 라운드 고유 — paired 판정
    primary_endpoint = list(
      definition = "paired 월별 active 차이 (OBJ_MEAN − OBJ_RANK) NW lag-3 t, 사전등록 문턱 +2.0",
      n_months = PR$OBJ_MEAN$n, mean_monthly = gv(PR$OBJ_MEAN$mean),
      annualized_pct = gv(100*12*PR$OBJ_MEAN$mean),
      nw3_t = gv(PR$OBJ_MEAN$t), threshold = 2.0, verdict = "NOT_SUPPORTED"),
    arms = lapply(setNames(c("OBJ_RANK","OBJ_MEAN","OBJ_MED","LOOKAHEAD","LAG1"),
                           c("OBJ_RANK","OBJ_MEAN","OBJ_MED","LOOKAHEAD","LAG1")), function(a)
      list(port_t_capw = gv(A(a)$portfolio_alpha_t_nw_lag3),
           active_sr_IR = gv(A(a)$net_sr), information_ratio = gv(A(a)$information_ratio),
           alpha_annualized = gv(A(a)$alpha_annualized), turnover_annual = gv(A(a)$turnover_annual),
           n_months = A(a)$n_months,
           paired_nw3_t_vs_base = if (a=="OBJ_RANK") NULL else gv(PR[[a]]$t))),
    basis_note = paste0("★basis: 계약 net_sr = mean(active)/sd(active)*sqrt(12) = **active SR(=IR)** 이지 total SR 아님. ",
                        "1급 축 = paired 월별 active NW3 t(primary) + canonical PORT_t(cap-w 벤치, 자본 축) 병기."),
    metric_type = "canonical_screen",
    metric_type_note = "canonical_screen_bt() 실측. 자본 판정 아님 — graduation HARD 3종은 forge-authoritative 값에만 적용."
  ),

  selection_objective = "canonical_port_t",

  challenge_flags = list(
    "[판정] primary NOT_SUPPORTED — paired NW3 t = +0.4930 < 사전등록 문턱 +2.0. '선별 통계량 교체는 이 프레임에서 레버 아님'.",
    "[정보성] 반증축 3종 전부 미발화 = 기전의 구조 사슬은 확인됨(①집합 분기 Jaccard 중앙 0.111 ≪ 0.8 ②왜도 프로파일 분기 NW3 t −9.79 예측방향 ③negative control −0.667 미개선). 끊어진 고리는 마지막 하나 — '갈림이 실현 전이 개선을 만든다'.",
    "[검정력 실증] 위반 주입(1개월 누출) arm 이 동일 paired 통계에서 t = +4.1557 를 산출 — n=221 에서 문턱 +2.0 크기 효과는 탐지 가능. NOT_SUPPORTED 는 검정력 부족의 산물이 아님.",
    "[advisory·판정 아님] 국면 분해가 사전등록 regime_scope 와 방향 일치: non-crisis paired t +2.1467 / crisis −2.7656, crisis_alpha OBJ_MEAN −0.0154 vs OBJ_RANK +0.0058. ★사전등록이 국면축을 '판정 축 아님' 으로 명시 라벨했으므로 primary 승격 금지(사후선택). 별도 사전등록 라운드로만 적법 — next_probe 1호.",
    "[정보성] OBJ_MEAN 은 rank 계열 advisory 전 지표에서 열위(rank_ic 0.0203 vs 0.0373 · ICIR 0.175 vs 0.370 · harvey_t 2.34 vs 5.30 · mono 0.081 vs 0.132 · postNeutIC 0.0157 vs 0.0278)인데 실현 소비 축에서는 소폭 우위(PORT_t 0.990 vs 0.947 · IR 0.267 vs 0.228 · alpha_ann 0.0953 vs 0.0697). rank-IC advisory 강등 교리의 독립 재현 — 단 우위는 유의하지 않음.",
    "[안정성 반론 소거] '평균 선별은 불안정' 반론은 실측에서 성립 안 함 — 자기-겹침 Jaccard 3 arm 전부 0.6667 동일, 회전율 배율 1.027 (상쇄 판정선 1.5 미달). 즉 null 의 원인은 선별 불안정이 아니다.",
    "[★승계 자산 결함 — Q-Lead 조치 요망] 인계가 지목한 지문 출처 `master_panel_FIXED.rds` 가 원천(`load_month_factors`)에서 재현되지 않는다: 27종 무작위 표본 중 cor>=0.99 는 8종뿐(중앙 0.9257, 3종 <0.5), 지문 팩터 M04_Mom_1 은 cor 0.3372. 같은 표본에서 lane_a 패널은 27/27 종 cor>=0.9945. ⇒ 지문 3종을 그대로 적용하면 **원천-충실 패널이 오히려 탈락**한다. 본 라운드는 지문 규약을 '원천 재현성 + IC 프로파일 정상성' 으로 대체하고 그 사실을 PREREG/challenge_note 에 명시 기록(No Silent Override). R32/R33 결론이 이 패널 위에 있으므로 소급 점검 필요 — 단 R32 전제 4종은 원천-충실 패널에서 재현됨(부호갈림 127/320 vs 123 · 비대칭 99 vs 28 vs 102 vs 21 · cor(왜도기울기,gap) −0.6755 vs −0.728).",
    "[★데이터 지뢰] lane_a 패널에 실현 미완료 홀딩월 2건 혼입 — anchor 2026-09-01 은 **전 종목 fwd = 정확히 0.000000**(결손이 정상값 모양으로 내려앉음), 2026-08-01 은 월중 부분수익(평균 +13.6%). 본 라운드는 anchor <= 2026-07-01 로 절단. 이 패널을 쓰는 다른 소비자도 동일 절단 필요.",
    "[한계] 라이브 α̂ 스케일 b 는 창-민감: 전기간 FM 기울기 +0.003815(NW3 t +1.658) / 최근 10y −0.000209 / 최근 5y +0.001011. 파라미터 없는 전기간을 채택했으나 부호 안정성 미확보 — alpha_vector 방향을 배포 근거로 쓰지 말 것.",
    "[한계] 어느 arm 도 자본 자격 근처 아님 (cap-w PORT_t 0.38~0.99 ≪ 2.95). 본 산출은 선별층 실험이지 전략 승격 후보가 아니다. dual-basis 병기: EW-유니버스 대비 PORT_t OBJ_MEAN +2.2606 / OBJ_RANK +2.0878 — 두 arm 모두 벤치 basis 전환에서 함께 올라가므로 basis 가 paired 판정을 뒤집지 않음.",
    "[승계 보관] q90 상방 분위 표적 · arm C 분포형태(CRPS) · quality 46종 DIST-QPM-003 대조 — 별도 사전등록 라운드로만 적법(가설 에이전트 challenge_flags 승계).",
    "[교차 해석 의무 승계] WT-D20260802_003(realized-PORT_t 정렬 조합가중)과 교차 — 본 건 음성이므로, 그쪽이 양성이면 드라이버는 '실현 경로·성과지속' 쪽으로 좁혀진다(R6 기전 분해 정보 생산)."
  )
)

dir.create(MB, showWarnings = FALSE, recursive = TRUE)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, na = "null", digits = 8)
cat(sprintf("저장: %s/alpha_package.json (%.1f KB)\n", MB, file.size(file.path(MB,"alpha_package.json"))/1024))

## ── alpha_validation.json ──────────────────────────────────────────────────────
val <- list(
  task_id = WT, produced_by = "alpha-research", produced_at = as.character(Sys.time()),
  prereg_ref = "stage_artifacts/WT-D20260813_005/PREREG_impl_lock.md (측정 착수 전 봉인)",
  selection_type = "chain", selection_objective = "canonical_port_t",
  design = list(K = S2$K, trailing_window_months = S2$W, top_n = S2$TOPN, cost_bps_oneway = S2$COST,
                quantile = "Q5 of 5", n_factors_material = 320, combination = "z_score_aligned_equal_weight",
                normalization_held_constant = "3 arm 전부 NW lag-3 t — '평균 vs 순위' 축만 격리",
                n_holding_months = 221, period = "2008-03-01 ~ 2026-07-01",
                universe = "KOSPI200 ∪ KOSDAQ150 (패널 승계, 월중앙 344종목)",
                benchmark = "IKS200 (.cache/benchmark.parquet 일별 → apply.monthly(Return.cumulative), ym 키)"),
  primary_endpoint = list(nw3_t = gv(PR$OBJ_MEAN$t), threshold = 2.0, verdict = "NOT_SUPPORTED",
                          mean_monthly = gv(PR$OBJ_MEAN$mean), annualized_pct = gv(100*12*PR$OBJ_MEAN$mean)),
  falsification = list(
    axis1_set_divergence = list(jaccard_median = gv(median(S2$jaccard$mean_rank)),
      reject_if = "> 0.8", fired = FALSE,
      note = "두 통계량이 실제로 다른 집합을 고른다 — 기전이 작동할 물리적 여지 확인"),
    axis2_skew_profile = DG$falsification_2,
    axis3_negative_control = list(objmed_paired_nw3_t = gv(PR$OBJ_MED$t), reject_if = ">= +2.0",
      fired = FALSE, note = "대조군 미개선 — 개선이 임의 통계량 교체 효과가 아님(단 본 라운드는 개선 자체가 미달)")),
  stability_cost_test = list(turnover_ratio_mean_over_rank = gv(S2$to_ratio), threshold = 1.5,
    self_overlap_jaccard_median = list(OBJ_RANK = gv(median(S2$selfj[[1]], na.rm=TRUE)),
      OBJ_MEAN = gv(median(S2$selfj[[2]], na.rm=TRUE)), OBJ_MED = gv(median(S2$selfj[[3]], na.rm=TRUE))),
    verdict = "미발화 — 불안정 비용 가설 기각(회전율 배율 1.027)"),
  detection_power = list(
    design = "PREREG §4 — 선별창에 홀딩월 자신을 포함시킨 위반 주입 arm(LOOKAHEAD) 실측",
    lookahead_port_t = gv(RES$LOOKAHEAD$portfolio_alpha_t_nw_lag3),
    clean_port_t = gv(RES$OBJ_MEAN$portfolio_alpha_t_nw_lag3),
    delta = gv(RES$LOOKAHEAD$portfolio_alpha_t_nw_lag3 - RES$OBJ_MEAN$portfolio_alpha_t_nw_lag3),
    lookahead_paired_t = gv(PR$LOOKAHEAD$t), lag1_paired_t = gv(PR$LAG1$t),
    lag1_port_t = gv(RES$LAG1$portfolio_alpha_t_nw_lag3),
    verdict = "판별력 있음 — 1개월 누출이 PORT_t 를 +2.44, paired t 를 +3.66 이동. 따라서 clean arm 의 PIT 통과 진술이 근거로 성립하고, NOT_SUPPORTED 도 검정력 부족의 산물이 아니다.",
    monotone_lag_response = "LAG1 0.527 < clean 0.990 < LOOKAHEAD 3.429 — 단조 lag-반응 = 오염이 아니라 약한 실신호의 지문"),
  advisory = DG$advisory, dsr = DG$dsr, regime_advisory = DG$regime_advisory,
  dual_basis = DG$dual_basis, ax001_v2 = DG$ax001_v2,
  frame_check = S1$frame_check, r32_replication = S1$r32_replication,
  inherited_asset_defect = list(
    asset = "stage_artifacts/fq233_probe0_20260813/master_panel_FIXED.rds",
    finding = "원천(load_month_factors) 재현 실패 — 27종 표본 중 cor>=0.99 8종(중앙 0.9257, 3종 <0.5). 지문 팩터 M04_Mom_1 cor 0.3372.",
    control = "동일 표본에서 lane_a_feature_panel.parquet 는 27/27 cor>=0.9945 (중앙 0.9982)",
    action = "지문 규약을 '원천 재현성 + IC 프로파일 정상성' 으로 대체 후 진행. No Silent Override — PREREG/challenge_note 기록.",
    downstream = "R32/R33 결론이 이 패널 기반 — 소급 점검 필요. 단 R32 전제 4종은 원천-충실 패널에서 재현됨."),
  method_shopping_log = list(candidates_tried = 3,
    method_log = list(
      list(name = "OBJ_RANK (base, rank-IC 선별)", port_t = gv(RES$OBJ_RANK$portfolio_alpha_t_nw_lag3), selected = FALSE),
      list(name = "OBJ_MEAN (primary, 평균 스프레드 선별)", port_t = gv(RES$OBJ_MEAN$portfolio_alpha_t_nw_lag3), selected = TRUE),
      list(name = "OBJ_MED (negative control)", port_t = gv(RES$OBJ_MED$portfolio_alpha_t_nw_lag3), selected = FALSE)),
    note = "LOOKAHEAD/LAG1 은 후보가 아니라 **검사 판별력 대조군** — 선택 풀에 포함되지 않음. K·W 스윕 0회(단일 고정, PREREG §1)."),
  routing = list(
    verdict = "not-supported → 재료 축 라우팅 (승계 on_failure 규약)",
    destination = "FQ-234 (일별 축 재료) · 비-return 원천",
    forbidden = "계열 확대 금지 (INV-7) — 선별 통계량 변형 추가 탐색 금지",
    next_probe = list(
      "P1: 국면 조건부 선별 — 본 라운드 advisory 에서 non-crisis paired t +2.1467 / crisis −2.7656 로 사전등록 regime_scope 와 방향 일치. 국면 게이팅(crisis 에서 rank-선별로 전환)을 **새 사전등록**으로 검정. 사후선택이므로 본 라운드 데이터로 판정 금지 — primary/문턱/국면 라벨 규약을 착수 전 봉인할 것.",
      "P2: 선별 통계량이 아니라 **결합 가중** 축 — WT-D20260802_003(realized-PORT_t 정렬 조합가중) 결과와 교차. 본 건 음성 + 그쪽 양성이면 드라이버는 실현 경로·성과지속(R6 분해 정보).",
      "P3: 승계 자산 결함 소급 — master_panel_FIXED 를 소비한 R32/R33 및 하류 결론의 원천-충실 재산출(본 라운드가 재산출 경로 s1_build_monthly_factor_stats.R 를 남겨둠).",
      "P4: ★분위 깊이 불일치 — 본 라운드의 선별 통계량은 Q5(상위 20%, 월 ~69종)인데 소비는 top-25(~7.3%)다. 가설의 핵심 주장이 '소비 형태와 같은 함수형' 인데 깊이가 3배 어긋나 정합이 부분적이다. 소비 깊이에 맞춘 선별 통계량(top-25 상당 분위 또는 top-N 직접 평균)으로 재검정 — 사후 변경 금지이므로 본 라운드 판정은 Q5 로 확정하고 별도 사전등록 라운드로만 적법.",
      "P5: 결합층 교란 — 선별 K=5 를 EW 평균으로 합치는 단계가 '단일 팩터의 상위분위 평균 우위' 를 희석할 수 있다(두 arm 공통이라 편향은 아니나 효과 감쇠 요인). K=1 선별 또는 선별통계 가중 결합으로 감쇠 여부만 분리 측정.")),
  revival_condition = "선별 통계량 축의 부활 조건: (a) 국면 조건부 P1 이 사전등록 하에 양성이거나 (b) 재료 축이 mean/rank 갈림이 더 큰 패널(일별·비-return)을 제공할 때. 그 전까지 이 프레임(월간·return-파생 320종·top-25 EW)에서 재도전 금지."
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, na = "null", digits = 8)
cat(sprintf("저장: %s/alpha_validation.json (%.1f KB)\n", OUT, file.size(file.path(OUT,"alpha_validation.json"))/1024))

## ── lineage (L-194: package write 이후) ────────────────────────────────────────
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id = WT, package_type = "alpha_package",
    method_selected = "walk-forward K=5 selection by trailing NW3-t of top-quintile mean active spread (OBJ_MEAN) vs rank-IC base",
    input_file_paths = c(file.path(SRC,"lane_a_feature_panel.parquet"),
                         file.path(SRC,"master_panel_FIXED.rds"),
                         ".cache/benchmark.parquet", ".cache/msm_daily_latest.parquet"))
  TRUE }, error = function(e) { cat("lineage 실패:", conditionMessage(e), "\n"); FALSE })
cat(sprintf("lineage 기록: %s\n", if (ok) "OK" else "FAILED(수동 확인 필요)"))
