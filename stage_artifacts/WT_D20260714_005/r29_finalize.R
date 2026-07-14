## R29 finalize — alpha_scores.parquet (clean Z6 primary blend) + alpha_package.json (diagnostic, screening FAIL) + lineage
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_005")
MB <- file.path(QM,"qepm/mailbox/worktask/WT_D20260714_005")
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}

PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(WT,"value_panels.parquet"))); VP[,Date:=as.Date(Date)]
DT <- merge(PAN[,.(Date,Ticker,base=`0_stored_S7`)], VP[,.(Date,Ticker,vz_off0)], by=c("Date","Ticker"), all.x=TRUE)
DT <- DT[is.finite(base)]
DT[,b_z:=zc(base),by=Date]; DT[,v_z:=zc(vz_off0),by=Date]; DT[is.na(v_z),v_z:=0]
DT[,alpha_z6_clean:=(1-0.30)*b_z+0.30*v_z]
AS <- DT[,.(Date,Ticker,base_score_clean=base,value_z_clean=vz_off0,alpha_z6_clean)]
save_safe(AS, file.path(WT,"alpha_scores.parquet"), function(o,p) write_parquet(o,p))
cat(sprintf("alpha_scores.parquet: %d rows %d months, last=%s\n", nrow(AS), uniqueN(AS$Date), as.character(max(AS$Date))))

## alpha_package.json (diagnostic — screening FAIL on PIT-clean basis, no dossier re-launch)
last_d <- max(AS$Date)
av <- av0 <- fromJSON(file.path(WT,"alpha_validation.json"))
pkg <- list(
  task_id = "WT-D20260714_005",
  as_of_date = "2026-07-14",
  forecast_horizon = "1M",
  wt_type = "discovery (measurement-integrity re-test — Z6 value blend PIT-clean re-verify)",
  verdict = "SCREENING FAIL (PIT-clean cap-w) — Z6 book-marginal 자본기여 미검증. R27 3.807=look-ahead-base 아티팩트. book_state 무변경. dossier 재발사 NO-GO(clean 기준).",
  factor_specs = list(list(
    factor_family = "Value (book-marginal 3rd axis)",
    proxy = "z-blend( z(V14_EBIT_EV) + z(V07_EV_EBITDA) ), w=0.30 over base score_eff",
    formula = "blend = 0.70*z(base_score_eff_clean) + 0.30*z(value_z_clean); value NA->0",
    lag_rule = "value = factor_db T-1 (off0, PIT-clean); base = 0_stored_S7 (recon off0, production _recompute convention)",
    winsorization = "2.5std (factor_db aligned z)",
    neutralization = "cross-sectional z per month; direction via align_factor_direction (V07 flipped, V14 kept)",
    economic_rationale = "현 PG2 북(Core Consensus + Defense quality/mom)에 순수 value 축 부재. V14/V07 준독립(cor 0.20) blend가 직교 value 정보 추가. PIT-clean cap-w에서 dIR+0.153·variant PORT_t 3.06->3.85·EW-uni pt 6.39로 실재하나 paired NW-t 1.24<2.0 (cap-w top-25 국소화 벽).",
    weight_theta = 0.30,
    redundancy_cluster_id = "value_ev_multiple (V14~V07 0.20 준독립; V02_EP 미채택 cor 0.66)",
    references = c("Fama-French 1993 (value)", "R27 WT-D20260714_003", "R28 WT-D20260714_004")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = 3.85,
    canonical_base_port_t_clean = 3.058,
    canonical_base_port_t_clean_ic = 3.247,
    paired_nw_t_vs_clean_base = 1.243,
    paired_is = 0.918, paired_ho = 1.075, paired_lag1 = 1.530,
    delta_ir_windowmatched = 0.153,
    post2017_t = 1.03,
    ewuni_port_t = 6.39, ewuni_oos_approx = 0.52,
    turnover_annual = 14.0,
    r27_reference_paired_LAbase = 3.807,
    r27_reproduction_paired = 3.738,
    metric_type = "canonical_screen (weighted_screen_bt cap-w top-25, NW lag-3) — admission binding 아님(forge authoritative)"
  ),
  selection_objective = "canonical_port_t",
  challenge_flags = c(
    "SCREENING FAIL: PIT-clean cap-w paired 1.02~1.72 < 2.0 (전 clean cell). AND-게이트(paired>=2.0 ∧ dIR>=0.05) 미충족.",
    "R27 Z6 3.807 = look-ahead-base 아티팩트(base off+1->off0 vintage swap 단독 2.2~2.6->1.0~1.3).",
    "value 신호 자체는 진짜·clean(vz_pfs=T-1 cor 1.0000, dIR+, EW-uni pt 6.39) — 'value dead' 아님, cap-tier 국소화 프론티어.",
    "seam 확정: 저장 268m 패널=전기간 균일 same-month(off+1) look-ahead; forward recompute=T-1 clean; value=T-1 clean.",
    "현직 book pinned 6.130 재해석 = 범위 밖(별도 judge 라운드 + FQ-044 후속)."
  )
)
save_safe(pkg, file.path(MB,"alpha_package.json"), function(o,p) write_json(o,p,pretty=TRUE,auto_unbox=TRUE))
cat("alpha_package.json (diagnostic) written to mailbox\n")

## lineage (write first done above -> now record)
tryCatch({
  source(file.path(QM,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260714_005", package_type="alpha_package",
    method_selected="Z6 value z-blend V14+V07 w0.30 PIT-clean re-measurement (screening FAIL)",
    input_file_paths=c(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"),
                       file.path(WT,"value_panels.parquet")))
  cat("lineage recorded\n")
}, error=function(e) cat("lineage skip:", conditionMessage(e), "\n"))
cat("FINALIZE_DONE\n")
