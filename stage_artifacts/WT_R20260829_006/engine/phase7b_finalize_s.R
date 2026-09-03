## WT-R20260829_006 Phase 7b — challenge_flags 주입 · alpha_package.json / alpha_validation.json 발행 · lineage
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
ART <- "stage_artifacts/WT_R20260829_006"; MBX <- "qepm/mailbox/worktask/WT-R20260829_006"

B  <- readRDS(file.path(OUT,"p7s_pkg_base.rds")); PKG <- B$PKG
P2 <- readRDS(file.path(OUT,"p2s_tier1.rds")); P3 <- readRDS(file.path(OUT,"p3s_tier2.rds"))
P4 <- readRDS(file.path(OUT,"p4s_mech.rds")); P5 <- readRDS(file.path(OUT,"p5s_candidate.rds"))
P6 <- readRDS(file.path(OUT,"p6s_pit.rds"))
pc <- P2$power_contract; t1 <- P2$tier1; c5 <- P5$canonical; d5 <- P5$diagnostics; b5 <- P5$beta_controlled

cf <- function(id, sev, msg) list(id=id, severity=sev, message=msg)
AS_OF_STR <- PKG$as_of_date
COV0 <- as.data.table(B$as_of_cov)[n_at_as_of == 0, family]
CF <- list(
 cf("RF-A1","HIGH", sprintf("논문 2편(EL2022 게재판 · KSV2018) + 부기간 IC 안정성 %.3f < 0.5 (P1 %.4f / P2 %.4f / P3 %.4f) — Red Flag 규칙 발화.",
    d5$subperiod_stability, d5$subperiod$P1, d5$subperiod$P2, d5$subperiod$P3)),
 cf("WT006-01","HIGH", sprintf("소비면 감쇠: EW-유니버스 대비 post-2017 PORT_t %.3f (전기간 %.3f), oos_retention_approx %.3f — 최근 구간 신호 소멸.",
    c5$diag_ew_universe$post2017_t_nw_lag3, c5$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    c5$diag_ew_universe$oos_retention_approx)),
 cf("WT006-02","HIGH", sprintf("기전 반증 (d) 미통과: PC 순위 vs 자기상관 t Spearman %.3f (상위5 PC 기울기 %.4f t %.2f · 하위5 %.4f t %.2f). EL2022 의 고고유값 집중 예측(상위10 t 6.08 vs 하위7 2.15)이 KR 에서 재현되지 않는다 — 근-차익 마찰 논리가 KR 에서 지지되지 않음. 1급 자기상관이 관측되더라도 기전은 별개로 기각된다(설계 (d) 조항).",
    P4$eigen_ordering$spearman_rank_vs_t, P4$eigen_ordering$top5_slope, P4$eigen_ordering$top5_t,
    P4$eigen_ordering$bottom5_slope, P4$eigen_ordering$bottom5_t)),
 cf("WT006-03","HIGH", sprintf("2급 판정 무효(사전등록 조항): 양방향 흡수. M02 절편 %.4f(t %.2f)→%.4f(t %.2f) · TS-FMOM 절편 %.4f(t %.2f)→%.4f(t %.2f). 두 계열이 같은 것을 재고 있을 가능성 — 어느 쪽이 우선인지 판별 불가.",
    P4$tier2_asymmetry$intercept[1], P4$tier2_asymmetry$t[1], P4$tier2_asymmetry$intercept[2], P4$tier2_asymmetry$t[2],
    P4$tier2_asymmetry$intercept[3], P4$tier2_asymmetry$t[3], P4$tier2_asymmetry$intercept[4], P4$tier2_asymmetry$t[4])),
 cf("WT006-04","MEDIUM", sprintf("검정력: 1급 계열-대표 사양의 EL2022 효과크기(0.45%%/월) 대비 power %.3f · ratio %.3f · MDE80 %.4f. 착수 게이트(ratio>=0.15)는 통과했으나 US 효과크기 기준으로는 저검정력 — KR 실측 효과(%.4f/월)가 EL2022 보다 커서 검출됐다.",
    pc$tier1_primary$power, pc$tier1_primary$ratio, pc$tier1_primary$mde80, t1$primary_family_representative$slope)),
 cf("WT006-05","MEDIUM", sprintf("해상도: 선언 계열 15 중 monthly factor_db 실재 14(technical 12팩터는 daily store 전용 — 월간 미승격). 비-모멘텀 13 계열의 평균 |rho| %.4f → 유효 독립 계열 %.2f. 'F_eff≈15' 는 명목이고 실효 해상도는 3~4다.",
    pc$rho_bar_within_families, pc$F_eff_independent)),
 cf("WT006-06","MEDIUM", sprintf("회전율 %.2f/yr > 구현 규율 권고 11.0/yr (research_philosophy ⑥). 비용은 15bps delta 로 이미 차감된 net 수치이나 용량·집행 부담은 별도 심사 대상.",
    c5$turnover_annual)),
 cf("WT006-07","MEDIUM", "설계의 1급 '계열-대표 1팩터' 를 **계열 내 등가중 합성(EW composite)** 으로 구현. 사유: 대표 1팩터 선택 규칙이 성과 기반이면 selection 오염, 임의면 자의적. 결정론적 대체(계열별 알파벳 첫 팩터)로 강건성 병기 — 기울기 0.00650 t 2.12 로 동일 방향. No Silent Override 로 challenge_note 기록."),
 cf("WT006-08","MEDIUM", "기전 (d) 를 **월별 대체 사양**으로 산출. 설계 W6 은 '일별 커버리지 10년 미달 시 강등' 을 조건으로 걸었으나 실제 daily store 는 1990-01~2026-07 로 커버리지 미달이 아니다 — 강등 사유는 커버리지가 아니라 **일별 계열 L/S 수익 패널 부재(별도 파이프라인 필요)** 다. 조건을 사후에 맞추지 않고 실제 사유를 기록한다."),
 cf("WT006-09","MEDIUM", sprintf("DIST-RAMP-014 사전선언(소비면 증분 <=0) 대비: 실측 β-통제 α %+.4f/yr (t %.3f, β %.3f) vs cell4 +5.14%%/yr (t 1.205, β 1.058) → 증분 %+.2fpp. 방향은 사전선언과 어긋나나 **양쪽 다 |t|<2 로 무의미**하므로 반증으로 승격하지 않는다(DIST-AR-051 재현 의무 미발동).",
    b5$alpha_ann, b5$t_alpha, b5$beta, 100*(b5$alpha_ann - 0.0514))),
 cf("WT006-10","MEDIUM", sprintf("전달식 (c): Σ_f cov(형성,당월)·σ²_β = %.6f/월 vs 실측 M02 평균 %.6f/월 (비율 %.3f). 부호는 양(+)이나 수준으로는 3.6%%만 설명. ★단 EL2022 eq.(9)는 Lo-MacKinlay 가중상대강도 전략에 대한 항등식이고 본 M02 는 2×3 정렬 요인이라 **수준 비교는 동종이 아니다** — 부호·계열 순위만 인용 가능. 첫 항 기여의 71%%가 size 계열 단독.",
    P4$sigma2_beta$sum_term1_per_month, P4$sigma2_beta$realized_m02_mean, P4$sigma2_beta$ratio_term1_to_realized)),
 cf("WT006-11","LOW", "무신호 대조(시총 상위25 cap-w / 무작위 25종)는 Q-Lead 규율 ①(arm 배터리 폐지)에 따라 **미실시**. 설계 3급의 mandatory_confounder_controls 중 해당 항목은 지시로 대체됨 — 승계 설계 대비 축소를 은닉하지 않고 기록한다. 검사기 양성대조(sham-FMOM · F-사다리)는 계약형이므로 유지·통과."),
 cf("WT006-12","LOW", sprintf("self_pit_check restatement_prone 리프 %d/%d — registry 기준. 전부 load_month_factors() 승격분(Usable_Date <= sig_date)이라 구조적 look-ahead 는 없으나 judge WARN_RESTATEMENT 입력.",
    B$n_restate, length(PKG$self_pit_check$leaves_checked))),
 cf("WT006-14","HIGH", "PIT-strict 제외의 부작용: consensus 계열이 실질 소거됐다 — 등록 23팩터 중 12종이 ast_verify FAIL_LOOKAHEAD 로 빠지고 alias 3종이 dedup 되어 **소비 잔존 1팩터(C07_TP_Mom)**. 계열 해상도가 명목 13 이지만 한 계열은 단일 팩터다. 성과 사유가 아니라 PIT 사유의 제외이며 그 대가를 은닉하지 않는다."),
 cf("WT006-15","HIGH", sprintf("as_of(%s) 커버리지 결손: [%s] 계열이 그 달 월간 factor_db 에 부재 → as_of α̂ 는 %d 계열로 구성(역사 스코어는 13 계열). 하류(risk/optimizer/forge)는 이 구성 차이를 인지하고 소비할 것.",
   AS_OF_STR, paste(COV0, collapse=", "), 13L - length(COV0))),
 cf("WT006-13","HIGH", sprintf("자본 층 HARD 미달(진단): canonical PORT_t %.3f (p %.3f) ≪ 2.95. 본 수치는 스크리닝 실측이며 판정 권위는 forge — alpha 단계에서 졸업 판정을 선언하지 않는다.",
    c5$portfolio_alpha_t_nw_lag3, c5$portfolio_alpha_t_pvalue))
)
PKG$challenge_flags <- lapply(CF, function(x) paste0(x$id, " [", x$severity, "] ", x$message))
cat("[flags]", length(CF), "건 (HIGH", sum(vapply(CF,function(x) x$severity=="HIGH",logical(1))), ")\n")

## ── alpha_package.json ────────────────────────────────────────────────────────
pj <- file.path(MBX, "alpha_package.json")
tmp <- paste0(pj, ".tmp")
write(toJSON(PKG, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null"), tmp)
file.rename(tmp, pj)
cat("[saved]", pj, " bytes", file.info(pj)$size, "\n")

## ── alpha_validation.json ─────────────────────────────────────────────────────
VAL <- list(
  task_id = "WT-R20260829_006", produced_by = "alpha-research", produced_at = as.character(Sys.time()),
  paper = list(citation = "Ehsani, S. & Linnainmaa, J. T. (2022). Factor Momentum and the Momentum Factor. Journal of Finance 77(4):1877-1919",
    doi_url = "https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.13131",
    pdf = "https://www.q-group.org/resources/Documents/Linnainmaa_Factor%20Momentum%20Paper.pdf",
    edition_pinned = "게재판(JF 2022). Table 2 기울기 0.45%/월 t 4.22 (시사 SE 0.107). NBER WP w25551(0.52%/월 t 4.67)과 혼용 금지."),
  prior_run_disclosure = list(
    mandatory = TRUE,
    cards = list(
      list(id="DIST-RAMP-014", verdict="DISTILLED_COND",
           statement="지수-비중 최적화 계열(Black-Litterman / 팩터 모멘텀 배분)을 KR 배포 형태인 top-25 횡단면으로 변환하면 엣지가 남지 않는다 — 변환에서 살아남는 것은 알파가 아니라 베타(cor(시장상관, clean IR)=+0.974). 무신호 대조 구별불가. 필요 신호품질 4.18배.",
           relation="본 라운드 소비면 좌표와 정확히 겹침. 설계가 소비면 기대를 음(-)으로 사전 선언했고 그 선언을 승계했다."),
      list(id="DIST-RAMP-026", verdict="DISTILLED_NEG", family="factor_timing_allocation", n_l_codes=5),
      list(id="DIST-AR-033", verdict="DISTILLED_NEG", status="pending_5axis", statement_refined=NA,
           note="초안 — 구속력이 DIST-RAMP-014/026 보다 약하다")),
    lookup_command = "Rscript 02_Infrastructure/tools/hypothesis_index.R lookup factor_timing",
    lookup_result = "30 hits (DISTILLED_NEG 다수). 'spanning' 축 = no prior attempt matched."),
  power_contract = list(
    computed_before_slope_estimation = TRUE,
    method = "H0(기울기=0) 잔차 기반 월-클러스터 SE → MDE80 = (1.96+0.8416)·SE0. 기울기를 추정하지 않고 산출.",
    tier1_primary = pc$tier1_primary, tier1_secondary_all_factors = pc$tier1_secondary_allfactors,
    tier2 = P3$res$power_contract_tier2,
    f_declared_nonmomentum = pc$F_declared_nonmom,
    rho_bar_between_families = pc$rho_bar_within_families,
    f_eff_independent = pc$F_eff_independent,
    gate = "ratio >= 0.15 → 착수 허용", gate_result = "PASS (1급 ratio 0.458 · 2급 ratio 0.626)"),
  tier1_premise = list(
    spec = "EL2022 게재판 Table 2: y = 팩터 f 의 월 t 수익, x = 1{t-12~t-1 평균 > 0}(스킵월 없음), pooled OLS, 월 클러스터 SE, 모멘텀 계열 제외",
    preregistered_primary = "계열-대표 사양(비-모멘텀 계열 13)",
    result = t1$primary_family_representative,
    secondary_all_factors = t1$secondary_all_factors,
    robustness_alphabetical_representative = t1$robustness_alphabetical_representative,
    lag_ladder = t1$lag_ladder, per_family = t1$per_family, per_factor_sign = t1$per_factor_sign,
    verdict = "전제 존재 — reject_if(기울기<=0 또는 |t|<1.96) 미충족. KR 팩터 수익은 12-1 형성 부호에 양(+)으로 반응한다.",
    sample = P2$sample),
  tier2_spanning = P3$res$spanning,
  tier2_asymmetry = P4$tier2_asymmetry,
  tier2_verdict = "판정 무효(사전등록 bidirectional 조항 발동) — 양방향 모두 |t|<1.96 로 흡수. 검사기 양성대조(F-사다리 단조 · sham 구별)는 통과했으므로 배관 결함이 아니라 실질 공유성분.",
  f_ladder = P3$res$f_ladder, sham_control = P3$res$sham,
  mechanism_falsification = list(c_sigma2_beta = P4$sigma2_beta, d_eigen_ordering = P4$eigen_ordering),
  production_candidate = list(
    spec = "score_i(d) = Σ_f w_f(d)·z_fam(f,i,d) / Σ_f |w_f(d)|, w_f = sign(12-1 형성 평균)/sd_expanding, f = 비-모멘텀 계열 13",
    envelope = list(long_only=TRUE, max_names=25L, universe="KOSPI200 ∪ KOSDAQ150",
      period="2005-12(신호) ~ 2026-07(신호)", cost="15bps one-way delta (v2.4_kr_retail_15bps)",
      sum_weights=1, weight_cap="없음(v10)", liquidity="20일 평균 거래대금 >= 2e8 KRW (adv20_t1)"),
    canonical = c5, beta_controlled = b5, diagnostics = d5,
    period_returns_path = "stage_artifacts/WT_R20260829_006/period_returns_production.csv"),
  pit = list(detect_lookahead = P6$detect_lookahead, all_clean = P6$all_clean,
    checklist = list(C1="확장창만 — volm/sgn/FM 기울기 전부 t 이전 데이터. full-sample 통계 없음",
      C5="팩터 수익은 신호월말 형성 → 익월 실현. 오버레이 미적용(S0/S1)",
      C6="유니버스 = 월별 K200/KQ150 멤버십 패널(as-of)",
      C10="유동성 = adv20_t1(당일 미포함) — liq_ruler 실측 라벨 'adv20_t1'",
      C13="Z_Score_Aligned only — NEGATE/FLIP 미사용",
      C14="load_month_factors 내부 Usable_Date <= sig_date 강제",
      C15="Factor DB parquet 직접 load 0회 — 전부 load_month_factors()/load_daily_factors() 경유")),
  alpha_inheritance = P6$alpha_inheritance,
  artifacts = list(
    alpha_package = "qepm/mailbox/worktask/WT-R20260829_006/alpha_package.json",
    alpha_scores = "stage_artifacts/WT_R20260829_006/alpha_scores.parquet",
    period_returns = "stage_artifacts/WT_R20260829_006/period_returns_production.csv",
    engine = "stage_artifacts/WT_R20260829_006/engine/"),
  challenge_flags = CF
)
vj <- file.path(ART, "alpha_validation.json")
write(toJSON(VAL, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null"), paste0(vj,".tmp"))
file.rename(paste0(vj,".tmp"), vj)
cat("[saved]", vj, " bytes", file.info(vj)$size, "\n")

## ── lineage (패키지 write 이후 순서 준수) ─────────────────────────────────────
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id = "WT-R20260829_006", package_type = "alpha_package",
    method_selected = "TS-FMOM 지시 계열가중 사영 (비-모멘텀 계열 13 · EL2022 12-1 형성)",
    input_file_paths = c(".cache/rawdata.parquet", ".cache/factor_db/",
      "02_Infrastructure/factor_db/factor_registry.json",
      "qepm/mailbox/worktask/WT-R20260829_006/alpha_hypothesis.json"))
  TRUE }, error = function(e) { cat("[lineage] 실패:", conditionMessage(e), "\n"); FALSE })
cat("[lineage] ok =", ok, "\n[done] phase7b\n")
