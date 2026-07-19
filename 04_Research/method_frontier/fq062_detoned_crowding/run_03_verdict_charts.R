# =============================================================================
# FQ-062 run_03 — final verdict (mechanism-aware) + charts + challenge note
#
# 종합 3사실:
#  (1) RMT .rmt_denoise = p>n(q<1) 201/201 windows NO-OP → "RMT flattens" 전제 FALSE.
#  (2) 공분산 축(lw_nls 고유벡터 정확 보존 = 가설의 실제 claim): detoned 잔차 concentration
#      sample과 near-identical (PC1-AR pearson 1.000; 잔차 mfix 0.958) → 기전 반증.
#  (3) 상관 축: 발산(mfix pearson 0.53, 대각통제 후 0.64) — cov2cor-of-shrinkage 효과,
#      가설 기전(잔차 dispersion 보존) 아님·정보성 미입증·lw_nls 특이성 아님.
# → VERDICT = KILL_lw_nls_incidental (lw_nls-특이 가설 반증). 상관-발산은 별개 후보로
#   리다이렉트(목적-빌드 잔차-상관 denoiser, AR 대비 incremental-info 테스트) = followup.
#
# metric_type = spectral_diagnostic. 자본/성과/SR/weight 주장 ZERO.
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR   <- file.path(ROOT, "stage_artifacts/method_frontier/fq062")
STAGE_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
CHART_DIR <- file.path(OUT_DIR, "charts"); dir.create(CHART_DIR, recursive=TRUE, showWarnings=FALSE)

st  <- fromJSON(file.path(OUT_DIR,"fq062_divergence_stats.json"), simplifyVector=FALSE)
dc  <- fromJSON(file.path(OUT_DIR,"fq062_diag_control.json"), simplifyVector=FALSE)
DT  <- as.data.table(read_parquet(file.path(STAGE_DIR,"fq062_divergence.parquet")))
pin_tag <- st$pin_tag

gv <- function(basis,metric,pairname,field) st$divergence[[basis]][[metric]][[pairname]][[field]]

# ---- charts -----------------------------------------------------------------
ym_date <- as.Date(paste0(substr(DT$ym,1,4),"-",substr(DT$ym,5,6),"-01"))

png_line3 <- function(file, y1, y2, y3, labs, cols, title, ylab) {
  png(file, width=1100, height=620, res=130)
  par(mar=c(4,4.5,3.2,1))
  yr <- range(c(y1,y2,y3), na.rm=TRUE)
  plot(ym_date, y1, type="l", lwd=2, col=cols[1], ylim=yr, xlab="", ylab=ylab, main=title)
  if(!is.null(y2)) lines(ym_date, y2, lwd=2, col=cols[2], lty=1)
  if(!is.null(y3)) lines(ym_date, y3, lwd=1.6, col=cols[3], lty=2)
  grid(col="grey85"); legend("topright", legend=labs, col=cols[seq_along(labs)],
        lwd=2, lty=c(1,1,2)[seq_along(labs)], bg="white", cex=0.85)
  dev.off(); file
}

# Chart 1: COVARIANCE basis residual concentration (sample vs lw_nls) — near-identical
c1 <- png_line3(file.path(CHART_DIR,"fq062_cov_mfix.png"),
  DT$cov_mfix_sample, DT$cov_mfix_lwnls, NULL,
  c("sample cov","lw_nls cov"), c("#1f4e79","#c00000"),
  sprintf("공분산 detoned 잔차 concentration (mfix) — near-identical  [pearson %.3f]",
          gv("covariance","mfix","lwnls_vs_sample","pearson")),
  "PC2-10 / 공유 informative 잔차")

# Chart 2: PC1 Absorption Ratio (covariance) sample vs lw_nls — identical
c2 <- png_line3(file.path(CHART_DIR,"fq062_cov_ar_pc1.png"),
  DT$cov_ar_pc1_sample, DT$cov_ar_pc1_lwnls, NULL,
  c("sample cov","lw_nls cov"), c("#1f4e79","#c00000"),
  sprintf("공분산 PC1 흡수율 (고전 Absorption Ratio) — 완전 동일  [pearson %.3f]",
          gv("covariance","ar_pc1","lwnls_vs_sample","pearson")),
  "λ1 / Σλ (시장모드 흡수율)")

# Chart 3: CORRELATION basis mfix (sample vs lw_nls) — divergent (confounded)
c3 <- png_line3(file.path(CHART_DIR,"fq062_cor_mfix.png"),
  DT$cor_mfix_sample, DT$cor_mfix_lwnls, NULL,
  c("sample cor","lw_nls cor"), c("#1f4e79","#c00000"),
  sprintf("상관 detoned 잔차 concentration — 발산(cov2cor confound)  [pearson %.3f]",
          gv("correlation","mfix","lwnls_vs_sample","pearson")),
  "PC2-10 / 공유 informative 잔차")

# Chart 4: divergence summary bar (pearson by metric x basis)
c4 <- {
  cor_m <- c("ar_pc1","mfix","mfull","neff","top")
  cov_m <- c("ar_pc1","mfix","neff")
  cor_p <- sapply(cor_m, function(m) gv("correlation",m,"lwnls_vs_sample","pearson"))
  cov_p <- sapply(cov_m, function(m) gv("covariance",m,"lwnls_vs_sample","pearson"))
  png(file.path(CHART_DIR,"fq062_divergence_bar.png"), width=1100, height=620, res=130)
  par(mar=c(6.5,4.5,3.2,1))
  vals <- c(cov_p, NA, cor_p)
  nms  <- c(paste0("cov:",cov_m), "", paste0("cor:",cor_m))
  cols <- c(rep("#c00000",length(cov_p)), NA, rep("#1f4e79",length(cor_p)))
  bp <- barplot(vals, names.arg=nms, las=2, col=cols, ylim=c(0,1.05),
    main="lw_nls ~ sample 시계열 pearson (공분산=빨강 near-identical / 상관=파랑 발산)",
    ylab="pearson (detoned 잔차 지표 시계열)", cex.names=0.8)
  abline(h=0.95, col="grey40", lty=2); text(x=max(bp), y=0.965, "0.95", pos=2, cex=0.8, col="grey30")
  dev.off(); file.path(CHART_DIR,"fq062_divergence_bar.png")
}
charts <- c(c1,c2,c3,c4)
cat("[charts]", length(charts), "written\n")

# ---- final verdict.json (mechanism-aware) -----------------------------------
verdict <- "KILL_lw_nls_incidental"
estimator_divergence <- list(
  basis_note = "correlation = monitoring-standard object; covariance = lw_nls eigenvector-EXACT (faithful test of 'residual dispersion preservation' claim)",
  rmt_status = list(rmt_noop_all_windows = st$rmt_noop_all, n_windows = st$n_windows,
    note = ".rmt_denoise returns sample unchanged for q_ratio<1 (p>n) -> RMT-detone == sample-detone; 'RMT flattens residual' premise FALSE in mandated universe-scale regime"),
  covariance_lwnls_vs_sample = list(
    pc1_absorption   = list(pearson=gv("covariance","ar_pc1","lwnls_vs_sample","pearson"),
                            spearman=gv("covariance","ar_pc1","lwnls_vs_sample","spearman"),
                            sign_agree=gv("covariance","ar_pc1","lwnls_vs_sample","sign_agree"),
                            event_jaccard_z2=gv("covariance","ar_pc1","lwnls_vs_sample","event_jaccard_z2")),
    resid_mfix       = list(pearson=gv("covariance","mfix","lwnls_vs_sample","pearson"),
                            spearman=gv("covariance","mfix","lwnls_vs_sample","spearman"),
                            sign_agree=gv("covariance","mfix","lwnls_vs_sample","sign_agree"),
                            event_jaccard_z2=gv("covariance","mfix","lwnls_vs_sample","event_jaccard_z2")),
    resid_neff       = list(pearson=gv("covariance","neff","lwnls_vs_sample","pearson"),
                            spearman=gv("covariance","neff","lwnls_vs_sample","spearman"))),
  correlation_lwnls_vs_sample = list(
    pc1_absorption   = list(pearson=gv("correlation","ar_pc1","lwnls_vs_sample","pearson"),
                            spearman=gv("correlation","ar_pc1","lwnls_vs_sample","spearman"),
                            event_jaccard_z2=gv("correlation","ar_pc1","lwnls_vs_sample","event_jaccard_z2")),
    resid_mfix       = list(pearson=gv("correlation","mfix","lwnls_vs_sample","pearson"),
                            spearman=gv("correlation","mfix","lwnls_vs_sample","spearman"),
                            sign_agree=gv("correlation","mfix","lwnls_vs_sample","sign_agree"),
                            event_jaccard_z2=gv("correlation","mfix","lwnls_vs_sample","event_jaccard_z2")),
    resid_mfull      = list(pearson=gv("correlation","mfull","lwnls_vs_sample","pearson"),
                            level_ratio_median=gv("correlation","mfull","lwnls_vs_sample","level_ratio_median"))),
  sample_vs_rmt_correlation = list(pc1_pearson=gv("correlation","ar_pc1","sample_vs_rmt","pearson"),
    note="== 1.0 by construction (RMT no-op)"),
  diagonal_control_probe = list(
    cor_mfix_lwnls_vs_sample = list(pearson=dc$lwnls_vs_sample$pearson, spearman=dc$lwnls_vs_sample$spearman),
    cor_mfix_ctrl_vs_sample  = list(pearson=dc$ctrl_vs_sample$pearson, spearman=dc$ctrl_vs_sample$spearman),
    interpretation="sample-vol rescale only recovers 0.53->0.64: correlation divergence is a cov2cor-of-shrinkage effect (eigenvector rotation from heterogeneous variance shrink), only partly diagonal-driven; NOT the hypothesized residual co-movement preservation")
)

out <- list(
  fq = "FQ-062",
  hypothesis = "lw_nls의 잔차 고유값 dispersion 보존이 RMT-detone(.rmt_denoise)·sample과 실제로 다른 detoned 잔차-crowding 시계열을 낳는가 (falsification-first: near-identical이면 lw_nls incidental→KILL)",
  metric_type = "spectral_diagnostic",
  pin_tag = pin_tag,
  window_rule = st$window_rule,
  universe = "K200∪KQ150 PIT index members with complete 60m; monthly 60m rolling; p 180-318, n=60 (p>n all windows)",
  n_windows = st$n_windows,
  estimator_divergence = estimator_divergence,
  verdict = verdict,
  mechanism_diagnosis = paste(
    "lw_nls를 detoned 잔차-crowding의 '유일 unlock'으로 지목한 두 기둥이 모두 무너짐. ",
    "(1) 전제 'RMT가 잔차를 flatten': mandated 유니버스-규모 p>n(q_ratio 0.19-0.33)에서 .rmt_denoise는 201/201 윈도 no-op — flatten할 baseline 자체가 없음. RMT-detone ≡ sample-detone. ",
    "(2) 기전 '잔차 dispersion 보존이 다른 시계열': lw_nls가 고유벡터를 정확 보존하는 공분산 축(가설의 실제 claim 축)에서 detoned 잔차 concentration은 sample과 near-identical — PC1 흡수율(고전 Absorption Ratio) pearson 1.000·완전 동일, 잔차 mfix pearson 0.958. 비선형 수축은 detoned 잔차 concentration 시계열을 실질적으로 재편하지 못함. ",
    "(3) 상관 축의 발산(mfix pearson 0.53, 대각통제 후 0.64)은 cov2cor-of-shrinkage(이질적 분산수축이 잔차 부분공간을 회전)의 산물 — 가설이 주장한 'dispersion 보존' 기전이 아니며, 어떤 공분산 수축 추정기든 cov2cor에서 sample과 갈리므로 lw_nls 특이성도 아니고, 정보성(비-중복 monitoring 신호)은 미입증. ",
    "∴ lw_nls는 detoned 잔차-crowding 신호에 incidental. 순 가치로 제시된 '⑧risk/monitoring 소비면 1건'은 lw_nls 특이 능력으로 성립하지 않음.",
    sep=""),
  limitations = list(
    "판정은 basis-split(공분산 near-identical vs 상관 발산)을 기전으로 해소한 JUDGMENT — 리터럴하게 상관 mfix 0.53<0.95만 보면 자동 규칙상 DIVERGENT로 읽힐 수 있음(투명 병기). 반증 우선 규율상 가설의 실제 claim 축(공분산)과 전제(RMT flatten)의 붕괴를 결정적으로 봄.",
    "월간 60m·p>n 단일 측정틀. 일간 63d 롤링(더 조밀한 monitoring cadence)에서 재현 미검(값싼 후속 가능하나 estimator 대수는 동일 — 결론 이식 예상).",
    "z>2 이벤트 자카드는 201개월서 이벤트 3-14개로 검정력 부족(단일 값 취약) — pearson/spearman 주력, jaccard는 보조.",
    "상관-발산의 '정보성 없음'은 본 라운드서 미증명(different≠uninformative). 단 lw_nls 특이 기전이 아님은 확립 — 정보성 입증은 별개 목적-빌드 후보의 몫.",
    "AR 베이스라인(regime_absorption_ratio.R)이 main 미병합(병렬 세션 in-flight)이라 PC1-AR 대비 incremental-info 실증(다음 단계)은 본 라운드 범위 밖 — falsification-first는 여기까지."
  ),
  next_probes = list(
    "P1 (followup, lw_nls 아님): detoned 잔차-CORRELATION co-crowding monitor가 필요하면 목적-빌드 잔차-상관 denoiser(상관 객체 직접 p>n eigenvalue-clip 또는 상관 shrinkage)로 구성하고, 고전 Absorption Ratio(PC1) z-score 대비 INCREMENTAL 이벤트 실증으로 자격 판정. lw_nls는 이 역할의 특권 없음.",
    "P2: 일간 63d 롤링(monitoring cadence)로 본 3-estimator 발산 재현 — 결론 이식 여부 값싸게 확인(월간과 estimator 대수 동일하여 KILL 이식 예상).",
    "P3 (별개 lane): crowding 신규 차원이 목표면, 비-holdings·비-co-movement 축(신용/대차 crowding = FQ-005, passive overlap) 실측이 crowding_score_per_factor 갭(co-movement 차원 전무)을 더 직접 메움."
  ),
  revival_or_followup_conditions = list(
    lw_nls_revival = "원칙적 없음(lw_nls 특이 기전 반증). 예외 = lw_nls 잔차 dispersion 보존이 실질 차이를 낳는 '새 측정틀'(예: tail-conditional 잔차 스펙트럼 — 정상국면 아닌 극단국면 조건부) 등장 시에만 재검토. 자본 승격은 위험-축 진단이라 원칙적 불가(INV-7 성과 방화벽).",
    followup_owner = "P1/P3는 crowding lane(FQ-005) 또는 monitoring 개선 라운드로 등재 — lw_nls 부활 아님"
  ),
  honesty_note = "본 라운드는 위험-축(공동위험 구조) 진단. SR/자본 전이 ZERO(설계상). 어떤 발산이 유의해도 성과/자본으로 포장 금지 — mechanism_diagnosis는 lw_nls의 detoned 잔차-crowding 특이능력 부재만 확립.",
  charts = as.list(charts),
  source_runners = list(
    "04_Research/method_frontier/fq062_detoned_crowding/run_01_pin_panel.R",
    "04_Research/method_frontier/fq062_detoned_crowding/run_02_divergence.R",
    "04_Research/method_frontier/fq062_detoned_crowding/run_02b_diag_control.R",
    "04_Research/method_frontier/fq062_detoned_crowding/run_03_verdict_charts.R")
)
write_json(out, file.path(STAGE_DIR,"fq062_verdict.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
cat("[verdict] KILL_lw_nls_incidental written to stage_artifacts/method_frontier/fq062_verdict.json\n")
cat("[charts]\n"); cat(paste(charts, collapse="\n"), "\n")
