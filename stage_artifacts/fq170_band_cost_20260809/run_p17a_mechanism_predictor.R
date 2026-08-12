## P17a — 기전 기반 예측자: base 만 보고 Δ 부호를 맞힐 수 있는가 (재도전)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  실패 이력: slope = r26_50 - r14_25 는 19계열 층화에서 교차 rho -0.108/+0.081 로 **실패**(P9c).
##  P16a 가 기전을 확정했다: **Δ 부호는 base 의 랭크 14~25 가 그 base 에게 얼마나 값진지가 정한다**
##    (core4 는 14~25 가 **자기 최고 구간** 8.875 > top-13 의 5.323 → Δ<0).
##  ⇒ 예측자 교체: slope 는 14~25 를 **26~50 하나와만** 비교했다. 새 예측자는
##    **base 자기 구간들 전체 안에서의 14~25 상대 위치**를 쓴다:
##      rel14 = (r14_25 - min(R)) / (max(R) - min(R)),  R = {r1_13, r14_25, r26_50, r51_100}
##    rel14 -> 1 이면 14~25 가 base 의 최고 구간(버리면 비쌈) → Δ 낮음 (**음의 상관 예측**)
##  ★공유항 통제: rel14 도 r14_25 를 담고 Δ 도 -r14_25 를 담는다 ⇒ **홀/짝 분할 필수**
##    (예측자 홀수달, 결과 짝수달, 양방향). 분할 후 남는 것은 **지속적 base 성질**이며
##    그것이 곧 기전 주장이다 — '독립 정보' 주장이 아님을 명시한다.
##  결과량 = swap_d (P11a 에서 PORT_t Δ 와 spearman 0.988·부호 10/10 로 번역 확인됨).
##  표본 = P9c 의 19계열 층화 52 팩터 (성과 선택 없음).
##  판정 (임계 사전 산출):
##   F1_PREDICTS : 양방향 rho <= -임계 (예측 부호와 일치) → 사전판정 처음 성립
##   F2_WRONG_SIGN : 양방향 유의하나 부호가 반대 → 기전 서술 재검토
##   F3_FAILS    : 미달 → slope 와 마찬가지로 실패. 예측은 원리적으로 어렵다는 결론
##  ★백테 없음(패널 산술). 자본 주장 없음. 비교 기준선 = slope 교차 -0.108/+0.081.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))
crit <- function(n){ tc <- qt(0.975, max(n-2,1)); sqrt(tc^2/(tc^2+max(n-2,1))) }

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
SEL <- fread(file.path(OUT, "p11c_net.csv"))$base
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
allm <- sort(unique(U$Date)); ODD <- allm[seq(1,length(allm),2)]; EVN <- allm[seq(2,length(allm),2)]
cat(sprintf("[입력 실측] 행 %d · 월 %d (홀 %d/짝 %d) · base 후보 %d\n",
            nrow(U), length(allm), length(ODD), length(EVN), length(SEL)))
per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) return(NULL)
  D[, { o <- order(-get(col)); qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r1_13=f(1,13), r14_25=f(14,25), r26_50=f(26,50), r51_100=f(51,100),
      swap_d = if (length(ai) && length(di)) mean(e[ai])-mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("q","exc",col)]
}
agg <- function(M, s) { S <- M[Date %in% s]
  R4 <- c(mean(S$r1_13,na.rm=TRUE), mean(S$r14_25,na.rm=TRUE),
          mean(S$r26_50,na.rm=TRUE), mean(S$r51_100,na.rm=TRUE))
  rng <- max(R4,na.rm=TRUE) - min(R4,na.rm=TRUE)
  list(rel14 = if (is.finite(rng) && rng > 0) (R4[2]-min(R4,na.rm=TRUE))/rng else NA_real_,
       slope = (R4[3]-R4[2])*1200,
       swap  = mean(S$swap_d,na.rm=TRUE)*1200) }
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  M <- per_month(b); if (is.null(M)) next
  o <- agg(M,ODD); e <- agg(M,EVN); a <- agg(M,allm)
  rows[[length(rows)+1L]] <- data.table(base=b, rel14_all=a$rel14, swap_all=a$swap,
    rel14_odd=o$rel14, rel14_evn=e$rel14, slope_odd=o$slope, slope_evn=e$slope,
    swap_odd=o$swap, swap_evn=e$swap)
}
R <- rbindlist(rows, fill=TRUE)
R <- R[is.finite(rel14_odd) & is.finite(rel14_evn) & is.finite(swap_odd) & is.finite(swap_evn)]
n <- nrow(R); rc <- crit(n)
cat(sprintf("\n★n_base = %d · 임계 |rho| = %.3f (사전 산출)\n", n, rc))
tab <- data.table(
  predictor = c("rel14(신규)","rel14(신규)","slope(구·기준선)","slope(구·기준선)"),
  direction = c("홀→짝","짝→홀","홀→짝","짝→홀"),
  rho = round(c(sp(R$rel14_odd,R$swap_evn), sp(R$rel14_evn,R$swap_odd),
                sp(R$slope_odd,R$swap_evn), sp(R$slope_evn,R$swap_odd)), 3))
tab[, sig := abs(rho) >= rc]
cat("\n[교차 분할 — 공유항 통제]\n"); print(tab)
cat(sprintf("\n동일표본(오염됨·참고): rel14 %.3f · slope %.3f\n",
            sp(R$rel14_all,R$swap_all), NA_real_))
rel_ok <- all(tab[predictor=="rel14(신규)", sig])
rel_sign_ok <- all(tab[predictor=="rel14(신규)", rho] < 0)
verdict <- if (rel_ok && rel_sign_ok) "F1_PREDICTS" else
           if (rel_ok && !rel_sign_ok) "F2_WRONG_SIGN" else "F3_FAILS"
cat(sprintf("\n판정: %s\n", verdict))
cat(sprintf("예측 부호(음) 일치: %s · 양방향 유의: %s\n", rel_sign_ok, rel_ok))
cat("⚠분할 후 남는 것은 **지속적 base 성질**이다 — '독립 정보' 주장이 아니라 기전 주장이다\n")
fwrite(R, file.path(OUT,"p17a_predictor.csv"))
write_json(list(verdict=verdict, n_base=n, rho_crit=rc, cross=tab,
                rel_significant=rel_ok, rel_sign_negative=rel_sign_ok, results=R),
           file.path(OUT,"p17a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
