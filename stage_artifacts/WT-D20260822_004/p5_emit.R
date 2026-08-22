## WT-D20260822_004 · P5 — alpha_scores.parquet + alpha_validation.json + alpha_package.json + lineage
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_004"; MB <- "qepm/mailbox/worktask/WT-D20260822_004"
V  <- readRDS(file.path(OUT, "p4_verdict.rds"))
T3 <- readRDS(file.path(OUT, "p3_transport.rds"))
P2 <- readRDS(file.path(OUT, "p2_power.rds"))
B  <- readRDS(file.path(OUT, "p1_arms.rds"))
HY <- fromJSON(file.path(MB, "alpha_hypothesis.json"), simplifyVector = FALSE)
PR <- fromJSON(file.path(OUT, "PREREG.json"), simplifyVector = FALSE)
PRI <- V$PRI; BAS <- V$BAS; ADV <- V$ADV; PERF <- V$PERF; SCA <- V$SCA; n <- V$n
gv <- function(dt, a, col) dt[arm == a][[col]]
pg <- function(a, col) PRI[contrast == a][[col]]

## ── 1) alpha_scores.parquet (판정 4 arm) ───────────────────────────────────
AS <- rbindlist(lapply(c("C0","C1","C2","C3"), function(a)
  SCA[[a]][, .(Date, Ticker, alpha_score = score, arm = a)]))
AS[, `:=`(metric_type = "canonical_screen", spec_id = "FQ244_combination_rule",
          direction_note = "alpha_score = 선별 K=5 팩터의 Z_Score_Aligned 결합값. arm 별 결합 규칙만 다름(C13 부호반전 없음). 재사용 시 신규 사전등록 필요.")]
write_parquet(AS, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[alpha_scores.parquet] %d행 · %d개월 · 4 arm\n", nrow(AS), uniqueN(AS$Date)))

## ── 2) live alpha_vector (최종 홀딩월) + confidence ────────────────────────
lastm <- max(SCA$C0$Date)
LV <- SCA$C0[Date == lastm][order(-score)]
nf <- B$SC$C0_zscore_ew[Date == lastm, .(Ticker, n_fac_used)]
LV <- merge(LV, nf, by = "Ticker", all.x = TRUE)[order(-score)]
sub_ok <- 1  # subperiod_stability (advisory, 부호 안정 3/3)
LV[, confidence := pmin(1, pmax(0, (n_fac_used/B$K) * 0.7 + 0.3 * sub_ok))]
write_parquet(LV, file.path(OUT, "alpha_vector_live.parquet"))
alpha_vector     <- setNames(as.list(round(LV$score, 6)), LV$Ticker)
confidence_vector<- setNames(as.list(round(LV$confidence, 4)), LV$Ticker)
cat(sprintf("[alpha_vector] 홀딩월 %s · %d종목\n", format(lastm), nrow(LV)))

## ── 3) arm 간 스코어 상관 (redundancy 증거) ────────────────────────────────
crosscor <- function(a, b) { j <- merge(SCA[[a]][, .(Date,Ticker,sa=score)], SCA[[b]][, .(Date,Ticker,sb=score)], by=c("Date","Ticker"))
  mean(j[, .(r = if (.N>=30) cor(rank(sa), rank(sb)) else NA_real_), by=Date]$r, na.rm=TRUE) }
COR <- list(C0_vs_C1 = crosscor("C0","C1"), C0_vs_C2 = crosscor("C0","C2"),
            C0_vs_C3 = crosscor("C0","C3"), C1_vs_C2 = crosscor("C1","C2"))
cat("[cross-arm rank cor] "); print(unlist(COR))

## ── 4) alpha_validation.json ───────────────────────────────────────────────
val <- list(
  task_id = "WT-D20260822_004", round_id = PR$round_id, fq_ref = "FQ-244",
  produced_by = "alpha-research", produced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen",
  metric_type_note = "전 수치 canonical_screen_bt() 실측. graduation HARD 3종은 forge-authoritative 값에만 적용 — 본 단계 수치로 졸업 주장 금지.",
  prereg_ref = "stage_artifacts/WT-D20260822_004/PREREG.json (측정 전 봉인, entry_gate_order_enforced)",
  control_parity = list(
    arm = "C0_zscore_ew", measured_port_t = gv(BAS,"C0","port_t_IKS200"),
    published_fq237 = 0.94741072, delta = gv(BAS,"C0","port_t_IKS200") - 0.94741072,
    rank_ic_measured = gv(ADV,"C0","rank_ic"), rank_ic_published = 0.0373043,
    ew_universe_measured = gv(BAS,"C0","port_t_EW_universe"), ew_universe_published = 2.0878059,
    verdict = "PASS — 대조군이 FQ-237 공표값을 재현. 승계 하네스 정합 확인."),
  power_precheck = PR$power_precheck_measured,
  primary = lapply(c("C1","C2"), function(a) list(
    arm = a, contrast = paste0(a, " - C0"), n = n,
    annual_pct = pg(a,"ann_pct"), t_nw3 = pg(a,"t_nw3"),
    ci95_annual_pct = c(pg(a,"ci95_lo"), pg(a,"ci95_hi")),
    mde_annual_pct = PR$power_precheck_measured$measured[[if (a=="C1") 1 else 2]]$mde_own_annual_pct,
    material_threshold_annual_pct = V$MATERIAL, label = pg(a,"label"))),
  negative_control = list(arm = "C3_max_z", annual_pct = pg("C3","ann_pct"), t_nw3 = pg("C3","t_nw3"),
    label = pg("C3","label"),
    interpretation = "사전등록 R4 방향 예측 성립 — 극단 증폭 결합(max-z)은 C0 대비 유의 악화(-3.98%p/yr, t -2.08). 즉 이 마디는 파괴 방향으로는 실효 지렛대를 갖는다. FQ-116 의 M2(평균화 뭉갬) 가설이 참이었다면 C3 > C0 이어야 했으므로 M2 기각의 독립 재확인."),
  window_reachability = list(
    obligation = "PORT_t 2.95 미달 보고 시 그 창의 도달 가능 상한 병기 (mandate)",
    ORACLE_FWD = list(port_t_IKS200 = gv(BAS,"ORACLE","port_t_IKS200"), paired_annual_pct = pg("ORACLE","ann_pct"),
      paired_t = pg("ORACLE","t_nw3"), note = "월내 실현수익 top-25 완전예지 — 도달 불가 절대 상한."),
    ORACLE_K_node_headroom = list(port_t_IKS200 = gv(BAS,"ORACLE_K","port_t_IKS200"),
      port_t_parent = gv(BAS,"ORACLE_K","port_t_parent_capw"), port_t_EW = gv(BAS,"ORACLE_K","port_t_EW_universe"),
      paired_annual_pct = pg("ORACLE_K","ann_pct"), paired_t = pg("ORACLE_K","t_nw3"),
      ir = gv(BAS,"ORACLE_K","ir_IKS200"), turnover = gv(BAS,"ORACLE_K","turnover"),
      label = "post_hoc_diagnostic_not_preregistered_not_judged",
      note = "매월 선별 K=5 중 실현 차월 rank-IC 최대 팩터를 완전예지로 채택. {K개 중 고르기} 족의 상한. ★이 마디에 실질 여유폭이 있는지의 유일한 직접 측정."),
    verdict = "창-도달가능성 병기 완료 — 본 창에서 결합 마디는 PORT_t 4.647(ORACLE_K)까지 도달 가능하며 이는 벽 2.95 를 넘는다. 따라서 C1/C2 의 null 은 '창이 좁아서' 가 아니다."),
  controls = list(
    LEAK1 = list(annual_pct = pg("LEAK1","ann_pct"), t_nw3 = pg("LEAK1","t_nw3"),
      prereg_threshold = "t >= +2.0", passed = FALSE,
      note = "★사전등록 양성 대조 미통과. 원인 진단: 결합 입력 z 를 1개월 앞당기는 것은 *수익*을 누출하는 게 아니라 팩터값 vintage 만 바꾸는 약한 개입이다. 창-도달가능성 의무는 ORACLE_FWD/ORACLE_K 로 충족했고, LEAK1 실패는 별도 정보(이 마디의 vintage 축도 약한 지렛대)로 기록한다."),
    LAG1 = list(annual_pct = pg("LAG1","ann_pct"), t_nw3 = pg("LAG1","t_nw3"),
      note = "PIT 스트레스. 붕괴 없음(PORT_t 0.947 -> 0.350, 부호 유지) — 동월 누출 징후 부재."),
    vintage_monotonicity = list(order = c("LAG1","C0","LEAK1"),
      annual_pct = c(pg("LAG1","ann_pct"), 0, pg("LEAK1","ann_pct")),
      note = "정보 신선도 축이 예측 방향으로 단조(-2.44 / 0 / +1.00 %p/yr, 스팬 3.44%p) — 하네스가 정보량에 반응함을 실증. 단 |t| 는 둘 다 2 미만이라 이 축 자체도 약한 지렛대.")),
  falsification_measured = list(
    R1a_transport = list(solo_advocate_share_median = T3$r1a, threshold = 0.20,
      slots_of_25 = T3$r1a*25, fired = FALSE,
      verdict = "수송 확인 — C0 top-25 의 중앙 64%(16/25 slot)가 solo-advocate 편입(advocate 팩터를 빼면 top-25 밖으로 밀림). M1 구조는 본 팩터 풀에 실재한다. STOP 미발화, 진행."),
    R1b_transfer_negative_concentration = list(
      pool_standalone_port_t_median = T3$pool_med, solo_advocate_port_t_median = T3$solo_med,
      consensus_advocate_port_t_median = T3$cons_med,
      neg_share_solo = T3$neg_share_solo, neg_share_consensus = T3$neg_share_cons,
      threshold = "solo 중앙 < 풀 중앙", fired = TRUE,
      verdict = "★미성립 — solo-advocate 의 advocate 팩터 standalone PORT_t 중앙 -0.2797 이 풀 중앙 -0.3476 보다 오히려 **높다**. 전이-음성 팩터가 solo 편입에 집중된다는 FQ-116 귀속(-8.27%/yr 의 75%)은 본 풀로 수송되지 않았다. 기전 강등."),
    R2_mediator_movement = list(
      solo_share = list(C0 = T3$r1a, C1 = median(T3$R$solo_C1), C2 = median(T3$R$solo_C2), C3 = median(T3$R$solo_C3)),
      ratio_vs_C0 = list(C1 = median(T3$R$solo_C1)/T3$r1a, C2 = median(T3$R$solo_C2)/T3$r1a, C3 = median(T3$R$solo_C3)/T3$r1a),
      threshold = "처치 <= 0.8 x C0",
      verdict = "C1 통과(0.688배 — rank 평균이 단독-advocate 편입을 실제로 억제했다). C2 미통과(0.938배, NO_MEDIATOR_MOVEMENT — clip c=2.0 이 매개변수를 유의하게 못 움직임). C3 는 1.312배로 증폭(음성 대조 설계 의도대로).",
      consequence = "★C1 은 매개변수를 움직였는데 성과가 안 움직였다 = 기전의 '연결' 이 끊긴 것이지 처치가 무력한 게 아니다. C2 의 null 은 처치 무력(매개 미이동)이 섞여 있어 기전 반증 증거로 약하다 — 두 arm 의 null 은 같은 무게가 아니다."),
    R3_linkage = list(n_months = 216, monthly_gap = mean(T3$G$gap), annual_pct = mean(T3$G$gap)*12*100,
      t_nw3 = T3$t_gap, threshold = "t <= -1.5", fq116_reference = -2.01, fired = TRUE,
      verdict = "★연결 절단 — solo-advocate 편입 종목이 consensus 편입 종목보다 오히려 연 +1.48%p 더 벌었다(t +0.25, 사실상 무차별). FQ-116 의 IN-vs-OUT 격차 t -2.01 은 본 풀로 수송되지 않았다. ⇒ 손실 원천은 slot 잠식이 아니다. 사전등록대로 이산 top-N 절단 마디(FQ-059)로 귀속 이전한다."),
    R5_kurtosis_heterogeneity = list(iqr_excess_kurtosis_median = T3$r5, threshold = 1.0, fired = FALSE,
      verdict = "friction 3 전제 성립 — 선별 K=5 팩터 간 횡단면 초과첨도 IQR 중앙 6.94(월별 min -0.21 / max 21.16). 꼬리 두께 이질은 대규모로 실재한다. 즉 raw-z 평균이 '두꺼운 꼬리 팩터에 은닉 과가중' 을 준다는 전제 자체는 참인데, 그 과가중이 손실로 이어지지 않았다(R3)."),
    coherence = "★반증 축이 성과보다 먼저 답을 줬다: R1b·R3 가 '잠식은 있으나 손해가 아니다' 를 성과 측정 전에 확정했고, primary 의 powered null 이 그 예측과 정합한다. 성과 null 을 사후 해석한 것이 아니다."),
  basis_three_way = list(
    arm = BAS$arm, port_t_IKS200 = BAS$port_t_IKS200, port_t_parent_capw = BAS$port_t_parent_capw,
    port_t_EW_universe = BAS$port_t_EW_universe, ir_IKS200 = BAS$ir_IKS200, ir_parent = BAS$ir_parent,
    post2017_t_EW_universe = BAS$post2017_t_EWuni,
    basis_invariance_paired_delta_t = list(C1 = -5.551e-17, C2 = -1.110e-16, C3 = 0),
    benchmark_label_caveat = "★canonical_screen_bt 는 benchmark_id 를 'KOSPI200_total_return' 으로 하드코딩한다. 실제 넘긴 계열 = primary: .cache/benchmark.parquet (build_index_cache.py Code-매칭 IKS200) / parent: stage_artifacts/WT-D20260822_002/p0_returns.rds$bench (build_monthly_forward_returns K200∪KQ150 cap-w) / EW-유니버스: canonical_screen_bt 내부 diag_ew_universe(유동성필터 前 패널 동일가중).",
    note = "수준값은 basis 에 크게 종속(C0 0.947 / 1.491 / 2.088)하나 paired 판정은 basis 불변(Δt ~ 1e-17). FQ-237 실측과 동일 구조."),
  robustness = list(
    R_LIQ_2e8 = list(port_t = list(C0 = 0.7040, C1 = 0.6518, C2 = 0.6962, C3 = -0.3764),
      paired_t = list(C1 = -0.1636, C2 = -0.0859, C3 = -2.0795),
      verdict = "유동성 필터 하에서도 판정 불변 — C1/C2 null, C3 유의 음수."),
    R_SUB_2015_07 = list(
      C1 = list(pre_n = 88, pre_t = -0.8098, pre_annual = -2.510, post_n = 133, post_t = 0.4829, post_annual = 0.975),
      C2 = list(pre_n = 88, pre_t = -1.3794, pre_annual = -2.691, post_n = 133, post_t = 0.5457, post_annual = 0.672),
      C3 = list(pre_n = 88, pre_t = -1.7677, pre_annual = -4.636, post_n = 133, post_t = -1.2478, post_annual = -3.539),
      caveat = "★진단 병기만 — 국면 주장으로 승격 금지. 2015-07 분할은 era 교락 + universe_exit_unrecorded_pre201512(KQ150 2015-11 이전 편입만 기록·퇴출 미기록, 편향 하방/중립 — 생존자 편향 아님)와 분리 불가. 어느 부분표본도 |t| 2.0 미달."),
    R_TOP5_exclusion = list(C1 = list(t = -0.2359, t_ex = 0.1791), C2 = list(t = -0.6069, t_ex = -0.5236),
      C3 = list(t = -2.0770, t_ex = -2.3171),
      verdict = "C3 의 음수는 상위 5개월 제외 후 오히려 강화(-2.077 -> -2.317) — 소수 월 아티팩트 아님.")),
  advisory_battery = list(
    arm = ADV$arm, rank_ic = ADV$rank_ic, rank_ic_sd = ADV$rank_ic_sd, icir_monthly = ADV$icir_monthly,
    harvey_t_rank_ic_nw3 = ADV$harvey_t_rankic_nw3, pearson_ic = ADV$pearson_ic,
    pearson_t_nw3 = ADV$pearson_t_nw3, monotonicity = ADV$monotonicity,
    ic_vs_port_t_contrast = "★Cycle 2 교훈 재현: rank-IC Harvey-t 는 C0/C1/C2 전부 문턱 2.95 를 크게 넘는다(5.30 / 4.75 / 5.28)나 cap-w PORT_t 는 전부 미달(0.947 / 0.875 / 0.805). rank-IC t 와 portfolio-alpha t 를 명시 구분해 보고한다. ★본 라운드의 추가 관측: 결합 규칙을 바꿔도 rank-IC 는 거의 안 움직이고(0.0373/0.0359/0.0375) PORT_t 도 거의 안 움직인다 — FQ-237 은 rank-IC 를 움직였는데 PORT_t 가 반대로 갔다. 두 라운드를 합치면 '두 통계량의 연결이 이 마디에서 끊겨 있다' 가 아니라 '두 통계량 모두 이 마디에서 움직이지 않는다' 다."),
  performance_table = as.list(PERF),
  cost_awareness = list(cost_model_version = "v2.4_kr_retail_15bps",
    turnover_annual = list(C0 = gv(PERF,"C0","turnover"), C1 = gv(PERF,"C1","turnover"),
                           C2 = gv(PERF,"C2","turnover"), C3 = gv(PERF,"C3","turnover")),
    note = "전 수치 net-of-cost(15bps delta-based, canonical_screen_bt 내장 차감). C1 회전율이 C0 보다 +0.44/yr 높아(11.99 vs 11.55) 비용 측면에서도 개선 없음."),
  ax001_v2 = list(applicable = FALSE,
    reason = "본 라운드 arm 은 방어형 팩터가 아니라 결합 규칙 대조군이다(detected_family 미해당). 조건부 평가 축 비적용 — 단, C3 의 crisis 구간 열위는 R_SUB pre 구간(-4.64%p)에 기록."),
  dsr_diagnostic = list(arm = V$DSR$arm, active_sr_ann = V$DSR$active_sr_ann,
    dsr_trials1 = V$DSR$dsr_trials1, dsr_trials3 = V$DSR$dsr_trials3,
    gate_status = "비발동 — selection_type=preregistered_arms_no_champion (argmax 선택 없음). 진단 산출·기록만.",
    n_trials_this_round = 3, sweep_count = 0),
  redundancy = list(cross_arm_rank_cor = COR,
    note = "arm 간 스코어 상관은 의도된 동일-클러스터 대조 — 신규 팩터 추가가 아니다(Factor Zoo 축소 원칙 ①). 기존 admitted 대비 상관(<0.95 요건)은 본 라운드가 자본 후보를 제출하지 않으므로 비적용 — 침묵이 아니라 명시 비적용."),
  verdict = "NON_ML_COMBINATION_POWERED_NULL",
  verdict_detail = "사전고정 비-ML 결합 규칙 2종(rank 평균 · winsor-z 평균)은 C0 대비 개선 없음 — 둘 다 POWERED_NULL_NO_MATERIAL_EFFECT(CI95 상단 +3.01 / +1.49 %p/yr 로 MATERIAL 8.22 를 배제). 음성 대조 C3 는 예측대로 유의 악화(-3.98%p, t -2.08). 반증 축이 성과 이전에 이유를 제공: 잠식(R1a 64%)은 실재하나 손해가 아니다(R3 t +0.25)."
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[alpha_validation.json] saved\n")
saveRDS(list(val = val, alpha_vector = alpha_vector, confidence_vector = confidence_vector,
             COR = COR, lastm = lastm, LV = LV), file.path(OUT, "p5_emit.rds"))
cat("OK\n")
