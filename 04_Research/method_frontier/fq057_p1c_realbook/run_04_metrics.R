# =============================================================================
# FQ-057 NP4-P1c run_04: QLIKE/RMSE/MZ + paired DM(NW lag3) — 실 book SPLIT 재확인
#   포트: capw_mom_proxy(P1 replica) / real_book_fullinv / real_book_overlaid
#   창: full-range + recent-60m 하위창 별도.
#   판정: P1 (a)ADOPT/(b)KEEP 방향이 실 book에서 부호·유의 유지되는가.
#   Output: p1c_metrics.json
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "04_Research/method_frontier/fq057_p1_risk_accuracy/p1_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

P <- as.data.table(read_parquet(file.path(OUT_DIR, "p1c_pairs.parquet")))
ARMS_STRUCT <- c("lw_linear","lw_nls","ewma_struct")
ALL_ARMS <- c(ARMS_STRUCT, "ewma_direct")
RECENT_FROM <- 202007L    # 최근-60m 하위창 시작 홀딩월

make_wide <- function(pf, tg, arms, ymin=NULL) {
  s <- P[portfolio==pf & target==tg & arm %in% arms]
  if (!is.null(ymin)) s <- s[holding_ym >= ymin]
  w <- dcast(s, holding_ym + realized_var ~ arm, value.var="pred_var")
  need <- intersect(arms, colnames(w))
  w <- w[complete.cases(w[, ..need])]
  w[order(holding_ym)]
}
arm_summary <- function(w, arms) {
  rv <- w$realized_var; out <- list()
  for (a in arms) { pv <- w[[a]]; mz <- mz_reg(rv, pv)
    out[[a]] <- list(mean_qlike=round(mean_qlike(rv,pv),5),
      rmse_vol_ann=round(rmse_vol_ann(rv,pv,scale=12),5),
      median_pred_vol_ann=round(sqrt(median(pv))*sqrt(12),4),
      mz_a=round(mz$a,6), mz_b=round(mz$b,4), mz_r2=round(mz$r2,4)) }
  out }
dm_pair <- function(w, A, B, lag=3L) {
  rv <- w$realized_var; lA <- qlike_loss(rv,w[[A]]); lB <- qlike_loss(rv,w[[B]])
  r <- dm_nw(lA, lB, lag=lag)
  list(pair=paste0(A," - ",B), mean_qlike_diff=round(r$mean_d,5), dm_nw_t_lag3=round(r$t,4), n=r$n,
    verdict=if(is.na(r$t))"NA" else if(r$t<=-2)paste0(A,"_better") else if(r$t>=2)paste0(B,"_better") else "tie") }

eval_block <- function(pf, ymin=NULL) {
  out <- list()
  for (tg in c("te","total")) {
    w_all <- make_wide(pf, tg, ALL_ARMS, ymin)
    if (nrow(w_all) < 10L) { out[[tg]] <- list(n=nrow(w_all), note="insufficient_n"); next }
    out[[tg]] <- list(
      n=nrow(w_all), holding_range=range(w_all$holding_ym),
      realized_vol_ann=round(sqrt(median(w_all$realized_var))*sqrt(12),4),
      arm_summary=arm_summary(w_all, ALL_ARMS),
      paired=list(
        a_lwnls_vs_lwlinear    = dm_pair(w_all,"lw_nls","lw_linear"),
        lwnls_vs_ewma_struct   = dm_pair(w_all,"lw_nls","ewma_struct"),
        b_lwnls_vs_ewma_direct = dm_pair(w_all,"lw_nls","ewma_direct")))
  }
  out }

PFS <- c("capw_mom_proxy","real_book_fullinv","real_book_overlaid")
results_full <- setNames(lapply(PFS, eval_block), PFS)
results_recent <- setNames(lapply(PFS, function(pf) eval_block(pf, RECENT_FROM)), PFS)

# ---- SPLIT 판정: 각 실 book 변형에서 (a)/(b) 방향 유지 여부 ------------------
split_check <- function(res) {
  te <- res$te
  if (is.null(te$paired)) return(list(status="insufficient_n", n=te$n))
  a <- te$paired$a_lwnls_vs_lwlinear      # (a) lw_nls vs linear LW
  b <- te$paired$b_lwnls_vs_ewma_direct   # (b) lw_nls vs EWMA-direct
  a_holds <- (!is.na(a$dm_nw_t_lag3) && a$dm_nw_t_lag3 <= -2.0 && a$mean_qlike_diff < 0)
  # (b) KEEP EWMA = lw_nls가 EWMA-direct를 t<=-2로 유의 초과 '못함' (tie 또는 EWMA 우월)
  b_keep_holds <- !(!is.na(b$dm_nw_t_lag3) && b$dm_nw_t_lag3 <= -2.0)
  list(
    n=te$n,
    a_ADOPT_lwnls = list(dm_t=a$dm_nw_t_lag3, qlike_diff=a$mean_qlike_diff, verdict=a$verdict,
                         holds_vs_P1=a_holds, direction=if(a_holds)"CONFIRM_ADOPT_lw_nls" else "DIVERGE_from_P1_a"),
    b_KEEP_ewma   = list(dm_t=b$dm_nw_t_lag3, qlike_diff=b$mean_qlike_diff, verdict=b$verdict,
                         holds_vs_P1=b_keep_holds, direction=if(b_keep_holds)"CONFIRM_KEEP_ewma_direct" else "DIVERGE_lwnls_beats_ewma"))
}
split_full   <- setNames(lapply(PFS, function(pf) split_check(results_full[[pf]])), PFS)
split_recent <- setNames(lapply(PFS, function(pf) split_check(results_recent[[pf]])), PFS)

# 종합: 실 book(fullinv+overlaid) full-range에서 (a)/(b) 모두 유지면 SPLIT 확증
rb <- c("real_book_fullinv","real_book_overlaid")
a_all_hold <- all(sapply(rb, function(pf) isTRUE(split_full[[pf]]$a_ADOPT_lwnls$holds_vs_P1)))
b_all_hold <- all(sapply(rb, function(pf) isTRUE(split_full[[pf]]$b_KEEP_ewma$holds_vs_P1)))
overall <- if (a_all_hold && b_all_hold) "SPLIT_CONFIRMED_on_real_book" else
           if (a_all_hold && !b_all_hold) "a_CONFIRMED_b_DIVERGES" else
           if (!a_all_hold && b_all_hold) "a_DIVERGES_b_CONFIRMED" else "SPLIT_NOT_CONFIRMED"

metrics <- list(pin_tag="fq057_20260718_171024", measured_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  metric_type="risk_forecast_accuracy_diagnostic",
  loss="QLIKE(Patton 2011) primary; RMSE(vol_ann) + MZ b calibration",
  paired_test="Diebold-Mariano NW HAC lag3 on per-month QLIKE diffs (neg t = left arm better)",
  ewma_lambda=0.94, recent_window_from=RECENT_FROM,
  results_full_range=results_full, results_recent_60m=results_recent,
  split_verdict_full=split_full, split_verdict_recent=split_recent,
  overall_full_range=overall)
write_json(metrics, file.path(OUT_DIR,"p1c_metrics.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[done] run_04. overall(full):", overall, "\n")
for (pf in PFS) { s<-split_full[[pf]]
  if(!is.null(s$a_ADOPT_lwnls)) cat(sprintf("  %-20s a:%s (t=%s) | b:%s (t=%s) n=%s\n", pf,
    s$a_ADOPT_lwnls$direction, s$a_ADOPT_lwnls$dm_t, s$b_KEEP_ewma$direction, s$b_KEEP_ewma$dm_t, s$n))
  else cat(sprintf("  %-20s insufficient_n=%s\n", pf, s$n)) }
