# probe_d03_quintile.R — "D03 5분위 평균이 Q1→Q5 단조 감소" 주장을 직접 잰다.
#   ★전달받은 계열([13.07,15.33,14.63,11.07,7.96])을 전사하지 않는다 — 내가 재서 쓴다.
#   두 유니버스에서 각각 잰다: 재발행(청정) 패널 · 구 발행(superseded) 패널 = 원 주장이 나온 자리.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
say <- function(f,...) cat(sprintf(paste0("[q5] ",f,"\n"),...))
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
nw_ci <- function(x,lag=3L){x<-x[is.finite(x)];f<-lm(x~1)
  se<-sqrt(sandwich::NeweyWest(f,lag=lag,prewhite=FALSE)[1,1]); mean(x)+c(-1,1)*qt(.975,length(x)-1L)*se}
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
RET <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]

quint <- function(panel, col, label) {
  P <- as.data.table(read_parquet(panel))[,Date:=as.Date(Date)]
  D <- merge(P[is.finite(get(col)), .(Date,Ticker,score=get(col))], RET, by=c("Date","Ticker"))
  qm <- D[, { if (.N>=20L && sd(score)>0) { q <- cut(frank(score), breaks=5, labels=FALSE)
      as.list(setNames(sapply(1:5,function(k) mean(Ret_1m[q==k],na.rm=TRUE)), paste0("m",k=1:5)))
    } else as.list(setNames(rep(NA_real_,5), paste0("m",1:5))) }, by=Date]
  qmean <- sapply(paste0("m",1:5), function(k) 100*12*mean(qm[[k]], na.rm=TRUE))
  sp <- qm$m5 - qm$m1
  spr <- 100*12*mean(sp, na.rm=TRUE); tt <- nw_t(sp); ci <- 100*12*nw_ci(sp[is.finite(sp)])
  mono_up <- mean(diff(qmean) > 0)
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  say("--- %s (%s) · %d개월 ---", label, col, nrow(qm))
  say("  분위 평균 연수익 Q1..Q5 = [%s]", paste(sprintf("%.2f", qmean), collapse=", "))
  say("  형태: 최대 분위 = Q%d · Q1→Q2 %+.2f%%p · monotonicity(상승비율) %.2f",
      which.max(qmean), qmean[2]-qmean[1], mono_up)
  say("  Q5−Q1 스프레드 연 %+.2f%%  NW t %+.2f  CI[%+.2f, %+.2f] → %s",
      spr, tt, ci[1], ci[2], if (abs(tt)>=2) "유의" else "**비유의**")
  say("  rank-IC 평균 %+.6f · Harvey-t %+.3f (순위 통계는 양(+))", mean(ic$ic), nw_t(ic$ic))
  list(quintile_ann_pct=round(unname(qmean),3), argmax=which.max(qmean),
       q1_to_q2_pp=round(qmean[2]-qmean[1],3), monotonicity=mono_up,
       spread_q5_q1_ann_pct=round(spr,3), spread_t_nw=round(tt,3),
       spread_ci=round(ci,3), n_month=nrow(qm),
       rank_ic=mean(ic$ic), rank_ic_harvey_t=nw_t(ic$ic))
}
R <- list()
R$repaired  <- quint(file.path(OUT,"alpha_scores.parquet"), "D03_EWMA", "재발행(청정) 패널")
R$superseded<- quint(file.path(OUT,"alpha_scores_superseded_20260809.parquet"), "D03_EWMA", "구 발행 패널(원 주장 자리)")
say("=== 주장 대조 ===")
say("  주장: 'Q1 +13.1%% → Q5 +8.0%% 단조 감소'")
say("  실측(구 패널): Q1 %.2f%% Q5 %.2f%% · 최대분위 Q%d · 단조감소인가 %s",
    R$superseded$quintile_ann_pct[1], R$superseded$quintile_ann_pct[5], R$superseded$argmax,
    all(diff(R$superseded$quintile_ann_pct) < 0))
saveRDS(R, file.path(FU,"fu_d03_quintile.rds"))
