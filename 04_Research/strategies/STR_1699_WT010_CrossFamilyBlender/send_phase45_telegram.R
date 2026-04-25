## Phase 4.5 Telegram dispatch (force=TRUE override)
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-D20260425_010"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR  <- file.path(BASE_DIR, "04_Research/strategies/STR_1699_WT010_CrossFamilyBlender/output")

pkg <- fromJSON(file.path(WT_DIR, "forge_phase45_package.json"),
                simplifyVector = FALSE)

# Extract metrics
sr_full   <- pkg$str_1699_full_period$metrics$sr
cagr_full <- pkg$str_1699_full_period$metrics$cagr
mdd_full  <- pkg$str_1699_full_period$metrics$mdd
n_full    <- pkg$str_1699_full_period$metrics$n_months
t_ff5_full <- pkg$str_1699_full_period$metrics$harvey_t_ff5
dsr_full  <- pkg$str_1699_full_period$metrics$dsr_post_penalty

sr_prelb  <- pkg$str_1699_full_period$decomposition$pre_lb_only$sr
cagr_prelb <- pkg$str_1699_full_period$decomposition$pre_lb_only$cagr
mdd_prelb <- pkg$str_1699_full_period$decomposition$pre_lb_only$mdd
t_prelb   <- pkg$str_1699_full_period$decomposition$pre_lb_only$harvey_t_ff5

sr_oos    <- pkg$str_1699_full_period$decomposition$oos_only$sr
cagr_oos  <- pkg$str_1699_full_period$decomposition$oos_only$cagr
mdd_oos   <- pkg$str_1699_full_period$decomposition$oos_only$mdd
t_oos     <- pkg$str_1699_full_period$decomposition$oos_only$harvey_t_ff5

mega_sr   <- pkg$mega05_documented_dsr$metrics$sr
mega_cagr <- pkg$mega05_documented_dsr$metrics$cagr
mega_mdd  <- pkg$mega05_documented_dsr$metrics$mdd
mega_n    <- pkg$mega05_documented_dsr$metrics$n_months
mega_dsr_raw  <- pkg$mega05_documented_dsr$dsr_basis$raw_dsr
mega_dsr_post <- pkg$mega05_documented_dsr$dsr_basis$post_penalty_dsr
mega_doc_sr   <- pkg$mega05_documented_dsr$documented_baseline$SR

scen_a_full   <- pkg$nav_level_scenarios$scenario_A_full_period
scen_a_doc    <- pkg$nav_level_scenarios$scenario_A_vs_doc_same
scen_b        <- pkg$nav_level_scenarios$scenario_B_with_1699_60_20_20
scen_d        <- pkg$nav_level_scenarios$scenario_D_current_PG2_80_20
mega_sp       <- pkg$nav_level_scenarios$baseline_mega_doc_same_period
fair_dsr      <- pkg$nav_level_scenarios$fair_delta_vs_doc$delta_sr
fair_cagr     <- pkg$nav_level_scenarios$fair_delta_vs_doc$delta_cagr_pp
fair_mdd      <- pkg$nav_level_scenarios$fair_delta_vs_doc$delta_mdd_pp

recommended <- pkg$recommendation$selected
hash_pass <- pkg$hash_audit$pure_function_pass

# Build sections
s1_df <- data.frame(
  Period   = c("Pre-LB (215m)", "OOS 24-26 (29m)", "Full-Period (244m)"),
  SR       = sprintf("%.3f", c(sr_prelb,   sr_oos,   sr_full)),
  CAGR_pct = sprintf("%.2f", 100*c(cagr_prelb, cagr_oos, cagr_full)),
  MDD_pct  = sprintf("%.2f", 100*c(mdd_prelb,  mdd_oos,  mdd_full)),
  t_FF5    = sprintf("%.3f", c(t_prelb,    t_oos,    t_ff5_full)),
  stringsAsFactors = FALSE
)

s2_df <- data.frame(
  Scenario = c("A. STR_1699 100% (full)",
               "Baseline. MEGA_05 doc",
               "B. MEGA60+1699_20+1656_20",
               "D. MEGA80+1656_20 (cur)"),
  n_m      = c(scen_a_full$n_months, mega_n, scen_b$n_months, scen_d$n_months),
  SR       = sprintf("%.3f", c(scen_a_full$sr, mega_sr, scen_b$sr, scen_d$sr)),
  CAGR_pct = sprintf("%.2f", 100*c(scen_a_full$cagr, mega_cagr,
                                    scen_b$cagr,     scen_d$cagr)),
  MDD_pct  = sprintf("%.2f", 100*c(scen_a_full$mdd, mega_mdd,
                                    scen_b$mdd,     scen_d$mdd)),
  DSR_post = sprintf("%.3f", c(scen_a_full$dsr_post_penalty,
                                mega_dsr_post,
                                scen_b$dsr_post_penalty,
                                scen_d$dsr_post_penalty)),
  stringsAsFactors = FALSE
)

s3_kv <- list(
  `MEGA_doc_remeasured_SR`     = sprintf("%.3f (Forge monthly resample of NAV_vdp)", mega_sr),
  `MEGA_doc_reported_SR`       = sprintf("%.3f (production performance.json)", mega_doc_sr),
  `MEGA_doc_DSR_raw`           = sprintf("%.3f", mega_dsr_raw),
  `MEGA_doc_DSR_post_penalty`  = sprintf("%.3f (penalty 0.75 = 15 cand × 0.05)", mega_dsr_post),
  `Fair_Delta_SR_vs_doc`       = sprintf("%+.3f (STR_1699 vs MEGA_doc same-period 243m)", fair_dsr),
  `Fair_Delta_CAGR_pp`         = sprintf("%+.2fpp (annual)", fair_cagr),
  `Fair_Delta_MDD_pp`          = sprintf("%+.2fpp", fair_mdd),
  `Recommended_Scenario`       = sprintf("%s", recommended),
  `Pure_Function_Hash_Audit`   = if (hash_pass) "PASS" else "FAIL"
)

s4_text <- sprintf(
  "Phase 4.5 보강 완료. REC-2 P1 (NAV-level real MEGA_doc 합성, cor=0.8 가정 폐기) + REC-3 P1 (MEGA_doc 동일 DSR penalty 0.75 적용). STR_1699 전기간 244m SR=%.3f CAGR=%.2f%% MDD=%.2f%% t_FF5=%.3f (Pre-LB SR=%.3f → OOS SR=%.3f boost 흡수). MEGA_doc(NAV_vdp) 재측정 SR=%.3f vs 보고 SR=%.3f. MEGA_doc DSR_post_penalty=%.3f (raw=%.3f - 0.75) → multi-testing fair basis robust. Same-period fair Δ SR=%+.3f (STR_1699 vs MEGA_doc 243m). Risk-adjusted 종합 점수 max → %s.",
  sr_full, cagr_full*100, mdd_full*100, t_ff5_full,
  sr_prelb, sr_oos,
  mega_sr, mega_doc_sr,
  mega_dsr_post, mega_dsr_raw,
  fair_dsr, recommended)

s5_bullets <- c(
  "Charts 2건 첨부: full_period_equity_curve(244m) + nav_level_scenario_comparison(A/B/D real-NAV)",
  "Real MEGA_05 NAV source: STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv:NAV_vdp (PG2 active)",
  "DSR 일관성 동일 basis: STR_1699 / MEGA_doc / Scen_A/B/D 모두 candidates_tried=15 penalty=0.75",
  "NAV-level synthesis: r_blend(t) = Σ w_i × r_i(t) (cor=0.8 closed-form approx 폐기)",
  sprintf("Pure Function v6.1 R12 hash audit: %s (3-package read-only verified)",
          if (hash_pass) "PASS" else "FAIL"),
  sprintf("판단 핵심: MEGA_doc DSR_post=%.3f vs STR_1699 full DSR_post=%.3f → robustness 직접 비교",
          mega_dsr_post, dsr_full),
  "Judge S6 ready: judge_ready.json phase45_full_period_nav_integration section 추가"
)

source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))

full_eq_path <- file.path(OUT_DIR, "full_period_equity_curve.png")
scen_path    <- file.path(OUT_DIR, "nav_level_scenario_comparison.png")

res <- tg_agent_brief(
  agent  = "Forge",
  title  = sprintf("STR_1699 %s Phase 4.5 Full-Period + NAV-Level Integration (REC-2/3)", WT_ID),
  sections = list(
    list(heading = "STR_1699 Full-Period Decomposition (244m)",
         type = "table", df = s1_df, emoji = "📈"),
    list(heading = "NAV-level Scenarios (REAL MEGA_05 documented NAV)",
         type = "table", df = s2_df, emoji = "🧬"),
    list(heading = "MEGA_05 Documented DSR + Fair Delta",
         type = "kv",   kv = s3_kv,  emoji = "⚖️"),
    list(heading = "Recommendation Rationale",
         type = "text", body = s4_text, emoji = "💡"),
    list(heading = "Audit + Next Step",
         type = "bullet", items = s5_bullets, emoji = "🔍")
  ),
  charts = c(full_eq_path, scen_path),
  footer = sprintf("Pure Function v6.1 R12 | Hash: %s | REC-2/3 P1 HIGH complete",
                   if (hash_pass) "PASS" else "FAIL"),
  force = TRUE
)
cat(sprintf("tg_agent_brief result: ok=%s bytes=%d\n",
            isTRUE(res$ok), res$bytes %||% 0L))
