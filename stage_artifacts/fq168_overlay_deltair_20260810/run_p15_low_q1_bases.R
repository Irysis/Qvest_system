## P15 — 명제의 실전 시험: q1 이 낮은 base 에서 오버레이가 사는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P16: q1 최저 3종 = **FAM_S 0.195(eff -16.856)** · FAM_CR 0.150(-9.066) · FAM_L 0.148(-7.753).
##  명제('q1 낮을수록 오버레이 좋음')가 맞다면 **여기서 살아야 한다**.
##  ★P16 의 eff 는 **보유 내부 차이**일 뿐이다 — 유의성도, 포트폴리오 Δ 도 모른다. 둘 다 잰다.
##  측정 2종:
##   ①eff 의 **NW lag-3 t** (보유 내부 차이가 유의한가)
##   ②실제 2-arm `canonical_screen_bt`: 무오버레이 top-25 vs **flagged 제외 후 상위 25** ⇒ **PORT_t Δ**
##      (오버레이 = 하위25% reversal 을 후보에서 빼고 다음 순위로 채움 = '축소' 의 극단형)
##  판정:
##   N1_CONFIRMS   : eff |t|>=2 인 base 중 **2/3 이상에서 PORT_t Δ > 0**
##   N2_PANEL_ONLY : eff 는 유의하나 Δ 가 따라오지 않음 → 패널 차이가 포트로 전이 안 됨
##   N3_FAILS      : eff 도 유의하지 않음
##  ★대조: PG2(q1 0.308·eff +5.740)도 함께 재서 **부호가 반대로 나오는지** 확인(명제의 양끝).
##  ★자본 주장 없음 — 이 base 들은 대부분 t_nb 가 낮다(P12a). **명제 시험이지 후보 발굴 아님**.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
B[, ym := format(Date,"%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date),"%Y-%m")]
NET <- fread(file.path(OUT,"../fq170_band_cost_20260809/p11c_net.csv"))
fam_of <- function(x){f<-sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f)}
NET[, fam := fam_of(base)]
TARGET <- c("S","CR","L")                      # q1 최저 3계열
need <- NET[fam %in% TARGET, base]
ds <- sort(unique(B$Date)); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=need), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]; if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill=TRUE)
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by=.(Ticker,ym), .SDcols="Sector"]; rm(RD); invisible(gc())
U <- merge(B[, .(Date,Ticker,ym)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, SEC, by=c("Ticker","ym"), all.x=TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, A[!is.na(score_eff), .(ym,Ticker,PG2=score_eff)], by=c("ym","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date); U[, r1 := shift(Ret_1m,1L), by=Ticker]
W <- U[is.finite(r1) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]
W[, nm := .N, by=Date]; W <- W[nm >= 125L]
W[, sc := 1 - (frank(r1, ties.method="average") - 0.5)/.N, by=.(Date,Sector)]
W[, q4 := cut(frank(sc, ties.method="first"), breaks=quantile(seq_len(.N), probs=seq(0,1,0.25)),
              include.lowest=TRUE, labels=FALSE), by=Date]
W[, flagged := q4 == 1L]
zs <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) rep(0,length(x)) else (x-m)/s}
nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<24L) return(NA_real_)
  m<-lm(x~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3L,prewhite=FALSE)[1,1]))}
mk <- function(D, bc, drop_flagged) D[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; fl <- .SD$flagged[o]
  cand <- if (drop_flagged) tk[!fl] else tk
  sel <- head(cand, 25L)
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","flagged",bc)]
runbt <- function(Sc, lab) { r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench,
    top_n=25L, cost_bps_oneway=15, liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8,
    run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL); list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage) }
bases <- list()
for (f in TARGET) { mem <- intersect(NET[fam==f, base], names(W)); if (length(mem)) bases[[paste0("FAM_",f)]] <- mem }
rows <- list()
for (nm in c(names(bases), "PG2")) {
  if (nm == "PG2") { cc <- "PG2" } else { W[, .tmp := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=bases[[nm]]]; cc <- ".tmp" }
  D <- W[is.finite(get(cc))]; D[, npg := .N, by=Date]; D <- D[npg >= 60L]
  D[, rk := frank(-get(cc), ties.method="first"), by=Date]
  H <- D[rk <= 25L]
  S <- H[, .(q1=mean(flagged), f=mean(exc[flagged],na.rm=TRUE), u=mean(exc[!flagged],na.rm=TRUE)), by=Date]
  S <- S[is.finite(f) & is.finite(u)]; S[, d := f - u]
  r0 <- runbt(mk(D, cc, FALSE), paste0("p15_",nm,"_base"))
  r1 <- runbt(mk(D, cc, TRUE),  paste0("p15_",nm,"_ovl"))
  if (".tmp" %in% names(W)) W[, .tmp := NULL]
  if (is.null(r0)||is.null(r1)) { cat(sprintf("  fail %s\n", nm)); next }
  rows[[length(rows)+1L]] <- data.table(base=nm, q1=round(mean(S$q1),3), n=nrow(S),
    eff=round(mean(S$d,na.rm=TRUE)*1200,3), eff_t=round(nw_t(S$d),3),
    t_base=round(r0$t,3), t_ovl=round(r1$t,3), delta=round(r1$t-r0$t,3),
    cov=round(min(r0$cov,r1$cov),3))
  cat(sprintf("  %-8s q1 %.3f · eff %+8.3f(t %+5.2f) · PORT_t %+6.3f → %+6.3f · **Δ %+6.3f**\n",
              nm, mean(S$q1), mean(S$d,na.rm=TRUE)*1200, nw_t(S$d), r0$t, r1$t, r1$t-r0$t))
}
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
cat("\n=== 결과 ===\n"); print(R[order(q1)])
LOW <- R[base != "PG2"]; sig <- LOW[is.finite(eff_t) & abs(eff_t) >= 2]
verdict <- if (!nrow(sig)) "N3_FAILS" else
           if (sum(sig$delta > 0) >= ceiling(2/3*nrow(sig))) "N1_CONFIRMS" else "N2_PANEL_ONLY"
cat(sprintf("\neff 유의 base %d/%d · 그중 Δ>0 %d\n판정: %s\n",
            nrow(sig), nrow(LOW), sum(sig$delta > 0), verdict))
pg <- R[base == "PG2"]
if (nrow(pg)) cat(sprintf("[대조·명제 양끝] PG2 q1 %.3f · eff %+.3f · **Δ %+.3f** (낮은 q1 과 부호가 갈리는가)\n",
                          pg$q1, pg$eff, pg$delta))
cat("★자본 주장 없음 — 이 base 들은 t_base 가 낮다. **명제 시험이지 후보 발굴 아님**\n")
fwrite(R, file.path(OUT,"p15_low_q1.csv"))
write_json(list(verdict=verdict, results=R, n_sig=nrow(sig)),
           file.path(OUT,"p15_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
