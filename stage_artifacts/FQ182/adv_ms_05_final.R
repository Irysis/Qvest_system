## FQ-182 적대검증 · STEP 10: 확증 배터리
##  10a. 원 주장의 se(0.18/0.21) 가 왜 작은가 — 페어드 블록부트 vs dd 재생성 부트 대조
##  10b. 연도 잭나이프 (2026 단일 연도 지배 여부)
##  10c. 2026 제외 / 최대일 제외 후 재판정
##  10d. ★GARCH 표준화잔차 통계량의 귀무 분포 (변동성 혼합 제거 후에도 귀무 밖인가)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv10] ", fmt, "\n"), ...)); flush.console() }
D <- as.data.table(readRDS(file.path(OUT, "adv_ms_input.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type="lead")]; D <- D[!is.na(fwd1)]
n <- nrow(D)
say("=== 입력 실측 === %d행 · %s~%s · 관측단위 daily", n, as.character(min(D$Date)), as.character(max(D$Date)))
skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
rollmax_right <- function(x,k=252L){m<-length(x);nb<-ceiling(m/k);xp<-c(x,rep(-Inf,nb*k-m));M<-matrix(xp,nrow=k)
  A<-apply(M,2,cummax);B<-apply(M[k:1,,drop=FALSE],2,cummax)[k:1,,drop=FALSE];a<-as.vector(A);b<-as.vector(B)
  out<-numeric(m);ii<-k:m;out[ii]<-pmax(b[ii-k+1L],a[ii]);out[1:(k-1L)]<-cummax(x[1:(k-1L)]);out}
dd_of <- function(rr){ix<-cumprod(1+rr);ix/rollmax_right(ix,252L)-1}
res <- list(); add <- function(...) res[[length(res)+1L]] <<- data.table(...)

## ---------- 10a. se 의 출처 -----------------------------------------------------
say("")
say("=== 10a. 원 주장 se 의 출처: 'ON 라벨을 고정한 페어드 블록부트' vs 'dd252 재생성 부트' ===")
set.seed(20260809)
paired_bb <- function(x, on, B=500L, blk=60L){ m<-length(x); nb<-ceiling(m/blk); o<-numeric(0)
  for(b in seq_len(B)){ st<-sample.int(m-blk+1L,nb,TRUE)
    ii<-as.integer(unlist(lapply(st,function(k) k:(k+blk-1L))))[1:m]
    xb<-x[ii]; ob<-on[ii]; if(sum(ob)<30||sum(!ob)<30) next
    o<-c(o, skew1(xb[ob])-skew1(xb[!ob])) }; o }
regen_bb <- function(x, thr, B=500L, blk=60L){ m<-length(x); nb<-ceiling(m/blk); o<-numeric(0)
  for(b in seq_len(B)){ st<-sample.int(m-blk+1L,nb,TRUE)
    ii<-as.integer(unlist(lapply(st,function(k) k:(k+blk-1L))))[1:m]
    xb<-x[ii]; dd<-dd_of(xb); fw<-c(xb[-1],NA); kp<-252:(m-1L); dd<-dd[kp]; fw<-fw[kp]
    ob<-dd<=thr; if(sum(ob)<30||sum(!ob)<30) next
    o<-c(o, skew1(fw[ob])-skew1(fw[!ob])) }; o }
for (thr in c(-0.20,-0.30)) {
  on <- D$dd252 <= thr; obs <- skew1(D$fwd1[on]) - skew1(D$fwd1[!on])
  pb <- paired_bb(D$fwd1, on); rb <- regen_bb(D$BM_Ret, thr)
  say("  thr %.0f%%: 관측 %+0.4f", thr*100, obs)
  say("    (i) 페어드(ON 라벨 동반 재표집, = p1 방식)  se %.4f · |obs|/se %.2f",
      sd(pb), abs(obs)/sd(pb))
  say("    (ii) dd252 재생성(선택 메커니즘까지 재표집)  se %.4f · mean %+0.4f · |obs−mean|/se %.2f",
      sd(rb), mean(rb), abs(obs-mean(rb))/sd(rb))
  say("    ★se 과소평가 배수 = %.2fx  — p1 의 se 는 '낙폭 선택 자체의 표본변동'을 조건부로 고정해 제거했다",
      sd(rb)/sd(pb))
  add(step="10a", tag=sprintf("thr%.0f", thr*100), obs=obs, se_paired=sd(pb), se_regen=sd(rb),
      mean_regen=mean(rb), ratio_paired=abs(obs)/sd(pb), ratio_regen=abs(obs-mean(rb))/sd(rb))
}

## ---------- 10b. 연도 잭나이프 --------------------------------------------------
say("")
say("=== 10b. 연도 잭나이프 (한 해가 결론을 만드는가) ===")
D[, yr := as.integer(format(Date, "%Y"))]
for (thr in c(-0.20,-0.30)) {
  on <- D$dd252 <= thr; base <- skew1(D$fwd1[on]) - skew1(D$fwd1[!on])
  jk <- data.table(yr=integer(), n_on_drop=integer(), diff=numeric())
  for (y in sort(unique(D$yr))) {
    k <- D$yr != y; on2 <- on & k
    if (sum(on2) < 100) next
    jk <- rbind(jk, data.table(yr=y, n_on_drop=sum(on & !k),
                               diff=skew1(D$fwd1[on2]) - skew1(D$fwd1[!on & k])))
  }
  say("  thr %.0f%% (base %+0.4f): 잭나이프 diff 범위 [%+0.4f, %+0.4f] · 부호반전 %d/%d",
      thr*100, base, min(jk$diff), max(jk$diff), sum(sign(jk$diff)!=sign(base)), nrow(jk))
  print(jk[order(diff)][1:4])
  add(step="10b", tag=sprintf("thr%.0f", thr*100), obs=base, se_paired=NA, se_regen=NA,
      mean_regen=min(jk$diff), ratio_paired=NA, ratio_regen=NA)
}

## ---------- 10c. 2026 제외 / 최대일 제외 ----------------------------------------
say("")
say("=== 10c. 지배 관측 제거 후 재판정 ===")
say("  참고: 2026년 n=%d (전체의 %.1f%%) · sd %.4f (전체 %.4f 의 %.2f배) · |ret|>8%% 일수 %d (전체 %d 중)",
    D[yr==2026,.N], 100*D[yr==2026,.N]/n, D[yr==2026,sd(BM_Ret)], sd(D$BM_Ret),
    D[yr==2026,sd(BM_Ret)]/sd(D$BM_Ret), D[yr==2026 & abs(BM_Ret)>0.08,.N], D[abs(BM_Ret)>0.08,.N])
for (thr in c(-0.20,-0.30)) {
  on <- D$dd252 <= thr; base <- skew1(D$fwd1[on]) - skew1(D$fwd1[!on])
  k1 <- D$yr != 2026
  d1 <- skew1(D$fwd1[on & k1]) - skew1(D$fwd1[!on & k1])
  imax <- which.max(ifelse(on, D$fwd1, -Inf)); k2 <- rep(TRUE,n); k2[imax] <- FALSE
  d2 <- skew1(D$fwd1[on & k2]) - skew1(D$fwd1[!on & k2])
  k3 <- k1 & k2
  say("  thr %.0f%%: 전체 %+0.4f | 2026 제외 %+0.4f (ON %d일) | 최대1일 제외 %+0.4f | 둘 다 %+0.4f",
      thr*100, base, d1, sum(on & k1), d2, skew1(D$fwd1[on&k3])-skew1(D$fwd1[!on&k3]))
  add(step="10c", tag=sprintf("thr%.0f", thr*100), obs=base, se_paired=d1, se_regen=d2,
      mean_regen=NA, ratio_paired=NA, ratio_regen=NA)
}

## ---------- 10d. 표준화잔차 통계량의 귀무 분포 -----------------------------------
say("")
say("=== 10d. ★변동성 표준화 후 통계량도 귀무 안인가 (GARCH 잔차 기준) ===")
G <- readRDS(file.path(OUT,"adv_ms_garchfit.rds")); cf <- G$coef; z_emp <- G$z[is.finite(G$z)]
sg_obs <- G$sigma; sgf <- shift(sg_obs, 1L, type="lead")[1:n]
z_obs <- (D$fwd1 - cf[["mu"]]) / sgf
obs_r <- sapply(c(-0.20,-0.30), function(thr){ on <- D$dd252<=thr & is.finite(z_obs)
  skew1(z_obs[on]) - skew1(z_obs[D$dd252>thr & is.finite(z_obs)]) })
say("  관측(표준화잔차): thr -20%% %+0.4f · thr -30%% %+0.4f", obs_r[1], obs_r[2])
sim_gs <- function(zd, burn=500L){ N<-n+burn; s2<-numeric(N); e<-numeric(N); s2[1]<-var(D$BM_Ret); e[1]<-sqrt(s2[1])*zd[1]
  for(i in 2:N){ s2[i]<-cf[["omega"]]+cf[["alpha1"]]*e[i-1]^2+cf[["beta1"]]*s2[i-1]; e[i]<-sqrt(s2[i])*zd[i] }
  list(r=(cf[["mu"]]+e)[(burn+1):N], sg=sqrt(s2)[(burn+1):N]) }
set.seed(20260809); B <- 500L
for (nm in c("NULL_B_signflip","NULL_D_iidshape")) {
  M <- matrix(NA_real_, B, 2)
  for (b in seq_len(B)) {
    zd <- sample(z_emp, n+500L, TRUE); if (nm=="NULL_B_signflip") zd <- zd*sample(c(-1,1), n+500L, TRUE)
    S <- sim_gs(zd); rr <- S$r; sg <- S$sg
    dd <- dd_of(rr); zz <- (c(rr[-1],NA) - cf[["mu"]]) / c(sg[-1],NA)
    kp <- 252:(n-1L); dd <- dd[kp]; zz <- zz[kp]
    for (j in 1:2) { thr <- c(-0.20,-0.30)[j]; on <- dd<=thr & is.finite(zz); off <- dd>thr & is.finite(zz)
      if (sum(on)>=100 && sum(off)>=100) M[b,j] <- skew1(zz[on]) - skew1(zz[off]) }
  }
  for (j in 1:2) { v <- M[,j]; v <- v[is.finite(v)]
    pr <- mean(v >= obs_r[j])
    say("  %s thr %.0f%%: 관측 %+0.4f | 귀무 mean %+0.4f sd %0.4f q95 %+0.4f | P(귀무>=관측)=%.4f %s",
        nm, c(-20,-30)[j], obs_r[j], mean(v), sd(v), quantile(v,.95,names=FALSE), pr,
        if (pr>0.05) "★귀무 안 → 반증" else "귀무 밖")
    add(step="10d", tag=sprintf("%s_thr%.0f", nm, c(-20,-30)[j]), obs=obs_r[j], se_paired=sd(v),
        se_regen=quantile(v,.95,names=FALSE), mean_regen=mean(v), ratio_paired=pr, ratio_regen=NA) }
}
R <- rbindlist(res, fill=TRUE); fwrite(R, file.path(OUT,"adv_mechanical_selection.csv"))
say(""); say("=== STEP 10 완료 → adv_mechanical_selection.csv (%d행) ===", nrow(R))
