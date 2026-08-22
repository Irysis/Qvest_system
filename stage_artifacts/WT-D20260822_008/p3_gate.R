## WT-D20260822_008 (FQ-246 NP2) P3 — 전도성 → 본 측정 → paired 대조
## ★판정 순서(사전등록): ①전도성 실증 → ②정답지별 게이트 → ③정답지 교체 paired
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); PRE <- fromJSON(file.path(OUT,"PREREG.json"))
K <- P1$K; NM <- P1$NM; CRIT <- P1$CRIT; icm <- P1$icm; RBF <- P1$ret_by_factor
DIRS <- P1$DIRS; AM <- P1$AM; months <- P1$months; A4 <- P1$A4
ic_best <- P1$ic_best; ret_best <- P1$ret_best
MDE_HIT <- PRE$MDE_precomputed$marginal_hit_binom_1s5pct
MDE_HIT2<- PRE$MDE_precomputed$top2_hit_binom_1s5pct
MDE_D2S <- PRE$MDE_precomputed$paired_dhit_mde_2s

## ---------- 공통 통계 엔진 ----------
top2_set <- lapply(seq_len(NM), function(m){ x <- RBF[m,]; x[!is.finite(x)] <- -Inf
  order(x, decreasing=TRUE)[1:2] })
selval_of <- function(am) { v <- vapply(seq_len(NM), function(m){
  if (is.na(am[m])) return(NA_real_); b <- RBF[m,]; ok <- is.finite(b)
  RBF[m, am[m]] - mean(b[ok]) }, 0); v[is.finite(v)] }
gate_row <- function(am, keyvec, keyM, critM, dec, lab, key_lab) {
  ok <- !is.na(am); n <- sum(ok); idx <- which(ok)
  hits <- am[idx] == keyvec[idx]; hit <- mean(hits)
  bt <- binom.test(sum(hits), n, p=1/K, alternative="greater")
  h2v <- vapply(idx, function(m) am[m] %in% top2_set[[m]], TRUE); h2 <- mean(h2v)
  bt2 <- binom.test(sum(h2v), n, p=2/K, alternative="greater")
  rho <- if (is.null(critM)) rep(NA_real_, NM) else vapply(seq_len(NM), function(m){
    a <- critM[m,]; b <- keyM[m,]; o <- is.finite(a) & is.finite(b)
    if (sum(o) < 3L || sd(a[o]) == 0) return(NA_real_); cor(rank(a[o]), rank(b[o])) }, 0)
  rr <- rho[is.finite(rho)]; if (!is.null(critM) && !dec) rr <- -rr
  sv <- selval_of(am)
  data.table(criterion=lab, key_id=key_lab, n=n, hit=hit, hit_p=bt$p.value,
    hit_excess_pp=(hit-1/K)*100, hit2=h2, hit2_p=bt2$p.value,
    rho=if(length(rr)) mean(rr) else NA_real_,
    rho_t=if(length(rr)) .nw_t_mean(rr, lag=3L) else NA_real_,
    rho_mde95=if(length(rr)) 1.96*sd(rr)/sqrt(length(rr)) else NA_real_,
    selval_ann_pct=mean(sv)*12*100, selval_t=.nw_t_mean(sv, lag=3L)) }

cat("################ (1) 전도성 실증 — 게이트가 존재하는 정보를 검출하는가 ################\n")
set.seed(20260822L)
noise_add <- function(M, sd_mult) { S <- apply(M, 1, function(x) sd(x[is.finite(x)]))
  M + matrix(rnorm(length(M)), nrow=nrow(M)) * (S*sd_mult) }
N05 <- noise_add(RBF,0.5); N15 <- noise_add(RBF,1.5); N40 <- noise_add(RBF,4.0)
amax <- function(M) apply(M, 1, function(x){ x[!is.finite(x)] <- -Inf; which.max(x) })
COND <- rbindlist(list(
  gate_row(amax(RBF), ret_best, RBF, RBF, TRUE, "POSCTRL_oracle_self_RET", "RET"),
  gate_row(amax(N05), ret_best, RBF, N05, TRUE, "POSCTRL_oracle_noise0.5", "RET"),
  gate_row(amax(N15), ret_best, RBF, N15, TRUE, "POSCTRL_oracle_noise1.5", "RET"),
  gate_row(amax(N40), ret_best, RBF, N40, TRUE, "POSCTRL_oracle_noise4.0", "RET"),
  gate_row(sample.int(K, NM, replace=TRUE), ret_best, RBF, NULL, TRUE, "NEGCTRL_uniform_random", "RET"),
  gate_row(amax(icm), ic_best, icm, icm, TRUE, "POSCTRL_oracle_self_IC", "IC")))
COND[, gate_raw := hit_p < 0.05 | (is.finite(rho_t) & abs(rho_t) >= 1.5)]
print(COND[, .(criterion, key_id, n, hit=round(hit,4), hit_p=signif(hit_p,3),
               rho=round(rho,4), rho_t=round(rho_t,3), selval=round(selval_ann_pct,3), gate_raw)])
cat(sprintf("\n[전도성] 양성 대조 발화 %d/4 · 음성 대조 미발화 = %s\n",
    sum(COND[grepl("^POSCTRL_oracle_(self_RET|noise)", criterion), gate_raw]),
    !COND[criterion=="NEGCTRL_uniform_random", gate_raw]))

cat("\n################ (2) 본 측정 — 기준 8방향 × 정답지 2종 ################\n")
CN_of <- function(nmd) DIRS[[nmd]][[1]]; DEC_of <- function(nmd) DIRS[[nmd]][[2]]
MAIN <- rbindlist(c(
  lapply(names(DIRS), function(nmd) gate_row(AM[[nmd]], ic_best, icm, CRIT[,,CN_of(nmd)], DEC_of(nmd), nmd, "IC")),
  lapply(names(DIRS), function(nmd) gate_row(AM[[nmd]], ret_best, RBF, CRIT[,,CN_of(nmd)], DEC_of(nmd), nmd, "RET"))))
am_sel1 <- rep(1L, NM)
prev_win_name <- c(NA_character_, vapply(seq_len(NM-1), function(m)
  A4$sel_rank[[months[m]]][ ret_best[m] ], ""))
am_lag1 <- vapply(seq_len(NM), function(m){ if (is.na(prev_win_name[m])) return(NA_integer_)
  i <- match(prev_win_name[m], A4$sel_rank[[months[m]]]); if (is.na(i)) NA_integer_ else as.integer(i) }, 0L)
cat(sprintf("lag1_winner 가용 월 = %d/%d (전월 승자가 당월 K 에 잔류 %.4f)\n",
            sum(!is.na(am_lag1)), NM, mean(!is.na(am_lag1))))
CTRL <- rbindlist(list(
  gate_row(am_sel1, ic_best,  icm, NULL, TRUE, "CTRL_selrank1_perfderived", "IC"),
  gate_row(am_sel1, ret_best, RBF, NULL, TRUE, "CTRL_selrank1_perfderived", "RET"),
  gate_row(am_lag1, ic_best,  icm, NULL, TRUE, "CTRL_lag1_winner_perfderived", "IC"),
  gate_row(am_lag1, ret_best, RBF, NULL, TRUE, "CTRL_lag1_winner_perfderived", "RET")))
ALL <- rbind(MAIN, CTRL)
ALL[, pass_raw := hit_p < 0.05 | (is.finite(rho_t) & abs(rho_t) >= 1.5)]
ALL[, pass_adj := hit_p < 0.05/8 | (is.finite(rho_t) & abs(rho_t) >= qnorm(1-0.05/16))]
ALL[, label := fifelse(pass_adj, "TRANSPORT_ESTABLISHED",
              fifelse(pass_raw, "TRANSPORT_RAW_ONLY_MULTIPLICITY_FAIL",
              fifelse(hit < MDE_HIT & (!is.finite(rho_mde95) | abs(rho)+rho_mde95 < 0.15),
                      "POWERED_NULL_CRITERION_UNINFORMATIVE", "UNRESOLVED_UNDERPOWERED")))]
setorder(ALL, key_id, -hit)
cat("\n--- RET 정답지 (처치 · 소비면 정합) ---\n")
print(ALL[key_id=="RET", .(criterion, n, hit=round(hit,6), exc_pp=round(hit_excess_pp,2),
   hit_p=signif(hit_p,3), hit2=round(hit2,4), rho=round(rho,5), rho_t=round(rho_t,3),
   mde=round(rho_mde95,4), selval=round(selval_ann_pct,3), sv_t=round(selval_t,2), label)])
cat(sprintf("\n[사전등록 MDE] 적중률 %.6f · top-2 %.6f · rho 해석적 %.6f\n",
            MDE_HIT, MDE_HIT2, PRE$MDE_precomputed$rho_iid_analytic_95))
cat("\n--- IC 정답지 (대조 · WT-007 재현) ---\n")
print(ALL[key_id=="IC", .(criterion, hit=round(hit,6), hit_p=signif(hit_p,3), rho=round(rho,5),
                       rho_t=round(rho_t,3), selval=round(selval_ann_pct,3), label)])

cat("\n################ (3) paired — 정답지 교체 효과 ################\n")
armlist <- c(names(DIRS), "CTRL_selrank1_perfderived", "CTRL_lag1_winner_perfderived")
PAIR <- rbindlist(lapply(armlist, function(nmd) {
  am <- if (nmd %in% names(DIRS)) AM[[nmd]] else if (grepl("selrank1", nmd)) am_sel1 else am_lag1
  ok <- !is.na(am); idx <- which(ok)
  hI <- am[idx]==ic_best[idx]; hR <- am[idx]==ret_best[idx]
  b <- sum(hR & !hI); cc <- sum(hI & !hR); dh <- mean(hR)-mean(hI)
  mcn_z <- if (b+cc > 0) (b-cc)/sqrt(b+cc) else NA_real_
  drho <- numeric(0)
  if (nmd %in% names(DIRS)) { cn <- CN_of(nmd); dec <- DEC_of(nmd)
    v <- vapply(seq_len(NM), function(m){ a <- CRIT[m,,cn]
      o1 <- is.finite(a)&is.finite(icm[m,]); o2 <- is.finite(a)&is.finite(RBF[m,])
      if (sum(o1)<3L||sum(o2)<3L||sd(a[o1])==0) return(NA_real_)
      r1 <- cor(rank(a[o1]),rank(icm[m,][o1])); r2 <- cor(rank(a[o2]),rank(RBF[m,][o2]))
      if (!dec) (-r2)-(-r1) else r2-r1 }, 0); drho <- v[is.finite(v)] }
  data.table(criterion=nmd, n=sum(ok), hit_IC=mean(hI), hit_RET=mean(hR), d_hit=dh,
    b_RETonly=b, c_IConly=cc, mcnemar_z=mcn_z,
    mcnemar_p2=if(is.na(mcn_z)) NA_real_ else 2*(1-pnorm(abs(mcn_z))),
    d_rho_mean=if(length(drho)) mean(drho) else NA_real_,
    d_rho_t=if(length(drho)) .nw_t_mean(drho, lag=3L) else NA_real_) }))
PAIR[, key_swap_material := (abs(d_hit) >= MDE_D2S) | (is.finite(d_rho_t) & abs(d_rho_t) >= 1.96)]
PAIR[, label := fifelse(key_swap_material, "KEY_SWAP_MATERIAL", "KEY_SWAP_NULL")]
print(PAIR[, .(criterion, n, hit_IC=round(hit_IC,5), hit_RET=round(hit_RET,5), d_hit=round(d_hit,5),
               b=b_RETonly, c=c_IConly, mcn_z=round(mcnemar_z,3), mcn_p=signif(mcnemar_p2,3),
               d_rho=round(d_rho_mean,5), d_rho_t=round(d_rho_t,3), label)])
cat(sprintf("\n[사전등록] paired Δhit 양측 MDE = %.6f (귀무 sd %.6f · 불일치 월 %d)\n",
            MDE_D2S, PRE$MDE_precomputed$paired_dhit_sd_null, PRE$measured_design_inputs$n_discordant_months))

saveRDS(list(COND=COND, ALL=ALL, PAIR=PAIR, am_sel1=am_sel1, am_lag1=am_lag1,
             MDE_HIT=MDE_HIT, MDE_HIT2=MDE_HIT2, MDE_D2S=MDE_D2S, top2_set=top2_set),
        file.path(OUT,"p3_gate.rds"))
cat("\n[saved] p3_gate.rds\nOK\n")
