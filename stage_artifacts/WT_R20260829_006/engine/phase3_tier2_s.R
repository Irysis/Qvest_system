## WT-R20260829_006 Phase 3 — 2급(스패닝) + F-사다리 양성대조 + sham-FMOM 무신호 대조
##  M02 = EL2022 Table 6 Panel A 규격 개별주 모멘텀 요인 (시총 2 × 과거성과 3, 상위2 − 하위2, 12-2)
##  TS-FMOM = 계열 팩터 시계열 모멘텀 (12-1 부호, t 시점까지 변동성 동일화)
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite);
  library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
LIQ_MIN <- 2e8; MOM_FAM <- "momentum"; SAMPLE_START_HM <- 2006L*12L + 1L

M <- readRDS(file.path(OUT,"p1s_market.rds"))
RET_DT <- M$RET_DT; BENCH_DT <- M$BENCH_DT; LIQ_DT <- M$LIQ_DT
SIZE_DT <- M$SIZE_DT; UNIV_DT <- M$UNIV_DT
FAM_RET <- as.data.table(read_parquet(file.path(OUT,"p1s_family_ls_returns.parquet")))
d2hm <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m")) + 1L
hm2str <- function(h) sprintf("%04d-%02d", (h-1L)%/%12L, (h-1L)%%12L + 1L)
FAM_RET[, hm := d2hm(Date)]
RET_DT[, hm := d2hm(Date)]            # hm = 이 Ret_1m 이 실현되는 홀딩월
BENCH_DT[, hm := d2hm(Date)]

## ═══════════ 1. M02 개별주 모멘텀 요인 (2×3, 12-2) ═══════════
UNIV_DT[, hm := d2hm(Date)]; LIQ_DT[, hm := d2hm(Date)]; SIZE_DT[, hm := d2hm(Date)]
R <- RET_DT[, .(Ticker, hm, r = Ret_1m)]
setorder(R, Ticker, hm)
## 과거 11개월 누적수익 (홀딩월 m 기준 m-12..m-2 = R 의 hm ∈ [m-12, m-2])
allhm <- seq(min(R$hm), max(R$hm))
RW <- dcast(R, hm ~ Ticker, value.var = "r")
setorder(RW, hm)
hmv <- RW$hm; Rm <- as.matrix(RW[, -1, with = FALSE]); tick <- colnames(Rm)
logR <- log1p(Rm)
cum11 <- matrix(NA_real_, nrow(Rm), ncol(Rm), dimnames = dimnames(Rm))
for (i in seq_len(nrow(Rm))) {
  lo <- i - 11L; hi <- i - 1L          # 홀딩월 hmv[i]+1 기준 형성창: hmv[i-11..i-1]
  if (lo < 1) next
  blk <- logR[lo:hi, , drop = FALSE]
  ok <- colSums(!is.na(blk)) >= 9L
  s <- colSums(blk, na.rm = TRUE); s[!ok] <- NA_real_
  cum11[i, ] <- expm1(s)
}
MOM <- as.data.table(cum11); MOM[, hm_sig := hmv]
MOM <- melt(MOM, id.vars = "hm_sig", variable.name = "Ticker", value.name = "mom122",
            variable.factor = FALSE)
MOM <- MOM[!is.na(mom122)]
MOM[, hm := hm_sig + 1L]               # 홀딩월

## 유니버스 ∩ 유동성 ∩ 실현수익
base <- merge(R, MOM[, .(Ticker, hm, mom122)], by = c("Ticker","hm"))
uu <- UNIV_DT[, .(Ticker, hm)]
base <- merge(base, uu, by = c("Ticker","hm"))
lq <- LIQ_DT[, .(Ticker, hm, adv)]
base <- merge(base, lq, by = c("Ticker","hm"), all.x = TRUE)
base <- base[is.na(adv) | adv >= LIQ_MIN]
sz <- SIZE_DT[, .(Ticker, hm, Size)]
base <- merge(base, sz, by = c("Ticker","hm"))
base <- base[is.finite(Size) & Size > 0]
cat("[M02] panel rows", nrow(base), " months", uniqueN(base$hm), "\n")

base[, sz_grp := ifelse(Size > median(Size, na.rm = TRUE), "B", "S"), by = hm]
base[, mq := { q <- quantile(mom122, c(0.3,0.7), na.rm = TRUE)
               fifelse(mom122 <= q[1], "L", fifelse(mom122 >= q[2], "W", "M")) }, by = .(hm, sz_grp)]
p6 <- base[, .(pr = mean(r)), by = .(hm, sz_grp, mq)]
p6w <- dcast(p6, hm ~ sz_grp + mq, value.var = "pr")
p6w <- p6w[complete.cases(p6w)]
p6w[, M02 := (B_W + S_W)/2 - (B_L + S_L)/2]
M02 <- p6w[, .(hm, M02)]
cat("[M02] months", nrow(M02), " mean", sprintf("%.4f", mean(M02$M02)),
    " sd", sprintf("%.4f", sd(M02$M02)), "\n")

## ═══════════ 2. 계열 팩터 수익 wide + TS-FMOM ═══════════
FW <- dcast(FAM_RET, hm ~ family, value.var = "ls")
setorder(FW, hm)
fams <- setdiff(names(FW), "hm")
nonmom <- setdiff(fams, MOM_FAM)
Fm <- as.matrix(FW[, ..fams]); rownames(Fm) <- as.character(FW$hm)

## 확장창 변동성 (t 시점까지, 최소 24m) — C1 준수(full-sample 금지)
volm <- matrix(NA_real_, nrow(Fm), ncol(Fm), dimnames = dimnames(Fm))
for (i in seq_len(nrow(Fm))) {
  if (i < 25) next
  blk <- Fm[1:(i-1), , drop = FALSE]
  volm[i, ] <- apply(blk, 2, sd, na.rm = TRUE)
}
## 12-1 형성 부호 (m-12..m-1 평균)
sgn <- matrix(NA_real_, nrow(Fm), ncol(Fm), dimnames = dimnames(Fm))
for (i in seq_len(nrow(Fm))) {
  lo <- i-12L; hi <- i-1L; if (lo < 1) next
  mu <- colMeans(Fm[lo:hi, , drop = FALSE], na.rm = TRUE)
  sgn[i, ] <- sign(mu)
}

build_fmom <- function(cols, sign_mat = sgn) {
  W <- sign_mat[, cols, drop = FALSE] / volm[, cols, drop = FALSE]
  X <- Fm[, cols, drop = FALSE]
  num <- rowSums(W * X, na.rm = TRUE)
  den <- rowSums(is.finite(W) & is.finite(X))
  out <- ifelse(den > 0, num/den, NA_real_)
  out * 0.05      # 스케일만 조정(회귀 절편·t 불변)
}
FMOM_all <- build_fmom(nonmom)
FMOM_inc <- build_fmom(fams)

## ═══════════ 3. 기본 요인집합 (MKT · SIZE · VALUE) ═══════════
BASE <- data.table(hm = FW$hm,
                   SIZEF = if ("size" %in% fams) FW[["size"]] else NA_real_,
                   VALF  = if ("value" %in% fams) FW[["value"]] else NA_real_,
                   FMOM  = FMOM_all, FMOM_inc = FMOM_inc)
BASE <- merge(BASE, BENCH_DT[, .(hm, MKT = BM_Ret)], by = "hm")
D <- merge(M02, BASE, by = "hm")
D <- D[hm >= SAMPLE_START_HM]
D <- D[complete.cases(D[, .(M02, SIZEF, VALF, MKT, FMOM)])]
cat("[tier2] regression months", nrow(D), " ", hm2str(min(D$hm)), "~", hm2str(max(D$hm)), "\n")

nwfit <- function(f, dat, lag = 3L) {
  m <- lm(f, data = dat)
  ct <- coeftest(m, vcov. = NeweyWest(m, lag = lag, prewhite = FALSE))
  list(coef = ct[,1], se = ct[,2], t = ct[,3], p = ct[,4],
       r2 = summary(m)$r.squared, n = nrow(dat))
}

## 사전 검정력 (2급) — 원(raw) 프리미엄을 참조 효과크기로
raw_mean <- mean(D$M02); raw_se <- {
  m0 <- lm(M02 ~ 1, data = D); sqrt(NeweyWest(m0, lag=3, prewhite=FALSE)[1,1]) }
m_ctrl <- lm(M02 ~ MKT + SIZEF + VALF + FMOM, data = D)
resid_sd <- sd(residuals(m_ctrl))
se_int_ctrl <- sqrt(NeweyWest(m_ctrl, lag=3, prewhite=FALSE)[1,1])
mde80_t2 <- (qnorm(0.975)+qnorm(0.80)) * se_int_ctrl
pc_t2 <- list(label = "tier2_spanning_intercept", n_months = nrow(D),
              effect_ref_raw_mean = raw_mean, effect_ref_note =
                "참조 효과크기 = KR 개별주 모멘텀 요인의 무조건부 평균(실측). 원 프리미엄 전체가 잔여로 남는 경우가 최대 검출 대상.",
              se_intercept_controlled = se_int_ctrl, mde80 = mde80_t2,
              ratio = abs(raw_mean)/mde80_t2,
              expected_t = raw_mean/se_int_ctrl,
              power = pnorm(abs(raw_mean)/se_int_ctrl - qnorm(0.975)) +
                      pnorm(-abs(raw_mean)/se_int_ctrl - qnorm(0.975)))
cat("\n══════ 2급 사전 검정력 ══════\n"); str(pc_t2)

cat("\n══════ 2급 — 스패닝 회귀 ══════\n")
f_raw   <- nwfit(M02 ~ 1, D)
f_base  <- nwfit(M02 ~ MKT + SIZEF + VALF, D)
f_span  <- nwfit(M02 ~ MKT + SIZEF + VALF + FMOM, D)
f_spani <- nwfit(M02 ~ MKT + SIZEF + VALF + FMOM_inc, D)
cat("[raw M02 mean]\n"); print(rbind(coef=f_raw$coef, t=f_raw$t))
cat("[base 통제]\n");   print(rbind(coef=f_base$coef, t=f_base$t))
cat("[base + TS-FMOM (비-모멘텀 계열)]\n"); print(rbind(coef=f_span$coef, t=f_span$t))
cat("[base + TS-FMOM (모멘텀 계열 포함 — 참고)]\n"); print(rbind(coef=f_spani$coef, t=f_spani$t))

## 역방향
f_rev <- nwfit(FMOM ~ MKT + SIZEF + VALF + M02, D)
cat("[역방향: TS-FMOM ~ base + M02]\n"); print(rbind(coef=f_rev$coef, t=f_rev$t))

## ═══════════ 4. F-사다리 양성 대조 ═══════════
cat("\n══════ F-사다리 (양성 대조) ══════\n")
set.seed(20260829)
ladder <- rbindlist(lapply(c(1L,3L,5L,10L,length(nonmom)), function(k) {
  nd <- if (k >= length(nonmom)) 1L else 200L
  ts <- numeric(nd); bs <- numeric(nd)
  for (j in seq_len(nd)) {
    cols <- if (k >= length(nonmom)) nonmom else sample(nonmom, k)
    fm <- build_fmom(cols)
    dd <- merge(D[, .(hm, M02, MKT, SIZEF, VALF)],
                data.table(hm = FW$hm, FM = fm), by = "hm")
    dd <- dd[complete.cases(dd)]
    ff <- nwfit(M02 ~ MKT + SIZEF + VALF + FM, dd)
    ts[j] <- ff$t[1]; bs[j] <- ff$coef[1]
  }
  data.table(F = k, n_draws = nd, mean_abs_t_intercept = mean(abs(ts)),
             median_abs_t = median(abs(ts)), mean_intercept = mean(bs))
}))
print(ladder)

## ═══════════ 5. sham-FMOM 무신호 대조 (검사기 양성 대조) ═══════════
cat("\n══════ sham-FMOM (부호 무작위) ══════\n")
set.seed(7)
nsim <- 300L
sham_t <- numeric(nsim); sham_beta_t <- numeric(nsim)
for (j in seq_len(nsim)) {
  sg <- sgn
  rs <- matrix(sample(c(-1,1), length(sg), replace = TRUE), nrow(sg), ncol(sg),
               dimnames = dimnames(sg))
  sg[] <- ifelse(is.finite(sg), rs, NA_real_)
  fm <- build_fmom(nonmom, sign_mat = sg)
  dd <- merge(D[, .(hm, M02, MKT, SIZEF, VALF)], data.table(hm = FW$hm, FM = fm), by = "hm")
  dd <- dd[complete.cases(dd)]
  ff <- nwfit(M02 ~ MKT + SIZEF + VALF + FM, dd)
  sham_t[j] <- ff$t[1]; sham_beta_t[j] <- ff$t[5]
}
cat(sprintf("실측 TS-FMOM: 절편 t = %.3f · FMOM 계수 t = %.3f\n", f_span$t[1], f_span$t[5]))
cat(sprintf("sham 절편 |t| 분포: 중앙 %.3f · 90%% %.3f | sham FMOM계수 |t|: 중앙 %.3f · 90%% %.3f\n",
    median(abs(sham_t)), quantile(abs(sham_t),0.9), median(abs(sham_beta_t)),
    quantile(abs(sham_beta_t),0.9)))
sham_p_beta <- mean(abs(sham_beta_t) >= abs(f_span$t[5]))
cat(sprintf("sham 대비 FMOM 계수 t 경험 p = %.4f (구별 가능 = p 작음)\n", sham_p_beta))

res <- list(
  power_contract_tier2 = pc_t2,
  m02 = list(n_months = nrow(M02), mean = mean(M02$M02), sd = sd(M02$M02),
             spec = "EL2022 Table 6 Panel A: 시총2 × 과거성과3(30/70), 상위2 평균 − 하위2 평균, 12-2 스킵월"),
  fmom = list(spec = "계열 12-1 부호(스킵월 없음) × 확장창 변동성 역수 가중, 비-모멘텀 계열 14",
              n_families = length(nonmom), families = nonmom),
  spanning = list(
    raw = list(coef = as.list(f_raw$coef), t = as.list(f_raw$t)),
    base = list(coef = as.list(f_base$coef), t = as.list(f_base$t), r2 = f_base$r2),
    with_fmom = list(coef = as.list(f_span$coef), t = as.list(f_span$t), r2 = f_span$r2),
    with_fmom_incl_momentum = list(coef = as.list(f_spani$coef), t = as.list(f_spani$t), r2 = f_spani$r2),
    reverse = list(coef = as.list(f_rev$coef), t = as.list(f_rev$t), r2 = f_rev$r2),
    n_months = nrow(D), sample = c(hm2str(min(D$hm)), hm2str(max(D$hm)))),
  f_ladder = ladder,
  sham = list(nsim = nsim, obs_intercept_t = f_span$t[1], obs_fmom_beta_t = f_span$t[5],
              sham_abs_t_intercept_median = median(abs(sham_t)),
              sham_abs_t_intercept_q90 = as.numeric(quantile(abs(sham_t),0.9)),
              sham_abs_t_fmom_median = median(abs(sham_beta_t)),
              sham_abs_t_fmom_q90 = as.numeric(quantile(abs(sham_beta_t),0.9)),
              empirical_p_fmom_beta = sham_p_beta)
)
saveRDS(list(res=res, D=D, M02=M02, FW=FW, Fm=Fm, volm=volm, sgn=sgn,
             nonmom=nonmom, base_panel=base), file.path(OUT,"p3s_tier2.rds"))
write(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null"),
      file.path(OUT,"p3s_tier2.json"))
cat("\n[done] phase3\n")
