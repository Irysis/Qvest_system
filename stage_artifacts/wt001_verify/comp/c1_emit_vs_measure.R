# c1_emit_vs_measure.R — 완전성 렌즈: 아무도 시험하지 않은 축
#  T1 emitted panel(alpha_scores.parquet) vs measured panel(ELIG) 정합
#  T2 필터 변수 결측 -> 구조적 면역 + 플라시보 풀 오염
#  T3 forward-return inner-join attrition (C6) — 렌즈2의 '결측률 0.0002' 가 잰 대상 확인
# READ-ONLY. 원 산출물 무수정.
suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
say <- function(f, ...) cat(sprintf(paste0("[C1] ", f, "\n"), ...))
source("02_Infrastructure/ramp/factor_validation.R")

# ---------- 입력 실측 (가정 금지) ----------
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
say("INPUT tuned_panel rows=%d  uniq_dates=%d  범위 %s~%s  cols=%s",
    nrow(TUNED), uniqueN(TUNED$Date), as.character(min(TUNED$Date)),
    as.character(max(TUNED$Date)), paste(names(TUNED), collapse=","))
say("INPUT tuned Factor_Name 종류=%d", uniqueN(TUNED$Factor_Name))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
say("INPUT RAWDATA rows=%d  uniq_dates=%d (DAILY 여부 확인)  범위 %s~%s",
    nrow(RAW), uniqueN(RAW$Date), as.character(min(RAW$Date)), as.character(max(RAW$Date)))
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
say("월말행 RAWME rows=%d  월수=%d", nrow(RAWME), length(MEND))

SIG <- sort(unique(TUNED$Date)); sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200==TRUE | KQ150==TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date=as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date=as.Date(Date), Ticker, adv)]
say("returns_dt rows=%d  월=%d | liq rows=%d | bench 월=%d",
    nrow(returns_dt), uniqueN(returns_dt$Date), nrow(liq_dt), nrow(bench_dt))

Wd <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
            Date + Ticker ~ Factor_Name, value.var="score")

# ---------- (A) 측정 패널 ELIG : eval 스크립트 재현 ----------
W <- merge(Wd, UNIV, by=c("Date","Ticker"))
W <- merge(W, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
W <- W[is.na(adv) | adv >= 2e8]
W <- merge(W, returns_dt, by=c("Date","Ticker"), all.x=TRUE)
W <- merge(W, bench_dt, by="Date", all.x=TRUE)
W[, act := Ret_1m - BM_Ret]
ELIG <- W[is.finite(M01_PATHQ)]
ELIG[, rk_m01 := frank(-M01_PATHQ, ties.method="first"), by=Date]
say("A. ELIG(측정) rows=%d 월=%d 월평균 %.1f종목", nrow(ELIG), uniqueN(ELIG$Date), nrow(ELIG)/uniqueN(ELIG$Date))

# ---------- (B) 발행 패널 S : emit 스크립트 재현 (유동성 필터 없음) ----------
W2 <- merge(Wd, UNIV, by=c("Date","Ticker"))
S <- W2[is.finite(M01_PATHQ)]
S[, rk_m01 := frank(-M01_PATHQ, ties.method="first"), by=Date]
for (f in c("D03_EWMA","Q01_EB")) {
  S[, (paste0(f,"_pct")) := { v <- get(f); r <- rep(NA_real_, .N); ok <- is.finite(v)
      if (any(ok)) r[ok] <- frank(v[ok])/sum(ok); r }, by=Date]
}
S[, excl_q01_q20 := is.finite(Q01_EB_pct) & Q01_EB_pct <= 0.20]
S[, score_q01filtered := ifelse(excl_q01_q20, NA_real_, M01_PATHQ)]
say("B. S(발행) rows=%d 월=%d 월평균 %.1f종목", nrow(S), uniqueN(S$Date), nrow(S)/uniqueN(S$Date))
say("B. 발행패널이 측정패널보다 월평균 %+.1f종목 많음",
    nrow(S)/uniqueN(S$Date) - nrow(ELIG)/uniqueN(ELIG$Date))

# T1-a: 발행 패널의 유동성 위반
Sl <- merge(S, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
say("T1a 발행패널 adv<2e8 행수=%d / %d (%.2f%%) · adv 결측 %d",
    Sl[is.finite(adv) & adv < 2e8, .N], nrow(Sl),
    100*Sl[is.finite(adv) & adv < 2e8, .N]/nrow(Sl), Sl[is.na(adv), .N])

# T1-b: 최종 발행 alpha_vector 25종목의 유동성/제약 준수
last_d <- max(S$Date)
L <- S[Date==last_d & !is.na(score_q01filtered)][order(-score_q01filtered)][1:25]
Lc <- merge(L[, .(Date,Ticker,rk_m01,M01_PATHQ)], liq_dt, by=c("Date","Ticker"), all.x=TRUE)
say("T1b last_d=%s  alpha_vector 25종 중 adv 결측 %d · adv<2e8 %d",
    as.character(last_d), Lc[is.na(adv), .N], Lc[is.finite(adv) & adv<2e8, .N])
print(Lc[order(adv)][1:8, .(Ticker, rk_m01, adv=format(adv, big.mark=",", scientific=FALSE))])

# T1-c: 측정 정의 vs 발행 정의로 만든 제외집합 불일치
excl_meas <- ELIG[is.finite(Q01_EB)][, thr := quantile(Q01_EB, 0.20, type=7, na.rm=TRUE), by=Date][Q01_EB<=thr, .(Date,Ticker)]
excl_emit <- S[excl_q01_q20==TRUE, .(Date,Ticker)]
setkey(excl_meas, Date, Ticker); setkey(excl_emit, Date, Ticker)
inter <- nrow(excl_meas[excl_emit, nomatch=0L])
say("T1c 제외집합  측정정의 %d행 / 발행정의 %d행 / 교집합 %d  → Jaccard %.3f",
    nrow(excl_meas), nrow(excl_emit), inter,
    inter/(nrow(excl_meas)+nrow(excl_emit)-inter))

# ---------- T2: 필터 변수 결측 = 구조적 면역 ----------
cov_dt <- ELIG[, .(n=.N, n_q01=sum(is.finite(Q01_EB)), n_d03=sum(is.finite(D03_EWMA))), by=Date]
say("T2 ELIG 내 Q01_EB 가용률: 평균 %.3f (월별 최소 %.3f 최대 %.3f) | D03 가용률 평균 %.3f",
    mean(cov_dt$n_q01/cov_dt$n), min(cov_dt$n_q01/cov_dt$n), max(cov_dt$n_q01/cov_dt$n),
    mean(cov_dt$n_d03/cov_dt$n))
say("T2 => Q01 결측 종목 월평균 %.1f개는 어떤 q 에서도 제외 불가(구조적 면역)",
    mean(cov_dt$n - cov_dt$n_q01))
# 면역 종목의 forward active 가 다른가?
imm <- ELIG[is.finite(act), .(m_imm = mean(act[!is.finite(Q01_EB)]), n_imm=sum(!is.finite(Q01_EB)),
                              m_cov = mean(act[is.finite(Q01_EB)]), n_cov=sum(is.finite(Q01_EB))), by=Date]
imm <- imm[n_imm>=3 & n_cov>=20]
dser <- imm$m_imm - imm$m_cov
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  fit<-lm(x~1); as.numeric(lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]) }
suppressPackageStartupMessages({library(sandwich); library(lmtest)})
say("T2 면역(Q01결측) vs 가용 종목 forward active 차: 연 %+.2f%%  NW t=%+.2f  (n월=%d)",
    100*12*mean(dser), nw_t(dser), length(dser))
# top-25 안에서의 면역 비중
t25 <- ELIG[rk_m01<=25]
say("T2 base top-25 중 Q01 결측(제외 불가) 비율 %.3f · 월평균 %.2f종",
    mean(!is.finite(t25$Q01_EB)), t25[, sum(!is.finite(Q01_EB)), by=Date][, mean(V1)])

# ---------- T3: forward-return attrition (inner join 탈락) ----------
elig_dates <- sort(unique(ELIG$Date))
att <- ELIG[, .(n=.N, n_ret=sum(is.finite(Ret_1m))), by=Date]
say("T3 ELIG 중 Ret_1m 결측(= d1 월말에 부재 = 상폐/이탈) 총 %d / %d = %.4f",
    sum(att$n - att$n_ret), sum(att$n), 1-sum(att$n_ret)/sum(att$n))
# 마지막 달은 구조적 결측 -> 제외
att2 <- att[Date < max(Date)]
say("T3 (최종월 제외) 결측률 %.5f · 월평균 탈락 %.2f종",
    1-sum(att2$n_ret)/sum(att2$n), mean(att2$n - att2$n_ret))
# 탈락이 D03/Q01 하위분위에 편중되는가
E2 <- ELIG[Date < max(Date)]
E2[, q01r := { v<-Q01_EB; r<-rep(NA_real_,.N); ok<-is.finite(v); if(any(ok)) r[ok]<-frank(v[ok])/sum(ok); r }, by=Date]
E2[, d03r := { v<-D03_EWMA; r<-rep(NA_real_,.N); ok<-is.finite(v); if(any(ok)) r[ok]<-frank(v[ok])/sum(ok); r }, by=Date]
say("T3 탈락률: Q01 하위20%% %.5f vs 그외 %.5f | D03 하위20%% %.5f vs 그외 %.5f | Q01결측군 %.5f",
    E2[is.finite(q01r) & q01r<=0.2, mean(!is.finite(Ret_1m))],
    E2[is.finite(q01r) & q01r> 0.2, mean(!is.finite(Ret_1m))],
    E2[is.finite(d03r) & d03r<=0.2, mean(!is.finite(Ret_1m))],
    E2[is.finite(d03r) & d03r> 0.2, mean(!is.finite(Ret_1m))],
    E2[!is.finite(q01r), mean(!is.finite(Ret_1m))])

saveRDS(list(cov_dt=cov_dt, att=att, ELIG_n=nrow(ELIG), S_n=nrow(S)),
        "stage_artifacts/wt001_verify/comp/c1.rds")
say("완료")
