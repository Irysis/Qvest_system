## R31 finalize — alpha_scores.parquet (B2 csc per sub-axis) + alpha_validation.json + alpha_package.json
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_007")
MB <- file.path(QM,"qepm/mailbox/worktask/WT_D20260714_007")
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
W_BLEND<-0.30

PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
SP7 <- as.data.table(read_parquet(file.path(WT,"subaxis_panels.parquet"))); SP7[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds")); SIZE<-SI$SIZE
RG  <- as.data.table(read_parquet(file.path(WT,"subaxis_b2_grid.parquet")))
cormat <- readRDS(file.path(WT,"subaxis_corr.rds"))
AX <- c("BM","EP","CFP","FCF","SP","SHY","EBIT_EV")

DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`)], SP7[,c("Date","Ticker",AX),with=FALSE], by=c("Date","Ticker"), all.x=TRUE)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]

## build B2 csc per sub-axis -> long alpha_scores
sc_list <- list()
for(sx in AX){
  d<-copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,tier,b=`0_stored_S7`,v=get(sx))])
  d[,b_z:=zc(b),by=Date]; d[,v_z:=zc(v),by=Date]; d[is.na(v_z),v_z:=0]
  d[,v_boost:=fifelse(tier %in% c("MID","OTHER"),v_z,0)]; d[,csc:=(1-W_BLEND)*b_z+W_BLEND*v_boost]
  sc_list[[sx]]<-d[,.(Date,Ticker,subaxis=sx,tier,score_B2=csc,base_z=b_z,value_z=v_z)]
}
AS <- rbindlist(sc_list)
save_safe(AS, file.path(WT,"alpha_scores.parquet"), function(o,p) write_parquet(o,p))
cat(sprintf("alpha_scores rows=%d subaxes=%d\n", nrow(AS), uniqueN(AS$subaxis)))

## ---- verdict logic ----
gate_pass <- RG[AND_gate==TRUE, subaxis]
new_ax <- setdiff(AX,"EBIT_EV")
sp_row <- RG[subaxis=="SP"]
frontier_open <- RG[subaxis %in% new_ax & is.finite(paired_post2024) & paired_post2024>=1.5 & cor_active<0.5, subaxis]  # dossier branch
verdict <- if(length(setdiff(gate_pass,"EBIT_EV"))==0 && length(frontier_open)==0)
  "VALUE_DEFINITION_AXIS_CONFIG_SCOPED_EXHAUSTED (screening/cap-w). EBIT/EV uniquely gate-clearing; no new definition clears AND-gate nor escapes construction-bound incumbent redundancy. Recency NOT value-universal (SP/EP improve 2024+). Arc complete at cap-w book-marginal; SP=EW-basis frontier flag." else
  "FRONTIER_CANDIDATE_FOUND"

## ---- alpha_validation.json ----
av <- list(
  wt_id="WT_D20260714_007", round="R31", fq="FQ-047",
  as_of=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  metric_type="weighted_screen (cap-w top-25 paired NW-t lag3 vs clean base 0_stored_S7)",
  base_authority="production_parity_verified clean 0_stored_S7 (WT_004 recon_panels, off0 T-1, READ-ONLY 05_Production)",
  base_port_t=RG$base_port_t[1], base_ir=readRDS(file.path(WT,"base_ref.rds"))$base_ir,
  pin="R28_current_20260714",
  prereg_sha256=readLines(file.path(WT,"preregistration.sha256"))[1],
  parity_check=list(note="EBIT_EV B2 reproduces R30 exactly",
    r30_paired=2.378, r31_ebit_ev_paired=RG[subaxis=="EBIT_EV",paired_full],
    r30_dIR=0.232, r31_ebit_ev_dIR=RG[subaxis=="EBIT_EV",dIR_full],
    match=isTRUE(abs(RG[subaxis=="EBIT_EV",paired_full]-2.378)<0.01)),
  subaxis_grid=lapply(AX, function(sx){r<-RG[subaxis==sx]; list(
    subaxis=sx, definition=switch(sx, BM="Book-to-Market", EP="Earnings yield", CFP="Cash-flow yield",
      FCF="FCF yield", SP="Sales yield", SHY="Shareholder yield", EBIT_EV="EBIT/EV (CONTROL=R30)"),
    variant_port_t=round(r$variant_port_t,3), paired_full=round(r$paired_full,3),
    paired_pre2024=round(r$paired_pre2024,3), paired_post2024=round(r$paired_post2024,3),
    dIR_full=round(r$dIR_full,3), dIR_post2024=round(r$dIR_post2024,3),
    post2017_t=round(r$post2017_t,3), cor_active=round(r$cor_active,3),
    ewuni_port_t=round(r$ewuni_port_t,3), ewuni_oos=round(r$ewuni_oos,3),
    AND_gate=r$AND_gate)}),
  recency_finding="2024+ decay is DEFINITION-SPECIFIC not value-universal: EBIT_EV(2.21->0.92)+FCF(0.00->-0.52) decay; SP(0.99->1.85)+EP(0.77->1.33)+CFP(-0.03->0.79) IMPROVE post-2024",
  incumbent_redundancy_finding="cor_active uniformly high 0.86-0.93 across ALL definitions (even FCF whose value-signal cross-corr to EBIT_EV=0.07) => redundancy is CONSTRUCTION property (cap-w tier-tilt w=0.3 ~ base), NOT definition property. '실낱 EV' (less-redundant definition) FALSIFIED. Caveat: cor_active=screening proxy; risk-stage realized corr vs STR_1715 authoritative (moot, none gate-clear)",
  subaxis_corr_median=as.list(setNames(round(cormat["EBIT_EV",],3), colnames(cormat))),
  characterization=list(
    SP=readRDS(file.path(WT,"placebo_SP.rds"))[c("actual","p_emp","lag1")],
    EP=readRDS(file.path(WT,"placebo_EP.rds"))[c("actual","p_emp","lag1")]),
  gate_pass_subaxes=gate_pass, frontier_dossier_candidates=frontier_open,
  verdict=verdict,
  n_trials_this_round=7, selection_type="chain",
  value_family_cumulative_trials="~15 (R26-R30 ~8 + R31 7)",
  dsr_note="chain (each independent value definition, hypothesis-driven, not argmax). DSR gate not applied (measurement-graduation §3). multiple-testing disclosed in challenge_note.",
  pit=list(lag1_stress="SP lag1=2.147 (no collapse), EP lag1=1.006 (stable) => no same-month look-ahead; value vintage off0=T-1 clean (R29 parity)",
    c4_note="factor_db aligned-z is PIT-built with financial-statement lag; off0 vintage = month M = AS_OF-1"),
  prohibitions_respected=list(book_state="unchanged", production="read-only", insider_crawl="untouched", dart_api="not used", cov_weights="none (alpha-research role)")
)
save_safe(av, file.path(WT,"alpha_validation.json"), function(o,p) write_json(o,p,pretty=TRUE,auto_unbox=TRUE,digits=6))

## ---- alpha_package.json (canonical schema, screening negative) ----
dir.create(MB, showWarnings=FALSE, recursive=TRUE)
best_new <- RG[subaxis!="EBIT_EV"][order(-paired_full)][1]
ap <- list(
  task_id="WT_D20260714_007", as_of_date=as.character(Sys.Date()), forecast_horizon="1M",
  wt_type="discovery", selection_objective="canonical_port_t",
  alpha_vector=list(), confidence_vector=list(),  # screening-tier negative: no deployable alpha_vector emitted
  signal_matrix_ref="stage_artifacts/WT_D20260714_007/alpha_scores.parquet",
  factor_specs=lapply(AX, function(sx){list(
    factor_family="Value", proxy=sx,
    formula=switch(sx, BM="V01_BM aligned-z", EP="V02_EP", CFP="V03_CFP", FCF="V10_FCF_Yield",
      SP="V20_SP", SHY="V11_Shareholder_Yield (sparse)", EBIT_EV="V14_EBIT_EV+V07_EV_EBITDA blend (control)"),
    construction="B2 non-mega tier-conditional tilt: csc=0.7*base_z + 0.3*(value_z if tier in {MID,OTHER} else 0)",
    lag_rule="off0 T-1 clean (factor_db month M)", neutralization="per-month cross-sectional z",
    economic_rationale="value risk-premium / mispricing; tested whether definition escapes EBIT/EV 2024+ decay + incumbent redundancy",
    variant_port_t=RG[subaxis==sx,variant_port_t], paired_vs_base=RG[subaxis==sx,paired_full])}),
  diagnostics=list(
    canonical_port_t_nw_lag3=RG[subaxis=="SP",ewuni_port_t],  # best new EW-uni (non-binding diag)
    canonical_note="value_screening: cap-w authoritative paired; EW-uni diag non-binding",
    base_port_t=RG$base_port_t[1],
    best_new_definition=best_new$subaxis, best_new_paired=best_new$paired_full,
    ebit_ev_control_paired=RG[subaxis=="EBIT_EV",paired_full],
    gate_pass=gate_pass),
  challenge_flags=list(
    "SCREENING_NEGATIVE: no new value definition clears cap-w AND-gate (paired>=2.0); EBIT/EV uniquely gate-clearing",
    "RECENCY_NUANCE: 2024+ decay is definition-specific (EBIT_EV/FCF decay; SP/EP/CFP improve) — not value-universal",
    "INCUMBENT_REDUNDANCY_CONSTRUCTION_BOUND: cor_active ~0.9 for all (even orthogonal FCF signal) => '실낱 EV' falsified",
    "SP_FRONTIER: sales-yield only definition improving 2024+ (post24 1.85, EW-uni 6.60, oos 0.61, placebo p=0.025) but cap-w gate fail = cap-w localization -> EW-basis frontier flag",
    "LOW_EV_MULTIPLE_TESTING: value family cumulative ~15 trials; chain justification + DSR diagnostic"),
  verdict=verdict)
save_safe(ap, file.path(MB,"alpha_package.json"), function(o,p) write_json(o,p,pretty=TRUE,auto_unbox=TRUE,digits=6))

## lineage (after write)
tryCatch({source(file.path(QM,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT_D20260714_007", package_type="alpha_package",
    method_selected="R31 value-definition spectrum x B2 tier-conditional (7 sub-axes, screening negative)",
    input_file_paths=c(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"),
      file.path(WT,"subaxis_panels.parquet")))}, error=function(e) cat("lineage skip:",conditionMessage(e),"\n"))

cat("\nVERDICT:", verdict, "\n")
cat("gate_pass:", paste(gate_pass,collapse=","), "| frontier_dossier:", paste(frontier_open,collapse=","), "\n")
cat("FINALIZE_DONE\n")
