## FQ-182 P1 — ★본측정: **forward** 분포 형태 (동시점은 기술적이라 판정 불가)
## P0 은 동시점(t 낙폭 ↔ t 수익)이었다 — 낙폭 중 변동성이 큰 것은 정의에 가까워 의사결정 정보가 아니다.
## 의사결정 질문 = "오늘 낙폭 상태일 때 **내일** 분포가 어떻게 생겼나".
## ★사전 고정: 1급 = tail_asym(상방꼬리 − 하방꼬리) forward. 도훈 가설의 가장 날카로운 검정 가능 형태.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
D <- D[!is.na(fwd1)]
say("=== 입력 실측 === %d일 · %s ~ %s · forward 수익 sd %.5f",
    nrow(D), min(D$Date), max(D$Date), sd(D$fwd1))
say("  ★정렬: 신호 dd252[t] (t 종가 관측 가능) → 대상 fwd1 = BM_Ret[t+1]. 동시점 미사용.")

skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/n/s^4-3}
stats_of <- function(v) c(mean = mean(v), sd = sd(v), skew = skew1(v), kurt = kurt1(v),
                          p_dn3 = mean(v <= -0.03), p_up3 = mean(v >= 0.03),
                          tail_asym = mean(v >= 0.03) - mean(v <= -0.03))
set.seed(20260809)
bb <- function(x, on, B = 500L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1))
  o <- matrix(NA_real_, B, 7)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b, ] <- stats_of(xb[ob]) - stats_of(xb[!ob])
  }
  o <- o[complete.cases(o), , drop = FALSE]; colnames(o) <- names(stats_of(x[1:10])); o
}

rows <- list()
for (thr in c(-0.10, -0.20, -0.30)) {
  on <- D$dd252 <= thr
  if (sum(on) < 100) next
  A <- stats_of(D$fwd1[on]); B0 <- stats_of(D$fwd1[!on]); obs <- A - B0
  BB <- bb(D$fwd1, on, 500L, 60L); se <- apply(BB, 2, sd, na.rm = TRUE)
  say("--- dd252 <= %.0f%% (ON %d일 · OFF %d일 · 부트 %d회) ---", thr*100, sum(on), sum(!on), nrow(BB))
  say("    지표         ON        OFF       차이      부트se    |차이|/2se")
  for (k in names(A))
    say("    %-10s %+9.5f %+9.5f %+9.5f %9.5f %9.3f",
        k, A[[k]], B0[[k]], obs[[k]], se[[k]], abs(obs[[k]])/(2*se[[k]]))
  for (k in names(A)) rows[[length(rows)+1L]] <- data.table(
    thr = thr*100, stat = k, on = A[[k]], off = B0[[k]], diff = obs[[k]],
    se = se[[k]], ratio = abs(obs[[k]])/(2*se[[k]]),
    p_two = mean(abs(BB[, k] - mean(BB[, k], na.rm=TRUE)) >= abs(obs[[k]]), na.rm = TRUE))
}
R <- rbindlist(rows)

say("=== ★1급 판정: tail_asym (상방 − 하방 꼬리) forward ===")
TA <- R[stat == "tail_asym"]
print(TA[, .(thr, on = round(on,4), off = round(off,4), diff = round(diff,4),
             se = round(se,4), ratio = round(ratio,3))])
say("  ★도훈 가설이 옳다면 diff > 0 (낙폭 뒤 상방꼬리가 상대적으로 두꺼워짐)")
say("  실측 부호: %s", paste(sprintf("%.0f%%: %s", TA$thr, ifelse(TA$diff>0,"양(+)","음(−)")), collapse=" · "))

say("=== 분포 지표 요약 (mean 제외) ===")
DS <- R[stat != "mean"]
print(DS[order(-ratio), .(thr, stat, diff = round(diff,5), ratio = round(ratio,3))][1:10])
say("  ratio >= 1.0 셀 = %d / %d", DS[ratio >= 1.0, .N], nrow(DS))

say("=== ★해석 규약 (사전 고정) ===")
say("  ①sd 증가는 도훈 가설을 지지하지 않는다 — 변동성 확대는 양방향이다")
say("  ②지지 근거가 되려면 **tail_asym > 0** 또는 skew 개선이 필요하다")
say("  ③분포가 달라도 그것이 '비중 확대' 를 함의하려면 별도 논증(효용/위험예산)이 필요하다")

fwrite(R, file.path(OUT, "p1_forward_moments.csv"))
saveRDS(list(R = R), file.path(OUT, "p1.rds"))
say("=== P1 완료 ===")
