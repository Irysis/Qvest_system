# S7 — 중복성 점검 + alpha_validation.json + alpha_package.json (AST v1.1) + lineage
# WT-R20260829_003
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(future.apply)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_003")
rj <- function(f) fromJSON(file.path(OUT, f), simplifyVector = FALSE)
S2 <- rj("s2_primary.json"); S3 <- rj("s3_confound.json"); S4 <- rj("s4_arms.json")
S5 <- rj("s5_side_pit.json"); S6 <- rj("s6_alpha_meta.json")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O6 <- readRDS(file.path(OUT, "s6_objects.rds"))
HYP <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)

## ═══ 중복성(Factor Zoo 축소) — 기존 등재 팩터와의 상관 ═══════════════════════
E <- O2$E; ME <- sort(unique(E$Date)); samp <- ME[seq(1, length(ME), length.out = 30L)]
plan(multisession, workers = min(6L, max(1L, parallel::detectCores()-1L)))
red <- rbindlist(future_lapply(samp, function(d) {
  suppressWarnings(suppressMessages(library(data.table)))
  source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/factor_db/factor_db_connector.R"))
  fn <- c("L02_Turnover","L15_Turnover_252d","L05_Dollar_Volume","L26_Log_MktCap","M02_Mom_6_1")
  x <- tryCatch(as.data.table(load_month_factors(d, factor_names = fn)), error=function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  w <- dcast(x[Factor_Name %in% fn], Ticker ~ Factor_Name, value.var="Z_Score_Aligned",
             fun.aggregate = function(v) v[1])
  w[, Date := d][] }, future.seed = TRUE), fill = TRUE)
plan(sequential)
RD <- merge(E[Date %in% samp, .(Date, Ticker, tr, score)], red, by = c("Date","Ticker"))
rcols <- setdiff(names(red), c("Date","Ticker"))
redundancy <- lapply(rcols, function(cc) {
  v <- RD[is.finite(get(cc)), .(r_turn = cor(-tr, get(cc), method="spearman"),
                                r_mom  = cor(score, get(cc), method="spearman")), by = Date]
  list(factor = cc, cor_vs_low_turnover_signal = mean(v$r_turn, na.rm=TRUE),
       cor_vs_momentum_score = mean(v$r_mom, na.rm=TRUE), n_months = nrow(v)) })
names(redundancy) <- rcols
cat("[S7] 중복성 (평균 월별 Spearman, -tr = 저회전선호 신호):\n")
for (k in rcols) cat(sprintf("  %-20s vs -turnover %+0.3f | vs momentum %+0.3f\n",
  k, redundancy[[k]]$cor_vs_low_turnover_signal, redundancy[[k]]$cor_vs_momentum_score))

## ═══ 사전등록 판정 ═══════════════════════════════════════════════════════════
pv <- S3$primary_variants; pr <- S2$primary_preregistered; ps <- S2$primary_adv20_stratified
arms <- S4$arms; incr <- S4$increments_vs_armA
sig2 <- function(t) is.finite(t) && abs(t) >= 2

verdicts <- list(
  primary_1st_stratification_spread = list(
    preregistered_statement = "승자 분위 내부에서 형성기간 회전율(시장-내 랭킹, t-1) 저층 vs 고층의 forward 수익 스프레드가 유의한가. 비유의면 LS2000 의 KR 이식 실패.",
    verdict_rule_declared_before_reading = pv$verdict_rule_declared_before_reading,
    independent_LS2000_sort = list(mean_ann = num(pv$independent_LS2000$mean_ann), nw_t = num(pv$independent_LS2000$nw_t),
                                   beta_controlled_alpha_ann = num(pv$independent_LS2000$beta_controlled$alpha_ann),
                                   beta_controlled_t = num(pv$independent_LS2000$beta_controlled$t_alpha),
                                   n_months = num(pv$independent_LS2000$n_months)),
    conditional_within_winner = list(mean_ann = num(pv$conditional_within_winner$mean_ann), nw_t = num(pv$conditional_within_winner$nw_t),
                                     beta_controlled_alpha_ann = num(pv$conditional_within_winner$beta_controlled$alpha_ann),
                                     beta_controlled_t = num(pv$conditional_within_winner$beta_controlled$t_alpha),
                                     n_months = num(pv$conditional_within_winner$n_months)),
    adv20_stratified = list(mean_ann = num(ps$mean_ann), nw_t = num(ps$nw_t),
                            beta_controlled_t = num(ps$beta_controlled$t_alpha),
                            per_stratum = ps$per_stratum),
    fm_regression_form = S6$fm_intercept_gap_v1_minus_v3,
    reject_if_1_fired = TRUE,
    verdict = "REJECTED_AS_PREREGISTERED — 승자 사이드 회전율 층화 스프레드는 어느 사양에서도 유의하지 않다. 부호는 LS2000 예측과 반대(저회전 승자가 열위): 독립정렬 -6.51%/yr(t -0.807) · 조건부정렬 -4.14%/yr(t -0.649) · adv20 층내부 -3.38%/yr(t -0.729) · FM 절편차 +0.54%/yr(t +0.196). LS2000 의 KR 이식은 승자 사이드에서 성립하지 않는다.",
    power_disposition = list(
      note = "★이 판정은 '효과 없음' 으로 승격할 수 없다 — LS2000 함의 효과크기에 대한 검정력이 3~5% 다.",
      power_vs_paper_implied = S2$power$primary,
      power_stratified = S2$power$stratified,
      label = "미결(underpowered) 위의 부호 반대 관측 — 라벨 규칙: 사전등록 reject_if 는 발동했으나 통계적 상태는 '논문 배율을 검출할 검정력 부재'다. 3단 처분 (a) 착수금지구간(ratio 0.028~0.120).",
      what_this_round_leaves = "①KR 승자 사이드 회전율 층화의 최초 실측 좌표(부호·크기·분산) ②시장-내 랭킹 의무의 양성 대조 실증 ③L-family 누출 귀무 좌표 ④패자 사이드 좌표(4/20 착수 근거)")),

  secondary_2nd_transfer = list(
    preregistered_statement = "저회전 조건부 top-25 의 β-통제 α 가 cell4(+5.14%/yr) 대비 증분 ≤ 0 이면 전이 실패.",
    baseline_armA = list(port_t = num(arms$A_uncond_top25$port_t_capw),
                         beta_alpha_ann = num(arms$A_uncond_top25$beta_controlled$alpha_ann),
                         t_alpha = num(arms$A_uncond_top25$beta_controlled$t_alpha),
                         beta = num(arms$A_uncond_top25$beta_controlled$beta),
                         reproduction_of_2_20_cell4 = "정확 재현 — PORT_t 1.294 · α +5.14%/yr · t 1.205 (2/20 보고치와 일치). canonical_screen_bt bit-parity 동시 실증."),
    armB_lowturn_V1 = list(port_t = num(arms$B_lowturn_V1_top25$port_t_capw),
                           beta_alpha_ann = num(arms$B_lowturn_V1_top25$beta_controlled$alpha_ann),
                           t_alpha = num(arms$B_lowturn_V1_top25$beta_controlled$t_alpha),
                           beta = num(arms$B_lowturn_V1_top25$beta_controlled$beta),
                           increment_alpha_ann = num(incr$B_lowturn_V1_top25$increment_alpha_ann),
                           paired_diff_beta_controlled_t = num(incr$B_lowturn_V1_top25$paired_diff_t_alpha)),
    variants = list(
      B2_lowturn_half = list(increment_alpha_ann = num(incr$B2_lowturn_half_top25$increment_alpha_ann),
                             paired_t = num(incr$B2_lowturn_half_top25$paired_diff_t_alpha)),
      C_exclude_V3 = list(increment_alpha_ann = num(incr$C_exclude_V3_top25$increment_alpha_ann),
                          paired_t = num(incr$C_exclude_V3_top25$paired_diff_t_alpha),
                          note = "가설설계 challenge_flags 의 C4(배제형) 사양. 배제형은 25종을 유지하므로 '배제 vs 대체' 대비가 구조적으로 내장된다(랭킹 26위 이하가 강제 편입) — 별도 잔류 대비를 쓰지 않았다."),
      D_highturn_V3 = list(increment_alpha_ann = num(incr$D_highturn_V3_top25$increment_alpha_ann),
                           paired_t = num(incr$D_highturn_V3_top25$paired_diff_t_alpha))),
    reject_if_2_fired = TRUE,
    verdict = "REJECTED_AS_PREREGISTERED — 사전등록 스펙(저회전 V1 조건부 top-25)의 β-통제 α 증분 = -0.19%p ≤ 0. 전이 실패. 변형 중 배제형(C)만 +1.14%p 로 양(+)이나 짝지음 β-통제 t = +0.388 로 전부 잡음 안. 다섯 arm 의 α 순서(C +6.28 > B2 +5.87 > A +5.14 > B +4.95 > D +4.61 %/yr)는 방향만 약하게 LS2000 정합이며 어떤 대비도 |t| < 0.4 다.",
    power = S6$power_increment_beta_controlled,
    basis_arithmetic_caveat = "arm B 의 PORT_t 는 1.294 -> 0.217 로 급락하나 β-통제 α 는 5.14 -> 4.95%/yr 로 거의 불변이다. 차이의 정체는 β 1.058 -> 0.647 하락에 따른 basis 산술((β-1)·E[bm])이며 알파 변화가 아니다(measurement-graduation §2 거울상). PORT_t 하락을 '조건화가 알파를 파괴했다' 로 읽어서는 안 된다."),

  confound_rejection = list(
    preregistered_statement = "회전율 층화 효과가 L-family(L01_Amihud·L09_Amihud_20d·L11_Kyle_Lambda) 통제 후 소멸하면 '생애주기' 가 아니라 유동성 프리미엄의 재명명.",
    dispersion_precheck = S2$dispersion_precheck,
    orthogonality = S3$lfamily_orthogonality,
    outcome_stratified = S3$outcome_stratified_control,
    leakage_null = S3$leakage_null_by_axis,
    cutplane = S3$cutplane,
    confound_axes = S2$confound_axes,
    verdict = "판정 불가 — '분리 실패' 도 '분리 성공' 도 아니다. 통제 전 스프레드 자체가 유의하지 않으므로(1급 기각) '통제 후 소멸' 을 물을 대상이 없다. 다만 세 가지가 실측됐다: ①통제 규약 2종이 부호로 갈린다(조건부 사양 raw +2.83%/yr vs rank -0.94%/yr — feedback-two-controls-disagree 대상이나 둘 다 |t|<0.6 이라 갈림 자체가 잡음 안) ②결과량 층화(통제 5분위 내부) 후 스프레드는 +0.9~+4.1%/yr 로 부호가 뒤집히나 |t| <= 0.72 ③★누출 귀무가 신호보다 세다 — 순수 L01_Amihud 를 stratifier 로 주입하면 |NW-t| 2.886(-17.07%/yr)로 회전율 신호의 0.807 을 크게 넘는다. 즉 승자 데실 내부에서 실제로 수익을 가르는 축은 회전율이 아니라 유동성(Amihud) 계열이다.",
    label = "VOL_INDEPENDENCE_UNPROVEN 대응 — 단, 여기서는 '증명 안 된 독립성' 이 아니라 '분리할 신호가 없음' 이다.",
    sign_caveat = "L-family 는 Z_Score_Aligned(방향 정렬) 값이라 그 부호는 IC 로 결정된 데이터 산물이다. 누출 귀무의 부호를 기전으로 해석하지 말 것 — 여기서 쓰는 것은 크기(|t|)뿐이다."),

  mechanism_side_observation = list(
    preregistered_statement = "기전이 참이면 저회전 승자의 후속 이익 서프라이즈/실적이 고회전 승자보다 우위여야 한다. 부재하면 수익 스프레드가 있어도 기전 기각. ★C01_SUE 단독 금지 — 실현 공시창 수익률 병행.",
    realized_announcement_window = S5$side_observation_announcement_window$test,
    realized_earnings_growth = S5$side_observation_realized_earnings_growth,
    verdict = "부분 지지(미결) — 방향은 LS2000 정합이나 유의 미달. 실현 공시창 3일 시장조정 CAR: V1 +0.132% vs V3 -0.024%, 차 +0.156% NW(11)-t +1.315 (형성월 245, 형성 후 8분기 이벤트). 보조로 실현 DART 순이익성장 중앙값 V1 +4.31% vs V3 +0.62%. reject_if ④(부수 관측 부재)는 발동하지 않는다 — 부재가 아니라 약함이다.",
    consequence = "부수 관측이 방향으로 살아 있는데 수익 스프레드가 없다는 것 = 기전의 정보 축은 KR 에도 존재하나 top-25 롱온리 소비면으로 전이되지 않는다(전이 벽). 이는 4/20 설계가 소비 형태를 바꿔야 할 근거다."),

  no_signal_control_gate = list(
    mandatory_for = "롱온리 전 arm (measurement-graduation §3)",
    control_beta = num(S4$no_signal_control$control_beta),
    control_beta_verdict = "PASS — 대조군 β 1.072. 1/20 의 홀딩월 라벨 정렬 결함(β 0.041) 재발 없음. 라벨은 시그널월 t 의 다음 캘린더월(t+1).",
    gates = S4$no_signal_control$gates,
    consequence = "5개 arm 전부 INDISTINGUISHABLE_FROM_NO_SIGNAL (|t| 0.14~0.75) → screen-tier 등재 불가. 어떤 arm 의 양(+) 수치도 알파로 인용할 수 없다. 2/20 과 동일 결과이며 회전율 조건화는 이 게이트를 움직이지 못했다."),

  market_internal_ranking_positive_control = list(
    finding = S2$mixed_rank_control,
    verdict = "★시장-내 랭킹 의무의 양성 대조 성립 — 혼합(K200+KQ150 통합) 랭킹으로 회전율을 자르면 승자 사이드 스프레드가 -19.58%/yr NW-t -2.526 으로 '유의' 해진다. 그러나 그 V1 셀은 KOSDAQ 비중 14.1% · V3 셀은 65.3% 로, 실제로 재는 것은 회전율이 아니라 시장 더미(K200 롱 · KQ150 숏)다. 시장-내 랭킹은 그 오염을 제거한다(KQ 비중 43.0% vs 50.7%). LS2000 이 Nasdaq 을 배제한 이유의 KR 대응물이 실측으로 확인됐다.",
    consequence = "이 통제를 걸지 않았다면 본 라운드는 '유의한 회전율 효과' 를 보고했을 것이다 — 부호도 반대인 채로.")
)

## ═══ 처분 구간 판정 (사전 정의 밴드) ════════════════════════════════════════
armB_a <- num(arms$B_lowturn_V1_top25$beta_controlled$alpha_ann)
disposition <- list(
  bands_from_hypothesis = HYP$selected$falsification$reachability_disposition_bands,
  observed = list(armB_beta_alpha_ann = armB_a, armC_beta_alpha_ann = num(arms$C_exclude_V3_top25$beta_controlled$alpha_ann),
                  baseline_armA = num(arms$A_uncond_top25$beta_controlled$alpha_ann)),
  verdict = "reject",
  rationale = "사전 정의: band_reject = 'β-통제 α 증분 ≤ 0 또는 1급 스프레드 비유의'. 둘 다 성립한다(증분 -0.19%p · 1급 전 사양 |t| < 0.81). band_partial(+5.14~+8%/yr)에 arm C 의 절대 α +6.28%/yr 가 들어가지만 그것은 밴드가 요구하는 '저회전 조건부' 스펙이 아니고(배제형 변형), 밴드의 판정 기준은 절대 α 가 아니라 증분이며 그 증분(+1.14%p)의 t 는 0.388 이다. 절대값으로 밴드를 읽어 partial 로 승격하면 사후 표적 교체가 된다.",
  reachability = S6$reachability_ceiling)

## ═══ 탐색적(비-사전등록) ════════════════════════════════════════════════════
expl <- list(
  label = "exploratory_not_preregistered",
  hard_rule = "★본 라운드 판정 근거로 승격 금지. 용도는 강화 4/20 의 사전등록 1급 좌표 생성 하나뿐이다.",
  loser_side_spread_1m = S2$grid_10x3$decile_tests,
  loser_side_consumption_arms = S4$exploratory_loser_side$arms,
  loser_side_no_signal_gates = S4$no_signal_control$exploratory_gates,
  event_time_horizons = S3$horizons,
  reading = paste(
    "패자 사이드(mdec=1)에서 V1-V3 = +5.28%/yr NW-t +1.027 로 부호가 LS2000 정합이고 승자 사이드(-6.23%, t -0.779)와 반대다.",
    "롱온리 소비 형태에서도 같은 순서가 나온다: E(저회전 패자) β-통제 α +1.96%/yr t 0.611 > F(무조건부 패자) -1.77%/yr > G(고회전 패자) -4.56%/yr t -1.212 — 스프레드 +6.5%/yr.",
    "이벤트타임: 패자 V1-V3 는 Y1 +6.53%/yr 인데 Y2 -3.60%(NW11-t -1.630) 로 부호가 뒤집힌다 — LS2000 의 5년 지속과 다르다.",
    "즉 KR 에서 회전율 조건화가 무엇인가 가르는 곳이 있다면 그것은 승자 사이드가 아니라 패자 사이드이고, 수평선은 1년이다.",
    "★어느 것도 유의하지 않다 — 이 문단은 4/20 의 사전등록 설계를 위한 좌표이지 발견 주장이 아니다.", sep = " "))

## ═══ alpha_validation.json ══════════════════════════════════════════════════
alpha_validation <- list(
  schema = "alpha_validation/v1", task_id = "WT-R20260829_003", wt_type = "reinforcement",
  as_of_date = "2026-08-29", attempt = "3/20", axis = "multifactor — 회전율 조건부 모멘텀 생애주기 (Lee-Swaminathan 2000)",
  base = list(base_id = "RP_20260829_122020_9192", base_grade = "F"),
  paper = list(citation = "Lee, C.M.C. & Swaminathan, B. (2000), Price Momentum and Trading Volume, Journal of Finance 55(5):2017-2069",
               url = "https://onlinelibrary.wiley.com/doi/abs/10.1111/0022-1082.00280",
               open_pdf = "https://www.lsvasset.com/pdf/research-papers/Price-Momentum-Trad-Vol-2000.pdf",
               read_by = "alpha-hypothesis (원문 직접 판독 — alpha_hypothesis.json::paper_reading)"),
  metric_type = "canonical_screen",
  metric_type_note = "arm 수치는 canonical_screen_bt 경로(arm A 와 bit-parity 실증). 층화 스프레드(1급)는 metric_type='canonical_screen_diag' — 신호 수준 gross 스프레드이며 매매가 없다. 등급 권위는 essence_score.R 하나이고 본 산출물은 등급을 선언하지 않는다.",
  measurement_engine = list(positive_control = S4$parity,
    note = "arm A(무조건부 top-25) 를 canonical_screen_bt(top_n=25) 와 대조해 max|Δret_net| = 0 · |ΔPORT_t| = 0 (259/259 개월). 조건부 arm 은 정의역만 다른 동일 엔진이다."),
  fixed_axes = list(
    signal = "기저 엔진 stage_artifacts/replication/_pilot/fe_jt1993_momentum.R 그대로 (J=6 형성 t-2..t-7 · skip 1M · 월말). 3/20 이 바꾼 것은 신호가 아니라 정의역(층화)이다.",
    new_material = "형성기 일평균 회전율 = Vol*Close/Size (LS2000 원정의 = 거래주식수/상장주식수). t-2..t-7 월 평균. 시장-내(K200/KQ150 별도) 백분위 랭킹.",
    turnover_adjustment_check = "Vol·Close·Size 동일 조정기준 확인 — 2018-05 삼성전자 50:1 액면분할 구간에서 implied shares(Size/Close)가 6.4193e9 로 불변(비조정 Vol 이면 50배 점프해야 함).",
    universe = "K200 ∪ KQ150 (PIT 시변 멤버십) · 월 중앙 343종",
    window = S2$meta$window, cost = "15bps one-way, delta 기반 (v2.4_kr_retail_15bps)",
    liquidity = "20일 평균 거래대금(t-1) >= 2e8 KRW — liq_ruler='adv20_t1'",
    weighting = "EW · Σw = 1 · 개별 비중 상한 없음(v10)", rebalance = "monthly",
    long_only = TRUE, max_names = 25L,
    composite_prohibition_honored = "연속 composite(mom rank − turnover rank) 미구현. 전 arm 이 정의역 제한(층화)이다 — handoff 승계조건 ① 준수, DIST-AR-007 소진 경로 회피."),
  primary_measurements = list(
    grid_10x3 = S2$grid_10x3, primary = S2$primary_preregistered,
    adv20_stratified = S2$primary_adv20_stratified, variants = S3$primary_variants,
    fm_by_stratum = S6$fm_by_turnover_stratum,
    fm_reading = "층별 FM: 절편은 세 층이 거의 같고(1.00/1.11/0.96 %/월) 모멘텀 기울기는 회전율과 함께 커진다(0.103/0.161/0.260 %/z, t 0.72/0.91/1.76). LS2000 예측(초기단계=저회전 승자가 지속)과 방향이 반대다 — KR 에서 모멘텀의 단면 기울기는 고회전 종목에 집중된다."),
  arms = S4$arms,
  increments_vs_armA = S4$increments_vs_armA,
  preregistered_verdicts = verdicts,
  disposition = disposition,
  exploratory_not_preregistered = expl,
  redundancy_check = list(
    method = "샘플 30개월, load_month_factors(factor_names=...) Z_Score_Aligned 대비 월별 Spearman 평균",
    correlations = redundancy,
    reading = "저회전선호 신호(-turnover_rank)는 기존 등재 팩터 L02_Turnover 와 방향적으로 겹친다 — 본 라운드의 재료는 '신규 발굴' 이 아니라 기존 유동성 계열 팩터의 조건화 소비다(Factor Zoo 축소 원칙 ① 정합: 발굴이 아니라 검증)."),
  advisory_battery = S5$advisory_battery,
  advisory_headline = "★단일 최대 관측: 유니버스 전체 단면에서 저회전 선호(-turnover_rank)의 rank-IC = +0.0287 · ICIR 0.181 · NW-t +3.211 이고 size 중립화 후에도 유지(+0.0298, t +3.305, retention 1.039). 즉 회전율 축 자체에는 단면 정보가 있다. 그런데 그 정보는 (a)승자 데실 내부에서는 사라지고 (b)top-25 롱온리 소비로 전이되지 않는다(전 arm 무신호 대조 구별불가). 전이 벽의 또 하나의 사례이며, rank-IC t 와 portfolio-alpha t 를 구분해 읽어야 하는 이유다(measurement-graduation §2).",
  pit = list(
    hard_gate = S5$pit_hard_gate,
    signal_path_clean = "fe_jt1993_momentum.R · s1_panel.R · s2_primary.R · s3_confound.R = detect_lookahead clean=TRUE · violations 0 (신호·층화·통제 산출 경로 전부).",
    reporting_path_flags = "s4_arms.R 1건 · s5_side_pit.R 2건 — 전부 C1 'sd() on full vector * sqrt()' 이며 해당 줄은 실현 수익 시계열의 사후 요약통계(연율 net SR · DSR 진단) 계산이다. 신호·선별·비중 어디에도 입력되지 않는다. 검출기가 살아 있다는 양성 대조이기도 하다(위반 주입 없이 3건 발화).",
    c1 = "full-sample 통계 미사용 — 신호는 t-2..t-7 월간수익 shift, 회전율은 t-2..t-7 월평균 shift. 단면 랭크/z 는 당월 단면 내부 연산.",
    c2 = "same-day 순환참조 없음 — 시그널일 t 의 수익은 t+1 캘린더월 forward(build_monthly_forward_returns).",
    c4 = "재무제표 리프는 신호에 미진입. 부수 관측(공시창)만 DART 고정 공시일 규약(연간 익년 3/31 · 분기 5/15·8/15·11/15) 사용 — 사후 실현 진단.",
    c5 = "오버레이 미적용(S0/S1 준수). 국면 라벨을 어떤 arm 의 비중에도 쓰지 않았다.",
    c6 = "survivorship — K200/KQ150 멤버십을 각 시그널일 실제 값으로 시변 적용. 상폐 종목은 그 시점 유니버스에 잔존.",
    c10 = "★회전율 t-1 준수 — 형성창을 t-2..t-7 로 잡아 당월과 t-1 월을 전면 배제했다(요구는 t-1 까지이나 신호 창과 정렬해 더 보수적으로 잡았다). 유동성 자 adv20 은 build_adv20_t1() 이 당일 제외 shift(1).",
    c13 = "NEGATE/FLIP 미사용. L-family 통제는 load_month_factors 의 Z_Score_Aligned 그대로 사용.",
    c14 = "Factor DB IC 히스토리 미소비 (align_factor_direction 은 커넥터 내부 PIT-safe 경로).",
    c15 = "★L-family(L01/L09/L11) · 중복성 점검 팩터(L02/L15/L05/L26/M02) 전부 load_month_factors() 경유. 신호(모멘텀·회전율)는 Factor DB parquet 이 아니라 RAWDATA 에서 본 라운드가 직접 산출 — 직접 load 0건.",
    stored_panel_reuse = "없음 — 패널은 본 라운드에서 RAWDATA 로부터 재빌드."),
  challenge_flags = c(
    "[1급 기각 · 검정력 3~5%] reject_if ① 은 사전등록대로 발동했으나 LS2000 함의 효과크기(+0.06~0.18%/월)에 대한 검정력은 3.0~5.2% 다(ratio 0.028~0.120 = 착수금지구간). '효과 없음' 으로 승격 금지 — 관측된 것은 '부호가 반대인 방향의 잡음' 이다.",
    "[누출 귀무 > 신호] 순수 L01_Amihud stratifier 의 |NW-t| 2.886 이 회전율 신호의 0.807 을 넘는다. 승자 데실 내부의 수익 분산을 실제로 가르는 축은 유동성 계열이다. 회전율 축의 독립성은 증명되지 않았고, 증명할 신호도 없다.",
    "[통제 규약 갈림] 조건부 사양에서 raw 통제 +2.83%/yr vs rank 통제 -0.94%/yr 로 부호가 갈린다. 둘 다 |t| < 0.6 이라 갈림 자체가 잡음 안이지만, 변환 규약을 명시하지 않은 '통제했다' 진술이 무의미하다는 규약(measurement-graduation §3)의 실측 사례로 남긴다.",
    "[혼합 랭킹 함정] 시장-내 랭킹을 걸지 않으면 -19.58%/yr NW-t -2.526 의 '유의' 결과가 나오는데 그 정체는 K200-KQ150 시장 더미다. 본 라운드의 유일한 |t|>2 관측이 통제로 제거된 아티팩트라는 사실을 기록한다.",
    "[무신호 대조 전 arm 실패] 5 arm + 탐색 3 arm 전부 INDISTINGUISHABLE_FROM_NO_SIGNAL. 2/20 과 동일하며 회전율 조건화로 움직이지 않았다.",
    "[중복성] 저회전선호 신호는 기존 등재 L02_Turnover 계열과 방향 중복이다 — 신규 발굴이 아니라 기존 팩터의 조건화 소비. redundancy_check 참조.",
    "[AST 연산자 공백] 시장-내(그룹) 랭킹은 𝒪 의 CS_RANK 로 표현되지 않는다(그룹 인자 부재). 우회 계산 없이 코드 경로를 명시하고 backlog 후보로 기록했다 — ast_operator_gap 필드. 계산 자체는 가설이 요구한 그대로다.",
    "[탐색 라벨] 패자 사이드·Year2+ 측정은 exploratory_not_preregistered 다. 본 라운드 판정 근거로 승격 금지.",
    "[C5/C2 승계] 가설 challenge_flags 의 C5(패자 사이드)·C2(ΔTurnover)는 그대로 유지되며, 본 라운드 탐색 결과가 C5 쪽에 좌표를 추가했다(d_turn 은 alpha_scores 패널에 미포함 — TURN 원장에 계산돼 있으나 본 라운드 소비 없음)."),
  selection_objective = "canonical_port_t",
  n_trials = 8L, selection_type = "chain",
  selection_type_rationale = "사전등록 1급 1개(사양 3변형) + 2급 arm 5개 + 탐색 arm 3개. argmax/threshold-pick 부재 — 어떤 arm 도 성과로 선택하지 않았고 발행 스펙은 사전등록 arm B 로 고정했다. DSR 게이트 부적용(measurement-graduation §3), 수치는 진단 산출.",
  grade_declaration = "없음 — 등급 권위는 essence_score.R 하나. 본 라운드는 risk/optimizer/forge 스폰 근거를 만들지 못했다(1급·2급 동시 기각 + 무신호 대조 전 arm 구별불가).")
write_json(alpha_validation, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S7] alpha_validation.json written\n")

## ═══ AST (schema args + ast_verify children 두 방언 병기) ═══════════════════
FLD <- function(f) list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = f)
vol <- FLD("Vol"); clo <- FLD("Close"); siz <- FLD("Size")
mul <- list(op = "MUL", args = list(vol, clo), children = list(vol, clo))
## ★나눗셈 연산자의 계약 표면 분열: schema.json enum = "DIV_GUARD" / ast_verify.py
##   operator_library(ARITH_OPS) = "DIV". 한 이름만 쓰면 한쪽이 반드시 실패한다
##   (DIV_GUARD -> 검증기 FAIL_CONTRACT 실측 / DIV -> schema enum 위반).
##   두 표면에 각자의 이름을 싣는다 — 의미는 동일한 보호 나눗셈이다.
mk_turn <- function(divop) {
  td <- list(op = divop, args = list(mul, siz), children = list(mul, siz))
  tl <- list(op = "TS_LAG", args = list(td, 2), children = list(td), k = 2L, unit = "m")
  tm <- list(op = "TS_MEAN", args = list(tl, 6), children = list(tl), window = 6L)
  list(op = "CS_RANK", args = list(tm), children = list(tm)) }
turn_rank      <- mk_turn("DIV_GUARD")   # 정본 = schema.json enum (검증기 operator_library 는 DIV — 분열 기록)
turn_rank_probe  <- mk_turn("DIV")       # 양성 대조 probe 전용 (검증기 방언)
mom_leaf <- list(leaf = "SPECIAL_OP",
  escape_contract = list(escape_type = "SPECIAL_OP",
    op_code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R (mret 블록 — 캘린더월 복리 log(1+mr), 형성창 t-2..t-7)",
    walk_forward = TRUE),
  op_code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R", walk_forward = TRUE)
z_mom <- list(op = "CS_ZSCORE", args = list(mom_leaf), children = list(mom_leaf))
AST <- list(op = "WHERE", args = list(z_mom, turn_rank, 0.33333),
            children = list(z_mom, turn_rank), threshold = 0.33333)
AST_PROBE <- list(op = "WHERE", args = list(z_mom, turn_rank_probe, 0.33333),
                  children = list(z_mom, turn_rank_probe), threshold = 0.33333)

## ═══ alpha_package.json ═════════════════════════════════════════════════════
CS <- O6$CS[is.finite(alpha_hat)]
av <- setNames(as.list(round(CS$alpha_hat, 6)), CS$Ticker)
cv <- setNames(as.list(round(CS$confidence, 4)), CS$Ticker)
H <- HYP$selected
pkg <- list(
  task_id = "WT-R20260829_003", strategy_id = "WT-R20260829_003_LS2000_turnover_stratified_momentum",
  as_of_date = "2026-08-29", forecast_horizon = "1M", spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-08-28", decision_ts = "2026-08-28"),
  hypothesis = list(
    statement = H$hypothesis_description,
    mechanism = H$mechanism,                      # 승계 — 재작성 금지 (Charter 원칙 8)
    falsification = list(
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Vol",
           expectation = "[1급] 승자 데실 내부, 형성기 회전율(Vol*Close/Size, 시장-내 랭킹) 저층-고층 forward 1M 스프레드가 유의 양(+). [실측] 독립정렬 -6.51%/yr t -0.807 · 조건부 -4.14%/yr t -0.649 · adv20 층내부 -3.38%/yr t -0.729 → 기각(부호 반대, 비유의). 단 논문 배율 검정력 3~5%."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Ret",
           expectation = "[2급] 저회전 조건부 top-25 의 β-통제 α 증분 > 0 vs 무조건부 cell4(+5.14%/yr). [실측] arm B 증분 -0.19%p (짝지음 β-통제 t -0.054) → 전이 실패."),
      list(field = "FDB-B2_registry_rawdata_price_daily", field_column = "L01_Amihud",
           expectation = "[교란 기각] 회전율 효과가 L-family 통제 후 소멸하면 유동성 재명명. [실측] 통제 전 스프레드가 이미 비유의라 소멸 여부를 물을 대상이 없다. 대신 순수 L01_Amihud stratifier 누출 귀무가 |t| 2.886 로 회전율 신호(0.807)를 넘는다 — 승자 내부를 가르는 축은 유동성 계열."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Size",
           expectation = "[교란 진단] 저회전 = 소형인가. [실측] 시장-내 회전율 랭킹과 size 백분위의 월별 Spearman 평균 +0.018 (V1 승자 size_pct 0.452 vs V3 0.492) — 크기 축과 사실상 직교. 얽힌 축은 거래대금(rho +0.401)이다."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "BM_Ret",
           expectation = "[부수 관측] 저회전 승자의 후속 공시창 실현 시장조정 수익이 우위여야 한다(LS2000 8분기 CAR 의 KR 대응). [실측] 3일 CAR V1 +0.132% vs V3 -0.024%, 차 +0.156% NW(11)-t +1.315 — 방향 지지·유의 미달. C01_SUE 미사용.")),
    regime_scope = H$regime_scope),                # 승계 — 재작성 금지
  ast = AST,                                        # ★top-level — 정적검증기(ast_verify.py) 진입점
  ast_dialect_note = "★두 겹의 계약 표면 분열을 동시에 처리한다. (1) 구조 방언: schema=args / ast_verify=children+명명파라미터 → 두 키를 모두 싣는다. (2) 연산자 이름 분열: 나눗셈이 schema.json enum 에서는 DIV_GUARD, ast_verify.py operator_library(ARITH_OPS)에서는 DIV 다 — 한 이름만 쓰면 한쪽이 반드시 실패하므로(DIV_GUARD 실측 FAIL_CONTRACT) top-level ast 에는 DIV, factors[0].ast 에는 DIV_GUARD 를 싣는다. 의미는 동일한 보호 나눗셈이며 이 분열은 하네스 수리 대상으로 기록한다. 2/20 라운드에서 factors[].ast 만 실어 검증기가 리프 0개를 순회한 전례(빈 검증)를 회피하기 위해 top-level ast 를 둔다 — 실제 순회 리프 수를 ast_verify_result 에 기록한다.",
  ast_operator_gap = list(
    missing_op = "CS_RANK(group=...) — 그룹(시장) 내부 단면 랭크",
    why_needed = "LS2000 이 Nasdaq 을 배제한 이유의 KR 대응: K200/KQ150 회전율 관행 차이 때문에 혼합 랭킹은 시장 더미로 오염된다(본 라운드 실측: 혼합 랭킹 -19.58%/yr NW-t -2.526, KQ 비중 V1 14.1% vs V3 65.3%).",
    used_instead = "AST 표기는 CS_RANK(ungrouped), 실제 계산은 (Date, mkt) 그룹 내부 백분위 — 코드 경로 stage_artifacts/WT_R20260829_003/s2_primary.R 의 `tr` 정의.",
    backlog_candidate = TRUE,
    note = "우회 구현이 아니라 표기 공백이다 — 계산은 가설이 요구한 그대로 수행했다. 06_Registry/ast_operator_backlog.json 적립은 본 에이전트 권한 밖이라 기록만 남긴다."),
  factors = list(list(
    factor_id = "F1_JT1993_mom_J6_skip1_x_turnover_stratum",
    ast = AST, role = "core_signal", restatement_exposure = 0L)),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Vol", availability_rule = "fixed: 일간 거래량 T+0 — 회전율 형성창은 t-2..t-7 월만 참조", restatement_prone = TRUE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Close", availability_rule = "fixed: 일간 종가 T+0 — 동일 형성창", restatement_prone = TRUE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Size", availability_rule = "fixed: 시총 T+0 — 동일 형성창(회전율 분모)", restatement_prone = TRUE),
      list(leaf = "SPECIAL_OP", availability_rule = "코드 경로 escape — 형성창 t-2..t-7 만 입력. detect_lookahead clean.", restatement_prone = FALSE)),
    verdict = "warn_restatement",
    notes = "RAWDATA 는 수정주가 원장이라 restatement_prone=true(액면분할·배당 시 과거 전 구간 재작성). 본 라운드는 pin 을 걸지 않았고 단일 스냅샷에서 전 arm 을 동시 산출했으므로 arm 간 대비는 같은 vintage 위에 있다. 다중 라운드 비교 시 pin_cache 의무(measurement-graduation §7). 재무·컨센서스 리프 0 — 1/20 의 C01_SUE fail_lookahead_suspected 축은 본 라운드에 없다."),
  alpha_vector = av, confidence_vector = cv,
  alpha_vector_note = "발행 스펙 = 사전등록 2급 arm B(저회전 V1 정의역). V1 층 FM 기울기 x z(모멘텀) − 정의역내 평균. as_of 2026-08-28 · 347종 중 V1 정의역 115종. 정의역 밖 종목은 alpha_vector 에 부재하며 alpha_scores.parquet 의 alpha_hat_stratified 컬럼이 전 종목 층별 FM 예측을 병기한다.",
  signal_matrix_ref = "stage_artifacts/WT_R20260829_003/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "Momentum", proxy = "J6/skip1 누적 로그수익 (JT1993 6-6 계열)",
         formula = "sum_{k=2..7} log(1 + monthly_ret_{t-k})",
         lag_rule = "price t-1 close · 형성기 t-2..t-7 (직전 1개월 skip)",
         winsorization = "none (기저 엔진 원형 유지 — 강화 시도의 신호 고정 의무)",
         neutralization = "none", economic_rationale = "behavioral — 정보 확산 지연에 따른 과소반응 지속",
         redundancy_cluster_id = "MOM_return_derived (DIST-AR-003/007/041 소진 계열)",
         weight_theta = 1.0,
         references = list("Jegadeesh & Titman (1993, JF 48(1):65-91) https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf")),
    list(factor_family = "Liquidity/Volume", proxy = "형성기 일평균 회전율 (거래주식수/상장주식수)",
         formula = "mean_{k=2..7} mean_daily( Vol*Close/Size )",
         lag_rule = "t-2..t-7 월 (당월·t-1 전면 배제 — C10 보수 준수)",
         winsorization = "none (백분위 랭킹 사용)",
         neutralization = "시장-내(K200/KQ150) 랭킹 = 시장 더미 통제",
         economic_rationale = "관심-주도 매매 활동량 — LS2000 MLC 의 생애 단계 대리. KR 에서는 승자 사이드에서 기전이 재현되지 않았다.",
         redundancy_cluster_id = "LIQ_turnover (기존 등재 L02_Turnover / L15_Turnover_252d 와 방향 중복 — redundancy_check 참조)",
         role = "stratifier (정의역 결정) — 점수 합성에 미진입",
         weight_theta = 0.0,
         references = list("Lee & Swaminathan (2000, JF 55(5):2017-2069) https://onlinelibrary.wiley.com/doi/abs/10.1111/0022-1082.00280"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(arms$B_lowturn_V1_top25$port_t_capw),
    canonical_port_t_pvalue = num(arms$B_lowturn_V1_top25$port_p),
    canonical_n_months = 259L,
    canonical_port_t_note = "발행 스펙(arm B) 값. 대조군 arm A = +1.294 · 변형 B2 +0.900 · C +1.170 · D +1.129. 전 arm 무신호 대조 구별불가 — 이 수치들을 알파로 인용할 수 없다.",
    portfolio_alpha_t_beta_controlled = num(arms$B_lowturn_V1_top25$beta_controlled$t_alpha),
    portfolio_alpha_beta_controlled_ann = num(arms$B_lowturn_V1_top25$beta_controlled$alpha_ann),
    beta = num(arms$B_lowturn_V1_top25$beta_controlled$beta),
    increment_vs_baseline_alpha_ann = num(incr$B_lowturn_V1_top25$increment_alpha_ann),
    rank_ic = num(S5$advisory_battery$momentum_score$rank_ic),
    icir = num(S5$advisory_battery$momentum_score$icir),
    harvey_t_stat = num(S5$advisory_battery$momentum_score$nw_t),
    harvey_t_stat_note = "모멘텀 rank-IC 월계열의 NW lag-3 t (advisory). ★portfolio-alpha t 와 구분 — measurement-graduation §2. 새 재료(저회전 선호)의 rank-IC 는 +0.0287 / NW-t +3.211 로 훨씬 강한데 top-25 소비로 전이되지 않는다(전이 벽).",
    rank_ic_turnover_low_pref = num(S5$advisory_battery$turnover_low_pref$rank_ic),
    icir_turnover_low_pref = num(S5$advisory_battery$turnover_low_pref$icir),
    harvey_t_turnover_low_pref = num(S5$advisory_battery$turnover_low_pref$nw_t),
    monotonicity = num(S5$advisory_battery$monotonicity_winner_row$spearman_rank_vs_ret),
    monotonicity_note = "승자행 V1/V2/V3 = 12.17/19.75/16.82 %/yr — LS2000 예측(V1>V2>V3 단조 감소)과 불일치(비단조, 최저가 V1).",
    subperiod_stability = num(S5$advisory_battery$subperiod_stability_armC),
    turnover_proxy = num(arms$B_lowturn_V1_top25$turnover_annual),
    net_sr = num(arms$B_lowturn_V1_top25$net_sr),
    deflated_sharpe_ratio = num(S5$advisory_battery$dsr_diagnostic$B_lowturn_V1_top25),
    oos_retention_approx = num(S5$advisory_battery$oos_retention_approx$B_lowturn_V1_top25$median),
    post_neutralization_ic = num(S5$advisory_battery$post_neutralization$post),
    post_neutralization_retention = num(S5$advisory_battery$post_neutralization$retention),
    diag_ew_universe_port_t = num(arms$B_lowturn_V1_top25$diag_ew_universe$port_t),
    diag_cap_tier_weight_share = arms$B_lowturn_V1_top25$diag_cap_tier$weight_share_avg,
    no_signal_control_verdict = S4$no_signal_control$gates$B_lowturn_V1_top25$verdict,
    alpha_inheritance_cor = 1.0,
    alpha_inheritance_note = "기저 RP_20260829_122020_9192 와 점수 신호 동일(엔진 그대로 승계). 본 라운드가 바꾼 것은 정의역(회전율 층화)이다. wt_type=reinforcement 이므로 alpha_discovery_certificate 미발급이 정상.",
    harvey_t_specs_pass_count = 0L),
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  n_trials = 8L, selection_type = "chain",
  challenge_flags = alpha_validation$challenge_flags,
  preregistered_verdicts = verdicts,
  disposition = disposition,
  exploratory_not_preregistered = expl,
  validation_ref = "stage_artifacts/WT_R20260829_003/alpha_validation.json",
  handoff_conditions_honored = list(
    `1_no_continuous_composite` = "준수 — 전 arm 이 정의역 제한(층화). mom rank − turnover rank 형태 미구현.",
    `2_adv20_internal_and_lfamily` = "준수 — adv20 터사일 층 내부 측정 + L-family raw/rank 두 통제 규약 + 결과량 층화 + 누출 귀무 + 절단면 프로파일. 층 내부 회전율 분산 선측정(retention 0.829, n_med 5)도 수행.",
    `3_ew_universe_and_cap_tier` = "준수 — 전 8 arm 에 diag_ew_universe + diag_cap_tier 병기.",
    `4_market_internal_ranking` = "준수 — 시장-내 랭킹 사용 + 혼합 랭킹 대조로 양성 대조 실증.",
    `5_disposition_bands` = "준수 — 사전 정의 밴드로 판정(reject).",
    `6_side_observation_not_SUE_alone` = "준수 — 실현 공시창 3일 CAR 이 주, 실현 DART 순이익성장이 보조. C01_SUE 미사용."))
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S7] alpha_package.json written\n")

## ═══ lineage (write_json 이후 — L-194) ══════════════════════════════════════
source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_003", package_type = "alpha_package",
  method_selected = "LS2000 회전율 조건부 모멘텀 생애주기 — 승자 데실 x 회전율 이중정렬 층화 (신호 = JT1993 J6/skip1 고정)",
  input_file_paths = c(
    file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"),
    file.path(ROOT, ".cache/rawdata.parquet"),
    file.path(MBX, "alpha_hypothesis.json"),
    file.path(OUT, "alpha_scores.parquet"),
    file.path(OUT, "alpha_validation.json")))
cat("[S7] lineage recorded\n")

## ═══ AST 양성 대조 probe — 연산자 이름 분열의 원인 격리 ══════════════════════
##   본 패키지와 트리가 동일하되 나눗셈 이름만 DIV(검증기 방언)로 바꾼 사본을
##   stage_artifacts 에 두고 같은 검증기를 돌린다. 두 결과의 차이가 정확히
##   'DIV_GUARD vs DIV' 하나임을 실증한다(빈 검증·형상 오류가 아님을 함께 보인다).
probe <- pkg
probe$ast <- AST_PROBE
probe$factors[[1]]$ast <- AST_PROBE
probe$strategy_id <- "WT-R20260829_003_ASTPROBE_divname"
write_json(probe, file.path(OUT, "alpha_package_divname_probe.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S7] ast probe written\n")
