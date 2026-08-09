## FQ-182 적대검증 보조 — "왜도는 스케일 불변" 방어논거의 반대편 시험
## 스케일 불변 != 이상치 강건. 3차 적률은 단일 극단일에 지배될 수 있다.
## ① 극단일 k개 제거 민감도 ② 에피소드 잭나이프 ③ 분위수 기반 강건왜도(Bowley/octile) + 순환이동 p
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[frag] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1)]
n <- nrow(D)
say("=== 입력 실측 === %d행 · daily · %s ~ %s · fwd1 sd %.6f",
    n, as.character(min(D$Date)), as.character(max(D$Date)), sd(D$fwd1))

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
bowley <- function(v){q<-quantile(v,c(.25,.5,.75),names=FALSE);if(q[3]-q[1]==0)return(NA_real_);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}
octile <- function(v){q<-quantile(v,c(1/8,.5,7/8),names=FALSE);if(q[3]-q[1]==0)return(NA_real_);(q[3]+q[1]-2*q[2])/(q[3]-q[1])}

THRS <- c(-0.20, -0.30)

## ---------------- ① 극단일 제거 민감도 ----------------
say("=== ① 극단 |fwd1| k일 제거 후 skew 차이 (ON 집단에서만 제거) ===")
rows <- list()
for (thr in THRS) {
  on <- D$dd252 <= thr
  xon <- D$fwd1[on]; xoff <- D$fwd1[!on]
  ord <- order(abs(xon), decreasing = TRUE)
  say("  --- thr %.0f%% (ON %d일) · ON 상위 극단일: %s",
      thr*100, sum(on), paste(sprintf("%+.2f%%", 100*xon[ord[1:5]]), collapse=" "))
  say("      해당일자: %s", paste(as.character(D$Date[on][ord[1:5]]), collapse=" "))
  for (k in 0:5) {
    keep <- if (k == 0) xon else xon[-ord[1:k]]
    d <- skew1(keep) - skew1(xoff)
    say("      k=%d 제거 → ON skew %+.4f · diff %+.4f", k, skew1(keep), d)
    rows[[length(rows)+1L]] <- data.table(thr=thr*100, test="drop_extreme", k=k,
                                          on_skew=skew1(keep), off_skew=skew1(xoff), diff=d)
  }
  ## 상방만 제거 / 하방만 제거 분해
  up <- order(xon, decreasing = TRUE); dn <- order(xon)
  for (k in 1:3) {
    du <- skew1(xon[-up[1:k]]) - skew1(xoff); dd_ <- skew1(xon[-dn[1:k]]) - skew1(xoff)
    say("      상방 top%d 제거 → diff %+.4f | 하방 bot%d 제거 → diff %+.4f", k, du, k, dd_)
    rows[[length(rows)+1L]] <- data.table(thr=thr*100, test="drop_up", k=k, on_skew=skew1(xon[-up[1:k]]), off_skew=skew1(xoff), diff=du)
    rows[[length(rows)+1L]] <- data.table(thr=thr*100, test="drop_dn", k=k, on_skew=skew1(xon[-dn[1:k]]), off_skew=skew1(xoff), diff=dd_)
  }
}
FR <- rbindlist(rows); fwrite(FR, file.path(OUT, "adv_skew_dropk.csv"))

## ---------------- ② 에피소드 잭나이프 ----------------
say("=== ② 에피소드 잭나이프 (ON 에피소드 1개씩 제외) ===")
jk <- list()
for (thr in THRS) {
  on <- D$dd252 <= thr
  r <- rle(on); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  ei <- which(r$values)
  base <- skew1(D$fwd1[on]) - skew1(D$fwd1[!on])
  ds <- numeric(length(ei)); lens <- integer(length(ei)); dts <- character(length(ei))
  for (j in seq_along(ei)) {
    idx <- starts[ei[j]]:ends[ei[j]]
    keep <- setdiff(which(on), idx)
    ds[j] <- skew1(D$fwd1[keep]) - skew1(D$fwd1[!on])
    lens[j] <- length(idx); dts[j] <- as.character(D$Date[starts[ei[j]]])
  }
  o <- order(ds)
  say("  --- thr %.0f%% · base diff %+.4f · 에피소드 %d개 ---", thr*100, base, length(ei))
  say("      잭나이프 diff range [%+.4f, %+.4f] · 부호 반전 에피소드 %d개",
      min(ds), max(ds), sum(ds <= 0))
  say("      최대 하락 3개: %s",
      paste(sprintf("%s(len%d) %+.4f", dts[o[1:3]], lens[o[1:3]], ds[o[1:3]]), collapse=" | "))
  jk[[length(jk)+1L]] <- data.table(thr=thr*100, episode_start=dts, len=lens, diff_wo=ds, base=base)
}
JK <- rbindlist(jk); fwrite(JK, file.path(OUT, "adv_skew_jackknife.csv"))

## ---------------- ③ 강건 왜도 + 순환이동 귀무 ----------------
say("=== ③ 분위수 기반 강건 왜도 (Bowley Q1/Q3, octile 1/8-7/8) + 순환이동 p ===")
set.seed(20260811)
NSH <- 500L; MINSH <- 252L
shifts <- sample(seq(MINSH, n - MINSH), NSH, replace = FALSE)
rb <- list()
for (thr in THRS) {
  dd <- D$dd252; x <- D$fwd1
  on <- dd <= thr
  obs <- c(skew_m3 = skew1(x[on]) - skew1(x[!on]),
           bowley  = bowley(x[on]) - bowley(x[!on]),
           octile  = octile(x[on]) - octile(x[!on]))
  NL <- matrix(NA_real_, NSH, 3); colnames(NL) <- names(obs)
  for (j in seq_len(NSH)) {
    k <- shifts[j]; ddp <- dd[c((k+1):n, 1:k)]; ob <- ddp <= thr
    if (sum(ob) < 30 || sum(!ob) < 30) next
    NL[j, ] <- c(skew1(x[ob]) - skew1(x[!ob]), bowley(x[ob]) - bowley(x[!ob]), octile(x[ob]) - octile(x[!ob]))
  }
  NL <- NL[complete.cases(NL), , drop = FALSE]
  say("  --- thr %.0f%% (ON %d일) ---", thr*100, sum(on))
  for (k in names(obs)) {
    nv <- NL[, k]
    p <- (1 + sum(abs(nv - median(nv)) >= abs(obs[[k]] - median(nv)))) / (1 + length(nv))
    say("      %-8s ON %+.4f · OFF %+.4f · diff %+.4f · null se %.4f · z %+.2f · p %.4f",
        k,
        if (k=="skew_m3") skew1(x[on]) else if (k=="bowley") bowley(x[on]) else octile(x[on]),
        if (k=="skew_m3") skew1(x[!on]) else if (k=="bowley") bowley(x[!on]) else octile(x[!on]),
        obs[[k]], sd(nv), (obs[[k]]-median(nv))/sd(nv), p)
    rb[[length(rb)+1L]] <- data.table(thr=thr*100, stat=k, diff=obs[[k]],
      null_med=median(nv), null_se=sd(nv), z=(obs[[k]]-median(nv))/sd(nv), p_two=p, n_null=length(nv))
  }
}
RB <- rbindlist(rb); fwrite(RB, file.path(OUT, "adv_robust_skew.csv"))
say("=== 완료 ===")
