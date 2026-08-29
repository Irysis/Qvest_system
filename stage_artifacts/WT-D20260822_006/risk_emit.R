# ============================================================================
# Risk Research EMIT — regime_correlation, covariance.parquet, risk_package.json
# WT-D20260822_006. Assembles all 5 axes into contract output + red flags + lineage.
# ============================================================================
suppressMessages({library(arrow); library(dplyr); library(data.table); library(jsonlite)})
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
WTID <- "WT-D20260822_006"; OUT <- file.path("stage_artifacts", WTID)
MBX  <- file.path("qepm/mailbox/worktask", WTID); SIG <- as.Date("2026-07-01")
C <- readRDS(file.path(OUT, "risk_core.rds"))
T <- readRDS(file.path(OUT, "risk_tail.rds"))
Sigma <- C$Sigma; keep_tick <- C$keep_tick; mat <- C$mat; est_dates <- C$est_dates

# ============================================================================
# regime_correlation — avg pairwise correlation shift across vol regimes
# split est window by market (BM) realized vol tercile -> compare mean |corr|
# ============================================================================
bm_ret <- C$bm_ret
roll_vol <- data.table::frollapply(bm_ret, 21, sd); roll_vol[is.na(roll_vol)] <- median(roll_vol, na.rm=TRUE)
brk <- quantile(roll_vol, c(1/3, 2/3), na.rm = TRUE)
reg <- ifelse(roll_vol >= brk[2], "HIGH_VOL", ifelse(roll_vol >= brk[1], "MID_VOL", "LOW_VOL"))
mean_abs_corr <- function(rows) {
  m <- mat[rows, , drop = FALSE]
  keep <- apply(m, 2, function(x) sd(x) > 0)
  m <- m[, keep, drop = FALSE]
  if (ncol(m) < 5 || nrow(m) < 20) return(NA_real_)
  cc <- cor(m); mean(abs(cc[upper.tri(cc)]), na.rm = TRUE)
}
regime_corr <- data.table(
  regime = c("LOW_VOL","MID_VOL","HIGH_VOL"),
  n_days = c(sum(reg=="LOW_VOL"), sum(reg=="MID_VOL"), sum(reg=="HIGH_VOL")),
  mean_abs_pairwise_corr = c(mean_abs_corr(which(reg=="LOW_VOL")),
                             mean_abs_corr(which(reg=="MID_VOL")),
                             mean_abs_corr(which(reg=="HIGH_VOL")))
)
corr_lift <- regime_corr$mean_abs_pairwise_corr[3] / regime_corr$mean_abs_pairwise_corr[1]
write_parquet(regime_corr, file.path(OUT, "regime_correlation.parquet"))
cat(sprintf("[REGIME] corr LOW=%.3f MID=%.3f HIGH=%.3f  lift=%.2fx\n",
    regime_corr$mean_abs_pairwise_corr[1], regime_corr$mean_abs_pairwise_corr[2],
    regime_corr$mean_abs_pairwise_corr[3], corr_lift))

# ============================================================================
# covariance.parquet — annualized Σ (names x names), long form to stay compact
# ============================================================================
Sig_df <- as.data.table(Sigma); Sig_df[, ticker := keep_tick]
setcolorder(Sig_df, c("ticker", setdiff(names(Sig_df), "ticker")))
write_parquet(Sig_df, file.path(OUT, "covariance.parquet"))
# also exposure + factor cov + specific
exp_df <- as.data.table(C$B); exp_df[, ticker := keep_tick]
setcolorder(exp_df, c("ticker", setdiff(names(exp_df),"ticker")))
write_parquet(exp_df, file.path(OUT, "exposure_matrix.parquet"))
om_df <- as.data.table(C$Omega); om_df[, factor := colnames(C$B)]
write_parquet(om_df, file.path(OUT, "factor_covariance.parquet"))
write_parquet(data.table(ticker=keep_tick, specific_var=C$spec_var*252),
              file.path(OUT, "specific_risk.parquet"))
cat("[SAVE] covariance/exposure/factor_cov/specific parquet\n")

# ============================================================================
# RED FLAGS (RF-R1..R5)
# ============================================================================
top <- C$top_risks_pct
top_name <- names(top)[1]; top_val <- as.numeric(top[1])
crowd_flags_present <- any(sapply(T$crowding_per_factor, function(x) x$crowding_score >= 0.75))
# factor pairs |corr|>0.8
Om <- C$Omega; osd <- sqrt(diag(Om)); Ocor <- Om / outer(osd, osd)
hi_pairs <- sum(abs(Ocor[upper.tri(Ocor)]) > 0.8)
mkt5 <- T$stress$market_down_5$cum_ret

challenge_flags <- list()
if (top_val > 0.40) challenge_flags <- c(challenge_flags, sprintf(
  "RF-R1 [HIGH] top_common_risk %s = %.1f%% > 40%% — 신호가 시장 방향 노출에 지배됨(롱온리 |alpha| attention 기준). exposure bound 권고는 optimizer scope 위임(측정만).", top_name, top_val*100))
if (C$cond_after > 500) challenge_flags <- c(challenge_flags, sprintf(
  "RF-R2 [HIGH] condition_number after shrinkage = %.1f > 500", C$cond_after))
if (crowd_flags_present) challenge_flags <- c(challenge_flags,
  "RF-R3 [MEDIUM] crowding_score >= 0.75 존재")
if (!is.na(mkt5) && mkt5 < -0.08) challenge_flags <- c(challenge_flags, sprintf(
  "RF-R4 [HIGH] market_down_5 = %.4f < -8%%", mkt5))
if (hi_pairs >= 2) challenge_flags <- c(challenge_flags, sprintf(
  "RF-R5 [MEDIUM] factor |corr|>0.8 pair %d개", hi_pairs))
# always-note: COVID reliable stress magnitude
covid <- T$stress$covid_2020$cum_ret
challenge_flags <- c(challenge_flags, sprintf(
  "RF-note [INFO] 최심 신뢰가능 stress = COVID_2020 %.1f%% (coverage %.0f%%), RateHike2022 %.1f%% (coverage %.0f%%). GFC/EuDebt/China2015 은 book coverage <85%% 로 UNRELIABLE(부분상장 아티팩트, hard-fail 아님).",
  covid*100, T$stress$covid_2020$coverage*100,
  T$stress$ratehike_2022$cum_ret*100, T$stress$ratehike_2022$coverage*100))
cat("[FLAGS]\n"); for (f in challenge_flags) cat("  -", f, "\n")

# ============================================================================
# cap-tier decomposition (v8.3.1 mandatory field)
# ============================================================================
trs <- T$tier_risk_share; tas <- T$tier_alpha_share
tiers <- lapply(c("MEGA","MID","SMALL"), function(tn) {
  list(tier=tn,
       active_risk_share = round(as.numeric(ifelse(tn %in% names(trs), trs[tn], 0)),3),
       alpha_share       = round(as.numeric(ifelse(tn %in% names(tas), tas[tn], 0)),3),
       signal_alive      = as.numeric(ifelse(tn %in% names(tas), tas[tn], 0)) > 0.15)
})
dual_div <- abs((as.numeric(ifelse("MEGA"%in%names(trs),trs["MEGA"],0))) -
                (as.numeric(ifelse("MEGA"%in%names(tas),tas["MEGA"],0)))) > 0.10

# ============================================================================
# top_common_risks formatted
# ============================================================================
top_fmt <- sapply(seq_len(min(4,length(top))), function(i)
  sprintf("%s (%.0f%%)", names(top)[i], top[i]*100))

# ============================================================================
# ASSEMBLE risk_package.json
# ============================================================================
rp <- list(
  task_id = WTID,
  as_of_date = "2026-06-30",
  sig_date = "2026-07-01",
  pit_note = "모든 추정은 Date < 2026-07-01 (sig_date) 데이터만 사용. 유니버스 스냅샷 = 2026-06-30 최종 관측. beta = 3y(756d) walk-forward window 회귀(단일 cross-section 아티팩트 회피, Blume shrink).",
  role_boundary = "alpha_vector 수정 없이 수신(328종). weight/MVO 미산출(optimizer scope). RF-R1 exposure bound 는 측정·권고만.",
  selection_objective = "condition_number",   # v6.1 R4: estimation-quality enum only
  exposure_matrix_ref = "stage_artifacts/WT-D20260822_006/exposure_matrix.parquet",
  factor_covariance_ref = "stage_artifacts/WT-D20260822_006/factor_covariance.parquet",
  specific_risk_ref = "stage_artifacts/WT-D20260822_006/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT-D20260822_006/covariance.parquet",
  sigma_structure = "BOmegaB' + D (factor risk model)",
  n_names = length(keep_tick),
  n_factors = ncol(C$B),
  risk_summary = list(
    top_common_risks = as.list(top_fmt),
    factor_variance_share = round(C$factor_share,4),
    specific_variance_share = round(C$specific_share,4),
    portfolio_beta_blume = round(T$port_beta,3),
    crowding_flags = if (crowd_flags_present) list("see crowding_score_per_factor") else list(),
    crowding_score_per_factor = T$crowding_per_factor,
    liquidity_flags = list(sprintf("advt-based; 유동성 하한 2e8 KRW 는 편입 단계 제약(optimizer). 본 진단은 concentration 관점 — vol_concentration(top-decile illiquid) F1=%.3f",
                                   T$crowding_per_factor[[1]]$vol_concentration)),
    concentration = list(
      sector_hhi = round(T$sector_hhi,4), sector_n_effective = round(T$sector_n_eff,1),
      name_hhi = round(T$name_hhi,5), name_n_effective = round(T$name_n_eff,1)
    ),
    cap_tier_decomposition = list(
      basis = "cap_w_and_ew_uni_proxy(Size_tercile)",
      tiers = tiers,
      dual_basis_divergence_flag = dual_div
    ),
    stress_tests = list(
      market_down_5 = T$stress$market_down_5$cum_ret,
      gfc_2008      = list(cum=T$stress$gfc_2008$cum_ret, coverage=T$stress$gfc_2008$coverage, reliable=FALSE),
      eudebt_2011   = list(cum=T$stress$eudebt_2011$cum_ret, coverage=T$stress$eudebt_2011$coverage, reliable=FALSE),
      china_2015    = list(cum=T$stress$china_2015$cum_ret, coverage=T$stress$china_2015$coverage, reliable=FALSE),
      covid_2020    = list(cum=T$stress$covid_2020$cum_ret, coverage=T$stress$covid_2020$coverage, reliable=TRUE),
      ratehike_2022 = list(cum=T$stress$ratehike_2022$cum_ret, coverage=T$stress$ratehike_2022$coverage, reliable=TRUE),
      kr_bear_2018  = list(cum=T$stress$kr_bear_2018$cum_ret, coverage=T$stress$kr_bear_2018$coverage, reliable=TRUE)
    ),
    tail_risk = T$tail_risk
  ),
  diagnostics = list(
    condition_number_BOmegaB_D_precalibration = round(C$cond_precal,1),
    condition_number_before = round(C$cond_before,1),   # post variance-calibration, pre-floor
    condition_number_after  = round(C$cond_after,1),     # after RF-R2 eigen-floor
    shrinkage_used = C$shrink_used,
    shrinkage_method = C$shrink_method,
    variance_calibration = list(
      applied = TRUE,
      method = "diagonal_preserving: rescale each name so diag(Σ)=realized total var; keeps factor-implied correlation",
      reason = "cross-sectional factor model over-attributes total variance (Var(fitted)+Var(resid)=1.72x Var(raw), temporal Cov(fitted,resid)≠0). Barra-style anchor of variance level to empirical.",
      vol_level_preservation_median = round(C$vol_inflation_median,3)
    ),
    psd_verified = C$psd_ok,
    factor_correlation_warnings = if (hi_pairs>0) list(sprintf("%d factor pairs |corr|>0.8", hi_pairs)) else list(),
    regime_correlation = list(
      low_vol  = round(regime_corr$mean_abs_pairwise_corr[1],3),
      mid_vol  = round(regime_corr$mean_abs_pairwise_corr[2],3),
      high_vol = round(regime_corr$mean_abs_pairwise_corr[3],3),
      high_over_low_lift = round(corr_lift,2),
      interpretation = "high-vol 국면 상관 상승 = 위기 시 분산효과 축소(공동움직임 강화). 가설의 '고분산 구간' scope 와 방향 정합.",
      ref = "stage_artifacts/WT-D20260822_006/regime_correlation.parquet"
    ),
    method_shopping_log = list(
      risk_agent = list(
        candidates_tried = 3L,
        method_log = list(
          list(name="raw_sample_cov_NxN", condition="full_rank_but_noisy", selected=FALSE,
               note="328 names x 756 days(3y): full-rank 이나 name-pair 상관 노이즈 과다 -> 구조 부여 위해 factor model 채택"),
          list(name="factor_model_BOmegaB'+D (Omega LW-diag)", condition=round(C$cond_precal,1), selected=FALSE,
               note="base 구조. 단 총분산 1.72x 과다귀속(temporal Cov(fitted,resid)≠0) -> 분산레벨 보정 필요"),
          list(name="factor_model + diag-var-calibration + eigen_floor(cond<=400)", condition=round(C$cond_after,1), selected=TRUE,
               note="채택 — 상관구조는 factor model, 분산레벨은 empirical anchor(vol 보존 1.01x). cond 3639->400 RF-R2 대응, PSD 보존")
        ),
        selection_objective = "condition_number"
      )
    ),
    tdc_summary = list(note="factor-model 기반 — 명시적 copula TDC 미적합. regime_correlation high/low lift 로 tail co-movement 대리."),
    regime_correlation_ref = "stage_artifacts/WT-D20260822_006/regime_correlation.parquet"
  ),
  challenge_flags = challenge_flags,
  challenge_review = list(
    from = "risk", to = "alpha", objection = FALSE,
    targets_reviewed = c("alpha_package","alpha_vector","confidence_vector","factor_specs"),
    note = "alpha_vector 328종 무결 수신. round_verdict=CONFIG_SCOPED_NEGATIVE 인지 — 자본 주장 없음. risk 관점 이의 없음(신호 자체가 시장노출 지배이나 이는 alpha 설계 결함이 아니라 롱온리 top-N 구조 속성, CF-01 계열 alpha 진단과 정합). RF-R1 은 정보 전달이지 alpha 반론 아님."
  )
)

write_json(rp, file.path(MBX, "risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
cat("[EMIT] risk_package.json written\n")

# ---- lineage (AFTER write_json, per v6.1 R11 order) ----
lin_ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WTID, package_type = "risk_package",
    method_selected = "factor_model_BOmegaB'+D_eigenfloor",
    input_file_paths = c(file.path(MBX,"alpha_package.json")),
    windows = list(list(name="estimation", start=as.character(min(est_dates)),
                        end=as.character(max(est_dates)))))
  TRUE
}, error=function(e){cat("[lineage] skipped:",conditionMessage(e),"\n"); FALSE})
cat("[LINEAGE]", if(lin_ok)"recorded" else "skipped(non-fatal)", "\n")
cat("[DONE] risk emit complete\n")
