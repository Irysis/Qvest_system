# run_g1b_universe_scoped.R — G1b: 유니버스 범위를 맞춰 재현 게이트 재시도
# G1 실패 원인: rawdata 전체시장(1,560종목/월)으로 median 을 잡아 원본(K200∪KQ150 350종목/월)과
#   다른 것을 쟀다 — 게이트가 정확히 막았다(cor 0.177·라벨 일치 59.5%).
# 수리: .cache/universe_support/us_k200.parquet ∪ us_kq150.parquet 으로 유니버스를 복원해 재계산.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

k2 <- as.data.table(read_parquet(".cache/universe_support/us_k200.parquet"))
kq <- as.data.table(read_parquet(".cache/universe_support/us_kq150.parquet"))
cat(sprintf("[us_k200] %d행 cols=%s\n[us_kq150] %d행 cols=%s\n", nrow(k2), paste(names(k2),collapse=","),
            nrow(kq), paste(names(kq),collapse=",")))
print(utils::head(k2, 2))
vcol <- setdiff(names(k2), c("Date","Ticker"))[1]
cat(sprintf("[멤버십 열 추정] %s | 값 분포: %s\n", vcol,
            paste(utils::head(sort(table(k2[[vcol]]), decreasing=TRUE), 4), collapse=" / ")))
mk_mem <- function(D, lab) { D <- as.data.table(D); D[, Date := as.Date(Date)]
  v <- setdiff(names(D), c("Date","Ticker"))[1]
  D <- D[!is.na(get(v))]
  keep <- if (is.logical(D[[v]])) D[get(v) == TRUE] else if (is.numeric(D[[v]])) D[get(v) > 0] else D[as.character(get(v)) %in% c("Y","TRUE","1")]
  unique(keep[, .(Date, Ticker, src = lab)]) }
U <- unique(rbind(mk_mem(k2,"k200"), mk_mem(kq,"kq150"))[, .(Date, Ticker)])
U[, ymd := as.Date(paste0(format(Date, "%Y-%m"), "-01"))]
cat(sprintf("[유니버스] %d행 | %s ~ %s | 월평균 %.0f종목\n", nrow(U), min(U$Date), max(U$Date),
            U[, uniqueN(Ticker), by=ymd][, mean(V1)]))

raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret","Size")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, ymd := as.Date(paste0(format(Date, "%Y-%m"), "-01"))]
MR <- raw[, .(Ret_1m = prod(1+Ret)-1, Size = last(Size[is.finite(Size)]), nd = .N), by=.(Ticker, ymd)]
MR <- MR[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size) & nd >= 10]
MRU <- merge(MR, unique(U[, .(Ticker, ymd)]), by=c("Ticker","ymd"))
MRU[, rk := frank(-Size, ties.method="first"), by=ymd]
rec <- MRU[, .(ms_rec = mean(Ret_1m[rk <= 10]) - median(Ret_1m), n = .N), by=ymd][order(ymd)]
cat(sprintf("[재구성 유니버스-scoped] %d개월 %s~%s | 월평균 %.0f종목\n", nrow(rec), min(rec$ymd), max(rec$ymd), mean(rec$n)))

Rg <- as.data.table(read_parquet(file.path(FQ,"grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet(file.path(FQ,"grid_universe_size.parquet"))); SZ[, Date := as.Date(Date)]
X <- merge(Rg, SZ, by=c("Date","Ticker"))[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
X[, rk := frank(-Size, ties.method="first"), by=Date]
orig <- X[, .(ms_orig = mean(Ret_1m[rk <= 10]) - median(Ret_1m)), by=Date][order(Date)]
orig[, ymd := as.Date(paste0(format(Date, "%Y-%m"), "-01"))]
V <- merge(orig[, .(ymd, ms_orig)], rec[, .(ymd, ms_rec)], by="ymd")
cat(sprintf("\n[재현 검증] 겹침 %d개월 | cor %.4f | 부호일치 %.1f%% | 라벨(<=0) 일치 %.1f%% | 평균|Δ| %.4f\n",
  nrow(V), suppressWarnings(cor(V$ms_orig,V$ms_rec)), 100*mean(sign(V$ms_orig)==sign(V$ms_rec)),
  100*mean((V$ms_orig<=0)==(V$ms_rec<=0)), mean(abs(V$ms_orig-V$ms_rec))))
ok <- mean((V$ms_orig<=0)==(V$ms_rec<=0)) >= 0.85
cat(sprintf("[게이트] %s\n", ifelse(ok, "통과 — 확장 진행", "★여전히 미통과 — 확장 보류(원본과 다른 것을 재는 중)")))
if (!ok) { fwrite(V, file.path(OUT,"g1b_recon_compare.csv")); quit(save="no", status=0) }

rec[, `:=`(ms_lag1 = shift(ms_rec,1), ym = format(ymd, "%Y%m"))]
P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet", col_select=c("Date","Ticker","Foreign")))
IV[, Date := as.Date(Date)]
rw2 <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
rw2[, Date := as.Date(Date)]; rw2[, TV := Close*Vol]
IV <- merge(IV, rw2[, .(Date,Ticker,TV)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y%m")]
MF <- IV[, .(forg=sum(Foreign,na.rm=TRUE), tv=sum(TV,na.rm=TRUE)), by=.(Ticker,ym)]
MF[, `:=`(forg_n=forg/pmax(tv,1), mi=as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7)))]
E <- copy(P); E[, mi := as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7))]
for (h in 1:3) { a <- MF[, .(Ticker, mi, forg_n)]; a[, mi := mi-h]; setnames(a,"forg_n",paste0("f",h))
  E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE) }
E[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("f1","f2","f3")]
E[, forg_3m := rowSums(.SD,na.rm=TRUE), .SDcols=c("f1","f2","f3")]
E <- merge(E[n_ok==3L], rec[, .(ym, ms_lag1)], by="ym")[is.finite(ms_lag1)]
E[, `:=`(broad = ms_lag1 <= 0, has_contract = amt_sum > 0)]
cat(sprintf("\n[확장 결합] %d건 | broad %d건(%d개월) · mega주도 %d건\n", nrow(E), sum(E$broad),
            uniqueN(E[broad==TRUE]$ym), sum(!E$broad)))
one <- function(sub,lab){ hi<-sub[has_contract==TRUE]; lo<-sub[has_contract==FALSE]
  if (nrow(hi)<20||nrow(lo)<20) return(NULL); tf<-t.test(hi$forg_3m, lo$forg_3m)
  data.table(국면=lab, n_계약=nrow(hi), n_무계약=nrow(lo), 외국인차이=round(mean(hi$forg_3m)-mean(lo$forg_3m),5),
             t=round(as.numeric(tf$statistic),2), p=round(tf$p.value,4)) }
R <- rbindlist(Filter(Negate(is.null), list(one(E,"전체"), one(E[broad==TRUE],"broad (알파 강)"), one(E[broad==FALSE],"mega주도 (알파 약)"))))
cat("\n===== 확장 국면 × 외국인 수급 =====\n"); print(R)
fit <- lm(forg_3m ~ has_contract*broad, data=E); cs <- summary(fit)$coefficients; ix <- grep(":", rownames(cs))
cat(sprintf("\n[상호작용] 계수 %+.5f · t=%.2f · p=%.4f → %s\n", cs[ix,1], cs[ix,3], cs[ix,4],
  ifelse(cs[ix,4]<0.05, ifelse(cs[ix,1]>0,"★수급이 국면 의존 설명","★반대 방향 유의 — 설명 실패 확정"), "여전히 유의하지 않음")))
fwrite(R, file.path(OUT,"g1b_extended_regime.csv"))
