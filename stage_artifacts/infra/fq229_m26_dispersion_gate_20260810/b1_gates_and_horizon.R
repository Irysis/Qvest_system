## =============================================================================
## FQ-229 (B) — ①검정력 바의 실제 검정력(50% vs 80%) 정정 ②지평 스캔(h=0..3) 스케일/기술
##              ③사전등록 게이트 G1~G4 재료자격 ④위반 주입(무작위 달)
## 사전등록: PREREG.md §2 §4 §6-3 §7-2
## metric_type: canonical_screen_diag. 자본 주장 없음.
## ★A 단계에서 착수게이트 '폐기' — 아래 게이트 수치는 **판정이 아니라 사전등록 보고**다.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[b1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260811L)
source("02_Infrastructure/contracts/required_effect_size.R")
T_THRESH <- 2.0; NWLAG <- 3L; BURN <- 24L; B_INJ <- 2000L
FACS <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "M26_Revenue_Mom")
TARGET <- "M26_Revenue_Mom"

nw_t <- function(x, lag = NWLAG) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- tryCatch(solve(crossprod(X)), error = function(e) NULL); if (is.null(XtXi)) return(NULL)
  b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X * e) / n
  for (l in 1:lag) { w <- 1 - l/(lag + 1)
    G <- crossprod((X*e)[(l+1):n, , drop = FALSE], (X*e)[1:(n-l), , drop = FALSE]) / n
    S <- S + w * (G + t(G)) }
  V <- XtXi %*% (n * S) %*% XtXi; se <- sqrt(pmax(diag(V), 0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y - mean(y))^2))
}

A <- readRDS(file.path(OUT, "a1_results.rds")); DT <- as.data.table(A$DT); setorder(DT, signal_ym)
say("입력: a1 월별 성분 %d개월 · 착수게이트 %s", nrow(DT), if (A$GO) "착수" else "폐기")

## ============================================================ [1] 검정력 바 정정 — 50% vs 80%
say("================ [1] 검정력 바의 실제 검정력 (도구 바 = 50%% power) ================")
say("required_effect 의 바는 '참효과 = t_thresh x se' 이므로 기대 t 가 정확히 %.1f — 즉 **검정력 50%%**다.", T_THRESH)
Z80 <- qnorm(0.80)
se_c <- A$req_full / T_THRESH
for (pw in c(0.50, 0.80, 0.90)) {
  mult <- (T_THRESH + qnorm(pw)) / T_THRESH
  need <- A$req_full * mult
  say("  검정력 %.0f%% ⇒ 필요 기울기 %.6f (바 배수 %.3f) · 외부기준 효과 %+.6f ⇒ %s (비율 %.3f)",
      pw*100, need, mult, A$ext_expected,
      if (abs(A$ext_expected) >= need) "검출 가능" else "★검출 불가", abs(A$ext_expected)/need)
}
obs_c <- A$S1[y == TARGET, c]; obs_se <- A$S1[y == TARGET, se]
say("★관측 기울기 %+.6f · se %.6f ⇒ 0 으로부터 %.2f se · 감쇠함의치 %+.6f 로부터 %.2f se",
    obs_c, obs_se, abs(obs_c)/obs_se, A$ext_expected, abs(A$ext_expected - obs_c)/obs_se)
say("   ⇒ 이 표본은 '의존 없음(0)'과 '동시점 의존이 자기상관만큼 전이(%.6f)'를 **구별하지 못한다**.",
    A$ext_expected)

## ============================================================ [2] 지평 스캔 h=0..3 (스케일 vs 기술)
## ★사전등록 §2 의 S1/S2 정의를 지평만 바꿔 적용 — 자유도 추가 없음. 부모 발견(동시점 t=+4.14)의 재해석.
say("================ [2] 지평 스캔 — 동시점 의존은 스케일인가 기술인가 ================")
HZ <- rbindlist(lapply(0:3, function(h) {
  DT[, xh := if (h == 0L) disp_t else shift(disp_t, h)]
  rbindlist(lapply(c(FACS, "M01"), function(f) {
    r1 <- ols_nw(DT[[f]], DT[, .(xh)]); r2 <- ols_nw(DT[[paste0("ss_", f)]], DT[, .(xh)])
    data.table(h = h, factor = f,
               S1_c = r1[term=="xh", est], S1_t = r1[term=="xh", t], S1_r2 = r1$r2[1],
               S2_c = r2[term=="xh", est], S2_t = r2[term=="xh", t], S2_r2 = r2$r2[1], n = r1$n[1])
  }))
}))
for (h in 0:3) { say("--- h = %d (%s) ---", h, if (h == 0L) "동시점 · 소비 불가" else sprintf("lag%d · 소비 가능", h))
  for (i in which(HZ$h == h)) with(HZ[i], say(
    "  %-18s S1(스케일) c %+.5f t %+.3f R2 %.4f | S2(기술) c %+.5f t %+.3f R2 %.4f",
    factor, S1_c, S1_t, S1_r2, S2_c, S2_t, S2_r2)) }
h0 <- HZ[h == 0L]
say("★★부모 발견 재해석: h=0 에서 S1 유의 축 %d/5 · S2 유의 축 %d/5",
    sum(abs(h0$S1_t) >= T_THRESH), sum(abs(h0$S2_t) >= T_THRESH))
PARENT <- if (sum(abs(h0$S1_t) >= T_THRESH) >= 1 && sum(abs(h0$S2_t) >= T_THRESH) == 0)
  "동시점 disp 의존 = **순수 기계적 스케일** — 표준화 기울기(기술)는 어느 축에서도 분산에 반응하지 않는다" else
  if (sum(abs(h0$S2_t) >= T_THRESH) >= 1) "동시점에 기술 채널 존재 — 축별로 확인" else "동시점 의존 자체가 이 사양에서 미검출"
say("   ⇒ %s", PARENT)
say("   양성 대조 읽기: S1 이 M26 외 축에서도 유의하면 '분산 의존'은 M26 고유 성질이 아니다 (유의 축 = %s)",
    paste(h0[abs(S1_t) >= T_THRESH, factor], collapse = " / "))

## ============================================================ [3] 게이트 구성 (PIT-safe 확장창)
say("================ [3] 사전등록 게이트 G1~G4 구성 ================")
d1 <- DT$disp_lag1; n <- length(d1)
expq <- function(p) { v <- rep(NA_real_, n)
  for (i in seq_len(n)) { h <- d1[1:i]; h <- h[is.finite(h)]
    if (length(h) >= BURN) v[i] <- quantile(h, p, names = FALSE) }; v }
q70 <- expq(0.70); q50 <- expq(0.50); q25 <- expq(0.25); q75 <- expq(0.75)
gz <- DT$g_exp
mk <- function(v, lab) { v[!is.finite(v)] <- 1; list(m = v, lab = lab) }
G1 <- mk(ifelse(is.finite(q70) & d1 >= q70, 1, ifelse(is.finite(q70), 0, NA)), "G1 이진 상위30%")
G2 <- mk(ifelse(is.finite(q50) & d1 >= q50, 1, ifelse(is.finite(q50), 0, NA)), "G2 이진 상위50%")
G3 <- mk(pmin(pmax(1 + 1.0*gz, 0), 2), "G3 연속 선형 λ=1")
g4v <- rep(NA_real_, n)
for (i in seq_len(n)) if (is.finite(q25[i])) g4v[i] <-
  if (d1[i] >= q75[i]) 1.50 else if (d1[i] >= q50[i]) 1.15 else if (d1[i] >= q25[i]) 0.85 else 0.50
G4 <- mk(g4v, "G4 분위 조건부 {0.5,0.85,1.15,1.5}")
GATES <- list(G1, G2, G3, G4)
## 노출 중립화: 확장창 평균(t-1 까지)으로 나눔
neutral <- function(m) { out <- m; run <- 0; cnt <- 0
  for (i in seq_along(m)) { out[i] <- if (cnt > 0 && run/cnt > 1e-9) m[i]/(run/cnt) else m[i]
    run <- run + m[i]; cnt <- cnt + 1 }; out }
for (g in GATES) say("  %-32s 발화(m>0) %3d/%d · mean(m) %.3f · mean(m~) %.3f",
                     g$lab, sum(g$m > 0), n, mean(g$m), mean(neutral(g$m)))

## ============================================================ [4] 재료 자격 — p_t = m~ * b_t
say("================ [4] 재료 자격 (노출 중립화 payoff) — 사전등록 4종 전부 ================")
say("★진단 형태(노출 스케일)다. 소비 주장은 §3 채택 소비면(복합 재가중, c1)에서만 한다.")
mat_row <- function(m, lab, y) {
  mt <- neutral(m); p <- mt * y
  data.table(gate = lab, t_gated = nw_t(p), mean_gated = mean(p), sd_gated = sd(p),
             mean_exposure = mean(mt), t_base = nw_t(y), delta_t = nw_t(p) - nw_t(y))
}
MAT <- rbindlist(lapply(GATES, function(g) mat_row(g$m, g$lab, DT[[TARGET]])))
MAT <- rbind(data.table(gate = "무게이트(기저)", t_gated = nw_t(DT[[TARGET]]), mean_gated = mean(DT[[TARGET]]),
                        sd_gated = sd(DT[[TARGET]]), mean_exposure = 1, t_base = nw_t(DT[[TARGET]]), delta_t = 0), MAT)
for (i in seq_len(nrow(MAT))) with(MAT[i], say(
  "  %-32s t %+.4f (Δt %+.4f) · mean %+.6f · sd %.6f · 평균노출 %.3f", gate, t_gated, delta_t, mean_gated, sd_gated, mean_exposure))
best <- MAT[gate != "무게이트(기저)"][which.max(delta_t)]
say("★재료자격: 최대 개선 %s Δt %+.4f — %s", best$gate, best$delta_t,
    if (best$delta_t > 0) "부호는 개선이나 검정력 폐기 판정 하에서 판정 근거 아님" else "개선 없음")

## 대조축에 동일 게이트 (양성 대조)
say("--- 양성 대조: 동일 게이트를 타 팩터에 ---")
CTLM <- rbindlist(lapply(c(setdiff(FACS, TARGET), "M01"), function(f)
  rbindlist(lapply(GATES, function(g) cbind(factor = f, mat_row(g$m, g$lab, DT[[f]]))))))
for (i in seq_len(nrow(CTLM))) with(CTLM[i], say("  %-18s %-32s Δt %+.4f (t %+.4f → %+.4f)", factor, gate, delta_t, t_base, t_gated))
say("★대조 판정: M26 Δt 최대 %+.4f vs 대조축 Δt 최대 %+.4f ⇒ %s",
    max(MAT[gate != "무게이트(기저)", delta_t]), max(CTLM$delta_t),
    if (max(MAT[gate != "무게이트(기저)", delta_t]) > max(CTLM$delta_t))
      "M26 이 최대 — 그러나 대조축도 같은 방향이면 게이트가 M26 고유성을 재는 게 아니다" else
      "★대조축이 M26 보다 크게 개선 — 게이트는 M26 분산의존이 아니라 다른 것을 잰다")

## ============================================================ [5] 위반 주입 — 무작위 달 선택
say("================ [5] 위반 주입 (무작위 달 게이트, B=%d) ================", B_INJ)
n_on <- sum(G1$m > 0)
obs_dt <- MAT[gate == "G1 이진 상위30%", delta_t]
null_dt <- numeric(B_INJ)
for (b in seq_len(B_INJ)) {
  mm <- rep(0, n); mm[sample.int(n, n_on)] <- 1
  null_dt[b] <- mat_row(mm, "rand", DT[[TARGET]])$delta_t
}
pct <- mean(null_dt <= obs_dt)
say("무작위 달 귀무분포: 중앙 %+.4f · 5%%~95%% [%+.4f, %+.4f] · 관측 G1 Δt %+.4f ⇒ 백분위 %.1f%% (p_우측 %.4f)",
    median(null_dt), quantile(null_dt, .05), quantile(null_dt, .95), obs_dt, pct*100, mean(null_dt >= obs_dt))
say("★주입 판정: %s", if (mean(null_dt >= obs_dt) < 0.05)
  "무작위로는 재현 안 됨 — 게이트가 자유도 이상을 담음" else
  "★무작위 달 선택으로도 같은 크기가 흔히 나온다 — 게이트 효과는 자유도와 구별 안 됨")
say("   ※ 무작위 게이트조차 Δt 중앙 %+.4f — 노출 중립화 payoff 통계 자체가 게이팅에 %s 편향",
    median(null_dt), if (median(null_dt) > 0) "양(+)의" else "음(−)의")

## ============================================================ [6] 저장
fwrite(HZ, file.path(OUT, "b1_horizon_scan.csv"))
fwrite(MAT, file.path(OUT, "b1_material_eligibility.csv"))
fwrite(CTLM, file.path(OUT, "b1_control_gates.csv"))
fwrite(data.table(gate_lab = sapply(GATES, function(g) g$lab),
                  m = I(lapply(GATES, function(g) paste(round(g$m, 4), collapse = ";")))),
       file.path(OUT, "b1_gate_multipliers.csv"))
saveRDS(list(HZ = HZ, MAT = MAT, CTLM = CTLM, PARENT = PARENT, gates = GATES,
             null_dt = null_dt, obs_dt = obs_dt, inj_p = mean(null_dt >= obs_dt),
             neutral = neutral, n_on = n_on), file.path(OUT, "b1_results.rds"))
say("저장 완료 -> %s", OUT)
say("★★[B 요약] 부모 재해석: %s · G 최대 Δt %+.4f · 주입 p %.4f", PARENT,
    max(MAT[gate != "무게이트(기저)", delta_t]), mean(null_dt >= obs_dt))
