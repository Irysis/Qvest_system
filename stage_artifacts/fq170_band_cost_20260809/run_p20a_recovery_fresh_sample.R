## P20a — 회수 상관을 **새 표본에서 1급으로** 사전등록 재질문
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P19b 에서 1급(쌍체 mean(d)>0)은 반대로 떨어졌고(-3.039), 2급으로 `cor(d, decay)` spearman
##  **+0.500**(보수 임계 0.456 통과)이 나왔다. 그러나 이는 **사후 2급**이라 판정 근거가 아니다.
##  ⇒ **이번에 안 쓴 팩터**로 표본을 갈고, 그 상관을 **1급으로 사전 선언**해 다시 묻는다.
##  ★1급(이번 판정의 유일 근거): spearman(d, decay) 가 **양수 ∧ 계열수 기준 보수 임계 이상**
##      d = swap_late − swap_early · decay = str_early − str_late (P19b 와 동일 정의)
##  2급(참고·판정 아님): 쌍체 mean(d) — P19b 에서 음수였으므로 재현 여부만 본다.
##  표본: 331 후보 − P19b 의 52종 = 미사용. 계열당 최대 3종 **층화**(P9c 와 동일 절차, 성과 선택 없음).
##  ★검정력 착수 전 산출·출력. 계열수 < 8 이면 **판정 중단**(군집 과소).
##  판정:
##   K1_REPLICATES : 1급 통과(양수 ∧ 보수임계 이상) → '감쇠 재료 회수' 처음 확립
##   K2_WRONG_SIGN : 유의하나 음수 → 서사 반전
##   K3_FAILS      : 미달 → P19b 의 0.500 은 사후 우연으로 닫힘
##  ★백테 없음(패널 산술). 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))
crit_r <- function(n){ tc <- qt(0.975, max(n-2,1)); sqrt(tc^2/(tc^2+max(n-2,1))) }

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
fam_of <- function(x){ f <- sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f) }
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
ALL <- sort(unique(probe$Factor_Name)); OLD <- fread(file.path(OUT,"p11c_net.csv"))$base
CD <- data.table(base = setdiff(ALL, OLD)); CD[, fam := fam_of(base)]
SEL <- CD[, head(.SD, 3L), by=fam]$base
cat(sprintf("[표본 교체] 전체 %d − 기존 %d = 미사용 %d → 층화 선택 **%d종 / 계열 %d**\n",
            length(ALL), length(OLD), nrow(CD), length(SEL), uniqueN(CD[base %in% SEL, fam])))

acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=SEL), silent=TRUE)
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
allm <- sort(unique(U$Date)); half <- floor(length(allm)/2)
EARLY <- allm[seq_len(half)]; LATE <- allm[(half+1L):length(allm)]
per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) return(NULL)
  D[, { o <- order(-get(col)); qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r1_25=f(1,25), swap_d = if (length(ai) && length(di)) mean(e[ai])-mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("q","exc",col)]
}
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  M <- per_month(b); if (is.null(M)) next
  E <- M[Date %in% EARLY]; L <- M[Date %in% LATE]
  if (nrow(E) < 60L || nrow(L) < 60L) next
  rows[[length(rows)+1L]] <- data.table(base=b, fam=fam_of(b),
    swap_early=mean(E$swap_d,na.rm=TRUE)*1200, swap_late=mean(L$swap_d,na.rm=TRUE)*1200,
    str_early=mean(E$r1_25,na.rm=TRUE)*1200,  str_late=mean(L$r1_25,na.rm=TRUE)*1200)
}
R <- rbindlist(rows, fill=TRUE)
R[, d := swap_late - swap_early][, decay := str_early - str_late]
R <- R[is.finite(d) & is.finite(decay)]
n <- nrow(R); nf <- uniqueN(R$fam)
cat(sprintf("\n★검정력(착수 전 산출): n=%d · 계열 %d · 임계 전체 %.3f · **보수(계열) %.3f**\n",
            n, nf, crit_r(n), crit_r(nf)))
if (nf < 8L) { cat("⇒ 계열 < 8 — **판정 중단**(군집 과소)\n")
  write_json(list(verdict="ABORT_TOO_CLUSTERED", n_base=n, n_fam=nf),
             file.path(OUT,"p20a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
rho <- sp(R$d, R$decay); tt <- t.test(R$d)
cat(sprintf("\n[1급] spearman(d, decay) = **%.3f**  (양수 ∧ >= %.3f 이어야 통과)\n", rho, crit_r(nf)))
cat(sprintf("[2급·참고] 쌍체 mean(d) = %.3f · t = %.3f · p = %.4f · 후반우위 %d/%d\n",
            mean(R$d), as.numeric(tt$statistic), tt$p.value, sum(R$d>0), n))
cat(sprintf("  감쇠(decay>0) base %d/%d · 감쇠 중앙 %.3f\n", sum(R$decay>0), n, median(R$decay)))
cat(sprintf("  밴드 기여 전반 중앙 %.3f → 후반 %.3f\n", median(R$swap_early), median(R$swap_late)))
BF <- R[, .(n=.N, med_d=round(median(d),3)), by=fam][order(-med_d)]
cat("\n=== 계열별 쌍체차 (상위/하위 4) ===\n"); print(rbind(head(BF,4), tail(BF,4)))
pass <- is.finite(rho) && rho >= crit_r(nf)
verdict <- if (pass) "K1_REPLICATES" else if (is.finite(rho) && rho <= -crit_r(nf)) "K2_WRONG_SIGN" else "K3_FAILS"
cat(sprintf("\n판정: %s\n", verdict))
cat(sprintf("(대조) P19b 원표본 1급 상관 = +0.500 · 이번 새 표본 = %.3f\n", rho))
cat("★자본 주장 없음 · 패널 산술\n")
fwrite(R, file.path(OUT,"p20a_fresh.csv"))
write_json(list(verdict=verdict, n_base=n, n_fam=nf, crit_full=crit_r(n), crit_fam=crit_r(nf),
                rho_primary=rho, prior_rho=0.500, paired_mean=mean(R$d),
                paired_t=as.numeric(tt$statistic), paired_p=tt$p.value,
                frac_late_larger=mean(R$d>0), by_family=BF),
           file.path(OUT,"p20a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
