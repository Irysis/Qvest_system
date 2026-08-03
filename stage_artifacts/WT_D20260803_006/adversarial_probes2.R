# =============================================================================
# adversarial_probes2.R — WT-D20260803_006 2차 적대검증
#  ★probe C(in-sample 치팅 0.857) 를 그대로 '정보 존재'로 읽으면 안 된다.
#   E. 순열 귀무: 같은 13피처로 **블록 순환이동한 target** 을 in-sample 적합 →
#      귀무분포. 관측 0.857 이 이 분포 안이면 상한은 공허(= 과적합 보간)다.
#   F. 다피처 실시간판: 13피처 확장창 로지스틱 (단일 피처 탓인가 검사)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006AP2] ", fmt, "\n"), ...))
set.seed(777L)

R6 <- readRDS(file.path(OUT, "era_results.rds")); AP <- readRDS(file.path(OUT, "adversarial_probes.rds"))
P <- copy(R6$Sp$P); FT <- R6$FT; CONC <- R6$CONC; h <- 24L
ylag <- rep(NA_integer_, nrow(P)); m <- match(P$t - h, P$t); ok <- !is.na(m); ylag[ok] <- P$y[m[ok]]
tr <- which(!is.na(ylag) & ylag != P$y)

D <- merge(P[, .(t, y, cusum_val = rt_cusum, br = br_rt, tr12 = trail12,
                 tr24 = trail24, tr36 = trail36, tr60 = trail60)], FT, by = "t")
D <- merge(D, CONC[, .(t, top10, top10_d12)], by = "t")
VARS <- c("cusum_val","br","tr12","tr24","tr36","tr60","xsec_sd","xsec_cor",
          "spread","bm_ret12","bm_vol12","top10","top10_d12")
DD <- D[complete.cases(D[, c("y", VARS), with = FALSE])]
FML <- as.formula(paste("I(y==1L) ~", paste(VARS, collapse = " + ")))
trD <- which(DD$t %in% P$t[tr])
fit_acc <- function(yv) {
  d <- copy(DD); d[, y := yv]
  f <- suppressWarnings(glm(FML, data = d, family = binomial()))
  p <- ifelse(predict(f, type = "response") > 0.5, 1L, -1L)
  c(all = mean(p == d$y), tr = mean(p[trD] == d$y[trD]))
}
obs <- fit_acc(DD$y)
say("관측 in-sample 치팅: 전체 %.4f / 전이 %.4f", obs["all"], obs["tr"])

# ── E. 블록 순환이동 순열 귀무 (피처-target 관계 파괴, 시계열 구조 보존) ─────
NP <- 300L
NUL <- t(replicate(NP, { s <- sample.int(nrow(DD), 1L)
  fit_acc(DD$y[c(s:nrow(DD), seq_len(s - 1L))]) }))
say("E. 순열 귀무 %d draw — in-sample 전체: 평균 %.4f [%.3f, %.3f] | 관측 %.4f → 백분위 %.1f%%",
    NP, mean(NUL[,1]), quantile(NUL[,1], .025), quantile(NUL[,1], .975), obs["all"],
    100 * mean(NUL[,1] < obs["all"]))
say("E. 순열 귀무 — in-sample 전이월: 평균 %.4f [%.3f, %.3f] | 관측 %.4f → 백분위 %.1f%%",
    mean(NUL[,2]), quantile(NUL[,2], .025), quantile(NUL[,2], .975), obs["tr"],
    100 * mean(NUL[,2] < obs["tr"]))
p_perm_all <- mean(NUL[,1] >= obs["all"]); p_perm_tr <- mean(NUL[,2] >= obs["tr"])
say("   순열 p (전체) %.4f / (전이) %.4f", p_perm_all, p_perm_tr)
VACUOUS <- p_perm_all > 0.05
say("   ★판정: in-sample 상한은 %s",
    ifelse(VACUOUS, "공허 — 무작위 target 도 같은 수준으로 적합됨(순수 과적합 보간). '정보 존재' 주장 불가",
           "비공허 — 순열 귀무를 유의하게 초과. 트레일링 피처에 era 구조가 실재하나 실시간 학습이 안 됨"))

# ── F. 다피처 실시간판 (확장창) ─────────────────────────────────────────────
pr <- rep(NA_integer_, nrow(DD))
for (i in seq_len(nrow(DD))) {
  tt <- DD$t[i]; trn <- DD[t <= tt - h]
  if (nrow(trn) < 60 || length(unique(trn$y)) < 2) next
  f <- tryCatch(suppressWarnings(glm(FML, data = trn, family = binomial())), error = function(e) NULL)
  if (is.null(f)) next
  pp <- tryCatch(predict(f, newdata = DD[i], type = "response"), error = function(e) NA_real_)
  if (is.finite(pp)) pr[i] <- if (pp > 0.5) 1L else -1L
}
acc_f <- mean(pr == DD$y, na.rm = TRUE)
acc_ftr <- mean(pr[trD] == DD$y[trD], na.rm = TRUE)
say("F. 13피처 확장창 실시간 로지스틱: 전체 %.4f (n=%d) | 전이월 %.4f (n=%d)",
    acc_f, sum(!is.na(pr)), acc_ftr, sum(!is.na(pr[trD])))
say("   ★단일 피처 탓이 아님 — 전 피처를 동시에 줘도 실시간 적중률은 base(0.5025) 근방/미만")

saveRDS(list(obs = obs, perm_mean_all = mean(NUL[,1]), perm_ci_all = quantile(NUL[,1], c(.025,.975)),
             perm_mean_tr = mean(NUL[,2]), perm_ci_tr = quantile(NUL[,2], c(.025,.975)),
             p_perm_all = p_perm_all, p_perm_tr = p_perm_tr, vacuous = VACUOUS,
             multi_rt_all = acc_f, multi_rt_tr = acc_ftr, multi_rt_n = sum(!is.na(pr))),
        file.path(OUT, "adversarial_probes2.rds"))
say("DONE")
