## FQ-182 적대검증 · STEP 11: 표준화잔차 통계량의 **공정한** 귀무 검정
## 10d 결함: 관측은 '적합 sigma'(추정오차 포함), 귀무는 '참 sigma'(추정오차 없음) — 비대칭 비교였다.
## 수리: 양쪽 모두 **동일 EWMA(0.94) 추정기**로 sigma 를 만든다(적합 없음 → 완전 대칭 비교).
## 부가: 표준화잔차 통계량의 극단치 지배·2026 지배·로버스트 판본 확인.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv11] ", fmt, "\n"), ...)); flush.console() }
D <- as.data.table(readRDS(file.path(OUT,"adv_ms_input.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret,1L,type="lead")]; D <- D[!is.na(fwd1)]; n <- nrow(D)
D[, yr := as.integer(format(Date,"%Y"))]
say("=== 입력 실측 === %d행 · %s~%s · daily · BM_Ret sd %.5f", n,
    as.character(min(D$Date)), as.character(max(D$Date)), sd(D$BM_Ret))
skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
bowley<- function(v,p=0.10){q<-quantile(v,c(p,.5,1-p),names=FALSE,na.rm=TRUE);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}
rollmax_right <- function(x,k=252L){m<-length(x);nb<-ceiling(m/k);xp<-c(x,rep(-Inf,nb*k-m));M<-matrix(xp,nrow=k)
  A<-apply(M,2,cummax);B<-apply(M[k:1,,drop=FALSE],2,cummax)[k:1,,drop=FALSE];a<-as.vector(A);b<-as.vector(B)
  out<-numeric(m);ii<-k:m;out[ii]<-pmax(b[ii-k+1L],a[ii]);out[1:(k-1L)]<-cummax(x[1:(k-1L)]);out}
dd_of <- function(rr){ix<-cumprod(1+rr);ix/rollmax_right(ix,252L)-1}
ewma_z <- function(rr, lam=0.94){                       ## 양쪽에 동일 적용되는 추정기
  m <- length(rr); mu <- mean(rr); v <- numeric(m); v[1] <- var(rr)
  for(i in 2:m) v[i] <- lam*v[i-1] + (1-lam)*(rr[i-1]-mu)^2
  (rr - mu)/sqrt(v)                                     ## z[i] = i 일 표준화잔차 (i-1 까지 정보)
}
stat_resid <- function(rr, thr){ dd <- dd_of(rr); z <- ewma_z(rr)
  zf <- c(z[-1], NA_real_); kp <- 252:(length(rr)-1L)
  dd <- dd[kp]; zf <- zf[kp]
  on <- dd<=thr & is.finite(zf); off <- dd>thr & is.finite(zf)
  if(sum(on)<100 || sum(off)<100) return(c(NA_real_, NA_real_, NA_integer_))
  c(skew1(zf[on])-skew1(zf[off]), bowley(zf[on],.10)-bowley(zf[off],.10), sum(on)) }

## ---- 관측 ----------------------------------------------------------------------
say("")
say("=== 11a. 관측 (EWMA-0.94 표준화잔차, 귀무와 동일 추정기) ===")
obs <- sapply(c(-0.20,-0.30), function(t) stat_resid(D$BM_Ret, t))
for(j in 1:2) say("  thr %.0f%%: skew diff %+0.4f · Bowley diff %+0.4f · ON %d일",
                  c(-20,-30)[j], obs[1,j], obs[2,j], obs[3,j])

## ---- 관측의 취약성: 극단치·2026 지배 -------------------------------------------
say("")
say("=== 11b. 표준화잔차 통계량의 취약성 ===")
z_full <- ewma_z(D$BM_Ret); zf <- c(z_full[-1], NA_real_)
for (thr in c(-0.20,-0.30)) {
  on <- D$dd252<=thr & is.finite(zf); off <- D$dd252>thr & is.finite(zf)
  base <- skew1(zf[on]) - skew1(zf[off]); v <- zf[on]
  contrib <- (v-mean(v))^3/(length(v)*sd(v)^3); o <- order(contrib, decreasing=TRUE)
  say("  thr %.0f%% base %+0.4f · 상위1 기여 %+0.4f (왜도의 %.0f%%) · 해당일 %s (z=%+0.2f)",
      thr*100, base, contrib[o[1]], 100*contrib[o[1]]/skew1(v),
      as.character(D$Date[on][o[1]]), v[o[1]])
  for(k in c(1,3,5)) say("    상위 %d개 제거 후 diff %+0.4f", k, skew1(v[-o[1:k]])-skew1(zf[off]))
  k26 <- D$yr != 2026
  say("    2026 제외 diff %+0.4f (ON %d일)", skew1(zf[on & k26])-skew1(zf[off & k26]), sum(on & k26))
  say("    Bowley(p=.10) diff %+0.4f · Bowley(p=.25) diff %+0.4f",
      bowley(zf[on],.10)-bowley(zf[off],.10), bowley(zf[on],.25)-bowley(zf[off],.25))
}

## ---- 귀무 (동일 EWMA 추정기) ---------------------------------------------------
say("")
say("=== 11c. 귀무 분포 (동일 EWMA 추정기 — 공정 비교) ===")
G <- readRDS(file.path(OUT,"adv_ms_garchfit.rds")); cf <- G$coef; z_emp <- G$z[is.finite(G$z)]
sim_g <- function(zd, burn=500L){ N<-n+burn; s2<-numeric(N); e<-numeric(N); s2[1]<-var(D$BM_Ret); e[1]<-sqrt(s2[1])*zd[1]
  for(i in 2:N){s2[i]<-cf[["omega"]]+cf[["alpha1"]]*e[i-1]^2+cf[["beta1"]]*s2[i-1]; e[i]<-sqrt(s2[i])*zd[i]}
  (cf[["mu"]]+e)[(burn+1):N] }
blockboot <- function(x, blk=60L){ m<-length(x); nb<-ceiling(m/blk); st<-sample.int(m-blk+1L,nb,TRUE)
  as.numeric(unlist(lapply(st, function(k) x[k:(k+blk-1L)])))[1:m] }
set.seed(20260809); B <- 500L
rows <- list()
for (nm in c("NULL_B_signflip","NULL_D_iidshape","NULL_E_blockboot")) {
  M <- array(NA_real_, c(B,2,2))
  for (b in seq_len(B)) {
    rr <- switch(nm,
      NULL_B_signflip = sim_g(sample(z_emp,n+500L,TRUE)*sample(c(-1,1),n+500L,TRUE)),
      NULL_D_iidshape = sim_g(sample(z_emp,n+500L,TRUE)),
      NULL_E_blockboot= blockboot(D$BM_Ret,60L))
    for(j in 1:2){ s <- stat_resid(rr, c(-0.20,-0.30)[j]); M[b,j,1] <- s[1]; M[b,j,2] <- s[2] }
  }
  for (j in 1:2) for (m_i in 1:2) {
    v <- M[,j,m_i]; v <- v[is.finite(v)]; ob <- obs[m_i,j]
    pr <- mean(v >= ob)
    say("  %-16s thr %.0f%% %-6s: 관측 %+0.4f | 귀무 mean %+0.4f sd %.4f q95 %+0.4f | P(귀무>=관측)=%.4f %s",
        nm, c(-20,-30)[j], c("skew","bowley")[m_i], ob, mean(v), sd(v),
        quantile(v,.95,names=FALSE), pr, if(pr>0.05) "★귀무 안 → 반증" else "귀무 밖")
    rows[[length(rows)+1L]] <- data.table(null_model=nm, thr=c(-20,-30)[j], measure=c("skew","bowley")[m_i],
      obs=ob, null_mean=mean(v), null_sd=sd(v), q95=quantile(v,.95,names=FALSE),
      p_one_sided=pr, inside_null=pr>0.05, n_sim=length(v))
  }
}
NR <- rbindlist(rows); fwrite(NR, file.path(OUT,"adv_mechanical_selection_resid_null.csv"))
say("")
say("=== ★11 요약 ===")
print(NR[, .(null_model, thr, measure, obs=round(obs,4), null_sd=round(null_sd,4),
             q95=round(q95,4), p_one=round(p_one_sided,4), inside_null)])
say("=== STEP 11 완료 ===")
