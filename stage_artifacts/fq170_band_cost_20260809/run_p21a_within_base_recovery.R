## P21a — 회수 가설을 **base-내부 시계열**로 재질문 (계열 수 제약 우회)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P19b/P20a 는 **계열-간 상관** 설계였고 계열 수(선언 15, 표본 12~14)가 묶어서 두 번 다 미달했다.
##  ★반면 **base-내부** 설계(순열 통제 P15c/P16a)는 4/4 로 깨끗하게 결론이 났다 — 계열 수를 안 쓰기 때문.
##  ⇒ 같은 가설을 내부 형태로 바꾼다: **한 base 안에서** 그 base 가 약할 때 밴드 기여가 큰가.
##    회귀: swap_d_t ~ str_lag_t   (base 마다 독립, 월 관측 ~230개 → 군집 제약 없음)
##      swap_d_t  = 그 달 밴드 기여(added 12 − dropped 14~25)
##      str_lag_t = 그 base 의 **직전 36개월** top-25 초과수익 평균(PIT: shift(1) 적용)
##    예측: 계수 **음수**(base 가 약할수록 밴드 기여 큼).
##  1급 = **개별 base 에서 유의(|t_NW3| > 2)한 음의 계수 비율**.
##   R1_RECOVERY : >= 50%  → 회수 기전 확립(개별 base 수준에서)
##   R2_WEAK     : 20~50%
##   R3_NO       : < 20%   → 내부 설계로도 안 잡힘. 회수 서사 종결
##  ★귀무 대조 의무: **양의 유의 비율**도 함께 낸다. 둘이 비슷하면 잡음이지 신호가 아니다
##    (귀무에선 양쪽 꼬리 각 ~2.5%).
##  ★백테 없음(패널 산술). 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date)); SEL <- fread(file.path(OUT,"p11c_net.csv"))$base
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
cat(sprintf("[입력 실측] 행 %d · 월 %d · base %d\n", nrow(U), uniqueN(U$Date), length(SEL)))

per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 150L) return(NULL)
  M <- D[, { o <- order(-get(col)); qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r1_25=f(1,25), swap_d = if (length(ai) && length(di)) mean(e[ai])-mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("q","exc",col)]
  setorder(M, Date); M
}
nwt <- function(fit) { v <- tryCatch(NeweyWest(fit, lag=3L, prewhite=FALSE), error=function(e) NULL)
  if (is.null(v)) return(NA_real_); as.numeric(coef(fit)[2] / sqrt(v[2,2])) }
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  M <- per_month(b); if (is.null(M)) next
  ## PIT: 직전 36개월 강도(현재월 제외) — shift(1) 후 rolling mean
  M[, str_lag := frollmean(shift(r1_25, 1L), 36L, align="right")]
  W <- M[is.finite(swap_d) & is.finite(str_lag)]
  if (nrow(W) < 120L) next
  fit <- lm(swap_d ~ str_lag, data = W)
  t_nw <- nwt(fit)
  rows[[length(rows)+1L]] <- data.table(base=b, n_obs=nrow(W),
    beta=round(as.numeric(coef(fit)[2]),4), t_nw=round(t_nw,3),
    sig_neg = isTRUE(t_nw < -2), sig_pos = isTRUE(t_nw > 2))
}
R <- rbindlist(rows, fill=TRUE)
n <- nrow(R)
cat(sprintf("\n★base %d · 평균 월 관측 %.0f (군집 제약 없음 — base 내부 시계열)\n", n, mean(R$n_obs)))
cat(sprintf("  계수 음수 %d/%d (%.1f%%) · **유의 음수 %d (%.1f%%)** · 유의 양수 %d (%.1f%%)\n",
            sum(R$beta<0), n, 100*mean(R$beta<0),
            sum(R$sig_neg), 100*mean(R$sig_neg), sum(R$sig_pos), 100*mean(R$sig_pos)))
cat(sprintf("  ★귀무 대조: 양쪽 꼬리 각 ~2.5%% 기대 — 음 %.1f%% vs 양 %.1f%%\n",
            100*mean(R$sig_neg), 100*mean(R$sig_pos)))
cat("\n=== 유의 음수 상위 6 ===\n"); print(head(R[sig_neg == TRUE][order(t_nw), .(base, n_obs, beta, t_nw)], 6))
if (any(R$sig_pos)) { cat("\n=== 유의 양수 (반대 방향) ===\n"); print(head(R[sig_pos == TRUE][order(-t_nw), .(base, n_obs, beta, t_nw)], 6)) }
frac <- mean(R$sig_neg)
verdict <- if (frac >= 0.50) "R1_RECOVERY" else if (frac >= 0.20) "R2_WEAK" else "R3_NO"
cat(sprintf("\n판정: %s (유의 음수 %.1f%%)\n", verdict, 100*frac))
cat("⚠개별 base 수준 결론이다 — base 간 pooling 은 여전히 계열 수에 묶인다(그래서 안 한다)\n★자본 주장 없음\n")
fwrite(R, file.path(OUT,"p21a_within.csv"))
write_json(list(verdict=verdict, n_base=n, mean_obs=mean(R$n_obs),
                frac_neg=mean(R$beta<0), frac_sig_neg=frac, frac_sig_pos=mean(R$sig_pos),
                results=R), file.path(OUT,"p21a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
