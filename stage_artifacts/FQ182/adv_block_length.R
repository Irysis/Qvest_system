## FQ-182 적대검증 — 렌즈: block_length
## 목적 = 확인이 아니라 반증. 블록 60일 se 가 과소평가인가?
## ① 블록 60/120/250/500(+750) 재산출 → ratio 표
## ② 순환이동(circular shift) 귀무 500회 → p 값 (dd252 위상만 이동, ON 개수·에피소드 구조 보존)
## ratio 정의는 P1 원본과 동일: |diff| / (2*se)   (즉 ratio 1.0 == 2-sigma)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv] ", fmt, "\n"), ...)); flush.console() }

## ---------------- 입력 실측 (측정 첫 출력) ----------------
P0 <- readRDS(file.path(OUT, "p0.rds"))
D  <- as.data.table(P0$D)[order(Date)]
say("원본 D: %d행 · 컬럼 [%s]", nrow(D), paste(names(D), collapse=", "))
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1)]
n <- nrow(D)
say("=== 입력 실측 ===")
say("  행수 %d · 관측단위 daily · 기간 %s ~ %s", n, as.character(min(D$Date)), as.character(max(D$Date)))
say("  BM_Ret  sd %.6f · range [%+.5f, %+.5f]", sd(D$BM_Ret), min(D$BM_Ret), max(D$BM_Ret))
say("  fwd1    sd %.6f · range [%+.5f, %+.5f]", sd(D$fwd1), min(D$fwd1), max(D$fwd1))
say("  dd252   range [%+.5f, %+.5f] · NA %d", min(D$dd252), max(D$dd252), sum(is.na(D$dd252)))
## 관측단위 확인: 날짜 간격
gaps <- as.numeric(diff(as.Date(D$Date)))
say("  날짜간격 중앙값 %.0f일 (일간 확인) · 최대 %.0f일", median(gaps), max(gaps))

## ---------------- 통계량 (P1 과 동일 정의) ----------------
skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/m/s^4-3}
stats_of <- function(v) c(mean = mean(v), sd = sd(v), skew = skew1(v), kurt = kurt1(v),
                          p_dn3 = mean(v <= -0.03), p_up3 = mean(v >= 0.03),
                          tail_asym = mean(v >= 0.03) - mean(v <= -0.03))
SN <- names(stats_of(rnorm(10)))

## ---------------- 에피소드 구조 실측 ----------------
runs_of <- function(on) { r <- rle(on); r$lengths[r$values] }
THRS <- c(-0.10, -0.20, -0.30)
say("=== 에피소드 구조 (ON = dd252 <= thr) ===")
epi <- list()
for (thr in THRS) {
  on <- D$dd252 <= thr
  L <- runs_of(on)
  say("  thr %.0f%%: ON %d일 (%.1f%%) · 에피소드 %d개 · 길이 median %.0f / max %.0f",
      thr*100, sum(on), 100*mean(on), length(L), median(L), max(L))
  epi[[length(epi)+1L]] <- data.table(thr = thr*100, n_on = sum(on), n_off = sum(!on),
                                      n_episode = length(L), epi_med = median(L), epi_max = max(L))
}
EPI <- rbindlist(epi); fwrite(EPI, file.path(OUT, "adv_episodes.csv"))

## ---------------- 관측 차이 ----------------
obs_list <- list()
for (thr in THRS) {
  on <- D$dd252 <= thr
  A <- stats_of(D$fwd1[on]); B0 <- stats_of(D$fwd1[!on])
  for (k in SN) obs_list[[length(obs_list)+1L]] <-
    data.table(thr = thr*100, stat = k, on = A[[k]], off = B0[[k]], diff = A[[k]] - B0[[k]])
}
OBS <- rbindlist(obs_list)
say("=== 관측 차이 (재측정 — 인용 아님) ===")
print(OBS[stat %in% c("skew","sd","tail_asym","mean"), .(thr, stat, on=round(on,4), off=round(off,4), diff=round(diff,4))])

## ---------------- ① 블록 부트스트랩 × 블록길이 ----------------
bb <- function(x, on, B, blk) {
  nn <- length(x); nb <- ceiling(nn/blk); starts <- seq_len(max(1, nn-blk+1))
  o <- matrix(NA_real_, B, 7); drop <- 0L
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, nn))))[1:nn]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) { drop <- drop + 1L; next }
    o[b, ] <- stats_of(xb[ob]) - stats_of(xb[!ob])
  }
  o <- o[complete.cases(o), , drop = FALSE]; colnames(o) <- SN
  attr(o, "drop") <- drop; o
}

BLKS <- c(60L, 120L, 250L, 500L, 750L)
B <- 1000L
set.seed(20260809)
rows <- list()
for (thr in THRS) {
  on <- D$dd252 <= thr
  A <- stats_of(D$fwd1[on]); B0 <- stats_of(D$fwd1[!on]); obs <- A - B0
  for (blk in BLKS) {
    BB <- bb(D$fwd1, on, B, blk)
    se <- apply(BB, 2, sd, na.rm = TRUE)
    say("  thr %.0f%% · blk %3d: 유효 %d/%d (min-30 필터 탈락 %d)",
        thr*100, blk, nrow(BB), B, attr(BB, "drop"))
    for (k in SN) rows[[length(rows)+1L]] <- data.table(
      thr = thr*100, blk = blk, stat = k, diff = obs[[k]], se = se[[k]],
      ratio = abs(obs[[k]])/(2*se[[k]]), t_1se = abs(obs[[k]])/se[[k]],
      n_valid = nrow(BB))
  }
}
BL <- rbindlist(rows)
fwrite(BL, file.path(OUT, "adv_block_length.csv"))

say("=== ① 블록길이별 se · ratio (ratio = |diff|/(2se), 1.0 = 2-sigma) ===")
for (st in c("skew","sd","tail_asym","p_up3","p_dn3","mean")) {
  W <- dcast(BL[stat == st], thr ~ blk, value.var = "ratio")
  S <- dcast(BL[stat == st], thr ~ blk, value.var = "se")
  say("  --- %s ---", st)
  cat("   ratio:\n"); print(W[, lapply(.SD, function(z) if (is.numeric(z)) round(z,3) else z)])
  cat("   se   :\n"); print(S[, lapply(.SD, function(z) if (is.numeric(z)) signif(z,4) else z)])
}

## ---------------- ② 순환이동 귀무 ----------------
## dd252 를 무작위 위상 k 만큼 순환이동 → ON 개수·에피소드 구조 보존, fwd1 과의 정렬만 파괴
set.seed(20260810)
NSH <- 500L
MINSH <- 252L   ## dd252 는 252일 롤링 → 1년 미만 이동은 원본과 강하게 겹침
shifts <- sample(seq(MINSH, n - MINSH), NSH, replace = FALSE)
say("=== ② 순환이동 귀무: %d회 · 이동폭 [%d, %d]일 ===", NSH, min(shifts), max(shifts))
cs_rows <- list(); nulls <- list()
for (thr in THRS) {
  dd <- D$dd252; x <- D$fwd1
  obs <- stats_of(x[dd <= thr]) - stats_of(x[!(dd <= thr)])
  NL <- matrix(NA_real_, NSH, 7); colnames(NL) <- SN
  for (j in seq_len(NSH)) {
    k <- shifts[j]
    ddp <- dd[c((k+1):n, 1:k)]
    ob <- ddp <= thr
    if (sum(ob) < 30 || sum(!ob) < 30) next
    NL[j, ] <- stats_of(x[ob]) - stats_of(x[!ob])
  }
  NL <- NL[complete.cases(NL), , drop = FALSE]
  nulls[[as.character(thr)]] <- NL
  for (k in SN) {
    nv <- NL[, k]
    p_two <- (1 + sum(abs(nv - median(nv)) >= abs(obs[[k]] - median(nv)))) / (1 + length(nv))
    p_raw <- (1 + sum(abs(nv) >= abs(obs[[k]]))) / (1 + length(nv))
    cs_rows[[length(cs_rows)+1L]] <- data.table(
      thr = thr*100, stat = k, diff = obs[[k]],
      null_med = median(nv), null_se = sd(nv),
      z_vs_null = (obs[[k]] - median(nv))/sd(nv),
      p_two_centered = p_two, p_two_raw = p_raw, n_null = length(nv))
  }
}
CS <- rbindlist(cs_rows)
fwrite(CS, file.path(OUT, "adv_circular_shift.csv"))
say("=== ② 순환이동 귀무 p 값 ===")
print(CS[stat %in% c("skew","sd","tail_asym","p_up3","p_dn3","mean"),
         .(thr, stat, diff = round(diff,4), null_med = round(null_med,4),
           null_se = round(null_se,4), z = round(z_vs_null,2),
           p = round(p_two_centered,4), p_raw = round(p_two_raw,4))][order(stat, thr)])

## ---------------- 판정 규칙 (사전 고정, 배정문 그대로) ----------------
say("=== 판정 ===")
sk <- BL[stat == "skew"]
tab <- dcast(sk, thr ~ blk, value.var = "ratio")
print(tab)
bad <- sk[blk >= 250L & thr <= -20 & ratio < 1.0]
say("  ★규칙: blk>=250 에서 skew ratio < 1.0 인 셀 = %d (해당 시 반증)", nrow(bad))
if (nrow(bad)) print(bad[, .(thr, blk, ratio = round(ratio,3))])
p_sk <- CS[stat == "skew" & thr <= -20]
say("  ★순환이동 skew p: %s", paste(sprintf("%.0f%%: p=%.4f", p_sk$thr, p_sk$p_two_centered), collapse = " · "))
say("=== 완료 ===")
