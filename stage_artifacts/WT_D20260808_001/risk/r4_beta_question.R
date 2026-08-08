# =============================================================================
# r4_beta_question.R — 질문1: 제외필터 최상위 분위의 저-β 구조가 현행 Σ 에
#   이미 반영돼 있는가, 결손인가. 반영돼 있다면 어느 항이 담는가.
#
#   설계 원칙: 국면 '분할' 없음. 전표본 span test + 잔차 블록구조 + 노출 분해.
#   metric_type = risk_estimate / risk_validation
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r4] ",fmt,"\n"),...))

E   <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT,"factor_returns.parquet"))); FR[,Date:=as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT,"residuals_panel.parquet"))); RES[,Date:=as.Date(Date)]
AS  <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
S3  <- readRDS(file.path(OUT,"r3_sigma.rds")); m2 <- readRDS(file.path(OUT,"r2_meta.rds"))
fac_names <- m2$fac_names; STY <- m2$sty

say("입력: exposure %d행/%d월 | factor_returns %d월 | residuals %d행 | alpha_scores %d행/%d월",
    nrow(E), uniqueN(E$Date), nrow(FR), nrow(RES), nrow(AS), uniqueN(AS$Date))
say("alpha_scores 컬럼: %s", paste(names(AS), collapse=","))

nwt <- function(x, lag=3L) {   # Newey-West t (평균 0 검정)
  x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag) { g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(lag+1))*g }
  if (s <= 0) return(NA_real_)
  m/sqrt(s/n)
}

# ── 0. Σ 검증: alpha_vector 25종 EW 의 실현 vs 예측 ──────────────────────────
tk <- S3$tk25
RW <- dcast(E[Ticker %in% tk, .(Date,Ticker,Ret_1m)], Date~Ticker, value.var="Ret_1m")
rr <- RW[Date <= as.Date("2026-06-30")][order(Date)]
rr <- tail(rr, 60)
M <- as.matrix(rr[,-1]); pr <- apply(M, 1, function(z) mean(z, na.rm=TRUE))
say("[Σ 검증] alpha_vector 25종 EW 실현 연변동(trailing 60m, 단일기간 횡단면평균) = %.3f | 모델 예측 %.3f | 비율 %.2f",
    stats::sd(pr, na.rm=TRUE)*sqrt(12), sqrt(S3$var_tot*12),
    sqrt(S3$var_tot*12)/(stats::sd(pr,na.rm=TRUE)*sqrt(12)))
say("  (25종 중 수익 관측 종목수 중앙 %d)", as.integer(median(rowSums(!is.na(M)))))

# ── 1. 필터 분위별 β — alpha 실측 재현 ───────────────────────────────────────
P <- merge(AS[, .(Date,Ticker,D03_EWMA_pct,Q01_EB_pct,excl_d03_q20,excl_q01_q20,rk_m01)],
           E[, .(Date,Ticker,beta_60m,ivol_60m,X_BETA,X_SIZE,X_IVOL,X_LIQ,X_MOM,X_QUAL,X_VAL,Ret_1m,Size,Sector)],
           by=c("Date","Ticker"))
say("병합 패널 rows=%d 월 %d | beta 관측 %.3f", nrow(P), uniqueN(P$Date), mean(is.finite(P$beta_60m)))

qtag <- function(p) cut(p, breaks=c(-Inf,.2,.4,.6,.8,Inf), labels=paste0("Q",1:5))
P[, d03_q := qtag(D03_EWMA_pct)][, q01_q := qtag(Q01_EB_pct)]

bt <- P[is.finite(beta_60m), .(beta_med=median(beta_60m), n=.N), by=.(Date,d03_q)]
uni <- P[is.finite(beta_60m), .(beta_uni=median(beta_60m)), by=Date]
bt <- merge(bt, uni, by="Date")[!is.na(d03_q)]
say("[F3 재현 · D03 분위별 β 중앙 (전표본 월중앙) vs 유니버스]")
sm <- bt[, .(beta=median(beta_med), diff_t_nw=nwt(beta_med-beta_uni),
             diff_mean=mean(beta_med-beta_uni)), by=d03_q][order(d03_q)]
sm[, uni := median(uni$beta_uni)]; print(sm)

bt2 <- P[is.finite(beta_60m), .(beta_med=median(beta_60m)), by=.(Date,q01_q)]
bt2 <- merge(bt2, uni, by="Date")[!is.na(q01_q)]
say("[Q01 분위별 β]")
print(bt2[, .(beta=median(beta_med), diff_t_nw=nwt(beta_med-beta_uni)), by=q01_q][order(q01_q)])

# 제외집합 vs 잔존집합 (필터의 실제 소비 형태)
ex <- P[is.finite(beta_60m) & !is.na(excl_q01_q20),
        .(b_ex=median(beta_60m[excl_q01_q20==TRUE], na.rm=TRUE),
          b_kp=median(beta_60m[excl_q01_q20==FALSE], na.rm=TRUE),
          n_ex=sum(excl_q01_q20==TRUE)), by=Date][is.finite(b_ex)]
say("[Q01 제외집합 β %.3f vs 잔존 %.3f | 차 t_NW %.2f | 월평균 제외 %.0f종]",
    median(ex$b_ex), median(ex$b_kp), nwt(ex$b_ex-ex$b_kp), mean(ex$n_ex))

# ── 2. Span test: tier 스프레드가 현행 팩터로 설명되는가 ─────────────────────
mk_spread <- function(col, hi="Q5", lo="Q1") {
  z <- P[!is.na(get(col)) & is.finite(Ret_1m)]
  a <- z[get(col)==hi, .(r_hi=mean(Ret_1m)), by=Date]
  b <- z[get(col)==lo, .(r_lo=mean(Ret_1m)), by=Date]
  merge(a,b,by="Date")[, .(Date, spread=r_hi-r_lo, r_hi, r_lo)]
}
span <- function(y_dt, ycol, xnames, label) {
  m <- merge(y_dt, FR, by="Date"); y <- m[[ycol]]
  X <- as.matrix(m[, ..xnames]); X[!is.finite(X)] <- 0
  keep <- which(apply(X,2,stats::sd)>1e-10); X <- X[,keep,drop=FALSE]
  fit <- stats::lm(y ~ X)
  s <- summary(fit); e <- stats::residuals(fit)
  say("  %-34s n=%3d  R2=%.3f  잔차 연변동 %.4f (총 %.4f, 미설명분산 %.1f%%)  잔차평균 t_NW %.2f",
      label, length(y), s$r.squared, stats::sd(e)*sqrt(12), stats::sd(y)*sqrt(12),
      100*(1-s$r.squared), nwt(e))
  cf <- stats::coef(s); rn <- gsub("^X","",rownames(cf))
  top <- data.table(term=rn, est=cf[,1], t=cf[,3])[term!="(Intercept)"][order(-abs(t))][1:5]
  print(top[, .(term, est=round(est,4), t=round(t,2))])
  list(r2=s$r.squared, resid_vol_ann=stats::sd(e)*sqrt(12), tot_vol_ann=stats::sd(y)*sqrt(12),
       alpha_t=nwt(e), top=top)
}
sp_d03 <- mk_spread("d03_q"); sp_q01 <- mk_spread("q01_q")
say("[Span test — 현행 팩터 전체(MKT+SEC+STYLE)로 tier 스프레드 설명]")
r_d03_full <- span(sp_d03,"spread", fac_names, "D03 Q5-Q1 ~ 전 팩터")
r_q01_full <- span(sp_q01,"spread", fac_names, "Q01 Q5-Q1 ~ 전 팩터")
say("[Span test — MKT 만 (단일 시장항이 담는가)]")
r_d03_mkt <- span(sp_d03,"spread","MKT","D03 Q5-Q1 ~ MKT")
r_q01_mkt <- span(sp_q01,"spread","MKT","Q01 Q5-Q1 ~ MKT")
say("[Span test — MKT + X_BETA (β 항 추가분)]")
r_d03_b <- span(sp_d03,"spread",c("MKT","X_BETA"),"D03 Q5-Q1 ~ MKT+X_BETA")
r_q01_b <- span(sp_q01,"spread",c("MKT","X_BETA"),"Q01 Q5-Q1 ~ MKT+X_BETA")
say("[Span test — MKT + X_BETA + X_IVOL]")
r_d03_bi <- span(sp_d03,"spread",c("MKT","X_BETA","X_IVOL"),"D03 Q5-Q1 ~ MKT+BETA+IVOL")
r_q01_bi <- span(sp_q01,"spread",c("MKT","X_BETA","X_IVOL"),"Q01 Q5-Q1 ~ MKT+BETA+IVOL")

# ── 3. 잔차 블록구조: 모델 후에도 tier 내부가 함께 움직이는가 ────────────────
RP <- merge(RES, P[, .(Date,Ticker,d03_q,q01_q)], by=c("Date","Ticker"))
say("[잔차 블록] 잔차 패널 병합 rows=%d", nrow(RP))
blk <- RP[!is.na(d03_q), .(m_resid=mean(resid), n=.N), by=.(Date,d03_q)]
bw <- dcast(blk, Date~d03_q, value.var="m_resid")
say("  D03 분위별 '평균 잔차' 의 시계열 표준편차(연율) — 0 이면 잔차에 tier 공통성분 없음:")
for (q in paste0("Q",1:5)) if (q %in% names(bw))
  say("    %s : %.4f (n_month %d, 평균종목 %.0f)", q, stats::sd(bw[[q]],na.rm=TRUE)*sqrt(12),
      sum(is.finite(bw[[q]])), mean(blk[d03_q==q]$n))
# 개별 잔차 대비 축소비: tier 평균 잔차 vol / (개별 잔차 vol / sqrt(n))
ind_sd <- stats::sd(RP$resid, na.rm=TRUE)
for (q in paste0("Q",1:5)) if (q %in% names(bw)) {
  nq <- mean(blk[d03_q==q]$n)
  say("    %s : tier-평균잔차 vol %.4f vs 독립가정 기대 %.4f → 배율 %.2f (1.0=독립, >1=잔여 공통성분)",
      q, stats::sd(bw[[q]],na.rm=TRUE), ind_sd/sqrt(nq),
      stats::sd(bw[[q]],na.rm=TRUE)/(ind_sd/sqrt(nq)))
}

# ── 4. 노출 프로파일 (제외집합 vs 잔존, top-25 vs 유니버스) ──────────────────
expo_cols <- c("X_BETA","X_SIZE","X_IVOL","X_LIQ","X_MOM","X_QUAL","X_VAL")
pf <- P[is.finite(X_BETA)]
say("[노출 프로파일 — 월별 평균의 전표본 중앙값]")
prof <- rbind(
  data.table(group="universe",        pf[, lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols]),
  data.table(group="D03_Q5(최저변동)", pf[d03_q=="Q5", lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols]),
  data.table(group="D03_Q1",           pf[d03_q=="Q1", lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols]),
  data.table(group="Q01_Q5",           pf[q01_q=="Q5", lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols]),
  data.table(group="Q01제외집합",      pf[excl_q01_q20==TRUE, lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols]),
  data.table(group="M01_top25",        pf[rk_m01<=25, lapply(.SD, mean, na.rm=TRUE), by=Date, .SDcols=expo_cols][, lapply(.SD, median), .SDcols=expo_cols])
)
print(prof[, lapply(.SD, function(z) if(is.numeric(z)) round(z,3) else z)])

saveRDS(list(sm_d03=sm, ex=ex, prof=prof,
             span=list(d03_full=r_d03_full,q01_full=r_q01_full,d03_mkt=r_d03_mkt,q01_mkt=r_q01_mkt,
                       d03_b=r_d03_b,q01_b=r_q01_b,d03_bi=r_d03_bi,q01_bi=r_q01_bi),
             blk=bw, ind_sd=ind_sd, blk_n=blk[, .(n=mean(n)), by=d03_q],
             realized_ew25_vol=stats::sd(pr,na.rm=TRUE)*sqrt(12)),
        file.path(OUT,"r4_beta.rds"))
say("저장 완료")
