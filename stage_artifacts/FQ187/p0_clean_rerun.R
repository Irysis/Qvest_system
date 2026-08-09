## FQ-187 P0 — ★오염 제거 위에서 전 결론 재검 + 생존 실(깊이 단조성) 정면 검증
## 도훈 지시 2026-08-09 "집요하게 더 검증해봐"
##
## 3중 정제 (사전 고정):
##   C1 2026 전체 제외 (벤치 sd/종목중앙 sd 2.15배 = 계열 고유 결함)
##   C2 벤치-종목 괴리 상위 오염일 제거 (gap > p99 = 0.0468)
##   C3 1% 윈저화
## 1급 판정량 = **Bowley 왜도**(적률 아님 — 적률은 FQ-182 에서 단일일 99.3% 지배로 실격)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ187")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/moment_fragility.R")

D <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ182/p0.rds"))$D)[order(Date)]
G <- fread(file.path(ROOT, "stage_artifacts/FQ182/p5_bench_stock_gap.csv"))
G[, Date := as.Date(Date)]
D <- merge(D, G[, .(Date, gap)], by = "Date", all.x = TRUE)
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1) & !is.na(dd252)]
say("=== 입력 실측 === 원본 %d일 · %s ~ %s", nrow(D), min(D$Date), max(D$Date))

p99 <- quantile(G$gap, 0.99, na.rm = TRUE)
say("  gap p99 = %.4f · gap 결측 %d일", p99, sum(is.na(D$gap)))

## ---- 정제 단계별 표본 ---------------------------------------------------------
mk <- function(lab, dt) list(lab = lab, dt = dt)
S <- list(
  mk("R0 원본",              D),
  mk("C1 2026 제외",         D[Date < as.Date("2026-01-01")]),
  mk("C1+C2 오염일 제거",    D[Date < as.Date("2026-01-01") & (is.na(gap) | gap <= p99)]),
  mk("C2 단독(2026 포함)",   D[is.na(gap) | gap <= p99])
)
say("=== 정제 단계별 표본 ===")
for (s in S) say("  %-20s %d일 (%.1f%%) · %s ~ %s", s$lab, nrow(s$dt),
                 100*nrow(s$dt)/nrow(D), min(s$dt$Date), max(s$dt$Date))

wins <- function(x, p = 0.01) { q <- quantile(x, c(p, 1-p), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }
skew_m3 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}

set.seed(20260809)
bb_stat <- function(x, on, f, B = 400L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk); st <- seq_len(max(1, n-blk+1)); o <- numeric(0)
  for (b in seq_len(B)) {
    idx <- as.integer(unlist(lapply(sample(st, nb, TRUE), function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 40 || sum(!ob) < 40) next
    o <- c(o, f(xb[ob]) - f(xb[!ob]))
  }
  o
}

## ---- ①1급 = Bowley (사전 고정) · ②적률 대조 · ③tail_asym(원 사전등록 1급) ----
tail_asym <- function(v) mean(v >= 0.03) - mean(v <= -0.03)
bow <- function(v) robust_skew(v)$bowley
oct <- function(v) robust_skew(v)$octile

say("=== ★정제 × 문턱 × 통계량 전수 ===")
rows <- list()
for (s in S) for (thr in c(-0.10, -0.20, -0.30)) {
  dt <- s$dt; on <- dt$dd252 <= thr
  if (sum(on) < 80 || sum(!on) < 200) { say("  %s thr %.0f%% : 표본 부족(ON %d) — 기록", s$lab, thr*100, sum(on)); next }
  x <- dt$fwd1; xw <- wins(x)
  for (nm in c("bowley","octile","m3","m3_winsor","tail_asym")) {
    f <- switch(nm, bowley = bow, octile = oct, m3 = skew_m3,
                m3_winsor = function(v) skew_m3(wins(v)), tail_asym = tail_asym)
    d <- f(x[on]) - f(x[!on])
    bo <- bb_stat(x, on, f)
    se <- if (length(bo) > 20) sd(bo) else NA_real_
    rows[[length(rows)+1L]] <- data.table(clean = s$lab, thr = thr*100, stat = nm,
      on = f(x[on]), off = f(x[!on]), diff = d, se = se, ratio = abs(d)/(2*se), n_on = sum(on))
  }
}
R <- rbindlist(rows)
say("--- 1급(Bowley) ---")
print(R[stat == "bowley", .(clean, thr, on = round(on,4), off = round(off,4),
                            diff = round(diff,4), ratio = round(ratio,3), n_on)])
say("--- 원 사전등록 1급(tail_asym) ---")
print(R[stat == "tail_asym", .(clean, thr, diff = round(diff,4), ratio = round(ratio,3))])
say("--- 적률(m3) 대조: 정제가 얼마나 깎는가 ---")
print(dcast(R[stat %in% c("m3","m3_winsor")], clean + thr ~ stat, value.var = "diff")[
  , lapply(.SD, function(z) if (is.numeric(z)) round(z,4) else z)])

## ---- ★생존 실: 깊이 단조성 (정제 위에서) --------------------------------------
say("=== ★생존 실: 깊이 단조성 — 정제 표본 위 ===")
bands <- list(c(-0.10,-0.20), c(-0.20,-0.30), c(-0.30,-0.40), c(-0.40,-1.00))
for (s in S[c(1,3)]) {
  dt <- s$dt; say("  --- %s ---", s$lab)
  say("    구간            n     Bowley    적률m3   평균수익")
  offv <- dt$fwd1[dt$dd252 > -0.10]
  say("    OFF(dd>-10%%)  %5d  %+8.4f %+8.4f %+8.5f", length(offv), bow(offv), skew_m3(offv), mean(offv))
  for (b in bands) {
    v <- dt$fwd1[dt$dd252 <= b[1] & dt$dd252 > b[2]]
    if (length(v) < 60) { say("    (%.0f,%.0f]     %5d  표본부족", b[2]*100, b[1]*100, length(v)); next }
    say("    (%.0f,%.0f]%s  %5d  %+8.4f %+8.4f %+8.5f", b[2]*100, b[1]*100,
        strrep(" ", max(0, 4-nchar(sprintf("%.0f",b[2]*100)))), length(v), bow(v), skew_m3(v), mean(v))
  }
}

fwrite(R, file.path(OUT, "p0_clean_grid.csv"))
saveRDS(list(R = R, S = lapply(S, function(s) list(lab=s$lab, n=nrow(s$dt)))), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
