# =============================================================================
# adversarial_probes3.R — WT-D20260803_006 3차 적대검증
#  probe F(13피처 확장창 실시간 0.650 / 전이 0.691)를 그대로 '우위'로 읽으면 안 된다.
#  F 는 학습 최소표본 조건 때문에 **평가 구간이 뒤로 밀린 부분집합**을 본다.
#  그 부분집합의 base rate 와, 같은 부분집합에서의 BASE(RT_CUSUM)/상수규칙을 비교해야
#  'F 가 이겼다'가 성립한다. (부분집합 이동 = 거짓 우위의 고전적 원천)
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006AP3] ", fmt, "\n"), ...))
set.seed(31337L)

R6 <- readRDS(file.path(OUT, "era_results.rds"))
P <- copy(R6$Sp$P); FT <- R6$FT; CONC <- R6$CONC; h <- 24L
ylag <- rep(NA_integer_, nrow(P)); m <- match(P$t - h, P$t); ok <- !is.na(m); ylag[ok] <- P$y[m[ok]]
P[, is_trans := !is.na(ylag) & ylag != P$y]

D <- merge(P[, .(t, Date, y, is_trans, p_rt = p_rt_cusum, cusum_val = rt_cusum, br = br_rt,
                 tr12 = trail12, tr24 = trail24, tr36 = trail36, tr60 = trail60)], FT, by = "t")
D <- merge(D, CONC[, .(t, top10, top10_d12)], by = "t")
VARS <- c("cusum_val","br","tr12","tr24","tr36","tr60","xsec_sd","xsec_cor",
          "spread","bm_ret12","bm_vol12","top10","top10_d12")
DD <- D[complete.cases(D[, c("y", VARS), with = FALSE])]
FML <- as.formula(paste("I(y==1L) ~", paste(VARS, collapse = " + ")))

pr <- rep(NA_integer_, nrow(DD))
for (i in seq_len(nrow(DD))) {
  tt <- DD$t[i]; trn <- DD[t <= tt - h]
  if (nrow(trn) < 60 || length(unique(trn$y)) < 2) next
  f <- tryCatch(suppressWarnings(glm(FML, data = trn, family = binomial())), error = function(e) NULL)
  if (is.null(f)) next
  pp <- tryCatch(predict(f, newdata = DD[i], type = "response"), error = function(e) NA_real_)
  if (is.finite(pp)) pr[i] <- if (pp > 0.5) 1L else -1L
}
ev <- which(!is.na(pr))
S <- DD[ev]; prv <- pr[ev]
say("F 평가 부분집합: n=%d | 기간 %s ~ %s (전체 평가 %d개월 중 뒤쪽 %.0f%%)",
    length(ev), S$Date[1], S$Date[nrow(S)], nrow(DD), 100*length(ev)/nrow(DD))
BRs <- max(mean(S$y == 1L), mean(S$y == -1L))
maj <- if (mean(S$y == 1L) >= 0.5) 1L else -1L
say("★부분집합 base rate(사후 최빈 상수 %+d) = %.4f | 전체 평가구간 base rate = %.4f",
    maj, BRs, max(mean(DD$y==1L), mean(DD$y==-1L)))
say("★같은 부분집합에서:")
say("   F(13피처 실시간)      %.4f", mean(prv == S$y))
say("   BASE(RT_CUSUM)        %.4f", mean(S$p_rt == S$y))
say("   상수규칙(항상 %+d)     %.4f", maj, mean(maj == S$y))
say("   → F vs 상수규칙 Δ %+.4f | F vs BASE Δ %+.4f",
    mean(prv == S$y) - mean(maj == S$y), mean(prv == S$y) - mean(S$p_rt == S$y))
tr <- which(S$is_trans)
say("★전이월(n=%d) 부분집합:", length(tr))
say("   F %.4f | BASE %.4f | 상수규칙 %.4f | 전이월 base rate %.4f",
    mean(prv[tr] == S$y[tr]), mean(S$p_rt[tr] == S$y[tr]), mean(maj == S$y[tr]),
    max(mean(S$y[tr]==1L), mean(S$y[tr]==-1L)))
say("   ★전이월에서 y 는 정의상 이전 창과 다르다 — 그 부분집합의 최빈 클래스 비율이 %.4f 라는 것은",
    max(mean(S$y[tr]==1L), mean(S$y[tr]==-1L)))
say("     '전이월 적중률 %.3f' 가 우위가 아니라 **클래스 불균형 재현**일 수 있음을 뜻한다.",
    mean(prv[tr] == S$y[tr]))
say("   F 예측 분포: +1 %.3f / -1 %.3f | 실제 y +1 %.3f",
    mean(prv == 1L), mean(prv == -1L), mean(S$y == 1L))

# 순열 대조: 같은 파이프라인, target 블록 순환이동 → 실시간 F 의 귀무분포
NP <- 120L
nul <- numeric(NP); nult <- numeric(NP)
for (b in seq_len(NP)) {
  s <- sample.int(nrow(DD), 1L)
  DP <- copy(DD); DP[, y := DD$y[c(s:nrow(DD), seq_len(s-1L))]]
  p2 <- rep(NA_integer_, nrow(DP))
  for (i in seq_len(nrow(DP))) {
    tt <- DP$t[i]; trn <- DP[t <= tt - h]
    if (nrow(trn) < 60 || length(unique(trn$y)) < 2) next
    f <- tryCatch(suppressWarnings(glm(FML, data = trn, family = binomial())), error=function(e) NULL)
    if (is.null(f)) next
    pp <- tryCatch(predict(f, newdata = DP[i], type="response"), error=function(e) NA_real_)
    if (is.finite(pp)) p2[i] <- if (pp > 0.5) 1L else -1L
  }
  e2 <- which(!is.na(p2))
  nul[b] <- mean(p2[e2] == DP$y[e2])
  t2 <- intersect(e2, which(DP$is_trans)); nult[b] <- if (length(t2)) mean(p2[t2] == DP$y[t2]) else NA_real_
}
say("★순열 귀무(실시간 F, %d draw): 전체 평균 %.4f [%.3f, %.3f] | 관측 %.4f → p=%.4f",
    NP, mean(nul), quantile(nul,.025), quantile(nul,.975), mean(prv==S$y), mean(nul >= mean(prv==S$y)))
say("★순열 귀무 전이월: 평균 %.4f [%.3f, %.3f] | 관측 %.4f → p=%.4f",
    mean(nult,na.rm=TRUE), quantile(nult,.025,na.rm=TRUE), quantile(nult,.975,na.rm=TRUE),
    mean(prv[tr]==S$y[tr]), mean(nult >= mean(prv[tr]==S$y[tr]), na.rm=TRUE))

saveRDS(list(n_eval = length(ev), from = S$Date[1], to = S$Date[nrow(S)],
             base_subset = BRs, maj = maj, F_acc = mean(prv==S$y),
             BASE_acc_subset = mean(S$p_rt==S$y), const_acc = mean(maj==S$y),
             F_tr = mean(prv[tr]==S$y[tr]), BASE_tr = mean(S$p_rt[tr]==S$y[tr]),
             const_tr = mean(maj==S$y[tr]), n_tr = length(tr),
             perm_mean = mean(nul), perm_ci = quantile(nul,c(.025,.975)),
             perm_p = mean(nul >= mean(prv==S$y)),
             perm_tr_mean = mean(nult,na.rm=TRUE),
             perm_tr_p = mean(nult >= mean(prv[tr]==S$y[tr]), na.rm=TRUE),
             pred_pos_ratio = mean(prv==1L), y_pos_ratio = mean(S$y==1L)),
        file.path(OUT, "adversarial_probes3.rds"))
say("DONE")
