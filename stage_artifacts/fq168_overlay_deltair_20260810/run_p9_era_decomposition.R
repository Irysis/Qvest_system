## FQ-168 P9 — -5.136 을 만든 구간은 무엇이었나 (초기 구간 분해)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P6: 공통 창 235m(1999-12~)에서 8셀 전부 무의미. 원 창 335m 에서만 -5.136(t -3.224).
##  ⇒ **차집합(≈1990~1999)이 효과를 만들었다**. 그 구간이 무엇인지 본다.
##  질문 2개: ①그 구간의 효과 크기·유의 ②그 구간이 **구조적으로 다른가**(재현 가능성 판단 재료)
##  구조 지표(사전 고정): 월 종목수 · 유동성 필터 통과율 · 섹터 수 · 월 횡단면 수익 sd
##  판정:
##   G1_ERA_CARRIES : 초기 구간 rel 이 강한 음수(|t|>=2) ∧ 공통창 대비 크게 큼 → 구간 특정
##   G2_SIMILAR     : 초기 ≈ 공통 → 차이는 창 길이(검정력)였지 구간 성질이 아니다
##   G3_MIXED       : 그 사이
##  ★구조가 크게 다르면(종목수·유동성) **재현 불가 구조**로 라우팅, 비슷하면 **post-decay** 계통.
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by = .(Ticker, ym), .SDcols = "Sector"]
rm(RD); invisible(gc())

RAW <- copy(ret)[, ym := format(Date, "%Y-%m")]
RAW <- merge(RAW, SEC, by = c("Ticker","ym"), all.x = TRUE)
RAW <- merge(RAW, liq[, .(Date,Ticker,adv)], by = c("Date","Ticker"), all.x = TRUE)
## 유동성 통과율은 **필터 전** 기준으로 재야 의미가 있다
STRUCT <- RAW[!is.na(Sector) & nzchar(Sector), .(
  n_stock = .N, liq_pass = mean(is.na(adv) | adv >= 2e8), n_sec = uniqueN(Sector),
  xs_sd = sd(Ret_1m, na.rm = TRUE)), by = Date][order(Date)]

U <- RAW[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by = "Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
U[, r1 := shift(Ret_1m, 1L), by = Ticker]
W <- U[is.finite(r1) & !is.na(Sector) & nzchar(Sector) & !is.na(exc)]
W[, n_sec := .N, by = .(Date, Sector)]; W <- W[n_sec >= 5L]
W[, nmo := .N, by = Date]; W <- W[nmo >= 125L]
W[, sc := 1 - (frank(r1, ties.method="average") - 0.5)/.N, by = .(Date, Sector)]
W[, q4 := cut(frank(sc, ties.method="first"), breaks = quantile(seq_len(.N), probs=seq(0,1,0.25)),
              include.lowest = TRUE, labels = FALSE), by = Date]
S <- W[, .(bot = mean(exc[q4==1L], na.rm=TRUE), all = mean(exc, na.rm=TRUE)), by = Date][order(Date)]
S[, rel := bot - all]
CUT <- as.Date("1999-12-01")
nw_t <- function(x){ x <- x[is.finite(x)]; if (length(x) < 20L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3L, prewhite=FALSE)[1,1])) }
seg <- function(d, lab) { s <- S[eval(d)]
  data.table(era = lab, n = nrow(s), rel_ann = round(mean(s$rel,na.rm=TRUE)*1200,3), t = round(nw_t(s$rel),3)) }
R <- rbindlist(list(seg(quote(Date <  CUT), "초기 (~1999-11)"),
                    seg(quote(Date >= CUT), "이후 (1999-12~)"),
                    seg(quote(rep(TRUE,.N)), "전체")))
cat("\n=== 구간별 하위25%−전체 ===\n"); print(R[])

cat("\n=== 구조 지표 (중앙값) ===\n")
ST <- rbindlist(list(
  STRUCT[Date <  CUT, .(era="초기", n_month=.N, n_stock=round(median(n_stock)), liq_pass=round(median(liq_pass),3),
                        n_sec=round(median(n_sec)), xs_sd=round(median(xs_sd),4))],
  STRUCT[Date >= CUT, .(era="이후", n_month=.N, n_stock=round(median(n_stock)), liq_pass=round(median(liq_pass),3),
                        n_sec=round(median(n_sec)), xs_sd=round(median(xs_sd),4))]))
print(ST[])

e1 <- R[era == "초기 (~1999-11)"]; e2 <- R[era == "이후 (1999-12~)"]
carries <- is.finite(e1$t) && e1$rel_ann < 0 && abs(e1$t) >= 2 && abs(e1$rel_ann) > 1.5*abs(e2$rel_ann)
similar <- is.finite(e1$rel_ann) && abs(e1$rel_ann - e2$rel_ann) < 1.5
verdict <- if (carries) "G1_ERA_CARRIES" else if (similar) "G2_SIMILAR" else "G3_MIXED"
cat(sprintf("\n판정: %s\n", verdict))
sd_ratio <- ST[era=="초기", xs_sd] / ST[era=="이후", xs_sd]
stock_ratio <- ST[era=="초기", n_stock] / ST[era=="이후", n_stock]
cat(sprintf("구조 차이: 종목수 %.2fx · 횡단면 sd %.2fx · 유동성통과 %.3f→%.3f\n",
            stock_ratio, sd_ratio, ST[era=="초기", liq_pass], ST[era=="이후", liq_pass]))
if (carries && (sd_ratio > 1.3 || stock_ratio < 0.7))
  cat("=> 초기 구간이 효과를 만들었고 **구조도 크게 다르다** ⇒ 재현 불가 구조 쪽. FQ-168 폐기 근거\n")
if (carries && !(sd_ratio > 1.3 || stock_ratio < 0.7))
  cat("=> 초기가 효과를 만들었으나 구조는 비슷 ⇒ **post-decay 계통**(M26/FAM_C 와 같은 축)\n")
fwrite(R, file.path(OUT, "p9_eras.csv")); fwrite(ST, file.path(OUT, "p9_struct.csv"))
write_json(list(verdict=verdict, eras=R, structure=ST,
                sd_ratio=sd_ratio, stock_ratio=stock_ratio),
           file.path(OUT, "p9_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
