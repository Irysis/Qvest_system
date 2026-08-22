## probe_a5_falsify5.R — M. 베타 아티팩트 검정
##  PORT_t 는 raw active(port - Market) 의 NW-t 다. 포트 베타>1 이고 Market 이 상승하면
##  active 는 기계적으로 양수가 된다. 2026 일별에서 팩터지수가 Market 대비 베타>1 로 움직이는 것을
##  관측했으므로, 베타 중립화 후에도 알파가 남는지 실측한다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/backtest_result_contract.R")
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log6.txt"), split = TRUE)
PT <- function(x) .nw_t_mean(x[is.finite(x)], lag = 3L)
IRf <- function(x){ x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(12) }
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market")); R[, ym := format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon, medate); NM <- nrow(mon); NAx <- 1+length(fac)
RET <- as.matrix(mon[, c("Market",fac), with=FALSE]); RET[!is.finite(RET)] <- 0
S <- matrix(NA_real_,NM,length(fac)); colnames(S) <- fac
for(fi in seq_along(fac)) for(m in 12:NM){ w <- (m-11):m
  S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
pr <- rep(NA_real_,NM); wprev <- rep(1/NAx,NAx); wcur <- NULL
for(m in 13:NM){ d <- m-1
  if(is.null(wcur) || ((m-13) %% 3 == 0)){ s <- S[d,]; pos <- which(is.finite(s)&s>0); w <- rep(0,NAx)
    if(length(pos)==0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos]); wcur <- w }
  ri <- RET[m,]; dlt <- sum(abs(wcur-wprev)); pr[m] <- sum(wcur*ri)-0.0015*dlt
  wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }
k <- is.finite(pr); p <- pr[k]; mk <- mon$Market[k]; a <- p-mk; dt <- mon$medate[k]
yy <- as.integer(format(dt,"%Y")); n <- length(p)

nwfit <- function(y, x){ f <- lm(y~x); ct <- coeftest(f, vcov=NeweyWest(f, lag=3, prewhite=FALSE))
  list(alpha_m=ct[1,1], alpha_t=ct[1,3], beta=ct[2,1], beta_t=ct[2,3]) }
cat("================ M: 베타 아티팩트 검정 ================\n")
cat(sprintf("  전체 n=%d | Market 연율수익=%.4f | 포트 연율수익=%.4f\n", n, mean(mk)*12, mean(p)*12))
f <- nwfit(p, mk)
cat(sprintf("  [전체] beta=%.4f (t=%.2f) | CAPM alpha=%.4f/월 = %.4f/년 (NW t=%.3f)\n",
    f$beta, f$beta_t, f$alpha_m, f$alpha_m*12, f$alpha_t))
cat(sprintf("  [전체] raw active 평균=%.4f/월 = %.4f/년 | PORT_t(raw, 게이트지표)=%.4f\n",
    mean(a), mean(a)*12, PT(a)))
cat(sprintf("  -> 베타 초과분(beta-1)*E[Rm] = %.4f/월 = %.4f/년 (raw active 의 %.1f%%)\n",
    (f$beta-1)*mean(mk), (f$beta-1)*mean(mk)*12, 100*(f$beta-1)*mean(mk)/mean(a)))
cat("\n  [구간별 beta / CAPM alpha / raw active]\n")
segs <- list(c(2007,2011), c(2012,2016), c(2017,2021), c(2022,2025), c(2026,2026), c(2007,2025))
res <- rbindlist(lapply(segs, function(s){ i <- yy>=s[1] & yy<=s[2]
  if(sum(i)<12) return(NULL); g <- nwfit(p[i], mk[i])
  data.table(seg=sprintf("%d-%d", s[1], s[2]), n=sum(i), mkt_ann=mean(mk[i])*12, beta=g$beta,
             capm_alpha_ann=g$alpha_m*12, capm_alpha_t=g$alpha_t,
             raw_active_ann=mean(a[i])*12, raw_pt=PT(a[i])) }))
print(res, digits=4)
cat("\n  [베타 중립 잔차 시계열의 PORT_t 등가]\n")
resid_all <- residuals(lm(p ~ mk))
cat(sprintf("    잔차 NW-t (전체, 절편 제거 전)=%.4f | CAPM alpha NW-t=%.4f vs raw PORT_t=%.4f\n",
    PT(resid_all), f$alpha_t, PT(a)))
i25 <- yy<=2025; g25 <- nwfit(p[i25], mk[i25])
cat(sprintf("    2026 제외: beta=%.4f CAPM alpha_ann=%.4f (t=%.3f) | raw PORT_t=%.4f\n",
    g25$beta, g25$alpha_m*12, g25$alpha_t, PT(a[i25])))
cat("\n  [연도별 beta] — 2026 이상 여부\n")
BY <- rbindlist(lapply(sort(unique(yy)), function(Y){ i <- yy==Y; if(sum(i)<8) return(NULL)
  g <- tryCatch(nwfit(p[i], mk[i]), error=function(e) list(beta=NA,alpha_m=NA,alpha_t=NA,beta_t=NA))
  data.table(year=Y, n=sum(i), mkt_ann=round(mean(mk[i])*12,4), beta=round(g$beta,3),
             raw_active_ann=round(mean(a[i])*12,4)) }))
print(BY, nrows=25)
cat(sprintf("\n  베타 median=%.3f | >1 인 해 %d/%d | 2026 베타=%.3f\n",
    median(BY$beta, na.rm=TRUE), sum(BY$beta>1, na.rm=TRUE), nrow(BY), BY[year==2026, beta]))
cat("\n  [상승장/하락장 비대칭 — 베타 노출이면 상승장에서만 초과]\n")
up <- mk>0
cat(sprintf("    상승월 n=%d: mean_active=%.4f | 하락월 n=%d: mean_active=%.4f\n",
    sum(up), mean(a[up]), sum(!up), mean(a[!up])))
cat(sprintf("    상관 cor(active, Market)=%.4f (양수 = 베타>1 노출 징후)\n", cor(a, mk)))
fwrite(res, file.path(OUTD,"m_beta_segments.csv")); fwrite(BY, file.path(OUTD,"m_beta_yearly.csv"))
cat("\nPROBE5_DONE\n")
sink()
