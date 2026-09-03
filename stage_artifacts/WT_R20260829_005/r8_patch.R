# ── R8 — Self-Adversarial Challenge 결과를 risk_package 에 반영 (ACCEPT 2건 포함)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")
TID <- "WT-R20260829_005"
R2<-readRDS(file.path(OUT,"risk_r2.rds")); R3<-readRDS(file.path(OUT,"risk_r3.rds"))
R4<-readRDS(file.path(OUT,"risk_r4.rds")); R5<-readRDS(file.path(OUT,"risk_r5.rds"))
A <-readRDS(file.path(OUT,"risk_r7_adversarial.rds"))
pkg <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector = FALSE)
REG <- R4$REG

## ── ACCEPT-1 : 레짐 상관 주장 철회 (중첩창이 n 을 부풀렸다) ─────────────────
pkg$risk_summary$regime_correlation$finding <- paste0(
  "★자기적대검증에서 **철회**된 주장이 있다. 창 단위로 세면 HIGHVOL ",
  round(REG[regime=="HIGHVOL", mean_pairwise_cor],4), " vs LOWVOL ",
  round(REG[regime=="LOWVOL", mean_pairwise_cor],4), " (+",
  round(100*(REG[regime=="HIGHVOL", mean_pairwise_cor]/REG[regime=="LOWVOL", mean_pairwise_cor]-1),1),
  "%) 로 크게 갈리지만, 24개월 창은 서로 23개월을 공유하므로 112/123 이라는 월 수는 독립 관측이 아니다. ",
  "연속 구간(에피소드) 단위로 다시 재면 HIGHVOL n=", A$sc4$highvol_ep_n, " 평균 ",
  round(A$sc4$highvol_ep_mean,4), " vs LOWVOL n=", A$sc4$lowvol_ep_n, " 평균 ",
  round(A$sc4$lowvol_ep_mean,4), ", p=", round(A$sc4$p_highvol_lowvol,3),
  " 로 **유의하지 않다**. CRISIS vs NORMAL 은 에피소드 단위에서 차이가 사실상 0 이다(",
  round(A$sc4$crisis_ep_mean,4), " vs ", round(A$sc4$normal_ep_mean,4), ", p=",
  round(A$sc4$p_crisis_normal,3), "). ",
  "∴ 판정 = **미결(검정력 부족)**. '변동성 국면에서 분산효과가 사라진다'는 서술을 하류가 인용해서는 안 된다. ",
  "실측으로 남는 것은 방향 국면(BULL ", round(REG[regime=="BULL", mean_pairwise_cor],4), " vs BEAR ",
  round(REG[regime=="BEAR", mean_pairwise_cor],4), ")이 공동움직임을 **거의 바꾸지 않는다**는 것뿐이며, ",
  "이 null 은 두 값이 소수점 셋째자리까지 같다는 점에서 검정력 문제와 무관하게 읽힌다.")
pkg$risk_summary$regime_correlation$power_check <- list(
  problem = "후행 24개월 창은 인접 창과 23개월을 공유한다. 창 수를 관측 수로 세면 n 이 24배 부풀려진다.",
  effective_independent_windows = list(CRISIS = 64/24, NORMAL = 171/24, HIGHVOL = 112/24,
                                       LOWVOL = 123/24, BULL = 146/24, BEAR = 89/24),
  episode_level_test = list(
    method = "연속 국면 구간마다 rho_bar 평균 1관측 -> Welch t-test",
    highvol_n = A$sc4$highvol_ep_n, highvol_mean = round(A$sc4$highvol_ep_mean,5),
    lowvol_n = A$sc4$lowvol_ep_n, lowvol_mean = round(A$sc4$lowvol_ep_mean,5),
    p_highvol_vs_lowvol = round(A$sc4$p_highvol_lowvol,5),
    crisis_n = A$sc4$crisis_ep_n, crisis_mean = round(A$sc4$crisis_ep_mean,5),
    normal_n = A$sc4$normal_ep_n, normal_mean = round(A$sc4$normal_ep_mean,5),
    p_crisis_vs_normal = round(A$sc4$p_crisis_normal,5)),
  verdict = "UNRESOLVED_UNDERPOWERED — 국면별 상관 이동은 본 표본에서 확립되지 않았다.")

## ── ACCEPT-2 : RF-R2 통과가 형식적임을 명시 ────────────────────────────────
pkg$diagnostics$shrinkage_detail$threshold_clearance_audit <- list(
  finding = paste0("★자기적대검증: 개별분산 바닥을 0.25 -> 0.40 으로 올려 condition 을 ",
    round(R3$cal[floor_frac==0.25, cond],1), " -> ", round(R5$cond_m,1),
    " 로 낮췄지만, 그 변경이 소비량(무작위 25종 균등 바스켓 500개의 예측 변동성)에 준 영향은 ",
    "수준 ", sprintf("%+.2f%%", A$sc2$level_shift_040_pct), " · 순위상관 ",
    round(A$sc2$spearman_025_040,4), " (0.50 까지 올려도 ", sprintf("%+.2f%%", A$sc2$level_shift_050_pct),
    ") 이다. 즉 **RF-R2 통과는 산술이지 수리가 아니다** — 문턱을 넘긴 것이지 조건수가 실제로 문제였던 것을 고친 게 아니다."),
  honest_reading = paste0("p=340 단일시장 주식 Sigma 에서 condition number 는 본질적으로 ",
    "(시장 고유값)/(최소 개별분산) 규모로 결정된다. 이 비가 수백이 되는 것은 추정 결함이 아니라 ",
    "주식 공분산의 구조다. 소비자가 실제로 알아야 할 양은 조건수 임계 통과 여부가 아니라 ",
    "**Sigma 가 PD 이고 역행렬이 안정한가**이며, 그 답은 min_eigenvalue = ",
    signif(R5$min_eig_m,4), " (월간) 로 양수이고 축퇴가 없다는 것이다."),
  floor_kept_because = "바닥 상향은 무해하고(소비량 불변) 방향이 보수적이다(소형주 개별위험 과소평가를 줄인다). 그래서 유지하되, 통과를 근거로 삼지는 않는다.",
  sensitivity = list(mean_pred_vol_floor_025 = round(A$sc2$mean_vol_f025,6),
                     mean_pred_vol_floor_040 = round(A$sc2$mean_vol_f040,6),
                     mean_pred_vol_floor_050 = round(A$sc2$mean_vol_f050,6),
                     spearman_025_vs_040 = round(A$sc2$spearman_025_040,6)))
pkg$red_flags[[2]]$detail <- paste0(pkg$red_flags[[2]]$detail,
  " ★단, 이 통과는 형식적이다 — diagnostics.shrinkage_detail.threshold_clearance_audit 참조. ",
  "조건수 임계는 p=340 주식 Sigma 에서 판별력이 없다.")

## ── 비퇴화 검증 (등재 계약의 non-degeneracy 취지) ──────────────────────────
pkg$diagnostics$non_degeneracy_check <- list(
  question = "채택한 factor_bwb_d 가 표본공분산과 실제로 구별되는가(폴백한 추정기가 아닌가).",
  offdiag_corr_vs_sample = round(A$sc1$corr_offdiag_factor_vs_sample, 4),
  offdiag_corr_lwnls_vs_sample = round(A$sc1$corr_offdiag_lwnls_vs_sample, 4),
  relative_frobenius_vs_sample = round(A$sc1$frob_factor, 4),
  relative_frobenius_lwnls_vs_sample = round(A$sc1$frob_lwnls, 4),
  rms_correlation_difference = round(A$sc1$rms_corr_diff, 4),
  verdict = "PASS — 상관 비대각의 표본 대비 상관이 0.694 로 뚜렷이 구별된다(lw_nls 는 0.951 로 사실상 표본).",
  practical_caveat = paste0("단 정직하게 덧붙이면, **분산된 25종 바스켓의 예측 변동성 수준**에서는 차이가 작다 — ",
    "무작위 500 바스켓에서 예측 vol 상관 ", round(A$sc1$basket_vol_corr,4), ", 평균 절대차 ",
    round(A$sc1$basket_vol_meanabsdiff_pct,2), "%. 팩터모형의 실익은 vol 수준 개선이 아니라 ",
    "(i) 340/340 전종목 적재 (ii) 위험 귀속 분해 가능 (iii) p>n 구간으로 창을 줄여도 붕괴하지 않는 구조다."))

## ── 무신호 대조 (RF-R1 을 대조 없이 읽지 않기) ─────────────────────────────
pkg$red_flags[[1]]$detail <- paste0(pkg$red_flags[[1]]$detail,
  " ★무신호 대조 병기: 같은 유니버스에서 **무작위 25종 균등** 바스켓 500개의 시장 분산비중은 평균 ",
  round(A$sc6$random_mean,3), " (sd ", round(A$sc6$random_sd,3), ", 범위 ",
  round(A$sc6$random_min,3), "~", round(A$sc6$random_max,3), ") 다. ",
  "기준바스켓의 ", round(A$sc6$ew_top25,3), " 는 그 무신호 기준선보다 **낮다**. ",
  "즉 RF-R1 은 발화하지만 그 원인은 이 전략의 선택이 아니라 롱온리 주식바스켓의 형태다 — ",
  "선택은 오히려 시장 지배도를 낮추는 방향으로 작동했다(스타일/섹터 분산이 비시장 분산을 더한다). ",
  "가중방식별 실측: EW 유니버스 340종 ", round(A$sc6$ew_universe340,3),
  " / K200 cap-w ", round(A$sc6$k200_capw,3), " — 시장 지배도는 가중방식 불변이 아니다.")
pkg$risk_summary$no_signal_control <- list(
  design = "유니버스 340종에서 무작위 25종 균등 바스켓 500개 (신호 미사용). Sigma 는 동일.",
  market_variance_share = list(random_mean = round(A$sc6$random_mean,4), random_sd = round(A$sc6$random_sd,4),
                               reference_basket = round(A$sc6$ew_top25,4),
                               ew_universe_340 = round(A$sc6$ew_universe340,4),
                               k200_capw = round(A$sc6$k200_capw,4)),
  reading = "위험구조 진단에서 '시장이 75%'는 대조 없이는 해석 불가다. 무신호 기준선이 87.4% 이므로 본 후보는 그보다 12.5%p 낮다.")

## ── 소비자용 기계가독 수준보정 계수 ─────────────────────────────────────────
pkg$handoff_to_optimizer$level_calibration_factor <- list(
  value = round(R5$bias_final$bias_stat, 4),
  meaning = "Sigma 에서 나온 월간 표준편차에 이 값을 곱하면 walk-forward 실현 분산도와 정합한다.",
  apply_to = "절대 위험목표 / CVaR 예산 / TE 상한 등 **수준** 기반 제약",
  do_not_apply_to = "MVO 계열 비중 산출(균일 스칼라배 불변). 적용해도 비중은 바뀌지 않는다.",
  decomposition = list(in_sample_daily = round(R5$CAL[basis=="ew_top25_reference", ratio],4),
                       temporal_aggregation = round(R5$agg_ratio,4),
                       out_of_sample_staleness = round(R5$bias_final$bias_stat /
                         (R5$CAL[basis=="ew_top25_reference", ratio] * R5$agg_ratio), 4)),
  applied_to_emitted_sigma = FALSE,
  why_not_applied = "관측된 배율을 Sigma 에 조용히 곱하면 추정치와 보정치가 한 객체에 섞여 하류가 되돌릴 수 없다. 계수를 분리해 넘긴다.")

## ── self-adversarial 기록 ───────────────────────────────────────────────────
pkg$self_adversarial_challenge <- list(
  performed = TRUE, protocol = "v8.2 Self-Adversarial (Codex Round 대체)",
  n_self_concerns = 6L,
  concerns = list(
    list(id="SC-1", concern="채택 추정기가 표본공분산의 폴백에 불과할 수 있다(비퇴화 실패).",
         classification="REBUTTAL",
         basis=paste0("실측 반증. 비대각 상관의 표본 대비 상관 ", round(A$sc1$corr_offdiag_factor_vs_sample,3),
           ", 상대 Frobenius ", round(A$sc1$frob_factor,3), " (lw_nls 는 각각 ",
           round(A$sc1$corr_offdiag_lwnls_vs_sample,3), " / ", round(A$sc1$frob_lwnls,3), " 로 사실상 표본). ",
           "단 분산된 바스켓 vol 수준 차이는 ", round(A$sc1$basket_vol_meanabsdiff_pct,2), "% 로 작다는 한계를 함께 공시한다.")),
    list(id="SC-2", concern="개별분산 바닥 0.40 은 RF-R2 문턱(500)에 맞춰 고른 값이다 — 문턱 맞춤.",
         classification="ACCEPT",
         basis=paste0("인정. 실측으로 확인된 바 바닥 변경은 소비량을 바꾸지 않는다(수준 ",
           sprintf("%+.2f%%", A$sc2$level_shift_040_pct), ", 순위상관 ", round(A$sc2$spearman_025_040,4),
           "). RF-R2 통과를 '조건수 수리'로 서술하지 않고 형식적 통과임을 패키지에 명시하도록 수정했다."),
         fix="diagnostics.shrinkage_detail.threshold_clearance_audit 신설 + RF-R2 detail 정정"),
    list(id="SC-3", concern="bias 1.384(38% 과소표시)를 알면서 보정 없이 Sigma 를 넘기는 것이 정직한가.",
         classification="PARTIAL",
         basis="Sigma 에 조용히 곱하면 추정과 보정이 한 객체에 섞인다(No Silent Override). 대신 기계가독 계수로 분리 발행하고 적용/미적용 대상을 명시했다.",
         fix="handoff_to_optimizer.level_calibration_factor 신설"),
    list(id="SC-4", concern="레짐 상관 결론이 중첩창으로 부풀린 n 위에 서 있다.",
         classification="ACCEPT",
         basis=paste0("인정. 에피소드 단위 재검에서 HIGHVOL vs LOWVOL p=", round(A$sc4$p_highvol_lowvol,3),
           ", CRISIS vs NORMAL p=", round(A$sc4$p_crisis_normal,3), " 로 어느 쪽도 유의하지 않다. ",
           "월 단위 +57.8% 는 유효 독립관측 4.7 vs 5.1 위에서 나온 수였다."),
         fix="risk_summary.regime_correlation.finding 를 '미결(검정력 부족)'로 교체 + power_check 신설"),
    list(id="SC-5", concern="gerber_rmt 가 bias 1위(1.069)인데 조건수로 기각했다 — 사후 기준 선택 아닌가.",
         classification="REBUTTAL",
         basis=paste0("selection_objective 는 계약 enum(condition_number)으로 사전 고정되어 있고 alpha 수익축을 참조하지 않았다. ",
           "더 결정적으로 gerber_rmt 의 상관 보존율은 1.626 — 표본 대비 상관을 63% 증폭한다. ",
           "bias 우위는 정확도가 아니라 증폭의 부산물이며, cond 1.008e4 로 Sigma^-1 소비가 불가하다. ",
           "다만 '만약 목적함수가 bias 였다면 gerber 가 이긴다'는 사실을 method_shopping_log 에 그대로 남겼다.")),
    list(id="SC-6", concern="RF-R1(시장 74.9%)을 대조 없이 HIGH 로 올리는 것은 형태를 신호 탓으로 돌리는 것이다.",
         classification="PARTIAL",
         basis=paste0("무신호 대조 실측: 무작위 25종 균등 바스켓의 시장 분산비중 평균 ",
           round(A$sc6$random_mean,3), " > 기준바스켓 ", round(A$sc6$ew_top25,3),
           ". 발화는 유지하되(임계는 임계다) 원인 귀속을 정정했다."),
         fix="RF-R1 detail 에 무신호 대조 병기 + risk_summary.no_signal_control 신설")),
  self_rationalization_scan = list(
    forbidden_phrases_checked = c("영향 미미","관행적 허용","보수적이면 괜찮다","대부분 결과 동일",
                                  "이미 반영되어 있었을 것","백테스트 기간이 충분히 길어서 상쇄"),
    hits = 0L,
    note = paste0("SC-2 에서 '바닥 상향은 보수적이라 무해하다'는 논리가 금지 표현 '보수적이면 괜찮다'에 ",
      "인접했다. 그래서 그 논거를 통과 근거로 쓰지 않고 **소비량 불변**을 실측한 뒤 '통과는 형식적'이라고 ",
      "먼저 적었다. 무해함은 유지 사유이지 통과 근거가 아니다.")),
  escalation = list(triggered = FALSE,
    checked = c("HIGH >= 5", "AX axiom hard FAIL >= 3", "PIT hard violation", "Sigma PD violation"),
    detail = "HIGH 발화 1건(RF-R1, 구조적·대조로 원인 귀속 정정) / PIT 위반 0 / Sigma PD 위반 0(min_eig 5.4e-3 > 0). escalate 조건 미충족."),
  note_ref = "stage_artifacts/WT_R20260829_005/challenge_note_risk.md")

write_json(pkg, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=10, na="null")
cat(sprintf("[R8] risk_package.json patched (%.1f KB)\n", file.size(file.path(MB,"risk_package.json"))/1024))

## regime_correlation.parquet 재작성 (읽기-후-쓰기 잠금 회피 — RDS 원본에서 재구성)
RHO <- R4$RHO; REGt <- R4$REG
RC <- rbindlist(list(
  cbind(scope="rolling_24m_series", RHO[, .(key=as.character(Date), mean_pairwise_cor=rho_bar,
        n_names=as.numeric(n_names), n_months=24, regime_dir, regime_vol, regime_crisis)]),
  cbind(scope="regime_aggregate", REGt[, .(key=regime, mean_pairwise_cor,
        n_names=as.numeric(median_n_names), n_months=as.numeric(n_months),
        regime_dir=NA_character_, regime_vol=NA_character_, regime_crisis=NA_character_)]),
  setnames(as.data.table(list(
    scope = rep("regime_episode_level", 4L),
    kk = c("HIGHVOL","LOWVOL","CRISIS","NORMAL"),
    mean_pairwise_cor = c(A$sc4$highvol_ep_mean,A$sc4$lowvol_ep_mean,A$sc4$crisis_ep_mean,A$sc4$normal_ep_mean),
    n_names = rep(NA_real_, 4L),
    n_months = as.numeric(c(A$sc4$highvol_ep_n,A$sc4$lowvol_ep_n,A$sc4$crisis_ep_n,A$sc4$normal_ep_n)),
    regime_dir = rep(NA_character_,4L), regime_vol = rep(NA_character_,4L),
    regime_crisis = rep(NA_character_,4L))), "kk", "key")), fill=TRUE)
write_parquet(RC, file.path(OUT,"regime_correlation.parquet"))
cat("[R8] regime_correlation.parquet rewritten with episode-level rows
")

## lineage 재기록 (파일이 바뀌었으므로 hash 갱신) — write_json 이후 순서 준수
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
invisible(tryCatch(record_package_lineage(task_id=TID, package_type="risk_package",
  method_selected="factor_bwb_d",
  input_file_paths=c(file.path(MB,"alpha_package.json")),
  windows=list(list(name="post_self_adversarial_patch", from=as.character(Sys.Date()), to=as.character(Sys.Date())))),
  error=function(e) message("lineage: ", conditionMessage(e))))
cat("[R8] done\n")
