## P8c — slope↔Δ 상관이 **공유항 아티팩트**인가 (내 P8a 주장에 대한 자기 적대검증)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  위험: slope = r26_50 - r14_25 이고 swap_d = added - dropped(≈r14_25),
##        PORT_t Δ = t_bd - t_nb 인데 t_nb 만 랭크 14~25 를 포함한다.
##        ⇒ **세 양이 모두 -r14_25 를 공유**한다. 그 구간의 **잡음만으로도** 양의 상관이 생긴다.
##        P8b spearman 0.740 이 여기서 왔다면 기전이 아니라 산술이다.
##  통제 = **분할 표본**: 예측자를 홀수달에서, 결과를 짝수달에서 재고 교차 상관을 본다.
##        잡음 기인이면 교차 상관은 붕괴한다(잡음은 달을 건너 전이되지 않음).
##        base 의 **지속적 구조 성질**이면 살아남는다.
##  경쟁 예측자도 같은 처리: base 강도 대용 r1_25(top-25 평균 초과수익).
##   A1_MECHANISM_SURVIVES : 양방향 교차 spearman >= 0.5 **그리고** 동일표본 값의 60% 이상 유지
##   A2_PARTIAL            : 한 방향만 >= 0.5
##   A3_SHARED_TERM_ARTIFACT: 양방향 모두 < 0.5 → P8a 기전 주장 철회, 상관은 산술
##  ★백테 없음(패널 산술만). 성과 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
B[, ym := format(Date, "%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date), "%Y-%m")]
ds <- sort(unique(B$Date)); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=CORE4), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
C4 <- rbindlist(acc, fill=TRUE)
U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, C4, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, A[!is.na(score_eff), .(ym, Ticker, pg2=score_eff)], by=c("ym","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
have4 <- intersect(CORE4, names(U))
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U[complete.cases(U[, have4, with=FALSE]),
  core4 := rowMeans(scale(as.matrix(.SD)), na.rm=TRUE), by=Date, .SDcols=have4]
allm <- sort(unique(U$Date)); ODD <- allm[seq(1, length(allm), by=2)]; EVN <- allm[seq(2, length(allm), by=2)]
cat(sprintf("[입력 실측] 행 %d · 월 %d (홀 %d / 짝 %d)\n", nrow(U), length(allm), length(ODD), length(EVN)))

## 월별 원자량: r1_25 / r14_25 / r26_50 / swap_d — 한 번만 계산하고 분할은 나중에 평균
per_month <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  D[, { o <- order(-get(col)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]; e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    keep <- seq_len(min(13L,n)); di <- if (n>=14L) 14:min(25L,n) else integer(0)
    ai <- head(setdiff(which(qq %in% 3:4), keep), 12L)
    .(r1_25=f(1,25), r14_25=f(14,25), r26_50=f(26,50),
      swap_d = if (length(ai) && length(di)) mean(e[ai]) - mean(e[di]) else NA_real_) },
    by=Date, .SDcols=c("Ticker","q","exc",col)]
}
BASES <- c("M26_Revenue_Mom","pg2","core4","D03_EWMA","Q01_EB","M01_PATHQ",
           "z_raw","z_neutral","C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
agg <- function(M, sel) { S <- M[Date %in% sel]
  list(slope = (mean(S$r26_50,na.rm=TRUE)-mean(S$r14_25,na.rm=TRUE))*1200,
       swap  = mean(S$swap_d,na.rm=TRUE)*1200,
       str   = mean(S$r1_25,na.rm=TRUE)*1200) }
rows <- list()
for (b in BASES) {
  M <- per_month(b); if (uniqueN(M$Date) < 60L) next
  o <- agg(M, ODD); e <- agg(M, EVN); a <- agg(M, allm)
  rows[[length(rows)+1L]] <- data.table(base=b, n=uniqueN(M$Date),
    slope_all=round(a$slope,3), swap_all=round(a$swap,3), str_all=round(a$str,3),
    slope_odd=o$slope, swap_evn=e$swap, str_odd=o$str,
    slope_evn=e$slope, swap_odd=o$swap, str_evn=e$str)
}
R <- rbindlist(rows)
sp <- function(x,y) suppressWarnings(cor(x, y, method="spearman"))
same   <- sp(R$slope_all, R$swap_all)
x_oe   <- sp(R$slope_odd, R$swap_evn)
x_eo   <- sp(R$slope_evn, R$swap_odd)
str_same <- sp(R$str_all, R$swap_all); str_oe <- sp(R$str_odd, R$swap_evn); str_eo <- sp(R$str_evn, R$swap_odd)
print(R[, .(base, n, slope_all, swap_all, str_all)])
cat(sprintf("\nn_base = %d\n", nrow(R)))
cat(sprintf("[slope]  동일표본 %.3f │ 교차 홀→짝 %.3f · 짝→홀 %.3f\n", same, x_oe, x_eo))
cat(sprintf("[강도 대용 r1_25] 동일표본 %.3f │ 교차 홀→짝 %.3f · 짝→홀 %.3f\n", str_same, str_oe, str_eo))
retain <- if (abs(same) > 1e-9) mean(c(x_oe, x_eo)) / same else NA_real_
cat(sprintf("교차 평균 / 동일표본 = %.3f (유지율)\n", retain))
verdict <- if (min(x_oe, x_eo) >= 0.5 && is.finite(retain) && retain >= 0.6) "A1_MECHANISM_SURVIVES" else
           if (max(x_oe, x_eo) >= 0.5) "A2_PARTIAL" else "A3_SHARED_TERM_ARTIFACT"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "A3_SHARED_TERM_ARTIFACT") cat("⇒ P8a 기전 주장 철회 필요: 상관은 공유항 산술\n")
fwrite(R, file.path(OUT,"p8c_split.csv"))
write_json(list(verdict=verdict, n_base=nrow(R), slope=list(same=same, odd_to_even=x_oe, even_to_odd=x_eo),
                strength=list(same=str_same, odd_to_even=str_oe, even_to_odd=str_eo),
                retention=retain, results=R),
           file.path(OUT,"p8c_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
