## FQ-182 적대검증 STEP 3 — adv_02 가 연 세 갈래를 se 붙여 확정
##  (i) 극단 관측 정체 확인 (어느 날인가)
##  (ii) 시대 분할 pre/post-2015 (KR 가격제한폭 ±15%→±30%, 2015-06) 를 문턱 grid 전체에서 + 블록부트 se
##  (iii) 결합 스트레스: pre-2015 ∧ winsorize 1%  (두 반론을 동시에 걸었을 때 남는가)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv3] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)][, .(Date, BM_Ret, dd252)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[is.finite(fwd1)][, yr := year(Date)]
say("=== 입력 실측 === %d일 · %s ~ %s · 관측단위 daily", nrow(D),
    as.character(min(D$Date)), as.character(max(D$Date)))

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
sdiff <- function(x, on) skew1(x[on]) - skew1(x[!on])

## ---- (i) ON 군 극단 관측의 정체 -------------------------------------------------
say("")
say("=== (i) ON(dd252<=-20%%) 군 상위 5개 forward 수익의 정체 + 3차합 기여율 ===")
on20 <- D$dd252 <= -0.20; xo <- D$fwd1[on20]; do_ <- D$Date[on20]
z <- (xo - mean(xo))/sd(xo); cub <- z^3
ordr <- order(-cub)[1:5]
say("  순위  날짜         fwd1      z      z^3     Σz^3 기여율")
for (i in seq_along(ordr)) say("  %4d  %s  %+7.4f %+6.2f %+8.1f %11.1f%%",
    i, as.character(do_[ordr[i]]), xo[ordr[i]], z[ordr[i]], cub[ordr[i]], 100*cub[ordr[i]]/sum(cub))
say("  ★상위5 합계 기여율 = %.1f%% (n_on=%d, 즉 표본의 %.2f%%가 왜도의 대부분)",
    100*sum(cub[ordr])/sum(cub), length(xo), 100*5/length(xo))

## ---- 블록 부트 (공통) -----------------------------------------------------------
bb_sdiff <- function(x, dd, thr, B = 600L, blk = 60L, transform = identity) {
  m <- length(x); starts <- seq_len(m - blk + 1L); nb <- ceiling(m/blk); off0 <- 0:(blk-1L)
  o <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.vector(outer(off0, s, "+"))[seq_len(m)]
    xb <- transform(x[idx]); ob <- dd[idx] <= thr
    if (sum(ob) < 30L || sum(!ob) < 30L) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob])
  }
  o[is.finite(o)]
}
THRS <- seq(-0.05, -0.40, by = -0.05)
set.seed(20260809)
rows <- list(); add <- function(...) rows[[length(rows)+1L]] <<- data.table(...)

## ---- (ii) 시대 분할 × 문턱 grid --------------------------------------------------
say("")
say("=== (ii) pre-2015(1991~2015-05) vs post-2015(2015-06~) × 문턱 grid ===")
say("  근거: KR 가격제한폭 ±15%% → ±30%% (2015-06-15). 일간 극단값의 물리적 상한이 2배로 바뀜.")
CUT <- as.Date("2015-06-15")
say("  문턱 | 전기간 diff  ratio | pre-2015 ON/diff/ratio          | post-2015 ON/diff/ratio")
for (thr in THRS) {
  res <- list()
  for (tag in c("all","pre","post")) {
    S <- if (tag=="all") D else if (tag=="pre") D[Date < CUT] else D[Date >= CUT]
    on <- S$dd252 <= thr
    if (sum(on) < 30 || sum(!on) < 30) { res[[tag]] <- c(sum(on), NA, NA); next }
    d <- sdiff(S$fwd1, on); bo <- bb_sdiff(S$fwd1, S$dd252, thr, 400L, 60L)
    se <- sd(bo); res[[tag]] <- c(sum(on), d, abs(d)/(2*se))
    add(test="era_split", era=tag, thr=thr*100, n_on=sum(on), n_off=sum(!on), diff=d, se=se, ratio=abs(d)/(2*se),
        skew_on=skew1(S$fwd1[on]), skew_off=skew1(S$fwd1[!on]))
  }
  f <- function(v) if (is.na(v[2])) sprintf("%5d   (표본부족)      ", v[1]) else sprintf("%5d %+7.4f %6.3f", v[1], v[2], v[3])
  say("  %4.0f%% | %+8.4f %6.3f | %s | %s", thr*100, res$all[2], res$all[3], f(res$pre), f(res$post))
}
E <- rbindlist(rows)
say("  ★pre-2015 에서 ratio>=1.0 문턱 = %d / %d  (전기간은 8/8)",
    E[era=="pre" & ratio>=1, .N], E[era=="pre", .N])
say("  ★pre-2015 부호 반전(ON>0 ∧ OFF<0) 문턱 = %s",
    { s <- E[era=="pre" & skew_on>0 & skew_off<0, sprintf("%.0f%%", thr)]; if(length(s)) paste(s, collapse=" · ") else "없음" })

## ---- (iii) 결합 스트레스 --------------------------------------------------------
say("")
say("=== (iii) 결합 스트레스 — 반론 2개(시대·극단레버리지)를 동시에 ===")
say("  문턱 |  전기간raw   전기간win1%%   pre2015raw   pre2015win1%% (diff / ratio)")
for (thr in THRS) {
  cells <- list()
  for (tag in c("all_raw","all_win","pre_raw","pre_win")) {
    S <- if (grepl("^all", tag)) D else D[Date < CUT]
    x <- S$fwd1
    tf <- identity
    if (grepl("win$", tag)) { q <- quantile(x, c(0.01, 0.99), names=FALSE); tf <- function(v) pmin(pmax(v, q[1]), q[2]) }
    xt <- tf(x); on <- S$dd252 <= thr
    if (sum(on) < 30 || sum(!on) < 30) { cells[[tag]] <- c(NA, NA); next }
    d <- sdiff(xt, on); bo <- bb_sdiff(x, S$dd252, thr, 400L, 60L, transform = tf); se <- sd(bo)
    cells[[tag]] <- c(d, abs(d)/(2*se))
    add(test="combined", era=tag, thr=thr*100, n_on=sum(on), n_off=sum(!on), diff=d, se=se, ratio=abs(d)/(2*se),
        skew_on=skew1(xt[on]), skew_off=skew1(xt[!on]))
  }
  g <- function(v) if (is.na(v[1])) "     -        " else sprintf("%+7.4f/%5.3f", v[1], v[2])
  say("  %4.0f%% | %s %s %s %s", thr*100, g(cells$all_raw), g(cells$all_win), g(cells$pre_raw), g(cells$pre_win))
}
R3 <- rbindlist(rows)
fwrite(R3, file.path(OUT, "adv_stress_combined.csv"))
CB <- R3[test=="combined"]
say("  ★결합 스트레스(pre2015 ∧ win1%%) 에서 ratio>=1.0 셀 = %d / %d",
    CB[era=="pre_win" & ratio>=1, .N], CB[era=="pre_win", .N])
say("  ★참고: 전기간 raw ratio>=1.0 = %d / %d", CB[era=="all_raw" & ratio>=1, .N], CB[era=="all_raw", .N])
say("=== adv_03 완료 → adv_stress_combined.csv ===")
