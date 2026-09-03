## WT-R20260829_006 Phase 4 — 기전 반증 (c) σ²_β 전달식 · (d) 고유값 정렬 방향성
##  + 2급 역방향 비대칭 보완 (TS-FMOM 의 base-only 알파)
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite);
  library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
P3 <- readRDS(file.path(OUT,"p3_tier2.rds"))
D <- P3$D; Fm <- P3$Fm; volm <- P3$volm; sgn <- P3$sgn; nonmom <- P3$nonmom; FW <- P3$FW
M <- readRDS(file.path(OUT,"p1_market.rds"))
d2hm <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m")) + 1L
hm2str <- function(h) sprintf("%04d-%02d", (h-1L)%/%12L, (h-1L)%%12L + 1L)
SAMPLE_START_HM <- 2006L*12L + 1L

nwfit <- function(f, dat, lag = 3L) {
  m <- lm(f, data = dat); ct <- coeftest(m, vcov. = NeweyWest(m, lag = lag, prewhite = FALSE))
  list(coef = ct[,1], t = ct[,3], p = ct[,4], n = nrow(dat))
}

## ═══ 0. 2급 역방향 비대칭 — TS-FMOM 의 base-only 알파 ═══
f_fm_base <- nwfit(FMOM ~ MKT + SIZEF + VALF, D)
f_fm_full <- nwfit(FMOM ~ MKT + SIZEF + VALF + M02, D)
f_m02_base <- nwfit(M02 ~ MKT + SIZEF + VALF, D)
f_m02_full <- nwfit(M02 ~ MKT + SIZEF + VALF + FMOM, D)
asym <- data.table(
  direction = c("M02 ~ base","M02 ~ base+FMOM","FMOM ~ base","FMOM ~ base+M02"),
  intercept = c(f_m02_base$coef[1], f_m02_full$coef[1], f_fm_base$coef[1], f_fm_full$coef[1]),
  t = c(f_m02_base$t[1], f_m02_full$t[1], f_fm_base$t[1], f_fm_full$t[1]))
asym[, retention := c(NA, intercept[2]/intercept[1], NA, intercept[4]/intercept[3])]
cat("\n══════ 2급 비대칭 (양방향) ══════\n"); print(asym)

## ═══ 1. (c) σ²_β — 전달식 둘째 요소 ═══
cat("\n══════ (c) σ²_β 전달식 분해 ══════\n")
RET <- M$RET_DT[, .(Ticker, hm = d2hm(Date), r = Ret_1m)]
UN  <- M$UNIV_DT[, .(Ticker, hm = d2hm(Date))]
LQ  <- M$LIQ_DT[, .(Ticker, hm = d2hm(Date), adv)]
RET <- merge(RET, UN, by = c("Ticker","hm"))
RET <- merge(RET, LQ, by = c("Ticker","hm"), all.x = TRUE)[is.na(adv) | adv >= 2e8]
FWn <- FW[, c("hm", nonmom), with = FALSE]
anchors <- seq(SAMPLE_START_HM + 59L, max(FW$hm), by = 12L)
sig2b <- rbindlist(lapply(anchors, function(a) {
  win <- (a-59L):a
  RR <- RET[hm %in% win]
  cnt <- RR[, .N, by = Ticker][N >= 54L]
  RR <- RR[Ticker %in% cnt$Ticker]
  if (uniqueN(RR$Ticker) < 50) return(NULL)
  X <- as.matrix(FWn[hm %in% win][order(hm)][, ..nonmom])
  hmv <- FWn[hm %in% win][order(hm)]$hm
  bl <- RR[, {
      xi <- X[match(hm, hmv), , drop = FALSE]
      ok <- complete.cases(xi) & is.finite(r)
      if (sum(ok) < 40) NULL else {
        cf <- tryCatch(coef(lm.fit(cbind(1, xi[ok,,drop=FALSE]), r[ok])), error=function(e) NULL)
        if (is.null(cf)) NULL else as.list(setNames(cf[-1], nonmom))
      } }, by = Ticker]
  if (is.null(bl) || nrow(bl) < 50) return(NULL)
  data.table(anchor = a, n_stocks = nrow(bl),
             family = nonmom,
             var_beta = sapply(nonmom, function(f) var(bl[[f]], na.rm = TRUE)))
}))
sb <- sig2b[, .(mean_var_beta = mean(var_beta, na.rm = TRUE),
                median_var_beta = median(var_beta, na.rm = TRUE),
                n_anchors = uniqueN(anchor)), by = family]
print(sb)

## 팩터 자기공분산: cov(형성창 평균, 당월 수익)
autocov <- rbindlist(lapply(nonmom, function(f) {
  x <- Fm[, f]; n <- length(x)
  fm <- rep(NA_real_, n)
  for (i in 13:n) fm[i] <- mean(x[(i-12):(i-1)], na.rm = TRUE)
  ix <- which(is.finite(fm) & is.finite(x) & FW$hm >= SAMPLE_START_HM)
  data.table(family = f, cov_form_cur = cov(fm[ix], x[ix]),
             ac1 = cov(x[ix], x[ix-1]), mean_ret = mean(x[ix]))
}))
trans <- merge(autocov, sb, by = "family")
trans[, term1_contrib := cov_form_cur * mean_var_beta]
print(trans[order(-term1_contrib)])
cat(sprintf("\nΣ_f cov(형성,당월)·σ²_β = %.6f /월 | 실측 M02 평균 = %.6f /월 | 비율 = %.3f\n",
            sum(trans$term1_contrib), mean(D$M02), sum(trans$term1_contrib)/mean(D$M02)))

## ═══ 2. (d) 고유값 정렬 방향성 ═══
cat("\n══════ (d) 고유값 정렬 방향성 (재귀 OOS PC) ══════\n")
Fn <- Fm[, nonmom, drop = FALSE]
nT <- nrow(Fn); K <- ncol(Fn)
pcret <- matrix(NA_real_, nT, K)
eigv  <- matrix(NA_real_, nT, K)
for (i in 61:nT) {
  hist <- Fn[1:(i-1), , drop = FALSE]
  hist <- hist[complete.cases(hist), , drop = FALSE]
  if (nrow(hist) < 60) next
  mu <- colMeans(hist); sdv <- apply(hist, 2, sd)
  Z <- scale(hist, center = mu, scale = sdv)
  e <- eigen(cor(Z), symmetric = TRUE)
  cur <- Fn[i, ]
  if (any(!is.finite(cur))) next
  zc <- (cur - mu)/sdv
  raw <- as.numeric(zc %*% e$vectors)             # PC 수익 (t 까지 고유벡터)
  histpc <- as.matrix(Z) %*% e$vectors            # t 까지 스케일
  pcret[i, ] <- raw / apply(histpc, 2, sd)        # t 까지 데이터로 leverage
  eigv[i, ]  <- e$values
}
pcdt <- as.data.table(pcret); setnames(pcdt, paste0("PC", 1:K)); pcdt[, hm := FW$hm]
pcl <- melt(pcdt, id.vars = "hm", variable.name = "pc", value.name = "r")[!is.na(r)]
pcl[, pcn := as.integer(sub("PC","",pc))]
setorder(pcl, pcn, hm)
pcl[, form := { rs <- shift(r,1L); frollmean(rs, 12L, na.rm=FALSE) }, by = pcn]
pcl[, x := as.integer(form > 0)]
pcp <- pcl[!is.na(x) & hm >= SAMPLE_START_HM]
per_pc <- pcp[, { fit <- lm(r ~ x); ct <- summary(fit)$coefficients
                  .(n = .N, slope = ct[2,1], t = ct[2,3], mean_eig = NA_real_) }, by = pcn]
eigmean <- colMeans(eigv, na.rm = TRUE)
per_pc[, mean_eig := eigmean[pcn]]
print(per_pc[order(pcn)])
hi <- pcp[pcn <= 5]; lo <- pcp[pcn > K-5]
fh <- lm(r ~ x, data = hi); fl <- lm(r ~ x, data = lo)
ch <- summary(fh)$coefficients; cl <- summary(fl)$coefficients
cat(sprintf("\n상위 5 PC pooled 기울기 %.5f (t %.2f) | 하위 5 PC %.5f (t %.2f)\n",
            ch[2,1], ch[2,3], cl[2,1], cl[2,3]))
cat(sprintf("고유값 상위5 평균 %.3f · 하위5 평균 %.3f\n",
            mean(eigmean[1:5]), mean(eigmean[(K-4):K])))
sp <- cor(per_pc$pcn, per_pc$t, method = "spearman")
cat(sprintf("PC 순위(고유값 내림차순) vs 자기상관 t 의 Spearman = %.3f  (음수 = 고고유값에 집중 = EL2022 방향)\n", sp))

res <- list(
  tier2_asymmetry = asym,
  sigma2_beta = list(per_family = sb, transmission = trans,
                     sum_term1_per_month = sum(trans$term1_contrib),
                     realized_m02_mean = mean(D$M02),
                     ratio_term1_to_realized = sum(trans$term1_contrib)/mean(D$M02),
                     n_anchors = uniqueN(sig2b$anchor),
                     window = "trailing 60m, 12개월 간격 anchor, 최소 54관측"),
  eigen_ordering = list(per_pc = per_pc[order(pcn)],
                        top5_slope = ch[2,1], top5_t = ch[2,3],
                        bottom5_slope = cl[2,1], bottom5_t = cl[2,3],
                        mean_eig_top5 = mean(eigmean[1:5]),
                        mean_eig_bottom5 = mean(eigmean[(K-4):K]),
                        spearman_rank_vs_t = sp,
                        spec = "재귀 OOS PC (t 까지 상관행렬 고유벡터 · t 까지 스케일). ★일별 아님 — 월별 대체 사양",
                        K = K)
)
saveRDS(res, file.path(OUT,"p4_mech.rds"))
write(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=8, na="null"), file.path(OUT,"p4_mech.json"))
cat("\n[done] phase4\n")
