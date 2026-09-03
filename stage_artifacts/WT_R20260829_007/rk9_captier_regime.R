# RK9 — cap-tier 실현 분해 · regime_correlation.parquet · 역방향(adverse) 스트레스
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT<-getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); o4<-readRDS(file.path(OUT,"rk4_objects.rds"))
o6<-readRDS(file.path(OUT,"rk6_objects.rds")); o7<-readRDS(file.path(OUT,"rk7_objects.rds")); o8<-readRDS(file.path(OUT,"rk8_objects.rds"))
X<-o3$X; STY<-o3$STY; Om<-o4$Om_lw; Bw<-o8$Bw; Bd<-o8$Bd
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
PR <- fread(file.path(OUT,"period_returns_production.csv")); PR[,signal_date:=as.Date(signal_date)]
pn <- readRDS(file.path(OUT,"panel.rds")); RET <- as.data.table(pn$fwd$returns_dt)

## ── cap-tier 실현 분해 (dual basis) ──
Xt <- X[, .(Date,Ticker,Size,sec)]
Xt[, tier := cut(frank(Size)/.N, c(0,1/3,2/3,1), labels=c("SMALL","MID","MEGA")), by=Date]
HD <- merge(A[in_top25==TRUE,.(Date,Ticker)], Xt, by=c("Date","Ticker"))
HD <- merge(HD, RET[,.(Date,Ticker,r=Ret_1m)], by=c("Date","Ticker"))
HD <- merge(HD, PR[,.(Date=signal_date, bm=benchmark_ret, holding_ym)], by="Date")
# EW-uni basis (당월 유니버스 EW) + cap-w basis (벤치 = BM_Ret)
UN <- merge(X[,.(Date,Ticker)], RET[,.(Date,Ticker,r=Ret_1m)], by=c("Date","Ticker"))
UN <- merge(UN, Xt[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
ewb <- UN[is.finite(r), .(ew_uni=mean(r), cap_uni=sum(r*Size,na.rm=TRUE)/sum(Size,na.rm=TRUE)), by=Date]
HD <- merge(HD, ewb, by="Date")
HD[, w := 1/25]
HD[, sub := fifelse(Date<as.Date("2015-01-01"),"P1_2005_2014", fifelse(Date<as.Date("2020-01-01"),"P2_2015_2019","P3_2020_2026"))]
tier_full <- HD[,.(n_obs=.N, w_share=sum(w)/uniqueN(Date),
                   contrib_vs_capw=sum(w*(r-bm))/uniqueN(Date)*12,
                   contrib_vs_ewuni=sum(w*(r-ew_uni))/uniqueN(Date)*12,
                   vol_ann=sd(r)*sqrt(12)), by=tier][order(-w_share)]
print(tier_full)
tier_sub <- HD[,.(w_share=sum(w)/uniqueN(Date), contrib_vs_capw=sum(w*(r-bm))/uniqueN(Date)*12,
                  contrib_vs_ewuni=sum(w*(r-ew_uni))/uniqueN(Date)*12), by=.(tier,sub)][order(sub,-w_share)]
print(tier_sub)
# 위험 기여(실현): tier 소포트 수익 시계열의 book 활성수익 대비 공분산 비중
tser <- dcast(HD[,.(x=sum(w*(r-bm))),by=.(Date,tier)], Date~tier, value.var="x", fill=0)
act <- PR[,.(Date=signal_date, a=ret_gross-benchmark_ret)]
tser <- merge(tser, act, by="Date")
tiers <- setdiff(names(tser), c("Date","a"))
rc_real <- sapply(tiers, function(k) stats::cov(tser[[k]], tser$a)/stats::var(tser$a))
print(round(rc_real,4))

## ── regime_correlation ──
MS <- o7$MS; sp <- o7$sp; cr <- o7$cr
rows <- list()
for(i in seq_len(nrow(sp))) rows[[length(rows)+1]] <- data.table(
  regime=sp$sub[i], regime_class="subperiod", metric_type="book_pairwise",
  factor=NA_character_, value=sp$avg_pairwise_corr[i],
  book_vol_ann=sp$book_vol_ann[i], name_vol_ann=sp$avg_name_vol_ann[i],
  beta_daily=sp$beta_daily[i], n_months=sp$months[i], coverage=1)
for(i in seq_len(nrow(cr))) rows[[length(rows)+1]] <- data.table(
  regime=cr$regime[i], regime_class="crisis", metric_type="book_pairwise",
  factor=NA_character_, value=cr$avg_pairwise_corr[i],
  book_vol_ann=cr$book_vol_ann[i], name_vol_ann=NA_real_,
  beta_daily=cr$beta[i], n_months=round(cr$n_days[i]/21), coverage=cr$coverage[i])
FVv <- o7$FV; cm <- o7$cormat
for(s in colnames(FVv)) for(f in rownames(FVv)) rows[[length(rows)+1]] <- data.table(
  regime=s, regime_class="subperiod", metric_type="factor_vol_and_mktcorr", factor=f,
  value=cm[[s]]["MKT",f], book_vol_ann=FVv[f,s], name_vol_ann=NA_real_,
  beta_daily=NA_real_, n_months=sp$months[match(s,sp$sub)], coverage=1)
RC <- rbindlist(rows)
write_parquet(RC, file.path(OUT,"regime_correlation.parquet"))
cat("[RK9] regime_correlation rows",nrow(RC),"\n")

## ── 구간별 Σ 이질성 요약 (Ω_sub 로 as_of book 예측) ──
B <- o4$B; wf <- o6$wf; Dv <- o6$Dv
het <- rbindlist(lapply(names(o7$sub_om), function(s){
  Oms <- o7$sub_om[[s]]; cn <- colnames(B)
  O2 <- matrix(0,length(cn),length(cn),dimnames=list(cn,cn)); cc<-intersect(cn,colnames(Oms)); O2[cc,cc]<-Oms[cc,cc]
  S <- B%*%O2%*%t(B); diag(S) <- diag(S)+Dv
  v <- as.numeric(t(wf)%*%S%*%wf)
  bwv <- as.numeric(t(B)%*%wf); names(bwv)<-cn
  fv <- as.numeric(t(bwv)%*%O2%*%bwv)
  d <- wf-o6$w_cap; bdv <- as.numeric(t(B)%*%d); names(bdv)<-cn
  av <- as.numeric(t(bdv)%*%O2%*%bdv) + sum(d^2*Dv)
  data.table(subperiod=s, book_vol_pred_ann=sqrt(v*12), factor_share=fv/v, specific_share=1-fv/v,
             te_vs_capw_pred_ann=sqrt(av*12),
             beta_pred_vs_capw=as.numeric(t(wf)%*%S%*%o6$w_cap)/as.numeric(t(o6$w_cap)%*%S%*%o6$w_cap))}))
print(het)

## ── adverse(불리 방향) 2σ 요인 스트레스 ──
sd_f <- sqrt(diag(Om))
adv <- rbindlist(lapply(c("MKT",STY), function(k){
  eff <- sapply(c(-2,2), function(ns){ f <- as.numeric(Om[,k]/Om[k,k]*(ns*sd_f[k]))
    c(total=sum(Bw*f), active=sum(Bd*f)) })
  data.table(factor=k, shock_sigma_worst_total=c(-2,2)[which.min(eff["total",])],
    total_pnl=min(eff["total",]),
    shock_sigma_worst_active=c(-2,2)[which.min(eff["active",])], active_pnl=min(eff["active",]))}))
print(adv)
saveRDS(list(tier_full=tier_full,tier_sub=tier_sub,rc_real=rc_real,RC=RC,het=het,adv=adv,HD=HD),
        file.path(OUT,"rk9_objects.rds"))
cat("[RK9] done\n")
