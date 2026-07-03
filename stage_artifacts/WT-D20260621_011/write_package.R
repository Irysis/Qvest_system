# WT-D20260621_011 — assemble alpha_package_draft.json + alpha_validation.json + alpha_scores.parquet
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
MBX  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260621_011")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a

X <- readRDS(file.path(OUT,"scored.rds")); best<-X$best
A <- readRDS(file.path(OUT,"analysis.rds"))
H <- readRDS(file.path(OUT,"holdout.rds"))
CAL <- readRDS(file.path(OUT,"calmar.rds"))
gridR <- fread(file.path(OUT,"is_grid.csv"))

# alpha_scores.parquet: latest sig month score vector (as-of 2026-06) for the IS-selected config
S <- X$S; build_scores<-X$build_scores
sc <- build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda); setkey(sc,NULL)
latest <- sc[Date==max(sc$Date)]
write_parquet(latest, file.path(OUT,"alpha_scores.parquet"))

# alpha_vector / confidence (latest month) — alpha-hat only
av <- setNames(as.list(round(latest$score,5)), latest$Ticker)
cv <- setNames(as.list(rep(0.15, nrow(latest))), latest$Ticker)  # low confidence: negative-validated alpha

ages <- A$ages; dec <- A$dec_ts; ortho <- A$ortho; eras <- A$eras; brd <- A$brd; gap <- A$gap

diagnostics <- list(
  metric_type = "canonical_screen",
  metric_type_note = "canonical_screen_bt() -> contract build_benchmark_compare (NW lag-3). admission binding은 forge build_bt_result. proxy 손계산 없음.",
  selection_type = "sweep",
  n_trials = 144L,
  n_trials_note = "2(A_lag)x4(A_max)x3(tau)x3(lambda)x2(top_n)=144 explicit grid -> sweep. DSR HARD 적용 대상이나 0/72 PIT-valid이 pt>0이라 무의미(모두 음수).",
  portfolio_alpha_t_nw_lag3_IS    = round(H$is$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_nw_lag3_HOLDOUT = round(H$holdout$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_nw_lag3_FULL  = round(H$full$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_nw_lag3_PLACEBO = round(H$placebo$portfolio_alpha_t_nw_lag3,3),
  net_sr_full = round(H$full$net_sr,3),
  information_ratio_full = round(H$full$information_ratio,3),
  turnover_annual = round(H$full$turnover_annual,2),
  calmar_full = round(CAL$calmar,3),
  mdd_full = round(CAL$mdd,3),
  cagr_full = round(CAL$cagr,3),
  rank_ic = NA, rank_ic_note = "본 알파는 binary 이벤트 sleeve(연속 score는 freshness-decay) — cross-sectional rank-IC 대신 decile term-structure + portfolio-alpha t를 권위 진단으로 사용(measurement-graduation §2).",
  decile_D10_mean_active = round(dec[dec==10,mean_active],5),
  decile_D10_t_nw = round(dec[dec==10,t_nw],3),
  decile_D10_D9_gap_mean = round(mean(gap$d),5),
  decile_monotonicity_note = "단조성 없음 — D10(가장 fresh/high-footprint inclusion)가 -0.18%/mo로 최하위. top-concentration 역전.",
  pit_valid_configs_pt_positive = 0L,
  pit_valid_configs_total = 72L,
  era_2005_2014_pt = eras[era=="2005-2014",pt],
  era_2015_2026_pt = eras[era=="2015-2026",pt],
  cohort_breadth_mean = round(mean(brd$n_eligible),1),
  cohort_breadth_median = median(brd$n_eligible),
  cohort_months_under_25 = nrow(brd[n_eligible<25]),
  cohort_months_total = nrow(brd)
)

age_ts <- lapply(seq_len(nrow(ages)), function(i)
  list(age=ages$age[i], mean_active=round(ages$mean_active[i],5), t_nw=round(ages$t_nw[i],3), n=ages$n[i]))

orthogonality <- lapply(seq_len(nrow(ortho)), function(i)
  list(factor=ortho$factor[i], corr_active=round(ortho$corr_active[i],3),
       target=ortho$target[i], pass=as.logical(ortho$pass[i]), basis="active(-BM)"))

challenge_flags <- list(
  list(id="RF-NEG-1", severity="HIGH",
       note="0/72 PIT-valid(A_lag=1) configs have positive portfolio-alpha t. Best PIT-valid IS pt=-0.282, Holdout pt=-1.033, Full pt=-0.885. KR index-inclusion drift is NEGATIVE at/after the effective date."),
  list(id="RF-PIT-1", severity="HIGH",
       note="Membership panel is EFFECTIVE-date only (month-end state). The frontrun alpha lives BEFORE effective (announcement ~2-4wk prior) and is UNOBSERVABLE in this data. A_lag=0 (borderline, announcement-assumed) is sensitivity-only and ALSO negative (best -0.121). No frontrun window was manufactured from effective-date flags."),
  list(id="RF-PLACEBO-1", severity="HIGH",
       note="Placebo (inclusion months shifted +6) Full pt=-0.738, indistinguishable from real config -0.885. No catalyst-specific signal exists to destroy."),
  list(id="RF-ORTHO-MOM", severity="MEDIUM",
       note="corr_active vs momentum(12-1)=0.798 (FAIL<0.35): inclusion sleeve is largely momentum re-packaging (included names ran up before inclusion). corr vs ST-reversal=0.672 (newly-included names mean-revert). Size corr=0.048 PASS (NOT a size-beta artifact)."),
  list(id="RF-LUMPY-1", severity="MEDIUM",
       note="Cohort breadth mean 21.9/median 19 names; 155/254 months (61%) have <25 eligible -> book chronically under-filled & lumpy (inclusions cluster Jun=205/Dec=42). A_max=3 (purest catalyst)=8.8 names/mo, turnover ~11x.")
)

factor_specs <- list(list(
  factor_family="EventDriven_IndexInclusion",
  proxy="freshness_decay x passive_footprint (Size/ADV)",
  formula="score = exp(-age/tau) * (1 + lambda*footprint); footprint = xs_zscore(log(w_idx/ADV21)); w_idx=Size/sum(Size); eligible iff age in [A_lag,A_max] & member(K200uKQ150) & not(Admin/Halt/Unfaithful)",
  lag_rule="membership EFFECTIVE-date panel, A_lag=1 (effective+1M) for PIT-safety; Size/ADV from t-1 month-end",
  winsorization="none (footprint xs-zscore)",
  neutralization="none (raw event sleeve)",
  economic_rationale="Index addition = forced passive + benchmark-tracker buying = mechanical price pressure (Shleifer 1986 downward-sloping demand; Chen-Noronha-Singal 2004 index effect). Exogenous threshold-crossing event (committee-driven), decoupled from good-news/run-up mean-reversion confound. AX-007 buy-side escape.",
  weight_theta=1.0,
  references=c("Shleifer 1986 JF","Chen-Noronha-Singal 2004 JF","Harris-Gurel 1986")
))

pkg <- list(
  task_id="WT-D20260621_011",
  as_of_date="2026-06-21",
  forecast_horizon="1M",
  wt_type="discovery",
  hypothesis_title="Index Inclusion Frontrun Drift",
  verdict="NEGATIVE_VALIDATED",
  verdict_summary="KR index-inclusion drift is NEGATIVE under PIT (effective-date panel). 0/72 PIT-valid configs positive; freshest cohort (age 0-2) most negative (-0.9 to -1.5%/mo); placebo indistinguishable; era 2015-2026 pt=-1.49 (inverted, not just decayed); momentum corr 0.80 (re-packaging). Frontrun window unobservable (announcement dates absent). NOT graduable; NOT a viable overlay/sleeve (negative+lumpy). Honest finding: even the cleanest EXOGENOUS mechanical-demand event does not translate to KR long-only top-25 — the index effect runs up BEFORE the (unobservable) effective date and mean-reverts after.",
  screen_route="NONE",
  screen_route_note="Not OVERLAY/FR/DPL candidate: portfolio-alpha t negative across all windows AND momentum-redundant (corr 0.80) AND lumpy. A DPL feature must carry residual signal; this carries negative, momentum-collinear, mean-reverting signal. L-code VALIDATED_HARD_FAIL.",
  selection_objective="subperiod_stability",
  alpha_vector=av,
  confidence_vector=cv,
  signal_matrix_ref="stage_artifacts/WT-D20260621_011/alpha_scores.parquet",
  factor_specs=factor_specs,
  diagnostics=diagnostics,
  age_term_structure=age_ts,
  orthogonality=orthogonality,
  pit_handling=list(
    panel_date_semantics="EFFECTIVE-date only (monthly month-end membership state in us_k200/us_kq150.parquet). 640 K200 + 342 KQ150 0->1 transitions. Inclusions cluster Jun(205)/Dec(42) = KRX semi-annual rebalance.",
    pit_valid_window="A_lag=1 (hold from effective+1M). This is the ONLY config cited for the verdict.",
    pit_borderline_window="A_lag=0 (effective month) = sensitivity-only (assumes announcement known at effective-21d). Also negative (best -0.121). NOT used for verdict.",
    frontrun_window="UNAVAILABLE — announcement dates absent from data. Pre-effective frontrun alpha (the genuinely profitable window per literature) cannot be tested without fabricating look-ahead. Explicitly NOT manufactured.",
    checks="C1 (xs zscore per month, IS-only grid select), C2/C5 (score uses m-1 observables, forward return from m+1), C10 (liq adv t-1 21d), C13 (score>=0 always), C14/C15 (RAWDATA+membership carve-out, no Factor DB factor)."
  ),
  challenge_flags=challenge_flags,
  method_shopping_log=list(candidates_tried=1L, method_log=list(
    list(name="IndexInclusion_freshness_footprint", selected=TRUE, note="single hypothesis, grid is hyperparameter sweep not method shopping"))),
  data_inputs=c(".cache/universe_support/us_k200.parquet",".cache/universe_support/us_kq150.parquet",
                ".cache/RAWDATA.parquet",".cache/benchmark.parquet")
)

write_json(pkg, file.path(MBX,"alpha_package_draft.json"), pretty=TRUE, auto_unbox=TRUE, na="null")

# alpha_validation.json
val <- list(
  task_id="WT-D20260621_011",
  verdict="NEGATIVE_VALIDATED",
  metric_type="canonical_screen",
  is_grid=list(n_configs=144L, pit_valid_n=72L, pit_valid_pt_positive=0L,
               pit_valid_best_pt=round(max(gridR[A_lag==1]$pt),3),
               pit_valid_worst_pt=round(min(gridR[A_lag==1]$pt),3),
               borderline_a_lag0_best_pt=round(max(gridR[A_lag==0]$pt),3)),
  holdout=list(is_pt=round(H$is$portfolio_alpha_t_nw_lag3,3),
               holdout_pt=round(H$holdout$portfolio_alpha_t_nw_lag3,3),
               full_pt=round(H$full$portfolio_alpha_t_nw_lag3,3),
               placebo_pt=round(H$placebo$portfolio_alpha_t_nw_lag3,3),
               full_net_sr=round(H$full$net_sr,3), full_calmar=round(CAL$calmar,3),
               full_mdd=round(CAL$mdd,3), full_turnover=round(H$full$turnover_annual,2)),
  graduation_gate=list(portfolio_alpha_t_nw_hard_2.95="FAIL (-0.885)",
                       calmar_hard_0.64="FAIL (0.023)",
                       oos_retention_0.7="N/A (both signs negative)",
                       overall="HARD FAIL on all substantive gates"),
  era_stability=list(era_2005_2014_pt=eras[era=="2005-2014",pt],
                     era_2015_2026_pt=eras[era=="2015-2026",pt],
                     interpretation="effect inverted over time (arbitraged away / front-run earlier)"),
  orthogonality_active=setNames(round(ortho$corr_active,3), ortho$factor),
  cohort_breadth=list(mean=round(mean(brd$n_eligible),1), median=median(brd$n_eligible),
                      months_under_25=nrow(brd[n_eligible<25]), months_total=nrow(brd)),
  universe_comparison="not run — KR_top342 effective-date PIT already produces robust negative; v2 universe would not rescue a negative+momentum-redundant sleeve."
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")

cat("WROTE alpha_package_draft.json, alpha_validation.json, alpha_scores.parquet\n")
cat("latest-month eligible names (top-25 candidates):", nrow(latest), "\n")
