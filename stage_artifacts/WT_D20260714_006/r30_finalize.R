## R30 finalize — alpha_package.json (latest-month B2 alpha_vector) + lineage
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_006")
MB <- file.path(QM,"qepm/mailbox/worktask/WT-D20260714_006")
AS <- as.data.table(read_parquet(file.path(WT,"alpha_scores.parquet")))
SIZE <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))$SIZE
liqf <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))$liqf
d_last <- max(AS$Date)
## latest-month B2 cap-w top-25 (alpha_vector = expected active proxy = z-score of B2 slotting score; confidence from cross-sec rank stability)
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
sub <- merge(AS[Date==d_last,.(Ticker,score=score_B2_nonmega,tier,cap_rank)], SIZE[Date==d_last,.(Ticker,Size)], by="Ticker")
sub <- merge(sub, liqf[Date==d_last,.(Ticker,adv)], by="Ticker", all.x=TRUE); sub <- sub[is.na(adv)|adv>=2e8]
setorder(sub,-score); top <- head(sub,25); top[,w:=cap_norm(Size)]
alpha_vec <- as.list(setNames(round(top$score,4), top$Ticker))
## confidence: sigmoid of score rank stability proxy (coverage + within-universe percentile); simple: normalized rank
top[, conf := round(pmin(1, pmax(0.3, 0.5 + 0.5*(score-mean(sub$score))/sd(sub$score)/3)),3)]
conf_vec <- as.list(setNames(top$conf, top$Ticker))

pkg <- list(
  task_id="WT-D20260714_006", frontier_id="FQ-045", as_of_date="2026-07-14", forecast_horizon="1M",
  wt_type="discovery (consumption-form re-measurement)",
  alpha_vector=alpha_vec, confidence_vector=conf_vec,
  signal_matrix_ref="stage_artifacts/WT_D20260714_006/alpha_scores.parquet",
  factor_specs=list(
    list(factor_family="Value", proxy="V14_EBIT_EV + V07_EV_EBITDA (aligned z-blend)",
         formula="score_B2 = 0.7*z(base_stored_S7) + 0.3*z(value)*1[cap_rank>=11]  (non-mega tier-conditional value slotting)",
         lag_rule="factor_db T-1 (off0 clean, production_parity_verified)", winsorization="cross-sectional z (no explicit winsor; factor_db aligned z)",
         neutralization="none (cap-tier conditional gating, not neutralization)", economic_rationale="value_risk_premium localized to non-mega tier — mega는 value signal-dead(project-captier-alpha-localization)이므로 value 틸트를 non-mega(11+)에만 적용해 marginal 희석 회피",
         weight_theta=0.30, references=c("R29 verdict","project-captier-alpha-localization-20260706","reference-kr-value-factor-decay")),
    list(factor_family="Composite base (incumbent)", proxy="STR_1715 7-factor sleeve (core Consensus + M08 momentum)",
         formula="0_stored_S7 stored theta (0.25x4 core EW)", lag_rule="off0 T-1 clean",
         winsorization="per production", neutralization="per production", economic_rationale="incumbent book base (read-only, unchanged)",
         weight_theta=0.70, references=c("STR_1715_on_M4_R05_noLayer4_PG2"))
  ),
  diagnostics=list(
    canonical_port_t_nw_lag3=4.234,   # B2 cap-w variant absolute (weighted_screen) — decision metric = paired 2.378
    canonical_port_t_note="cap-w variant absolute 4.234. **결정 지표 = paired NW-t 2.378 (variant active - clean-base active, AND-게이트)**. EW-uni diag = 6.588.",
    capw_paired_nw_lag3=2.378, capw_paired_is=2.096, capw_paired_ho=1.170, delta_ir_full=0.232, delta_ir_ho=-0.022,
    post2017_t=1.734, paired_lag1=2.473, placebo_p=0.000, placebo_null_max=1.104,
    capw_oos_v2_variant=0.452, paired_diff_oos_v2=2.326,
    ewuni_port_t=6.588, ewuni_oos=0.512,
    rank_ic=NA, icir=NA, monotonicity=NA, subperiod_stability=NA, harvey_t_stat=NA,
    turnover_proxy=0.14, n_months=268,
    metric_type="weighted_screen (cap-w top-25, NW lag-3) — admission binding 아님(forge authoritative). advisory rank-IC 계열 미산출(canonical PORT_t 1급)."
  ),
  selection_objective="canonical_port_t",
  selection_type="chain", n_trials_r30=4, n_trials_value_family_cumulative="~8 (R26-R30)",
  verdict="Branch B2 CONFIG-SCOPED POSITIVE (screening AND-게이트 full-period, paired 2.378·ΔIR 0.232) — cap-w 국소화 벽 최초 관통, placebo/lag/PIT-robust, cap-tier 국소화 방향 확증. 단 자본 아님(holdout dIR -0.022·post2017 1.73·variant oos 0.452 = 최근 marginal 감쇠, screening-tier). Branch A pure-value EW = 독립 페이퍼트래킹 3호 부적격(P-pure active-corr 0.50 redundant).",
  challenge_flags=list(
    "B2 게이트 관통 = IS/pre-2017 견인, holdout dIR -0.022 (최근 marginal 감쇠) — 자본 NO-GO",
    "value_quality_spread 백분위 0.175 (06-24 사상최대서 압축) = 늦은-사이클 리스크, forward value 하향",
    "B2 marginal = OTHER(소형) 소가중(wMID 0.062) tail 증폭 — 구현성 미검증(next_probe P2)",
    "Branch A EW-트랙 실투자 벤치 mandate 부재 + pure-value P-pure 중복(corr 0.50) — 독립 트랙 부적격",
    "metric_type=weighted_screen (cap-w screening) — forge graduation HARD 3종 미검증"
  ),
  role_boundary="alpha-only. 공분산/target weights 미산출(cap-w = 고정 screening 규격, R29 동일 precedent). book_state·05_Production·outputs/ramp 무변경.",
  pin_tag="R28_current_20260714", prereg_sha256="bc3d2dfd6528a037b6005a7906a5b445a0e055eecc733db6cd9752d34af3ac04"
)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("alpha_package.json written. latest month:",as.character(d_last)," top-25 B2 names:",nrow(top),"\n")
cat("top5:",paste(top$Ticker[1:5],collapse=","),"\n")

## lineage (after write)
tryCatch({
  source(file.path(QM,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260714_006", package_type="alpha_package",
    method_selected="R30 B2 non-mega tier-conditional value slotting (0.7 base + 0.3 value*1[cap_rank>=11])",
    input_file_paths=c(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"),
                       file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"),
                       file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds")))
  cat("lineage recorded\n")
}, error=function(e) cat("lineage skip:",conditionMessage(e),"\n"))
cat("FINALIZE_DONE\n")
