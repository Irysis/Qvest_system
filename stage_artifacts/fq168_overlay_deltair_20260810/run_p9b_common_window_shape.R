## FQ-168 P9b — P6 의 '공통 창' 이 실제로 무엇이었나 (내 귀속 오류의 원인 특정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P9: 효과는 **1999 이후**(309m, -4.942, t -3.090)가 만든다. 1999 이전은 가용 26m·t -0.99.
##  ⇒ P6 의 "공통 창에서 0/8 이므로 -5.136 은 **1999 이전 의존**" 은 **틀렸다**.
##  ★그러나 P6 의 공통 창이 235m 인데 1999-12~2026-07 은 약 320m 다 ⇒ **85개월이 어딘가 빠졌다**.
##  나는 그것을 '초기 제거' 로 읽었다. 실제로 무엇이 빠졌는지 특정한다.
##  측정: 공통 창의 **연속성**(월 gap) · 빠진 월의 연도 분포 · 빠진 월이 효과에 기여했는지
##  판정: H1_GAPPY(비연속·중간 결손 다수) / H2_CONTIGUOUS(연속, 앞부분만 잘림)
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector","Sector_Lv2")))
RD[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by=.(Ticker, ym), .SDcols=c("Sector","Sector_Lv2")]
rm(RD); invisible(gc())
U <- copy(ret)[, ym := format(Date,"%Y-%m")]
U <- merge(U, SEC, by=c("Ticker","ym"), all.x=TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
for (k in c(1L,2L,3L,6L)) U[, (paste0("r",k)) := shift(frollsum(Ret_1m,k),1L), by=Ticker]
cell_months <- function(pc, sc) {
  W <- U[is.finite(get(pc)) & !is.na(get(sc)) & nzchar(get(sc)) & !is.na(exc)]
  W[, ns := .N, by=c("Date",sc)]; W <- W[ns >= 5L]
  W[, nm := .N, by=Date]; W <- W[nm >= 125L]; unique(W$Date)
}
grid <- CJ(k=c(1L,2L,3L,6L), sec=c("Sector","Sector_Lv2"), sorted=FALSE)
mons <- lapply(seq_len(nrow(grid)), function(i) cell_months(paste0("r",grid$k[i]), grid$sec[i]))
names(mons) <- sprintf("%dm_%s", grid$k, ifelse(grid$sec=="Sector","Lv1","Lv2"))
COMMON <- as.Date(Reduce(intersect, mons), origin="1970-01-01")
BASE   <- as.Date(mons[["1m_Lv1"]], origin="1970-01-01")     # D1 정의의 전체 창
cat(sprintf("[창] D1 전체 %d개월(%s~%s) · 공통 %d개월(%s~%s)\n",
            length(BASE), min(BASE), max(BASE), length(COMMON), min(COMMON), max(COMMON)))
miss <- sort(setdiff(BASE, COMMON)); miss <- as.Date(miss, origin="1970-01-01")
cat(sprintf("**빠진 월 %d개** — 연도 분포:\n", length(miss)))
print(table(format(miss, "%Y")))
## 연속성: 공통 창 안에서 월 간격이 1개월 초과인 지점
cm <- sort(COMMON); gaps <- which(as.numeric(difftime(cm[-1], cm[-length(cm)], units="days")) > 45)
cat(sprintf("\n공통 창 내부 gap(>45일) %d곳%s\n", length(gaps),
            if (length(gaps)) sprintf(" — 예: %s → %s", cm[gaps[1]], cm[gaps[1]+1]) else ""))
## 셀별 창 길이 — 무엇이 교집합을 좁혔나
cat("\n셀별 월수:\n"); print(vapply(mons, length, 1L))
## 빠진 월들이 효과에 얼마나 기여했나
W <- U[is.finite(r1) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]; W[, nm := .N, by=Date]; W <- W[nm >= 125L]
W[, sc := 1 - (frank(r1, ties.method="average") - 0.5)/.N, by=.(Date,Sector)]
W[, q4 := cut(frank(sc, ties.method="first"), breaks=quantile(seq_len(.N), probs=seq(0,1,0.25)),
              include.lowest=TRUE, labels=FALSE), by=Date]
S <- W[, .(bot=mean(exc[q4==1L],na.rm=TRUE), all=mean(exc,na.rm=TRUE)), by=Date][order(Date)]
S[, rel := bot - all]
nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<20L) return(NA_real_)
  m<-lm(x~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3L,prewhite=FALSE)[1,1]))}
f <- function(d,l) { s <- S[Date %in% d]
  cat(sprintf("  %-18s n=%3d · rel %+7.3f%%p · t %+6.3f\n", l, nrow(s), mean(s$rel,na.rm=TRUE)*1200, nw_t(s$rel))) }
cat("\n=== 효과 기여 ===\n"); f(BASE,"D1 전체"); f(COMMON,"공통 창"); f(miss,"**빠진 월들**")
verdict <- if (length(gaps) > 0L) "H1_GAPPY" else "H2_CONTIGUOUS"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "H1_GAPPY")
  cat("=> 공통 창은 **연속 구간이 아니다**. P6 의 '1999 이전 제거' 서술은 틀렸고,\n   빠진 것은 **중간에 흩어진 월들**이다 — 그 월들이 효과를 담고 있었다\n")
write_json(list(verdict=verdict, n_base=length(BASE), n_common=length(COMMON),
                n_missing=length(miss), n_internal_gaps=length(gaps),
                missing_by_year=as.list(table(format(miss,"%Y"))),
                cell_months=as.list(vapply(mons, length, 1L))),
           file.path(OUT,"p9b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
