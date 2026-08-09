## FQ-182 적대검증 — 렌즈 threshold_and_horizon
## 목적 = 확인이 아니라 반증. "낙폭 조건부 forward 왜도 부호 반전"이
##        문턱(-5~-40%) · 전방창(h=1/5/20/60) · 꼬리문턱(2/3/4/5%) 선택에 의존하는가.
## 사전 고정 판정 규약 (측정 전 기록):
##   R1 단조성   : 문턱이 깊어질수록 skew diff 가 커져야 자연스럽다(가설의 내적 논리).
##                 비단조 · 특히 -20/-30% 만 봉우리면 = 단일 셀 선택 혐의.
##   R2 창 강건성: h=1 에만 있고 h=5/20/60 에서 소멸하면 = 1일 반등 아티팩트.
##   R3 꼬리문턱: 3% 에만 있고 2/4/5% 에서 소멸하면 = 꼬리문턱 선택.
##   R4 유의성   : ratio = |diff|/(2*se_blockboot) (P0/P1 과 동일 정의) >= 1.0 을 "유의" 로 본다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv1] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D <- D[, .(Date, BM_Ret, dd252)]
say("=== 입력 실측 === 행수 %d · %s ~ %s · 관측단위 daily · BM_Ret sd %.6f",
    nrow(D), as.character(min(D$Date)), as.character(max(D$Date)), sd(D$BM_Ret))

## ---- h일 forward 수익 (누적) --------------------------------------------------
## 자체합성 금지 규약 대응: 아래는 포트폴리오 *구성* 이 아니라 단일 벤치 시계열의 h일 집계.
## 그럼에도 PerformanceAnalytics::Return.cumulative 와 parity 검증 후에만 사용한다.
lr  <- log1p(D$BM_Ret)
n   <- nrow(D)
fwd_h <- function(h) {
  if (h == 1L) return(shift(D$BM_Ret, 1L, type = "lead"))
  cs <- c(0, cumsum(lr))                     # cs[i+1] = sum(lr[1..i])
  out <- rep(NA_real_, n)
  ok  <- seq_len(n - h)
  out[ok] <- expm1(cs[ok + 1L + h] - cs[ok + 1L])
  out
}
suppressPackageStartupMessages(library(PerformanceAnalytics))
set.seed(11)
chk_h <- 20L; f20 <- fwd_h(chk_h); ii <- sample(which(!is.na(f20)), 200)
ref <- vapply(ii, function(i) as.numeric(Return.cumulative(D$BM_Ret[(i+1):(i+chk_h)])), numeric(1))
say("  ★h집계 parity(PerformanceAnalytics::Return.cumulative, h=20, 200창): maxabs 차이 %.3e", max(abs(ref - f20[ii])))
stopifnot(max(abs(ref - f20[ii])) < 1e-12)

## ---- 통계량 (사전 고정) --------------------------------------------------------
skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/m/s^4-3}
bowley <- function(v, p){ q <- quantile(v, c(p, 0.5, 1-p), names = FALSE, type = 7)
  d <- q[3]-q[1]; if(!is.finite(d)||d==0) return(NA_real_); (q[3]+q[1]-2*q[2])/d }
TAILS <- c(0.02, 0.03, 0.04, 0.05)
stat_names <- c("mean","sd","skew","kurt","bowley25","bowley10",
                paste0("p_up", TAILS*100), paste0("p_dn", TAILS*100), paste0("tail_asym", TAILS*100))
stats_of <- function(v) {
  v <- v[is.finite(v)]
  c(mean = mean(v), sd = sd(v), skew = skew1(v), kurt = kurt1(v),
    bowley25 = bowley(v, 0.25), bowley10 = bowley(v, 0.10),
    vapply(TAILS, function(q) mean(v >= q), 0),
    vapply(TAILS, function(q) mean(v <= -q), 0),
    vapply(TAILS, function(q) mean(v >= q) - mean(v <= -q), 0))
}

THRS <- seq(-0.05, -0.40, by = -0.05)
HS   <- c(1L, 5L, 20L, 60L)
B    <- 500L
set.seed(20260809)

rows <- list()
for (h in HS) {
  x  <- fwd_h(h)
  keep <- is.finite(x)
  xx <- x[keep]; dd <- D$dd252[keep]; m <- length(xx)
  blk <- max(60L, 3L*h)                       # 중첩창 자기상관 흡수: 블록 >= 3h
  starts <- seq_len(m - blk + 1L); nb <- ceiling(m/blk); off0 <- 0:(blk-1L)
  say("--- h=%d일 (유효 %d일 · 블록 %d일 · 부트 %d회) ---", h, m, blk, B)
  ## 부트 인덱스는 h 당 한 번 뽑아 모든 문턱에 공유 (문턱 간 비교가능성 확보)
  BOOT <- vector("list", length(THRS))
  for (j in seq_along(THRS)) BOOT[[j]] <- matrix(NA_real_, B, length(stat_names))
  for (b in seq_len(B)) {
    s   <- sample(starts, nb, replace = TRUE)
    idx <- as.vector(outer(off0, s, "+"))[seq_len(m)]
    xb  <- xx[idx]; db <- dd[idx]
    for (j in seq_along(THRS)) {
      ob <- db <= THRS[j]
      if (sum(ob) < 30L || sum(!ob) < 30L) next
      BOOT[[j]][b, ] <- stats_of(xb[ob]) - stats_of(xb[!ob])
    }
  }
  for (j in seq_along(THRS)) {
    thr <- THRS[j]; on <- dd <= thr
    if (sum(on) < 30L) { say("    %.0f%%: ON %d일 — 표본 부족, 생략", thr*100, sum(on)); next }
    A <- stats_of(xx[on]); O <- stats_of(xx[!on]); obs <- A - O
    BB <- BOOT[[j]]; BB <- BB[complete.cases(BB), , drop = FALSE]
    se <- apply(BB, 2, sd, na.rm = TRUE)
    for (k in seq_along(stat_names)) {
      pv <- mean(abs(BB[, k] - mean(BB[, k], na.rm = TRUE)) >= abs(obs[[k]]), na.rm = TRUE)
      rows[[length(rows)+1L]] <- data.table(
        h = h, thr = thr*100, stat = stat_names[k], n_on = sum(on), n_off = sum(!on),
        n_boot = nrow(BB), on = A[[k]], off = O[[k]], diff = obs[[k]],
        se = se[[k]], ratio = abs(obs[[k]])/(2*se[[k]]), p_two = pv)
    }
    say("    %.0f%%: ON %5d · skew ON %+.4f OFF %+.4f diff %+.4f se %.4f ratio %.3f",
        thr*100, sum(on), A[["skew"]], O[["skew"]], obs[["skew"]], se[["skew"]],
        abs(obs[["skew"]])/(2*se[["skew"]]))
  }
}
R <- rbindlist(rows)
fwrite(R, file.path(OUT, "adv_threshold_and_horizon.csv"))
saveRDS(R, file.path(OUT, "adv_threshold_and_horizon.rds"))

## ================= 판정 =========================================================
say("")
say("=== ①문턱 grid × skew (h=1) — 단조성 검사 ===")
S1 <- R[stat == "skew" & h == 1L][order(-thr)]
say("  문턱   ON일수  skewON    skewOFF    diff      se      ratio   p_two")
for (i in seq_len(nrow(S1))) say("  %4.0f%% %7d %+8.4f %+9.4f %+9.4f %8.4f %7.3f %7.3f",
    S1$thr[i], S1$n_on[i], S1$on[i], S1$off[i], S1$diff[i], S1$se[i], S1$ratio[i], S1$p_two[i])
say("  ★부호 반전(ON>0 ∧ OFF<0) 성립 문턱 = %s",
    paste0(S1[on > 0 & off < 0, sprintf("%.0f%%", thr)], collapse = " · "))
say("  ★단조? diff 가 깊어질수록 증가하는지 — Spearman(|thr|, diff) = %+.3f",
    cor(abs(S1$thr), S1$diff, method = "spearman"))
say("  ★ratio>=1.0 문턱 = %s / %d",
    paste0(S1[ratio >= 1, sprintf("%.0f%%", thr)], collapse = " · "), nrow(S1))

say("")
say("=== ②전방창 h × skew diff ===")
W <- dcast(R[stat == "skew"], thr ~ h, value.var = "diff")
setnames(W, c("thr", paste0("h", HS)))
Wr <- dcast(R[stat == "skew"], thr ~ h, value.var = "ratio")
setnames(Wr, c("thr", paste0("r", HS)))
M <- merge(W, Wr, by = "thr")[order(-thr)]
say("  문턱     diff h1    h5     h20    h60   |  ratio h1   h5    h20   h60")
for (i in seq_len(nrow(M))) say("  %4.0f%%  %+7.4f %+7.4f %+7.4f %+7.4f | %6.3f %6.3f %6.3f %6.3f",
    M$thr[i], M$h1[i], M$h5[i], M$h20[i], M$h60[i], M$r1[i], M$r5[i], M$r20[i], M$r60[i])
say("  ★h>1 에서 ratio>=1.0 인 셀 = %d / %d", R[stat=="skew" & h>1 & ratio>=1, .N], R[stat=="skew" & h>1, .N])

say("")
say("=== ③꼬리 문턱 2/3/4/5%% × tail_asym (h=1) ===")
TA <- R[h == 1L & grepl("^tail_asym", stat)]
TA[, q := as.numeric(sub("tail_asym", "", stat))]
WT <- dcast(TA, thr ~ q, value.var = "diff"); WR <- dcast(TA, thr ~ q, value.var = "ratio")
setnames(WT, c("thr", paste0("d", c(2,3,4,5)))); setnames(WR, c("thr", paste0("r", c(2,3,4,5))))
MT <- merge(WT, WR, by = "thr")[order(-thr)]
say("  문턱    diff 2%%     3%%      4%%      5%%   |  ratio 2%%   3%%    4%%    5%%")
for (i in seq_len(nrow(MT))) say("  %4.0f%%  %+7.4f %+7.4f %+7.4f %+7.4f | %6.3f %6.3f %6.3f %6.3f",
    MT$thr[i], MT$d2[i], MT$d3[i], MT$d4[i], MT$d5[i], MT$r2[i], MT$r3[i], MT$r4[i], MT$r5[i])
say("  ★tail_asym ratio>=1.0 셀 = %d / %d", TA[ratio>=1, .N], nrow(TA))

say("")
say("=== ④강건 왜도(Bowley, 분위수 기반 — 극단 1~2관측에 둔감) h=1 ===")
BW <- R[h == 1L & stat %in% c("skew","bowley25","bowley10")]
BM <- dcast(BW, thr ~ stat, value.var = "diff")[order(-thr)]
BR <- dcast(BW, thr ~ stat, value.var = "ratio")[order(-thr)]
say("  문턱   diff: moment  bowley25  bowley10  |  ratio: moment bowley25 bowley10")
for (i in seq_len(nrow(BM))) say("  %4.0f%%  %+11.4f %+9.4f %+9.4f | %9.3f %8.3f %8.3f",
    BM$thr[i], BM$skew[i], BM$bowley25[i], BM$bowley10[i],
    BR$skew[i], BR$bowley25[i], BR$bowley10[i])
say("=== adv_01 완료 ===")
