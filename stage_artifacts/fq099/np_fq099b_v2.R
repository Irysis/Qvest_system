## FQ-099b v2 — ★v1 무효 정정판
## v1 오류: rawdata 를 월간으로 가정 → 실제 일간(9003일). 일간 IC·익일수익을 쟀고
##          중복관측 위에 NW lag-3 을 얹어 t 가 크게 부풀려졌다. 사전등록은 "월별 IC·다음달 Ret".
## v2: 계약 함수 build_monthly_forward_returns() 경유(자체 합성 금지) + rolling join 으로 재작성.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099b-v2] ",fmt,"\n"),...))

source("02_Infrastructure/ramp/factor_validation.R")

R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setkey(R, Date)
say("rawdata %d행 · 거래일 %d (%s ~ %s)", nrow(R), uniqueN(R$Date), min(R$Date), max(R$Date))

## 월말 거래일 (2005~) — 계약 함수에 넘길 sig_dates
R[, ym := format(Date, "%Y%m")]
me <- R[Date >= as.Date("2005-01-01"), .(d = max(Date)), by = ym][order(ym)]$d
say("월말 거래일 %d개 (%s ~ %s)", length(me), min(me), max(me))

fwd <- build_monthly_forward_returns(R, me)
ret <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
say("계약 산출 forward panel: %d행 · %d개월 · 종목 %d", nrow(ret), uniqueN(ret$Date), uniqueN(ret$Ticker))

## 월말 Size (분모)
snap <- R[Date %in% me, .(Date, Ticker, Sz = Size)]
panel <- merge(ret, snap, by = c("Date","Ticker"))[Sz > 0]
say("Size 결합 후 %d행", nrow(panel))

## 재무 패널 + 소스-인지 교정
T4 <- as.data.table(read_parquet(".cache/fundamental_xlsx_ttm.parquet"))
D  <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D2 <- merge(D, unique(T4[, .(Ticker,Period,Item,TTM_Value)]), by = c("Ticker","Period","Item"), all.x = TRUE)
D2[, val_fix := fifelse(Source == "DART", Value, TTM_Value)]

nwt <- function(x) {                       # 월별 계열용 NW(lag3)
  x <- x[is.finite(x)]; n <- length(x); if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:3) { if (n <= l) break; s <- s + 2*(1 - l/4)*(sum(e[(l+1):n]*e[1:(n-l)])/n) }
  if (s <= 0) return(NA_real_); m/sqrt(s/n)
}

ic_for <- function(itm) {
  f <- D2[Item == itm & !is.na(Factor_Date), .(Ticker, Factor_Date, Value, val_fix)]
  if (!nrow(f)) return(NULL)
  setkey(f, Ticker, Factor_Date)
  g <- panel[, .(Ticker, Factor_Date = Date, Date, Ret_1m, Sz)]
  setkey(g, Ticker, Factor_Date)
  j <- f[g, roll = TRUE]                                   # ★as-of 최신값 (PIT: Factor_Date <= 월말)
  j <- j[is.finite(Value) & is.finite(val_fix) & is.finite(Ret_1m)]   # ★공통 지지집합
  if (!nrow(j)) return(NULL)
  j[, `:=`(s_raw = Value/Sz, s_fix = val_fix/Sz)]
  s <- j[, .(n = .N,
             ic_raw = if (.N >= 40) cor(s_raw, Ret_1m, method="spearman") else NA_real_,
             ic_fix = if (.N >= 40) cor(s_fix, Ret_1m, method="spearman") else NA_real_),
         by = Date][!is.na(ic_raw) & !is.na(ic_fix)]
  s[order(Date)]
}

say("=== 월별 rank IC · 현행(raw) vs 교정(소스-인지 TTM) · 공통 지지집합 · 계약 forward ===")
out <- list()
for (itm in c("Revenue","OperatingProfit","OperatingCF","GrossProfit")) {
  s <- ic_for(itm)
  if (is.null(s) || nrow(s) < 24) { say("  %-16s 표본 부족", itm); next }
  out[[itm]] <- s
  for (w in list(list(nm="전기간", d=as.Date("1900-01-01")), list(nm="DART기(2016+)", d=as.Date("2016-01-01")))) {
    q <- s[Date >= w$d]; if (nrow(q) < 24) next
    say("  %-16s %-14s 개월 %3d 종목중앙 %3.0f | raw %+.4f (t %+.2f)  fix %+.4f (t %+.2f)  Δ %+.4f",
        itm, w$nm, nrow(q), median(q$n), mean(q$ic_raw), nwt(q$ic_raw), mean(q$ic_fix), nwt(q$ic_fix),
        mean(q$ic_fix) - mean(q$ic_raw))
  }
  d <- s[Date >= as.Date("2016-01-01")]
  if (nrow(d) >= 24) say("      └ ★주판정량: 2016+ 차이계열 Δ 의 NW(lag3) t = %+.2f  (개월 %d)", nwt(d$ic_fix - d$ic_raw), nrow(d))
}
saveRDS(out, "stage_artifacts/fq099/fq099b_v2_ic.rds")
say("저장 → stage_artifacts/fq099/fq099b_v2_ic.rds")
