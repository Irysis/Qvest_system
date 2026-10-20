## 구 이름 심(shim) — 끝난 라운드의 픽스처(evaluate_fixture.R)를 코어 함수로 다시 돌리기 위한 이름 대응표. 픽스처 사본이 evaluate.R 대신 이것을 적재한다.
##   대응은 이름 · 인자 묶기뿐이다(함수 본문 = round_core v1). 심을 통과하면 '코어 = 그 라운드 도우미'가 그 라운드의 합성 검사 전부에서 같다는 뜻이다.
##   사용: QM_ROOT=<저장소> Rscript -e 'source(".../rejudge/shims.R"); rc_shim("P2R04")' 형태가 아니라, 픽스처 사본에서 source(shims.R) 뒤 rc_shim(<라운드>)
.rc_shim_root <- function() gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
.rc_shim_load <- function(ext) {
  root <- .rc_shim_root()
  if (!exists("rc_p2_template", mode = "function")) source(file.path(root, "04_Research/programs/_lib/round_core/v1/load.R"))
  sys.source(file.path(root, "04_Research/programs/_lib/round_core/rejudge", ext), envir = globalenv())
}
.rc_assign <- function(L) for (n in names(L)) assign(n, L[[n]], envir = globalenv())
## P2 공용(P2R03 · P2R04 같은 이름 · 같은 동작)
.rc_shim_p2_common <- function() .rc_assign(list(
  p2_maj = rc_maj, .p2_rows_dt = .rc_rows_dt, .p2_key = .rc_key, p2_crisis_majority = rc_crisis_majority, p2_deep_crisis_keys = rc_deep_crisis_keys,
  p2_fast_crash_keys = rc_p2_fast_crash_keys, p2_bull_segments = rc_p2_bull_segments, p2_beta_asym = rc_p2_beta_asym, p2_beta_ratio_delta = rc_p2_beta_ratio_delta,
  p2_cycle_pairs = rc_cycle_pairs, p2_cycle_compound = rc_cycle_compound, p2_top_loss = rc_top_loss, p2_conc_status = rc_conc_status, p2_alpha_ok = rc_alpha_ok,
  p2_recovery_tag = rc_recovery_tag, p2_select = rc_select, p2_fp_same = rc_fp_same, .p2_read_holdings = rc_read_holdings, p2_pk_read = rc_pk_read,
  p2_pk_build = rc_pk_build, p2_eng_alpha = rc_eng_alpha, p2_cell_join = rc_cell_join,
  p2_fingerprint = function(rd, mode = "equality") rc_fingerprint(file.path(rd, "fingerprint.sh"), mode)))
rc_shim <- function(round) {
  switch(round,
    P2R04 = {
      .rc_shim_load("P2R04_ext.R"); .rc_shim_p2_common()
      T <- P2R04_T
      .rc_assign(list(
        P2R04_FS_KEYS = RC_P2_FS_KEYS, P2R04_VERDICTS = RC_P2_VERDICTS, P2R04_MC8_LABELS = RC_P2_MC8_LABELS, P2R04_PIN_KINDS = RC_LEGACY_PIN_KINDS,
        P2R04_VISIBLE_DROP = RC_P2_VISIBLE_DROP, P2R04_REDACT = RC_REDACT, P2R04_FULL_AUDIENCE = RC_FULL_AUDIENCE, P2R04_FULL_MARK = RC_FULL_MARK,
        P2R04_FULL_MARK_PARENT = RC_FULL_MARK_PARENT,
        .p2_mark_full = function(dir, note = NULL) rc_mark_full(dir, note),
        p2_trim_artifacts = function(src_dir, out_dir, start) rc_trim_artifacts(src_dir, out_dir, start, mark = TRUE),
        p2_beta_scaled_copy = function(src_dir, out_dir, k) rc_beta_scaled_copy(src_dir, out_dir, k, mark = TRUE),
        p2_beta_plan = rc_beta_plan, p2_size_beta_plan = rc_p2_size_beta_plan, p2_size_beta_core = rc_p2_size_beta_core, p2_vs_market = rc_p2_vs_market,
        p2_parse_cell_log = rc_p2_parse_cell_log, p2_parse_direction_lines = rc_p2_parse_direction_lines, p2_direction_record = rc_p2_direction_record,
        .p2_spec_tail = .rc_p2_spec_tail, p2_construction_check = rc_p2_construction_check, p2_blend_weight = rc_p2_blend_weight, p2_ratio_str = rc_p2_ratio_str,
        p2_diag_device = function(comp, spec_factors) rc_p2_diag_device(comp, spec_factors, P2R04_DIAGNOSTICS, P2R04_DEVICES),
        p2_diag_expect_weight = function(comp, cells, root) rc_p2_diag_expect_weight(comp, cells, root, P2R04_DIAGNOSTICS, P2R04_DEVICES),
        p2_holdings_overlap = rc_holdings_overlap, p2_treatment_delivered = rc_treatment_delivered,
        p2_selection_attr = function(label, required, controls_status = "ok") rc_p2_selection_attr(label, required, controls_status, RC_P2_MC8_LABELS),
        p2_selection_decomp = rc_p2_selection_decomp, p2_selection_rule = rc_p2_selection_rule, p2_crisis_record = rc_p2_crisis_record,
        p2_size_profile = rc_p2_size_profile, p2_size_compare = rc_p2_size_compare, p2_liq_deciles = rc_p2_liq_deciles, .p2_months = .rc_p2_months,
        p2_regime_diff = rc_p2_regime_diff,
        p2_rx0_identity_core = function(H4, H3, pr4, pr3, tau) rc_p2_rx0_identity_core(H4, H3, pr4, pr3, tau, "p2r04", "p2r03"),
        p2_cell_pass = rc_p2_cell_pass, p2_cell_verdict = rc_p2_cell_verdict, p2_defense_name = rc_p2_defense_name,
        p2_verdict_counts = function(v) rc_verdict_counts(v, RC_P2_VERDICTS, P2R04_VERDICT_SHORT),
        p2_round_verdict = function(TB) rc_round_verdict(TB, "device", RC_P2_VERDICTS, P2R04_VERDICT_SHORT),
        .p2_wins = .rc_p2_wins, p2_read_overlap_wins = rc_p2_read_overlap_wins, p2_read_missing = rc_p2_read_missing,
        p2_capacity_label = function(e2_50, e3_50, e2_12, e3_12, table = P2R04_CAPACITY_TABLE) rc_p2_capacity_label(e2_50, e3_50, e2_12, e3_12, table),
        p2_read_capacity = function(e2h, e3h, e2w, e3w) rc_p2_read_capacity(e2h, e3h, e2w, e3w, P2R04_CAPACITY_TABLE),
        p2_read_dilution = rc_p2_read_dilution, p2_diag_summary = rc_p2_diag_summary,
        p2_readings = function(OUT, DOUT, tol, devices = names(P2R04_DEVICES), diag_engine = P2R04_DIAG_ENGINE)
          rc_p2_readings(OUT, DOUT, tol, devices, P2R04_DIAGNOSTICS, diag_engine, P2R04_CAPACITY_TABLE),
        p2_a_distance = rc_p2_a_distance,
        p2_noise_reading = function(OUT, validated, tie_eps, maj, devices = names(P2R04_DEVICES)) rc_p2_noise_reading(OUT, validated, tie_eps, maj, devices),
        p2_fs_missing = function(FS) rc_p2_fs_missing(FS, RC_P2_FS_KEYS),
        p2_cells_check = function(cells, devices = P2R04_DEVICES, diags = P2R04_DIAGNOSTICS, diag_engine = P2R04_DIAG_ENGINE) rc_p2_cells_check(cells, devices, diags, diag_engine, "P2R04"),
        .p2_redact_chr = .rc_redact_chr, p2_redact_after_tau = rc_redact_after_tau,
        p2_visible_only = function(x, tau) rc_p2_visible_only(x, tau, RC_P2_VISIBLE_DROP),
        p2_pin_mismatches = function(pre, root) rc_legacy_pin_mismatches(pre, root, RC_LEGACY_PIN_KINDS),
        .p2_untested = T$untested, .p2_read_lines = rc_read_lines,
        p2_eval_pair = function(X, eng, dev, cm, cr, em, er, opts = list()) rc_pair_run(X, P2R04_T, list(engine = eng, unit = dev, cm = cm, cr = cr, em = em, er = er), opts),
        p2_eval_pair_safe = function(X, eng, dev, cm, cr, em, er, opts = list()) rc_pair_run_safe(X, P2R04_T, list(engine = eng, unit = dev, cm = cm, cr = cr, em = em, er = er), opts),
        p2_size_beta_record = rc_p2_size_beta_record, p2_liq_panel = function(root, tau) rc_p2_liq_panel(root, tau), p2_liquidity_record = rc_p2_liquidity_record,
        p2_regime_months = rc_p2_regime_months, p2_rx0_identity = function(X, art4, json3) rc_p2_rx0_identity(X, art4, json3, "p2r04", "p2r03")))
    },
    P2R03 = {
      .rc_shim_load("P2R03_ext.R"); .rc_shim_p2_common()
      .rc_assign(list(
        p2_trim_artifacts = function(src_dir, out_dir, start) rc_trim_artifacts(src_dir, out_dir, start, mark = FALSE),
        p2_beta_scaled_copy = function(src_dir, out_dir, k) rc_beta_scaled_copy(src_dir, out_dir, k, mark = FALSE),
        p2_hm_fit = p2r03_hm_fit, p2_cash_timing = p2r03_cash_timing, p2_parse_overlay_log = p2r03_parse_overlay_log, p2_subset_check = p2r03_subset_check,
        p2_round_verdict = function(TB) rc_round_verdict(TB, "device"), p2_lag_tag = p2r03_lag_tag, p2_lag_hold = p2r03_lag_hold,
        p2_pin_mismatches = function(pre, root) rc_legacy_pin_mismatches(pre, root, kinds = NULL),
        P2R03_OVERLAY_VISIBLE_KEYS = P2R03_OVERLAY_VISIBLE_KEYS, p2_visible_only = p2r03_visible_only, .p2_untested = p2r03_untested,
        P2R03_FULL_AUDIENCE = RC_FULL_AUDIENCE,
        p2_eval_pair = function(X, eng, dev, cm, cr, em, er, opts = list()) rc_pair_run(X, P2R03_T, list(engine = eng, unit = dev, cm = cm, cr = cr, em = em, er = er), opts),
        p2_eval_pair_safe = function(X, eng, dev, cm, cr, em, er, opts = list()) rc_pair_run_safe(X, P2R03_T, list(engine = eng, unit = dev, cm = cm, cr = cr, em = em, er = er), opts)))
    },
    P3R03 = {
      .rc_shim_load("P3R03_ext.R")
      .rc_assign(list(
        .p3_rows_dt = .rc_rows_dt, .p3_key = .rc_key,
        p3_trim_artifacts = function(src_dir, out_dir, start) rc_trim_artifacts(src_dir, out_dir, start, mark = FALSE, errtag = "p3_trim"),
        p3_beta_scaled_copy = function(src_dir, out_dir, k) rc_beta_scaled_copy(src_dir, out_dir, k, mark = FALSE, errtag = "p3_beta"),
        p3_crisis_majority = function(cr_m, cr_r, tol, metric = "cum_capture", subset = NULL) rc_crisis_majority(cr_m, cr_r, tol, metric, subset),
        p3_deep_crisis_keys = rc_deep_crisis_keys, p3_cycle_pairs = rc_cycle_pairs, p3_cycle_compound = rc_cycle_compound, p3_top_loss = rc_top_loss,
        p3_conc_status = rc_conc_status, p3_beta_verdict = rc_p3_beta_verdict, p3_parse_cell_log = rc_p3_parse_cell_log, p3_delivery = rc_p3_delivery,
        p3_crisis_execs = rc_p3_crisis_execs, p3_selection_vs_ref = rc_p3_selection_vs_ref, p3_history_drops = rc_p3_history_drops,
        p3_subset_check = rc_p3_subset_check, p3_alpha_ok = rc_alpha_ok, p3_round_verdict = function(TB) rc_round_verdict(TB, "method"),
        p3_candidate_tags = rc_p3_candidate_tags, p3_pin_mismatches = p3r03_pin_mismatches, p3_history_drop_eval = rc_p3_history_drop_eval,
        p3_fingerprint = function(rd, mode = "equality") rc_fingerprint(file.path(rd, "fingerprint.sh"), mode),
        .p3_untested = rc_p3_untested, .p3_read_holdings = rc_read_holdings, p3_pk_read = rc_pk_read, p3_pk_build = rc_pk_build, p3_eng_alpha = rc_eng_alpha,
        p3_eval_pair = function(X, eng, mth, cm, cr, em, er, opts = list()) rc_pair_run(X, P3R03_T, list(engine = eng, unit = mth, cm = cm, cr = cr, em = em, er = er), opts),
        p3_eval_pair_safe = function(X, eng, mth, cm, cr, em, er, opts = list()) rc_pair_run_safe(X, P3R03_T, list(engine = eng, unit = mth, cm = cm, cr = cr, em = em, er = er), opts)))
    },
    stop("모르는 라운드: ", round))
  invisible(round)
}
## 픽스처 사본 — 원래 픽스처를 읽어 evaluate.R 적재 줄을 심 적재로 바꾸고(치환 성사 단정 · 소스 텍스트 치환), 구 파일 대상 뮤테이션 절을 뺀다(뮤테이션은 코어 대상
##   검사가 따로 한다). 경로 = 저장소 접두 치환(main → 이 저장소). 반환 = 사본 경로
rc_fixture_sandbox <- function(round, fixture, root, out_dir, main_root = "C:/Users/99922/OneDrive/Quant_Module_Moltbot") {
  src <- readLines(fixture, encoding = "UTF-8", warn = FALSE)
  src <- gsub(main_root, root, src, fixed = TRUE)
  shim <- sprintf('source("%s/04_Research/programs/_lib/round_core/rejudge/shims.R"); rc_shim("%s")', root, round)
  hit <- grep("^source\\((EVF|\".*/evaluate\\.R\")\\)\\s*$", src)
  if (length(hit) != 1L) stop("evaluate.R 적재 줄이 정확히 1줄이 아니다: ", length(hit))
  src[hit] <- shim
  mu <- grep("^## [0-9]+\\) 뮤테이션", src)
  if (length(mu)) {
    tail_i <- grep("^cat\\(sprintf\\(\"(합계|\\\\n합계)", src)
    keep_tail <- if (length(tail_i)) src[tail_i[length(tail_i)]:length(src)] else character(0)
    src <- c(src[seq_len(mu[1] - 1L)], "nk <- 0L; MU <- list()", keep_tail)
  }
  src <- c(sprintf('Sys.setenv(QM_ROOT = "%s", CLAUDE_PROJECT_DIR = "%s")   # ~/.Renviron 의 QM_ROOT(main)를 이 저장소로 덮는다', root, root), src)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  p <- file.path(out_dir, sprintf("%s_fixture_core.R", round)); writeLines(src, p, useBytes = TRUE)
  p
}
