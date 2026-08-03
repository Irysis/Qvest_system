# =============================================================================
# adversarial_probes.R — WT-D20260803_006 Self-Adversarial Challenge 실측
#  A. lag1 스트레스 (BASE 에 우발 누출이 있나)
#  B. placebo (시간순서 파괴 target) — 관측 우위가 잡음인가
#  C. ★in-sample 치팅 상한 — 트레일링 피처 전량으로 **전기간 적합** 로지스틱.
#     내 8 arm 이 약한 설계라서 실패한 것인지, 정보집합 자체의 한계인지 분리한다.
#     (이 arm 은 target 을 보고 계수를 맞추므로 실현 불가 — 상한이지 성과 아님)
#  D. 유효 독립 표본 하에서의 이항 재검정
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006AP] ", fmt, "\n"), ...))
set.seed(4242L)

R6 <- readRDS(file.path(OUT, "era_results.rds"))
Sp <- R6$Sp; P <- copy(Sp$P); FT <- R6$FT; CONC <- R6$CONC
h <- 24L
ylag <- rep(NA_integer_, nrow(P)); m <- match(P$t - h, P$t); ok <- !is.na(m); ylag[ok] <- P$y[m[ok]]
tr <- which(!is.na(ylag) & ylag != P$y)
say("평가 n=%d | 전이 n=%d | BASE 적중 %.4f / 전이 %.4f",
    nrow(P), length(tr), mean(P$p_rt_cusum == P$y), mean(P$p_rt_cusum[tr] == P$y[tr]))

# ── A. lag1 스트레스 ────────────────────────────────────────────────────────
pl <- c(NA_integer_, head(P$p_rt_cusum, -1))
say("A. lag1 스트레스: 적중 %.4f (Δ %+.4f) / 전이 %.4f (Δ %+.4f)",
    mean(pl == P$y, na.rm = TRUE), mean(pl == P$y, na.rm = TRUE) - mean(P$p_rt_cusum == P$y),
    mean(pl[tr] == P$y[tr], na.rm = TRUE),
    mean(pl[tr] == P$y[tr], na.rm = TRUE) - mean(P$p_rt_cusum[tr] == P$y[tr]))
say("   해석: 1개월 지연으로 붕괴하지 않음 = BASE 에 동월 누출 없음 (누출이면 급락해야)")

# ── B. placebo (블록 순환이동 target) ───────────────────────────────────────
pb <- replicate(500L, { s <- sample.int(nrow(P), 1L)
  yp <- P$y[c(s:nrow(P), seq_len(s - 1L))]; mean(P$p_rt_cusum == yp) })
say("B. placebo(순환이동 target) 500 draw: 평균 %.4f [%.3f, %.3f] | 관측 %.4f (백분위 %.1f%%)",
    mean(pb), quantile(pb, .025), quantile(pb, .975), mean(P$p_rt_cusum == P$y),
    100 * mean(pb < mean(P$p_rt_cusum == P$y)))

# ── C. ★in-sample 치팅 상한 ─────────────────────────────────────────────────
D <- merge(P[, .(t, y, cusum_val = rt_cusum, br = br_rt,
                 tr12 = trail12, tr24 = trail24, tr36 = trail36, tr60 = trail60)],
           FT, by = "t")
D <- merge(D, CONC[, .(t, top10, top10_d12)], by = "t")
VARS <- c("cusum_val","br","tr12","tr24","tr36","tr60","xsec_sd","xsec_cor",
          "spread","bm_ret12","bm_vol12","top10","top10_d12")
DD <- D[complete.cases(D[, c("y", VARS), with = FALSE])]
say("C. in-sample 치팅 상한: 피처 %d개 / 관측 %d (전기간 적합, 실현 불가)", length(VARS), nrow(DD))
fit <- suppressWarnings(glm(as.formula(paste("I(y==1L) ~", paste(VARS, collapse=" + "))),
                            data = DD, family = binomial()))
pc <- ifelse(predict(fit, type = "response") > 0.5, 1L, -1L)
trD <- which(DD$t %in% P$t[tr])
say("   전체 적중 %.4f | 전이월 적중 %.4f (n=%d) | base rate %.4f",
    mean(pc == DD$y), mean(pc[trD] == DD$y[trD]), length(trD),
    max(mean(DD$y == 1L), mean(DD$y == -1L)))
say("   ★해석: 이건 target 을 보고 계수를 맞춘 상한이다. 이 상한의 전이월 값조차 낮으면,")
say("     실패는 '내 추정자가 약해서'가 아니라 '트레일링 피처 공간에 전이 정보가 없어서'다.")
# 2차항 + 상호작용 확장 (더 유연한 상한)
fit2 <- suppressWarnings(glm(as.formula(paste("I(y==1L) ~ poly(cusum_val,2) + poly(tr12,2) + poly(tr36,2) +",
        "poly(xsec_cor,2) + poly(top10,2) + poly(bm_ret12,2) + poly(spread,2) + tr12:tr36 + cusum_val:top10")),
        data = DD, family = binomial()))
pc2 <- ifelse(predict(fit2, type = "response") > 0.5, 1L, -1L)
say("   유연 상한(2차항+상호작용): 전체 %.4f | 전이월 %.4f", mean(pc2 == DD$y), mean(pc2[trD] == DD$y[trD]))

# ── D. 유효 독립 표본 이항 재검정 ───────────────────────────────────────────
say("D. 전이 부분집합 재검정")
hit <- as.numeric(P$p_rt_cusum[tr] == P$y[tr])
n_eff <- length(tr) / (h + 12L)
k_eff <- round(mean(hit) * n_eff)
say("   원시 %d/%d = %.4f | 유효 독립 %.1f 시행 환산 %d/%.0f | 이항 p(X<=k|0.5) 원시 %.5f / 유효 %.4f",
    sum(hit), length(hit), mean(hit), n_eff, k_eff, n_eff,
    pbinom(sum(hit), length(hit), 0.5), pbinom(k_eff, round(n_eff), 0.5))
say("   ★정직: 유효 표본 기준 p=%.4f 는 유의하지 않다. 전이 축의 결론은 '방향이 있으나 형식 유의 미달'.",
    pbinom(k_eff, round(n_eff), 0.5))

saveRDS(list(lag1_all = mean(pl == P$y, na.rm=TRUE), lag1_tr = mean(pl[tr]==P$y[tr], na.rm=TRUE),
             placebo_mean = mean(pb), placebo_ci = quantile(pb, c(.025,.975)),
             placebo_pct = 100*mean(pb < mean(P$p_rt_cusum==P$y)),
             cheat_all = mean(pc == DD$y), cheat_tr = mean(pc[trD]==DD$y[trD]),
             cheat2_all = mean(pc2 == DD$y), cheat2_tr = mean(pc2[trD]==DD$y[trD]),
             cheat_n = nrow(DD), cheat_ntr = length(trD), cheat_base = max(mean(DD$y==1L), mean(DD$y==-1L)),
             tr_binom_raw = pbinom(sum(hit), length(hit), 0.5),
             tr_binom_eff = pbinom(k_eff, round(n_eff), 0.5), n_eff = n_eff),
        file.path(OUT, "adversarial_probes.rds"))
say("DONE")
