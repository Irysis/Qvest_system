## FQ-182 P3 — 유일 생존자(변동성 예측성)가 **기존 배관 대비 증분**인가
## 왜: 왜도 반전은 반증 중이고 평균은 비유의다. 남는 건 sd 증가(ratio 2.86~3.53)뿐인데
##   그것은 leverage effect 재확인(교과서)이다. 소비 가치가 있으려면 **기존 입력 대비 증분**이 있어야 한다.
## 이 저장소의 현행 MDD 레버 = β_R05 오버레이. dd252 가 거기에 없는 정보를 주는가?
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]; D <- D[!is.na(fwd1) & !is.na(dd252)]
say("=== 입력 실측 === %d일 · %s ~ %s", nrow(D), min(D$Date), max(D$Date))

## 경쟁 예측자: 과거 실현변동성(가장 단순·표준). dd252 가 이것 위에 증분을 주는가.
D[, rv20 := frollapply(shift(BM_Ret, 1L), 20, sd, fill = NA)]
D[, rv60 := frollapply(shift(BM_Ret, 1L), 60, sd, fill = NA)]
D <- D[!is.na(rv20) & !is.na(rv60)]
D[, absfwd := abs(fwd1)]        # |수익| = 변동성 대용 (표준)
say("  분석표 %d일 · rv20 중앙 %.5f · rv60 중앙 %.5f", nrow(D), median(D$rv20), median(D$rv60))

say("=== 1. 상관 — dd252 는 기존 변동성 지표와 얼마나 겹치나 ===")
say("  cor(dd252, rv20) = %+.3f · cor(dd252, rv60) = %+.3f · cor(rv20, rv60) = %+.3f",
    cor(D$dd252, D$rv20), cor(D$dd252, D$rv60), cor(D$rv20, D$rv60))
say("  ★|상관| 이 높으면 dd252 는 실현변동성의 재표현일 뿐이다.")

say("=== 2. 증분 회귀 — |fwd1| ~ rv20 + rv60 (+ dd252) ===")
nw_t <- function(fit, lag = 20L) {
  X <- model.matrix(fit); e <- residuals(fit); n <- nrow(X)
  Xi <- solve(crossprod(X)); S <- crossprod(X * e)
  for (l in seq_len(lag)) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE]); S <- S + w*(G+t(G)) }
  V <- Xi %*% S %*% Xi; coef(fit)/sqrt(diag(V))
}
f0 <- lm(absfwd ~ rv20 + rv60, data = D)
f1 <- lm(absfwd ~ rv20 + rv60 + dd252, data = D)
t0 <- nw_t(f0); t1 <- nw_t(f1)
say("  기저(rv20+rv60)      : R2 %.4f", summary(f0)$r.squared)
say("  +dd252               : R2 %.4f (ΔR2 %+.5f)", summary(f1)$r.squared,
    summary(f1)$r.squared - summary(f0)$r.squared)
say("  ★dd252 계수 %+.5f · HAC20 t **%+.3f**", coef(f1)[["dd252"]], t1[["dd252"]])
say("  (참고) rv20 t %+.2f · rv60 t %+.2f", t1[["rv20"]], t1[["rv60"]])

say("=== 3. 반대 방향 — dd252 만으로 시작해 rv 를 더하면? (누가 누구를 흡수하나) ===")
g0 <- lm(absfwd ~ dd252, data = D); g1 <- lm(absfwd ~ dd252 + rv20 + rv60, data = D)
say("  dd252 단독            : R2 %.4f", summary(g0)$r.squared)
say("  +rv20+rv60            : R2 %.4f (ΔR2 %+.5f)", summary(g1)$r.squared,
    summary(g1)$r.squared - summary(g0)$r.squared)
say("  ★해석: 한쪽 ΔR2 가 다른 쪽보다 훨씬 크면 그쪽이 정보의 주인이다.")

say("=== 4. 현행 오버레이 입력과의 관계 (배선 확인) ===")
p <- ".cache/unified_regime_signal.parquet"
if (file.exists(p)) {
  U <- as.data.table(read_parquet(p)); U[, Date := as.Date(Date)]
  say("  unified_regime_signal 컬럼: %s", paste(head(names(U), 12), collapse=", "))
  D[, ym := format(Date, "%Y-%m")]; U[, ym := format(Date, "%Y-%m")]
  M <- merge(D[, .(dd_m = mean(dd252), rv_m = mean(rv20)), by = ym],
             U[, .(msm = tail(MSM_Crisis_Prob, 1), rs = tail(Regime_Score, 1)), by = ym], by = "ym")
  M <- M[is.finite(msm) & is.finite(dd_m)]
  say("  월별 병합 %d개월 · cor(dd252, MSM_Crisis_Prob) = %+.3f · cor(dd252, Regime_Score) = %+.3f",
      nrow(M), cor(M$dd_m, M$msm), cor(M$dd_m, M$rs))
  say("  ★현행 국면 엔진 입력과 강하게 상관되면 dd252 는 신규 정보가 아니다.")
} else say("  %s 부재 — 배선 확인 불가로 기록", p)

say("=== ★판정 ===")
inc_ok <- abs(t1[["dd252"]]) >= 2.0 && (summary(f1)$r.squared - summary(f0)$r.squared) > 0.001
say("  dd252 증분 유의(|t|>=2 ∧ ΔR2>0.001): %s", inc_ok)
say("  ⇒ %s", if (inc_ok) "생존자가 증분 정보를 가짐 — 위험모델 소비면 후보" else
   "★생존자(sd 예측성)조차 기존 실현변동성 대비 증분이 없다 — 소비 가치 없음")

saveRDS(list(f0 = f0, f1 = f1, t1 = t1), file.path(OUT, "p3.rds"))
say("=== P3 완료 ===")
