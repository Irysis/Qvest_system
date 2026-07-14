## R35 finalize — alpha_package.json (mailbox) + alpha_scores.parquet + charts + lineage
suppressPackageStartupMessages({library(arrow);library(data.table);library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Sys.setenv(QM_ROOT=QM)
WT<-file.path(QM,"stage_artifacts/WT_D20260715_004"); R31<-file.path(QM,"stage_artifacts/WT_D20260714_007")
MB<-file.path(QM,"qepm/mailbox/worktask/WT_D20260715_004"); dir.create(MB,recursive=TRUE,showWarnings=FALSE)
save_safe<-function(o,p,w){tmp<-paste0(p,".tmp_",Sys.getpid());w(o,tmp);if(file.exists(p))file.remove(p);if(!file.rename(tmp,p))stop("rename")}
RES<-readRDS(file.path(WT,"r35_results.rds")); PIT<-readRDS(file.path(WT,"r35_pitstress.rds"))

## alpha_scores.parquet — SP aligned-z, all months (characterized signal)
SP7<-as.data.table(read_parquet(file.path(R31,"subaxis_panels.parquet")));SP7[,Date:=as.Date(Date)]
SC<-SP7[is.finite(SP),.(Date,Ticker,alpha_score=SP,factor="V20_SP_sales_yield")]
save_safe(SC,file.path(WT,"alpha_scores.parquet"),function(o,p)write_parquet(o,p))
asof<-max(SC$Date); latest<-SC[Date==asof]
setorder(latest,-alpha_score)
alpha_vec<-as.list(setNames(round(latest$alpha_score,4),latest$Ticker))
## confidence: rank-stability proxy = 1/(1+|z|) inverse? use normalized coverage-based flat 0.5 for screening
conf_vec<-as.list(setNames(rep(round(0.5,2),nrow(latest)),latest$Ticker))

alpha_package<-list(
  task_id="WT_D20260715_004", as_of_date=as.character(asof), forecast_horizon="1M",
  wt_type="discovery_screening_reroute",
  role_note="screening-tier consumption-face re-routing (NOT admission). SP characterized as OVERLAY_CANDIDATE feature. No covariance/weights (alpha-research role boundary). book_state unchanged.",
  alpha_vector=alpha_vec, confidence_vector=conf_vec,
  signal_matrix_ref="stage_artifacts/WT_D20260715_004/alpha_scores.parquet",
  factor_specs=list(list(
    factor_family="Value", proxy="Sales-to-Price (sales yield)", factor_id="V20_SP",
    formula="sales / market_cap (factor_db aligned Z_Score, C13 direction-aligned)",
    lag_rule="quarterly financials + off0 T-1 clean (factor_db month = AS_OF-1)",
    winsorization="factor_db standard", neutralization="per-month cross-sectional z within base membership",
    economic_rationale="sales-yield value premium — cyclical/deep-value tilt; distinct from earnings-multiple (EBIT/EV) axis (cross-corr 0.61 vs EBIT_EV). regime-dependent (dead 2015-19, revived 2020-23).",
    weight_theta=1.0, references=c("O'Shaughnessy sales-to-price","R31 FQ-047 value-definition-spectrum")
  )),
  diagnostics=list(
    canonical_port_t_nw_lag3=round(RES$part1$capw_pt,3),
    canonical_port_t_basis="cap-w KOSPI200 (authoritative); EW-universe diag below",
    ewuni_port_t_nw_lag3=round(RES$part1$ewuni_pt,3),
    ewuni_post2017_t=round(RES$part1$ewuni_post17,3),
    oos_retention_v2_ew=round(RES$part1$oos_ew,3),
    oos_retention_v2_capw=round(RES$part1$oos_capw,3),
    net_sr_ew=round(RES$part1$net_sr_ew,3), te_ann_ew=round(RES$part1$TE_ew,3),
    turnover_proxy=round(RES$part1$turnover,2),
    capacity_median_aum_bil_krw=round(RES$part1$capacity_bil,2),
    active_corr_ppure_base=round(RES$part1$corr_ppbase,3),
    active_corr_ppure_d2=round(RES$part1$corr_ppd2,3),
    holding_jaccard_ppure_base=round(RES$part1$jaccard_ppbase,3),
    pit_lag1_ewuni=round(PIT$lag1["ewuni"],3), placebo_p_emp=round(PIT$placebo_p,3),
    overlay_base_paired=round(RES$part2$ovl_base_paired,3),
    overlay_base_post2024_paired=round(RES$part2$ovl_base_post,3),
    overlay_incumbent_paired=round(RES$part2$ovl_bk_paired,3),
    overlay_incumbent_post2024_paired=round(RES$part2$ovl_bk_post,3),
    subperiod_pre2024_nw_t=round(RES$part3$pre24_nwt,3),
    subperiod_2024plus_nw_t=round(RES$part3$post24_nwt,3),
    sector_hhi_post2024=round(RES$part3$hhi_post,3),
    low_quality_ep_z_median=round(RES$part3$ep_med_sp,3)
  ),
  selection_objective="canonical_port_t",
  verdict_type="screen_tier_routed",
  challenge_flags=c(
    "C1 ACCEPT: SP '2024+ survival' = cap-w marginal frame artifact; standalone pre-2024-dominant (pre 2.51 / post 1.12). R31 narrative CORRECTED.",
    "C2 ACCEPT: EW-basis not deployable (cap-w bench mandate + capacity 0.5bil micro).",
    "C3 PARTIAL: low-quality trap not supported (EP-z median -0.016) but proxy only.",
    "C4 ACCEPT: 2024+ window n=29 thin -> single-regime label.",
    "C5 REBUTTAL: SP diversifying not redundant (corr<0.5 vs P-pure, Jaccard 0.064).",
    "C6 ACCEPT: overlay marginal pre-2024-only on BOTH base+incumbent = SP-specific decay."
  ),
  next_probe=c(
    "P1 SP regime-conditional input to RAMP (not standalone) — low-EV",
    "P2 value-definition-rotation tripwire re-scoped to SP absolute rolling-24m EW PORT_t sustained>2",
    "P3 SP signal in deployable cap-tier (MEGA/MID) — expected OTHER-localized"
  )
)
write_json(alpha_package,file.path(MB,"alpha_package.json"),pretty=TRUE,auto_unbox=TRUE,digits=6)
cat("alpha_package.json written:",file.path(MB,"alpha_package.json"),"\n")

## lineage
tryCatch({source(file.path(QM,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT_D20260715_004", package_type="alpha_package",
    method_selected="SP(V20 sales-yield) consumption-face re-routing (EW-basis + overlay + 2024+ robustness)",
    input_file_paths=c(file.path(R31,"subaxis_panels.parquet"),
      file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds")))
  cat("lineage recorded\n")}, error=function(e)cat("lineage skip:",conditionMessage(e),"\n"))
cat("R35_FINALIZE_DONE\n")
