## FQ-168 P2 — ΔIR 대신 **패널 산술**로 오버레이 기여를 잰다 (고분해능 경로)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P0: ΔIR 문턱 0.05 는 **1.05se** ⇒ '통과' 판정 원리적 불가. 2se 최소 검출 0.0955.
##  ⇒ 결과량을 바꾼다. 오버레이의 본질은 "**PG2 보유 중 어떤 종목을 줄이는가**" 이므로,
##     **축소 대상 종목의 forward 초과수익**을 월별 시계열로 재면 검정력이 훨씬 높다.
##     (P11a 가 패널→PORT_t 번역 spearman 0.988 로 확인 — 패널 경로는 계약 언어로 옮겨진다)
##  ★**선행 확인(이 라운드 안에서)**: 신호가 **PG2 보유에서 발화하기는 하는가**.
##    PG2 top-25 에 하위25% reversal 종목이 거의 없으면 오버레이는 **무효**다(효과 이전에 발화 문제).
##  측정:
##   ①월별 발화 수(top-25 중 flagged 개수) 분포
##   ②flagged 보유 vs unflagged 보유의 forward 초과수익 차 · NW lag-3 t
##  판정:
##   J1_FIRES_AND_WORKS : 월중앙 발화 >=2 ∧ 차이 음수 ∧ |t|>=2 → 오버레이 기여 실재
##   J2_FIRES_NO_EFFECT : 발화는 충분하나 차이 미달
##   J3_INERT           : 월중앙 발화 <2 → **오버레이가 거의 발화하지 않는다**
##  ★base 명시: PG2 = alpha_scores score_eff top-25(유동성 필터). incumbent 정체는 book_state 참조.
##  ★자본 주장 없음. reversal 정의는 P11 이 유효로 남긴 **1개월·Lv1** 좌표 고정.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date), "%Y-%m")]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by=.(Ticker, ym), .SDcols="Sector"]
rm(RD); invisible(gc())

U <- copy(ret)[, ym := format(Date, "%Y-%m")]
U <- merge(U, SEC, by=c("Ticker","ym"), all.x=TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
U <- merge(U, A[!is.na(score_eff), .(ym, Ticker, pg2 = score_eff)], by=c("ym","Ticker"), all.x=TRUE)
setorder(U, Ticker, Date)
U[, r1 := shift(Ret_1m, 1L), by = Ticker]
W <- U[is.finite(r1) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]
W[, nm := .N, by=Date]; W <- W[nm >= 125L]
## P11 이 유효로 남긴 좌표: 1개월 · Lv1
W[, sc := 1 - (frank(r1, ties.method="average") - 0.5)/.N, by=.(Date,Sector)]
W[, q4 := cut(frank(sc, ties.method="first"), breaks=quantile(seq_len(.N), probs=seq(0,1,0.25)),
              include.lowest=TRUE, labels=FALSE), by=Date]
W[, flagged := q4 == 1L]                       # 하위25% = 축소 대상
## PG2 보유 = score_eff top-25
H <- W[!is.na(pg2)]
H[, n_pg2 := .N, by=Date]; H <- H[n_pg2 >= 60L]
H[, rk := frank(-pg2, ties.method="first"), by=Date]
HOLD <- H[rk <= 25L]
cat(sprintf("[입력 실측] PG2 점수 보유 월 %d · top-25 행 %d\n", uniqueN(HOLD$Date), nrow(HOLD)))

## ① 발화 확인
FIRE <- HOLD[, .(n_hold = .N, n_flag = sum(flagged)), by=Date][order(Date)]
cat(sprintf("\n=== ① 발화 ===\n  월중앙 flagged %d / %d · 분포 p10 %d · p90 %d · 발화 0인 달 %d (%.1f%%)\n",
            median(FIRE$n_flag), median(FIRE$n_hold),
            quantile(FIRE$n_flag, .1), quantile(FIRE$n_flag, .9),
            sum(FIRE$n_flag == 0), 100*mean(FIRE$n_flag == 0)))
nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<20L) return(NA_real_)
  m<-lm(x~1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m,lag=3L,prewhite=FALSE)[1,1]))}
## ② flagged vs unflagged (보유 내부)
S <- HOLD[, .(f = mean(exc[flagged], na.rm=TRUE), u = mean(exc[!flagged], na.rm=TRUE),
              nf = sum(flagged)), by=Date][order(Date)]
S <- S[nf >= 1L & is.finite(f) & is.finite(u)]
S[, d := f - u]
cat(sprintf("\n=== ② 보유 내부 대비 (flagged 있는 %d개월) ===\n", nrow(S)))
cat(sprintf("  flagged   연율 %+7.3f%%p\n  unflagged 연율 %+7.3f%%p\n  **차이 %+7.3f%%p · NW t %+6.3f**\n",
            mean(S$f,na.rm=TRUE)*1200, mean(S$u,na.rm=TRUE)*1200,
            mean(S$d,na.rm=TRUE)*1200, nw_t(S$d)))
md <- mean(S$d, na.rm=TRUE)*1200; td <- nw_t(S$d); mf <- median(FIRE$n_flag)
verdict <- if (mf < 2) "J3_INERT" else if (is.finite(td) && md < 0 && abs(td) >= 2) "J1_FIRES_AND_WORKS" else "J2_FIRES_NO_EFFECT"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "J3_INERT") cat("=> **오버레이가 거의 발화하지 않는다** — 효과 이전에 발화 문제. ΔIR 라운드는 무의미\n")
if (verdict == "J1_FIRES_AND_WORKS") cat("=> 축소 대상이 실제로 열위 — 오버레이 기여 실재(패널 근거). ΔIR 없이도 주장 가능\n")
if (verdict == "J2_FIRES_NO_EFFECT") cat("=> 발화는 하나 보유 내부에서는 구별 안 됨 — **유니버스 전체 효과가 PG2 보유에는 안 남는다**\n")
cat("⚠보유 내부 대비다 — 유니버스 전체(-4.143)와 다른 질문이며, PG2 선별이 이미 걸러냈을 수 있다\n")
fwrite(S, file.path(OUT,"p2_holdings.csv"))
write_json(list(verdict=verdict, n_months=nrow(S), median_flag=mf,
                zero_fire_pct=100*mean(FIRE$n_flag==0),
                flagged_ann=mean(S$f,na.rm=TRUE)*1200, unflagged_ann=mean(S$u,na.rm=TRUE)*1200,
                diff_ann=md, diff_t=td),
           file.path(OUT,"p2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
