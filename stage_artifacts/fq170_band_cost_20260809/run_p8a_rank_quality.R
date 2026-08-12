## P8a — 밴드 Δ 의 기전: base 순위 정보 품질 (직접 측정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P7a 에서 겹침 기각(0.20~0.22 동일한데 Δ 는 +0.845/+0.264/-0.293).
##  남은 가설: 밴드는 base 순위를 **불신하고 뒤집는 연산**이라, 순위가 정확한 base 에서 손해.
##  ★밴드 arm 의 실제 연산(mk 함수 원문): keep = 상위 13, added = 밴드적격 중 base 점수 상위 12,
##    dropped = 원래 14~25위. ⇒ Δ 는 **added vs dropped** 의 초과수익 차이로 분해된다.
##  측정 2종 (성과 백테 아님. 선택 집합의 forward 초과수익 진단):
##   (A) base 순위 프로파일: 랭크 구간 1-13 / 14-25 / 26-50 / 51-100 별 월평균 초과수익.
##       base 가 정보적이면 단조 감소. **swap 구간(14~50)의 기울기가 곧 교체 비용**.
##   (B) swap 분해: mean(added) - mean(dropped) 월별 시계열 + NW lag-3 t.
##  판정:
##   Z1 CONFIRMED: (B) 의 부호가 세 base 모두 PORT_t Δ 부호와 일치 ∧ (A) 기울기가 그 방향 설명
##   Z2 PARTIAL: (B) 부호는 맞으나 (A) 기울기로 설명 안 됨
##   Z3 REJECTED: (B) 부호가 PORT_t Δ 와 불일치 → 분해가 기전이 아님
##  ⚠(B)는 gross(비용 제외)라 크기는 PORT_t Δ 와 다르다 — **부호만** 대조한다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
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
U <- merge(U, bench, by="Date")
U[, exc := Ret_1m - BM_Ret]
have4 <- intersect(CORE4, names(U))
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U[complete.cases(U[, have4, with=FALSE]),
  core4 := rowMeans(scale(as.matrix(.SD)), na.rm=TRUE), by=Date, .SDcols=have4]
cat(sprintf("[입력 실측] 행 %d · 월 %d · 초과수익 결측 %d\n", nrow(U), uniqueN(U$Date), sum(is.na(U$exc))))

nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 24L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coef(m)[1] / sqrt(NeweyWest(m, lag=3L, prewhite=FALSE)[1,1])) }

analyze <- function(col, lab, delta_port) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]
  D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  # (A) 랭크 구간 프로파일
  prof <- D[, { o <- order(-get(col)); e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    .(r1_13=f(1,13), r14_25=f(14,25), r26_50=f(26,50), r51_100=f(51,100)) },
    by=Date, .SDcols=c("exc",col)]
  # (B) swap 분해 (mk 원문 승계)
  sw <- D[, { o <- order(-get(col)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]; e <- .SD$exc[o]
    keep <- seq_len(min(13L, .N)); drop_i <- if (.N >= 14L) 14:min(25L,.N) else integer(0)
    pool_i <- setdiff(which(qq %in% 3:4), keep); add_i <- head(pool_i, 12L)
    .(added = if (length(add_i)) mean(e[add_i]) else NA_real_,
      dropped = if (length(drop_i)) mean(e[drop_i]) else NA_real_,
      n_add = length(add_i)) }, by=Date, .SDcols=c("Ticker","q","exc",col)]
  sw[, d := added - dropped]
  data.table(base=lab, n_months=nrow(sw), delta_port=delta_port,
    r1_13 = round(mean(prof$r1_13,na.rm=TRUE)*1200,3), r14_25=round(mean(prof$r14_25,na.rm=TRUE)*1200,3),
    r26_50= round(mean(prof$r26_50,na.rm=TRUE)*1200,3), r51_100=round(mean(prof$r51_100,na.rm=TRUE)*1200,3),
    slope_14_50 = round((mean(prof$r26_50,na.rm=TRUE)-mean(prof$r14_25,na.rm=TRUE))*1200,3),
    swap_d_ann = round(mean(sw$d,na.rm=TRUE)*1200,3), swap_t = round(nw_t(sw$d),3),
    n_add_med = median(sw$n_add,na.rm=TRUE))
}
R <- rbindlist(list(analyze("M26_Revenue_Mom","mine(M26)", 0.845),
                    analyze("pg2","PG2 score_eff", 0.264),
                    analyze("core4","core4-EW", -0.293)))
cat("\n(A) base 순위 프로파일 — 랭크구간 연율 초과수익 %\n"); print(R[, .(base,r1_13,r14_25,r26_50,r51_100,slope_14_50)])
cat("\n(B) swap 분해 — added(밴드 12) - dropped(원래 14~25위), 연율 %\n")
print(R[, .(base, n_months, n_add_med, swap_d_ann, swap_t, delta_port)])

sign_match <- all(sign(R$swap_d_ann) == sign(R$delta_port))
slope_expl <- R[base=="core4-EW", slope_14_50] < R[base=="mine(M26)", slope_14_50]
verdict <- if (!sign_match) "Z3_DECOMPOSITION_NOT_MECHANISM" else if (slope_expl) "Z1_CONFIRMED" else "Z2_PARTIAL"
cat(sprintf("\n부호 일치(3/3): %s · core4 기울기가 mine 보다 가파름: %s\n판정: %s\n",
            sign_match, slope_expl, verdict))
cat("⚠(B)는 gross — 크기가 아니라 부호만 PORT_t Δ 와 대조\n")
write_json(list(verdict=verdict, sign_match=sign_match, slope_explains=slope_expl, results=R),
           file.path(OUT,"p8a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
fwrite(R, file.path(OUT,"p8a_rank_quality.csv"))
