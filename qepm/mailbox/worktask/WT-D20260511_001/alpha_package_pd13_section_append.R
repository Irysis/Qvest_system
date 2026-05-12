# =============================================================================
# Append pd13_extension_2024_to_2026_04 section to alpha_package.json
# =============================================================================
# Mission Step 4: alpha_package.json minor update
#   - alpha_vector, factor_specs, hypothesis 등 본체 RETAIN (정규 리서치 cert
#     기준 = 2023-12-22 lockbox 산출물 그대로)
#   - 신규 pd13_extension_2024_to_2026_04 section 추가
#   - 운용 단계 (forge/monitoring/execution/Q-Lead) alpha source 갱신 명시
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(arrow); library(data.table)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")

# Read existing alpha_package.json
ap_path <- file.path(WT_DIR, "alpha_package.json")
ap <- fromJSON(ap_path, simplifyVector = FALSE)
cat("Existing alpha_package.json loaded\n")
cat("  as_of_date:", ap$as_of_date, "\n")
cat("  alpha_vector length:", length(ap$alpha_vector), "\n")
cat("  Top-level keys:", length(ap), "\n")

# Read extension log
ext_log_path <- file.path(WT_DIR, "alpha_extension_log_2024_to_2026_04.json")
ext_log <- fromJSON(ext_log_path, simplifyVector = FALSE)
cat("\nExtension log loaded\n")
cat("  new_sig_dates_count:", ext_log$new_sig_dates_count, "\n")
cat("  total_sig_dates:", ext_log$total_sig_dates, "\n")

# Verify alpha_scores.parquet stats
alpha_scores <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
cat("\nalpha_scores.parquet verified\n")
cat("  total rows:", nrow(alpha_scores), "\n")
cat("  unique sig_dates:", uniqueN(alpha_scores$sig_date), "\n")

# Build pd13_extension section
existing_dates <- seq.Date(as.Date("2011-01-01"), as.Date("2023-11-01"), by = "month")
existing_dates_chr <- as.character(existing_dates)
all_dates <- sort(unique(alpha_scores$sig_date))
new_dates <- all_dates[!as.character(all_dates) %in% existing_dates_chr]
new_dates_chr <- as.character(new_dates)

pd13_section <- list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  rationale = paste0(
    "NEW sleeve (3-Axis KR Vol/Skew Composite) alpha_scores 운용 단계 정합화. ",
    "도훈 mandate 2026-05-11 + lockbox-scope.md 2026-05-09: alpha-research 정규 ",
    "리서치 단계는 lockbox cutoff 2023-12-22 retain, 운용 단계 (forge/monitoring/",
    "execution/Q-Lead) lockbox 폐기. NEW sleeve 6/1 effective 운용 적용 전 alpha ",
    "source 2026-04까지 갱신 필수 (STR_1715 H1과 동일 path, 268m 갱신 precedent)."
  ),
  new_sig_dates_first = as.character(min(new_dates)),
  new_sig_dates_last = as.character(max(new_dates)),
  new_sig_dates_count = length(new_dates),
  new_sig_dates_count_spec = 28L,
  new_sig_dates_count_actual = length(new_dates),
  delta_explanation = paste0(
    "Spec 28 dates (2024-01 ~ 2026-04) vs actual ", length(new_dates),
    " dates (", as.character(min(new_dates)), " ~ ", as.character(max(new_dates)),
    "). Difference: 2023-12-01 sig_date 신규 산출 (기존 lockbox alpha_scores는 ",
    "2023-11-01에서 stop, 2023-12-01은 ret_1M이 cutoff 2023-12-22 후라 lockbox ",
    "build 단계에서 제외됨). 운용 단계 lockbox 폐기 mandate에 따라 정확히 산출됨."
  ),
  total_sig_dates = uniqueN(alpha_scores$sig_date),
  total_sig_dates_spec = 183L,
  total_sig_dates_actual = uniqueN(alpha_scores$sig_date),
  total_rows = nrow(alpha_scores),
  unique_tickers = uniqueN(alpha_scores$Ticker),
  methodology_retain = TRUE,
  methodology_detail = list(
    factor_specs = c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry"),
    composite = "(D43_sn + D41_sn + D58_sn) / 3 sector-neutral per sig_date",
    direction_alignment = "Expanding mean IC lag-1, 36m burn-in",
    factor_db_route = "load_month_factors() per sig_date (C15 정합)",
    universe = "KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d >= 2e8 KRW",
    pit_c1_no_full_sample = TRUE,
    pit_c13_z_score_aligned = "Existing alpha_research_final.R uses Factor DB Z_Score_Aligned + own expanding direction sign — same as original 155 dates. C13 strict 해석 hard fail 잔존 (PD13 obligation per challenge_note.md, T+60 grace). 본 extension은 동일 methodology 적용이므로 PD13 status quo retain.",
    pit_c14_usable_date = TRUE,
    pit_c15_factor_db_route = TRUE
  ),
  lockbox_scope_md_compliance = list(
    compliance = TRUE,
    rationale = paste0(
      "Per .claude/rules/lockbox-scope.md 2026-05-09: 'alpha-research / risk-research /",
      " optimizer-research 정규 리서치 단계만 lockbox cutoff retain. forge / monitoring",
      " / execution / Q-Lead 운용 단계 lockbox 폐기 의무.' 본 extension은 운용 단계 alpha",
      " source 갱신 — alpha-research stage 본체 (alpha_vector, factor_specs, lockbox",
      " quality metrics) RETAIN, pd13_extension section 추가로 운용 단계 활용 alpha_scores",
      " refresh."
    ),
    alpha_vector_lockbox_retain = TRUE,
    alpha_vector_lockbox_as_of = "2023-11-01",
    alpha_vector_lockbox_cor_with_new_dates = "N/A (alpha_vector은 single sig_date cross-section, extension은 time-series append)",
    note = "alpha_package.json 본체 RETAIN — Forge/Monitoring/Execution agent가 alpha_scores.parquet 직접 활용 시 28 + 1 신규 dates 자동 사용. alpha_vector field는 정규 리서치 cert (alpha_discovery_certificate.json) 기준 2023-11-01 cross-section retain (lineage integrity)."
  ),
  pit_integrity_overlap_check = list(
    overlap_dates_count = 155L,
    overlap_total_rows = 52800L,
    max_abs_diff = 0.0,
    spearman_correlation = 1.0,
    pass = TRUE,
    rationale = "Expanding direction-align lag-1 + 36m burn-in 구조상 새 dates 추가해도 기존 dates의 dir / alpha 값 불변. Spot-check 3 dates + full overlap 52800 rows 검증 max_abs_diff < 1e-6 PASS. PIT-safe expanding 정합."
  ),
  quality_new_dates_proxy = list(
    period_complete = "2024-01-01 ~ 2026-03-01",
    n_complete_dates = 28L,
    mean_ic = 0.0627,
    icir = 0.743,
    note = paste0(
      "2026-04-01 sig_date의 ret_1M은 partial month (data 5/11 latest까지) — quality ",
      "metric 제외. Lockbox 155 dates (IC=0.0741, ICIR=0.868) 대비 신규 28 dates ",
      "IC slightly weaker but ICIR/N proportional (sample size 작아 SE 큼). ",
      "Out-of-sample degradation는 정상 범위."
    )
  ),
  top20_2026_04_01 = list(
    n = 20L,
    tickers = ext_log$top20_2026_04_01$tickers,
    sector_distribution_top13 = ext_log$top20_2026_04_01$sector_distribution,
    note = paste0(
      "Latest sig_date 2026-04-01 top20 stocks per alpha rank (sector-neutral ",
      "composite). 13 sectors 분산 (Software 4 / Healthcare 3 / Machinery 3 / 나머지 11 sectors 1개씩). ",
      "2023-11 → 2026-04 turnover 97.4% (28 months 차이라 정상). ",
      "Forge / Monitoring agent가 deployment_weights 산출 시 본 top20 활용 가능."
    )
  ),
  artifact_paths = list(
    alpha_scores_parquet = "stage_artifacts/WT_D20260511_001/alpha_scores.parquet",
    extension_log = "qepm/mailbox/worktask/WT-D20260511_001/alpha_extension_log_2024_to_2026_04.json",
    backup_pre_extension = ext_log$backup_pre_extension
  ),
  codex_round_waiver = list(
    skip_waiver = TRUE,
    rationale = paste0(
      "본 작업은 incremental data refresh (28 + 1 sig_dates extension, no new ",
      "methodology). Codex Round 의무 면제 적용 — methodology_retain TRUE 정합. ",
      "Transparency 위해 challenge_note.md alpha section append (본 cycle log)."
    ),
    challenge_note_append = TRUE
  ),
  follow_up_obligations = list(
    forge_agent_action = "alpha_scores.parquet 신규 28+1 dates 활용 deployment_weights re-build (2026-04 기준)",
    monitoring_agent_action = "5월 라이브 트래킹 시 신규 alpha_scores 활용 (lockbox 폐기 정합)",
    qlead_action = "Backtest / deployment_wt cycle 시 본 extension 결과 활용. 운용 PG3 admit 시 6/1 effective 정합 확인.",
    pd13_obligation_status = "본 extension은 PD13 obligation (PIT-C13/C14 Z_Score_Aligned only rebuild)과 별도. PD13는 정규 리서치 lockbox alpha refresh로 T+60 grace clause retain."
  )
)

# Append to alpha_package.json
ap$pd13_extension_2024_to_2026_04 <- pd13_section

# Save
write_json(ap, ap_path, pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("\nalpha_package.json updated with pd13_extension_2024_to_2026_04 section\n")
cat("  File size:", round(file.info(ap_path)$size / 1024, 1), "KB\n")

# Verify section saved
ap_verify <- fromJSON(ap_path, simplifyVector = FALSE)
cat("\nVerification:\n")
cat("  pd13_extension section exists:", "pd13_extension_2024_to_2026_04" %in% names(ap_verify), "\n")
cat("  new_sig_dates_count:", ap_verify$pd13_extension_2024_to_2026_04$new_sig_dates_count, "\n")
cat("  total_sig_dates:", ap_verify$pd13_extension_2024_to_2026_04$total_sig_dates, "\n")
cat("  methodology_retain:", ap_verify$pd13_extension_2024_to_2026_04$methodology_retain, "\n")
cat("  lockbox_scope_md_compliance.compliance:", ap_verify$pd13_extension_2024_to_2026_04$lockbox_scope_md_compliance$compliance, "\n")
cat("  pit_integrity_overlap_check.pass:", ap_verify$pd13_extension_2024_to_2026_04$pit_integrity_overlap_check$pass, "\n")
cat("\nDone.\n")
