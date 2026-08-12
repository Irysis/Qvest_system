## P9a — 검정력을 갖춘 재측정: 밴드 Δ 를 base 만 보고 사전 판정할 수 있는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P8d: n=11 에서 임계 |rho|=0.602 라 4/4 전부 비유의. rho=0.45 검출에 **base 약 23개** 필요.
##  ⇒ 이번엔 base 를 factor DB 에서 **25종 이상** 뽑아 같은 설계를 다시 돌린다.
##  ★공유항 아티팩트 통제 유지 = **홀/짝 월 분할**(예측자 홀수달, 결과 짝수달, 양방향).
##  예측자 2종 head-to-head (동일 분할):
##    slope   = r26_50 - r14_25   (내 기전 가설: 밴드가 버리는 구간의 질)
##    strength= r1_25             (더 단순한 설명: 약한 base 보정)
##  결과량 swap_d = mean(added 12) - mean(dropped 14~25), 밴드 = D03 q∈{3,4}, keep 상위 13.
##  ★백테 없음(패널 산술). 성과·자본 주장 없음.
##  판정 (임계는 실제 n 에서 산출해 **먼저** 출력):
##   U1_SLOPE_ESTABLISHED : slope 양방향 |rho| >= 임계 (strength 여부 무관하게 보고)
##   U2_STRENGTH_ONLY     : strength 만 양방향 유의
##   U3_BOTH              : 둘 다 양방향 유의 → 공선성 경고와 함께 보고
##   U4_NEITHER           : 둘 다 미달 → 사전판정 규칙은 검정력 충족 후에도 미확립
##  ⚠n<23 이면 **판정하지 않고 중단**한다(P8d 를 반복하지 않기 위해).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))

## 1) 팩터 명부 — C15 준수(load_month_factors 경유). 중간 시점 한 달로 열거
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
cand <- sort(unique(probe$Factor_Name))
cat(sprintf("[명부] 후보 팩터 %d종\n", length(cand)))
set_seed_free <- cand[seq_len(min(40L, length(cand)))]   # 결정적 선택(무작위 아님)

## 2) 패널 적재
acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names = set_seed_free), silent = TRUE)
  if (inherits(z, "try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill = TRUE)
cat(sprintf("[적재] 행 %d · 월 %d · 열 %d\n", nrow(FD), uniqueN(FD$Date), ncol(FD)-2L))

U <- merge(B[, .(Date, Ticker, D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
cat(sprintf("[유니버스] 행 %d · 월 %d · 초과 결측 %d\n", nrow(U), uniqueN(U$Date), sum(is.na(U$exc))))
allm <- sort(unique(U$Date)); ODD <- allm[seq(1,length(allm),2)]; EVN <- allm[seq(2,length(allm),2)]

per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]
  D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) return(NULL)
  D[, { o <- order(-get(col)); qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r1_25=f(1,25), r14_25=f(14,25), r26_50=f(26,50),
      swap_d = if (length(ai) && length(di)) mean(e[ai]) - mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("q","exc",col)]
}
agg <- function(M, sel) { S <- M[Date %in% sel]
  list(slope=(mean(S$r26_50,na.rm=TRUE)-mean(S$r14_25,na.rm=TRUE))*1200,
       swap=mean(S$swap_d,na.rm=TRUE)*1200, str=mean(S$r1_25,na.rm=TRUE)*1200) }

bases <- setdiff(names(FD), c("Date","Ticker"))
rows <- list()
for (b in bases) {
  M <- per_month(b); if (is.null(M)) next
  o <- agg(M, ODD); e <- agg(M, EVN); a <- agg(M, allm)
  rows[[length(rows)+1L]] <- data.table(base=b, n_months=uniqueN(M$Date),
    slope_all=a$slope, swap_all=a$swap, str_all=a$str,
    slope_odd=o$slope, str_odd=o$str, swap_odd=o$swap,
    slope_evn=e$slope, str_evn=e$str, swap_evn=e$swap)
}
R <- rbindlist(rows, fill=TRUE)
R <- R[is.finite(slope_odd) & is.finite(slope_evn) & is.finite(swap_odd) & is.finite(swap_evn)]
n <- nrow(R)
tc <- qt(0.975, max(n-2,1)); rho_crit <- sqrt(tc^2/(tc^2 + max(n-2,1)))
cat(sprintf("\n★n_base = %d · spearman 양측5%% 임계 |rho| = %.3f (사전 산출)\n", n, rho_crit))
if (n < 23L) {
  cat("⇒ n < 23 — **판정 중단**(P8d 반복 방지). 팩터 후보를 늘려 재실행할 것.\n")
  write_json(list(verdict="ABORT_UNDERPOWERED", n_base=n, rho_crit=rho_crit),
             file.path(OUT,"p9a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
  quit(save="no")
}
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))
tab <- data.table(
  predictor=c("slope","slope","strength_r1_25","strength_r1_25"),
  direction=c("odd→even","even→odd","odd→even","even→odd"),
  rho=round(c(sp(R$slope_odd,R$swap_evn), sp(R$slope_evn,R$swap_odd),
              sp(R$str_odd,R$swap_evn),   sp(R$str_evn,R$swap_odd)),3))
tab[, sig := abs(rho) >= rho_crit]
same_slope <- sp(R$slope_all, R$swap_all); same_str <- sp(R$str_all, R$swap_all)
cat(sprintf("\n[동일표본 — 공유항 오염됨, 참고만] slope %.3f · strength %.3f\n", same_slope, same_str))
cat("\n[교차 분할 — 아티팩트 통제]\n"); print(tab)
sl_ok  <- all(tab[predictor=="slope", sig]); st_ok <- all(tab[predictor=="strength_r1_25", sig])
verdict <- if (sl_ok && st_ok) "U3_BOTH" else if (sl_ok) "U1_SLOPE_ESTABLISHED" else
           if (st_ok) "U2_STRENGTH_ONLY" else "U4_NEITHER"
cat(sprintf("\n판정: %s\n", verdict))
cat(sprintf("유지율: slope %.3f · strength %.3f (교차평균/동일표본)\n",
            mean(tab[predictor=="slope", rho])/same_slope,
            mean(tab[predictor=="strength_r1_25", rho])/same_str))
cat(sprintf("Δ 양수 base: %d / %d\n★자본 자격 주장 없음\n", sum(R$swap_all > 0), n))
fwrite(R, file.path(OUT,"p9a_bases.csv"))
write_json(list(verdict=verdict, n_base=n, rho_crit=rho_crit, cross=tab,
                same_sample=list(slope=same_slope, strength=same_str),
                n_positive_delta=sum(R$swap_all>0), results=R),
           file.path(OUT,"p9a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
