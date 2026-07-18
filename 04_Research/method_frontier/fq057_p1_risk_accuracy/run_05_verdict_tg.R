# =============================================================================
# FQ-057 NP4-P1 run_05: verdict JSON + charts(base R png) + telegram(v7)
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

met  <- fromJSON(file.path(OUT_DIR,"p1_metrics.json"), simplifyDataFrame=FALSE)
P    <- as.data.table(read_parquet(file.path(OUT_DIR,"p1_pairs.parquet")))
DIAG <- as.data.table(read_parquet(file.path(OUT_DIR,"p1_sigma_diag.parquet")))

R <- met$results
cs <- function(k) R[[k]]$common_set
armsum <- function(k) cs(k)$arm_summary
pair <- function(k, nm) cs(k)$paired[[nm]]

# ---- Σ 진단 요약 -------------------------------------------------------------
sig_diag <- DIAG[, .(cond_median=round(median(cond),2), min_ev_median=round(median(min_ev),6),
                     psd_rate=round(mean(psd),4)), by=arm]

# ============================ CHARTS (base R png) =============================
# 1) capw/te 예측 vol(연율) 시계열 + 실현
plot_predvol <- function(pf, tg, file, ttl) {
  s <- P[portfolio==pf & target==tg]
  wide <- dcast(s, holding_ym + realized_var ~ arm, value.var="pred_var")
  wide <- wide[order(holding_ym)]
  ym2d <- function(y) as.Date(paste0(y%/%100,"-",sprintf("%02d",y%%100),"-01"))
  x <- ym2d(wide$holding_ym)
  av <- function(v) sqrt(pmax(v,0))*sqrt(12)
  png(file, width=1100, height=620, res=110)
  par(mar=c(4,4,3,1))
  plot(x, av(wide$realized_var), type="l", lwd=3, col="black",
       ylim=c(0, max(av(wide$realized_var), av(wide$lw_nls), av(wide$lw_linear), av(wide$ewma_direct), na.rm=TRUE)*1.05),
       xlab="holding month", ylab="annualized vol", main=ttl)
  lines(x, av(wide$lw_nls),      lwd=2, col="#1f77b4")
  lines(x, av(wide$lw_linear),   lwd=2, col="#d62728", lty=2)
  lines(x, av(wide$ewma_direct), lwd=2, col="#2ca02c", lty=3)
  legend("topright", c("realized (실현)","lw_nls","lw_linear (현행·퇴화)","ewma_direct"),
         col=c("black","#1f77b4","#d62728","#2ca02c"), lwd=c(3,2,2,2), lty=c(1,1,2,3), bg="white", cex=0.9)
  dev.off()
}
c1 <- file.path(OUT_DIR,"p1_chart_predvol_capw_te.png")
plot_predvol("capw_tilt_top25","te", c1, "TE 예측 vs 실현 변동성 (capw book-form proxy) — lw_nls가 실현 추종")

# 2) QLIKE by arm (te + total, capw)
c2 <- file.path(OUT_DIR,"p1_chart_qlike_bars.png")
qte  <- sapply(c("lw_linear","lw_nls","ewma_struct","ewma_direct"), function(a) armsum("capw_tilt_top25/te")[[a]]$mean_qlike)
qtot <- sapply(c("lw_linear","lw_nls","ewma_struct","ewma_direct"), function(a) armsum("capw_tilt_top25/total")[[a]]$mean_qlike)
png(c2, width=1100, height=560, res=110); par(mar=c(5,4,3,1))
M <- rbind(TE=qte, TOTAL=qtot)
cols <- c("#d62728","#1f77b4","#ff7f0e","#2ca02c")
bp <- barplot(M, beside=TRUE, col=rep(cols, each=1), border=NA,
              names.arg=colnames(M), legend.text=c("TE","TOTAL"),
              args.legend=list(x="topright", bg="white"),
              main="QLIKE 예측손실 by arm (capw, 낮을수록 우월)", ylab="mean QLIKE")
dev.off()

# 3) sweep: te QLIKE 두 포트 x 4 arm (tg_chart_sweep)
source(file.path(ROOT,"02_Infrastructure/telegram/tg_chart_pack.R"))
c3 <- tg_chart_sweep(
  labels=c("capw lw_linear","capw lw_nls","capw ewma_dir","ew lw_linear","ew lw_nls","ew ewma_dir"),
  values=c(armsum("capw_tilt_top25/te")$lw_linear$mean_qlike, armsum("capw_tilt_top25/te")$lw_nls$mean_qlike,
           armsum("capw_tilt_top25/te")$ewma_direct$mean_qlike, armsum("ew_top25/te")$lw_linear$mean_qlike,
           armsum("ew_top25/te")$lw_nls$mean_qlike, armsum("ew_top25/te")$ewma_direct$mean_qlike),
  out_dir=OUT_DIR, title="TE-분산 QLIKE (낮을수록 우월) — lw_nls vs 현행 vs EWMA-direct",
  filename="p1_sweep_qlike_te.png")
charts <- c(c1,c2,c3); charts <- charts[file.exists(charts)]
cat("[charts]", length(charts), "png\n")

# ============================ VERDICT JSON ===================================
verdict <- list(
  id="FQ-057-NP4-P1", lane="method_frontier", round_type="independent_research_round_not_WT",
  agent="risk-research", finalized_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  pin_tag="fq057_20260718_171024",
  preregistration_ref="stage_artifacts/method_frontier/p1_preregistration.json",
  metric_type="risk_forecast_accuracy_diagnostic",
  selection_objective="estimation_quality (QLIKE 예측손실 — R4 P3, SR/IR/alpha 미사용)",
  capital_claim=FALSE, graduation_claim=FALSE, weight_proposal=FALSE,

  hypothesis=paste0("대형-유니버스(p>n, ~300종·60m) rolling Σ 에서 lw_nls 가 linear LW(퇴화) 대비 ",
    "위험 예측 정확도(predicted vs realized 월간 vol/TE-분산)를 유의 개선하며, ⑧행 TE 기준선(EWMA-direct) ",
    "대비 실소비 가치가 있는가. NP4 '위험-축 우위'의 소비면 판정."),

  verdict=paste0("SPLIT — (a) risk_package 대형-유니버스 Σ: ADOPT lw_nls (linear LW 대비 TE-분산 QLIKE ",
    "capw ", pair("capw_tilt_top25/te","a_lwnls_vs_lwlinear")$mean_qlike_diff, " DM-t ",
    pair("capw_tilt_top25/te","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, " / ew DM-t ",
    pair("ew_top25/te","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, ", 총분산은 더 극적 DM-t ",
    pair("capw_tilt_top25/total","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, "/",
    pair("ew_top25/total","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, "). ",
    "(b) monitoring TE 기준선: KEEP EWMA-direct — lw_nls 가 univariate EWMA-direct 를 유의 초과 못함(capw/te DM-t ",
    pair("capw_tilt_top25/te","b_lwnls_vs_ewma_direct")$dm_nw_t_lag3, " tie / ew DM-t ",
    pair("ew_top25/te","b_lwnls_vs_ewma_direct")$dm_nw_t_lag3, " tie). NP4 위험-축 우위는 '퇴화 incumbent 대비' 참이나 '직접 EWMA 대비'는 아님."),

  scored_set=list(common=cs("capw_tilt_top25/te")$holding_range, n_common=cs("capw_tilt_top25/te")$n,
                  structural_fullset_n=R[["capw_tilt_top25/te"]]$structural_fullset$n,
                  ewma_lambda=0.94, note="공통 4-arm 셋은 ewma_direct 12m warmup 바인딩(201101~202606)"),

  sigma_diagnostics=setNames(lapply(seq_len(nrow(sig_diag)), function(i)
    as.list(sig_diag[i])), sig_diag$arm),

  arms=list(
    capw_te=armsum("capw_tilt_top25/te"), ew_te=armsum("ew_top25/te"),
    capw_total=armsum("capw_tilt_top25/total"), ew_total=armsum("ew_top25/total")),

  paired_tests=list(
    capw_te=cs("capw_tilt_top25/te")$paired, ew_te=cs("ew_top25/te")$paired,
    capw_total=cs("capw_tilt_top25/total")$paired, ew_total=cs("ew_top25/total")$paired,
    structural_fullset_te=list(capw=R[["capw_tilt_top25/te"]]$structural_fullset$paired,
                               ew=R[["ew_top25/te"]]$structural_fullset$paired)),

  mechanism_diagnosis=list(
    lw_linear_degeneracy_poisons_all=paste0("incumbent linear LW 는 p>n 에서 ρ-cap→1 로 Σ≈μI (cond 중앙값 1.00, ",
      "상관구조 전멸). 이는 TE 뿐 아니라 25종 총분산 sub-block 까지 대각화 → 총분산 QLIKE 폭발(capw 2.10 / ew 5.71, ",
      "예측 vol 0.149/0.101 vs 실현 0.253/0.230, ~40% 과소예측). '대형 Σ 하나로 total·TE 다 읽는' risk_package 관례에선 ",
      "total 도 오염 — 사전등록 'total 은 arm 수렴' 가설은 이 소비형태에서 부분 반증(FQ-057 incumbent_finding 실증 강화)."),
    lw_nls_best_calibrated=paste0("lw_nls cond 중앙값 98.1·PSD 100%·full-rank. MZ slope b: TE capw 0.937/ew 1.008(~1 완벽 캘리브), ",
      "total 1.487/1.302(고변동월 소폭 과소). 예측 vol 이 실현에 최근접(TE 0.187/0.177 vs 실현 0.187/0.184). ",
      "QLIKE 전 4셀 최저 또는 tie-최저 → NP4 위험-축 우위가 forecast-accuracy 로 확증."),
    ewma_struct_shape_not_level=paste0("RiskMetrics 다변량 EWMA 는 p>n 특이(cond Inf) — 예측 vol 과대(0.28~0.37, ~40% 과대예측)이나 ",
      "vol-clustering 시변을 최고로 추적(MZ r2 TE 0.24·total 0.29 최고). QLIKE 는 과대예측을 과소예측보다 덜 벌하므로 total 에서 ",
      "lw_nls 와 tie(형태는 좋으나 레벨 미스캘리브) — RMSE(vol)로는 lw_nls 가 명확 우월(0.121 vs 0.148)."),
    ewma_direct_competitive_for_single_port_te=paste0("univariate EWMA-direct(포트 자기 실현 TE 의 λ-EWMA)는 구조 Σ 불요인데도 ",
      "capw/te QLIKE 0.297·ew/te 0.244 로 lw_nls(0.244/0.229)와 통계적 tie(DM-t -1.24/-0.54). ",
      "한 포트의 자기 TE 추적엔 직접법이 구조모델을 이기기 어렵다 = monitoring TE 기준선은 EWMA 유지가 합리(단순·⑧행 확정)."),
    risk_axis_only=paste0("NP4 평균-축 NULL 과 정합: Σ 품질은 분산-축 레버. 단 그 위험-축 우위조차 '누가 대상인가'에 조건적 — ",
      "퇴화 incumbent·다변량 EWMA 대비는 유의 우월(risk_package), 단일-포트 직접 EWMA 대비는 tie(monitoring).")),

  consumption_recommendation=list(
    risk_package=list(adopt=TRUE, target="대형-유니버스(p>n) cross-sectional Σ / TE 예측 입력",
      basis=paste0("TE-분산 QLIKE: lw_nls < linear LW, DM-t capw ", pair("capw_tilt_top25/te","a_lwnls_vs_lwlinear")$dm_nw_t_lag3,
        " / ew ", pair("ew_top25/te","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, " (동일방향), 총분산 DM-t ",
        pair("capw_tilt_top25/total","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, "/",
        pair("ew_top25/total","a_lwnls_vs_lwlinear")$dm_nw_t_lag3, " · PSD 100%·cond 98 · MZ b≈1. ",
        "linear LW 는 p>n 에서 μI 퇴화라 대형 Σ 소비 금지(incumbent 가드 재확인) — lw_nls(NP3 등재)가 대체."),
      scope_caveat="p≤25 소-유니버스 Σ 에서는 linear LW 비퇴화·무해(가드 attr 기존). 본 권고는 p>n 대형 Σ 소비자 한정."),
    monitoring=list(adopt=FALSE, keep="EWMA-direct (univariate 실현-TE λ-EWMA, ⑧행 확정 후보 유지)",
      basis=paste0("lw_nls-예측 TE 가 EWMA-direct 를 유의 초과 못함(capw/te DM-t ",
        pair("capw_tilt_top25/te","b_lwnls_vs_ewma_direct")$dm_nw_t_lag3, " · ew/te ",
        pair("ew_top25/te","b_lwnls_vs_ewma_direct")$dm_nw_t_lag3, ", 둘 다 tie). ",
        "단일 포트 자기 TE 추적은 직접법이 이미 충분·더 단순. λ 튜닝은 EWMA 를 더 유리하게만 하므로 KEEP 보수적으로 강건."),
      caveat="ewma_struct(다변량)의 형태-추적 r2 우위는 regime-timed TE 경보엔 잠재 가치 — next_probe.")),

  limitations=list(
    "벤치 = cap-w over elig(유동성·60m-완전 members) — 실 index 아님. 단 예측/실현 동일 벤치·paired DM 는 벤치 선택 불변(arm 상대비교 robust).",
    "실현분산 = 홀딩월 일간 제곱합(월간 Σ 예측과 스케일 정합은 lw_nls MZ b≈0.94~1.01 로 실증). paired 비교는 공통 realized 라 스케일 불변.",
    "capw_tilt_top25 = book FORM proxy(cap-w LinearTilt top-25), 실 production STR_1715 홀딩/스코어 아님 — anachronism·저장패널 look-ahead caveat 회피(의도적).",
    "현 book 보유 active weights(book_state) 고정벡터 short-window 판독은 미실시 — form proxy 로 대체(next_probe).",
    "lw_linear 총분산 오염은 '대형 Σ 하나 소비' 전제 하 — 25-only Σ 별도 추정 시 비퇴화(본 라운드 scope=대형 Σ, FQ-057 incumbent_finding 정합).",
    "ewma λ=0.94 사전고정(RiskMetrics canonical); 0.97 은 KEEP 방향 강화라 미보고(보수적).",
    "MVP/포트는 진단 instrument(FQ-057 관례) — allocation 제안 아님(role boundary)."),

  next_probes=list(
    list(id="P1a", title="tier-factor Σ (NP2) vs lw_nls TE-forecast A/B",
      detail="risk_research_init base frame Σ=BΩB'+D (market+tier+size factors, PSD by construction)를 동일 QLIKE 하네스로 lw_nls 와 비교 — 구조 Σ 가 lw_nls 를 넘는지(FQ-057 NP2 sanctioned path)."),
    list(id="P1b", title="regime-conditional TE: ewma_struct/GARCH 형태-추적을 monitoring 경보에",
      detail="ewma_struct MZ r2(TE 0.24) 우위는 vol-clustering 추적 — CRISIS 진입 TE 급증 조기경보에 잠재. lw_nls(레벨) + ewma_struct(형태) 결합 예측이 QLIKE 개선하는지 실측."),
    list(id="P1c", title="현 book 고정 active vector predicted-vs-realized short-window",
      detail="book_state 현 홀딩 active 벡터를 최근 60m 고정 판독 — form proxy 결론(ADOPT/KEEP)이 실 book 구성에서도 유지되는지 확인(small-n honest caveat)."),
    list(id="P1d", title="risk_package 배선: .get_cor_cov('lw_nls') 대형-유니버스 소비 경로 + cap_tier_decomposition 동시산출",
      detail="ADOPT 결정 실배선 — WT-시점 risk_package 가 p>n 유니버스 Σ 에서 lw_nls 를 기본 소비하고 predicted TE 를 emit, EWMA-direct 를 monitoring 대조로 병기.")),

  revival_or_followup_conditions=list(
    "monitoring lw_nls-TE 채택 재검토: tier-factor/GARCH 결합이 EWMA-direct 를 QLIKE 유의 초과(DM-t≤-2) 시(P1b).",
    "risk_package lw_nls 소비는 WT-시점 posterior-driven Σ 이원화(§v83) 하에서 대형-유니버스 경로에 한해 default — NP3 등재 유지가 전제.",
    "engine: turnover_penalty 미배선(NP4 task_89b2050e)·HHI max_names 누출(task_1b9e50a3) 수리는 optimizer lane 소관(위험 예측 판정과 무관)."),

  self_adversarial=list(
    accept=list("form proxy ≠ production book 명시(P1c 로 보완)", "현 book 고정벡터 판독 미실시 인정"),
    partial=list("벤치 risk-universe 제한(paired 불변으로 verdict robust)", "total 오염은 대형-Σ-소비 전제(scope 명시)"),
    rebuttal=list("스케일 정합 = lw_nls MZ b≈1 실증", "λ=0.94 고정은 KEEP 방향 보수 강화", "QLIKE=Patton 2011 표준 robust loss·TE-레벨 경보에 decision-appropriate")),

  artifacts=list(
    runner_dir="04_Research/method_frontier/fq057_p1_risk_accuracy/",
    preregistration="stage_artifacts/method_frontier/p1_preregistration.json",
    pairs="stage_artifacts/method_frontier/p1_pairs.parquet",
    sigma_diag="stage_artifacts/method_frontier/p1_sigma_diag.parquet",
    metrics="stage_artifacts/method_frontier/p1_metrics.json",
    daily="stage_artifacts/method_frontier/p1_daily_returns.parquet",
    challenge_note="stage_artifacts/method_frontier/p1_challenge_note.md",
    charts=charts))

write_json(verdict, file.path(OUT_DIR,"p1_verdict.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[verdict] written\n")

# ============================ TELEGRAM (v7) ==================================
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
p_a_capw <- pair("capw_tilt_top25/te","a_lwnls_vs_lwlinear")
p_a_ew   <- pair("ew_top25/te","a_lwnls_vs_lwlinear")
p_b_capw <- pair("capw_tilt_top25/te","b_lwnls_vs_ewma_direct")
p_a_tot  <- pair("capw_tilt_top25/total","a_lwnls_vs_lwlinear")
as_capw_te <- armsum("capw_tilt_top25/te")

sections <- list(
  list(type="bullet", emoji="\U0001F4DA", heading="연구 컨텍스트",
    items=c(
      "목적: NP4가 밝힌 'lw_nls 우위=위험-축'을 소비 가능한 형태로 판정",
      "설계: 대형 유니버스(종목>표본) 롤링 공분산의 위험 예측 정확도 짝 비교",
      "3부품: 현행(퇴화) / lw_nls(신규 등재) / 지수가중 + 직접 지수가중 기준선",
      "판정: 예측손실(QLIKE) + 짝 Diebold-Mariano 검정 (측정 전 사전등록)")),
  list(type="bullet", emoji="\U0001F4D6", heading="쉬운 설명",
    items=c(
      "질문: 위험(출렁임)을 더 잘 '예측'하는 공분산 부품이 실제로 더 정확한가",
      "발견1: 현행 부품은 종목이 많아지면 상관관계를 통째로 잃어 위험을 크게 과소예측",
      "발견2: 새 부품 lw_nls는 실현 위험을 정확히 맞힘 → 위험모델용 채택 권고",
      "발견3: 단 한 포트 추적오차만 감시할 땐 단순 지수가중으로 충분 → 기준선 유지")),
  list(type="bullet", emoji="\U0001F52C", heading="실측 수치 (핵심)",
    items=c(
      sprintf("(a) 추적오차 예측손실: lw_nls %.3f vs 현행 %.3f, 검정t %.2f/%.2f → 채택",
        as_capw_te$lw_nls$mean_qlike, as_capw_te$lw_linear$mean_qlike, p_a_capw$dm_nw_t_lag3, p_a_ew$dm_nw_t_lag3),
      sprintf("총분산은 현행 폭발: 손실 2.10/5.71 vs lw_nls 0.41/0.48 (검정t %.1f)", p_a_tot$dm_nw_t_lag3),
      "조건수: 현행 1.00(대각 퇴화) / lw_nls 98(양정치 100%) / 지수가중 무한(특이)",
      sprintf("(b) lw_nls vs 직접 지수가중 검정t %.2f = 무승부 → 기준선 유지", p_b_capw$dm_nw_t_lag3))),
  list(type="bullet", emoji="\U0001F9E0", heading="기전 진단",
    items=c(
      "현행 퇴화가 추적오차뿐 아니라 25종 총분산까지 오염 — 대형 공분산 단일소비 취약점",
      "lw_nls는 보정계수 약 1·실현 변동성 최근접 = 위험-축 우위가 예측정확도로 확증",
      "직접 지수가중은 구조모델 없이도 단일-포트 추적엔 무승부 — 직접법이 이기기 어려움",
      "NP4 평균-축 무효와 정합: 공분산 품질은 위험-축 레버, 단 우위조차 대상에 조건적")),
  list(type="bullet", emoji="\U0001F6A9", heading="판정 + 다음 단계",
    items=c(
      "판정 분리: (가) 위험모델 대형 공분산 = lw_nls 채택",
      "(나) 감시 추적오차 기준선 = 직접 지수가중 유지 (단순·확정)",
      "병목 8행 추적오차 기준선 유지 확정 · 5행 lw_nls 위험-축 소비면 실측 완료",
      "다음 프로브: 계층-요인 공분산 대조 · 국면 형태추적 · 위험모델 배선",
      "자본/비중 주장 없음 (위험 예측정확도 진단)")))

r <- tg_agent_brief(agent="Risk",
  title="FQ-057 P1 — 위험예측 정확도 A/B (SPLIT: risk_package ADOPT lw_nls / monitoring KEEP EWMA)",
  sections=sections, charts=charts)
cat("[telegram] sent:", !is.null(r), "\n")
cat("[done] run_05 complete\n")
