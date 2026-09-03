## RISK Stage 4 — book risk decomposition / family concentration / cap-tier / regime corr / turnover
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
S <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
source("02_Infrastructure/portfolio/hrp_core.R")
R1<-readRDS(file.path(O,"r1_reg.rds")); R2<-readRDS(file.path(O,"r2_omega.rds")); R3<-readRDS(file.path(O,"r3_sigma.rds"))
mk<-readRDS(file.path(S,"p1s_market.rds"))
U<-R3$U; B<-R3$B; OM<-R3$OM; SIGMA<-R3$SIGMA; Dvec<-R3$Dvec; FACN<-R3$FACN; av<-R3$av
SIG<-as.Date("2026-08-28")

## ── 0. as_of 커버리지 결손 원인 분해 ────────────────────────────────────────
uni <- mk$UNIV_DT[Date==SIG, .(Ticker)]
liq <- mk$LIQ_DT[Date==SIG, .(Ticker, adv)]
bet <- unique(R3$AS[, .(Ticker)])
drop <- setdiff(av$Ticker, U$Ticker)
d1 <- length(setdiff(drop, uni$Ticker))
d2 <- length(intersect(drop, merge(uni,liq,by="Ticker")[adv<2e8]$Ticker))
cat("[coverage] alpha 347 -> Sigma", nrow(U), " dropped", length(drop),
    " | not in K200/KQ150 at as_of:", d1, " | liq<2e8:", d2, " | other(beta/size 부족):",
    length(drop)-d1-d2, "\n")

## ── 1. 진단용 기준 book (전략 사양 = top-25 EW · 비중 제안 아님) ───────────
sc <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_006/alpha_scores.parquet"))
asf <- sc[layer=="as_of"][order(-score)]
bk_all <- head(asf$Ticker, 25)
bk <- head(asf[Ticker %in% U$Ticker]$Ticker, 25)
cat("[book] top25(alpha 원순위) 중 Sigma 유니버스 잔존:", length(intersect(bk_all,U$Ticker)),
    "/25 -> 진단 book 은 잔존 상위 25종 사용\n")
idx <- match(bk, rownames(SIGMA)); w <- rep(1/length(bk), length(bk))
Sb <- SIGMA[idx, idx]; Bb <- B[idx, , drop=FALSE]
tot <- as.numeric(t(w)%*%Sb%*%w)
xp  <- as.numeric(t(w)%*%Bb)                       # book factor exposure
fvar<- as.numeric(t(xp)%*%OM%*%xp)
svar<- sum(w^2*Dvec[idx])
cat(sprintf("[book] ann vol %.2f pct | factor share %.4f | specific share %.4f\n",
    sqrt(tot*12)*100, fvar/tot, svar/tot))
mc <- xp * as.numeric(OM %*% xp) / tot            # per-factor variance contribution
names(mc) <- FACN
grp <- ifelse(FACN=="Intercept","Market", ifelse(grepl("^s_",FACN),"Sector",
        ifelse(FACN %in% c("x_beta","x_size","x_liq"),"Style","Family")))
gcon <- tapply(mc, grp, sum); gcon <- c(gcon, Specific=svar/tot)
cat("[book] variance share by group:\n"); print(round(sort(gcon,decreasing=TRUE),4))
cat("[book] top-8 single factor contributions:\n"); print(round(sort(mc,decreasing=TRUE)[1:8],4))
names(xp) <- FACN
cat("[book] exposures (top |x|):\n"); print(round(xp[order(-abs(xp))][1:12],3))

## ── 2. 계열 집중 (12 alpha families) ───────────────────────────────────────
FL <- as.data.table(read_parquet(file.path(S,"p1s_family_ls_returns.parquet")))
FLW <- dcast(FL, Date ~ family, value.var="ls"); setorder(FLW,Date)
FLW <- FLW[Date>=as.Date("2005-12-01")]
ALPHA_FAM <- c("accrual","crowding","defense","growth","investor_flow","leverage",
               "liquidity","quality","regime","risk","size","value")
Mfam <- as.matrix(FLW[, ..ALPHA_FAM])
Cf <- cor(Mfam)
pr <- function(M){e<-eigen(M,symmetric=TRUE,only.values=TRUE)$values;e<-pmax(e,0);(sum(e)^2)/sum(e^2)}
cat(sprintf("[family] n=%d  mean|rho|=%.4f  participation-ratio=%.2f  PC1 share=%.4f\n",
    nrow(Mfam), mean(abs(Cf[upper.tri(Cf)])), pr(Cf),
    eigen(Cf,only.values=TRUE)$values[1]/ncol(Cf)))
ev <- eigen(Cf,only.values=TRUE)$values
cat("[family] eigen share cum:", paste(round(cumsum(ev)/sum(ev),3)[1:6],collapse=" "),"\n")
## 구간별
i1 <- FLW$Date < as.Date("2015-01-01"); i2 <- !i1
C1f <- cor(Mfam[i1,]); C2f <- cor(Mfam[i2,])
cat(sprintf("[family] pre2015 n=%d mean|rho|=%.4f PR=%.2f | post2015 n=%d mean|rho|=%.4f PR=%.2f | relFro=%.4f\n",
    sum(i1), mean(abs(C1f[upper.tri(C1f)])), pr(C1f), sum(i2),
    mean(abs(C2f[upper.tri(C2f)])), pr(C2f), norm(C1f-C2f,"F")/norm((C1f+C2f)/2,"F")))
## Jennrich test (equality of correlation matrices)
jennrich <- function(R1m,R2m,n1,n2){ p<-ncol(R1m); c<-n1/(n1+n2)
  Rb <- c*R1m + (1-c)*R2m; Ri <- solve(Rb)
  Z  <- sqrt(n1*n2/(n1+n2)) * (R1m-R2m)
  S  <- Ri %*% Z
  dg <- diag(Ri*Rb)  # placeholder
  d  <- diag(S); Dm <- diag(dg,p)
  ## Jennrich 1970 statistic
  Smat <- Ri*Rb; Smat <- Smat + diag(p)
  stat <- 0.5*sum(diag(S%*%S)) - as.numeric(t(d) %*% solve(Smat) %*% d)
  df <- p*(p-1)/2
  list(stat=stat, df=df, p=pchisq(stat,df,lower.tail=FALSE)) }
jt <- jennrich(C1f,C2f,sum(i1),sum(i2))
cat(sprintf("[family] Jennrich chi2=%.1f df=%d p=%.4g\n", jt$stat, jt$df, jt$p))

## alpha 가중 계열 노출 집중 (weight_theta 사용)
apk <- fromJSON("qepm/mailbox/worktask/WT-R20260829_006/alpha_package.json", simplifyVector=TRUE)
fs  <- as.data.table(apk$factor_specs)[factor_family %in% ALPHA_FAM, .(factor_family, weight_theta)]
wf  <- setNames(fs$weight_theta, fs$factor_family)
wf  <- wf/sum(abs(wf))
CFam <- cov(Mfam)[names(wf), names(wf)]
sig_fam <- as.numeric(t(wf)%*%CFam%*%wf)
contr   <- wf*as.numeric(CFam%*%wf)/sig_fam
cat("[family] alpha-weight-implied variance share per family:\n"); print(round(sort(contr,decreasing=TRUE),4))
cat(sprintf("[family] HHI of |w_f| = %.4f  n_eff(1/HHI) = %.2f  HHI of variance contrib = %.4f\n",
    sum((abs(wf)/sum(abs(wf)))^2), 1/sum((abs(wf)/sum(abs(wf)))^2), sum(contr^2)))

## ── 3. 섹터 / cap-tier 집중 ────────────────────────────────────────────────
bkU <- U[Ticker %in% bk]
nb <- nrow(bkU); sw <- bkU[, .N, by=sec9]; shhi <- sum((sw$N/nb)^2)
cat("[conc] book sector HHI =", round(shhi,4), " n_eff =", round(1/shhi,2), "\n")
print(bkU[, .N, by=sec9][order(-N)])
uh <- U[, .N, by=sec9][, sum((N/nrow(U))^2)]
cat("[conc] universe sector HHI =", round(uh,4),"\n")
## cap tier (as_of Size, 유니버스 기준 상위 20pct=MEGA / 20~60=MID / 하위 40=SMALL)
U[, sz_rk := frank(-Size)/.N]
U[, cap_tier := ifelse(sz_rk<=0.2,"MEGA", ifelse(sz_rk<=0.6,"MID","SMALL"))]
alp <- merge(U[,.(Ticker,cap_tier,sz_rk)], av, by="Ticker")
bkt <- U[Ticker %in% bk, .N, by=cap_tier]
## active risk share by tier: book EW vs cap-w universe benchmark
wc <- U$Size/sum(U$Size); wb <- rep(0,nrow(U)); wb[match(bk,U$Ticker)] <- 1/length(bk)
wa <- wb - wc
Sig <- SIGMA
te2 <- as.numeric(t(wa)%*%Sig%*%wa)
cat(sprintf("[captier] active TE (vs cap-w universe) = %.2f pct ann\n", sqrt(te2*12)*100))
tier_rows <- list()
for (tt in c("MEGA","MID","SMALL")) {
  sel <- U$cap_tier==tt
  wat <- wa; wat[!sel] <- 0
  ars <- as.numeric(t(wat)%*%Sig%*%wa)/te2
  ash <- sum(alp[cap_tier==tt & Ticker %in% bk]$alpha)/sum(alp[Ticker %in% bk]$alpha)
  n_in <- sum(U$cap_tier==tt & U$Ticker %in% bk)
  tier_rows[[tt]] <- data.table(tier=tt, n_book=n_in, active_risk_share=round(ars,4),
                                alpha_share=round(ash,4))
}
TIER <- rbindlist(tier_rows); print(TIER)
## dual basis: EW-universe vs cap-w universe 벤치 대비 book 노출 차
wew <- rep(1/nrow(U), nrow(U))
te_ew <- sqrt(as.numeric(t(wb-wew)%*%Sig%*%(wb-wew))*12)*100
cat(sprintf("[captier] TE vs EW-universe = %.2f pct  vs cap-w = %.2f pct  divergence = %.2f pp\n",
    te_ew, sqrt(te2*12)*100, abs(te_ew - sqrt(te2*12)*100)))

## ── 4. regime correlation (국면별 평균 종목 상관 · 계열 상관) ──────────────
ben <- mk$BENCH_DT[Date>=as.Date("2005-12-01")]; setorder(ben,Date)
ben[, bm12 := frollsum(log(1+BM_Ret), 12)]
ben[, vol12 := frollapply(BM_Ret, 12, sd)]
ben[, regime := ifelse(is.na(bm12),"NA", ifelse(bm12<0,"BEAR","BULL"))]
vmed <- median(ben$vol12, na.rm=TRUE)
ben[, volreg := ifelse(is.na(vol12),"NA", ifelse(vol12>vmed,"HIVOL","LOVOL"))]
ER <- R1$ER
CVd <- R1$CV
rgs <- merge(CVd[,.(Date,r2,sd_res,sd_tot)], ben[,.(Date,regime,volreg,BM_Ret)], by="Date")
## 평균 종목 pairwise 상관 프록시: 1 - (평균 특이분산/평균 총분산) 을 공통성으로 사용
regrows <- list()
for (rg in c("BULL","BEAR","HIVOL","LOVOL")) {
  sel <- if (rg %in% c("BULL","BEAR")) rgs$regime==rg else rgs$volreg==rg
  d <- rgs[sel]
  if (nrow(d)<12) next
  ff <- R2$Fm[as.character(d$Date), , drop=FALSE]
  Cg <- cor(ff)
  regrows[[rg]] <- data.table(regime=rg, n_months=nrow(d),
    mean_cross_sec_r2=round(mean(d$r2),4),
    common_share=round(mean(1-(d$sd_res^2/d$sd_tot^2)),4),
    specific_vol_ann=round(mean(d$sd_res)*sqrt(12)*100,2),
    market_fac_vol_ann=round(sd(ff[,"Intercept"])*sqrt(12)*100,2),
    mean_abs_factor_rho=round(mean(abs(Cg[upper.tri(Cg)])),4),
    factor_pr=round(pr(Cg),2))
}
REG <- rbindlist(regrows); print(REG)

## 계열 L/S 상관 — 국면별
regfam <- list()
FLW2 <- merge(FLW, ben[,.(Date,bmreg=regime,volreg2=volreg)], by="Date")
for (rg in c("BULL","BEAR","HIVOL","LOVOL")) {
  sel <- if (rg %in% c("BULL","BEAR")) FLW2$bmreg==rg else FLW2$volreg2==rg
  Mx <- as.matrix(FLW2[sel, ..ALPHA_FAM]); if (nrow(Mx)<24) next
  Cx <- cor(Mx)
  regfam[[rg]] <- data.table(regime=rg, n=nrow(Mx),
    fam_mean_abs_rho=round(mean(abs(Cx[upper.tri(Cx)])),4), fam_pr=round(pr(Cx),2))
}
REGF <- rbindlist(regfam); print(REGF)

## ── 5. 회전율 위험 (top-25 명부 회전 · 진입/이탈 레그 수익 분산) ───────────
hist <- sc[layer=="history"]
setorder(hist, Date, -score)
TOP <- hist[, .(Ticker=head(Ticker,25)), by=Date]
dts <- sort(unique(TOP$Date))
tl <- list()
for (i in 2:length(dts)) {
  a <- TOP[Date==dts[i-1]]$Ticker; b <- TOP[Date==dts[i]]$Ticker
  ent <- setdiff(b,a); exi <- setdiff(a,b)
  ret <- mk$RET_DT[Date==dts[i]]
  re <- mean(ret[Ticker %in% ent]$Ret_1m, na.rm=TRUE)
  rx <- mean(ret[Ticker %in% exi]$Ret_1m, na.rm=TRUE)
  tl[[i]] <- data.table(Date=dts[i], n_ent=length(ent), to=length(ent)/25,
                        ret_ent=re, ret_exi=rx, gap=re-rx)
}
TO <- rbindlist(tl)
cat(sprintf("[turnover] mean monthly name turnover = %.4f (ann one-way = %.2f x)  median = %.3f\n",
    mean(TO$to), mean(TO$to)*12, median(TO$to)))
cat(sprintf("[turnover] entering-minus-exiting next-month return: mean %.4f  sd %.4f  t %.2f\n",
    mean(TO$gap,na.rm=TRUE), sd(TO$gap,na.rm=TRUE),
    mean(TO$gap,na.rm=TRUE)/(sd(TO$gap,na.rm=TRUE)/sqrt(sum(!is.na(TO$gap))))))
cat(sprintf("[turnover] trade-timing risk (ann sd of turnover-weighted leg gap) = %.2f pct\n",
    sd(TO$to*TO$gap, na.rm=TRUE)*sqrt(12)*100))
saveRDS(list(TO=TO, REG=REG, REGF=REGF, TIER=TIER, mc=mc, gcon=gcon, xp=xp, bk=bk,
             Cf=Cf, C1f=C1f, C2f=C2f, jt=jt, contr=contr, wf=wf, shhi=shhi,
             book_vol=sqrt(tot*12)*100, book_fac_share=fvar/tot, te_capw=sqrt(te2*12)*100,
             te_ew=te_ew, U=U, drop_n=length(drop), drop_uni=d1, drop_liq=d2,
             fam_pr=pr(Cf), fam_rho=mean(abs(Cf[upper.tri(Cf)]))),
        file.path(O,"r4_diag.rds"))
cat("[done]\n")
