## ramp_shumulvey_features.R — Shu-Mulvey v5 공용 피처 모듈 (FQ-239 P1/P1b).
## f15  = 구 build_feat 15종 그대로 (run_ramp_shumulvey.R:64-75와 수치 동일 — 회귀 보증).
## f17  = f15 + 금리 2종: rate3y_d21 = ewm(diff(KR_Gov3Y),21) · term_d21 = ewm(diff(10Y-3Y),21)
##        (논문 2Y→KR 표준 단기물 3Y 매핑. ECOS 817Y002 당일 고시 — T종가 신호→T+1 체결이라 T일 값 적법.
##         단 P1b 게이트로 금리-피처 lag1 스트레스 의무.)
## f17_usvix = f17에서 vix21(실현변동성 프록시) → US VIX logdiff ewm21, ★t-1 lag 의무
##        (US VIX 당일값은 KST 익일 새벽 확정 — KR T종가 시점 최신 가용 = 전 KR거래일 값).
## prereg: outputs/ramp/smv_v5_prereg_20260820.json

smv_ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_
  for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
smv_rollmin<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-min(x[lo:i])};y}
smv_rollmax<-function(x,w){n<-length(x);y<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1,i-w+1);y[i]<-max(x[lo:i])};y}

## ---- 외생 패널 로더 (지수 거래일 그리드 정렬, locf 상한) ----
## ECOS 국고채·회사채: long(Date,Value,Series) → 그리드 정렬. locf 최대 7 캘린더일(≈5영업일) — 초과 구간 NA.
smv_load_rates<-function(grid_dates, path=".cache/ecos_bond_rates.parquet"){
  b<-data.table::as.data.table(arrow::read_parquet(path))
  b<-b[Series %in% c("KR_Gov3Y","KR_Gov10Y","KR_CorpBBB") & is.finite(Value)]
  b[,Date:=as.Date(Date)]
  wide<-data.table::dcast(b, Date~Series, value.var="Value")
  data.table::setorder(wide,Date); data.table::setkey(wide,Date)
  g<-data.table::data.table(Date=as.Date(grid_dates)); data.table::setkey(g,Date)
  j<-wide[g, roll=7]   # 직전 관측 locf, 7일 초과 시 NA
  list(rate3y=j$KR_Gov3Y, rate10y=j$KR_Gov10Y, corpbbb=j$KR_CorpBBB)
}
## 원/달러 환율(fred_macro_wide::KRW_USD) → 그리드 정렬 후 shift(1) = t-1 lag (US-source 계열 규약, prereg v6 T2).
smv_load_fx<-function(grid_dates, path=".cache/fred_macro_wide.parquet"){
  f<-data.table::as.data.table(arrow::read_parquet(path, col_select=c("Date","KRW_USD")))
  f[,Date:=as.Date(Date)]; f<-f[is.finite(KRW_USD)]
  data.table::setorder(f,Date); data.table::setkey(f,Date)
  g<-data.table::data.table(Date=as.Date(grid_dates)); data.table::setkey(g,Date)
  j<-f[g, roll=7]
  data.table::shift(j$KRW_USD,1)
}
## US VIX: fred_macro_wide(Date,VIX) → 그리드 정렬 후 shift(1) = 전 KR거래일 값 (t-1 lag).
smv_load_usvix<-function(grid_dates, path=".cache/fred_macro_wide.parquet"){
  f<-data.table::as.data.table(arrow::read_parquet(path, col_select=c("Date","VIX")))
  f[,Date:=as.Date(Date)]; f<-f[is.finite(VIX)]
  data.table::setorder(f,Date); data.table::setkey(f,Date)
  g<-data.table::data.table(Date=as.Date(grid_dates)); data.table::setkey(g,Date)
  j<-f[g, roll=7]
  data.table::shift(j$VIX,1)   # t-1 lag
}

## ---- 피처 빌더 ----
## a = 팩터 active 일별, m = 시장 일별, featset ∈ f15|f17|f17_usvix,
## extras = list(rate3y, rate10y, usvix_lag) — 그리드 정렬 완료 벡터 (f15는 불요)
build_feat_v2<-function(a, m, featset="f15", extras=NULL){
  n<-length(a); L<-cumprod(1+ifelse(is.finite(a),a,0))  # 누적 active 레벨
  F<-list()
  for(hl in c(8,21,63)){F[[paste0("ewma",hl)]]<-smv_ewm(a,hl)}
  for(wn in c(8,21,63)){ up<-smv_ewm(pmax(a,0),wn);dn<-smv_ewm(pmax(-a,0),wn);F[[paste0("rsi",wn)]]<-100-100/(1+up/(dn+1e-12))}
  for(wn in c(8,21,63)){rmn<-smv_rollmin(L,wn);rmx<-smv_rollmax(L,wn);F[[paste0("k",wn)]]<-100*(L-rmn)/(rmx-rmn+1e-12)}
  F[["macd_8_21"]]<-(smv_ewm(L,8)-smv_ewm(L,21))/L; F[["macd_21_63"]]<-(smv_ewm(L,21)-smv_ewm(L,63))/L
  dd<-sqrt(smv_ewm(pmin(a,0)^2,21)); F[["logdd21"]]<-log(dd+1e-8)
  ma<-smv_ewm(a,21);mm<-smv_ewm(m,21);cov<-smv_ewm((a-ma)*(m-mm),21);vr<-smv_ewm((m-mm)^2,21);F[["beta21"]]<-cov/(vr+1e-12)
  F[["mkt21"]]<-smv_ewm(m,21)
  rv<-rep(NA_real_,n);for(i in 22:n)rv[i]<-stats::sd(m[(i-20):i]);lrv<-log(rv+1e-8);F[["vix21"]]<-smv_ewm(c(NA,diff(lrv)),21)
  if(featset %in% c("f17","f17_usvix")){
    stopifnot(!is.null(extras$rate3y), !is.null(extras$rate10y))
    F[["rate3y_d21"]]<-smv_ewm(c(NA,diff(extras$rate3y)),21)
    F[["term_d21"]] <-smv_ewm(c(NA,diff(extras$rate10y-extras$rate3y)),21)
  }
  if(featset=="f17_usvix"){
    stopifnot(!is.null(extras$usvix_lag))
    F[["vix21"]]<-smv_ewm(c(NA,diff(log(extras$usvix_lag))),21)   # 프록시 → US VIX(t-1) 교체
  }
  if(featset=="f17k"){   # KR-특이 시장환경 (prereg smv_v6 T2): 신용스프레드 + 환율(t-1)
    stopifnot(!is.null(extras$rate3y), !is.null(extras$corpbbb), !is.null(extras$fx_lag))
    F[["credit_d21"]]<-smv_ewm(c(NA,diff(extras$corpbbb-extras$rate3y)),21)
    F[["fx_d21"]]    <-smv_ewm(c(NA,diff(log(extras$fx_lag))),21)
  }
  data.table::as.data.table(F)
}
