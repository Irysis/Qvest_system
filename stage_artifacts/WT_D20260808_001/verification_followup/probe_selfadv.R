# probe_selfadv.R — 자기 적대검증에서 나온 두 의문을 측정한다(주장 전에 잰다).
#  Q1. 재발행 패널이 판정 유니버스(eligible_set)의 **부분집합**인가, 아니면 다른 집합인가.
#  Q2. 판정 유니버스 자체도 20일-ADV 자로 보면 축을 깨는가. 깬다면 **실제 선별된 top-25**
#      중 몇 종이 Production Constraints 유동성 미달인가 — 이게 결과에 닿는 수다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(f,...) cat(sprintf(paste0("[selfadv] ",f,"\n"),...))

NEW <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[,Date:=as.Date(Date)]
SUP <- as.data.table(read_parquet(file.path(OUT,"alpha_scores_superseded_20260809.parquet")))[,Date:=as.Date(Date)]
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select=c("Date","Ticker","Close","Vol","K200","KQ150")))[,Date:=as.Date(Date)]
setorder(R,Ticker,Date); R[,adv20:=frollmean(Vol*Close,20L,align="right"),by=Ticker]
R[,ym:=format(Date,"%Y-%m")]
ADV20 <- R[,.(adv20=last(adv20)),by=.(Ticker,ym)]
MEND <- sort(R[,.(Date=max(Date)),by=ym]$Date)
UNIV <- R[Date %in% MEND & (K200==TRUE|KQ150==TRUE),.(Date,Ticker)]; rm(R); gc(verbose=FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
ADVC <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv_c=adv)]
RET <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]

# eligible_set 재구성 (측정 스크립트 정의 그대로: M01 = TUNED score)
SC <- TUNED[Factor_Name=="M01_PATHQ" & !is.na(score), .(Date,Ticker,score)]
E <- merge(merge(SC,UNIV,by=c("Date","Ticker")), ADVC, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv_c)|adv_c>=2e8][Date %in% RET$Date]
say("Q1: eligible_set 재구성 %d행 (원 보고 82,566 대조: %s)", nrow(E),
    if (nrow(E)==82566) "일치" else "★불일치 — 정의 재확인 필요")
key_new <- NEW[,paste0(Date,"|",Ticker)]; key_e <- E[,paste0(Date,"|",Ticker)]
say("Q1: 재발행 %d행 · eligible_set 에 없는 행 %d (부분집합이면 0)",
    nrow(NEW), sum(!key_new %in% key_e))
say("Q1: eligible_set 중 재발행에서 빠진 행 %d (= 20일-ADV 자 미달분)", sum(!key_e %in% key_new))

# Q2: eligible_set 을 20일-ADV 자로 재검
E[,ym:=format(Date,"%Y-%m")]
EC <- merge(E, ADV20, by=c("Ticker","ym"), all.x=TRUE)
say("Q2: 판정 유니버스(eligible_set) 중 20일-ADV < 2e8 : %d행 (%.3f%%) · 결측 %d",
    sum(EC$adv20<2e8,na.rm=TRUE), 100*mean(EC$adv20<2e8,na.rm=TRUE), sum(is.na(EC$adv20)))

# ★결과에 닿는 수: 실제 선별된 top-25 중 미달 종목
SUP[,ym:=format(Date,"%Y-%m")]
for (col in c("score","score_q01filtered")) {
  T25 <- SUP[is.finite(get(col))][order(Date,-get(col))][, .SD[seq_len(min(25L,.N))], by=Date][,.(Date,ym,Ticker)]
  T25 <- merge(T25, ADV20, by=c("Ticker","ym"), all.x=TRUE)
  T25 <- merge(T25, ADVC, by=c("Date","Ticker"), all.x=TRUE)
  nfail <- sum(T25$adv20 < 2e8, na.rm=TRUE)
  say("Q2: [%s] 선별 top-25 총 %d종-월 중 20일-ADV 미달 **%d종-월 (%.3f%%)** · 계약자 미달 %d · 결측 %d",
      col, nrow(T25), nfail, 100*nfail/nrow(T25), sum(T25$adv_c<2e8,na.rm=TRUE), sum(is.na(T25$adv20)))
  if (nfail>0) {
    bym <- T25[adv20<2e8, .N, by=Date][order(-N)]
    say("     미달 발생 월 %d개 · 최다 월 %s (%d종) · 미달 종목 adv20 중앙 %.3e",
        nrow(bym), as.character(bym$Date[1]), bym$N[1], median(T25[adv20<2e8]$adv20, na.rm=TRUE))
  }
}
