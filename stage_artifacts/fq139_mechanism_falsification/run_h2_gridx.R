# run_h2_gridx.R — H2: 재구성 대신 **이미 있는 확장 그리드(gridx_*)** 사용
# G1 3연속 실패의 진짜 원인: 확장본이 없어서가 아니라 **내가 파일럿(grid_*)을 쓰고 있었다**.
#   build_fq002_grid_ext.R 헤더: "동일 로직, 창만 2019-12~ 로 확장" → gridx_returns/gridx_universe_size.
#   ★J1 교훈("재구성하지 말고 원본에서")이 여기서도 정답 — 재구성 3회를 원본 파일 1개가 대체.
# 절차: ①gridx 커버리지 확인 ②겹치는 구간에서 pilot grid 와 대조(빌더 헤더가 요구한 vintage 대조)
#       ③확장 국면으로 F2 상호작용 재시험
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

ms_of <- function(rf, sf) {
  R <- as.data.table(read_parquet(file.path(FQ, rf))); R[, Date := as.Date(Date)]
  S <- as.data.table(read_parquet(file.path(FQ, sf))); S[, Date := as.Date(Date)]
  X <- merge(R, S, by=c("Date","Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
  X[, rk := frank(-Size, ties.method="first"), by=Date]
  list(ms = X[, .(ms = mean(Ret_1m[rk<=10]) - median(Ret_1m)), by=Date][order(Date)],
       n = X[, .N, by=Date][, mean(N)])
}
A <- ms_of("grid_returns.parquet",  "grid_universe_size.parquet")
B <- ms_of("gridx_returns.parquet", "gridx_universe_size.parquet")
cat(sprintf("[pilot  grid ] %d개월 %s~%s | 월평균 %.0f종목\n", nrow(A$ms), min(A$ms$Date), max(A$ms$Date), A$n))
cat(sprintf("[확장  gridx ] %d개월 %s~%s | 월평균 %.0f종목\n", nrow(B$ms), min(B$ms$Date), max(B$ms$Date), B$n))

V <- merge(A$ms[, .(Date, ms_pilot=ms)], B$ms[, .(Date, ms_ext=ms)], by="Date")
cat(sprintf("\n[빌더 요구 대조 — 겹침 %d개월] cor %.4f | 라벨(<=0) 일치 %.1f%% | 평균|Δ| %.5f\n",
  nrow(V), suppressWarnings(cor(V$ms_pilot, V$ms_ext)), 100*mean((V$ms_pilot<=0)==(V$ms_ext<=0)),
  mean(abs(V$ms_pilot - V$ms_ext))))
ok <- mean((V$ms_pilot<=0)==(V$ms_ext<=0)) >= 0.85
cat(sprintf("[게이트] %s\n", ifelse(ok, "통과 — 확장 국면으로 F2 재시험", "★미통과 — vintage 갈림, 판정에 병기 필요")))
if (!ok) { fwrite(V, file.path(OUT,"h2_vintage_compare.csv")); quit(save="no", status=0) }

M <- copy(B$ms); setorder(M, Date)
M[, `:=`(ms_lag1 = shift(ms, 1), ym = format(Date, "%Y%m"))]
P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Foreign","Institutional")))
IV[, Date := as.Date(Date)]
rw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
rw[, Date := as.Date(Date)]; rw[, TV := Close*Vol]
IV <- merge(IV, rw[, .(Date,Ticker,TV)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y%m")]
MF <- IV[, .(forg=sum(Foreign,na.rm=TRUE), inst=sum(Institutional,na.rm=TRUE), tv=sum(TV,na.rm=TRUE)), by=.(Ticker,ym)]
MF[, `:=`(forg_n=forg/pmax(tv,1), inst_n=inst/pmax(tv,1),
          mi=as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7)))]
E <- copy(P); E[, mi := as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7))]
for (h in 1:3) { a <- MF[, .(Ticker, mi, forg_n, inst_n)]; a[, mi := mi-h]
  setnames(a, c("forg_n","inst_n"), paste0(c("f","i"),h)); E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE) }
E[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("f1","f2","f3")]
E[, forg_3m := rowSums(.SD,na.rm=TRUE), .SDcols=c("f1","f2","f3")]
E[, inst_3m := rowSums(.SD,na.rm=TRUE), .SDcols=c("i1","i2","i3")]
E <- merge(E[n_ok==3L], M[, .(ym, ms_lag1)], by="ym")[is.finite(ms_lag1)]
E[, `:=`(broad = ms_lag1 <= 0, has_contract = amt_sum > 0)]
cat(sprintf("\n[확장 결합] %d건 | broad %d건(%d개월) · mega주도 %d건(%d개월)\n", nrow(E),
  sum(E$broad), uniqueN(E[broad==TRUE]$ym), sum(!E$broad), uniqueN(E[broad==FALSE]$ym)))
one <- function(sub,lab){ hi<-sub[has_contract==TRUE]; lo<-sub[has_contract==FALSE]
  if (nrow(hi)<20||nrow(lo)<20) return(NULL); tf<-t.test(hi$forg_3m, lo$forg_3m)
  data.table(국면=lab, n_계약=nrow(hi), n_무계약=nrow(lo), 외국인차이=round(mean(hi$forg_3m)-mean(lo$forg_3m),5),
             t=round(as.numeric(tf$statistic),2), p=round(tf$p.value,4)) }
R <- rbindlist(Filter(Negate(is.null), list(one(E,"전체"), one(E[broad==TRUE],"broad (알파 강)"), one(E[broad==FALSE],"mega주도 (알파 약)"))))
cat("\n===== 확장 국면 × 외국인 수급 =====\n"); print(R)
fit <- lm(forg_3m ~ has_contract*broad, data=E); cs <- summary(fit)$coefficients; ix <- grep(":", rownames(cs))
cat(sprintf("\n[상호작용] 계수 %+.5f · t=%.2f · p=%.4f\n", cs[ix,1], cs[ix,3], cs[ix,4]))
cat(sprintf("[판정] %s\n", ifelse(cs[ix,4] < 0.05,
  ifelse(cs[ix,1] > 0, "★수급이 국면 의존을 설명(정방향 유의)", "★반대 방향 유의 — 수급 설명 실패 확정"),
  "상호작용 유의하지 않음 — 표본 확대 후에도 설명력 없음(부호만 보고)")))
fwrite(R, file.path(OUT,"h2_extended_regime.csv"))
