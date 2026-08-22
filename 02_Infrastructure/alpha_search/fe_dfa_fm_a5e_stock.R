# fe_dfa_fm_a5e_stock — A5E 팩터 모멘텀 가중의 종목 전파 (prereg dfa_v13 R14, 감사 사양 8-7b)
#   Score_i = sum_f w_f x Z_f,i   (w_f = A5E 3-코호트 평균 가중, Z = Z_Score_Aligned)
#   A5E: broad-21 팩터 중 trailing 12M active > 0 인 팩터에 크기 비례 가중, 3-코호트 중첩(분기 홀딩)
#   ★DFA 국면판(fe_dfa_regimesignals_bl.R) 대비 차별점: 국면 모델 없음, 가중이 관측 모멘텀에서 직접 도출
stopifnot(exists("RAWDATA"), data.table::is.data.table(RAWDATA))
suppressPackageStartupMessages({library(arrow); library(data.table)})
.PRJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!exists("load_month_factors", mode="function"))
  source(file.path(.PRJ,"02_Infrastructure/factor_db/factor_db_connector.R"))

## ---- 1) 팩터 지수 월간 → A5E 가중 (코호트별) ----
.R <- as.data.table(read_parquet(file.path(.PRJ,"outputs/ramp/dfa_index_returns_broad_202608.parquet")))
.R[,Date:=as.Date(Date)]; setorder(.R,Date); .R<-.R[is.finite(Market)]
.fac <- setdiff(names(.R), c("Date","ym","as_of_date","source_version","Market"))
.R[,ym:=format(Date,"%Y-%m")]
.mon <- .R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))), by=ym, .SDcols=c("Market",.fac)]
setorder(.mon,medate); .NM<-nrow(.mon); .NF<-length(.fac)
.S <- matrix(NA_real_,.NM,.NF); colnames(.S)<-.fac
for(.fi in 1:.NF) for(.m in 12:.NM){ .w<-(.m-11):.m
  .S[.m,.fi] <- prod(1+.mon[[.fac[.fi]]][.w])/prod(1+.mon$Market[.w])-1 }
## 팩터 index명 → factor_db id
.FMAP <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets", LowVol="D03_RealVol",
  LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity",
  Accrual="AC18_Accrual_Quality", Consensus="C19_Composite_Earnings", SUE="C01_SUE",
  Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
## 코호트 c 의 적용월 m 에 유효한 결정월 d (분기 홀딩): 각 코호트 시작 13+c, 3개월마다 갱신
.dec_for <- function(m, cc, start0=13L, freq=3L){
  st <- start0 + cc; if(m < st) return(NA_integer_)
  m - 1L - ((m - st) %% freq) }        # 마지막 갱신 시점의 결정월(= 그 시점 m0 의 m0-1)
.w_at <- function(d){                   # 결정월 d 의 A5E 팩터 가중 (Market 제외분만 반환)
  if(is.na(d) || d < 12) return(NULL)
  s <- .S[d,]; pos <- which(is.finite(s) & s > 0)
  if(!length(pos)) return(NULL)
  w <- s[pos]/sum(s[pos]); names(w) <- .fac[pos]; w }

## ---- 2) 월말마다 3코호트 평균 가중 → 종목 스코어 ----
.rows <- list()
for(.m in 16:.NM){                       # 전 코호트 가동 후
  .agg <- setNames(rep(0, .NF), .fac); .nc <- 0L
  for(.cc in 0:2){ .d <- .dec_for(.m,.cc); .w <- .w_at(.d)
    if(!is.null(.w)){ .agg[names(.w)] <- .agg[names(.w)] + .w; .nc <- .nc + 1L } }
  if(.nc == 0L) next
  .agg <- .agg/.nc                       # 3코호트 자본 1/3씩 → 평균 가중
  .use <- .agg[.agg > 0]; if(!length(.use)) next
  .sd_date <- .mon$medate[.m]            # 스코어 기준일 = 적용월 직전 월말(캐노니컬: 스코어 t → 익월 적용)
  .ids <- unname(.FMAP[names(.use)]); .ids <- .ids[!is.na(.ids)]
  .f <- tryCatch(as.data.table(load_month_factors(.sd_date, factor_names=.ids)), error=function(e) NULL)
  if(is.null(.f) || !nrow(.f)) next
  .zw <- dcast(.f[Factor_Name %in% .ids], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  .sc <- rep(0, nrow(.zw)); .wsum <- 0
  for(.nm in names(.use)){ .col <- .FMAP[[.nm]]
    if(!is.null(.col) && .col %in% names(.zw)){ .z <- .zw[[.col]]; .z[!is.finite(.z)] <- 0
      .sc <- .sc + .use[[.nm]]*.z; .wsum <- .wsum + .use[[.nm]] } }
  if(.wsum <= 0) next
  .sc <- .sc/.wsum                       # 결측 팩터 제외 후 가중 재정규화
  .rows[[length(.rows)+1]] <- data.table(Date=.sd_date, Ticker=.zw$Ticker, Score=.sc)
}
FACTORS <- rbindlist(.rows)
.liq <- RAWDATA[Date %in% unique(FACTORS$Date) & LiqPass == TRUE, .(Date,Ticker)]
FACTORS <- merge(FACTORS, .liq, by=c("Date","Ticker"))
FACTORS <- FACTORS[is.finite(Score)]
cat(sprintf("[fe_dfa_fm_a5e_stock] FACTORS rows=%d | dates=%d (%s ~ %s)\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$Date), max(FACTORS$Date)))
