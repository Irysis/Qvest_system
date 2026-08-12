## FQ-168 P14 — '이미 반영' 인가 '조건부로 사라짐' 인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P2: PG2 보유 내부에서 flagged(하위25% reversal)가 +15.880 vs unflagged +11.585 (부호 반대).
##  두 기전이 가능하다:
##   (A) **이미 반영** — PG2 가 flagged 종목을 **덜 담는다**(q1 비중 < 25%) ⇒ 자를 게 적다
##   (B) **조건부 소멸** — PG2 가 균등/과대 담는데도 그 안에선 열위가 아니다 ⇒ 선별이 성질을 바꾼다
##  ★P2 실측이 이미 힌트: 월중앙 flagged **7/25 = 28%** ⇒ 균등(25%)보다 **높다** ⇒ (B) 쪽.
##  여기서 정밀 확인한다: 월별 q1~q4 비중 + 균등 대비 검정.
##  판정:
##   K1_ALREADY_ABSORBED : q1 비중이 25% 를 **유의하게 하회**
##   K2_UNIFORM          : 25% 근방(유의차 없음)
##   K3_OVERWEIGHT       : 25% 를 **유의하게 상회** → PG2 는 오히려 flagged 를 더 담는다
##  ★자본 주장 없음. 좌표는 P11 유효분(1개월·Lv1) 고정.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date), "%Y-%m")]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by=.(Ticker, ym), .SDcols="Sector"]
rm(RD); invisible(gc())
U <- copy(ret)[, ym := format(Date,"%Y-%m")]
U <- merge(U, SEC, by=c("Ticker","ym"), all.x=TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
U <- merge(U, A[!is.na(score_eff), .(ym, Ticker, pg2=score_eff)], by=c("ym","Ticker"), all.x=TRUE)
setorder(U, Ticker, Date); U[, r1 := shift(Ret_1m,1L), by=Ticker]
W <- U[is.finite(r1) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
W[, ns := .N, by=.(Date,Sector)]; W <- W[ns >= 5L]
W[, nm := .N, by=Date]; W <- W[nm >= 125L]
W[, sc := 1 - (frank(r1, ties.method="average") - 0.5)/.N, by=.(Date,Sector)]
W[, q4 := cut(frank(sc, ties.method="first"), breaks=quantile(seq_len(.N), probs=seq(0,1,0.25)),
              include.lowest=TRUE, labels=FALSE), by=Date]
H <- W[!is.na(pg2)]; H[, npg := .N, by=Date]; H <- H[npg >= 60L]
H[, rk := frank(-pg2, ties.method="first"), by=Date]
HOLD <- H[rk <= 25L]
S <- HOLD[, .(n = .N,
              s1 = mean(q4==1L), s2 = mean(q4==2L), s3 = mean(q4==3L), s4 = mean(q4==4L)),
          by=Date][order(Date)]
cat(sprintf("[입력 실측] 월 %d · 월평균 보유 %.1f\n", nrow(S), mean(S$n)))
cat("\n=== PG2 top-25 의 reversal 분위 비중 (균등 = 0.250) ===\n")
for (k in 1:4) {
  v <- S[[paste0("s",k)]]
  tt <- t.test(v, mu = 0.25)
  cat(sprintf("  q%d(%s) 평균 **%.3f** · 균등 대비 t %+6.3f · p %.4f\n", k,
              c("하위=최근승자","","","상위=최근패자")[k], mean(v), as.numeric(tt$statistic), tt$p.value))
}
v1 <- S$s1; t1 <- t.test(v1, mu = 0.25)
m1 <- mean(v1); tv <- as.numeric(t1$statistic); pv <- t1$p.value
verdict <- if (pv >= 0.05) "K2_UNIFORM" else if (m1 < 0.25) "K1_ALREADY_ABSORBED" else "K3_OVERWEIGHT"
cat(sprintf("\n★q1(자를 대상) 비중 = **%.3f** (균등 0.250) · t %+.3f · p %.4f\n판정: %s\n",
            m1, tv, pv, verdict))
if (verdict == "K1_ALREADY_ABSORBED")
  cat("=> PG2 가 flagged 를 **덜 담는다** ⇒ '이미 반영'. 오버레이는 자를 게 적다\n")
if (verdict == "K3_OVERWEIGHT")
  cat("=> PG2 가 flagged 를 **더 담는데도** 그 안에선 열위가 아니다 ⇒ **선별이 성질을 바꾼다**.\n",
      "   '자를 게 없다' 가 아니라 **'자르면 안 된다'** 가 정확한 서술\n")
if (verdict == "K2_UNIFORM")
  cat("=> 균등하게 담는다 ⇒ 노출은 정상인데 **효과만 조건부로 사라진다**\n")
fwrite(S, file.path(OUT,"p14_shares.csv"))
write_json(list(verdict=verdict, n_months=nrow(S), q1_share=m1, q1_t=tv, q1_p=pv,
                shares=list(q1=mean(S$s1), q2=mean(S$s2), q3=mean(S$s3), q4=mean(S$s4))),
           file.path(OUT,"p14_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
