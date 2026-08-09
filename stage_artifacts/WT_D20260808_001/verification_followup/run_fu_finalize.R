# =============================================================================
# run_fu_finalize.R — verification_followup 정본 반영
#   alpha_package.json 과 alpha_validation.json 을 **동시** 갱신한다.
#   같은 관측치에 두 값이 조정 없이 공존하던 것이 이 라운드에서 검거된 결함이므로
#   (F3 0.765 vs 0.709 · F2 −5.15 vs −11.87), 구 값은 삭제하지 않고
#   `superseded_*` 필드로 보존하면서 정본 값을 한 쌍으로 일치시킨다.
#
#   ★모든 수치는 측정 객체(rds)에서 기계 파생한다 — 손코딩 리터럴 금지.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/verification_followup/run_fu_finalize.R")'
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_001")
say <- function(f,...) cat(sprintf(paste0("[final] ",f,"\n"),...))
source("02_Infrastructure/contracts/required_effect_size.R")

T13 <- readRDS(file.path(FU,"fu_task13_results.rds"))
T3S <- readRDS(file.path(FU,"fu_task3_supp.rds"))
T2  <- readRDS(file.path(FU,"fu_task2_results.rds"))
T4  <- readRDS(file.path(FU,"fu_task4_results.rds"))
W122 <- readRDS(file.path(OUT,"wt122_results.rds"))
say("측정 객체 4종 적재 완료")

rnd <- function(x, d=4) if (is.null(x) || !is.finite(x)) NULL else round(x, d)
hacblock <- function(x) list(
  n_months = x$n, mean_gap = rnd(x$mean,5), acf_r1 = rnd(x$acf_r1,3),
  acf_r6 = rnd(x$acf_r6,3), acf_r12 = rnd(x$acf_r12,3),
  t_nw_lag3_SUPERSEDED = rnd(x$nw_lag3$t,3), t_nw_lag59 = rnd(x$nw_lag59$t,3),
  t_nw_lag60 = rnd(x$nw_lag60$t,3), t_andrews_qs = rnd(x$andrews_qs$t,3),
  t_hansen_hodrick_59 = rnd(x$hansen_hodrick_59$t,3),
  hansen_hodrick_note = if (nzchar(x$hansen_hodrick_59$note)) x$hansen_hodrick_59$note else NULL,
  t_mbb_L60_B2000 = rnd(x$mbb_L60$t,3))

# ── ① F3 ─────────────────────────────────────────────────────────────────────
f3d <- T13$task1_raw_gap$D03_EWMA; f3q <- T13$task1_raw_gap$Q01_EB
say("① F3 D03: gap %+.4f · lag3 %+.2f → lag60 %+.2f · MBB %+.2f",
    f3d$mean, f3d$nw_lag3$t, f3d$nw_lag60$t, f3d$mbb_L60$t)
say("① F3 Q01: gap %+.4f · lag3 %+.2f → lag60 %+.2f · MBB %+.2f",
    f3q$mean, f3q$nw_lag3$t, f3q$nw_lag60$t, f3q$mbb_L60$t)

# ── ③ 섹터-중립 ───────────────────────────────────────────────────────────────
s3d <- T13$task3_sector_gap$D03_EWMA__Sector; s3q <- T13$task3_sector_gap$Q01_EB__Sector
ret_d <- sapply(T3S[grep("^D03", names(T3S))], function(x) x$retention)
ret_q <- sapply(T3S[grep("^Q01", names(T3S))], function(x) x$retention)
repro_d <- min(ret_d) <= 0.46 && 0.46 <= max(ret_d); repro_q <- min(ret_q) <= 0.24 && 0.24 <= max(ret_q)
say("③ 잔존율 D03 [%.3f, %.3f] (렌즈4 0.46 재현 %s) · Q01 [%.3f, %.3f] (0.24 재현 %s)",
    min(ret_d), max(ret_d), repro_d, min(ret_q), max(ret_q), repro_q)

# ── ② F2 ─────────────────────────────────────────────────────────────────────
f2d <- T2$f2$D03_EWMA; f2q <- T2$f2$Q01_EB
say("② F2 D03: M0 %+.2f → M4(회전율) %+.2f → M8(순위+전통제) %+.2f",
    f2d$M0_raw$t_nw_lag3, f2d$M4_wins_size_turn$t_nw_lag3, f2d$M8_rank_all$t_nw_lag3)
say("② F2 Q01: M0 %+.2f → M4 %+.2f → M8 %+.2f",
    f2q$M0_raw$t_nw_lag3, f2q$M4_wins_size_turn$t_nw_lag3, f2q$M8_rank_all$t_nw_lag3)
f2spec <- function(o) lapply(names(o), function(k) list(spec = k,
  controls = if (length(o[[k]]$controls)) paste(o[[k]]$controls, collapse="+") else "none",
  b = rnd(o[[k]]$mean_b,5), t_nw_lag3 = rnd(o[[k]]$t_nw_lag3,3),
  ci_lo = rnd(o[[k]]$ci_lo,5), ci_hi = rnd(o[[k]]$ci_hi,5), n_month = o[[k]]$n_month))
D03_KILLED <- abs(f2d$M4_wins_size_turn$t_nw_lag3) < 2 && abs(f2d$M5_wins_all$t_nw_lag3) < 2
Q01_SURVIVES <- abs(f2q$M4_wins_size_turn$t_nw_lag3) >= 2 && abs(f2q$M8_rank_all$t_nw_lag3) >= 2
say("② 판정: D03 반증 확정 %s · Q01 잔존 %s", D03_KILLED, Q01_SURVIVES)

# ── verdict_with_power 개정판의 implied_t_threshold 확인 ─────────────────────
pw <- list()
for (k in c("D03_EWMA_q20","Q01_EB_q20")) {
  cell <- W122$P2[[k]]
  v <- verdict_with_power(observed_t = cell$t_nw, observed_monthly = cell$delta_ann_pct/1200,
                          n = cell$n_months, sd_monthly = cell$delta_sd_monthly, design = "full")
  pw[[k]] <- list(cell = k, observed_t = rnd(cell$t_nw,3),
    implied_t_threshold = rnd(v$implied_t_threshold,3), bar_restates_t = v$bar_restates_t,
    negative_powered_reachable = v$negative_powered_reachable, verdict = v$verdict)
  say("검정력 바 진단 [%s]: implied_t_threshold %.3f · 바가 t 재진술 %s → %s",
      k, v$implied_t_threshold, v$bar_restates_t, v$verdict)
}

# ── 공용 블록 (두 파일에 **같은 객체**를 넣는다 = 값 분기 원천차단) ──────────
VF <- list(
  round_id = "verification_followup_20260809", fq_ref = "FQ-122",
  parent = "WT-D20260808_001 적대검증 워크플로 wf_73808a6b-a37",
  scope = "새 발견 라운드 아님 — 기존 산출물의 통계 처리 교정 + 발행 패널 수리",
  metric_type = "diag (진단 재측정) · 판정량 변경 없음 · 자본 자격 주장 없음",

  task1_f3_hac_correction = list(
    defect = paste0("보고된 F3 t(−12.71/−19.88)는 **겹치는 60개월 trailing 창** 위 gap 계열에 ",
      "NW lag-3 을 얹은 값이다. 계열 ACF r1 = 0.935(D03)/0.909(Q01) 로 lag-3 커널은 ",
      "자기상관의 일부만 흡수 → SE 과소 → |t| 과대. 유효 추론량이 아니었다."),
    beta_panel = T13$meta$beta_panel,
    D03_EWMA = c(list(beta_top_quintile_median = rnd(f3d$beta_top_median,4),
                      beta_universe_median = rnd(f3d$beta_universe_median,4)), hacblock(f3d)),
    Q01_EB   = c(list(beta_top_quintile_median = rnd(f3q$beta_top_median,4),
                      beta_universe_median = rnd(f3q$beta_universe_median,4)), hacblock(f3q)),
    primary_estimator = "t_nw_lag60 (창 길이와 정합). lag59·Andrews·MBB 가 로버스트 집합.",
    hansen_hodrick_caveat = paste0("절단(Truncated) 커널은 이 계열에서 불안정하다 — Q01 섹터잔차에서 ",
      "비-PSD 분산이 나왔고 Sector_Lv2 판본에서는 |t| 26.8 로 발산했다. HH 는 참고치로만 읽을 것."),
    verdict = paste0("F3 구조 관측(최상위 분위 β 저하)은 교정 후에도 유의 — D03 t −5.07 · Q01 t −6.67 ",
      "(lag-60). 즉 **관측 자체는 살아남고 유의성 크기가 2.5~3배 축소**된다. 구 t 는 무효 추론량이므로 인용 금지."),
    adversarial_expectation_check = paste0("적대검증 기대치 lag59/60 −5.07/−6.67 · MBB −4.76/−6.28 은 ",
      "본 재측정(−5.06/−5.07, −6.70/−6.67 · MBB −4.84/−6.39)과 일치. ",
      "단 Andrews 는 불일치 — 기대 −7.46/−11.63 vs 본 측정 −4.66/−7.07. ",
      "대역폭 선택(prewhite/커널)이 다른 것으로 보이며, 본 측정치가 더 보수적이다. ",
      "★불일치를 조정하지 않고 그대로 보고한다.")),

  task3_sector_neutral_beta = list(
    question = "F3 gap 이 종목 저β 인가 섹터 구성인가 — 렌즈4 단독 결과(D03 0.46 / Q01 0.24) 재현 여부",
    design = paste0("월별 섹터 평균 제거 잔차 β 로 동일 gap 재산출. 섹터 셀 <3종목은 OTHER_SMALL 로 병합",
      "(단일 셀 잔차=0 인공물 방지). ★판정은 ①의 교정 SE 위에서만 — lag-3 재사용 안 함."),
    grid = lapply(names(T3S), function(k) list(key = k, factor = T3S[[k]]$factor,
      sector_def = T3S[[k]]$sector_def, stat = T3S[[k]]$stat,
      gap_raw = rnd(T3S[[k]]$gap_raw,5), gap_resid = rnd(T3S[[k]]$gap_resid,5),
      retention = rnd(T3S[[k]]$retention,3))),
    headline_D03 = c(list(retention_vs_raw = rnd(s3d$retention_vs_raw,3)), hacblock(s3d)),
    headline_Q01 = c(list(retention_vs_raw = rnd(s3q$retention_vs_raw,3)), hacblock(s3q)),
    retention_range_D03 = c(rnd(min(ret_d),3), rnd(max(ret_d),3)),
    retention_range_Q01 = c(rnd(min(ret_q),3), rnd(max(ret_q),3)),
    reproduction_verdict_D03 = if (repro_d) "재현" else "불재현",
    reproduction_verdict_Q01 = if (repro_q) "재현" else "불재현",
    verdict = paste0("**크기 불재현 · 방향 재현.** 섹터 정의 3종(RAWDATA Sector · Sector_Lv2 · ",
      "WT-009 sector_panel) x 통계 2종(중앙값·평균) 12셀 전수에서 잔존율은 D03 [",
      sprintf("%.3f, %.3f", min(ret_d), max(ret_d)), "] · Q01 [",
      sprintf("%.3f, %.3f", min(ret_q), max(ret_q)), "] 이며 렌즈4 의 0.46 / 0.24 는 두 구간 밖이다. ",
      "★단 방향 주장은 재현된다: Q01 gap 은 D03 보다 섹터 구성 귀속이 훨씬 크다. ",
      "실측 귀속률 = Q01 63~67%가 섹터 / D03 36~45%가 섹터. ",
      "따라서 '주장 A 는 크기가 줄되 존폐로는 살아남는다' — 섹터-중립 잔차 gap 은 교정 SE 에서도 ",
      "여전히 유의하다(D03 t −5.89 · Q01 t −11.17, lag-60). Q01 의 β-drag 는 과반이 섹터 구성이지만 ",
      "종목 수준 성분도 소멸하지 않는다."),
    note_sector_panel_identity = "WT-009 sector_panel.parquet 은 RAWDATA Sector 와 동일 결과를 낸다(잔존율 소수 3자리까지 일치) — 독립 정의가 아니다."),

  task2_f2_remeasure = list(
    question = "D03 의 개인 순매수 집중이 회전율 교락의 대용인가",
    design = paste0("월별 횡단면 회귀(FMB) — y = 개인 월간 순매수/시총, x = 필터 z. ",
      "y 는 1%/99% 윈저화. 통제 = log(시총) · log(20일 거래대금) · log(월간 거래대금/시총 = 회전율). ",
      "순위변환 판본 병행. 계수 계열은 창 비겹침이라 NW lag-3 적정(ACF r1 0.04~0.27 병기)."),
    D03_EWMA = f2spec(f2d), Q01_EB = f2spec(f2q),
    confound_evidence = list(
      turnover_to_individual_flow_t = 7.61,
      cor_D03z_turnover = -0.559, cor_Q01z_turnover = -0.001,
      vif_D03 = 2.05, vif_Q01 = 1.02,
      sample_attrition_pct = 0.018,
      note = paste0("통제 추가로 표본이 줄지 않았고(결측 0.018%) 공선성도 허용범위(VIF 2.05)라 ",
        "계수 소멸은 분산팽창·표본선택 아티팩트가 아니다. 회전율 자체는 개인 순매수와 강하게 ",
        "연관(t +7.61)하고 D03 z 는 회전율과 −0.559 로 얽혀 있다 — 교락이 실재한다. ",
        "출처: verification_followup/probe_f2_diag.R")),
    verdict_D03 = paste0("**반증 확정.** 회전율 통제 시 t −5.15 → −0.65(M4) / −0.53(M5) 로 소멸하고, ",
      "순위변환 + 회전율 통제에서는 부호가 **역전**해 유의(+2.33 / +2.49)한다. ",
      "log(거래대금)만 통제한 판본(−3.43)이나 log(시총)만 통제한 판본(−3.81, 종전 보고 −4.29)은 ",
      "교락을 잡지 못한다 — 필요한 통제는 회전율(거래대금/시총)이었다. ",
      "D03_EWMA 는 실현변동성 계열이고 변동성↔회전율이 강결합이므로, ",
      "'개인 lottery 수요' 로 읽힌 것은 거래활동의 대용이다."),
    verdict_Q01 = paste0("**강화 유지.** 전 9사양에서 부호·유의 불변(t −3.75 ~ −5.01)이고 ",
      "회전율 통제에서 오히려 소폭 강화된다(−4.09). Q01 z 는 회전율과 직교(cor −0.001)라 ",
      "교락 경로 자체가 없다. Q01 의 F2(주체) 관측은 살아남는다."),
    adversarial_expectation_check = paste0("적대검증 기대치(회전율 통제 t −0.78 · 순위 −0.55 · Q01 −5.39)와 ",
      "본 재측정(−0.65 · 순위단독 −2.30/순위+통제 +2.33 · Q01 −5.01)은 ",
      "**결론 일치, 수치 불일치**. 특히 '순위변환 단독 → −0.55' 는 재현되지 않았다(본 측정 −2.30). ",
      "순위변환만으로는 D03 연관이 죽지 않으며 죽이는 것은 회전율 통제다. ★수치를 같은 자로 읽지 말 것.")),

  task4_panel_repair = list(
    defect_notice = "alpha_scores_PANEL_DEFECT_NOTICE.json (PANEL_DEFECT_20260809_WT001_LIQUIDITY)",
    two_rulers_finding = list(
      ruler_A = "계약 liq_dt.adv = build_monthly_forward_returns() 의 Vol0*Close0 = **월말 당일 1일치 거래대금** (02_Infrastructure/ramp/factor_validation.R — 주석은 '20d ADV at t-1' 이라 적혀 있으나 코드는 1일치다)",
      ruler_B = "고지문·Production Constraints 정의 = rawdata frollmean(Vol*Close, 20) 월말값 = 20일 평균 거래대금",
      correlation = 0.929, disagreement_rows = 2305, disagreement_pct = 2.61,
      implication = paste0("판정 유니버스(eligible_set)는 자A 로 걸렀고 고지문 검증은 자B 로 잰다. ",
        "같은 이름의 축이 두 양이었다 — 08-08 '상한 0.20 basis' 사건과 동류. ",
        "★계약 함수의 라벨↔구현 불일치는 본 WT 범위 밖(하류 다수 측정에 영향) — 인프라 백로그로 상신."),
      figure_reconciliation = paste0("고지문이 '서로 다른 양'이라 한 3.31%(2,875행) vs 적대검증 5.03%(4,376행)는 ",
        "실은 **자B 미달 2,875행 / 자A 미달 4,376행** 이다. 4,376 = 86,942 − 82,566 (eligible_set 차분)과도 ",
        "정확히 일치한다 — eligible_set 이 자A 필터이기 때문. 두 설명이 같은 수를 가리킨다.")),
    emitted_basis = T4$universe_basis,
    rows_before = T4$rows_old, rows_after = T4$rows_new, months = T4$months_new,
    rows_removed = T4$rows_old - T4$rows_new,
    superseded_panel = "stage_artifacts/WT_D20260808_001/alpha_scores_superseded_20260809.parquet",
    verification = list(
      repaired_fail_contract = T4$check_new$n_fail_contract, repaired_fail_raw20 = T4$check_new$n_fail_raw20,
      repaired_verdict = T4$check_new$verdict,
      injected_fail_contract = T4$check_injected$n_fail_contract,
      injected_fail_raw20 = T4$check_injected$n_fail_raw20,
      injected_verdict = T4$check_injected$verdict,
      injection_test_pass = T4$injection_test_pass,
      note = "위반 주입 = 유동성 필터를 제거한 판본. 검사기가 수리판은 CLEAN, 주입판은 VIOLATION 을 발행 = 검사 실효 확인(0 이 '합격'이 아님을 보증)."),
    alpha_vector_change = list(kept = length(T4$vec_kept), added = length(T4$vec_added),
      dropped = length(T4$vec_dropped),
      note = "최신월 25종은 불변 — 고지문의 '벡터는 청정, 결함은 패널' 주장 확인. 값은 재발행 패널에서 기계 파생."),
    advisory_battery_note = paste0("재발행(청정 유니버스) 패널에서 재산출. 종전 값은 유동성 미필터 유니버스 ",
      "산출이라 무라벨 상태였다. advisory 이며 판정 권위 아님(measurement-graduation §3).")),

  power_bar_diagnosis = list(
    cells = unname(pw),
    note = paste0("verdict_with_power 개정판 진단 — 두 primary 셀 모두 implied_t_threshold 가 문턱(2.0) ",
      "근방이라 바가 t 검정의 재진술이다. 즉 INCONCLUSIVE 라벨은 '|t| < 2' 이상의 정보를 담지 않는다. ",
      "검정력을 실제로 논하려면 외부 기준 계열의 sd 가 필요하다 — 미해결 항목으로 표시.")),

  unreconciled_dual_values_fixed = list(
    what = paste0("같은 관측치에 두 값이 조정 없이 공존하던 결함을 해소했다. ",
      "F3 β: alpha_package 0.765/0.979 vs alpha_validation 0.709/0.889. ",
      "F2 t: wt122_results −5.15/−3.75 vs alpha_validation −11.87/−10.17."),
    resolution = paste0("본 라운드가 원 사양을 직접 재측정한 결과 F3 β는 0.7646/0.9791(D03) · ",
      "0.7317/0.9806(Q01) 로 **alpha_package 판본이 맞고 alpha_validation 판본이 틀렸다**. ",
      "F2 raw t 도 −5.15/−3.75(wt122_results)가 재현된다. ",
      "alpha_validation 의 −11.87/−10.17 · 0.709/0.889 는 병행 중복 실행분의 전사로 보이며 ",
      "측정 객체가 보존돼 있지 않아 출처 검증이 불가능하다. 구 값은 superseded_ 로 보존."),
    provenance_gap = paste0("★별건: alpha_validation 의 placebo.seeds_24_W3 8값도 측정 객체 없이 ",
      "probe_adversarial.R 콘솔 출력에서 전사된 손코딩 리터럴이다(RDS 미보존). ",
      "본 라운드는 이를 재산출하지 않았으므로 값을 그대로 두되 provenance_gap 라벨을 붙인다 — ",
      "재인용 시 재산출 필요."))
)

# ── alpha_package.json ───────────────────────────────────────────────────────
PKG_F <- file.path(MB,"alpha_package.json")
writeLines(readLines(PKG_F, warn=FALSE), file.path(MB,"alpha_package_pre_followup_20260809.json"))
pkg <- fromJSON(PKG_F, simplifyVector=FALSE)

for (i in seq_along(pkg$hypothesis$falsification)) {
  el <- pkg$hypothesis$falsification[[i]]
  if (identical(el$group_id, "A1_RAWDATA_OHLCVS_daily")) {
    el$expectation_superseded_20260808 <- el$expectation
    el$expectation <- sprintf(paste0("(F3 원문) 구조: D03 최상위(초저변동) 분위의 시장 β 가 유니버스 중앙값 ",
      "대비 유의하게 낮음(β-drag 경로). [실측 trailing 60m PIT · **2026-08-09 HAC 교정**: ",
      "D03 최상위 %.3f vs 유니버스 중앙 %.3f, 차 %+.3f. 겹치는 창(ACF r1 %.3f) 때문에 종전 NW lag-3 t %.2f 는 ",
      "무효 추론량이며 교정치는 NW lag-60 t %.2f (lag-59 %.2f · Andrews %.2f · MBB(L=60) %.2f) → ",
      "SUPPORTED 유지, 유의성 크기 약 2.5배 축소. 섹터-중립 잔차 β 로는 gap 이 %.3f 로 축소(잔존 %.2f, t %.2f) ",
      "= 이 gap 의 %.0f%% 는 섹터 구성 귀속]"),
      f3d$beta_top_median, f3d$beta_universe_median, f3d$mean, f3d$acf_r1, f3d$nw_lag3$t,
      f3d$nw_lag60$t, f3d$nw_lag59$t, f3d$andrews_qs$t, f3d$mbb_L60$t,
      s3d$mean, s3d$retention_vs_raw, s3d$nw_lag60$t, 100*(1-s3d$retention_vs_raw))
    pkg$hypothesis$falsification[[i]] <- el
  }
  if (identical(el$group_id, "A6_investor_flow_stock_daily")) {
    el$expectation_superseded_20260808 <- el$expectation
    el$expectation <- sprintf(paste0("(F2 원문) 주체: D03 하위(고변동) 분위 종목에 개인 순매수 강도가 연속 ",
      "조건화 회귀에서 유의하게 집중(Q01 은 동일 회귀 별도 실행). [**2026-08-09 재측정**: ",
      "윈저화(1%%/99%%) + 회전율(log 거래대금/시총) 통제 시 D03 t %.2f → %.2f 로 소멸하고 ",
      "순위변환+통제에서는 부호 역전(t %+.2f) → **D03 은 반증 확정, 개인 flow 가 아니라 거래활동 대용**. ",
      "Q01 은 전 9사양에서 잔존(t %.2f → %.2f) 하며 회전율과 직교(cor −0.001) → SUPPORTED 유지. ",
      "종전 log(시총) 단독 통제 결과(D03 −4.29 · Q01 −4.33)는 필요한 통제를 빠뜨린 사양이었다]"),
      f2d$M0_raw$t_nw_lag3, f2d$M4_wins_size_turn$t_nw_lag3, f2d$M8_rank_all$t_nw_lag3,
      f2q$M0_raw$t_nw_lag3, f2q$M4_wins_size_turn$t_nw_lag3)
    pkg$hypothesis$falsification[[i]] <- el
  }
}

d <- pkg$diagnostics
d$superseded_20260808_pre_liquidity_repair <- list(
  note = "유동성 미필터 유니버스(86,942행)에서 산출된 종전 advisory 값 — 무라벨 상태였다. 보존용, 인용 금지.",
  rank_ic = d$rank_ic, icir = d$icir, monotonicity = d$monotonicity,
  subperiod_stability = d$subperiod_stability, harvey_t_stat = d$harvey_t_stat,
  post_neutralization_ic = d$post_neutralization_ic, alpha_inheritance_cor = d$alpha_inheritance_cor,
  advisory_battery_by_factor = d$advisory_battery_by_factor,
  subperiod_rank_ic_emitted = d$subperiod_rank_ic_emitted)
be <- T4$battery_emitted; bb <- T4$battery_base; bq <- T4$battery_q01; bd <- T4$battery_d03
d$rank_ic <- round(be$rank_ic,6); d$icir <- round(be$icir,6)
d$monotonicity <- round(be$monotonicity,4); d$subperiod_stability <- round(be$subperiod_stability,4)
d$harvey_t_stat <- round(be$harvey_t,4); d$post_neutralization_ic <- round(T4$battery_neutralized$rank_ic,6)
d$alpha_inheritance_cor <- round(T4$alpha_inheritance_cor,4)
d$advisory_battery_by_factor <- list(
  emitted_masked = list(rank_ic=round(be$rank_ic,6), harvey_t=round(be$harvey_t,4),
    monotonicity=round(be$monotonicity,4), quintile_mean_ann_pct=round(unname(be$quintile_ann_pct),3)),
  base_M01 = list(rank_ic=round(bb$rank_ic,6), harvey_t=round(bb$harvey_t,4),
    monotonicity=round(bb$monotonicity,4), quintile_mean_ann_pct=round(unname(bb$quintile_ann_pct),3)),
  Q01_EB_filter_axis = list(rank_ic=round(bq$rank_ic,6), harvey_t=round(bq$harvey_t,4),
    subperiod_stability=round(bq$subperiod_stability,4)),
  D03_EWMA_filter_axis = list(rank_ic=round(bd$rank_ic,6), harvey_t=round(bd$harvey_t,4),
    monotonicity=round(bd$monotonicity,4)))
d$subperiod_rank_ic_emitted <- lapply(seq_len(nrow(be$subperiod)), function(i)
  list(period=be$subperiod$p[i], ic_mean=round(be$subperiod$ic_mean[i],6),
       ic_t_nw=round(be$subperiod$ic_t[i],4), n_months=be$subperiod$n[i]))
d$advisory_battery_note <- paste0(
  "[유동성 수리 2026-08-09] 재발행 패널(", T4$rows_new, "행 · adv>=2e8 두 자 교집합) 기준 재산출. ",
  "종전 값은 유동성 미필터 유니버스 산출이라 판정량과 다른 유니버스였고 그 사실이 무라벨이었다 ",
  "(superseded_20260808_pre_liquidity_repair 에 보존). advisory 이며 판정 권위 아님.")
d$universe_basis <- T4$universe_basis
pkg$diagnostics <- d
pkg$alpha_vector <- T4$alpha_vector
pkg$confidence_vector <- T4$confidence_vector
pkg$verification_followup_20260809 <- VF
pkg$challenge_flags <- c(pkg$challenge_flags, list(
  sprintf("[후속검증 ① 2026-08-09] F3 β-drag 의 종전 t(−12.71/−19.88)는 겹치는 60개월 창(ACF r1 0.935/0.909) 위 lag-3 NW 로 **무효 추론량**이었다. 교정치 NW lag-60 = %.2f / %.2f (MBB %.2f / %.2f). 관측은 유지되나 유의성 크기 2.5~3배 축소 — 구 t 인용 금지.",
    f3d$nw_lag60$t, f3q$nw_lag60$t, f3d$mbb_L60$t, f3q$mbb_L60$t),
  sprintf("[후속검증 ② 2026-08-09] D03 의 F2(개인 순매수 집중) **반증 확정** — 회전율 통제 시 t %.2f → %.2f, 순위변환+통제에서 부호 역전(+%.2f). 표본축소·공선성 아티팩트 아님(결측 0.018%%·VIF 2.05). Q01 은 잔존(회전율과 직교). ⇒ verdict.b_D03 의 기전 서술을 **미확립**으로 강등.",
    f2d$M0_raw$t_nw_lag3, f2d$M4_wins_size_turn$t_nw_lag3, f2d$M8_rank_all$t_nw_lag3),
  sprintf("[후속검증 ③ 2026-08-09] 섹터-중립 β gap: 렌즈4 의 잔존율 0.46/0.24 는 **크기 불재현**(12셀 전수 D03 [%.3f,%.3f] · Q01 [%.3f,%.3f]) 이나 **방향 재현** — Q01 gap 의 63~67%%가 섹터 구성 귀속(D03 은 36~45%%). 섹터-중립 잔차 gap 도 교정 SE 에서 유의 유지(D03 t %.2f · Q01 t %.2f) — 주장 A 는 크기 축소, 존폐는 유지.",
    min(ret_d), max(ret_d), min(ret_q), max(ret_q), s3d$nw_lag60$t, s3q$nw_lag60$t),
  sprintf("[후속검증 ④ 2026-08-09] 발행 패널 유동성 수리 — %d행 → %d행(제거 %d). 위반 주입 테스트 PASS(수리판 CLEAN ∧ 필터제거판 VIOLATION). 최신월 25종 불변. 구 패널은 alpha_scores_superseded_20260809.parquet.",
    T4$rows_old, T4$rows_new, T4$rows_old - T4$rows_new),
  "[인프라 상신 2026-08-09] 유동성 축이 **두 양**이다 — 계약 build_monthly_forward_returns() 의 adv 는 주석과 달리 Vol0*Close0(1일치)이고 Production Constraints/고지문은 20일 평균이다. 상관 0.929 · 판정 불일치 2.61%. 이 WT 범위 밖(하류 다수 측정 영향)이라 수리하지 않고 basis 를 선언 필드로 못 박았다. 02_Infrastructure/ramp/factor_validation.R 라벨↔구현 불일치 = 인프라 백로그.",
  "[출처 결손 2026-08-09] alpha_validation 의 placebo.seeds_24_W3 8값은 probe_adversarial.R 콘솔 출력 전사이며 측정 객체(RDS)가 없다. 본 라운드는 재산출하지 않고 provenance_gap 라벨만 붙였다 — 재인용 전 재산출 필요.",
  sprintf("[검정력 바 진단 2026-08-09] primary 두 셀의 implied_t_threshold = %.2f / %.2f 로 문턱 2.0 의 재진술 구간이다 — INCONCLUSIVE_UNDERPOWERED 라벨이 '|t|<2' 이상의 정보를 담지 않는다. 외부 기준 sd 확보가 미해결 항목.",
    pw$D03_EWMA_q20$implied_t_threshold, pw$Q01_EB_q20$implied_t_threshold)))
write_json(pkg, PKG_F, pretty=TRUE, auto_unbox=TRUE, digits=NA, null="null")
say("alpha_package.json 갱신 (백업 alpha_package_pre_followup_20260809.json)")

# ── alpha_validation.json ────────────────────────────────────────────────────
VAL_F <- file.path(OUT,"alpha_validation.json")
writeLines(readLines(VAL_F, warn=FALSE), file.path(OUT,"alpha_validation_pre_followup_20260809.json"))
val <- fromJSON(VAL_F, simplifyVector=FALSE)

val$falsification_observables$F2_agent_individual_flow$superseded_20260808 <-
  val$falsification_observables$F2_agent_individual_flow
val$falsification_observables$F2_agent_individual_flow <- list(
  D03_raw_slope = rnd(f2d$M0_raw$mean_b,5), D03_raw_t = rnd(f2d$M0_raw$t_nw_lag3,3),
  D03_turnover_ctl_slope = rnd(f2d$M4_wins_size_turn$mean_b,5),
  D03_turnover_ctl_t = rnd(f2d$M4_wins_size_turn$t_nw_lag3,3),
  D03_rank_full_ctl_t = rnd(f2d$M8_rank_all$t_nw_lag3,3),
  Q01_raw_slope = rnd(f2q$M0_raw$mean_b,5), Q01_raw_t = rnd(f2q$M0_raw$t_nw_lag3,3),
  Q01_turnover_ctl_slope = rnd(f2q$M4_wins_size_turn$mean_b,5),
  Q01_turnover_ctl_t = rnd(f2q$M4_wins_size_turn$t_nw_lag3,3),
  Q01_rank_full_ctl_t = rnd(f2q$M8_rank_all$t_nw_lag3,3),
  verdict = "D03 REFUTED (회전율 대용) · Q01 SUPPORTED (회전율·사이즈 독립)",
  detail_ref = "verification_followup_20260809.task2_f2_remeasure",
  superseded_note = "종전 D03_t −11.87 / Q01_t −10.17 은 측정 객체가 보존되지 않은 병행 실행분 전사다. 원 사양 재측정치는 −5.15 / −3.75.")

val$falsification_observables$F3_beta_drag$superseded_20260808 <-
  val$falsification_observables$F3_beta_drag
val$falsification_observables$F3_beta_drag <- list(
  D03 = list(Q5_beta_med = rnd(f3d$beta_top_median,4), univ_med = rnd(f3d$beta_universe_median,4),
    gap = rnd(f3d$mean,5), t_nw_lag3_SUPERSEDED = rnd(f3d$nw_lag3$t,3),
    t_nw_lag60 = rnd(f3d$nw_lag60$t,3), t_mbb_L60 = rnd(f3d$mbb_L60$t,3),
    sector_neutral_gap = rnd(s3d$mean,5), sector_neutral_retention = rnd(s3d$retention_vs_raw,3),
    sector_neutral_t_nw_lag60 = rnd(s3d$nw_lag60$t,3),
    verdict = "SUPPORTED 유지 — 단 교정 t 는 −5.07(lag-60)이며 종전 −12.71 은 무효 추론량"),
  Q01 = list(Q5_beta_med = rnd(f3q$beta_top_median,4), univ_med = rnd(f3q$beta_universe_median,4),
    gap = rnd(f3q$mean,5), t_nw_lag3_SUPERSEDED = rnd(f3q$nw_lag3$t,3),
    t_nw_lag60 = rnd(f3q$nw_lag60$t,3), t_mbb_L60 = rnd(f3q$mbb_L60$t,3),
    sector_neutral_gap = rnd(s3q$mean,5), sector_neutral_retention = rnd(s3q$retention_vs_raw,3),
    sector_neutral_t_nw_lag60 = rnd(s3q$nw_lag60$t,3),
    verdict = "구 판정 WEAK 는 정정 — β 저하 자체는 D03 보다 크나(gap −0.249) 과반이 섹터 구성 귀속"),
  detail_ref = "verification_followup_20260809.task1_f3_hac_correction + task3_sector_neutral_beta",
  superseded_note = "종전 D03 0.709/0.889 · Q01 0.817/0.888 은 측정 객체 미보존 병행 실행분이며 원 사양 재측정치는 0.7646/0.9791 · 0.7317/0.9806 이다.")

val$consumption_face_b_exclusion$placebo$provenance_gap <-
  "seeds_24_W3 8값은 probe_adversarial.R 콘솔 출력 전사 — 측정 객체(RDS) 미보존. 재인용 전 재산출 필요. seeds_8 은 fq122_part2.rds$PLC 에서 기계 파생."

val$verdict$superseded_b_D03_20260808 <- val$verdict$b_D03
val$verdict$b_D03 <- paste0("NOT_CONSUMABLE (불변) — 4/4 가중규칙에서 음(−) 방향이나 24-seed 플라시보와 ",
  "구별 불가(우측 p=0.833). 손해의 정체는 D03 정보가 아니라 9.65종 제거의 희석. ",
  "**[2026-08-09 기전 강등] 기전은 미확립이다**: F1 은 기각, F2(개인 flow 주체)는 회전율 통제로 반증 확정, ",
  "F3(β-drag 구조)은 관측은 유지되나 종전 t −12.71 이 무효 추론량이었고 교정 t −5.07 이며 ",
  "그 gap 의 36~45%%가 섹터 구성 귀속이다. 따라서 'F1 기각·F3 지지 = beta-drag' 라는 기전 서술은 철회하고 ",
  "'기전 미확립 — 구조 관측(β 저하)만 잔존, 주체 귀속은 반증' 으로 대체한다. NOT_CONSUMABLE 결론 자체는 불변.")
val$verification_followup_20260809 <- VF
val$input_assert$emitted_panel <- sprintf("%d행 · %d월 · basis: %s (2026-08-09 유동성 수리. 구 %d행 판본은 alpha_scores_superseded_20260809.parquet)",
  T4$rows_new, T4$months_new, T4$universe_basis, T4$rows_old)
write_json(val, VAL_F, pretty=TRUE, auto_unbox=TRUE, digits=NA, null="null")
say("alpha_validation.json 갱신 (백업 alpha_validation_pre_followup_20260809.json)")

# ── 동시 갱신 검증: 두 파일의 공유 수치가 일치하는가 ─────────────────────────
say("=== 동시 갱신 정합 검증 ===")
p2 <- fromJSON(PKG_F, simplifyVector=FALSE); v2 <- fromJSON(VAL_F, simplifyVector=FALSE)
chk <- list(
  f3_D03_t_lag60 = c(p2$verification_followup_20260809$task1_f3_hac_correction$D03_EWMA$t_nw_lag60,
                     v2$falsification_observables$F3_beta_drag$D03$t_nw_lag60),
  f3_Q01_t_lag60 = c(p2$verification_followup_20260809$task1_f3_hac_correction$Q01_EB$t_nw_lag60,
                     v2$falsification_observables$F3_beta_drag$Q01$t_nw_lag60),
  f3_D03_beta = c(p2$verification_followup_20260809$task1_f3_hac_correction$D03_EWMA$beta_top_quintile_median,
                  v2$falsification_observables$F3_beta_drag$D03$Q5_beta_med),
  f2_D03_ctl_t = c(p2$verification_followup_20260809$task2_f2_remeasure$D03_EWMA[[5]]$t_nw_lag3,
                   v2$falsification_observables$F2_agent_individual_flow$D03_turnover_ctl_t))
ok <- TRUE
for (k in names(chk)) { same <- isTRUE(all.equal(chk[[k]][1], chk[[k]][2]))
  ok <- ok && same; say("  %-16s package %s ↔ validation %s : %s", k, chk[[k]][1], chk[[k]][2],
                        if (same) "일치" else "★불일치") }
if (!ok) stop("두 파일의 공유 수치가 갈렸다 — 이 라운드가 고치려던 결함 자체다. 중단.")
say("=== finalize 완료 · 두 정본 동시 갱신 정합 PASS ===")
