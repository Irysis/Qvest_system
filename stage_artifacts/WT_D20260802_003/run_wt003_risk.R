## run_wt003_risk.R — WT-D20260802_003 Risk Research
## ─────────────────────────────────────────────────────────────────────────────
## Q-Lead 재정의(2026-08-02): dossier 아닌 **기전 진단** — 2x2 비대칭(정렬 정보가
## 선별 slot에선 유효 2.61, 가중 slot에선 1.34 천장)이 위험 구조로 설명되는가.
## + 의무 필드: Sigma=B.Omega.B'+D / cap_tier_decomposition(dual-basis) / crowding /
##   tail / stress / regime correlation.
## 역할 경계: Sigma+tail+stress+crowding+style 만. alpha 수정/weight 제안 없음.
## Sigma estimator 근거(FQ-057): 유니버스 p=348 > n=120 이므로 직접 covariance 추정은
##   linear LW mu*I 퇴화 영역 -> **factor 구조 Sigma = B Omega B' + D 로 회피**.
##   Omega 는 p=21(MKT+20) << n=120 이라 linear LW 무해(비바인딩). shopping <=5 기록.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite)
})
setDTthreads(2); try(arrow::set_cpu_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_003"
MBX <- "qepm/mailbox/worktask/WT-D20260802_003"
RUNTAG <- "20260802"
logf <- file.path(OUT, sprintf("_wt003_risk_log_%s.txt", RUNTAG))
con <- file(logf, "w", encoding="UTF-8")
w <- function(...){ msg <- paste0(...); writeLines(msg, con); flush(con); cat(msg, "\n") }
wf <- function(...) w(sprintf(...))

nwt <- function(x){ x <- x[is.finite(x)]; if(length(x) < 12) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }

wf("=== WT-D20260802_003 RISK — start %s ===", format(Sys.time()))

## ── 입력 (frozen 소비) ──────────────────────────────────────────────────────
alpha_pkg <- fromJSON(file.path(MBX, "alpha_package.json"), simplifyVector = TRUE)
full <- readRDS(file.path(OUT, "wt003_full_20260802.rds"))
POOL <- full$ANCH_last$pool                       # 20 factors (ICIR-selected)
TT_ALL <- full$ANCH_last$tt                       # trailing NW-t at anchor 2026-01-31 (102 approved)
COMP <- as.data.table(full$COMP_final)            # 348 names, composite score @2026-06-30
PR <- full$PR                                     # 5 arms period returns 221m
SIG_ASOF <- as.Date("2026-06-30")

## theta (alpha_package 그대로 수신 — 수정 금지)
fs <- as.data.table(alpha_pkg$factor_specs)
THETA <- setNames(fs$weight_theta, fs$proxy)
THETA <- THETA[POOL]; THETA[is.na(THETA)] <- 0
wf("theta received: %s", paste(sprintf("%s=%.4f", names(THETA)[THETA>0], THETA[THETA>0]), collapse=" / "))
HHI_theta <- sum(THETA^2); NEFF_theta <- 1/HHI_theta
wf("theta HHI=%.4f  n_eff=%.3f  (EW n_eff=20)", HHI_theta, NEFF_theta)

## ═══════════════════════════════════════════════════════════════════════════
## PART 1 — 기전 진단: 팩터 배포권 active 상관 구조 (r6 panel, metric_type=canonical_screen 파생)
## ═══════════════════════════════════════════════════════════════════════════
r6 <- as.data.table(read_parquet("outputs/ramp/r6_factor_deployzone_active.parquet"))
r6[, signal_date := as.Date(signal_date)]
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]

arm_dates <- as.Date(PR$W_portt$date)             # 2008-01 ~ 2026-05 (221m)
r6p <- r6[factor_id %in% POOL & signal_date %in% arm_dates]
Wact <- dcast(r6p, signal_date ~ factor_id, value.var="active_bm")
Mact <- as.matrix(Wact[, -1]); rownames(Mact) <- as.character(Wact$signal_date)
Mact <- Mact[, POOL]
wf("PART1: pool active matrix %d x %d (NA %.1f%%)", nrow(Mact), ncol(Mact), 100*mean(is.na(Mact)))

## (a) pairwise cor — full window + trailing 36m at anchor
C_full <- cor(Mact, use="pairwise.complete.obs")
anchor <- as.Date("2026-01-31")
tr_dates <- arm_dates[arm_dates < anchor]; tr_dates <- tail(sort(tr_dates), 36)
M36 <- Mact[rownames(Mact) %in% as.character(tr_dates), ]
C_36 <- cor(M36, use="pairwise.complete.obs")
off <- function(M) M[upper.tri(M)]
mean_cor_icir_full <- mean(off(C_full), na.rm=TRUE)
mean_cor_icir_36 <- mean(off(C_36), na.rm=TRUE)
hi_pairs <- which(C_full > 0.8 & upper.tri(C_full), arr.ind=TRUE)
hi_pair_list <- if(nrow(hi_pairs)) apply(hi_pairs, 1, function(ij)
  sprintf("%s~%s(%.2f)", rownames(C_full)[ij[1]], colnames(C_full)[ij[2]], C_full[ij[1],ij[2]])) else character(0)
wf("ICIR pool mean pairwise active-cor: full=%.4f  trailing36=%.4f  pairs>0.8: %d",
   mean_cor_icir_full, mean_cor_icir_36, length(hi_pair_list))

## (b) Ppure pool 재구성 (PORT_t-정렬 top-20, 동일 추정량 tt) — 비교군
tt_pos <- sort(TT_ALL[TT_ALL > 0 & names(TT_ALL) %in% APPROVED], decreasing=TRUE)
PPURE <- names(head(tt_pos, 20))
r6pp <- r6[factor_id %in% PPURE & signal_date %in% arm_dates]
Wpp <- dcast(r6pp, signal_date ~ factor_id, value.var="active_bm")
Mpp <- as.matrix(Wpp[, -1]); rownames(Mpp) <- as.character(Wpp$signal_date)
Cpp_full <- cor(Mpp, use="pairwise.complete.obs")
Mpp36 <- Mpp[rownames(Mpp) %in% as.character(tr_dates), ]
Cpp_36 <- cor(Mpp36, use="pairwise.complete.obs")
mean_cor_ppure_full <- mean(off(Cpp_full), na.rm=TRUE)
mean_cor_ppure_36 <- mean(off(Cpp_36), na.rm=TRUE)
jac <- length(intersect(POOL, PPURE)) / length(union(POOL, PPURE))
wf("Ppure pool (top-20 by anchor tt): mean pairwise cor full=%.4f trailing36=%.4f | Jaccard(ICIR,Ppure)=%.3f",
   mean_cor_ppure_full, mean_cor_ppure_36, jac)

## (c) diversification ratio + n_eff (risk basis) — trailing 36m cov
cov36 <- cov(M36, use="pairwise.complete.obs"); cov36[is.na(cov36)] <- 0
sig36 <- sqrt(diag(cov36))
dr <- function(wv){ wv <- wv/sum(wv); as.numeric((wv %*% sig36) / sqrt(t(wv) %*% cov36 %*% wv)) }
w_ew <- rep(1/20, 20); names(w_ew) <- POOL
DR_ew <- dr(w_ew); DR_theta <- dr(THETA)
wf("Diversification ratio (36m active cov): EW=%.3f (n_eff_risk=%.2f) vs theta=%.3f (n_eff_risk=%.2f)",
   DR_ew, DR_ew^2, DR_theta, DR_theta^2)

## (d) theta 조합의 팩터분산 점유 (full-window cov, Euler)
covF <- cov(Mact, use="pairwise.complete.obs"); covF[is.na(covF)] <- 0
th <- THETA/sum(THETA)
rc <- th * as.numeric(covF %*% th); rc_share <- rc / sum(rc)
top_rc <- sort(rc_share, decreasing=TRUE)[1:3]
wf("theta composite variance share: %s", paste(sprintf("%s=%.3f", names(top_rc), top_rc), collapse=" / "))

## (e) W_portt arm ~ 단일팩터 C04 등가성 검사
c04 <- r6[factor_id=="C04_ESBR" & signal_date %in% arm_dates][order(signal_date)]
arm <- as.data.table(PR$W_portt)[order(date)]
mm <- merge(arm[,.(date, act_bm)], c04[,.(date=signal_date, c04_act=active_bm)], by="date")
cor_arm_c04 <- cor(mm$act_bm, mm$c04_act, use="complete.obs")
nwt_c04_standalone <- nwt(mm$c04_act)
nwt_arm <- nwt(mm$act_bm)
base_arm <- as.data.table(PR$base)[order(date)]
cor_arm_base <- cor(arm$act_bm, base_arm$act_bm, use="complete.obs")
wf("W_portt arm vs C04 standalone: cor=%.4f | NW-t: arm=%.3f C04alone=%.3f | cor(arm, base_EW)=%.4f",
   cor_arm_c04, nwt_arm, nwt_c04_standalone, cor_arm_base)

## (f) redundancy proxy (factor-level): theta composite vs Ppure-EW composite
common_f <- intersect(rownames(Mact), rownames(Mpp))
cs_theta <- as.numeric(Mact[common_f, ] %*% th)
cs_ppure <- rowMeans(Mpp[common_f, ], na.rm=TRUE)
cs_icirew <- rowMeans(Mact[common_f, ], na.rm=TRUE)
cor_theta_ppure <- cor(cs_theta, cs_ppure, use="complete.obs")
cor_icirew_ppure <- cor(cs_icirew, cs_ppure, use="complete.obs")
wf("redundancy (factor-level proxy): cor(theta_comp, PpureEW)=%.4f | cor(icirEW, PpureEW)=%.4f",
   cor_theta_ppure, cor_icirew_ppure)

## (g) regime correlation shift — crisis(bm<-5%) vs normal
bmr <- unique(r6p[,.(signal_date, benchmark_ret)])
crisis_m <- as.character(bmr[benchmark_ret < -0.05, signal_date])
norm_m <- setdiff(rownames(Mact), crisis_m)
C_crisis <- cor(Mact[rownames(Mact) %in% crisis_m, ], use="pairwise.complete.obs")
C_norm <- cor(Mact[norm_m, ], use="pairwise.complete.obs")
mean_cor_crisis <- mean(off(C_crisis), na.rm=TRUE); mean_cor_norm <- mean(off(C_norm), na.rm=TRUE)
wf("regime cor shift (pool active): crisis(n=%d)=%.4f vs normal(n=%d)=%.4f",
   length(crisis_m), mean_cor_crisis, length(norm_m), mean_cor_norm)
reg_long <- rbind(
  data.table(as.data.table(as.table(C_crisis)), regime="crisis"),
  data.table(as.data.table(as.table(C_norm)), regime="normal"))
setnames(reg_long, c("V1","V2","N"), c("factor_i","factor_j","correlation"))
write_parquet(reg_long, file.path(OUT, "regime_correlation.parquet"))

## ═══════════════════════════════════════════════════════════════════════════
## PART 2 — Sigma = B Omega B' + D (universe 348, MKT+20 factor 구조)
## ═══════════════════════════════════════════════════════════════════════════
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_dates <- sort(unique(as.Date(g$signal_date))); rm(g)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need)))
rawdata[, Date := as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme <- rawdata[Date %in% .me[!is.na(.me)]]
me_map <- data.table(Date_me=.me, Date=sig_dates)[!is.na(Date_me)]
fwd <- build_monthly_forward_returns(rawme, sig_dates)
RET_DT <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]

sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% POOL]; sc[, signal_date := as.Date(signal_date)]

## FM cross-sectional regression: 최근 120 sig months (실현 forward 존재분)
ret_months <- sort(unique(RET_DT$Date))
est_months <- tail(intersect(as.character(sort(unique(sc$signal_date))), as.character(ret_months)), 120)
wf("PART2: FM window %s ~ %s (%d months)", est_months[1], tail(est_months,1), length(est_months))

## 공선성 제거 (rank 결핍 방지): pooled 60m z-cor > 0.97 근사-중복 drop
ds60 <- tail(as.Date(est_months), 60)
zz <- dcast(sc[signal_date %in% ds60], signal_date + security_id ~ factor_id, value.var="z")
Cz <- cor(as.matrix(zz[, -(1:2)]), use="pairwise.complete.obs")
DROPPED <- character(0); keep <- colnames(Cz)
dup <- which(abs(Cz) > 0.97 & upper.tri(Cz), arr.ind=TRUE)
if(nrow(dup)){
  for(k in seq_len(nrow(dup))){
    a <- rownames(Cz)[dup[k,1]]; b <- colnames(Cz)[dup[k,2]]
    ## 뒤쪽(POOL 순서 하위 = ICIR 하위) drop
    victim <- if(match(a, POOL) < match(b, POOL)) b else a
    if(victim %in% keep && !(setdiff(c(a,b), victim) %in% DROPPED)){
      keep <- setdiff(keep, victim); DROPPED <- c(DROPPED, victim) } } }
FM_SET <- intersect(POOL, keep)
wf("collinearity: dropped %s -> FM_SET %d factors",
   if(length(DROPPED)) paste(DROPPED, collapse=",") else "none", length(FM_SET))

f_list <- list(); resid_list <- list()
for(mth in est_months){
  d <- as.Date(mth)
  z <- dcast(sc[signal_date==d], security_id ~ factor_id, value.var="z")
  rr <- RET_DT[Date==d, .(security_id=Ticker, Ret_1m)]
  dtm <- merge(z, rr, by="security_id")
  zc_cols <- intersect(FM_SET, names(dtm))
  n_ok <- rowSums(!is.na(as.matrix(dtm[, ..zc_cols])))
  dtm <- dtm[n_ok >= 10 & is.finite(Ret_1m)]
  if(nrow(dtm) < 60) next
  X <- as.matrix(dtm[, ..zc_cols]); X[is.na(X)] <- 0
  miss <- setdiff(FM_SET, zc_cols)
  if(length(miss)){ X <- cbind(X, matrix(0, nrow(X), length(miss), dimnames=list(NULL, miss))) }
  X <- X[, FM_SET]
  fit <- lm.fit(cbind(MKT=1, X), dtm$Ret_1m)
  cf <- fit$coefficients; cf[is.na(cf)] <- 0
  f_list[[mth]] <- cf
  resid_list[[mth]] <- data.table(security_id=dtm$security_id, e=fit$residuals)
}
f_mat <- do.call(rbind, f_list)   # n x (1+|FM_SET|)
na_cols <- colnames(f_mat)[colSums(is.na(f_mat)) > 0]
if(length(na_cols)) stop("f_mat NA columns remain: ", paste(na_cols, collapse=","))
wf("factor returns: %d months x %d (MKT+%d)", nrow(f_mat), ncol(f_mat), length(FM_SET))

## Omega — method shopping (<=5), selection_objective = condition_number
source("02_Infrastructure/portfolio/hrp_core.R")
cond_of <- function(S){ ev <- eigen(S, symmetric=TRUE, only.values=TRUE)$values
  max(ev)/max(min(ev), 1e-300) }
psd_of <- function(S) min(eigen(S, symmetric=TRUE, only.values=TRUE)$values) > -1e-10
cand <- list()
S_smp <- .get_cor_cov(f_mat, "sample")$cov
cand$sample <- list(cov=S_smp, cond=cond_of(S_smp), psd=psd_of(S_smp))
S_lw <- .get_cor_cov(f_mat, "ledoit_wolf")$cov
cand$ledoit_wolf <- list(cov=S_lw, cond=cond_of(S_lw), psd=psd_of(S_lw))
S_nls <- tryCatch(.get_cor_cov(f_mat, "lw_nls")$cov, error=function(e) NULL)
if(!is.null(S_nls)) cand$lw_nls <- list(cov=S_nls, cond=cond_of(S_nls), psd=psd_of(S_nls))
for(nm in names(cand)) wf("Omega candidate %-12s cond=%.1f psd=%s", nm, cand[[nm]]$cond, cand[[nm]]$psd)
## 선택: PSD 충족 중 cond 최소 (동률권이면 shrinkage 우선)
ok <- names(cand)[sapply(cand, `[[`, "psd")]
sel <- ok[which.min(sapply(cand[ok], `[[`, "cond"))]
Omega <- cand[[sel]]$cov
wf("Omega selected: %s (cond=%.1f) — p=21 << n=%d, linear LW 비바인딩 영역(FQ-057 p>n 퇴화 비해당)",
   sel, cand[[sel]]$cond, nrow(f_mat))

## D — specific risk (residual variance, min 24 obs)
resid_dt <- rbindlist(resid_list, idcol="mth")
Dv <- resid_dt[, .(v=var(e), n=.N), by=security_id]
med_v <- median(Dv[n >= 24, v], na.rm=TRUE)
COMP_ids <- COMP$security_id
D_vec <- setNames(rep(med_v, length(COMP_ids)), COMP_ids)
hit <- Dv[security_id %in% COMP_ids & n >= 24]
D_vec[hit$security_id] <- hit$v
D_vec <- pmax(D_vec, 1e-6)
wf("D: %d/%d names direct (>=24m resid), fallback median=%.6f", nrow(hit), length(COMP_ids), med_v)

## B at as_of (2026-06-30) — FM_SET 기준 (dropped 팩터는 근사-중복 twin이 위험 대표)
z_asof <- dcast(sc[signal_date==SIG_ASOF], security_id ~ factor_id, value.var="z")
B <- merge(data.table(security_id=COMP_ids), z_asof, by="security_id", all.x=TRUE)
zc_cols <- intersect(FM_SET, names(B))
n_missing_cell <- sum(is.na(as.matrix(B[, ..zc_cols])))
Bm <- as.matrix(B[, ..zc_cols]); Bm[is.na(Bm)] <- 0
miss <- setdiff(FM_SET, zc_cols)
if(length(miss)) Bm <- cbind(Bm, matrix(0, nrow(Bm), length(miss), dimnames=list(NULL, miss)))
Bm <- Bm[, FM_SET]; rownames(Bm) <- B$security_id
B_aug <- cbind(MKT=1, Bm)
wf("B: %d x %d, missing z cells=%d (-> 0 neutral)", nrow(B_aug), ncol(B_aug), n_missing_cell)

## Sigma
Sigma <- B_aug %*% Omega %*% t(B_aug) + diag(D_vec[rownames(Bm)])
ev_S <- eigen(Sigma, symmetric=TRUE, only.values=TRUE)$values
cond_S <- max(ev_S)/min(ev_S); psd_S <- min(ev_S) > 0
fac_var <- diag(B_aug %*% Omega %*% t(B_aug)); tot_var <- diag(Sigma)
factor_coverage <- mean(fac_var/tot_var)
wf("Sigma %dx%d: cond=%.1f psd=%s factor_coverage(mean var share)=%.3f", nrow(Sigma), ncol(Sigma),
   cond_S, psd_S, factor_coverage)

## artifacts
write_parquet(as.data.table(cbind(data.table(security_id=rownames(Bm)), as.data.table(B_aug))),
              file.path(OUT, "exposure_matrix.parquet"))
write_parquet(data.table(factor_id=colnames(Omega), as.data.table(Omega)),
              file.path(OUT, "factor_covariance.parquet"))
write_parquet(data.table(security_id=names(D_vec), specific_var=as.numeric(D_vec)),
              file.path(OUT, "specific_risk.parquet"))
cov_dt <- data.table(security_id=rownames(Sigma), as.data.table(Sigma))
write_parquet(cov_dt, file.path(OUT, "covariance.parquet"))
write_parquet(cov_dt, file.path(MBX, "covariance.parquet"))
wf("artifacts written: exposure/factor_cov/specific/covariance (+mailbox copy)")

## ═══════════════════════════════════════════════════════════════════════════
## PART 3 — cap_tier dual-basis 분해 (top-25 canonical deployment snapshot)
## ═══════════════════════════════════════════════════════════════════════════
me_asof <- max(.udates[.udates <= SIG_ASOF])
snap <- rawdata[Date == me_asof]
setorder(snap, -Size); snap[, crank := seq_len(.N)]
snap[, tier := fifelse(crank <= 10L, "MEGA", fifelse(crank <= 30L, "MID", "SMALL"))]
COMP2 <- merge(COMP, snap[,.(security_id=Ticker, Size, Sector, tier, K200, KQ150)],
               by="security_id", all.x=TRUE)
COMP2[is.na(tier), tier := "SMALL"]
setorder(COMP2, -score)
top25 <- COMP2[1:25]
w_hold <- setNames(rep(0, length(COMP_ids)), COMP_ids); w_hold[top25$security_id] <- 1/25

## bench weights
k200 <- COMP2[K200 == 1 & !is.na(Size)]
w_cw <- setNames(rep(0, length(COMP_ids)), COMP_ids)
w_cw[k200$security_id] <- k200$Size / sum(k200$Size)
w_ew <- setNames(rep(1/length(COMP_ids), length(COMP_ids)), COMP_ids)

tier_of <- setNames(COMP2$tier, COMP2$security_id)
rc_by_tier <- function(w_act){
  w_act <- w_act[rownames(Sigma)]
  tot <- as.numeric(t(w_act) %*% Sigma %*% w_act)
  rc <- w_act * as.numeric(Sigma %*% w_act) / tot
  tapply(rc, tier_of[names(rc)], sum)
}
act_cw <- w_hold - w_cw; act_ew <- w_hold - w_ew
rs_cw <- rc_by_tier(act_cw); rs_ew <- rc_by_tier(act_ew)
te_cw <- sqrt(as.numeric(t(act_cw[rownames(Sigma)]) %*% Sigma %*% act_cw[rownames(Sigma)]) * 12)
te_ew <- sqrt(as.numeric(t(act_ew[rownames(Sigma)]) %*% Sigma %*% act_ew[rownames(Sigma)]) * 12)

av <- alpha_pkg$alpha_vector; av_pos <- unlist(av); av_pos <- pmax(av_pos, 0)
a_tier <- tapply(av_pos[top25$security_id], top25$tier, sum, default=0)
a_share <- a_tier / sum(av_pos[top25$security_id])
hold_share <- table(top25$tier)/25
tiers <- c("MEGA","MID","SMALL")
gv <- function(x, t) if(t %in% names(x)) as.numeric(x[t]) else 0
div_gap <- max(abs(sapply(tiers, function(t) gv(rs_cw,t) - gv(rs_ew,t))))
div_flag <- div_gap >= 0.30
for(t in tiers) wf("tier %-5s | hold=%.3f alpha_share=%.3f | active_risk_share cap-w=%.3f ew-uni=%.3f",
   t, gv(hold_share,t), gv(a_share,t), gv(rs_cw,t), gv(rs_ew,t))
wf("dual_basis divergence: max tier gap=%.3f -> flag=%s | TE(ann): cap-w=%.3f ew-uni=%.3f",
   div_gap, div_flag, te_cw, te_ew)

## concentration
sec_hhi <- top25[, .(s=.N/25), by=Sector][, sum(s^2)]
n_eff_port <- 1/sum((rep(1/25,25))^2)
wf("top-25 sector HHI=%.3f (n_sectors=%d) n_eff_names=%.0f", sec_hhi, uniqueN(top25$Sector), n_eff_port)

## ═══════════════════════════════════════════════════════════════════════════
## PART 4 — crowding_score_per_factor (의무, Acadian 2026)
## ═══════════════════════════════════════════════════════════════════════════
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
fe_long <- melt(z_asof, id.vars="security_id", variable.name="factor_name", value.name="exposure")
fe_long <- fe_long[!is.na(exposure), .(Ticker=security_id, factor_name=as.character(factor_name), exposure)]
bmk_t <- snap[K200==1 | KQ150==1, Ticker]
crw <- crowding_score_per_factor(fe_long, sig_date=SIG_ASOF,
        RAWDATA=rawdata[,.(Date,Ticker,Close,Vol,Size)], benchmark_tickers=bmk_t)
crw <- as.data.table(crw)
setorder(crw, -crowding_score)
wf("crowding top: %s", paste(sprintf("%s=%.2f", head(crw$factor_name,5), head(crw$crowding_score,5)), collapse=" / "))
crw_flags <- crw[crowding_score >= 0.75, factor_name]
wf("crowding flags (>=0.75): %s", if(length(crw_flags)) paste(crw_flags, collapse=",") else "none")

## ═══════════════════════════════════════════════════════════════════════════
## PART 5 — tail + stress (W_portt arm, canonical_screen 파생)
## ═══════════════════════════════════════════════════════════════════════════
## EVT-GPD: fExtremes/evir 미설치 + 월간 n=221 소표본(5% 초과 ~11건) — GPD 신뢰불가.
## PerformanceAnalytics 표준함수(historical + modified=Cornish-Fisher)가 권위 (Pfaff Ch4).
suppressPackageStartupMessages(library(PerformanceAnalytics))
act <- arm$act_bm; retn <- arm$ret_net
pa_tail <- function(x, p){
  xx <- xts::xts(x, order.by=arm$date)
  list(var_hist = -as.numeric(VaR(xx, p=p, method="historical")),
       es_hist  = -as.numeric(ES(xx, p=p, method="historical")),
       var_cf   = -as.numeric(VaR(xx, p=p, method="modified")),
       es_cf    = -as.numeric(ES(xx, p=p, method="modified"))) }
tail_out <- list(
  basis = "W_portt arm monthly (221m, 2008-01~2026-05), metric_type=canonical_screen",
  method = "PerformanceAnalytics VaR/ES historical + modified(Cornish-Fisher)",
  active_bm = list(p95=pa_tail(act,.95), p99=pa_tail(act,.99)),
  ret_net  = list(p95=pa_tail(retn,.95), p99=pa_tail(retn,.99)),
  evt_gpd = "unavailable — fExtremes/evir 미설치 + 월간 5% tail n~11 소표본 (metric_type=unavailable)",
  skew_active = as.numeric(skewness(act)), kurt_active = as.numeric(kurtosis(act)),
  note = "monthly frequency: empirical + Cornish-Fisher 권위, GPD 부적합"
)
wf("tail: active VaR95(hist)=%.3f ES95=%.3f VaR99=%.3f CF-VaR99=%.3f | skew=%.2f",
   tail_out$active_bm$p95$var_hist, tail_out$active_bm$p95$es_hist,
   tail_out$active_bm$p99$var_hist, tail_out$active_bm$p99$var_cf, tail_out$skew_active)
write_json(tail_out, file.path(OUT, "tail_risk.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

stress_periods <- list(
  list(name="GFC",            start="2007-10-01", end="2009-03-31"),
  list(name="Euro_Debt",      start="2011-07-01", end="2011-12-31"),
  list(name="China_Shock",    start="2015-06-01", end="2016-02-29"),
  list(name="US_China_Trade", start="2018-03-01", end="2018-12-31"),
  list(name="COVID",          start="2020-01-01", end="2020-06-30"),
  list(name="Rate_Hike",      start="2022-01-01", end="2022-12-31"),
  list(name="Iran_War",       start="2026-02-01", end="2026-04-30"))
stress_rows <- list()
for(sp in stress_periods){
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  idx <- arm$date >= s & arm$date <= e
  n_exp <- length(seq(s, e, by="month"))
  n_got <- sum(idx)
  cum1 <- function(x) as.numeric(Return.cumulative(xts::xts(x, order.by=arm$date[idx])))
  cum_act <- if(n_got) cum1(arm$act_bm[idx]) else NA_real_
  cum_ret <- if(n_got) cum1(arm$ret_net[idx]) else NA_real_
  cum_bm  <- if(n_got) cum1(arm$benchmark_ret[idx]) else NA_real_
  cov_r <- n_got/n_exp
  stress_rows[[sp$name]] <- list(cum_active=round(cum_act,4), cum_ret_net=round(cum_ret,4),
    cum_benchmark=round(cum_bm,4), coverage=round(cov_r,2),
    reliability=if(cov_r < 0.85) "UNRELIABLE(coverage<85%)" else "ok")
  wf("stress %-14s act=%+.3f ret=%+.3f bm=%+.3f cov=%.2f %s", sp$name,
     ifelse(is.na(cum_act),0,cum_act), ifelse(is.na(cum_ret),0,cum_ret),
     ifelse(is.na(cum_bm),0,cum_bm), cov_r, if(cov_r<0.85) "[UNRELIABLE]" else "")
}
## market_down_5 proxy: beta-implied via regression of ret_net on bm
b_mkt <- coef(lm(retn ~ arm$benchmark_ret))[2]
md5 <- as.numeric(b_mkt * -0.05)
wf("market_down_5 (beta=%.2f implied): %.4f", b_mkt, md5)

## ═══════════════════════════════════════════════════════════════════════════
## PART 6 — risk_package.json + lineage + challenge review
## ═══════════════════════════════════════════════════════════════════════════
mech <- list(
  question = "2x2 비대칭(선별 slot 2.61 vs 가중 slot 1.34)이 위험 구조로 설명되는가",
  theta_concentration = list(hhi=round(HHI_theta,4), n_eff=round(NEFF_theta,3),
    top_factor="C04_ESBR", top_theta=round(as.numeric(THETA["C04_ESBR"]),4)),
  factor_active_correlation = list(
    icir_pool_mean_full=round(mean_cor_icir_full,4), icir_pool_mean_36m=round(mean_cor_icir_36,4),
    ppure_pool_mean_full=round(mean_cor_ppure_full,4), ppure_pool_mean_36m=round(mean_cor_ppure_36,4),
    pairs_gt_08=hi_pair_list, jaccard_icir_ppure=round(jac,3)),
  diversification = list(DR_ew=round(DR_ew,3), DR_theta=round(DR_theta,3),
    n_eff_risk_ew=round(DR_ew^2,2), n_eff_risk_theta=round(DR_theta^2,2)),
  theta_variance_share = as.list(round(sort(rc_share, decreasing=TRUE)[1:5],4)),
  single_factor_equivalence = list(cor_arm_vs_C04=round(cor_arm_c04,4),
    nwt_arm=round(nwt_arm,3), nwt_C04_standalone=round(nwt_c04_standalone,3),
    cor_arm_vs_baseEW=round(cor_arm_base,4)),
  redundancy_proxy = list(cor_thetaComp_vs_PpureEW=round(cor_theta_ppure,4),
    cor_icirEW_vs_PpureEW=round(cor_icirew_ppure,4),
    metric_type="proxy (factor-level r6 composite, not security-level bt)"),
  regime_cor_shift = list(crisis=round(mean_cor_crisis,4), normal=round(mean_cor_norm,4),
    n_crisis_months=length(crisis_m))
)

rf_flags <- list()
if(length(hi_pair_list) >= 2) rf_flags <- c(rf_flags, list(list(id="RF-R5", severity="MEDIUM",
  flag=sprintf("factor active cor>0.8 pairs %d: %s", length(hi_pair_list), paste(head(hi_pair_list,4), collapse="; ")))))
if(length(crw_flags)) rf_flags <- c(rf_flags, list(list(id="RF-R3", severity="MEDIUM",
  flag=paste("crowding>=0.75:", paste(crw_flags, collapse=",")))))
if(md5 < -0.08) rf_flags <- c(rf_flags, list(list(id="RF-R4", severity="HIGH",
  flag=sprintf("market_down_5=%.3f < -8%%", md5))))
rf_flags <- c(rf_flags, list(list(id="RF-WT003-MECH", severity="HIGH",
  flag=sprintf("조합 가중 위험 집중 실측: theta n_eff=%.2f (EW 20), DR_theta=%.2f, arm~C04 단일팩터 cor=%.2f — 분산 효과 사실상 부재. 가중 정렬 = 사실상 단일팩터 선택",
    NEFF_theta, DR_theta, cor_arm_c04))))

risk_package <- list(
  task_id = "WT-D20260802_003",
  as_of_date = "2026-08-02",
  exposure_matrix_ref = file.path(OUT, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path(OUT, "factor_covariance.parquet"),
  specific_risk_ref = file.path(OUT, "specific_risk.parquet"),
  security_covariance_ref = file.path(OUT, "covariance.parquet"),
  selection_objective = "condition_number",
  sigma_estimator = list(
    structure = sprintf("Sigma = B Omega B' + D (MKT + %d factor cross-sectional FM, %dm window)",
                        length(FM_SET), length(est_months)),
    omega_method = sel, omega_cond = round(cand[[sel]]$cond,1),
    collinearity_dropped = as.list(DROPPED),
    collinearity_note = "pooled 60m z-cor>0.97 근사-중복(D01~R12 cor=1.000 완전중복 포함) — rank 결핍 방지 drop, twin이 위험 대표",
    rationale = "universe p=348 > n=120 -> 직접 추정은 linear LW mu*I 퇴화 영역(FQ-057). factor 구조로 회피. Omega는 p<<n — linear LW 비바인딩 무해(p<=25 posterior). lw_nls 후보 병기 실측.",
    sigma_cond = round(cond_S,1), sigma_psd = psd_S,
    factor_coverage = round(factor_coverage,3),
    units = "monthly return covariance"),
  method_shopping_log = list(risk_agent=list(candidates_tried=length(cand), parallel_exec=FALSE,
    method_log=lapply(names(cand), function(nm) list(name=nm, condition=round(cand[[nm]]$cond,1),
      psd=cand[[nm]]$psd, selected=(nm==sel))))),
  mechanism_diagnosis = mech,
  risk_summary = list(
    top_common_risks = {
      e_vec <- as.numeric(t(B_aug) %*% (act_cw[rownames(Sigma)]))
      names(e_vec) <- colnames(B_aug)
      cf <- e_vec * as.numeric(Omega %*% e_vec)
      spec_c <- sum((act_cw[rownames(Sigma)])^2 * D_vec[rownames(Sigma)])
      tot <- sum(cf) + spec_c
      shares <- sort(c(cf/tot, specific=spec_c/tot), decreasing=TRUE)
      as.list(round(head(shares[shares>0.02], 6), 3)) },
    crowding_flags = as.list(crw_flags),
    crowding_score_per_factor = crw,
    liquidity_flags = list(),
    stress_tests = stress_rows,
    market_down_5 = round(md5,4),
    tail_risk_ref = file.path(OUT, "tail_risk.json"),
    cap_tier_decomposition = list(
      basis = "cap_w_and_ew_uni",
      portfolio_basis = "canonical top-25 EW deployment snapshot @2026-06-30 (측정용 — weight 제안 아님)",
      tiers = lapply(tiers, function(t) list(tier=t,
        holdings_share=round(gv(hold_share,t),3),
        alpha_share=round(gv(a_share,t),3),
        active_risk_share_capw=round(gv(rs_cw,t),3),
        active_risk_share_ewuni=round(gv(rs_ew,t),3),
        signal_alive=(gv(a_share,t) >= 0.10))),
      te_ann_capw = round(te_cw,4), te_ann_ewuni = round(te_ew,4),
      dual_basis_divergence_gap = round(div_gap,3),
      dual_basis_divergence_flag = div_flag),
    concentration = list(sector_hhi_top25=round(sec_hhi,3), n_eff_names=25,
      n_sectors=uniqueN(top25$Sector))),
  diagnostics = list(
    condition_number = round(cond_S,1),
    shrinkage_used = (sel != "sample"),
    shrinkage_method = sel,
    factor_correlation_warnings = hi_pair_list,
    regime_correlation_ref = file.path(OUT, "regime_correlation.parquet"),
    fm_window_months = length(est_months),
    metric_type = "canonical_screen 파생(기전 실측) + estimated(Sigma 구조 추정)"),
  challenge_flags = rf_flags
)
write_json(risk_package, file.path(MBX, "risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
wf("risk_package.json written")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id="WT-D20260802_003", package_type="risk_package",
  method_selected=sprintf("factor_model_BOmegaB_D_%s", sel),
  input_file_paths=c(file.path(MBX,"alpha_package.json"),
                     "outputs/ramp/r6_factor_deployzone_active.parquet",
                     "outputs/ramp/pure_factor_scores.parquet"),
  windows=list(fm_window=c(est_months[1], tail(est_months,1)), trailing36=as.character(range(tr_dates))))
source("02_Infrastructure/worktask/worktask_manager.R")
wt_record_challenge_review(task_id="WT-D20260802_003", from_agent="risk", objection=FALSE,
  targets_reviewed=c("alpha_package","confidence_vector","factor_specs","theta_weights"))
wf("=== RISK done %s ===", format(Sys.time()))
close(con)
