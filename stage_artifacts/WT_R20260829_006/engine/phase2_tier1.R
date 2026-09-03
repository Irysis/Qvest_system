## WT-R20260829_006 Phase 2 — Step 0(B) 사전 검정력 계약 + 1급(전제) 검정
##  1급 = EL2022 게재판 Table 2 사양: pooled 지시변수 회귀(12-1, 스킵월 없음, 월 클러스터,
##        모멘텀 계열 제외). 사전등록 1급 = **계열-대표 사양**(계열 15).
##  ★검정력은 기울기를 추정하기 전에 H0(β=0) 잔차로 산출한다 — 결과를 보고 사후 계산하지 않는다.
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"

FAM_RET <- as.data.table(read_parquet(file.path(OUT,"p1_family_ls_returns.parquet")))
FAC_RET <- as.data.table(read_parquet(file.path(OUT,"p1_factor_ls_returns.parquet")))
FAMMAP  <- fread(file.path(OUT,"p1_family_map.csv"))

## 신호월(Date) → 홀딩월(hm) 라벨: Date 는 신호 월말, ls 는 그 다음 달 실현수익
FAM_RET[, hm := as.integer(format(Date,"%Y"))*12L + as.integer(format(Date,"%m")) + 1L]
FAC_RET[, hm := as.integer(format(Date,"%Y"))*12L + as.integer(format(Date,"%m")) + 1L]
hm2str <- function(h) sprintf("%04d-%02d", (h-1L)%/%12L, (h-1L)%%12L + 1L)

MOM_FAM <- "momentum"      # EL2022 게재판과 동일 — 검정대상이 종속변수에 들어가지 않게
SAMPLE_START_HM <- 2006L*12L + 1L                 # 2006-01 (2005-01 + 형성창 12m)
SAMPLE_END_HM   <- max(FAM_RET$hm)

## ── 형성 지시변수 (12-1, 스킵월 없음): x_{f,m} = 1{ mean(r_{f, m-12..m-1}) > 0 } ──
build_panel <- function(DT, idcol, lag_shift = 0L, win = 12L) {
  D <- copy(DT); setnames(D, idcol, "fid")
  D <- D[, .(fid, hm, r = ls)]
  setorder(D, fid, hm)
  full <- CJ(fid = unique(D$fid), hm = seq(min(D$hm), max(D$hm)))
  D <- merge(full, D, by = c("fid","hm"), all.x = TRUE)
  setorder(D, fid, hm)
  ## 형성창 = m-win-lag_shift .. m-1-lag_shift  (lag_shift 0 = EL2022 사양)
  D[, form_mean := {
      rs <- shift(r, 1L + lag_shift)
      frollmean(rs, n = win, na.rm = FALSE)
    }, by = fid]
  D[, x := as.integer(form_mean > 0)]
  D[!is.na(r) & !is.na(x)]
}

## ── 월 클러스터 OLS (H0 SE 와 실측 SE 를 분리 산출) ──────────────────────────
cluster_ols <- function(P) {
  y <- P$r; x <- P$x; g <- P$hm
  n <- length(y)
  X <- cbind(1, x)
  XtX_inv <- solve(crossprod(X))
  b <- as.numeric(XtX_inv %*% crossprod(X, y))
  e <- y - X %*% b
  ## CR1 월 클러스터
  G <- length(unique(g))
  meat <- matrix(0, 2, 2)
  for (gi in unique(g)) {
    ix <- which(g == gi)
    u <- crossprod(X[ix,,drop=FALSE], e[ix])
    meat <- meat + tcrossprod(u)
  }
  cadj <- (G/(G-1)) * ((n-1)/(n-2))
  V <- XtX_inv %*% (cadj*meat) %*% XtX_inv
  se <- sqrt(diag(V))
  list(intercept = b[1], slope = b[2], se_slope = se[2], se_intercept = se[1],
       t_slope = b[2]/se[2], t_intercept = b[1]/se[1],
       n_obs = n, n_clusters = G,
       p_slope = 2*pnorm(-abs(b[2]/se[2])))
}

## H0 기반 SE — 기울기를 추정하지 않고 산출 (검정력 계약용)
se_under_null <- function(P) {
  y <- P$r; x <- P$x; g <- P$hm
  xb <- mean(x); e <- y - mean(y)          # H0: 기울기 0 → 잔차 = 평균편차
  d  <- x - xb
  D  <- sum(d^2)
  M  <- 0
  for (gi in unique(g)) { ix <- which(g == gi); M <- M + (sum(d[ix]*e[ix]))^2 }
  G <- length(unique(g)); n <- length(y)
  cadj <- (G/(G-1)) * ((n-1)/(n-2))
  sqrt(cadj*M)/D
}

power_contract <- function(P, effect = 0.0045, label = "") {
  se0 <- se_under_null(P)
  mde80 <- (qnorm(0.975) + qnorm(0.80)) * se0
  ncp <- effect / se0
  pow <- pnorm(ncp - qnorm(0.975)) + pnorm(-ncp - qnorm(0.975))
  list(label = label, n_obs = nrow(P), n_months = uniqueN(P$hm), n_units = uniqueN(P$fid),
       se_under_null = se0, mde80 = mde80, effect_ref = effect,
       ratio = effect/mde80, expected_t = ncp, power = pow)
}

## ═══════════ A. 계열-대표 패널 (사전등록 1급) ═══════════
FAMP_all <- build_panel(FAM_RET, "family")
FAMP <- FAMP_all[fid != MOM_FAM & hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]

## 계열 내 상관 → 유효 클러스터 보정
W <- dcast(FAM_RET[hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM], hm ~ family, value.var = "ls")
Wm <- as.matrix(W[, -1, with = FALSE])
CM <- suppressWarnings(cor(Wm, use = "pairwise.complete.obs"))
nm <- setdiff(colnames(CM), MOM_FAM)
CMn <- CM[nm, nm]
rho_bar <- mean(abs(CMn[upper.tri(CMn)]), na.rm = TRUE)
F_decl <- length(nm)
F_eff_indep <- F_decl / (1 + (F_decl - 1) * rho_bar)

cat("\n══════ Step 0(B) 사전 검정력 계약 ══════\n")
cat(sprintf("F_declared(비-모멘텀 계열) = %d | 계열간 평균 |rho| = %.4f | F_eff_indep = %.2f\n",
            F_decl, rho_bar, F_eff_indep))
pc_t1 <- power_contract(FAMP, 0.0045, "tier1_family_representative")
str(pc_t1)

## 전수(팩터) 패널 — 병기(1급 아님)
FACMAP <- FAMMAP[, .(fid = Factor_Name, family)]
FACP_all <- build_panel(FAC_RET, "Factor_Name")
FACP_all <- merge(FACP_all, FACMAP, by = "fid", all.x = TRUE)
FACP <- FACP_all[family != MOM_FAM & !is.na(family) & hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]
pc_t1b <- power_contract(FACP, 0.0045, "tier1_all_factors_secondary")

## ═══════════ B. 1급 실측 ═══════════
cat("\n══════ 1급 — pooled 지시변수 회귀 ══════\n")
r_prim <- cluster_ols(FAMP)
cat("[계열-대표 (사전등록 1급)]\n"); str(r_prim)
r_sec  <- cluster_ols(FACP)
cat("[전수 팩터 (병기·1급 아님)]\n"); str(r_sec)

## 팩터-대표 대안: 계열별 알파벳 첫 팩터 (결정론적 대체 대표) — 강건성
alt_rep <- FAMMAP[order(family, Factor_Name), .(Factor_Name = Factor_Name[1]), by = family]
FACP_alt <- FACP_all[fid %in% alt_rep$Factor_Name & family != MOM_FAM &
                     hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]
r_alt <- cluster_ols(FACP_alt)
cat("[계열별 알파벳-첫 팩터 대표 (강건성)]\n"); str(r_alt)

## ═══════════ C. lag 사다리 (PIT 스트레스) ═══════════
cat("\n══════ lag 사다리 (형성창 종점 m-1 → m-2 → m-3) ══════\n")
ladder <- rbindlist(lapply(0:2, function(L) {
  P <- build_panel(FAM_RET, "family")[fid != MOM_FAM & hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]
  P2 <- build_panel(FAM_RET, "family", lag_shift = L)[fid != MOM_FAM &
          hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]
  o <- cluster_ols(P2)
  data.table(lag_shift = L, slope = o$slope, se = o$se_slope, t = o$t_slope, n_obs = o$n_obs)
}))
print(ladder)

## ═══════════ D. 부수관측 (a) 계열별 개별 회귀 부호 분포 ═══════════
cat("\n══════ (a) 계열별 개별 회귀 ══════\n")
per_fam <- rbindlist(lapply(sort(unique(FAMP_all$fid)), function(f) {
  P <- FAMP_all[fid == f & hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM]
  if (nrow(P) < 60) return(NULL)
  fit <- lm(r ~ x, data = P)
  ct <- summary(fit)$coefficients
  data.table(family = f, n = nrow(P), slope = ct[2,1], se = ct[2,2], t = ct[2,3],
             mean_ret = mean(P$r), sd_ret = sd(P$r),
             is_momentum = (f == MOM_FAM))
}))
print(per_fam)
cat(sprintf("\n비-모멘텀 계열 %d 중 기울기 양(+) = %d · |t|>1.96 양(+) = %d · |t|>1.96 음(-) = %d\n",
    per_fam[!(is_momentum), .N], per_fam[!(is_momentum) & slope>0, .N],
    per_fam[!(is_momentum) & slope>0 & abs(t)>1.96, .N],
    per_fam[!(is_momentum) & slope<0 & abs(t)>1.96, .N]))

## 팩터 단위 부호 분포 (병기)
per_fac <- FACP_all[family != MOM_FAM & !is.na(family) & hm >= SAMPLE_START_HM & hm <= SAMPLE_END_HM,
  { if (.N < 60) NULL else { fit <- lm(r ~ x); ct <- summary(fit)$coefficients
      .(n=.N, slope=ct[2,1], t=ct[2,3]) } }, by = .(fid, family)]
cat(sprintf("[전수] 팩터 %d 중 기울기 양(+) %d (%.1f%%) · 5%% 유의 양(+) %d · 5%% 유의 음(-) %d\n",
    nrow(per_fac), per_fac[slope>0,.N], 100*per_fac[slope>0,.N]/nrow(per_fac),
    per_fac[slope>0 & abs(t)>1.96,.N], per_fac[slope<0 & abs(t)>1.96,.N]))

## 이항검정 — 부호 분포 대칭성
bt <- binom.test(per_fac[slope>0,.N], nrow(per_fac), 0.5)
cat(sprintf("[전수] 부호 대칭 이항검정 p = %.4g\n", bt$p.value))

res <- list(
  power_contract = list(tier1_primary = pc_t1, tier1_secondary_allfactors = pc_t1b,
                        F_declared_nonmom = F_decl, rho_bar_within_families = rho_bar,
                        F_eff_independent = F_eff_indep,
                        el2022_effect_pct_per_month = 0.45, el2022_t = 4.22,
                        el2022_implied_se_pct = 0.107,
                        source = "Ehsani & Linnainmaa (2022) JF 77:1877-1919 게재판 Table 2"),
  tier1 = list(primary_family_representative = r_prim,
               secondary_all_factors = r_sec,
               robustness_alphabetical_representative = r_alt,
               lag_ladder = ladder,
               per_family = per_fam,
               per_factor_sign = list(n = nrow(per_fac), n_pos = per_fac[slope>0,.N],
                    n_pos_sig = per_fac[slope>0 & abs(t)>1.96,.N],
                    n_neg_sig = per_fac[slope<0 & abs(t)>1.96,.N],
                    binom_p = bt$p.value)),
  sample = list(start_hm = hm2str(SAMPLE_START_HM), end_hm = hm2str(SAMPLE_END_HM),
                n_months = uniqueN(FAMP$hm))
)
saveRDS(res, file.path(OUT,"p2_tier1.rds"))
write(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null"),
      file.path(OUT,"p2_tier1.json"))
cat("\n[done] phase2\n")
