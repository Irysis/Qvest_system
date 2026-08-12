## P9c — 계열 층화 재측정: P9a 의 40 base 가 2계열(AC/C)뿐이라 유효 n 이 부풀었다
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P9a: 교차 rho 0.390/0.381, 전체 n=40 임계 0.312 → 유의. 그러나 P9b 에서 **계열 2종**으로 판명.
##  ⇒ 331 후보를 **계열당 최대 3종**으로 층화 추출해 계열 다양성을 확보하고 같은 설계를 재측정.
##  통제 유지: 홀/짝 월 분할(예측자 홀수달, 결과 짝수달, 양방향) — 공유항 -r14_25 아티팩트.
##  추가 보고: **계열별 교차 rho** (한 계열이 끌고 가는지, 여러 계열에서 재현되는지)
##  판정 (임계는 실제 n 과 계열수 둘 다로 산출해 먼저 출력):
##   W1_REPLICATES : 전체 교차 양방향 유의 ∧ **계열수 기준 보수 임계도 통과**
##   W2_FULL_ONLY  : 전체 기준만 유의(계열 기준 미달) → 다양성은 확보됐으나 보수적으로는 미확립
##   W3_FAILS      : 전체 기준도 미달 → P9a 는 계열 군집 아티팩트였다
##  ★백테 없음. 성과·자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))
crit <- function(n) { tc <- qt(0.975, max(n-2,1)); sqrt(tc^2/(tc^2+max(n-2,1))) }

## (0) 선행 데이터로 계열 내 교차 재현 먼저 (값싼 사전 확인)
PA <- fread(file.path(OUT,"p9a_bases.csv"))
PA[, fam := sub("^([A-Za-z]+)[0-9_].*$", "\\1", base)]
cat("=== P9a 데이터의 계열 내 교차 rho (공유항 통제됨) ===\n")
for (f in unique(PA$fam)) { S <- PA[fam==f]
  cat(sprintf("  %-3s n=%2d · 홀→짝 %+.3f · 짝→홀 %+.3f · 임계 %.3f\n", f, nrow(S),
              sp(S$slope_odd,S$swap_evn), sp(S$slope_evn,S$swap_odd), crit(nrow(S)))) }

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
cand <- sort(unique(probe$Factor_Name))
fam_of <- function(x) { f <- sub("^([A-Za-z]+)[0-9_].*$", "\\1", x); ifelse(f == x, substr(x,1,3), f) }
CD <- data.table(base=cand, fam=fam_of(cand))
sel <- CD[, head(.SD, 3L), by=fam]$base          # 계열당 최대 3종 — 결정적
cat(sprintf("\n[층화] 후보 %d종 · 계열 %d종 → 선택 %d종\n", nrow(CD), uniqueN(CD$fam), length(sel)))

acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=sel), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]; if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill=TRUE)
U <- merge(B[, .(Date,Ticker,D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]; U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
cat(sprintf("[유니버스] 행 %d · 월 %d\n", nrow(U), uniqueN(U$Date)))
allm <- sort(unique(U$Date)); ODD <- allm[seq(1,length(allm),2)]; EVN <- allm[seq(2,length(allm),2)]
per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) return(NULL)
  D[, { o <- order(-get(col)); qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r14_25=f(14,25), r26_50=f(26,50), r1_25=f(1,25),
      swap_d = if (length(ai) && length(di)) mean(e[ai])-mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("q","exc",col)]
}
agg <- function(M,s){ S <- M[Date %in% s]
  list(sl=(mean(S$r26_50,na.rm=TRUE)-mean(S$r14_25,na.rm=TRUE))*1200,
       sw=mean(S$swap_d,na.rm=TRUE)*1200, st=mean(S$r1_25,na.rm=TRUE)*1200) }
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  M <- per_month(b); if (is.null(M)) next
  o <- agg(M,ODD); e <- agg(M,EVN); a <- agg(M,allm)
  rows[[length(rows)+1L]] <- data.table(base=b, fam=fam_of(b),
    slope_all=a$sl, swap_all=a$sw, str_all=a$st,
    slope_odd=o$sl, swap_odd=o$sw, str_odd=o$st,
    slope_evn=e$sl, swap_evn=e$sw, str_evn=e$st)
}
R <- rbindlist(rows, fill=TRUE)
R <- R[is.finite(slope_odd)&is.finite(slope_evn)&is.finite(swap_odd)&is.finite(swap_evn)]
n <- nrow(R); nf <- uniqueN(R$fam)
cat(sprintf("\n★n_base=%d · 계열 %d종 · 임계 @n=%.3f · 보수임계 @계열수=%.3f (사전 산출)\n",
            n, nf, crit(n), crit(nf)))
print(R[, .N, by=fam][order(-N)])
r_oe <- sp(R$slope_odd,R$swap_evn); r_eo <- sp(R$slope_evn,R$swap_odd)
s_oe <- sp(R$str_odd,R$swap_evn);   s_eo <- sp(R$str_evn,R$swap_odd)
cat(sprintf("\n[교차] slope %+.3f / %+.3f · strength %+.3f / %+.3f\n", r_oe, r_eo, s_oe, s_eo))
full_ok <- min(abs(r_oe),abs(r_eo)) >= crit(n); cons_ok <- min(abs(r_oe),abs(r_eo)) >= crit(nf)
cat(sprintf("전체기준 통과 %s · 보수(계열수)기준 통과 %s\n", full_ok, cons_ok))
BF <- R[, .(n=.N, oe=round(sp(slope_odd,swap_evn),3), eo=round(sp(slope_evn,swap_odd),3)), by=fam][n>=4][order(-n)]
cat("\n=== 계열별 교차 (n>=4) ===\n"); print(BF)
cat(sprintf("계열별 양방향 부호 양수 비율: %.2f (%d/%d 계열)\n",
            mean(BF$oe>0 & BF$eo>0), sum(BF$oe>0 & BF$eo>0), nrow(BF)))
verdict <- if (full_ok && cons_ok) "W1_REPLICATES" else if (full_ok) "W2_FULL_ONLY" else "W3_FAILS"
cat(sprintf("\n판정: %s\nΔ 양수 base: %d/%d\n★자본 자격 주장 없음\n", verdict, sum(R$swap_all>0), n))
fwrite(R, file.path(OUT,"p9c_bases.csv"))
write_json(list(verdict=verdict, n_base=n, n_fam=nf, crit_full=crit(n), crit_fam=crit(nf),
                slope=list(oe=r_oe, eo=r_eo), strength=list(oe=s_oe, eo=s_eo),
                by_family=BF, results=R), file.path(OUT,"p9c_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
