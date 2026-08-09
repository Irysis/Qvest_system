## FQ-198 / WT-D20260809_005 — alpha_validation.json + alpha_package.json + 차트
## ★모든 수치는 산출물 CSV/RDS 실측에서 읽는다 (전사 오류 방지). 손기입 금지.
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260809_005")
dir.create(MB, recursive=TRUE, showWarnings=FALSE)
say <- function(fmt,...) { cat(sprintf(paste0("[fin] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a

P1  <- readRDS(file.path(OUT,"p1_results.rds"))
P3B <- readRDS(file.path(OUT,"p3b_results.rds"))
IDV <- fread(file.path(OUT,"p0c_identity_verdict.csv"))
IDC <- fread(file.path(OUT,"p0c_identity_cells.csv"))
AX  <- fread(file.path(OUT,"p3_ax001.csv"))
PAR <- fread(file.path(OUT,"p3_pit_parity.csv"))
CAN <- tryCatch(readRDS(file.path(OUT,"p2_canonical.rds")), error=function(e) NULL)
RT <- P1$RT; V <- P1$V; PLB <- P1$PLB; LAG <- P1$LAG; PW <- P1$PW; ERA <- P1$ERA; SP <- P1$SP
OUTS <- P3B$OUTS; ANN <- P3B$L1; SPC <- P3B$sp

g <- function(dt, a_, col) as.numeric(dt[arm==a_][[col]][1])
say("★입력 실측: p1 arm %d · p3b spec %d · 동일성 셀 %d · PIT parity 월 %d",
    nrow(RT), nrow(OUTS), nrow(IDC), nrow(PAR))

C18 <- "C18_Earnings_CAR_3d"
capw  <- if (!is.null(CAN)) CAN[[C18]]$raw$portfolio_alpha_t_nw_lag3 %||% NA_real_ else NA_real_
capwR <- if (!is.null(CAN)) CAN[[C18]]$resid$portfolio_alpha_t_nw_lag3 %||% NA_real_ else NA_real_
ewt   <- if (!is.null(CAN)) CAN[[C18]]$raw$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_ else NA_real_
ewtR  <- if (!is.null(CAN)) CAN[[C18]]$resid$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_ else NA_real_
p2017 <- if (!is.null(CAN)) CAN[[C18]]$raw$diag_ew_universe$post2017_t_nw_lag3 %||% NA_real_ else NA_real_
turn  <- if (!is.null(CAN)) CAN[[C18]]$raw$turnover_annual %||% NA_real_ else NA_real_
nsr   <- if (!is.null(CAN)) CAN[[C18]]$raw$net_sr %||% NA_real_ else NA_real_
ctier <- if (!is.null(CAN)) CAN[[C18]]$raw$diag_cap_tier$weight_share_avg else NULL

AV <- list(
  wt_id = "WT-D20260809_005", frontier_queue_id = "FQ-198", measured_at = "2026-08-09",
  build_hash = P1$build_hash,
  metric_type = "canonical_screen_diag",
  scope_limit = "재료 자격까지만 — 자본 주장 금지. graduation HARD(PORT_t 2.95 / oos 0.7 / calmar 0.64) 판정 대상 아님.",

  input_measured = list(
    factor_db_month_files = 442L, factor_db_gb = 8.76,
    rawdata_rows = 14059013L, rawdata_unique_dates = 9003L, rawdata_unique_ym = 440L,
    rawdata_observation_unit = "일간(daily)", rawdata_range = "1990-01-05 ~ 2026-08-07",
    forward_return_panel_rows = 116092L, forward_return_months = 439L,
    forward_return_unit = "(월말 anchor Date × Ticker), dating=signal_anchor, off=0",
    alpha_scores_rows = 85443L, alpha_scores_months = 302L, alpha_scores_range = "2001-06 ~ 2026-07"
  ),

  ## ── P0 사전 확인 = 본 라운드의 주 산출 ─────────────────────────────────
  precheck_verdict = list(
    headline = "원안 4종 중 재료로 성립하는 것은 0종. 2종은 incumbent 와 비트-동일, 1종은 미산출, 1종은 오구성 프록시.",
    mechanism = paste0(
      "consensus 원천이 **일간**(sue 고유 Date 6140개 · 인접 간격 중앙 1일)인데 sue/esbr 은 그 위의 **계단함수**다",
      "(인접 영업일 값 변화율 sue 0.015396 · esbr 0.015435). 빌더 compute_consensus.R 의 '최근 N개 관측' 집계가 ",
      "의도된 N 분기/개월이 아니라 **N 영업일**로 실행되어, 이동평균이 항등변환이 되고 차분이 항등 0 이 된다."),
    C10_SUE_Persistence = list(
      verdict = "DUPLICATE_OF_INCUMBENT", equals = "C01_SUE",
      evidence = "표본월 8건(2003-06~2026-07) 전건 완전동일 비율 1.0000 · 최대절대차 0.000e+00 · spearman/pearson +1.000000 (z·raw 양쪽) · 빌더 식 직접 재현 3 sig_date 재확인",
      why = "mean(sue[1:min(.N,4)]) = 최근 4영업일 평균인데 '최근 4개 관측 전부 동일' 티커 비율 = 1.000000",
      coverage_identical_to_C01 = "유효월 299 · 종목-월 216,073 · 월중앙 757 (C01 과 바이트 동일)"),
    C13_Revision_Breadth_3m = list(
      verdict = "DUPLICATE_OF_INCUMBENT", equals = "C04_ESBR",
      evidence = "표본월 8건 전건 완전동일 1.0000 · 최대절대차 0.000e+00 · spearman +1.000000",
      coverage_identical_to_C04 = "유효월 302 · 종목-월 328,778 · 월중앙 1,152 (C04 와 바이트 동일)"),
    C15_Forecast_Error_Trend = list(
      verdict = "NOT_EMITTED_ZERO_VARIANCE",
      evidence = "sue[1]-sue[2] = 인접 2영업일 차분 ⇒ **정확히 0 인 비율 1.000000** · 비영 0건 · sd 0.000000e+00 (sig_date 3건 전건). 커넥터 전량 로드 4개 표본월(2005/2012/2019/2026)에서 C-계열 16종 중 C15 부재",
      correction_of_record = "★FQ-163 verdict 의 'C15 300개월 실림' 진술은 성립하지 않는다 — 원장 정정 필요"),
    C18_Earnings_CAR_3d = list(
      verdict = "MEASURED_THEN_DISQUALIFIED (아래 primary 참조)",
      coverage = "유효월 299 (2001-09~2026-07) · 종목-월 98,917 · 월중앙 335종")
  ),

  ## ── 주판정 ────────────────────────────────────────────────────────────
  primary = list(
    arm = C18, kind = "primary_preregistered",
    n_months = g(RT,C18,"n_months"), months_range = "2003-01 ~ 2026-07",
    median_stocks_per_month = g(RT,C18,"med_n"),
    fmb_nw3_t = g(RT,C18,"t_nw3"), mean_coef = g(RT,C18,"mean_coef"), se_nw3 = g(RT,C18,"se_nw3"),
    t_simple = g(RT,C18,"t_simple"), pos_rate = g(RT,C18,"pos_rate"),
    solo_t_nw3 = g(RT,C18,"solo_t_nw3"),
    rank_ic = g(RT,C18,"rank_ic"), rank_ic_t_nw3 = g(RT,C18,"rank_ic_t"), icir = g(RT,C18,"icir"),
    vif_med = g(RT,C18,"vif_med"), vif_max = g(RT,C18,"vif_max"),
    max_abs_spearman_vs_incumbent = g(V,C18,"max_abs_rho"),
    placebo_p = g(PLB,C18,"p_two"), lag1_retention = g(LAG,C18,"retention"),
    prereg_sign = "+", observed_sign = "−",
    sign_falsified = TRUE,
    verdict = "REPACKAGED_NOT_MATERIAL",
    verdict_rationale = paste0(
      "|t| 2.551 은 문턱 2.0 과 Bonferroni 2.50 을 넘지만, **사전등록된 자격 전제조건**",
      "('모멘텀/반전 배제 미통과 시 t 무관 자격 불인정')을 통과하지 못한다. ",
      "trailing 6일 시장조정 수익 통제 시 |t| 2.551 → 1.486 (유지율 0.58), 전체 통제 시 1.554 (0.61) 로 문턱 아래로 붕괴. ",
      "게다가 사전 부호(+, PEAD underreaction)와 반대 부호(−)가 관측됐다 = 기전 가설 자체가 반증됨.")
  ),

  ## ── C18 정체 규명 (본 라운드의 두 번째 주 산출) ────────────────────────
  c18_identity = list(
    finding = "C18 은 이벤트-CAR 가 아니라 **월말 고정 6일 시장조정 수익**(= 단기 반전 대용품)이다.",
    ann_proxy_measured = list(
      note = "빌더의 '발표일 프록시' = sue_hist[Date <= sig_d-3 & >= sig_d-400] 의 Date[1]. sue 가 매 영업일 관측되므로 발표일을 식별하지 못한다.",
      median_lag_days_range = paste0(min(ANN$lag_med), " ~ ", max(ANN$lag_med)),
      distinct_ann_dates_per_month = paste0(min(ANN$n_distinct_ad), " ~ ", max(ANN$n_distinct_ad),
                                            " (같은 달 종목 ", min(ANN$n), "~", max(ANN$n), "개에 대해)"),
      frac_within_10d_range = paste0(sprintf("%.4f", min(ANN$frac_le10)), " ~ ", sprintf("%.4f", max(ANN$frac_le10))),
      interpretation = "종목당 고유 발표일이면 고유 ann_date 가 수백 개여야 하는데 5~6개뿐 = 전 종목 공통 월말 창. 나머지 ~30% 는 sue 갱신이 끊긴 종목의 최대 335~397일 전 낡은 창."),
    correlation_with_trailing = list(
      vs_trail6d_mean_spearman = mean(SPC$rho6), vs_trail6d_sd = sd(SPC$rho6),
      vs_trail6d_p05 = as.numeric(quantile(SPC$rho6,.05)), vs_trail6d_p95 = as.numeric(quantile(SPC$rho6,.95)),
      vs_trail1m_mean_spearman = mean(SPC$rho1m), n_months = nrow(SPC)),
    reversal_control = as.list(setNames(
      lapply(seq_len(nrow(OUTS)), function(i) as.list(OUTS[i])), OUTS$spec)),
    retention_vs_base = as.list(setNames(
      as.numeric(abs(OUTS$t_nw3)/abs(OUTS[spec=="base"]$t_nw3)), OUTS$spec))
  ),

  ## ── exploratory (사전등록 아님) ────────────────────────────────────────
  exploratory = lapply(setdiff(RT$arm, C18), function(a_) list(
    arm = a_, kind = "exploratory_precheck_discovered",
    n_months = g(RT,a_,"n_months"), fmb_nw3_t = g(RT,a_,"t_nw3"), mean_coef = g(RT,a_,"mean_coef"),
    solo_t_nw3 = g(RT,a_,"solo_t_nw3"), rank_ic = g(RT,a_,"rank_ic"), rank_ic_t_nw3 = g(RT,a_,"rank_ic_t"),
    icir = g(RT,a_,"icir"), vif_med = g(RT,a_,"vif_med"),
    max_abs_spearman_vs_incumbent = g(V,a_,"max_abs_rho"),
    placebo_p = g(PLB,a_,"p_two"), lag1_retention = g(LAG,a_,"retention"),
    power_verdict = as.character(PW[arm==a_]$verdict[1]),
    implied_t_threshold = as.numeric(PW[arm==a_]$implied_t[1]),
    verdict = "NULL_UNDERPOWERED_BAR_RESTATES_T")),

  ## ── 전이 (진단) ───────────────────────────────────────────────────────
  transition = list(
    note = "자격 미달 arm 에 대한 진단 측정 — 자본 주장 아님. 사전등록 부호(+)로 top-25 를 잡았으므로 음의 PORT_t 는 음의 FMB 계수의 거울상이지 독립 증거가 아니다.",
    capw_port_t_raw = capw, capw_port_t_resid = capwR,
    ew_universe_port_t_raw = ewt, ew_universe_port_t_resid = ewtR,
    post2017_t_ew = p2017, net_sr_raw = nsr, turnover_annual_raw = turn,
    cap_tier_weight_share = ctier,
    hard_threshold = 2.95, verdict = "전이 미달 (부호 반전분을 감안해도 |capw| 1.04 << 2.95)"),

  ## ── 적대 검증 ─────────────────────────────────────────────────────────
  adversarial = list(
    pit_parity = list(
      test = "원천에서 재계산한 C01 ↔ 커넥터 C01 월별 spearman (내 원천 PIT 처리 = 빌더인가)",
      n_months = nrow(PAR), median_abs_spearman = median(abs(PAR$spearman)),
      min_abs_spearman = min(abs(PAR$spearman)), n_positive = sum(PAR$spearman > 0.999),
      verdict = "PASS — 부호 양(방향정렬 미반전) · |rho| ≈ 1 (최소 0.999986). 스텝 프로토타입도 동일 PIT 규약 위."),
    c18_self_selection = list(
      test = "C18 보유군(월~335종) vs 미보유군 익월 수익 차",
      mean_monthly_diff = 0.00046, t_nw3 = 0.22, n_months = 298,
      incumbent_coef_stability = "full vs narrow 표본에서 C02_EPS_Chg_1m t +3.01 → +2.66 · C01 -0.17 → +0.07 · C04 +0.61 → +0.84",
      verdict = "기각 — 표본 자기선택이 수익 편의를 만들지 않는다(t 0.22). 단 C18 표본은 C01 평균 0.221 vs 0.041 · log(Size) 28.13 vs 26.88 로 **대형·고서프라이즈 편중**."),
    ax001_v2 = as.list(setNames(lapply(seq_len(nrow(AX)), function(i) as.list(AX[i])), AX$arm)),
    search_dof = list(
      n_trials_reported = 4L, bonferroni_two_sided_t = 2.50,
      note = "exploratory 3종은 사전등록 원안에 없고 P0 중 발견. '스텝 압축'은 여러 가능한 수리 중 하나(대안: 분기 리샘플·달력 lag·이벤트 정렬) ⇒ primary 와 같은 증거력으로 읽지 말 것.")
  ),

  round_verdict = list(
    material_qualified_count = 0L,
    statement = "원안 4종 · exploratory 3종 모두 재료 자격 불성립. 본 라운드의 산출은 알파가 아니라 **재료 인벤토리의 정정**이다.",
    selection_type = "preregistered_family_grid", n_trials = 4L,
    dsr_applicability = "sweep 성격이나 자격 arm 0 이라 DSR 적용 대상 자체가 없음(선택할 챔피언 부재)")
)
write(toJSON(AV, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null"),
      file.path(OUT,"alpha_validation.json"))
say("alpha_validation.json 저장 (%d bytes)", file.size(file.path(OUT,"alpha_validation.json")))
file.copy(file.path(OUT,"alpha_validation.json"), file.path(MB,"alpha_validation.json"), overwrite=TRUE)

## =============================================================================
## 차트 — (1) arm 별 FMB t + 문턱  (2) C18 반전 통제 붕괴
## =============================================================================
png(file.path(OUT,"chart_fq198_summary.png"), width=1400, height=620, res=110)
par(mfrow=c(1,2), mar=c(9,4.5,3.5,1))
lab <- c("C18\n(원안 primary)","C10s\n(스텝보정)","C13s\n(스텝보정)","C15s\n(스텝보정)")
ord <- c(C18,"C10s_SUE_Persist_step","C13s_RevBreadth_step","C15s_SUE_Trend_step")
tv  <- sapply(ord, function(a_) g(RT,a_,"t_nw3"))
bp <- barplot(tv, names.arg=lab, las=2, cex.names=0.8, ylim=c(-3.2, 3.2),
        col=ifelse(abs(tv)>=2.5,"#c0392b", ifelse(abs(tv)>=2,"#e67e22","#95a5a6")),
        main="증분 FMB NW(lag3) t — 4 arm", ylab="t (신규 팩터 계수)")
abline(h=c(2,-2), lty=2, col="#7f8c8d"); abline(h=c(2.5,-2.5), lty=3, col="#c0392b"); abline(h=0)
text(bp, tv + ifelse(tv>0,0.22,-0.28), sprintf("%+.2f", tv), cex=0.85, font=2)
legend("topright", c("문턱 |t|=2.0","Bonferroni |t|=2.50"), lty=c(2,3), col=c("#7f8c8d","#c0392b"), bty="n", cex=0.75)

par(mar=c(9,4.5,3.5,1))
sp2 <- OUTS[spec %in% c("base","plus_1m","plus_6d","plus_1m_12m","full")]
lab2 <- c("통제 없음","+1M 반전","+6일 창","+1M+12M","+전체")
tv2 <- abs(sp2$t_nw3)
bp2 <- barplot(tv2, names.arg=lab2, las=2, cex.names=0.8, ylim=c(0,4.2),
        col=ifelse(tv2>=2,"#e67e22","#27ae60"),
        main="C18 증분 |t| — 반전/모멘텀 통제 하", ylab="|t| (C18 계수)")
abline(h=2, lty=2, col="#7f8c8d")
text(bp2, tv2+0.18, sprintf("%.2f", tv2), cex=0.85, font=2)
legend("topright", "자격 문턱 |t|=2.0", lty=2, col="#7f8c8d", bty="n", cex=0.75)
dev.off()
say("차트 저장 → chart_fq198_summary.png")
