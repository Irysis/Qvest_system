## FQ-143 P7 — 사전선언 반증축 (b): 라벨은 trailing 변동성 상태의 재진술인가
##   + 필요 정밀도(lift) 정확 역산
## ★분할 금지 — 연속 상호작용(로지스틱)으로 통제. 표본 나누지 않는다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
S <- readRDS(file.path(DIR, "p3.rds")); u <- S$u; bmm <- S$bmm

## trailing 실현변동성 (PIT: 홀딩월 시작 전까지의 일별 수익 12M)
bm <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date); bm[, ym := format(Date,"%Y-%m")]
mv <- bm[, .(sd_m = sd(BM_Ret)*sqrt(21)), by = ym]; setorder(mv, ym)
mv[, tv12 := frollmean(sd_m, 12, align = "right")]        # 당월 포함 12개월 평균 (신호월 = 홀딩월 전월)

d <- merge(u[, .(ym, lab_on)], mv[, .(ym, tv12)], by = "ym")
d <- merge(d, bmm[, .(ym, k = .I)], by = "ym"); setorder(d, k)
d[, k_evt := k + 1L]
d <- merge(d, bmm[, .(k_evt = .I, evt = bm_ret)], by = "k_evt"); setorder(d, k)
d <- d[is.finite(tv12)]
cat(sprintf("[P7-0] 통제 표본 n=%d (%s ~ %s)  ON=%d  <-10%% 사건=%d\n",
            nrow(d), min(d$ym), max(d$ym), sum(d$lab_on), sum(d$evt < -0.10)))
d[, tvz := as.numeric(scale(tv12))]

cat("\n=== [P7-1] 라벨 vs trailing vol — 연속 통제 로지스틱 (사건 = 다음달 시장 < -10%) ===\n")
y <- as.integer(d$evt < -0.10)
m1 <- glm(y ~ lab_on,        data = d, family = binomial())
m2 <- glm(y ~ tvz,           data = d, family = binomial())
m3 <- glm(y ~ tvz + lab_on,  data = d, family = binomial())
pr <- function(m, nm) { s <- summary(m)$coefficients
  cat(sprintf("  %-16s ", nm))
  for (r in rownames(s)[-1]) cat(sprintf("%s: beta=%+.3f z=%+.2f p=%.4f   ", r, s[r,1], s[r,3], s[r,4]))
  cat(sprintf("| AIC=%.1f\n", AIC(m))) }
pr(m1, "라벨 단독"); pr(m2, "vol 단독"); pr(m3, "vol + 라벨")
cat(sprintf("  LR test (라벨의 vol 대비 증분): chisq=%.3f  df=1  p=%.4f\n",
            as.numeric(2*(logLik(m3)-logLik(m2))),
            pchisq(as.numeric(2*(logLik(m3)-logLik(m2))), 1, lower.tail = FALSE)))
cat(sprintf("  LR test (vol 의 라벨 대비 증분): chisq=%.3f  df=1  p=%.4f\n",
            as.numeric(2*(logLik(m3)-logLik(m1))),
            pchisq(as.numeric(2*(logLik(m3)-logLik(m1))), 1, lower.tail = FALSE)))
cat(sprintf("  cor(라벨ON, tvz) = %+.3f\n", cor(as.numeric(d$lab_on), d$tvz)))

cat("\n=== [P7-2] 방향 채널도 같은 통제로 (사건 = 다음달 수익 자체) ===\n")
l1 <- lm(evt ~ lab_on, data = d); l3 <- lm(evt ~ tvz + lab_on, data = d)
cat(sprintf("  E[r] ~ 라벨      : beta=%+.5f  t=%+.2f  p=%.4f\n",
            coef(summary(l1))[2,1], coef(summary(l1))[2,3], coef(summary(l1))[2,4]))
cat(sprintf("  E[r] ~ vol+라벨  : lab beta=%+.5f t=%+.2f p=%.4f | vol beta=%+.5f t=%+.2f p=%.4f\n",
            coef(summary(l3))["lab_onTRUE",1], coef(summary(l3))["lab_onTRUE",3], coef(summary(l3))["lab_onTRUE",4],
            coef(summary(l3))["tvz",1], coef(summary(l3))["tvz",3], coef(summary(l3))["tvz",4]))

cat("\n=== [P7-3] 필요 정밀도(lift) 정확 역산 — 배포창 ===\n")
p2 <- readRDS(file.path(DIR, "p4_panel_labeled.rds")); setDT(p2)
n <- nrow(p2); sdon <- sd(p2$ret_orig[p2$lab_on]); NWI <- 1.25
mu_tail  <- mean(p2$ret_orig[p2$ret_orig < -0.10])     # 꼬리월 평균
mu_rest  <- mean(p2$ret_orig[p2$ret_orig >= -0.10])    # 그 외 평균
base10   <- mean(p2$ret_orig < -0.10)
for (frac in c(0.05, 0.10, 0.20)) {
  k <- round(n*frac); se_apx <- 0.5*sqrt(k/n)*sdon/sqrt(n)*NWI
  need_mu <- -(2.0*se_apx)/(0.5*k/n)                    # 발화집합에 필요한 조건부 평균
  q <- (need_mu - mu_rest)/(mu_tail - mu_rest)          # 필요한 꼬리 정밀도
  cat(sprintf("  발화 %4.1f%%: 필요 E[r|발화]=%+.4f -> 필요 꼬리정밀도 q=%.3f -> 필요 lift=%.1fx (기저 %.4f)\n",
              frac*100, need_mu, q, q/base10, base10))
}
g <- readRDS(file.path(DIR, "p3.rds"))$tab
cat(sprintf("  실측 라벨 lift(<-10%%, C5-clean, 전표본) = %.3fx / 배포창 = 2.135x  ->  필요치 대비 부족\n",
            g[alignment=="B_clean" & event=="ret < -10%"]$lift))
cat("\n[P7 DONE]\n")
