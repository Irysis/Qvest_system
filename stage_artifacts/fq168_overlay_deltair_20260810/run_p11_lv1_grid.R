## FQ-168 P11 — Lv1 전용 격자: P5/P6 의 '취약' 이 Lv2 인공물이었나
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P9b: 공통 창(235m)은 **비연속**(gap 12곳)이고 `6m_Lv2` 가 교집합을 좁혔다.
##       빠진 100m 이 rel **-11.552(t -3.360)** ⇒ **공통 창이 효과 구간을 도려냈다**.
##  ⇒ Lv2 를 빼고 **Lv1 전용**(기간 1/2/3/6)으로 다시 그린다. 4셀 공통 창은 315m 수준일 것.
##  ★★내가 방금 만든 규약을 여기서 적용한다: 창을 min/max 로 부르지 말고
##    **개수 + 내부 gap + 이론 개월수 대조**를 반드시 출력한다.
##  판정:
##   I1_WIDE   : 유효 셀(음수 ∧ |t|>=2) >= 3 → P5/P6 는 **Lv2 인공물**, P1 재개 조건 성립
##   I2_NARROW : 1~2
##   I3_NONE   : 0 → Lv2 무관하게 좁다
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by=.(Ticker, ym), .SDcols="Sector"]
rm(RD); invisible(gc())
U <- copy(ret)[, ym := format(Date,"%Y-%m")]
U <- merge(U, SEC, by=c("Ticker","ym"), all.x=TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
KS <- c(1L,2L,3L,6L)
for (k in KS) U[, (paste0("r",k)) := shift(frollsum(Ret_1m,k),1L), by=Ticker]
cell_months <- function(pc) {
  W <- U[is.finite(get(pc)) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
  W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]
  W[, nm := .N, by=Date]; W <- W[nm >= 125L]; unique(W$Date)
}
mons <- lapply(KS, function(k) cell_months(paste0("r",k)))
names(mons) <- paste0(KS, "m")
CM <- sort(as.Date(Reduce(intersect, mons), origin="1970-01-01"))

## ★창 구성 실측 (오늘 만든 규약)
theo <- length(seq(min(CM), max(CM), by = "month"))
gaps <- which(as.numeric(difftime(CM[-1], CM[-length(CM)], units="days")) > 45)
cat(sprintf("[창 구성] 실제 **%d개월** · 범위 %s~%s(이론 %d) · **결손 %d** · 내부 gap **%d곳**\n",
            length(CM), min(CM), max(CM), theo, theo - length(CM), length(gaps)))
cat(sprintf("  셀별 월수: %s\n", paste(sprintf("%s=%d", names(mons), vapply(mons, length, 1L)), collapse=" · ")))
if (length(gaps)) cat(sprintf("  gap 예: %s → %s\n", CM[gaps[1]], CM[gaps[1]+1]))

nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<20L) return(NA_real_)
  m<-lm(x~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3L,prewhite=FALSE)[1,1]))}
run <- function(k) {
  pc <- paste0("r",k)
  W <- U[Date %in% CM & is.finite(get(pc)) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
  W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]
  W[, nm := .N, by=Date]; W <- W[nm >= 125L]
  W[, sc := 1 - (frank(get(pc), ties.method="average") - 0.5)/.N, by=.(Date,Sector)]
  W[, q4 := cut(frank(sc, ties.method="first"), breaks=quantile(seq_len(.N), probs=seq(0,1,0.25)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  S <- W[, .(bot=mean(exc[q4==1L],na.rm=TRUE), all=mean(exc,na.rm=TRUE)), by=Date][order(Date)]
  S[, rel := bot - all]
  data.table(k=k, n=nrow(S), rel_ann=round(mean(S$rel,na.rm=TRUE)*1200,3), t=round(nw_t(S$rel),3))
}
R <- rbindlist(lapply(KS, run))
R[, valid := is.finite(t) & rel_ann < 0 & abs(t) >= 2]
cat("\n=== Lv1 전용 격자 (공통 창) ===\n"); print(R[])
nv <- sum(R$valid)
cat(sprintf("\n★유효 셀: **%d / %d**\n", nv, nrow(R)))
verdict <- if (nv >= 3L) "I1_WIDE" else if (nv >= 1L) "I2_NARROW" else "I3_NONE"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "I1_WIDE")  cat("=> P5/P6 의 '취약' 은 **Lv2 인공물**이었다. P1 재개 조건 성립\n")
if (verdict == "I2_NARROW") cat("=> 좁다 — 유효 좌표를 사전등록하고 그 안에서만 P1\n")
if (verdict == "I3_NONE")  cat("=> Lv2 무관하게 서지 않는다. P8 소비면 라우팅 검토\n")
cat(sprintf("\n(대조) D1 전체창 335m = -5.136(t -3.224) · 1999 이후 309m = -4.942(t -3.090)\n"))
fwrite(R, file.path(OUT,"p11_lv1_grid.csv"))
write_json(list(verdict=verdict, n_common=length(CM), theoretical=theo,
                missing=theo-length(CM), internal_gaps=length(gaps),
                cell_months=as.list(vapply(mons, length, 1L)), n_valid=nv, results=R),
           file.path(OUT,"p11_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
