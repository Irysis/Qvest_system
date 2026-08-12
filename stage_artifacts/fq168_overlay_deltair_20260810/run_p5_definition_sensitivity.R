## FQ-168 P5 — 방향 확인이 **단일 정의의 산물인가** (P1 의 선행 조건)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P3b: reversal = '섹터 내 과거 **1개월** 수익 역순위' 로 하위25%−전체 = **-5.136%p/yr · t -3.224**.
##  ★내 P3 close_round 의 부활조건이 명시했다: "정의를 바꿨을 때 -5.136 이 무너지면
##    방향 확인 자체가 단일 정의 산물이므로 **P1 을 보류**한다." ⇒ P5 가 P1 보다 먼저다.
##  변형 4종(전부 사전 고정):
##   D1 과거 1개월 (P3b 재현 — **양성 대조**)
##   D2 과거 3개월 (누적)
##   D3 과거 1개월 · **Sector_Lv2**(더 세분)
##   D4 과거 1개월 · 섹터 내 **z-score**(순위 대신 크기 — 이상치 민감도 반대 방향)
##  판정(1급 = 하위25%−전체의 부호·유의):
##   E1_ROBUST  : 4/4 에서 음수 ∧ |t|>=2
##   E2_MOSTLY  : 3/4
##   E3_FRAGILE : <=2/4 → **P1 보류**, 방향 확인이 단일 정의 산물
##  ★양성 대조 D1 이 -5.136 을 재현 못 하면 파이프라인 문제이므로 수치 보고 중단.
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                 col_select = c("Date","Ticker","Sector","Sector_Lv2")))
RD[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by = .(Ticker, ym), .SDcols = c("Sector","Sector_Lv2")]
rm(RD); invisible(gc())
cat(sprintf("[섹터] (티커,월) %d · Lv1 %d종 · Lv2 %d종\n", nrow(SEC), uniqueN(SEC$Sector),
            uniqueN(SEC$Sector_Lv2)))

U <- copy(ret)[, ym := format(Date, "%Y-%m")]
U <- merge(U, SEC, by = c("Ticker","ym"), all.x = TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by = c("Date","Ticker"), all.x = TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by = "Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
U[, r1 := shift(Ret_1m, 1L), by = Ticker]
U[, r3 := shift(frollsum(Ret_1m, 3L), 1L), by = Ticker]   # 과거 3개월 누적(t 기지)
nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 24L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3L, prewhite=FALSE)[1,1])) }

run <- function(past_col, sec_col, mode, lab) {
  W <- U[is.finite(get(past_col)) & !is.na(get(sec_col)) & nzchar(get(sec_col)) & !is.na(exc)]
  W[, n_sec := .N, by = c("Date", sec_col)]; W <- W[n_sec >= 5L]
  W[, nmo := .N, by = Date]; W <- W[nmo >= 125L]
  if (!nrow(W)) return(NULL)
  if (mode == "rank")
    W[, sc := 1 - (frank(get(past_col), ties.method="average") - 0.5)/.N, by = c("Date", sec_col)]
  else
    W[, sc := { m <- mean(get(past_col), na.rm=TRUE); s <- sd(get(past_col), na.rm=TRUE)
                if (!is.finite(s) || s == 0) 0 else -(get(past_col) - m)/s }, by = c("Date", sec_col)]
  W[, q4 := cut(frank(sc, ties.method="first"),
                breaks = quantile(seq_len(.N), probs = seq(0,1,0.25)),
                include.lowest = TRUE, labels = FALSE), by = Date]
  S <- W[, .(bot = mean(exc[q4==1L], na.rm=TRUE), all = mean(exc, na.rm=TRUE)), by = Date][order(Date)]
  S[, rel := bot - all]
  data.table(def = lab, n_months = nrow(S), rel_ann = mean(S$rel, na.rm=TRUE)*1200, t = nw_t(S$rel))
}
R <- rbindlist(Filter(Negate(is.null), list(
  run("r1", "Sector",     "rank", "D1 1개월·Lv1·순위(대조)"),
  run("r3", "Sector",     "rank", "D2 3개월·Lv1·순위"),
  run("r1", "Sector_Lv2", "rank", "D3 1개월·Lv2·순위"),
  run("r1", "Sector",     "z",    "D4 1개월·Lv1·z-score"))))
R[, `:=`(rel_ann = round(rel_ann, 3), t = round(t, 3))]
print(R[])
ctl <- R[grepl("^D1", def)]
ok <- nrow(ctl) == 1L && abs(ctl$rel_ann - (-5.136)) <= 0.30
cat(sprintf("\n[양성대조] D1 = %+.3f / 정본 -5.136 → %s\n", ctl$rel_ann, ok))
if (!ok) { cat("=> 대조 실패 — 파이프라인 문제. 수치 보고 중단\n")
  write_json(list(verdict="CONTROL_FAILED", results=R), file.path(OUT,"p5_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
hits <- sum(R$rel_ann < 0 & abs(R$t) >= 2, na.rm = TRUE)
cat(sprintf("\n★음수 ∧ |t|>=2 : **%d / %d**\n", hits, nrow(R)))
verdict <- if (hits == nrow(R)) "E1_ROBUST" else if (hits >= nrow(R)-1L) "E2_MOSTLY" else "E3_FRAGILE"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "E3_FRAGILE") cat("=> **P1 보류** — 방향 확인이 단일 정의 산물이다\n")
if (verdict != "E3_FRAGILE") cat("=> P1 착수 가능. 사전등록에 **어느 정의를 쓰는지** 명시할 것\n")
fwrite(R, file.path(OUT, "p5_definitions.csv"))
write_json(list(verdict=verdict, control_ok=ok, n_hits=hits, n_defs=nrow(R), results=R),
           file.path(OUT, "p5_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
