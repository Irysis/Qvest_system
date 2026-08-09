## FQ-182 적대검증 STEP 4 — 두 잔여 질문
##  (I) 99.3% 를 지배하는 2026-07-30 관측이 실데이터인가 데이터 결함인가 (원자료 확인)
##  (II) h=1 효과가 '낙폭 상태' 때문인가, 아니면 **직전일 급락 후 단기반등**(1일 반전) 때문인가
##       — 후자면 252일 낙폭 상태는 대리변수일 뿐이고, h=5 소멸·h=20/60 역전과 정합한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv4] ", fmt, "\n"), ...)); flush.console() }

P0 <- readRDS(file.path(OUT, "p0.rds"))
D  <- as.data.table(P0$D)[order(Date)]
say("=== 입력 실측 === %d일 · 컬럼 %s", nrow(D), paste(names(D), collapse="/"))
## 저장된 fwd1 과 내 재계산 parity (정렬 가정 검증)
D[, fwd1_re := shift(BM_Ret, 1L, type = "lead")]
cc <- D[is.finite(fwd1) & is.finite(fwd1_re)]
say("  ★fwd1 정렬 parity(저장본 vs 재계산 lead1): maxabs %.3e (n=%d)", max(abs(cc$fwd1 - cc$fwd1_re)), nrow(cc))
D <- D[is.finite(fwd1_re)]; D[, fwd1 := fwd1_re]

## ---- (I) 원자료 확인 ------------------------------------------------------------
say("")
say("=== (I) 지배 관측 주변 원자료 (2026-07-24 ~ 2026-08-07) ===")
say("  Date         BM_Ret     dd252")
W <- D[Date >= as.Date("2026-07-24") & Date <= as.Date("2026-08-07")]
for (i in seq_len(nrow(W))) say("  %s  %+8.4f  %+8.4f", as.character(W$Date[i]), W$BM_Ret[i], W$dd252[i])
say("  ★전기간 |BM_Ret| 상위 8일:")
T8 <- D[order(-abs(BM_Ret))][1:8]
for (i in 1:8) say("     %s  %+8.4f  (dd252 %+.4f)", as.character(T8$Date[i]), T8$BM_Ret[i], T8$dd252[i])
say("  ★일간 |수익| > 15%% 인 날 = %d일 · > 12%% = %d일 (KR 지수 물리적 개연성 점검용)",
    D[abs(BM_Ret) > 0.15, .N], D[abs(BM_Ret) > 0.12, .N])

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
sdiff <- function(x, on) skew1(x[on]) - skew1(x[!on])
bb_se <- function(x, on, B=400L, blk=60L) {
  m <- length(x); starts <- seq_len(m-blk+1L); nb <- ceiling(m/blk); off0 <- 0:(blk-1L)
  o <- rep(NA_real_, B)
  for (b in seq_len(B)) { s <- sample(starts, nb, replace=TRUE)
    idx <- as.vector(outer(off0, s, "+"))[seq_len(m)]
    xb <- x[idx]; ob <- on[idx]; if (sum(ob)<30L || sum(!ob)<30L) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob]) }
  sd(o[is.finite(o)])
}
set.seed(20260809); rows <- list(); add <- function(...) rows[[length(rows)+1L]] <<- data.table(...)

## ---- (I-b) 지배 관측 1개 제거 후 전체 재판정 --------------------------------------
say("")
say("=== (I-b) 2026-07-30 단 1일 제거 후 문턱 grid 전면 재판정 (h=1) ===")
DX <- D[Date != as.Date("2026-07-30")]
say("  문턱 |  원본 diff/ratio   |  1일 제거 diff/ratio  | 감소율")
for (thr in seq(-0.05, -0.40, by=-0.05)) {
  on0 <- D$dd252 <= thr; on1 <- DX$dd252 <= thr
  if (sum(on0)<30 || sum(on1)<30) next
  d0 <- sdiff(D$fwd1, on0); s0 <- bb_se(D$fwd1, on0)
  d1 <- sdiff(DX$fwd1, on1); s1 <- bb_se(DX$fwd1, on1)
  say("  %4.0f%% | %+7.4f / %5.3f   | %+7.4f / %5.3f     | %6.1f%%",
      thr*100, d0, abs(d0)/(2*s0), d1, abs(d1)/(2*s1), 100*(1 - d1/d0))
  add(test="drop_2026_07_30", thr=thr*100, diff_full=d0, ratio_full=abs(d0)/(2*s0),
      diff_drop=d1, ratio_drop=abs(d1)/(2*s1), drop_pct=100*(1-d1/d0))
}

## ---- (II) 단기반전 교락: 직전일 수익 통제 -----------------------------------------
say("")
say("=== (II) h=1 효과는 '낙폭상태' 인가 '직전일 급락 후 1일 반등' 인가 ===")
say("  검정 = 같은 날 수익 BM_Ret[t] 구간 안에서(층화) dd252 문턱 대비 왜도차를 잰다.")
say("  ★교락이 원인이면 층화 후 왜도차가 소멸한다.")
for (thr in c(-0.10, -0.20, -0.30)) {
  on <- D$dd252 <= thr
  say("  --- dd252 <= %.0f%% ---", thr*100)
  d_all <- sdiff(D$fwd1, on); say("     비층화 전체 diff = %+.4f", d_all)
  ## (a) 당일 급락일(BM_Ret[t] <= -3%) 제외
  keepA <- D$BM_Ret > -0.03
  dA <- sdiff(D$fwd1[keepA], on[keepA])
  seA <- bb_se(D$fwd1[keepA], on[keepA])
  say("     (a) 당일 BM_Ret<=-3%% 제외 후 diff = %+.4f (ratio %.3f · 제외 %d일)", dA, abs(dA)/(2*seA), sum(!keepA))
  add(test="reversal_control", thr=thr*100, variant="excl_same_day_drop3", diff=dA, ratio=abs(dA)/(2*seA), n=sum(keepA))
  ## (b) 당일 |수익| 사분위 층화 — 각 층 안에서 diff
  D[, qb := cut(abs(BM_Ret), quantile(abs(BM_Ret), 0:4/4), include.lowest=TRUE, labels=FALSE)]
  for (q in 1:4) {
    k <- D$qb == q; if (sum(on & k) < 30 || sum(!on & k) < 30) next
    dq <- sdiff(D$fwd1[k], on[k]); seq_ <- bb_se(D$fwd1[k], on[k])
    say("     (b) 당일|수익| Q%d (ON %4d/OFF %4d) diff = %+.4f (ratio %.3f)",
        q, sum(on&k), sum(!on&k), dq, abs(dq)/(2*seq_))
    add(test="reversal_control", thr=thr*100, variant=paste0("absret_Q", q), diff=dq, ratio=abs(dq)/(2*seq_), n=sum(k))
  }
}

## ---- (III) h 를 촘촘히: 효과가 어디서 죽는가 ---------------------------------------
say("")
say("=== (III) 전방창 촘촘 grid h=1,2,3,5,10,20 (dd252<=-20%%) ===")
lr <- log1p(D$BM_Ret); n <- nrow(D); cs <- c(0, cumsum(lr))
say("  h    유효일수  skewON    skewOFF    diff      ratio")
for (h in c(1L,2L,3L,5L,10L,20L)) {
  x <- rep(NA_real_, n); ok <- seq_len(n-h); x[ok] <- expm1(cs[ok+1L+h] - cs[ok+1L])
  kp <- is.finite(x); xx <- x[kp]; on <- D$dd252[kp] <= -0.20
  d <- sdiff(xx, on); se <- bb_se(xx, on, 400L, max(60L, 3L*h))
  say("  %2d %9d %+9.4f %+9.4f %+9.4f %9.3f", h, sum(kp), skew1(xx[on]), skew1(xx[!on]), d, abs(d)/(2*se))
  add(test="h_fine", thr=-20, variant=paste0("h", h), diff=d, ratio=abs(d)/(2*se), n=sum(kp))
}
R4 <- rbindlist(rows, fill = TRUE)
fwrite(R4, file.path(OUT, "adv_dataqual_reversal.csv"))
say("=== adv_04 완료 → adv_dataqual_reversal.csv ===")
