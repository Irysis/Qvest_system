# c3_survivorship.R — C6: forward-return inner-join 이 종료월 손실을 지운다
#   build_monthly_forward_returns 는 merge(c0, c1, by="Ticker") 내부조인 →
#   d1 월말에 부재한 종목(상폐/이관)은 '결측 수익' 이 아니라 '아예 없는 행' 이 된다.
#   렌즈2 가 잰 '결측률 0.0002' 는 이 소거 *이후* 의 잔여물이라 C6 를 시험하지 못한다.
# READ-ONLY.
suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
say <- function(f, ...) cat(sprintf(paste0("[C3] ", f, "\n"), ...))

TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
say("INPUT RAWDATA rows=%d dates=%d 티커=%d", nrow(RAW), uniqueN(RAW$Date), uniqueN(RAW$Ticker))
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
setorder(RAWME, Ticker, Date)

# 각 티커의 월말 관측 시퀀스에서 '다음 월말이 없는' 행 = 종료월
allm <- sort(unique(RAWME$Date))
nxt <- data.table(Date=allm, Date_next=c(allm[-1], NA))
RAWME <- merge(RAWME, nxt, by="Date")
present <- RAWME[, .(Date, Ticker)]; setkey(present, Date, Ticker)
RAWME[, has_next := !is.na(Date_next) &
        paste(Date_next, Ticker) %in% paste(present$Date, present$Ticker)]
panel_end <- max(allm)
TERM <- RAWME[(K200==TRUE|KQ150==TRUE) & !has_next & Date < panel_end, .(Date, Ticker)]
say("종료월(유니버스 소속인데 다음 월말 관측 없음) = %d건 · 고유 티커 %d",
    nrow(TERM), uniqueN(TERM$Ticker))
say("→ 이 %d건은 forward return 이 '결측' 이 아니라 패널에서 소거된다(내부조인)", nrow(TERM))

# ELIG 재현 (유동성 + M01 가용) 후 종료월이 몇 건 걸리는가
W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
           Date+Ticker ~ Factor_Name, value.var="score")
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date, Ticker)]
W <- merge(W, UNIV, by=c("Date","Ticker"))
E <- W[is.finite(M01_PATHQ)]
E[, rk_m01 := frank(-M01_PATHQ, ties.method="first"), by=Date]
E[, q01r := { v<-Q01_EB; r<-rep(NA_real_,.N); ok<-is.finite(v); if(any(ok)) r[ok]<-frank(v[ok])/sum(ok); r }, by=Date]
E[, d03r := { v<-D03_EWMA; r<-rep(NA_real_,.N); ok<-is.finite(v); if(any(ok)) r[ok]<-frank(v[ok])/sum(ok); r }, by=Date]
setkey(TERM, Date, Ticker)
E[, is_term := FALSE]
E[TERM, is_term := TRUE, on=.(Date, Ticker)]
say("ELIG(유동성 전) rows=%d · 그중 종료월 %d건 (%.4f%%) · 월평균 %.2f건",
    nrow(E), sum(E$is_term), 100*mean(E$is_term), sum(E$is_term)/uniqueN(E$Date))

say("── 종료월의 팩터 분위 편중 (기전 F1 이 재는 좌측 꼬리와 겹치는가) ──")
say("  D03 하위20%% 내 종료월 비율 %.5f · 그외 %.5f · 배수 %.2f",
    E[is.finite(d03r) & d03r<=0.2, mean(is_term)], E[is.finite(d03r) & d03r>0.2, mean(is_term)],
    E[is.finite(d03r) & d03r<=0.2, mean(is_term)] / max(E[is.finite(d03r) & d03r>0.2, mean(is_term)], 1e-12))
say("  Q01 하위20%% 내 종료월 비율 %.5f · 그외 %.5f · 배수 %.2f",
    E[is.finite(q01r) & q01r<=0.2, mean(is_term)], E[is.finite(q01r) & q01r>0.2, mean(is_term)],
    E[is.finite(q01r) & q01r<=0.2, mean(is_term)] / max(E[is.finite(q01r) & q01r>0.2, mean(is_term)], 1e-12))
say("  M01 top-25 내 종료월 %d건 · top-50 %d건 · 밴드20~40 %d건",
    E[rk_m01<=25, sum(is_term)], E[rk_m01<=50, sum(is_term)], E[rk_m01>=20 & rk_m01<=40, sum(is_term)])

# 종료 직전 12개월 수익 (소거된 손실의 크기 대용)
say("── 소거된 종료월의 직전 흐름 (손실 규모 대용) ──")
PX <- RAWME[, .(Date, Ticker, Close)]
setorder(PX, Ticker, Date)
PX[, ret_prev := Close/shift(Close)-1, by=Ticker]
TT <- merge(TERM, PX, by=c("Date","Ticker"))
say("  종료월 당월 수익 중앙 %.4f · 평균 %.4f · n=%d",
    median(TT$ret_prev, na.rm=TRUE), mean(TT$ret_prev, na.rm=TRUE), sum(is.finite(TT$ret_prev)))
say("  비교: 전체 유니버스 월수익 중앙 %.4f",
    median(merge(UNIV, PX, by=c("Date","Ticker"))$ret_prev, na.rm=TRUE))
say("완료")
