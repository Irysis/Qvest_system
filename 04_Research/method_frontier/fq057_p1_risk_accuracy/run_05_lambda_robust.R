# =============================================================================
# FQ-057 NP4-P1 run_05: λ=0.97 robustness 진단 (사전등록 이행 — 보고 전용, 선택 아님)
#   prereg ewma_lambda_note: "0.97(월간 관례)은 robustness 진단으로만 보고(선택 아님)"
#   + 실소비 정합: monitoring TE 기준선(qepm/observability/te_baseline)은 ewma97 —
#     decision B(KEEP ewma_direct)를 운용 λ에서 재확인할 필요.
#
#   재계산 arm: ewma_struct97 / ewma_direct97 (λ=0.94 판정 arm은 불변 — 저장값 소비)
#   parity 가드: ewma_struct λ=0.94 를 재계산해 p1_pairs 저장값과 대조 (fail-closed —
#     불일치 시 λ=0.97 수치 발행 중단. weights/유니버스 재구축 드리프트 방어)
#   Output: p1_lambda_robust.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_p1_risk_accuracy/p1_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

# ---- run_03 과 동일한 사전등록 고정 파라미터 --------------------------------
BOUNDS <- c(0, 0.20); MAX_NAMES <- 25L
LIQ_MIN <- 2e8; WIN <- 60L; MOM_FROM <- 11L; MOM_TO <- 1L
REB_FROM <- 200912L; REB_TO <- 202605L
LAM94 <- 0.94; LAM97 <- 0.97

# ---- 입력 (run_03 동일 소스 + 저장 pairs) -----------------------------------
mr    <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
liq   <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_liq_snapshot.parquet")))
PAIRS <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_pairs.parquet")))

Mw <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
yms <- Mw$ym
mat <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
ym_next <- function(y){ yy<-y%/%100L; mm<-y%%100L; if(mm==12L)(yy+1L)*100L+1L else y+1L }
for (i in seq_len(length(yms)-1L)) stopifnot(yms[i+1L]==ym_next(yms[i]))
reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]

cap_renorm <- function(w, cap = 0.20, iter = 50L) {
  for (i in seq_len(iter)) {
    over <- w > cap + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - cap); w[over] <- cap
    under <- !over & w > 0
    if (!any(under)) break
    w[under] <- w[under] + excess * w[under]/sum(w[under])
  }
  w / sum(w)
}

# ---- walk-forward: run_03 동일 유니버스/비중 재구축 + EWMA-struct 94/97 예측 --
pred_rows <- list(); t0 <- Sys.time()
for (t_ym in reb_months) {
  idx <- match(t_ym, yms); stopifnot(idx >= WIN)
  w_idx <- (idx - WIN + 1L):idx
  h_ym <- ym_next(t_ym)

  members <- snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= LIQ_MIN, Ticker]
  cand    <- intersect(intersect(members, liq_ok), colnames(mat))
  if (length(cand) < 40L) next
  sub60 <- mat[w_idx, cand, drop = FALSE]
  elig  <- cand[colSums(!is.na(sub60)) == WIN]
  if (length(elig) < 40L) next
  ret60 <- sub60[, elig, drop = FALSE]

  mom_rows <- (idx - MOM_FROM):(idx - MOM_TO)
  mom <- expm1(colSums(log1p(mat[mom_rows, elig, drop = FALSE])))
  z <- as.numeric(scale(mom)); names(z) <- elig
  top25 <- names(sort(z, decreasing = TRUE))[seq_len(min(MAX_NAMES, length(elig)))]

  w_ew   <- setNames(rep(1/length(top25), length(top25)), top25)
  sz     <- snap[ym == t_ym & Ticker %in% top25, .(Ticker, size)]
  szv    <- setNames(pmax(sz$size, 0), sz$Ticker)[top25]
  szv[is.na(szv)] <- 0
  w_capw <- if (sum(szv) > 0) cap_renorm(szv/sum(szv), BOUNDS[2]) else w_ew
  names(w_capw) <- top25

  szb <- snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
  szbv <- setNames(pmax(szb$size, 0), szb$Ticker)[elig]; szbv[is.na(szbv)] <- 0
  w_bench <- if (sum(szbv) > 0) szbv/sum(szbv) else setNames(rep(1/length(elig), length(elig)), elig)

  a_ew <- setNames(rep(0, length(elig)), elig); a_ew[names(w_ew)] <- a_ew[names(w_ew)] + w_ew
  a_ew <- a_ew - w_bench
  a_capw <- setNames(rep(0, length(elig)), elig); a_capw[names(w_capw)] <- a_capw[names(w_capw)] + w_capw
  a_capw <- a_capw - w_bench

  Sig94 <- est_ewma_struct_p1(ret60, LAM94)
  Sig97 <- est_ewma_struct_p1(ret60, LAM97)
  for (arm in c("ewma_struct94_chk", "ewma_struct97")) {
    Sig <- if (arm == "ewma_struct97") Sig97 else Sig94
    pred_rows[[length(pred_rows)+1L]] <- rbindlist(list(
      data.table(holding_ym=h_ym, portfolio="ew_top25",        target="total", arm=arm, pred_var=pred_var_qform(w_ew,   Sig)),
      data.table(holding_ym=h_ym, portfolio="capw_tilt_top25", target="total", arm=arm, pred_var=pred_var_qform(w_capw, Sig)),
      data.table(holding_ym=h_ym, portfolio="ew_top25",        target="te",    arm=arm, pred_var=pred_var_qform(a_ew,   Sig)),
      data.table(holding_ym=h_ym, portfolio="capw_tilt_top25", target="te",    arm=arm, pred_var=pred_var_qform(a_capw, Sig))))
  }
}
NEW <- rbindlist(pred_rows)
cat("[wf] new pred rows:", nrow(NEW), "(", round(as.numeric(difftime(Sys.time(),t0,units="mins")),1), "min )\n")

# ---- parity 가드 (fail-closed): 재계산 λ=0.94 struct vs 저장 p1_pairs --------
stored94 <- PAIRS[arm == "ewma_struct", .(holding_ym, portfolio, target, stored = pred_var)]
chk94    <- NEW[arm == "ewma_struct94_chk", .(holding_ym, portfolio, target, recomputed = pred_var)]
par <- merge(stored94, chk94, by = c("holding_ym","portfolio","target"))
stopifnot(nrow(par) == nrow(stored94), nrow(par) == nrow(chk94))
par[, rel_diff := abs(recomputed - stored) / pmax(abs(stored), .Machine$double.eps)]
max_rel <- par[, max(rel_diff)]
cat("[parity] ewma_struct λ=0.94 recompute vs stored: n =", nrow(par),
    " max_rel_diff =", format(max_rel, digits = 3), "\n")
if (!(max_rel < 1e-10)) stop("[parity FAIL] weights/유니버스 재구축 드리프트 — λ=0.97 수치 발행 중단 (fail-closed)")

# ---- ewma_direct λ=0.97: 저장 realized 시계열에서 재귀 (run_03 동일 규칙) ----
REAL <- unique(PAIRS[, .(holding_ym, portfolio, target, realized_var)])
ed_rows <- list()
for (pf in unique(REAL$portfolio)) for (tg in unique(REAL$target)) {
  sub <- REAL[portfolio==pf & target==tg][order(holding_ym)]
  state <- NA_real_; preds <- rep(NA_real_, nrow(sub)); nprior <- rep(0L, nrow(sub))
  for (i in seq_len(nrow(sub))) {
    preds[i] <- state; nprior[i] <- if (is.na(state)) 0L else i-1L
    rv_i <- sub$realized_var[i]
    state <- if (is.na(state)) rv_i else LAM97*state + (1-LAM97)*rv_i
  }
  ed_rows[[length(ed_rows)+1L]] <- data.table(
    holding_ym=sub$holding_ym, portfolio=pf, target=tg, arm="ewma_direct97",
    pred_var=preds, n_prior=nprior)
}
ED97 <- rbindlist(ed_rows)[!is.na(pred_var) & n_prior >= 12L][, n_prior := NULL]

# ---- 통합 wide + 손실/DM (run_04 make_wide 방식) ----------------------------
S97 <- NEW[arm == "ewma_struct97", .(holding_ym, portfolio, target, arm, pred_var)]
AUG <- rbindlist(list(
  PAIRS[, .(holding_ym, portfolio, target, arm, pred_var, realized_var)],
  merge(S97,  REAL, by = c("holding_ym","portfolio","target"))[, .(holding_ym, portfolio, target, arm, pred_var, realized_var)],
  merge(ED97, REAL, by = c("holding_ym","portfolio","target"))[, .(holding_ym, portfolio, target, arm, pred_var, realized_var)]
), use.names = TRUE)

ARMS_ALL <- c("lw_linear","lw_nls","ewma_struct","ewma_direct","ewma_struct97","ewma_direct97")
make_wide <- function(pf, tg, arms) {
  s <- AUG[portfolio==pf & target==tg & arm %in% arms]
  w <- dcast(s, holding_ym + realized_var ~ arm, value.var="pred_var")
  need <- intersect(arms, colnames(w))
  w <- w[complete.cases(w[, ..need])]
  w[order(holding_ym)]
}
arm_summary <- function(w, arms) {
  rv <- w$realized_var; out <- list()
  for (a in arms) {
    pv <- w[[a]]; mz <- mz_reg(rv, pv)
    out[[a]] <- list(mean_qlike = round(mean_qlike(rv, pv), 5),
                     rmse_vol_ann = round(rmse_vol_ann(rv, pv, scale=12), 5),
                     median_pred_vol_ann = round(sqrt(median(pv))*sqrt(12), 4),
                     mz_b = round(mz$b, 4))
  }
  out
}
dm_pair <- function(w, A, B, lag=3L) {
  rv <- w$realized_var
  r <- dm_nw(qlike_loss(rv, w[[A]]), qlike_loss(rv, w[[B]]), lag=lag)
  list(pair=paste0(A," - ",B), mean_qlike_diff=round(r$mean_d,5),
       dm_nw_t_lag3=round(r$t,4), n=r$n,
       verdict = if (is.na(r$t)) "NA" else if (r$t <= -2.0) paste0(A,"_better") else if (r$t >= 2.0) paste0(B,"_better") else "tie")
}

results <- list()
for (pf in c("capw_tilt_top25","ew_top25")) for (tg in c("te","total")) {
  key <- paste(pf, tg, sep="/")
  w_all <- make_wide(pf, tg, ARMS_ALL)                       # 6-arm 공통셋 (=4-arm 공통셋과 동일 예상)
  w_str <- make_wide(pf, tg, c("lw_nls","ewma_struct","ewma_struct97"))
  results[[key]] <- list(
    common_set = list(
      n = nrow(w_all), holding_range = if (nrow(w_all)>0) range(w_all$holding_ym) else NA,
      arm_summary = arm_summary(w_all, c("ewma_struct97","ewma_direct97","ewma_struct","ewma_direct","lw_nls")),
      paired = list(
        direct97_vs_direct94 = dm_pair(w_all, "ewma_direct97", "ewma_direct"),
        struct97_vs_struct94 = dm_pair(w_all, "ewma_struct97", "ewma_struct"),
        lwnls_vs_direct97    = dm_pair(w_all, "lw_nls", "ewma_direct97"),
        lwnls_vs_struct97    = dm_pair(w_all, "lw_nls", "ewma_struct97"))),
    structural_fullset = list(
      n = nrow(w_str),
      paired = list(lwnls_vs_struct97 = dm_pair(w_str, "lw_nls", "ewma_struct97"))))
}

# decision B robustness (λ=0.97 운용 기준선 정합 — 판정 rule 재적용, 보고 전용)
bp <- results[["capw_tilt_top25/te"]]$common_set$paired$lwnls_vs_direct97
b97 <- list(
  rule = "capw/te DM(lw_nls - ewma_direct97) t<=-2 ∧ diff<0 이면 λ=0.97에서도 lw_nls 우월 (판정 아님 — 보고)",
  dm_t = bp$dm_nw_t_lag3, qlike_diff = bp$mean_qlike_diff,
  consistent_with_decision_b_keep_ewma = !(bp$dm_nw_t_lag3 <= -2.0 && bp$mean_qlike_diff < 0))

out <- list(pin_tag = "fq057_20260718_171024",
            measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            purpose = "prereg ewma_lambda_note 이행 — λ=0.97 robustness 진단 (선택 아님·판정 불변). 운용 TE 기준선(te_baseline ewma97)과의 λ 정합 확인.",
            parity_guard = list(n = nrow(par), max_rel_diff = max_rel, pass = TRUE),
            lambda = list(judged = LAM94, robustness = LAM97),
            results = results,
            decision_b_at_lambda97 = b97)
write_json(out, file.path(OUT_DIR, "p1_lambda_robust.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[done] run_05 λ-robustness — decision_b_at_0.97 consistent_with_KEEP =",
    b97$consistent_with_decision_b_keep_ewma, "| dm_t =", bp$dm_nw_t_lag3, "\n")
