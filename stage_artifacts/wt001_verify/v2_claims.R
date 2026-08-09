# v2_claims.R — 주장 A(β-drag) / B(순위↔평균 역전) 독립 재현 + PIT 스트레스
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/wt001_verify")
W1  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[v2] ", fmt, "\n"), ...))

TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
RAW[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]

fwd <- readRDS(file.path(W1,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bch <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date), BM_Ret)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date), Ticker, adv)]

nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  f<-lm(x~1); tryCatch(as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f, lag=lag, prewhite=FALSE))[1,3]), error=function(e) NA_real_) }

score_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(score_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E, Date, -score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% ret$Date]
say("eligible %d행 / %d개월 / 월평균 %.1f", nrow(E), uniqueN(E$Date), E[, .N, by=Date][, mean(N)])
FILT <- c("D03_EWMA","Q01_EB")
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[, .(Date,Ticker)], by=c("Date","Ticker"))
FZ[, q_rank := frank(fz)/.N, by=.(Date,F_)]

# ═════════ 주장 B: 순위↔평균 부호 역전 ═════════
say("=== 주장 B 재현: rank-IC vs 5분위 평균/중앙/왜도 ===")
skewf <- function(x){ x<-x[is.finite(x)]; n<-length(x); if(n<8) return(NA_real_)
  m<-mean(x); s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); sum((x-m)^3)/(n*s^3) }
bat <- function(sc, nm){
  D <- merge(sc, ret, by=c("Date","Ticker"))
  ic <- D[, if(.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  qq <- D[, { if(.N>=20L && sd(score)>0){ q <- cut(frank(score), breaks=5, labels=FALSE)
      c(as.list(setNames(sapply(1:5, function(k) mean(Ret_1m[q==k], na.rm=TRUE)), paste0("m",1:5))),
        as.list(setNames(sapply(1:5, function(k) median(Ret_1m[q==k], na.rm=TRUE)), paste0("md",1:5))),
        as.list(setNames(sapply(1:5, function(k) skewf(Ret_1m[q==k])), paste0("sk",1:5))))
    } else NULL }, by=Date]
  qm  <- sapply(paste0("m",1:5),  function(k) mean(qq[[k]], na.rm=TRUE))
  qmd <- sapply(paste0("md",1:5), function(k) mean(qq[[k]], na.rm=TRUE))
  qsk <- sapply(paste0("sk",1:5), function(k) mean(qq[[k]], na.rm=TRUE))
  # Q5-Q1 평균차의 NW t (월별 계열)
  dq <- qq[[ "m5" ]] - qq[[ "m1" ]]
  list(name=nm, n=nrow(ic), rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), harvey_t=nw_t(ic$ic),
       mono=mean(diff(qm)>0), q_ann=100*12*qm, qmed_ann=100*12*qmd, qskew=qsk,
       q5m1_ann=100*12*mean(dq, na.rm=TRUE), q5m1_t=nw_t(dq))
}
specs <- list(M01_PATHQ=E[, .(Date,Ticker,score)],
              D03_EWMA=FZ[F_=="D03_EWMA", .(Date,Ticker,score=fz)],
              Q01_EB  =FZ[F_=="Q01_EB",   .(Date,Ticker,score=fz)])
B <- lapply(names(specs), function(n) bat(specs[[n]], n)); names(B) <- names(specs)
for (n in names(B)) { b <- B[[n]]
  say("  %-10s rank_IC %+.4f ICIR %+.3f Harvey-t %+.2f mono %.2f n=%d", n, b$rank_ic, b$icir, b$harvey_t, b$mono, b$n)
  say("     평균 연%%  Q1..Q5 = %s   (Q5-Q1 %+.2f%%, NW t %+.2f)", paste(sprintf("%+7.1f", b$q_ann), collapse=" "), b$q5m1_ann, b$q5m1_t)
  say("     중앙 연%%  Q1..Q5 = %s", paste(sprintf("%+7.1f", b$qmed_ann), collapse=" "))
  say("     월내왜도  Q1..Q5 = %s", paste(sprintf("%+7.2f", b$qskew), collapse=" "))
}

# 리드-래그 IC 프로파일 (PIT 방향성 진단)
say("=== 리드-래그 IC 프로파일 (score_t vs Ret_1m at t+k; k=-1 은 이미 실현된 과거월) ===")
dts <- sort(unique(E$Date)); di <- data.table(Date=dts, i=seq_along(dts))
for (n in names(specs)) {
  sc <- merge(specs[[n]], di, by="Date")
  for (k in c(-1L, 0L, 1L)) {
    r2 <- merge(ret, di, by="Date")[, .(i_target=i, Ticker, Ret_1m)]
    m <- merge(sc[, .(i_target=i+k, Ticker, score)], r2, by=c("i_target","Ticker"))
    ic <- m[, if(.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=i_target][is.finite(ic)]
    say("  %-10s k=%+d : IC %+.4f  NW t %+.2f  n=%d", n, k, mean(ic$ic), nw_t(ic$ic), nrow(ic))
  }
}

# ═════════ 주장 A: β-drag ═════════
say("=== 주장 A 재현: trailing-60m β 분위 ===")
RM <- merge(ret, bch, by="Date")
beta_panel <- function(lag_extra=0L){
  bl <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    hi <- i-1L-lag_extra; lo <- max(1L, i-60L-lag_extra)
    if (i <= 36L || hi < lo) next
    w <- RM[Date %in% dts[lo:hi]]
    bb <- w[, { ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
      if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok])) else .(beta=NA_real_) }, by=Ticker][is.finite(beta)]
    bb[, Date := dts[i]]; bl[[i]] <- bb[, .(Date,Ticker,beta)]
  }
  rbindlist(bl)
}
for (lg in c(0L, 1L)) {
  BETA <- beta_panel(lg)
  say("  [창 i-%d..i-%d] β 패널 %d행 / %d개월", 60L+lg, 1L+lg, nrow(BETA), uniqueN(BETA$Date))
  for (f in FILT) {
    D <- merge(FZ[F_==f, .(Date,Ticker,fz,q_rank)], BETA, by=c("Date","Ticker"))
    s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), b_bot=median(beta[q_rank<=0.2])), by=Date]
    s <- s[is.finite(b_top)&is.finite(b_med)]
    say("    %-9s top %.3f vs univ중앙 %.3f  차 %+.3f NW t %+.2f | bot 차 %+.3f t %+.2f  n=%d",
        f, mean(s$b_top), mean(s$b_med), mean(s$b_top-s$b_med), nw_t(s$b_top-s$b_med),
        mean(s$b_bot-s$b_med), nw_t(s$b_bot-s$b_med), nrow(s))
  }
}
saveRDS(list(B=B), file.path(OUT,"v2.rds"))
say("=== v2 완료 ===")
