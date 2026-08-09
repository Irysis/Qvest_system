## FQ-178+179 P1 — 1급 판정: spread_IC[t+1] ~ d[t], HAC(NW lag6)
## 사전등록: preregistration.json (측정 전 작성, 성분·심도정의·lag 전부 고정)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ178")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
say("사전등록 파싱 OK — 처분규칙 %d", length(PRE$disposition_rules_fixed_before_results))
D0 <- readRDS(file.path(OUT, "p0.rds")); M <- as.data.table(D0$M)
say("=== 입력 실측 === 회귀표 %d행 · %s ~ %s", nrow(M), min(M$Date), max(M$Date))
stopifnot(nrow(M) == 281L)

## HAC(Newey-West) — 자체합성 아님(표준 분산추정). lag 는 사전등록 6 고정.
hac_lm <- function(y, x, lag = 6L) {
  n <- length(y); X <- cbind(1, x)
  b <- solve(crossprod(X), crossprod(X, y))
  e <- as.numeric(y - X %*% b)
  XtX_inv <- solve(crossprod(X))
  S <- crossprod(X * e)                       # lag 0
  for (l in seq_len(lag)) {
    w <- 1 - l/(lag + 1)
    Xe1 <- (X * e)[(l+1):n, , drop = FALSE]; Xe0 <- (X * e)[1:(n-l), , drop = FALSE]
    G <- crossprod(Xe1, Xe0)
    S <- S + w * (G + t(G))
  }
  V <- XtX_inv %*% S %*% XtX_inv
  list(coef = as.numeric(b), se = sqrt(diag(V)), t = as.numeric(b)/sqrt(diag(V)), n = n, resid = e)
}

say("=== ★1급 판정: spread_IC[t+1] ~ d[t] ===")
fit <- hac_lm(M$spread, M$d_lag, lag = 6L)
b1 <- fit$coef[2]; se1 <- fit$se[2]; t1 <- fit$t[2]; MDE <- 2 * se1
sd_d <- sd(M$d_lag)
say("  b1 = %+.4f · HAC se %.4f · **t = %+.3f** · n %d", b1, se1, t1, fit$n)
say("  MDE(=2*se) = %.4f · 관측 |b1| = %.4f · |b1|/MDE = %.2f", MDE, abs(b1), abs(b1)/MDE)
say("  심도 1sd(%.3f) 변화당 spread 변화 = %+.4f (spread sd %.4f 의 %.2f배)",
    sd_d, b1*sd_d, sd(M$spread), abs(b1*sd_d)/sd(M$spread))
say("  절편 b0 = %+.4f (t %+.2f) — 심도 0 에서의 기저 spread", fit$coef[1], fit$t[1])

## 사전등록 처분 규칙 적용
sig <- abs(t1) >= 2.0
dirok <- b1 < 0
verdict <- if (sig && dirok) "L1_DEPTH_CONDITIONAL_SUPPORTED" else
           if (sig && !dirok) "L2_REVERSED_SIGN" else
           if (abs(b1) >= MDE) "L4_NULL_POWERED" else "L3_INCONCLUSIVE_UNDERPOWERED"
say("  L1 (|t|>=2 ∧ b1<0) : %s", sig && dirok)
say("  L2 (|t|>=2 ∧ b1>0) : %s", sig && !dirok)
say("  L4 (|t|<2 ∧ |b1|>=MDE, 진짜 negative) : %s", !sig && abs(b1) >= MDE)
say("  ★판정: %s", verdict)

say("=== 성분 분해 (2급 진단) ===")
fA <- hac_lm(M$icA, M$d_lag, 6L); fV <- hac_lm(M$icV, M$d_lag, 6L)
say("  icA(quality_growth) ~ d : b %+.4f (t %+.3f)", fA$coef[2], fA$t[2])
say("  icV(value)          ~ d : b %+.4f (t %+.3f)", fV$coef[2], fV$t[2])
say("  ★스프레드 효과의 출처 = %s", if (abs(fA$t[2]) > abs(fV$t[2])) "quality_growth 측" else "value 측")

say("=== 심도 대체 정의 robustness (사전등록 3종) ===")
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
B <- as.data.table(P$bench)[!is.na(BM_Ret)][order(Date)]
B[, r := shift(BM_Ret, 1L)]
rr <- ifelse(is.na(B$r), 0, B$r); nav <- cumprod(1 + rr); n <- nrow(B)
alt <- data.table(Date = B$Date)
c3 <- rep(NA_real_, n); for (i in 3:n) c3[i] <- prod(1 + rr[(i-2):i]) - 1
d24 <- rep(NA_real_, n); for (i in 24:n) d24[i] <- nav[i]/max(nav[(i-23):i]) - 1
vol12 <- frollapply(rr, 12, sd, fill = NA)
alt[, `:=`(cum3 = c3, dd24 = d24, dd12v = D0$M$d_lag[1] * 0)]
B[, dd12 := { z <- rep(NA_real_, n); for (i in 12:n) z[i] <- nav[i]/max(nav[(i-11):i]) - 1; z }]
alt[, ddvol := B$dd12 / pmax(vol12, 1e-6)]
alt[, `:=`(cum3 = c3, dd24 = d24)]
res <- list()
for (k in c("cum3","dd24","ddvol")) {
  A <- merge(M[, .(Date, spread)], alt[, .(Date, v = shift(get(k), 1L))], by = "Date")
  A <- A[is.finite(v) & is.finite(spread)]
  f <- hac_lm(A$spread, A$v, 6L)
  say("  %-6s : b %+.5f · t %+.3f · n %d", k, f$coef[2], f$t[2], f$n)
  res[[k]] <- data.table(def = k, b = f$coef[2], t = f$t[2], n = f$n)
}

say("=== 시대 분할 (2급 — 분할은 검정력 파괴, 재현 실패를 '효과 없음' 으로 읽지 않음) ===")
for (lab in c("2003-2012","2013-2026")) {
  S <- if (lab == "2003-2012") M[Date < as.Date("2013-01-01")] else M[Date >= as.Date("2013-01-01")]
  f <- hac_lm(S$spread, S$d_lag, 6L)
  say("  %s : b %+.4f · t %+.3f · n %d · MDE %.4f · |b|/MDE %.2f",
      lab, f$coef[2], f$t[2], f$n, 2*f$se[2], abs(f$coef[2])/(2*f$se[2]))
}

saveRDS(list(fit = fit, fA = fA, fV = fV, alt = rbindlist(res), verdict = verdict,
             b1 = b1, se1 = se1, t1 = t1, MDE = MDE, sd_d = sd_d), file.path(OUT, "p1.rds"))
say("=== P1 완료 — 판정 %s ===", verdict)
