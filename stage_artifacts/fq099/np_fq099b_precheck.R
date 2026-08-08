## FQ-099b 사전 확인 — 교정이 IC 를 개선하는가 (51팩터 전량 재빌드 前 저비용 판정)
## read-only. factor_db 무수정. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099b] ",fmt,"\n"),...))

T4 <- as.data.table(read_parquet(".cache/fundamental_xlsx_ttm.parquet"))
D  <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D2 <- merge(D, unique(T4[, .(Ticker,Period,Item,TTM_Value)]), by=c("Ticker","Period","Item"), all.x=TRUE)
D2[, val_fix := fifelse(Source=="DART", Value, TTM_Value)]

R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
R[, inuniv := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]
setorder(R, Ticker, Date)
say("rawdata 월수 %d (%s ~ %s)", uniqueN(R$Date), min(R$Date), max(R$Date))
## 전방 수익 = 다음 달 Ret (신호는 당월말까지 정보만)
R[, fwd := shift(Ret, 1L, type="lead"), by=Ticker]

months <- sort(unique(R[Date >= as.Date("2005-01-01")]$Date))
nwt <- function(x) {                       # NW(lag3) t
  x <- x[is.finite(x)]; n <- length(x); if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:3) { if (n<=l) break; gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/4)*gl }
  if (s <= 0) return(NA_real_); m/sqrt(s/n)
}

ic_series <- function(itm) {
  out <- rbindlist(lapply(months, function(sd) {
    f <- D2[Item==itm & Factor_Date <= sd]
    if (!nrow(f)) return(NULL)
    setorder(f, Ticker, Factor_Date); f <- f[, .SD[.N], by=Ticker]
    p <- R[Date==sd & inuniv==TRUE, .(Ticker, Sz=Size, fwd)]
    z <- merge(f[, .(Ticker, Value, val_fix)], p, by="Ticker")
    z <- z[Sz>0 & is.finite(Value) & is.finite(val_fix) & is.finite(fwd)]   # ★공통 지지
    if (nrow(z) < 40) return(NULL)
    data.table(sd=sd, n=nrow(z),
               ic_raw = cor(z$Value/z$Sz,   z$fwd, method="spearman"),
               ic_fix = cor(z$val_fix/z$Sz, z$fwd, method="spearman"))
  }))
  out
}

say("=== 월별 rank IC: 현행(raw) vs 교정(소스-인지 TTM) · 공통 지지집합 ===")
res <- list()
for (itm in c("Revenue","OperatingProfit","OperatingCF","GrossProfit")) {
  s <- ic_series(itm)
  if (is.null(s) || nrow(s) < 24) { say("  %-16s 표본 부족", itm); next }
  res[[itm]] <- s
  for (win in list(list(nm="전기간", d=as.Date("1900-01-01")), list(nm="DART기(2016+)", d=as.Date("2016-01-01")))) {
    q <- s[sd >= win$d]
    if (nrow(q) < 24) next
    say("  %-16s %-14s n=%3d | IC raw %+.4f (t %+.2f)  fix %+.4f (t %+.2f)  Δ %+.4f",
        itm, win$nm, nrow(q), mean(q$ic_raw), nwt(q$ic_raw),
        mean(q$ic_fix), nwt(q$ic_fix), mean(q$ic_fix)-mean(q$ic_raw))
  }
  d <- s[sd >= as.Date("2016-01-01")]
  if (nrow(d) >= 24) say("      └ 2016+ 차이계열 Δ의 NW t = %+.2f (교정이 유의하게 낫나)", nwt(d$ic_fix - d$ic_raw))
}
saveRDS(res, "stage_artifacts/fq099/fq099b_ic_series.rds")
say("저장 → stage_artifacts/fq099/fq099b_ic_series.rds")
