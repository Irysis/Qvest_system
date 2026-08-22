## WT-D20260822_007 (FQ-246 NP1) P6 — alpha_validation.json + alpha_package.json 방출
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; MB <- "qepm/mailbox/worktask/WT-D20260822_007"
SRC <- "stage_artifacts/fq233_probe0_20260813"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months
PA <- readRDS(file.path(OUT,"p2_partA.rds")); P3 <- readRDS(file.path(OUT,"p3_partB.rds"))
P4 <- readRDS(file.path(OUT,"p4_verdict.rds")); P5 <- readRDS(file.path(OUT,"p5_adversarial.rds"))
PC <- readRDS(file.path(OUT,"p1c_parity.rds")); c0 <- PC$a_uni
H <- PA$HEADROOM; MATERIAL <- P3$MATERIAL; EMIT <- P4$EMIT; K <- A4$K; TOPN <- A4$TOPN
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector = FALSE)$selected
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
fwddt <- panh[, .(Date=anchor, Ticker=as.character(Ticker), fwd=fwd_ret_1m)]
r1 <- function(x, n=6) if (is.numeric(x)) round(x, n) else x

## ---- 방출 arm 의 advisory 보강 (monotonicity / subperiod / harvey) ----
sce <- P3$SCB[[EMIT]]; s <- merge(sce, fwddt, by=c("Date","Ticker"))
dec <- s[, { ok <- is.finite(score) & is.finite(fwd)
  if (sum(ok) < 50L) .(d=NA_integer_, r=NA_real_) else {
    q <- cut(rank(score[ok]), breaks=quantile(rank(score[ok]), probs=seq(0,1,.1)),
             include.lowest=TRUE, labels=FALSE)
    .(d=q, r=fwd[ok]) } }, by=Date]
dm <- dec[is.finite(d), .(mr=mean(r)), by=d][order(d)]
mono <- cor(dm$d, dm$mr, method="spearman")
icser <- s[, { ok <- is.finite(score) & is.finite(fwd)
  if (sum(ok) < 30L) NA_real_ else cor(rank(score[ok]), rank(fwd[ok])) }, by=Date]
icser <- icser[is.finite(V1)]
sub <- icser[, .(ic=mean(V1)), by=.(era=fifelse(Date < as.Date("2015-01-01"), "2008_2014",
                        fifelse(Date < as.Date("2020-01-01"), "2015_2019", "2020_2026")))]
subst <- 1 - (sd(sub$ic)/abs(mean(sub$ic)))
harvey <- .nw_t_mean(icser$V1, lag=3L)
sc0 <- P3$sc0
inh <- merge(sce[, .(Date,Ticker,se=score)], sc0[, .(Date,Ticker,s0=score)], by=c("Date","Ticker"))
inh_cor_score <- cor(inh$se, inh$s0)
inh_cor_active <- cor(P3$RESB[[EMIT]]$act, c0)
cat(sprintf("방출 arm %s: mono %.4f · subperiod_stab %.4f · harvey_t %.4f · inherit_cor(score) %.4f / (active) %.4f\n",
    EMIT, mono, subst, harvey, inh_cor_score, inh_cor_active))

CURVE <- PA$CURVE; PB2 <- P3$PB2; TG <- P3$TG
dtl <- function(dt) lapply(split(dt, seq_len(nrow(dt))), function(r) as.list(r))

VAL <- list(
  task_id = "WT-D20260822_007",
  round_id = "FQ-246_NP1_discrete_hard_selection_ceiling_WT-D20260822_007_20260822",
  fq_ref = "FQ-246 NP1", produced_by = "alpha-research",
  produced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg_ref = paste0(OUT, "/PREREG.json (Part A/B 동시 봉인, sealed_at 2026-08-22T18:05+0900;",
    " 파일 순서 = p0/p1/p1b/p1c(패리티) → PREREG → p2(A) → p3(B) → p4/p5/p6)"),
  hypothesis_ref = paste0(MB, "/alpha_hypothesis.json (alpha-hypothesis, verdict=designed)",
    " — mechanism/falsification/regime_scope 자구 승계, 재작성 없음"),
  metric_type_note = paste0("★2계층 라벨. Part A 전 arm = metric_type 'canonical_screen_diag_oracle',",
    " capital_eligible=FALSE (오라클 = 구성상 look-ahead, AX-002 방지). Part B 전 arm =",
    " 'canonical_screen' (오라클 미사용). 어느 쪽도 admission binding 아님 — graduation HARD 3종은",
    " forge-authoritative 값에만 적용."),

  control_parity = list(
    checks = dtl(PC$PAR),
    verdict = paste0("가중 프레임이 FQ-244 두 극점을 비트-동치 재현 (|Δ| ≤ 5e-9): C0 균등가중 = 0.947410715814893,",
      " one-hot argmax = 4.64699909. FQ-246 오라클 소프트 틸트도 재현(Δ 4.7e-10 / -2.9e-9).",
      " ⇒ 사다리 중간 지점(형태 변주)의 해석 자격 성립."),
    fq246_repro = dtl(PA$FQR[, .(arm, port_t, published_port_t, delta_port_t)])),

  lookup_clause = list(performed = TRUE,
    tool = "02_Infrastructure/tools/hypothesis_index.R :: lookup_hypothesis()",
    keywords = c("argmax","oracle","ceiling","headroom","sparsity","concentration",
                 "single_factor","factor+selection","form+loss","softmax","top_n"),
    prior_attempts_on_this_axis = 0,
    nearest_prior = paste0("DIST-RAMP-013 (DISTILLED_COND) — RAMP 에서 국면 정보는 soft membership 소비 시",
      " 성과 상승, 하드 스위치는 아님. ★본 라운드는 **반대 방향**을 시험(팩터 선택면에서는 집중이 상한을 올린다).",
      " 소비면이 다름(국면 배분 vs 팩터 선택)이 차별점이며, 실측 결과 두 발견은 '소비면마다 최적 집중도가 다르다' 로 공존한다."),
    differentiator = "선행 어디에도 '정보를 고정한 채 가중 집중도만 변주해 회수율 곡선을 잰' 라운드가 없다. FQ-246 은 정보(1차원 상태)와 형태(soft)를 동시에 바꿔 두 손실이 교락돼 있었다."),

  part_A = list(
    role = "진단 전용 — terminal_form = diagnostic_ceiling · alpha_vector 미방출 · capital_eligible = FALSE",
    denominator_annual_pct = H,
    denominator_note = "지시·사전등록대로 FQ-246 의 25.1% 와 직접 비교 가능하도록 ORACLE_K(IC-argmax) 여유폭 13.6929981793759 %p/yr 를 고정 분모로 유지.",
    form_ladder = dtl(CURVE[, .(arm, n_eff, ann_pct, t_nw3, recovery_pct = recovery*100,
                                port_t, turnover, ar1_diff)]),
    FA_monotonicity = list(
      spearman_neff_vs_recovery_all = cor(CURVE[grepl("^O_softmax|^O_top", arm), n_eff],
        CURVE[grepl("^O_softmax|^O_top", arm), recovery], method="spearman"),
      spearman_softmax_only = P4$sp_soft, spearman_topJ_only = P4$sp_hard,
      threshold = "<= -0.70", passed = TRUE,
      verdict = paste0("★FA 지지 — 정보를 고정한 채 집중도만 올리면 회수율이 단조 증가한다",
        " (Spearman -0.9794 전체 / -1.0000 topJ). '평균화 = 희석' 형태 손실 기전의 직접 지문."),
      shape_residual = paste0("★단 집중도는 형태의 1차 축이지 유일 축이 아니다 — n_eff 4.00 의 topJ4 하드 EW 는 26.31%",
        " 회수인데 n_eff 4.19 의 softmax0.5 는 40.99% 로, **덜 집중한 쪽이 더 많이 나른다**.",
        " 가중의 *모양*(정보 비례 배분 vs 균등-절단)도 기여한다.")),
    form_cost_null = list(
      design = "같은 형태 · 정보 제거 — 월별 IC 벡터를 월내 무작위 치환 후 같은 가중 형태 재실행. NPERM = 60/형태.",
      measured = dtl(rbindlist(lapply(names(PA$NULLD), function(f) data.table(form=f,
        n=length(PA$NULLD[[f]]), mean_ann_pct=mean(PA$NULLD[[f]]), sd_ann_pct=sd(PA$NULLD[[f]]),
        q05=quantile(PA$NULLD[[f]],.05), q95=quantile(PA$NULLD[[f]],.95))))),
      honest_name = paste0("★이 항의 정직한 이름 = **'정보 없는 단일-팩터 집중의 순비용'** —",
        " 분산(잡음 평균화) 상실 + 회전율 증가 + 특이위험 노출의 합이며 본 라운드는 셋을 분리하지 않았다.",
        " '형태 비용' 은 축약어다. 근거: rank_ic 가 C0 0.0373(ic_t 5.30) → 하드 arm 0.0164~0.0212(ic_t 2.90~3.13)로",
        " 절반 가까이 깎이고(평균화 상실), 동시에 Part B 13 arm 에서 cor(turnover, ann_pct) = -0.4315(회전율 채널).")),
    decomposition_2way = dtl(PA$DEC),
    decisive_contrast = list(
      paired_tests = dtl(P5$CMP),
      attribution = dtl(P4$ATTR),
      label_by_coordinate = dtl(P4$DEC),
      concern2_confound = list(
        neff_path_match = dtl(P5$NEC),
        note = paste0("★적대검증 CONCERN-2 인정 — 'N_eff 평균 일치' 는 평균에서만 참이다.",
          " FQ-246 소프트 틸트의 월별 집중도 sd 0.9888/1.0427 vs 매칭 arm 0.2793/0.1442,",
          " 경로 상관 0.1911/0.0299. ⇒ 이 성분은 순수 '정보 차원' 이 아니라",
          " **'정보 차원 + 집중 타이밍' 혼합**이며 라벨을 INFO_AND_TIMING_component 로 정정한다.")),
      verdict = paste0("★두 성분이 서로 다른 처분을 받는다. **형태 성분 = 확립**",
        " (T2 +50.58pp of headroom, t 2.934, p_two 0.0033 / T3 +63.40pp, t 2.959, p_two 0.0031).",
        " **정보+타이밍 성분 = 미결**(T2 +24.23pp t 1.786 MDE95 26.58pp / T3 +11.86pp t 0.966 MDE95 24.07pp).",
        " 사전등록 문턱(15/25 pp)이 설계 해상도보다 미세했으므로 '효과없음' 이 아니라 '미결' 이다.")),
    answer_to_headline_question = list(
      question = "FQ-246 이 남긴 미회수 3/4 이 순수 형태 손실인가",
      answer = paste0("**아니오 — 순수하지는 않다. 형태가 다수지만 전부는 아니다.**",
        " FQ-246 좌표(N_eff 3.910)에서 미회수 74.81pp 중 **형태 귀속 50.58pp(67.6%)**,",
        " **정보+타이밍 귀속 24.23pp(32.4%)**. T3 좌표(N_eff 4.344)에서는 미회수 75.25pp 중",
        " 형태 63.40pp(84.2%) / 정보+타이밍 11.86pp(15.8%).",
        " 형태 성분만 통계적으로 확립되고 정보 성분은 두 좌표 모두 MDE 미만 — 즉",
        " **'형태 손실이 다수' 는 확립, '정보 손실이 0' 은 미확립**."),
      key_numbers_with_units = list(
        fq246_recovery_pct_of_headroom = PA$FQR[arm=="FQ246_ORACLE_T2_form", recovery*100],
        oracle_ic_ceiling_at_same_neff_pct_of_headroom = CURVE[arm=="O_softmax_lamMATCH_T2", recovery*100],
        one_hot_recovery_pct_of_headroom = 100)),
    capital_eligible = FALSE, terminal_form = "diagnostic_ceiling", alpha_vector_emitted = FALSE),

  part_B = list(
    role = "α̂ 주장 가능한 유일 축 — 오라클 미사용, 선택 기준 전부 당월 z 횡단면만의 함수(성과-비파생, PIT-safe)",
    transport_gate_FC = list(
      principle = "★성과 판정 前에 기준이 정보를 아는지 먼저 묻는다(승계 규약 3). 하드 one-hot **형태**의 전도성은 Part A O_top1_EW(PORT_t 4.647)로 확립됐으므로, 미확립 가능성은 형태가 아니라 **기준**에 있다.",
      measured = dtl(TG),
      binomial_mde = list(n = 221, p0 = 0.2, mde_hit_rate = 0.2443, mde_excess_pp = 4.43),
      rho_mde95_mean = mean(TG$rho_mde95, na.rm=TRUE),
      verdict = paste0("★9/9 미통과 · 전부 POWERED_NULL_CRITERION_UNINFORMATIVE.",
        " 적중률 0.1719~0.2308 (우연 0.2000, 이항 MDE 0.2443) · |rho| 최대 0.0413 (MDE95 0.0772).",
        " ⇒ 성과-비파생 관측 기준 4종(꼬리 질량·경계 마진·상충도·순위 지속성) 어느 것도",
        " '다음 달 어느 팩터가 맞나' 를 모른다. 성과-파생 대조(sel_rank 위치 1)도 동일하게 무지",
        " (적중 0.2036, rho -0.0164) — RAMP R10 · FQ-121 posterior 와 정합."),
      power_note = "★게이트 자체의 MDE 를 측정했다 — FQ-246 초판이 게이트 검정력을 재지 않아 자기 적대검증에 적발된 결손의 재발 방지."),
    mediator_gate_FB = list(measured = dtl(P3$JAC),
      verdict = paste0("★13/13 TREATMENT_EFFECTIVE (Jaccard 중앙값 0.087~0.515 ≤ 0.79).",
        " 매월 top-25 중 중앙 8~21 종목이 교체되고도 회수 0 ⇒ **null 은 처치 무력이 아니다.**",
        " FQ-246 T1_AGREE/T3_BEAR(0.9231, 매개 무이동)과 명확히 다른 사건이다.")),
    arms = dtl(PB2[, .(arm, n_eff, ann_pct, t_nw3, ci95_lo, ci95_hi, port_t, turnover,
                       perm_pctile, vs_null_sd, jaccard_median, ar1_diff, label)]),
    power_declaration = list(
      MATERIAL_ann_pct = MATERIAL,
      MATERIAL_derivation = "C0 월평균 net active 0.003242 · NW3 SE 0.003422 · t 0.9474 → (2.95·SE − mean)·12·100 (FQ-246 승계, 동일 C0)",
      bars = dtl(P3$POW),
      degeneracy_avoided = "★바 원천 = 순열 arm 분포(처치 없음). 자기-diff sd 바는 implied_t_own = 2.0 으로 퇴화하므로 판정 문턱으로 쓰지 않았다.",
      contract_default_rejected = "계약 기본 sd 0.0394 미사용 — FQ-246 실측에서 본 대조 척도의 0.27~0.49배로 **다른 양**이었다.",
      breakeven = list(
        form_cost_ann_pct = mean(PA$NULLD$N_top1),
        oracle_info_value_ann_pct = P3$oracle_info_top1,
        capture_needed_for_breakeven_pct = -mean(PA$NULLD$N_top1)/P3$oracle_info_top1*100,
        capture_needed_for_MATERIAL_pct = (MATERIAL - mean(PA$NULLD$N_top1))/P3$oracle_info_top1*100,
        capture_measured_pct = 0,
        note = "★하드 선택은 정보를 **값을 치르고** 산다. one-hot 의 무정보 순비용 -4.427 %p/yr 를 상쇄하려면 오라클 정보의 24.4% 를, MATERIAL 8.2228 %p/yr 도달엔 69.8% 를 포착해야 한다. 실측 포착 = 0%.")),
    turnover_channel = list(
      cor_turnover_ann_pearson = -0.4315, cor_turnover_ann_spearman = -0.3901,
      cor_turnover_pctile = -0.5675,
      note = paste0("★FC 게이트가 정보 0 을 powered 로 확정했으므로, 일부 arm 이 무작위 하드 픽 분포의",
        " 93 백분위에 앉은 것을 '정보가 조금 있다' 로 읽으면 안 된다. 그 백분위는",
        " **'어느 팩터가 맞나' 가 아니라 '어느 팩터가 싼가'** 로 설명된다.")),
    basis_three_way = dtl(P3$BASB),
    ax001_v2 = list(measured = dtl(P3$AX),
      note = paste0("★FQ-246 과 달리 이번엔 승계 regime_scope 와 **방향이 정합**한다 —",
        " B3a 위기 alpha -1.6015 %p/yr vs 정상 -1.1173 %p/yr (위기 t -0.3789).",
        " 유의하지 않으므로 국면 주장으로 승격하지 않고 advisory 기록만.")),
    advisory_battery = dtl(P3$ADV),
    advisory_note = "★rank-IC 계열은 advisory (measurement-graduation §3). C0 ic_t_nw3 5.3019 인데 PORT_t 0.9474 — IC→PORT_t 전이 벽의 교과서적 재현이며 하드 arm 에서 rank_ic 자체가 절반으로 깎인다.",
    redundancy = list(measured = dtl(P4$RED),
      note = "처치 arm 의 active 계열이 C0 와 0.684~0.888 상관 — 같은 선별 궤적·같은 K=5 풀의 재가중이므로 redundancy_cluster_id 는 C0 와 동일 클러스터."),
    dsr_diagnostic = list(value = P3$DSR, n_trials = P3$n_tr,
      selection_type = "preregistered_grid_no_champion",
      gate_status = "비발동 — sweep 형 selection(열거 trial 에서 argmax/threshold-pick) 미해당. 수치는 진단용.",
      note = "★argmax 로 챔피언을 뽑는 순간 sweep 재분류 + DSR 0.5 HARD 발동임을 사전등록에 명시했고, 본 라운드는 전 arm 독립 라벨을 유지했다. 표에 나온 '최선 arm' 은 보고용 사후 식별이며 승격에 쓰지 않는다."),
    verdict = paste0("★POWERED_NULL — 실현 가능 하드 선택의 여유폭 회수 = **0 (음수)**.",
      " 13 arm 전부 C0 대비 음수이고 최선이 B1b_INDEP_MAX_top1 -1.134 %p/yr (t -0.503).",
      " 2 arm 은 EFFECT_NEGATIVE(B1a_INDEP_MIN_top1 -8.881 t -2.761 순열 5백분위 · B4b_STABLE_MIN_top1 -6.086 t -2.225).",
      " 기전 진단: 형태는 전도되는데(Part A 4.647) **기준이 무지**하다(FC 9/9 powered null).")),

  window_reachability = list(
    obligation = "PORT_t 2.95 미달 보고 시 그 창의 도달 가능 상한 병기 (mandate)",
    ORACLE_K_IC = list(port_t_IKS200 = 4.64699909, paired_annual_pct = H, paired_t = 4.28970507043012,
      note = "FQ-244 공표 · 본 하네스 재현. 실현 rank-IC argmax."),
    ORACLE_K_RET_new = list(port_t_IKS200 = P5$oracle_ret_port_t,
      paired_annual_pct = P5$oracle_ret_paired_ann, paired_t = P5$oracle_ret_paired_t,
      multiple_vs_IC_version = P5$oracle_ret_paired_ann / H,
      note = paste0("★신규 확립 — {K개 중 고르기} 족의 **진짜** 상한. 소비면이 top-25 절단이므로",
        " rank-IC argmax 가 아니라 실현 top-25 수익 argmax 가 족 상한이다. IC 판의 2.30배.",
        " ⇒ FQ-244 가 세운 4.647 은 이 마디 정보량의 **하한 추정**이었다.")),
    quantity_collision_warning = paste0("★승계 규약 11 사례 — ORACLE_K_RET **paired 31.4926 %p/yr** 와",
      " FQ-244 ORACLE_FWD **PORT_t 31.45062294** 는 소수 둘째 자리까지 닮았으나 완전히 다른 양이다",
      " (전자 = 연 초과수익 %p, 후자 = t 통계량). 인용 시 단위와 양의 이름을 병기할 것."),
    verdict = "본 창에서 이 마디는 PORT_t 4.647(IC 판) ~ 8.838(RET 판)까지 도달 가능하다. 따라서 본 라운드의 어떤 null 도 '창이 좁아서' 로 설명할 수 없다."),

  cost_awareness = list(cost_model_version = "v2.4_kr_retail_15bps",
    turnover_C0 = 11.5482, turnover_partB_range = range(PB2$turnover),
    turnover_partA_range = range(CURVE$turnover),
    note = "전 수치는 delta-based 15bps 차감 후 net. ★C0 자체 회전율 11.5482/yr 로 Research Philosophy P6 권고(TO ≤ 11.0/yr)를 이미 상회 — 승계된 하네스 속성이며 본 라운드가 만든 초과가 아니다. 하드 선택은 오라클 판에서 18.04/yr 까지 오른다(집중의 비용 채널)."),

  basis_note = "★canonical_screen_bt 는 benchmark_id 를 'KOSPI200_total_return' 으로 하드코딩한다. 실제 넘긴 계열 = primary .cache/benchmark.parquet(IKS200) / parent stage_artifacts/WT-D20260822_002 p0_returns.rds cap-w. paired 판정은 basis 불변, 수준값은 basis 종속.",

  self_adversarial = list(
    note = "v8.2 — 외부 Codex 없음. 전 concern 을 실측으로 응답. 상세 = qepm/mailbox/worktask/WT-D20260822_007/challenge_note.md",
    concerns = list(
      list(id="CONCERN-1", verdict="ACCEPT", title="분모 13.69 는 족 상한이 아니라 하한이었다",
           resolution="ORACLE_K_RET 실측(PORT_t 8.8381, paired +31.4926 %p/yr, 2.30x). 분모는 지시대로 유지하되 신규 사실로 별도 기록. 결론 방향은 보수적."),
      list(id="CONCERN-2", verdict="PARTIAL", title="'같은 집중도' 는 평균에서만 참",
           resolution="월별 N_eff sd 0.28 vs 0.99, 경로 상관 0.19/0.03. 정보 성분 라벨을 INFO_AND_TIMING_component 로 정정. 분리 설계는 NP2."),
      list(id="CONCERN-3", verdict="ACCEPT", title="사전등록 문턱이 설계 해상도보다 미세",
           resolution="MDE95 26.58/24.07pp > 문턱 15pp. 두 좌표 모두 UNRESOLVED_UNDERPOWERED 로 강등. 문턱 사후 완화 없음."),
      list(id="CONCERN-4", verdict="REBUTTAL", title="상위 선별기가 K=5 를 동질화했나",
           resolution="월내 IC best-worst 스프레드 0.16993 · top-25 수익 스프레드 0.0570/월(연 68.36%p 상당). 균질과 정반대 — 기각."),
      list(id="CONCERN-5", verdict="PARTIAL", title="'형태 비용' 은 세 성분의 축약어",
           resolution="명칭을 '정보 없는 단일-팩터 집중의 순비용' 으로 정정. rank_ic 반감 + 회전율 상관 -0.43 실측 병기. 세 성분 분리는 한계."),
      list(id="CONCERN-6", verdict="PARTIAL", title="오라클 arm 의 자본 자격 오독 위험",
           resolution="Part A 전 arm 에 capital_eligible=FALSE + metric_type 분리 라벨. diagnostics.canonical_port_t_nw_lag3 에는 Part B 방출 arm 값만 기입.")),
    escalate_triggers = list(high_severity_ge5 = FALSE, axiom_hard_fail_ge3 = FALSE,
      pit_c1_violation = FALSE, escalate = FALSE),
    inheritance_integrity = list(
      rewritten = FALSE,
      contradictions_recorded = list(
        list(item = "B2 solo-advocate 방향 반전",
             detail = "가설은 '중심성 최소(상충) 팩터가 정보를 갖는다' 로 서술. 실측 B1a_INDEP_MIN_top1 = -8.881 %p/yr (t -2.761, 순열 5백분위) 로 13 arm 중 최악이고, 거울 arm B1b_INDEP_MAX_top1(합의 팩터)이 -1.134 로 최선. 수정하지 않고 재설계 요청으로 등재(Charter 원칙 8)."),
        list(item = "regime_scope 정합", detail = "이번엔 방향 일치(위기 -1.6015 vs 정상 -1.1173, t -0.3789). 유의 미달로 국면 주장 미승격.")))),

  verdict = "FORM_LOSS_ESTABLISHED_MAJORITY__INFO_TIMING_COMPONENT_UNRESOLVED__REALIZABLE_HARD_SELECTION_POWERED_NULL",
  verdict_detail = paste0(
    "Part A: 정보를 K차원 오라클 IC 로 고정한 채 형태만 바꾸면 회수율이 단조 증가한다",
    " (Spearman(n_eff, recovery) -0.9794; n_eff 5.00→25.8%, 3.91→49.4%, 3.03→62.0%, 2.00→80.2%, 1.00→100%).",
    " FQ-246 좌표에서 미회수 74.81pp 의 귀속 = 형태 50.58pp(67.6%, t 2.934 확립) +",
    " 정보/타이밍 24.23pp(32.4%, t 1.786 · MDE95 26.58pp 미결). ⇒ '남은 3/4 = 순수 형태 손실' 은",
    " **부분적으로만 참** — 형태가 다수임은 확립됐고 정보 성분이 0 이라는 것은 확립되지 않았다.",
    " Part B: 성과-비파생 관측 기준 4종의 하드 선택은 여유폭을 전혀 회수하지 못한다(13/13 arm C0 대비 음수).",
    " 기전은 성과 이전에 갈렸다 — FC 전이 게이트 9/9 powered null(적중률 0.172~0.231 vs 우연 0.200, MDE 0.244)",
    " 로 **기준이 무지**함이 확정됐고, FB 매개는 13/13 실효(Jaccard 0.087~0.515)라 처치 무력이 아니다.",
    " 하드 선택은 무정보 시 -4.427 %p/yr 를 치르므로 손익분기에만 오라클 정보의 24.4% 포착이 필요한데 실측 포착 0%."),
  round_verdict = "CONFIG_SCOPED_NEGATIVE__REALIZABLE_HARD_SELECTION_NO_RECOVERY__FORM_CEILING_MAPPED",

  next_probe = list(
    list(id="NP1", title="족 상한 재정의 후 형태 사다리 재측정 (IC-argmax → RET-argmax 정보)",
      rationale = paste0("본 라운드 신규 실측 — 진짜 족 상한은 ORACLE_K_RET(PORT_t 8.8381, paired +31.4926 %p/yr)로",
        " IC 판의 2.30배다. 사다리 전체를 'top-25 실현수익 기준 오라클' 로 다시 태우면 회수율 곡선의 기울기와",
        " 형태/정보 귀속 비율이 바뀐다. 특히 rank-IC 는 전체 횡단면 지표이고 소비면은 꼬리이므로,",
        " **정보의 정의를 소비면에 맞추는 것 자체가 미측정 레버**다."),
      consumes = "본 라운드 p5_adversarial.rds(ret_by_factor) + p2_partA.rds"),
    list(id="NP2", title="집중 타이밍과 정보 차원의 분리 (월별 N_eff 경로 강제 일치)",
      rationale = paste0("적대검증 CONCERN-2 가 남긴 미분리 — 매칭 arm 의 월별 N_eff sd 0.2793 vs FQ-246 0.9888,",
        " 경로 상관 0.1911. 현재 '정보 성분' 추정치는 정보 차원과 집중 타이밍의 혼합이다.",
        " 월별 N_eff 를 FQ-246 경로에 강제 일치시킨 오라클-IC arm 을 만들면 두 축이 갈린다.",
        " 이 대조는 MDE 도 줄어든다(공통 변동 제거)."),
      consumes = "p2_partA.rds(LAM_T2/LAM_T3) + WT-D20260822_006 p4_conduit.rds(UO_A/UO_D)"),
    list(id="NP3", title="합의(중심성 최대) 방향의 하드 선택 — 승계 가설이 뒤집힌 축",
      rationale = paste0("승계 hypothesis 의 B2 는 '상충(중심성 최소) 팩터가 정보를 갖는다' 였는데 실측은 정반대다:",
        " INDEP_MIN -8.881(t -2.761, 순열 5백분위) vs INDEP_MAX -1.134(순열 93백분위).",
        " 중심성은 부호가 정해진 실질 축이며 방향이 가설과 반대다. 단 INDEP_MAX 도 C0 미달이므로",
        " 순수 argmax 가 아니라 **중심성 기반 소프트 틸트**(Part A 곡선이 형태 최적점을 이미 지도화했다)로",
        " 재시험하는 것이 다음 형태다. ★FC 게이트를 먼저 통과해야 한다는 조건은 유지."),
      consumes = "p3_partB.rds(CRIT centrality) + p2_partA.rds(form ladder)"),
    list(id="NP4", title="꼬리-정의 정보의 탐색 — rank-IC 가 아닌 top-25 적중을 표적으로 한 관측 기준",
      rationale = paste0("FC 게이트가 잰 것은 '기준이 실현 **rank-IC** 서열을 아는가' 였고 9/9 무지였다.",
        " 그러나 소비면은 꼬리다 — NP1 의 RET-argmax 정답지로 게이트를 다시 세우면 기준의 자격이 달라질 수 있다.",
        " v8.4 분포-표적 재편(평균 → 분위·꼬리)과 정확히 같은 방향의 마디별 적용."),
      consumes = "p5_adversarial.rds(ret_by_factor) + p3_partB.rds(CRIT)")),

  revival_conditions = list(
    criterion_revival = "새 성과-비파생 기준이 FC 게이트(적중률 > 0.2443 또는 |rho_t| >= 1.5)를 통과하면 Part B 축은 즉시 재개. 본 라운드는 기준 4종(+거울 4)만 기각했지 '하드 선택' 족을 기각하지 않았다(INV-7 config-scoped).",
    form_ceiling_revival = "형태 사다리는 IC-argmax 정보 기준이다. RET-argmax 정보(NP1)로 재측정하면 형태/정보 귀속 비율이 갱신된다.",
    hard_form_status = "★하드 형태 자체는 **부정되지 않았다** — 오라클 정보를 주면 PORT_t 4.647(IC)~8.838(RET)로 벽 2.95 를 넘긴다. 죽은 것은 형태가 아니라 본 라운드가 시험한 **식별 기준 4종**이다.",
    dist_ramp_013_coexistence = "DIST-RAMP-013(RAMP: soft membership > hard switch)과 모순 아님 — 소비면이 다르고, 본 라운드는 팩터 선택면에서 집중이 상한을 올림을 보였다. 두 발견은 '소비면마다 최적 집중도가 다르다' 로 공존한다."),

  consumption_surface_7 = list(
    factor_ranking = "즉시 소비 없음 — Part B 13 arm 전부 C0 미달.",
    universe_filter = "미측정 (본 라운드는 유니버스 불변).",
    overlay_regime_input = "미측정 — 단 Part A 형태 곡선은 '국면별 최적 집중도' 오버레이의 설계 입력이 될 수 있다(NP3 조건부).",
    risk_model_beta_budget = "역할 경계상 본 에이전트 소관 아님 — 단 '단일-팩터 집중의 순비용 -4.427 %p/yr' 은 risk-research 의 집중도 페널티 보정 입력으로 이식 가능.",
    monitoring_signal = "FC 게이트(기준-정보 적중률)는 라이브에서 월간 산출 가능한 진단이다 — 선택 기준이 정보를 되찾는 시점의 조기 경보로 배관 가능(FQ 등재 권고).",
    screening_label = "screen_route 발급 없음 — screening 신호력 자체가 C0 미달.",
    cross_mode_transfer = "★RAMP 로 이식 가치 있음 — DIST-RAMP-013 이 국면 배분면에서 soft > hard 를 실측했고 본 라운드가 팩터 선택면에서 반대를 실측했다. 두 소비면의 최적 집중도 차이는 RAMP Gate 의 배분 형태 설계 입력."),

  limitations = list(
    "Part A 전 수치는 구성상 look-ahead(오라클) — capital_eligible=FALSE. 자본·졸업 주장 금지.",
    "'형태 비용' 은 잡음 평균화 상실 + 회전율 + 특이위험의 합이며 본 라운드는 셋을 분리하지 않았다.",
    "결정 대조의 집중도 일치는 **평균**에서만 참 — 월별 경로 상관 0.19/0.03 (CONCERN-2).",
    "사전등록 판정 문턱(15/25pp)이 설계 MDE95(26.58/24.07pp)보다 미세했다 — 정보 성분은 미결이며 문턱을 사후 완화하지 않았다.",
    "분모 13.6929981793759 %p/yr 는 IC-argmax 기준이며 족 상한의 하한이다(진짜 상한 +31.4926 %p/yr).",
    "선별 궤적 sel_rank(K=5)는 상위 성과-정렬 선별의 산물을 승계 — 본 라운드는 그 안에서만 골랐다.",
    "subperiod 진단은 era 교락 + universe_exit_unrecorded_pre201512 (편입만 기록·퇴출 미기록) — 국면 주장 승격 금지.",
    "benchmark_id 하드코딩 불일치 (basis_note 참조)."))

write_json(VAL, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=10, na="null")
cat("[emit] alpha_validation.json\n")

## ---------------- alpha_package.json (AST v1.1 3층) ----------------
AV <- as.data.table(read_parquet(file.path(OUT,"alpha_vector_live.parquet")))
avec <- as.list(setNames(round(AV$score, 6), AV$Ticker))
cvec <- as.list(setNames(round(AV$confidence, 4), AV$Ticker))
fals <- lapply(HYP$falsification$falsification_gate_schema, function(z)
  list(group_id = z$group_id, expectation = z$expectation))

PKG <- list(
  task_id = "WT-D20260822_007", as_of_date = "2026-08-22", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-07-01",
    decision_ts = "2026-07-01",
    note = "방출 arm 의 최종 신호 산출 기준일 = 홀딩월 2026-07 시작 시점. 선택 기준은 당월 z 횡단면만 사용(성과-비파생)."),
  hypothesis = list(
    statement = HYP$statement, mechanism = HYP$mechanism,
    falsification = fals, regime_scope = HYP$regime_scope),
  factors = list(list(
    factor_id = "F1_breadth_argmax_hard_selection",
    ast = list(leaf = "SPECIAL_OP",
      escape_contract = list(escape_type = "SPECIAL_OP",
        op_code_path = "stage_artifacts/WT-D20260822_007/p3_partB.R :: CRIT[,,'breadth'] + W_argsel(...,J=1) + build_from_W()",
        walk_forward = TRUE)),
    role = "core_signal", restatement_exposure = 0,
    ast_note = paste0("★𝒪 로 표현 불가한 부분이 존재해 escape 리프로 산출했다 — 본 신호의 연산은",
      " **종목 축이 아니라 팩터 축에서 일어나는 argmax**(매월 K=5 팩터 중 하나를 고름)이고,",
      " ast_node 의 연산자 집합은 종목 횡단면/시계열 연산만 담는다. 우회 구현 대신 SPECIAL_OP 로 정직 산출.",
      " walk_forward=TRUE 인 이유: 기준(top-25 꼬리 질량)은 학습 파라미터가 없고 각 월의 결정이",
      " 그 달 횡단면만으로 닫힌다 — 적합 창 자체가 없다."),
    operator_gap_note = "𝒪 확장 후보 = 팩터-축 선택 연산(SELECT_ARGMAX_OVER_FACTORS). 단 본 라운드가 그 연산의 **실측 무효**(FC 게이트 9/9 powered null)를 확인했으므로 ast_operator_backlog 적립은 권고하지 않는다 — 표현 불가가 아니라 표현할 가치가 실측되지 않았다.")),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(performed = TRUE,
    leaves_checked = list(
      list(leaf = "FDB-B6_fdb_daily_store (팩터 z 횡단면)", availability_rule = "fixed: 월말 t-1 종가 기준 factor DB 승격분", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily", availability_rule = "fixed: t-1 close", restatement_prone = FALSE)),
    verdict = "clean",
    rationale = paste0("선택 기준 4종 전부 **당월 z 횡단면만의 함수**이며 차월 수익도 과거 수익도 입력이 아니다",
      " (stability 만 anchor m 과 m-1 을 쓰는데 둘 다 <= m). 오라클 arm 은 설계상 look-ahead 이나",
      " Part A 진단 전용으로 격리했고 capital_eligible=FALSE 로 선언했다 — 본 패키지의 alpha_vector 는",
      " Part B 방출 arm 에서만 나왔다.")),
  alpha_vector = avec, confidence_vector = cvec,
  signal_matrix_ref = paste0(OUT, "/alpha_scores.parquet (long: arm/Date/Ticker/score, 991893행 · 14 arm)"),
  factor_specs = list(list(
    factor_family = "MetaSelection_HardArgmax",
    proxy = "monthly argmax over K=5 selected factors by top-25 tail mass ((mean z of top-25 − cross-sectional mean)/sd)",
    formula = "score_i,t = z_i,k*(t) where k*(t) = argmax_k [ (mean_{top25 by k} z − mean z)/sd(z) ]",
    lag_rule = "당월 z 횡단면 (t-1 close 기준 factor DB 승격분) — 성과 비파생",
    winsorization = "승계 (패널 사전 처리)", neutralization = "없음 (선별 궤적 승계)",
    economic_rationale = paste0("top-25 절단 소비면은 평균 판별력이 아니라 꼬리 판별력을 소비하므로,",
      " 꼬리가 잘 분리된 팩터를 하드 채택하면 평균화가 파괴하는 순위 정보를 되찾는다는 가설.",
      " ★실측 결과 이 근거는 지지되지 않았다 — FC 전이 게이트에서 적중률 0.1900(우연 0.2000, MDE 0.2443)로",
      " powered null. 본 spec 은 판정 기록용으로 남기며 자본 경로 자격이 없다."),
    weight_theta = 1.0, source = "db_derived",
    references = c("Harvey-Liu-Zhu 2016 (다중검정 hurdle)",
                   "Jensen-Kelly-Malamud-Pedersen 2022 (cost-aware alpha)"),
    redundancy_cluster_id = "CLUSTER_C0_selrank_K5_reweighting")),
  diagnostics = list(
    canonical_port_t_nw_lag3 = P3$PB2[arm==EMIT, port_t],
    canonical_n_months = 221,
    rank_ic = P3$ADV[arm==EMIT, rank_ic], icir = P3$ADV[arm==EMIT, icir],
    monotonicity = mono, subperiod_stability = subst,
    turnover_proxy = P3$PB2[arm==EMIT, turnover],
    harvey_t_stat = harvey, post_neutralization_ic = NA,
    deflated_sharpe_ratio = P3$DSR,
    alpha_inheritance_cor = inh_cor_score,
    alpha_inheritance_cor_active_series = inh_cor_active,
    oracle_diagnostic_not_capital_eligible = list(
      metric_type = "canonical_screen_diag_oracle", capital_eligible = FALSE,
      ORACLE_K_IC_port_t = 4.64699909, ORACLE_K_RET_port_t = P5$oracle_ret_port_t,
      form_ladder_port_t_range = range(CURVE$port_t),
      note = "★이 블록의 수치는 전부 look-ahead 진단이다. 자본·졸업 주장에 사용 금지(AX-002).")),
  alpha_discovery_count = 0,
  selection_objective = "canonical_port_t",
  challenge_flags = c(
    "[자본 자격 없음] 방출 arm 은 FC 전이 게이트(9/9 powered null)와 순열 백분위 게이트를 통과하지 못했다. alpha_vector 는 사전등록 고정 규칙에 따라 성과와 무관하게 방출됐을 뿐 승격 후보가 아니다.",
    "[승계 가설 반전] hypothesis 의 B2 solo-advocate 방향(중심성 최소)이 실측에서 뒤집혔다 — INDEP_MIN -8.881 %p/yr (t -2.761) 최악 / INDEP_MAX -1.134 최선. 재설계 요청(challenge_note CONCERN 인계).",
    "[분모 하한] 여유폭 분모 13.6929981793759 %p/yr 는 IC-argmax 기준이며 진짜 족 상한은 +31.4926 %p/yr (2.30배).",
    "[사전등록 해상도 결손] Part A 결정 대조의 문턱(15/25pp)이 MDE95(26.58/24.07pp)보다 미세했다 — 정보 성분은 미결이며 문턱을 사후 완화하지 않았다.",
    "[집중 타이밍 교락] 결정 대조의 N_eff 일치는 평균에서만 참(월별 경로 상관 0.19/0.03) — 정보 성분 라벨은 INFO_AND_TIMING_component.",
    "[RF-A4 해당 없음] 중립화 미적용 arm 이라 post_neutralization_ic 미산출.",
    "[비용] C0 회전율 11.5482/yr 로 P6 권고(11.0) 승계 상회. 방출 arm 12.1607/yr.",
    "[benchmark_id 라벨 불일치] canonical_screen_bt 하드코딩 — alpha_validation.basis_note 참조."))

write_json(PKG, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=10, na="null")
cat("[emit] alpha_package.json\n")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260822_007", package_type = "alpha_package",
  method_selected = "Part A 형태 사다리(오라클 정보 고정, 17 arm) + Part B 실현가능 하드 선택(13 arm) + 형태 귀무분포 240 run",
  input_file_paths = c(file.path(SRC,"lane_a_feature_panel.parquet"),
    "stage_artifacts/WT-D20260822_004/p1_arms.rds",
    "stage_artifacts/WT-D20260822_006/p4_conduit.rds",
    "stage_artifacts/WT-D20260822_002/p0_returns.rds",
    file.path(OUT,"PREREG.json")))
cat("[lineage] recorded\n")
cat("\nOK\n")
