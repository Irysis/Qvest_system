## FQ-182 P0 — CLAIM + ★내 등재 주장("분산·꼬리는 일간에서 잘 추정된다") 자체 검증
## 혐의: 변동성도 군집한다(vol clustering 은 금융에서 가장 강건한 사실).
##       평균이 에피소드에 묶였듯 분산도 묶이면 FQ-182 는 착수 전 폐기다.
## 검증 = 블록 부트스트랩(블록 60일 = 에피소드 병합 기준)으로 정직한 se 를 얻어 순진 se 와 대조.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

## ---- CLAIM (배정 규약 1조) ----------------------------------------------------
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-182")
own <- paste(Q$entries[[i]]$owner, collapse = " ")
if (grepl("CLAIMED", own) && !grepl("UNCLAIMED", own)) { say("★이미 CLAIMED — 중단"); quit(status = 0) }
Q$entries[[i]]$owner <- "CLAIMED Q-Lead session 2026-08-09 — 분포 형태 축 착수. 완료 시 result_ref 기입."
Q$entries[[i]]$status <- "in_flight_20260809"
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("FQ-182 CLAIMED")

## ---- 입력 ---------------------------------------------------------------------
D <- readRDS(file.path(ROOT, "stage_artifacts/alloc_daily/p0.rds"))$BD
D <- as.data.table(D)[!is.na(dd252) & !is.na(BM_Ret)][order(Date)]
say("=== 입력 실측 === %d일 · %s ~ %s · 관측단위 daily · 수익 sd %.5f",
    nrow(D), min(D$Date), max(D$Date), sd(D$BM_Ret))

## ---- 통계량 정의 (사전 고정) ---------------------------------------------------
skew1 <- function(v) { v<-v[is.finite(v)]; n<-length(v); s<-sd(v); if(n<3||!is.finite(s)||s==0) return(NA_real_); sum((v-mean(v))^3)/n/s^3 }
kurt1 <- function(v) { v<-v[is.finite(v)]; n<-length(v); s<-sd(v); if(n<4||!is.finite(s)||s==0) return(NA_real_); sum((v-mean(v))^4)/n/s^4 - 3 }
stats_of <- function(v) c(mean = mean(v), sd = sd(v), skew = skew1(v), kurt = kurt1(v),
                          p_dn3 = mean(v <= -0.03), p_up3 = mean(v >= 0.03),
                          tail_asym = mean(v >= 0.03) - mean(v <= -0.03))

## ---- ★블록 부트스트랩 (블록 60일) ----------------------------------------------
set.seed(20260809)
block_boot_diff <- function(x, on, B = 400L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk)
  starts <- seq_len(max(1, n - blk + 1))
  out <- matrix(NA_real_, B, 7)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    out[b, ] <- stats_of(xb[ob]) - stats_of(xb[!ob])
  }
  out <- out[complete.cases(out), , drop = FALSE]
  colnames(out) <- names(stats_of(x[1:10]))
  out
}

say("=== ★핵심 검증: 분산·꼬리는 정말 일간 표본에서 추정되는가 ===")
say("  방법 = 블록(60일) 부트스트랩 400회 se vs 순진 se. 비율이 1 에 가까울수록 '일간 표본이 유효'.")
rows <- list()
for (thr in c(-0.10, -0.20, -0.30)) {
  on <- D$dd252 <= thr
  if (sum(on) < 100) next
  obs <- stats_of(D$BM_Ret[on]) - stats_of(D$BM_Ret[!on])
  BB <- block_boot_diff(D$BM_Ret, on, B = 400L, blk = 60L)
  se_boot <- apply(BB, 2, sd, na.rm = TRUE)
  ## 순진 se (독립 가정) — mean/sd 만 해석적으로, 나머지는 비교용 근사
  n1 <- sum(on); n0 <- sum(!on); s <- sd(D$BM_Ret)
  se_naive_mean <- s*sqrt(1/n1 + 1/n0)
  se_naive_sd   <- s/sqrt(2)*sqrt(1/n1 + 1/n0)
  say("  --- dd252 <= %.0f%% (ON %d일 · 부트 유효 %d회) ---", thr*100, n1, nrow(BB))
  say("    지표        관측차이     블록부트se   순진se    관측/2se(부트)")
  for (k in colnames(BB)) {
    nv <- if (k == "mean") se_naive_mean else if (k == "sd") se_naive_sd else NA_real_
    say("    %-10s %+11.5f  %10.5f  %8s  %8.3f", k, obs[[k]], se_boot[[k]],
        if (is.na(nv)) "-" else sprintf("%.5f", nv), abs(obs[[k]])/(2*se_boot[[k]]))
    rows[[length(rows)+1L]] <- data.table(thr = thr*100, stat = k, obs = obs[[k]],
      se_boot = se_boot[[k]], se_naive = nv, ratio = abs(obs[[k]])/(2*se_boot[[k]]))
  }
  say("    ★se 팽창(부트/순진): mean %.2fx · sd %.2fx",
      se_boot[["mean"]]/se_naive_mean, se_boot[["sd"]]/se_naive_sd)
}
R <- rbindlist(rows)

say("=== ★착수 자격 판정 (사전 고정) ===")
say("  규칙: 분포 지표(sd·skew·kurt·tail_asym) 중 **최소 1개**가 ratio >= 1.0 이어야 착수 자격.")
say("        평균(mean) 은 이미 폐기된 축이므로 자격 판정에서 제외한다.")
DS <- R[stat != "mean"]
say("  분포 지표 최대 ratio = %.3f (%s / thr %.0f%%)",
    max(DS$ratio, na.rm=TRUE), DS[which.max(ratio), stat], DS[which.max(ratio), thr])
say("  ratio >= 1.0 인 분포 지표 셀 = %d / %d", DS[ratio >= 1.0, .N], nrow(DS))
ok <- DS[ratio >= 1.0, .N] > 0
say("  ★판정: %s", if (ok) "착수 자격 있음 — 본측정 진행" else "★미달 — 착수 전 폐기")
say("  ★대조: 평균 축 ratio = %.3f (이미 폐기)", R[stat=="mean", max(ratio, na.rm=TRUE)])

fwrite(R, file.path(OUT, "p0_moments.csv"))
saveRDS(list(R = R, D = D, eligible = ok), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
