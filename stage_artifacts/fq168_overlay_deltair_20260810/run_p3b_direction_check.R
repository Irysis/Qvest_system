## FQ-168 P3b — 전제 방향 확인: '스코어 하위 25% = long 기피' 가 맞는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  FQ-168 의 오버레이 설계는 **"within_sector_reversal 스코어 하위 25% 의 long 을 축소"** 다.
##  ⇒ 전제: **하위 25% 의 forward 초과수익이 음수**여야 한다. 아니면 설계가 반대가 된다.
##  ★오늘 D03 밴드 아크에서 **부호 확인이 결정적**이었다(상단/중간/역전형이 갈렸다). 착수 전에 잰다.
##  스코어 정의(사전 고정): reversal = **섹터 내에서 과거 1개월 수익의 역순위**
##    (과거 패자 = 높은 스코어). ⇒ **하위 25% = 섹터 내 최근 승자**.
##  PIT: 과거 1개월 수익은 t 시점 기지, forward 초과수익은 t→t+1. 섹터는 **해당 월 이하 최종 관측**.
##  판정:
##   B1_PREMISE_HOLDS : 하위 25% forward 초과수익이 **음수 ∧ |t|>=2** → 설계 방향 정상
##   B2_UNRESOLVED    : 부호는 음수이나 |t|<2 → 방향은 맞으나 근거 약함
##   B3_PREMISE_FLIPS : **양수 ∧ |t|>=2** → 전제가 틀렸다. 오버레이를 반대로 설계해야 함
##  ★상위 25% 도 함께 내 대칭성을 본다(한쪽만 보면 '분위 전체가 밀린' 것과 구별 못 함).
##  ★자본 주장 없음. 패널 산술(NW lag-3).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
cat(sprintf("[입력 실측] 월 수익 행 %d · 월 %d · 범위 %s~%s\n", nrow(ret), uniqueN(ret$Date),
            min(ret$Date), max(ret$Date)))

## 섹터: RAWDATA(일간)에서 (Ticker, 월) 최종 관측 — PIT 안전
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Sector")))
RD[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by = .(Ticker, ym), .SDcols = "Sector"]
cat(sprintf("[섹터] 일간 행 %d → (티커,월) %d · 고유 섹터 %d\n", nrow(RD), nrow(SEC), uniqueN(SEC$Sector)))
rm(RD); invisible(gc())

U <- copy(ret)[, ym := format(Date, "%Y-%m")]
U <- merge(U, SEC, by = c("Ticker","ym"), all.x = TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by = c("Date","Ticker"), all.x = TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by = "Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
U[, past_ret := shift(Ret_1m, 1L), by = Ticker]          # t 시점 기지 (직전월 실현)
W <- U[!is.na(past_ret) & !is.na(Sector) & !is.na(exc)]
W[, n_sec := .N, by = .(Date, Sector)]
W <- W[n_sec >= 5L]                                       # 섹터 내 순위가 의미 있으려면
W[, nmo := .N, by = Date]; W <- W[nmo >= 125L]
cat(sprintf("[유니버스] 행 %d · 월 %d · 섹터 결측 제외 후\n", nrow(W), uniqueN(W$Date)))

## reversal = 섹터 내 과거수익 **역순위** (과거 패자 = 높은 스코어)
W[, rev_score := 1 - (frank(past_ret, ties.method = "average") - 0.5)/.N, by = .(Date, Sector)]
W[, q4 := cut(frank(rev_score, ties.method="first"),
              breaks = quantile(seq_len(.N), probs = seq(0,1,0.25)),
              include.lowest = TRUE, labels = FALSE), by = Date]
nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 24L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3L, prewhite=FALSE)[1,1])) }
S <- W[, .(bot = mean(exc[q4 == 1L], na.rm = TRUE),   # 하위 25% = 섹터 내 최근 승자
           top = mean(exc[q4 == 4L], na.rm = TRUE),   # 상위 25% = 섹터 내 최근 패자
           all = mean(exc, na.rm = TRUE)), by = Date][order(Date)]
S[, bot_rel := bot - all][, top_rel := top - all]
f <- function(v, lab) cat(sprintf("  %-22s 연율 %+7.3f%%p · NW t %+6.3f\n", lab, mean(v,na.rm=TRUE)*1200, nw_t(v)))
cat(sprintf("\n=== 분위 forward 초과수익 (월 %d) ===\n", nrow(S)))
f(S$bot, "하위25%(최근 승자)"); f(S$top, "상위25%(최근 패자)"); f(S$all, "유니버스 평균")
cat("\n=== 유니버스 대비 상대 ===\n")
f(S$bot_rel, "하위25% − 전체"); f(S$top_rel, "상위25% − 전체")

bt <- nw_t(S$bot_rel); bm_ <- mean(S$bot_rel, na.rm = TRUE)
verdict <- if (is.finite(bt) && bm_ < 0 && abs(bt) >= 2) "B1_PREMISE_HOLDS" else
           if (is.finite(bt) && bm_ > 0 && abs(bt) >= 2) "B3_PREMISE_FLIPS" else "B2_UNRESOLVED"
## ★sprintf 형식 문자열의 `%` 는 `%%` 로 escape (초판이 '하위25%' 에서 실패 — 측정은 이미 끝난 뒤였다)
cat(sprintf("\n★1급(하위25%% 상대) = %+.3f%%p/yr · t %+.3f\n판정: %s\n", bm_*1200, bt, verdict))
if (verdict == "B3_PREMISE_FLIPS")
  cat("=> **전제가 틀렸다**. '하위 = long 기피' 가 아니라 반대다 — 오버레이를 반대로 설계해야 한다\n")
if (verdict == "B2_UNRESOLVED")
  cat("=> 방향 근거가 약하다. 오버레이 설계 전에 신호 정의를 재검토하거나 '방향 미확정' 을 사전등록할 것\n")
cat("⚠섹터는 (티커,월) 최종 관측 · reversal 은 과거 1개월 단순 역순위 — 정의를 바꾸면 재산출 필요\n")
fwrite(S, file.path(OUT, "p3b_quartiles.csv"))
write_json(list(verdict = verdict, n_months = nrow(S),
                bot_rel_annual_pct = bm_*1200, bot_rel_t = bt,
                top_rel_annual_pct = mean(S$top_rel,na.rm=TRUE)*1200, top_rel_t = nw_t(S$top_rel),
                bot_annual_pct = mean(S$bot,na.rm=TRUE)*1200, top_annual_pct = mean(S$top,na.rm=TRUE)*1200),
           file.path(OUT, "p3b_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
