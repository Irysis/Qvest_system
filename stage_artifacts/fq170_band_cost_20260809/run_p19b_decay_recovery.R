## P19b — 밴드는 감쇠한 재료의 **회수 도구**인가 (P15b 예측의 직접 검정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P15b 실측: FAM_C Δ 전반 +0.431 → 후반 **+0.875** · FAM_M +0.665 → +0.414.
##  전자는 '감쇠한 시대에 밴드 기여가 더 크다' 를 시사하고 후자는 반대다 ⇒ **n=2 로는 무정보**.
##  ⇒ 52 base(19계열, 성과 선택 없음)로 확대해 **쌍체 비교**한다.
##  측정(패널 산술, 백테 없음): 각 base 의 swap_d 를 전반/후반 각각 산출.
##    d_i = swap_late_i − swap_early_i  (같은 base 의 쌍체차 — 두 시대는 disjoint 라 잡음 독립)
##    decay_i = strength_early_i − strength_late_i  (r1_25 기준, 감쇠 크기)
##  ★검정력 먼저(오늘 반복 확인된 규약): n=52 와 **계열수 19**(군집 보수) 양쪽으로 임계를 산출해
##    **측정 전에 출력**한다. 계열 기준으로도 볼 수 있는 효과만 주장한다.
##  판정:
##   H1_RECOVERY : mean(d) > 0 유의(쌍체) **그리고** cor(d, decay) > 0 유의 → 회수 도구
##   H2_ERA_ONLY : mean(d) > 0 유의이나 decay 상관 미달 → 시대 효과이지 회수 기전 아님
##   H3_NO       : mean(d) 미달 → 후반 우위는 FAM_C 개별 사례
##  ★자본 주장 없음. swap_d 는 PORT_t Δ 와 spearman 0.988 로 번역 확인(P11a)되었으나 크기 환산 금지.
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
NET <- fread(file.path(OUT, "p11c_net.csv")); SEL <- NET$base
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
cat(sprintf("[입력 실측] 행 %d · 월 %d (전반 %d %s~%s / 후반 %d %s~%s)\n", nrow(U), length(allm),
            length(EARLY), min(EARLY), max(EARLY), length(LATE), min(LATE), max(LATE)))
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
fam_of <- function(x){ f <- sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f) }
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  M <- per_month(b); if (is.null(M)) next
  E <- M[Date %in% EARLY]; L <- M[Date %in% LATE]
  if (nrow(E) < 60L || nrow(L) < 60L) next
  rows[[length(rows)+1L]] <- data.table(base=b, fam=fam_of(b),
    swap_early = mean(E$swap_d, na.rm=TRUE)*1200, swap_late = mean(L$swap_d, na.rm=TRUE)*1200,
    str_early  = mean(E$r1_25,  na.rm=TRUE)*1200, str_late  = mean(L$r1_25,  na.rm=TRUE)*1200)
}
R <- rbindlist(rows, fill=TRUE)
R[, d := swap_late - swap_early][, decay := str_early - str_late]
R <- R[is.finite(d) & is.finite(decay)]
n <- nrow(R); nf <- uniqueN(R$fam)
cat(sprintf("\n★검정력 사전 산출: n=%d(계열 %d) · spearman 임계 전체 %.3f · **계열수 기준 %.3f**\n",
            n, nf, crit_r(n), crit_r(nf)))
tt <- t.test(R$d)
cat(sprintf("  쌍체 mean(d) 검정: 필요 |t| 2.0 · 실측 t %.3f (n=%d)\n", as.numeric(tt$statistic), n))

cat(sprintf("\n=== 시대별 밴드 기여 (연율 %%p) ===\n"))
cat(sprintf("  전반 중앙 %.3f · 후반 중앙 %.3f · **쌍체차 중앙 %+.3f**\n",
            median(R$swap_early), median(R$swap_late), median(R$d)))
cat(sprintf("  후반이 더 큰 base: %d/%d (%.1f%%)\n", sum(R$d > 0), n, 100*mean(R$d > 0)))
cat(sprintf("  쌍체 t = %.3f · p = %.4f · 95%%CI [%.3f, %.3f]\n",
            as.numeric(tt$statistic), tt$p.value, tt$conf.int[1], tt$conf.int[2]))
cat(sprintf("\n=== 재료 감쇠 (str_early - str_late) ===\n"))
cat(sprintf("  중앙 %.3f · 감쇠(>0)한 base %d/%d\n", median(R$decay), sum(R$decay > 0), n))
rho <- sp(R$d, R$decay)
cat(sprintf("  ★cor(밴드 기여 증가, 재료 감쇠) spearman = **%.3f** (임계 전체 %.3f · 계열 %.3f)\n",
            rho, crit_r(n), crit_r(nf)))
BF <- R[, .(n=.N, med_d=round(median(d),3), med_decay=round(median(decay),3)), by=fam][order(-med_d)]
cat("\n=== 계열별 쌍체차 ===\n"); print(head(BF, 8))
mean_ok <- tt$p.value < 0.05 && as.numeric(tt$estimate) > 0
rho_ok  <- is.finite(rho) && rho >= crit_r(nf)     # 보수(계열수) 기준
verdict <- if (mean_ok && rho_ok) "H1_RECOVERY" else if (mean_ok) "H2_ERA_ONLY" else "H3_NO"
cat(sprintf("\n판정: %s\n  mean(d)>0 유의 %s · decay 상관이 **계열 기준** 임계 통과 %s\n",
            verdict, mean_ok, rho_ok))
cat("⚠계열 군집으로 유효 n 은 52 아닌 ~19 — 상관은 보수 임계로 판정했다\n★자본 주장 없음\n")
fwrite(R, file.path(OUT,"p19b_decay.csv"))
write_json(list(verdict=verdict, n_base=n, n_fam=nf, crit_full=crit_r(n), crit_fam=crit_r(nf),
                paired_t=as.numeric(tt$statistic), paired_p=tt$p.value,
                median_d=median(R$d), frac_late_larger=mean(R$d>0),
                rho_d_decay=rho, by_family=BF, results=R),
           file.path(OUT,"p19b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
