## w2 — ⓑ 국면-적응성 측정 (선별 재구성 + 양성 대조로 검증)
## w1 결과: ⓐ경제적 동조 **미지지**(spearman −0.139~+0.103, 전부 |0.3| 미만). ⓑ만 남았다.
## ★`canonical_screen_bt` 는 holdings 를 산출하지 않는다(스크리닝 헬퍼 설계) — PG2 결손과 무관한 계약 공백.
##   ⇒ 선별을 직접 재구성하되 **계약의 period_returns 를 재현하는지 양성 대조**로 검증한 뒤 쓴다.
##   (다른 경로로 재면 비교가 성립하지 않는다 — 오늘 반복 확인한 규율)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[w2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]

## ── 선별 재구성: 월별 score 상위 25 (계약과 동일 규칙) ──────────────────────
pick <- function(S, N = 25L) S[order(Date, -score), .SD[seq_len(min(N, .N))], by = Date][, .(Date, Ticker)]
say("=== ★양성 대조: 재구성 선별이 계약 period_returns 를 재현하는가 ===")
r <- suppressWarnings(canonical_screen_bt(SC, rt, bd, top_n=25L, cost_bps_oneway=15,
      run_id="W", strategy_id="W", diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)]))
PRc <- as.data.table(r$period_returns)[, .(date, ret_net)]
H <- pick(SC)
say("  재구성 보유 %d행 · %d개월 · 월평균 %.1f종목", nrow(H), uniqueN(H$Date), nrow(H)/uniqueN(H$Date))
## 재구성 EW 수익 (비용 제외 gross — 계약의 ret_gross 와 비교)
G <- merge(H, rt, by = c("Date","Ticker"))[, .(rec = mean(Ret_1m)), by = Date]
PRg <- as.data.table(r$period_returns)
gcol <- if ("ret_gross" %in% names(PRg)) "ret_gross" else "ret_net"
CMP <- merge(G[, .(date = Date, rec)], PRg[, .(date, con = get(gcol))], by = "date")
say("  비교 %d개월 · 상관 **%.6f** · 평균절대차 %.6f · 최대절대차 %.6f (계약 컬럼 %s)",
    nrow(CMP), cor(CMP$rec, CMP$con), mean(abs(CMP$rec-CMP$con)), max(abs(CMP$rec-CMP$con)), gcol)
okrec <- cor(CMP$rec, CMP$con) > 0.99
say("  ⇒ %s", if (okrec) "★재구성 검증 통과 — 이 보유 집합을 쓸 수 있다" else
  "★★재구성이 계약과 어긋난다 — 유동성 필터/동점 처리 차이. 적응성 측정을 이 경로로 하면 안 됨")
if (!okrec) { say("=== 중단 ==="); quit(status=0) }

## ── ⓑ 국면-적응성 ───────────────────────────────────────────────────────────
say("=== ⓑ 계약 슬리브의 국면-적응성 ===")
H[, m := mi(Date) + 2L]; HH <- merge(H, LB, by = "m")
sN <- unique(HH[on==TRUE, Ticker]); sF <- unique(HH[on==FALSE, Ticker])
jac_all <- length(intersect(sN,sF))/max(length(union(sN,sF)),1L)
say("  ON 고유 %d · OFF 고유 %d · 교집합 %d · **집합 Jaccard %.3f**",
    length(sN), length(sF), length(intersect(sN,sF)), jac_all)
adj <- function(D) {
  D <- D[order(m)]; ms <- sort(unique(D$m))
  o <- vapply(seq_along(ms)[-1], function(i) {
    a <- D[m==ms[i-1], Ticker]; b <- D[m==ms[i], Ticker]
    length(intersect(a,b))/max(length(union(a,b)),1L) }, numeric(1))
  s <- vapply(seq_along(ms)[-1], function(i)
    as.integer(unique(D[m==ms[i], on]) != unique(D[m==ms[i-1], on])), integer(1))
  c(keep = mean(o[s==0], na.rm=TRUE), switch = mean(o[s==1], na.rm=TRUE),
    n_keep = sum(s==0), n_switch = sum(s==1))
}
a1 <- adj(HH)
say("  월간 인접 Jaccard: 국면 유지 **%.3f**(n %d) · 국면 전환 **%.3f**(n %d) · 차 %+.3f",
    a1["keep"], a1["n_keep"], a1["switch"], a1["n_switch"], a1["switch"]-a1["keep"])

say("=== 대조: 다른 재료 4종 (계약만 적응적인가) ===")
A <- readRDS(file.path(OUT,"factor_long.rds"))
TB <- fread(file.path(OUT,"c6_full_table.csv"))
FS <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
say("  %-26s %10s %10s %10s", "factor", "집합Jac", "유지Jac", "전환Jac")
rows <- list(data.table(factor="계약(계약)", set_jac=jac_all, keep=a1["keep"], swi=a1["switch"]))
for (f in FS) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% SC$Date]
  if (!nrow(S)) next
  Hf <- pick(S)[, m := mi(Date) + 2L]
  Hf <- merge(Hf, LB, by="m"); if (!nrow(Hf)) next
  n1 <- unique(Hf[on==TRUE, Ticker]); f1 <- unique(Hf[on==FALSE, Ticker])
  a2 <- adj(Hf)
  sj <- length(intersect(n1,f1))/max(length(union(n1,f1)),1L)
  say("  %-26s %10.3f %10.3f %10.3f", substr(f,1,26), sj, a2["keep"], a2["switch"])
  rows[[length(rows)+1L]] <- data.table(factor=f, set_jac=sj, keep=a2["keep"], swi=a2["switch"])
}
say("  %-26s %10.3f %10.3f %10.3f", "★계약", jac_all, a1["keep"], a1["switch"])
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
oth <- R[factor != "계약(계약)" & factor != "계약"]
say("  계약 집합Jac %.3f vs 타재료 중앙 %.3f → %s", jac_all, median(oth$set_jac, na.rm=TRUE),
    if (jac_all < min(oth$set_jac, na.rm=TRUE)) "★계약이 가장 적응적" else "구분 안 됨")
say("  계약 전환Jac %.3f vs 타재료 중앙 %.3f", a1["switch"], median(oth$swi, na.rm=TRUE))
say("  ⇒ %s", if (jac_all < min(oth$set_jac, na.rm=TRUE))
  "★국면-적응성이 계약 특이성의 후보로 남는다" else
  "★★적응성으로도 설명 안 됨 — ⓐ·ⓑ 모두 기각. 계약 특이성은 **미해명 상태로 등재**한다")
fwrite(R, file.path(OUT,"w2_adaptivity.csv"))
say("=== w2 완료 ===")
