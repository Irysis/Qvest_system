# run_f2_regime_flow.R — F2: 외국인 수급 재서술이 FQ-138 의 국면 의존을 설명하는가
# FQ-138: 계약 알파 IC 가 t-1 mega_spread<=0 국면에서 +0.1445(t_NW 5.17), 대형주주도 국면 +0.0108.
# F1: 계약 신호 상위에서 **외국인 순매수 유의 증가(10/11 조합)**, 기관은 유의 변화 없음.
# F2 질문: 외국인 매수 우위가 **국면에 따라 달라지는가**. 달라지면 FQ-138 의 국면 의존은
#          '수급 접근 경로'로 설명되고 mechanism 서술이 갱신된다. 안 달라지면 국면 의존은
#          수급이 아닌 다른 축(유동성 사이클 등)으로 남는다.
# ★국면 정의 = diag_fq125_stage1_regime_robust.R:49-55 verbatim (t-1 시차, PIT 안전)
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

Rg <- as.data.table(read_parquet(file.path(FQ,"grid_returns.parquet")))
SZ <- as.data.table(read_parquet(file.path(FQ,"grid_universe_size.parquet")))
cat(sprintf("[grid_returns] %d행 cols=%s\n[grid_size] %d행 cols=%s\n",
  nrow(Rg), paste(names(Rg),collapse=","), nrow(SZ), paste(names(SZ),collapse=",")))
Rg[, Date := as.Date(Date)]; SZ[, Date := as.Date(Date)]
X <- merge(Rg, SZ, by=c("Date","Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
X[, rk := frank(-Size, ties.method="first"), by=Date]
megasp <- X[, .(mega_spread = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by=Date][order(Date)]
megasp[, ms_lag1 := shift(mega_spread, 1)]
megasp[, ym := format(Date, "%Y%m")]   # ★panelx_A 의 ym 은 "YYYYMM"(대시 없음) — 형식 일치 필수
                                       #   구 판은 "%Y-%m" 이라 조인이 0행(다행히 조용한 오답 대신 0으로 드러남)
cat(sprintf("[mega_spread] %d개월 %s~%s | ms_lag1<=0 인 달 %d (%.1f%%)\n", nrow(megasp),
  min(megasp$ym), max(megasp$ym), sum(megasp$ms_lag1 <= 0, na.rm=TRUE),
  100*mean(megasp$ms_lag1 <= 0, na.rm=TRUE)))

P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Institutional","Foreign")))
IV[, Date := as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
raw[, Date := as.Date(Date)]; raw[, TV := Close*Vol]
IV <- merge(IV, raw[, .(Date,Ticker,TV)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y-%m")]
MF <- IV[, .(inst=sum(Institutional,na.rm=TRUE), forg=sum(Foreign,na.rm=TRUE), tv=sum(TV,na.rm=TRUE)), by=.(Ticker,ym)]
MF[, `:=`(inst_n=inst/pmax(tv,1), forg_n=forg/pmax(tv,1),
          mi=as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7)))]
E <- copy(P); E[, mi := as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7))]
for (h in 1:3) { a <- MF[, .(Ticker, mi, inst_n, forg_n)]; a[, mi := mi-h]
  setnames(a, c("inst_n","forg_n"), paste0(c("i","f"),h)); E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE) }
E[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("i1","i2","i3")]
E[, `:=`(inst_3m=rowSums(.SD,na.rm=TRUE)), .SDcols=c("i1","i2","i3")]
E[, forg_3m := rowSums(.SD,na.rm=TRUE), .SDcols=c("f1","f2","f3")]
E <- merge(E[n_ok==3L], megasp[, .(ym, ms_lag1)], by="ym")
E <- E[is.finite(ms_lag1)]
E[, broad := ms_lag1 <= 0]
E[, has_contract := amt_sum > 0]
cat(sprintf("[결합] %d건 | broad(ms_lag1<=0) %d건 · mega주도 %d건 | 계약보유 %d건\n",
  nrow(E), sum(E$broad), sum(!E$broad), sum(E$has_contract)))

one <- function(sub, lab) {
  hi <- sub[has_contract == TRUE]; lo <- sub[has_contract == FALSE]
  if (nrow(hi) < 20 || nrow(lo) < 20) return(NULL)
  tf <- t.test(hi$forg_3m, lo$forg_3m); ti <- t.test(hi$inst_3m, lo$inst_3m)
  data.table(국면=lab, n_계약=nrow(hi), n_무계약=nrow(lo),
    외국인차이=round(mean(hi$forg_3m)-mean(lo$forg_3m),5), 외국인t=round(as.numeric(tf$statistic),2), 외국인p=round(tf$p.value,4),
    기관차이=round(mean(hi$inst_3m)-mean(lo$inst_3m),5), 기관t=round(as.numeric(ti$statistic),2), 기관p=round(ti$p.value,4))
}
R <- rbindlist(Filter(Negate(is.null), list(
  one(E, "전체"), one(E[broad == TRUE], "broad (ms_lag1<=0)"), one(E[broad == FALSE], "mega주도 (ms_lag1>0)"))))
cat("\n===== 국면별 계약보유 vs 무계약 수급 격차 =====\n"); print(R)

# 상호작용 직접 검정: forg_3m ~ has_contract * broad
fit <- lm(forg_3m ~ has_contract * broad, data=E)
cs <- summary(fit)$coefficients
cat("\n===== 상호작용 회귀 (forg_3m ~ 계약보유 × broad) =====\n")
print(round(cs, 5))
ix <- grep(":", rownames(cs))
if (length(ix)) cat(sprintf("\n[상호작용항] 계수 %+.5f · t=%.2f · p=%.4f → %s\n",
  cs[ix,1], cs[ix,3], cs[ix,4],
  ifelse(cs[ix,4] < 0.05, "★국면 의존을 수급이 설명 (상호작용 유의)",
         "상호작용 유의하지 않음 — 국면 의존은 수급 외 축")))
fiti <- lm(inst_3m ~ has_contract * broad, data=E)
csi <- summary(fiti)$coefficients; ixi <- grep(":", rownames(csi))
if (length(ixi)) cat(sprintf("[기관 대조 상호작용] 계수 %+.5f · t=%.2f · p=%.4f\n", csi[ixi,1], csi[ixi,3], csi[ixi,4]))
fwrite(R, file.path(OUT, "f2_regime_flow.csv"))
