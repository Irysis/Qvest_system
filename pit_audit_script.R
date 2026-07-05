## PIT_AUDIT.R - Adversarial check for look-ahead bias in RAMP R1
## Focus: regime overlay shift(,1) logic and asof_close semantics
library(data.table)
library(arrow)

OUT <- 'outputs/ramp'
QM <- getwd()

# Load the results from R1
res_file <- file.path('.cache', '_ramp_r1_20260705.rds')
if (!file.exists(res_file)) {
  cat('No cached R1 RDS found. Checking parquet output...\n')
  per <- tryCatch(as.data.table(read_parquet(file.path(OUT, 'r1_per_sleeve_gates.parquet'))), 
                  error=function(e) NULL)
  if (is.null(per)) {
    cat('ERROR: Cannot find R1 results\n')
    q()
  }
} else {
  cache <- readRDS(res_file)
  per <- cache$PER
  stk <- cache$STK
  ov <- cache$overlay_res
  best_stack <- cache$best_stack
}

cat('=== ADVERSARIAL VERIFICATION: RAMP R1 PIT ===\n')
cat('Lens: LOOK-AHEAD / PIT (Point-In-Time)\n\n')

# Check 1: Did any sleeve PASS port_t >= 2.95?
has_survivor <- any(is.finite(per$port_t_capwt) & per$port_t_capwt >= 2.95)
cat('1. SURVIVOR SLEEVE CHECK\n')
cat(sprintf('   Passed (port_t_capwt >= 2.95): %s\n', ifelse(has_survivor, 'YES', 'NO')))
if (has_survivor) {
  survivors <- per[port_t_capwt >= 2.95, model]
  cat(sprintf('   Models: %s\n', paste(survivors, collapse=', '))\n')
} else {
  cat('   => No individual sleeve survived. Diagnostic mode active.\n')
}

# Check 2: Stack passes?
stk_pass <- !is.null(stk) && nrow(stk) > 0 && any(is.finite(stk$port_t_capwt) & stk$port_t_capwt >= 2.95)
cat('\n2. STACK CHECK (EW/InvVol)\n')
if (!is.null(stk) && nrow(stk) > 0) {
  for (i in seq_len(nrow(stk))) {
    row <- stk[i]
    pass <- is.finite(row$port_t_capwt) && row$port_t_capwt >= 2.95
    cat(sprintf('   %s: port_t_capwt=%+.2f %s\n', 
                row$model, row$port_t_capwt, ifelse(pass, 'PASS', 'FAIL')))
  }
} else {
  cat('   No stack computed.\n')
}

# Check 3: Overlay passes?
ov_pass <- !is.null(ov) && nrow(ov) > 0 && is.finite(ov$port_t_capwt) && ov$port_t_capwt >= 2.95
cat('\n3. OVERLAY CHECK (soft regime)\n')
if (!is.null(ov) && nrow(ov) > 0) {
  cat(sprintf('   %s: port_t_capwt=%+.2f %s\n',
              ov$model, ov$port_t_capwt, ifelse(ov_pass, 'PASS', 'FAIL')))
} else {
  cat('   No overlay computed.\n')
}

cat('\n=== CRITICAL PIT CHECKS ===\n')
cat('Concern 1: shift(exposure,1) at line 151 of run_ramp_r1_sleeve_stack.R\n')
cat('  Question: Does shift(,1) eliminate LOOK-AHEAD in regime overlay?\n')
cat('  Issue: regime_state from alpha_scores may reflect t-close (current month-end)\n')
cat('    If regime is known at signal_date (t), shift(,1) just delays misalignment.\n')
cat('    PIT-safe requires: regime(signal_date) derived from t-1 data only.\n')
cat('  Status: CANNOT VERIFY without re-running with explicit lag checks.\n\n')

cat('Concern 2: canonical_screen_bt liquidity filter (t-1 ADV)\n')
cat('  Line 66: liq_dt = fwd$liq_dt[,.(Date, Ticker, adv)]\n')
cat('  This adv is from "Vol0*Close0" (line 42, factor_validation.R)\n')
cat('  Vol0 = Vol from c0=asof_close(signal_date)\n')
cat('  => Vol0 IS t-1 volume (pre-signal). OK.\n\n')

cat('Concern 3: group_z generation (factor_group_scores.parquet)\n')
cat('  Are group_z scores forward-looking?\n')
cat('  Required: group_z must use signal_date >= feature date (t-1 data)\n')
cat('  Status: CANNOT VERIFY without inspecting consolidation source.\n\n')

cat('=== VERDICT LOGIC (from §6) ===\n')
cat('  1. PORT_t_capwt >= 2.95 => SURVIVOR (book-marginal ΔIR)\n')
cat('  2. No survivors => negative confirmation\n')
cat('  3. Overlay as diagnostic (not graduation tier)\n\n')

final_verdict <- if (has_survivor || stk_pass) 'POTENTIAL PASS' else 'NEGATIVE'
cat(sprintf('Phase-1 Result: %s\n', final_verdict))
cat('BUT: Cannot confirm PIT-safety without re-audit of regime derivation.\n')
