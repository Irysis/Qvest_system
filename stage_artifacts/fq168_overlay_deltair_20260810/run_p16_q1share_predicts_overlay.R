## P16 — 오늘 두 아크가 낸 명제 시험: **base 의 q1 비중이 높을수록 오버레이 Δ 가 나쁘다**
## 사전등록(측정 전 고정, 이 주석이 정본):
##  두 점 확보: PG2(q1 0.297) → 부호 반전(+4.295) · core4 → 밴드 Δ -0.293(FQ-170).
##  ⇒ 일반 명제: **선별 오버레이는 base 의 선호를 되돌린다**. 예측 = cor(q1 비중, 오버레이 효과) **음수**.
##  ★처리는 **하나로 고정**한다(reversal 오버레이) — FQ-170 의 D03 밴드와 섞으면 처리 혼합이다.
##  base = **정체로 정의된 계열 EW 합성**(성과 선택 없음) + CORE4_EW + M26 + PG2.
##  ★★오늘 배운 통제 2종을 사전에 박는다:
##   ①**계열 수 임계** — 이건 계열-간 상관이므로 n 이 아니라 **군집 수** 기준(cluster_power 계약)
##   ②**홀/짝 분할** — q1 비중과 오버레이 효과가 flagged 집합을 공유하므로 공유항 통제 필수
##  판정(1급 = 교차 분할 상관, 보수 임계):
##   M1_PROPOSITION_HOLDS : 양방향 음수 ∧ |rho| >= 보수임계
##   M2_UNRESOLVED        : 부호는 음수이나 미달
##   M3_REFUTED           : 양수 유의
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/cluster_power.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
B[, ym := format(Date,"%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date),"%Y-%m")]
NET <- fread(file.path(OUT,"../fq170_band_cost_20260809/p11c_net.csv"))
CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
need <- unique(c(NET$base, CORE4)); ds <- sort(unique(B$Date))
acc <- list()
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

U <- merge(B[, .(Date,Ticker,ym,M26_Revenue_Mom)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
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
fam_of <- function(x){f<-sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f)}
NET[, fam := fam_of(base)]
comps <- list()
for (f in unique(NET$fam)) { mem <- intersect(NET[fam==f, base], names(W)); if (length(mem)) comps[[paste0("FAM_",f)]] <- mem }
h4 <- intersect(CORE4, names(W)); if (length(h4)==4L) comps[["CORE4_EW"]] <- h4
allm <- sort(unique(W$Date)); ODD <- allm[seq(1,length(allm),2)]; EVN <- allm[seq(2,length(allm),2)]
one <- function(col, sel) {
  D <- W[Date %in% sel & is.finite(get(col))]
  D[, npg := .N, by=Date]; D <- D[npg >= 60L]
  D[, rk := frank(-get(col), ties.method="first"), by=Date]
  H <- D[rk <= 25L]
  if (uniqueN(H$Date) < 40L) return(NULL)
  S <- H[, .(q1 = mean(flagged), f = mean(exc[flagged],na.rm=TRUE), u = mean(exc[!flagged],na.rm=TRUE)), by=Date]
  S <- S[is.finite(f) & is.finite(u)]
  list(q1 = mean(S$q1, na.rm=TRUE), eff = mean(S$f - S$u, na.rm=TRUE)*1200)
}
rows <- list()
for (nm in c(names(comps), "PG2", "M26_Revenue_Mom")) {
  if (nm %in% names(comps)) { W[, .tmp := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=comps[[nm]]]; cc <- ".tmp" }
  else cc <- nm
  a <- one(cc, allm); o <- one(cc, ODD); e <- one(cc, EVN)
  if (".tmp" %in% names(W)) W[, .tmp := NULL]
  if (is.null(a) || is.null(o) || is.null(e)) next
  rows[[length(rows)+1L]] <- data.table(base=nm, q1_all=a$q1, eff_all=a$eff,
                                        q1_odd=o$q1, eff_evn=e$eff, q1_evn=e$q1, eff_odd=o$eff)
}
R <- rbindlist(rows, fill=TRUE)
n <- nrow(R); rc <- cp_critical_rho(n)
cat(sprintf("\n★n_base = %d · 계열-간 상관이므로 보수 임계 |rho| = **%.3f** (사전 산출)\n", n, rc))
print(R[order(-q1_all), .(base, q1=round(q1_all,3), eff=round(eff_all,3))])
r_same <- sp(R$q1_all, R$eff_all)
r_oe <- sp(R$q1_odd, R$eff_evn); r_eo <- sp(R$q1_evn, R$eff_odd)
cat(sprintf("\n[동일표본·오염] rho = %+.3f\n[교차 분할] 홀→짝 %+.3f · 짝→홀 %+.3f\n", r_same, r_oe, r_eo))
ok <- is.finite(r_oe) && is.finite(r_eo) && max(r_oe, r_eo) <= -rc
verdict <- if (ok) "M1_PROPOSITION_HOLDS" else
           if (is.finite(r_oe) && r_oe < 0 && r_eo < 0) "M2_UNRESOLVED" else
           if (min(r_oe, r_eo) >= rc) "M3_REFUTED" else "M2_UNRESOLVED"
cat(sprintf("\n판정: %s\n", verdict))
cat("⚠계열-간 상관이라 오늘 4회 미달한 설계 유형이다 — 미달 시 '명제 반증' 이 아니라 **해상도 아래**\n")
fwrite(R, file.path(OUT,"p16_q1_vs_effect.csv"))
write_json(list(verdict=verdict, n_base=n, rho_crit=rc, rho_same=r_same,
                rho_odd_even=r_oe, rho_even_odd=r_eo, results=R),
           file.path(OUT,"p16_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
