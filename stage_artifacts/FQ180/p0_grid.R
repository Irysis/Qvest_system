## FQ-180 — 국면-조건부 선별 레인의 **실행가능 영역 지도** (착수 전 폐기 판정)
## ★원 프레이밍 갱신: FQ-178 이 병목을 '검정력' → '효과 크기' 로 바꿨다.
##   따라서 질문은 "어떤 문턱이 검정력을 주나" 가 아니라
##   "**어떤 신호정의·문턱에서도 관측 효과가 자기 MDE 를 넘지 못하나**" 다.
## 이 라운드는 메타-절차다 — 새 가설을 검정하지 않는다. sweep 이나 **챔피언 선택 금지**.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ180")
say  <- function(fmt, ...) { cat(sprintf(paste0("[g] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D0 <- readRDS(file.path(ROOT, "stage_artifacts/FQ178/p0.rds"))
IC <- as.data.table(D0$IC)[order(Date)]
say("=== 입력 실측 === spread_IC 계열 %d개월 · %s ~ %s · spread mean %+.4f sd %.4f",
    nrow(IC), min(IC$Date), max(IC$Date), mean(IC$spread), sd(IC$spread))

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
B <- as.data.table(P$bench)[!is.na(BM_Ret)][order(Date)]
B[, r := shift(BM_Ret, 1L)]
rr <- ifelse(is.na(B$r), 0, B$r); nav <- cumprod(1 + rr); n <- nrow(B)
dd <- function(w) { z <- rep(NA_real_, n); for (i in w:n) z[i] <- nav[i]/max(nav[(i-w+1):i]) - 1; z }
cum <- function(w) { z <- rep(NA_real_, n); for (i in w:n) z[i] <- prod(1 + rr[(i-w+1):i]) - 1; z }
vol12 <- frollapply(rr, 12, sd, fill = NA)
SIG <- data.table(Date = B$Date, mret = rr, cum3 = cum(3), cum6 = cum(6),
                  dd12 = dd(12), dd24 = dd(24), dd36 = dd(36))
SIG[, ddvol := dd12 / pmax(vol12, 1e-6)]
say("  신호 정의 %d종: %s", ncol(SIG)-1L, paste(setdiff(names(SIG),"Date"), collapse=", "))

hac_lm <- function(y, x, lag = 6L) {
  n <- length(y); X <- cbind(1, x)
  b <- solve(crossprod(X), crossprod(X, y)); e <- as.numeric(y - X %*% b)
  Xi <- solve(crossprod(X)); S <- crossprod(X * e)
  for (l in seq_len(lag)) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE]); S <- S + w*(G+t(G)) }
  V <- Xi %*% S %*% Xi
  list(b = as.numeric(b)[2], se = sqrt(diag(V))[2], t = as.numeric(b)[2]/sqrt(diag(V))[2], n = n)
}
n_episodes <- function(on) { r <- rle(on); sum(r$values) }

SIGN <- setdiff(names(SIG), "Date")
rows <- list()
for (s in SIGN) {
  M <- merge(IC[, .(Date, spread)], SIG[, .(Date, v = shift(get(s), 1L))], by = "Date")
  M <- M[is.finite(v) & is.finite(spread)]
  if (nrow(M) < 60) { say("  %s: n<60 — 제외 기록", s); next }
  ## (a) 연속
  f <- hac_lm(M$spread, M$v, 6L)
  eff <- abs(f$b) * sd(M$v)            # 1sd 변화당 효과
  mde <- 2 * f$se * sd(M$v)
  rows[[length(rows)+1L]] <- data.table(signal = s, mode = "continuous", thr_pct = NA_real_,
    n = f$n, n_on = NA_integer_, n_epi = NA_integer_, effect = eff, mde = mde,
    ratio = eff/mde, t = f$t)
  ## (b) 이분 — 신호 하위 백분위 문턱 grid
  for (q in c(0.05, 0.10, 0.20, 0.30, 0.40)) {
    thr <- quantile(M$v, q, na.rm = TRUE)
    on <- M$v <= thr
    if (sum(on) < 8 || sum(!on) < 30) next
    d1 <- mean(M$spread[on]) - mean(M$spread[!on])
    se <- sd(M$spread) * sqrt(1/sum(on) + 1/sum(!on)) * 1.25
    ne <- n_episodes(on)
    ## 에피소드-클러스터 보정: se 를 sqrt(n_on/n_epi) 배 팽창
    se_cl <- se * sqrt(max(1, sum(on)/max(1, ne)))
    rows[[length(rows)+1L]] <- data.table(signal = s, mode = "binary", thr_pct = q*100,
      n = nrow(M), n_on = sum(on), n_epi = ne, effect = abs(d1), mde = 2*se_cl,
      ratio = abs(d1)/(2*se_cl), t = d1/se_cl)
  }
}
G <- rbindlist(rows)
setorder(G, -ratio)
say("=== 실행가능 영역 지도 (%d 셀) — ratio = 관측효과 / 자기 MDE ===", nrow(G))
print(G[, .(signal, mode, thr_pct, n_on, n_epi, effect = round(effect,4),
            mde = round(mde,4), ratio = round(ratio,3), t = round(t,3))])

say("=== ★판정 (사전 고정 규칙) ===")
say("  규칙: 전 그리드에서 max(ratio) < 1.0 이면 **이 측정 프레임 구성상 닫힘**.")
say("        ratio >= 1.0 셀이 있으면 그것은 **승격 후보가 아니라 다음 사전등록 대상**이다(sweep 이므로).")
mx <- G[which.max(ratio)]
say("  max ratio = %.3f  (%s / %s / thr %s)", mx$ratio, mx$signal, mx$mode,
    if (is.na(mx$thr_pct)) "-" else sprintf("%.0f%%", mx$thr_pct))
say("  ratio >= 1.0 셀 수 = %d / %d", G[ratio >= 1.0, .N], nrow(G))
verdict <- if (G[, max(ratio)] < 1.0) "LANE_CONFIG_CLOSED" else "OPEN_CELLS_EXIST"
say("  ★판정: %s", verdict)

say("=== 에피소드 수 ↔ 효과 크기 트레이드오프 (이분 셀만) ===")
BI <- G[mode == "binary"]
if (nrow(BI)) {
  say("  문턱을 낮추면 에피소드는 늘지만 효과가 희석되는가?")
  print(BI[, .(mean_epi = round(mean(n_epi),1), mean_effect = round(mean(effect),4),
               mean_ratio = round(mean(ratio),3)), by = thr_pct][order(thr_pct)])
  say("  cor(n_epi, effect) = %+.3f · cor(n_epi, ratio) = %+.3f",
      cor(BI$n_epi, BI$effect), cor(BI$n_epi, BI$ratio))
  say("  ★해석: cor(n_epi, effect) 가 음수면 '에피소드를 늘리면 효과가 희석' = 트레이드오프 실재.")
}
say("=== 연속 vs 이분 (같은 신호 안에서) ===")
CM <- merge(G[mode=="continuous", .(signal, ratio_cont = ratio)],
            G[mode=="binary", .(ratio_bin_max = max(ratio)), by = signal], by = "signal")
print(CM[, .(signal, ratio_cont = round(ratio_cont,3), ratio_bin_max = round(ratio_bin_max,3),
             cont_better = ratio_cont > ratio_bin_max)])

fwrite(G, file.path(OUT, "feasibility_grid.csv"))
saveRDS(list(grid = G, verdict = verdict), file.path(OUT, "p0.rds"))
say("=== FQ-180 지도 완료 → feasibility_grid.csv ===")
