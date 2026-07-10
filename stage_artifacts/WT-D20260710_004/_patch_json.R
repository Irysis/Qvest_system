suppressMessages({library(jsonlite)})
SA <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT-D20260710_004"
d <- fromJSON(file.path(SA,"alpha_stageA_diagnostics.json"), simplifyVector=FALSE)
d$analyst_notes <- list(
  headline="Signal-age sampling-artifact hypothesis REJECTED. No fresh>stale IC heterogeneity in ANY series (3 factors x tau{0.5,1.0} + exogenous DART event-age + holding-tenure). B2 economics also fail (KA4). B1 PROMOTE census formally passes (81>=60) but thin (33 firms) and DART direction is mildly negative/insignificant.",
  A2_count_artifact_warning="A2 aggregate contrib_diff nw_t (capw 2.61 / ew 3.40) is a BOOK-COMPOSITION artifact — book is 77.7% fresh names vs 12.4% stale (avg hold age 1.88m). The BINDING freshness test is per-name (perName_diff nw_t = -0.323, NULL). Do NOT cite the aggregate contrib as a freshness edge.",
  A3_underpower="MEGA/MID age-bucket cells have n_months=1 (MEGA/MID hold only 10/20 names => rarely >=8 in a single age bucket). KA3_fresh_ic_by_tier MEGA=0.2727 is a 1-month noise value. KA3 is UNDER-POWERED/inconclusive, not a clean FALSE. Robust reading (OTHER pool, n=256): OTHER 0-1m IC 0.047 ~= OTHER 4m+ 0.0445 => no age heterogeneity; established cap-tier localization (alpha in OTHER>30) unchanged.",
  DART_direction_caveat="Corrected A1-DART: buyback-event forward active mildly negative all ages (-0.1..-0.4%/mo, all insignificant), contrast fresh-stale nw_t=0.261 (no heterogeneity). Likely cap-w/size confound (2015+ mega regime), NOT a proven buyback-adverse signal. Conclusion: no FAVORABLE fresh-buyback edge detected; needs size-matched control before hard directional rejection.",
  A6_normal_na="A6 'normal' regime mean_active is NA due to one month with NA forward active (final-month Ret_1m). Advisory only, non-binding.",
  window_limits="DART buyback crawl = 2015-01..2026-06 ONLY (not 2005+). Factor series = 2004-2026 full."
)
d$self_adversarial <- list(
  concerns=list(
    list(id="C1", concern="value-innovation age (|dz|>tau) is an endogenous proxy, not true information-arrival age; noise could dilute a real heterogeneity toward null.",
         classification="PARTIAL", resolution="3 INDEPENDENT age operationalizations all null: value-innovation (tau 0.5 AND 1.0), exogenous DART event-age (true disclosure timestamp), A2 holding-tenure. Convergent null is robust to any single proxy's noise. Residual gap: true earnings Usable_Date age not used directly for factors."),
    list(id="C2", concern="A2 aggregate contrib significance (nw_t 2.6-3.4) could be misread as a freshness edge.",
         classification="ACCEPT", resolution="It is a count artifact (77.7% fresh book). Binding test = per-name diff (-0.323, null). Flagged in analyst_notes.A2_count_artifact_warning."),
    list(id="C3", concern="DART negative active may be a cap-w/size confound (2015+ mega regime), not a true buyback-adverse signal.",
         classification="PARTIAL", resolution="Do not conclude 'buyback bad'. Conclude 'no favorable fresh-buyback edge; mildly negative & insignificant; needs size-matched control'. Census opens B1 gate; direction evidence unfavorable/inconclusive."),
    list(id="C4", concern="A3 MEGA/MID age cells n=1 => KA3 verdict unreliable.",
         classification="ACCEPT", resolution="KA3 flagged under-powered/inconclusive, not clean FALSE."),
    list(id="C5-PROCESS", concern="Census-count first computed 856; independent adversarial cross-check gave 81.",
         classification="ACCEPT", resolution="Found data.table by-group scoping bug (ev[Ticker==Ticker[i]] resolved to ev's column). Fixed via rolling join with carried matched_ev col; re-verified == 81. A1-DART also corrected (spurious -2.21 -> 0.261). Factor A1/A2/A3/A4/integrity unaffected (do not use ev_age_m).")
  ),
  self_rationalization_check="No use of '미미/관행적/보수적이면 OK/대부분 동일' to wave away nulls. Nulls are NW-t-measured across multiple operationalizations.",
  escalation_triggers="None fired (no HIGH-sev>=5, no axiom hard FAIL>=3, no PIT C1 violation). Integrity CLEAN (cor=1.0 all spot dates)."
)
write_json(d, file.path(SA,"alpha_stageA_diagnostics.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("[patched] analyst_notes + self_adversarial added\n")
