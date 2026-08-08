# run_g1_regime_extend.R — G1: 국면 변수(mega_spread) 커버리지 확장 → F2 상호작용 확정 시도
# 문제: 원본 mega_spread 는 grid_universe_size 커버리지 때문에 202301~202606(42개월) 뿐이라
#   F2 의 broad 국면 표본이 13개월·299 이벤트로 얇았다(상호작용 p=0.182 확정 불가).
# 방법: rawdata(Size·Ret 보유)로 재구성해 201912~202607 전 구간 확보.
#   ★단 확장 전에 **겹치는 42개월에서 원본과 재현되는지 먼저 검증**한다(재현 없는 확장은 기준 없음).
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

## --- 원본 (42개월) ---
Rg <- as.data.table(read_parquet(file.path(FQ,"grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet(file.path(FQ,"grid_universe_size.parquet"))); SZ[, Date := as.Date(Date)]
X <- merge(Rg, SZ, by=c("Date","Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
X[, rk := frank(-Size, ties.method="first"), by=Date]
orig <- X[, .(ms_orig = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by=Date][order(Date)]
cat(sprintf("[원본] %d개월 %s~%s | 월평균 종목 %.0f\n", nrow(orig), min(orig$Date), max(orig$Date),
            X[, .N, by=Date][, mean(N)]))

## --- 재구성 (rawdata) ---
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret","Size")))
raw[, Date := as.Date(Date)]
raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, ymd := as.Date(paste0(format(Date, "%Y-%m"), "-01"))]
MR <- raw[, .(Ret_1m = prod(1+Ret)-1, Size = last(Size[is.finite(Size)]), nd = .N), by=.(Ticker, ymd)]
MR <- MR[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size) & nd >= 10]
MR[, rk := frank(-Size, ties.method="first"), by=ymd]
rec_all <- MR[, .(ms_rec = mean(Ret_1m[rk <= 10]) - median(Ret_1m), n = .N), by=ymd][order(ymd)]
cat(sprintf("[재구성 전체시장] %d개월 %s~%s | 월평균 종목 %.0f\n", nrow(rec_all), min(rec_all$ymd), max(rec_all$ymd),
            mean(rec_all$n)))

## --- ★재현 검증 (겹치는 구간) ---
orig[, ymd := as.Date(paste0(format(Date, "%Y-%m"), "-01"))]
V <- merge(orig[, .(ymd, ms_orig)], rec_all[, .(ymd, ms_rec)], by="ymd")
cat(sprintf("\n[재현 검증] 겹침 %d개월 | cor %.4f | 부호 일치 %.1f%% | 평균|Δ| %.4f\n",
    nrow(V), suppressWarnings(cor(V$ms_orig, V$ms_rec)),
    100*mean(sign(V$ms_orig) == sign(V$ms_rec)), mean(abs(V$ms_orig - V$ms_rec))))
cat(sprintf("[국면 라벨(<=0) 일치] %.1f%% (%d/%d 불일치)\n",
    100*mean((V$ms_orig<=0) == (V$ms_rec<=0)), sum((V$ms_orig<=0) != (V$ms_rec<=0)), nrow(V)))
ok <- mean((V$ms_orig<=0) == (V$ms_rec<=0)) >= 0.85
cat(sprintf("[게이트] 라벨 일치 %s → %s\n", ifelse(ok,">=85%","<85%"),
    ifelse(ok, "확장 진행", "★확장 보류 — 재구성이 원본과 다른 것을 재고 있음")))
if (!ok) quit(save="no", status=0)

## --- 확장 국면으로 F2 재시험 ---
rec_all[, `:=`(ms_lag1 = shift(ms_rec, 1), ym = format(ymd, "%Y%m"))]
P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Institutional","Foreign")))
IV[, Date := as.Date(Date)]
rw2 <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
rw2[, Date := as.Date(Date)]; rw2[, TV := Close*Vol]
IV <- merge(IV, rw2[, .(Date,Ticker,TV)], by=c("Date","Ticker"), all.x=TRUE)
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
E <- merge(E[n_ok==3L], rec_all[, .(ym, ms_lag1)], by="ym")[is.finite(ms_lag1)]
E[, `:=`(broad = ms_lag1 <= 0, has_contract = amt_sum > 0)]
cat(sprintf("\n[확장 결합] %d건 | broad %d건(%d개월) · mega주도 %d건 | 계약보유 %d건\n",
  nrow(E), sum(E$broad), uniqueN(E[broad==TRUE]$ym), sum(!E$broad), sum(E$has_contract)))
one <- function(sub, lab) { hi <- sub[has_contract==TRUE]; lo <- sub[has_contract==FALSE]
  if (nrow(hi)<20 || nrow(lo)<20) return(NULL)
  tf <- t.test(hi$forg_3m, lo$forg_3m)
  data.table(국면=lab, n_계약=nrow(hi), n_무계약=nrow(lo),
    외국인차이=round(mean(hi$forg_3m)-mean(lo$forg_3m),5), t=round(as.numeric(tf$statistic),2), p=round(tf$p.value,4)) }
R <- rbindlist(Filter(Negate(is.null), list(one(E,"전체"), one(E[broad==TRUE],"broad (알파 강)"), one(E[broad==FALSE],"mega주도 (알파 약)"))))
cat("\n===== 확장 국면 × 외국인 수급 =====\n"); print(R)
fit <- lm(forg_3m ~ has_contract * broad, data=E); cs <- summary(fit)$coefficients
ix <- grep(":", rownames(cs))
cat(sprintf("\n[상호작용] 계수 %+.5f · t=%.2f · p=%.4f → %s\n", cs[ix,1], cs[ix,3], cs[ix,4],
  ifelse(cs[ix,4] < 0.05, ifelse(cs[ix,1] > 0, "★수급이 국면 의존 설명(정방향 유의)", "★반대 방향 유의 — 설명 실패 확정"),
         "여전히 유의하지 않음 — 부호만 보고")))
fwrite(R, file.path(OUT, "g1_extended_regime.csv"))
