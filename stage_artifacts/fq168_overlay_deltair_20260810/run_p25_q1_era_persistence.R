## P25 — q1 의 **시대-분할** 지속성: 계약이 스스로 '미검' 이라 선언한 유일한 축
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P24 는 q1 의 홀/짝 지속성을 확인했다(rho 0.981 · 군 Jaccard 0.800, 죽은 rel14 는 0.182).
##  ⚠그러나 홀/짝 교대는 **약한 시험**이다 — 인접 월이 같은 국면을 공유한다.
##    계약(`CP_OVERLAY_Q1_PERSISTENCE$caveat`)이 "시대-분할은 미검" 이라고 스스로 적어 두었다.
##  ⇒ 여기서 그 축을 닫는다. **q1 을 전반/후반 시대로 갈라** 같은 두 통계량을 잰다.
##  ★측정은 P16 파이프라인 그대로(재현) — 바뀌는 것은 **분할 방식뿐**(ODD/EVN → ERA1/ERA2).
##  ★사전 예상 기록: q1 은 base 의 **구성**이 정하는 평균 비중이므로 시대에도 안정할 것으로 예상.
##    그러나 유니버스·섹터 구성은 시대에 따라 변하므로 **홀/짝보다는 반드시 낮게** 나온다.
##    ⇒ 관건은 '높다/낮다'가 아니라 **판정(GO/CAUTION/NO_GO)이 시대 간 뒤집히는가**.
##  판정 (사전 고정):
##   K1_ERA_STABLE      : rho >= 0.7 ∧ 군 Jaccard >= 0.6 ∧ **GO<->NO_GO 횡단 0건**
##   K2_BAND_ABSORBS    : 횡단 0건이나 rho/Jaccard 중 하나 미달 → 밴드가 흡수, 한정 하에 계약 유지
##   K3_ERA_CONDITIONAL : **GO<->NO_GO 횡단 1건 이상** → 문턱은 시대-조건부. 계약에 era 필드 필수
##  ★자본 주장 없음. ★결과가 어느 쪽이든 계약에 반영한다(K3 면 오늘 발행한 계약을 내가 개정한다).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

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

## ★입력 실측 — 가정하지 않고 찍는다 (오늘 규약)
allm <- sort(unique(W$Date))
cat(sprintf("[입력 실측] 행 %s · 개월 %d · 범위 %s ~ %s\n",
            format(nrow(W), big.mark=","), length(allm),
            format(min(allm)), format(max(allm))))
gaps <- which(diff(as.integer(format(allm,"%Y"))*12 + as.integer(format(allm,"%m"))) != 1L)
cat(sprintf("[입력 실측] 내부 gap %d곳 · 이론 개월수 %d (실측/이론 %.3f)\n", length(gaps),
            as.integer(format(max(allm),"%Y"))*12 + as.integer(format(max(allm),"%m")) -
            (as.integer(format(min(allm),"%Y"))*12 + as.integer(format(min(allm),"%m"))) + 1L,
            length(allm) / (as.integer(format(max(allm),"%Y"))*12 + as.integer(format(max(allm),"%m")) -
            (as.integer(format(min(allm),"%Y"))*12 + as.integer(format(min(allm),"%m"))) + 1L)))
half <- ceiling(length(allm)/2)
E1 <- allm[seq_len(half)]; E2 <- allm[(half+1L):length(allm)]
cat(sprintf("[분할] ERA1 %d개월 %s~%s · ERA2 %d개월 %s~%s\n",
            length(E1), format(min(E1)), format(max(E1)),
            length(E2), format(min(E2)), format(max(E2))))

zs <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) rep(0,length(x)) else (x-m)/s}
fam_of <- function(x){f<-sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f)}
NET[, fam := fam_of(base)]
comps <- list()
for (f in unique(NET$fam)) { mem <- intersect(NET[fam==f, base], names(W)); if (length(mem)) comps[[paste0("FAM_",f)]] <- mem }
h4 <- intersect(CORE4, names(W)); if (length(h4)==4L) comps[["CORE4_EW"]] <- h4

one <- function(col, sel) {
  D <- W[Date %in% sel & is.finite(get(col))]
  D[, npg := .N, by=Date]; D <- D[npg >= 60L]
  D[, rk := frank(-get(col), ties.method="first"), by=Date]
  H <- D[rk <= 25L]
  if (uniqueN(H$Date) < 40L) return(NULL)
  S <- H[, .(q1 = mean(flagged)), by=Date]
  list(q1 = mean(S$q1, na.rm=TRUE), n = nrow(S))
}
rows <- list()
for (nm in c(names(comps), "PG2", "M26_Revenue_Mom")) {
  if (nm %in% names(comps)) { W[, .tmp := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=comps[[nm]]]; cc <- ".tmp" }
  else cc <- nm
  a <- one(cc, allm); e1 <- one(cc, E1); e2 <- one(cc, E2)
  if (".tmp" %in% names(W)) W[, .tmp := NULL]
  if (is.null(a) || is.null(e1) || is.null(e2)) next
  rows[[length(rows)+1L]] <- data.table(base=nm, q1_all=a$q1, q1_e1=e1$q1, q1_e2=e2$q1,
                                        n_e1=e1$n, n_e2=e2$n)
}
R <- rbindlist(rows, fill=TRUE)
cat(sprintf("\n[산출 실측] base %d (P24 의 22 와 대조)\n", nrow(R)))

vd <- function(q) ifelse(q >= 0.28, "NO_GO", ifelse(q >= 0.25, "CAUTION", "GO"))
R[, `:=`(v_all=vd(q1_all), v_e1=vd(q1_e1), v_e2=vd(q1_e2))]

rho <- suppressWarnings(cor(R$q1_e1, R$q1_e2, method="spearman"))
hi1 <- R[q1_e1 >= 0.25, base]; hi2 <- R[q1_e2 >= 0.25, base]
uni <- union(hi1,hi2); jac <- if (length(uni)) length(intersect(hi1,hi2))/length(uni) else NA_real_

cat("\n=== ① 연속량 지속성 (시대) ===\n")
cat(sprintf("  spearman(q1_ERA1, q1_ERA2) = **%+.3f**   (P24 홀/짝 +0.981 · 죽은 rel14 0.162/-0.070)\n", rho))
cat("\n=== ② 군 지속성 (문턱 >=0.25) ===\n")
cat(sprintf("  ERA1 %d · ERA2 %d · 교집합 %d → **Jaccard %.3f**  (P24 홀/짝 0.800 · rel14 0.182)\n",
            length(hi1), length(hi2), length(intersect(hi1,hi2)), jac))
cat("\n=== ③ ★판정 횡단 — 이게 1급이다 ===\n")
cross <- R[(v_e1=="GO" & v_e2=="NO_GO") | (v_e1=="NO_GO" & v_e2=="GO")]
flip  <- R[v_e1 != v_e2]
cat(sprintf("  판정 불일치 **%d/%d** · 그중 **GO<->NO_GO 횡단 %d건**\n", nrow(flip), nrow(R), nrow(cross)))
if (nrow(flip)) print(flip[, .(base, q1_e1=round(q1_e1,4), v_e1, q1_e2=round(q1_e2,4), v_e2, v_all)])
cat("\n  [근거 4점]\n")
print(R[base %in% c("FAM_L","FAM_CR","FAM_S","PG2"),
        .(base, q1_all=round(q1_all,4), v_all, q1_e1=round(q1_e1,4), v_e1, q1_e2=round(q1_e2,4), v_e2)])

verdict <- if (nrow(cross) > 0L) "K3_ERA_CONDITIONAL" else
           if (isTRUE(rho >= 0.7) && isTRUE(jac >= 0.6)) "K1_ERA_STABLE" else "K2_BAND_ABSORBS"
cat(sprintf("\n판정: **%s**  (rho %.3f · Jaccard %.3f · GO<->NO_GO 횡단 %d)\n", verdict, rho, jac, nrow(cross)))
fwrite(R, file.path(OUT,"p25_era.csv"))
write_json(list(verdict=verdict, n_base=nrow(R), n_e1=length(E1), n_e2=length(E2),
                era1=c(format(min(E1)),format(max(E1))), era2=c(format(min(E2)),format(max(E2))),
                rho_era=rho, jaccard_era=jac, n_flip=nrow(flip), n_cross_go_nogo=nrow(cross),
                oddeven_reference=list(rho=0.981, jaccard=0.800),
                rel14_reference=list(jaccard=0.182), flips=flip[, .(base,q1_e1,v_e1,q1_e2,v_e2)],
                results=R),
           file.path(OUT,"p25_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
cat(sprintf("\n=> %s\n", file.path(OUT,"p25_result.json")))
