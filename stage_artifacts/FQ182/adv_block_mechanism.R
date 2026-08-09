## 왜 블록을 늘려도 skew se 가 커지지 않는가 — 기전 진단
## 혐의: 부트 se 가 '분포 성질의 표본오차'가 아니라 '단일 극단일이 몇 번 재추출되는가'를 재고 있다.
## 검증 = 극단일 1~2개 제거 후 동일 blk 스윕. 제거 후에도 blk 무반응이면 다른 원인.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[mech] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]; D <- D[!is.na(fwd1)]
say("=== 입력 실측 === %d행 · daily · fwd1 sd %.6f", nrow(D), sd(D$fwd1))

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}

boot_skew_se <- function(x, on, B, blk) {
  nn <- length(x); nb <- ceiling(nn/blk); starts <- seq_len(max(1, nn-blk+1))
  o <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:(k+blk-1))))[1:nn]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob])
  }
  o[is.finite(o)]
}

BLKS <- c(60L, 120L, 250L, 500L, 750L); B <- 800L
res <- list()
for (thr in c(-0.20, -0.30)) {
  on0 <- D$dd252 <= thr
  ## 변형: 원본 / 최대 상방 1일 제거 / 상방 2일 제거 / 1% 윈저화
  xon_ord <- order(D$fwd1 * on0, decreasing = TRUE)
  variants <- list(
    raw   = list(x = D$fwd1, on = on0, keep = rep(TRUE, nrow(D))),
    drop1 = list(x = D$fwd1, on = on0, keep = !(seq_len(nrow(D)) %in% xon_ord[1])),
    drop2 = list(x = D$fwd1, on = on0, keep = !(seq_len(nrow(D)) %in% xon_ord[1:2]))
  )
  q <- quantile(D$fwd1, c(0.01, 0.99), names = FALSE)
  variants$wins1 <- list(x = pmin(pmax(D$fwd1, q[1]), q[2]), on = on0, keep = rep(TRUE, nrow(D)))
  for (vn in names(variants)) {
    v <- variants[[vn]]
    x <- v$x[v$keep]; on <- v$on[v$keep]
    obs <- skew1(x[on]) - skew1(x[!on])
    set.seed(20260812)
    line <- c()
    for (blk in BLKS) {
      bs <- boot_skew_se(x, on, B, blk)
      se <- sd(bs)
      res[[length(res)+1L]] <- data.table(thr = thr*100, variant = vn, blk = blk,
                                          diff = obs, se = se, ratio = abs(obs)/(2*se))
      line <- c(line, sprintf("blk%-3d se %.4f r %.2f", blk, se, abs(obs)/(2*se)))
    }
    say("  thr %.0f%% · %-5s diff %+.4f | %s", thr*100, vn, obs, paste(line, collapse = " | "))
  }
}
M <- rbindlist(res); fwrite(M, file.path(OUT, "adv_block_mechanism.csv"))

say("=== 요약: variant 별 ratio (blk 열) ===")
print(dcast(M, thr + variant ~ blk, value.var = "ratio")[, lapply(.SD, function(z) if (is.numeric(z)) round(z,3) else z)])
say("=== 완료 ===")
