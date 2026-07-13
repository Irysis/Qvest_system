## ============================================================================
## Kalman TE 추정기 head-to-head (task, 2026-07-13) — risk-research diagnostic
## READ-ONLY. book_state/monitoring/weight 무수정·무제안. 진단 재료만.
## 기존 워크포워드 프레임(te_decompose.R §7) 불변 + Kalman 후보 2종 추가.
##   1) Kalman local-level (log-variance / QML-SV)  — EWMA=정상상태 해
##   2) Kalman TV-beta → TE (β_t 시변 회귀, 잔차분산 + β불확실성 기여)
## 대조군: expand_const / roll36 / ewma94 / ewma97 / regime_cond (재현·수치일치 검증)
## 표준 상태공간 구현: dlm 패키지(dlmMLE/dlmFilter). 자체필터 수기구현 없음.
## R: .R source · 단일스레드 · arrow io(2). 병렬 백필/R17/R18 무간섭(이름 kill 없음).
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(dlm)
}))
setDTthreads(1)
set.seed(47)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
BASE <- file.path(ROOT, "stage_artifacts/te_diag_202607")
OUT  <- file.path(BASE, "kalman_ext")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ---- 데이터: 기존 병합 시계열 재사용(동일 active_rds = book_rds - bm) ----
d <- fread(file.path(BASE, "merged_series.csv"))
setorder(d, date)
a  <- d$active_rds          # 월별 active 수익 (0.1898/0.3324 재현 대상)
bk <- d$book_rds            # 라이브 북 (오버레이 반영)
bm <- d$bm                  # 벤치(계약)
rg <- d$regime
N  <- length(a)
ANN <- sqrt(12)
stopifnot(N >= 265)
cat(sprintf("[load] N=%d  %s ~ %s | full TE=%.4f trail21 TE=%.4f (재현체크)\n",
            N, d$date[1], d$date[N], sd(a)*ANN, sd(a[(N-20):N])*ANN))

## ============================================================================
## 공통 평가 함수 (te_decompose.R §7과 동일 로직 — 지표 불변)
##   s : 월별 σ̂ 예측 시계열 (info<=t-1 로 만든 t 시점 예측), 길이 N
##   ok_set: 평가에 쓸 공통 인덱스(finite & s>0) — head-to-head 는 공통집합 사용
## ============================================================================
eval_estimator <- function(s, a, N, restrict = NULL) {
  ok <- which(is.finite(s) & s > 0)
  if (!is.null(restrict)) ok <- intersect(ok, restrict)
  z <- a[ok] / s[ok]                       # 표준화 잔차 (예측 정확 시 var=1)
  ratio <- sqrt(mean(z^2))                 # 실현/예측 분산비 (>1 = 과소예측)
  br <- 0; cnt <- 0                         # 12m 실현TE / 예측TE >1.5 오경보율
  for (t in ok) if (t + 11 <= N) {
    realTE <- sd(a[t:(t+11)]); if (realTE / s[t] > 1.5) br <- br + 1; cnt <- cnt + 1
  }
  list(n_eval = length(ok),
       realized_over_pred = ratio,
       pct_z_gt1 = mean(abs(z) > 1),
       alert_1p5_rate = if (cnt > 0) br / cnt else NA_real_,
       current_TE_forecast_ann = s[N] * ANN,
       z = z, ok = ok, s = s)
}

## ============================================================================
## [1] 대조군 5종 재현 (te_decompose.R §7 그대로 — 수치 일치 검증)
## ============================================================================
ewma_sig <- function(a, lam) {                 # PIT: t-1 까지
  s <- rep(NA_real_, N); v <- var(a[1:12])
  for (t in 13:N) { v <- lam * v + (1 - lam) * a[t-1]^2; s[t] <- sqrt(v) }; s
}
sig_exp <- sig_r36 <- sig_reg <- rep(NA_real_, N)
for (t in 13:N) {
  sig_exp[t] <- sd(a[1:(t-1)])
  sig_r36[t] <- sd(a[max(1, t-36):(t-1)])
  ps <- a[1:(t-1)][rg[1:(t-1)] == rg[t]]
  sig_reg[t] <- if (length(ps) >= 6) sd(ps) else sd(a[1:(t-1)])
}
sig_e94 <- ewma_sig(a, 0.94); sig_e97 <- ewma_sig(a, 0.97)

## ============================================================================
## [2] Kalman local-level (log-variance / QML-SV)  via dlm
##   관측: y'_t = log(a_t^2 + c) + 1.2704   (log χ²_1 평균 -1.2704 보정)
##   상태: h_t = log(σ²_t), h_t = h_{t-1} + ξ_t  (random walk = local level)
##   관측잡음 분산 = π²/2 (log χ²_1 분산, 고정) ; 상태혁신 q = dlmMLE(IS-only, PIT)
##   예측 σ̂²_t = exp(m_{t-1})  (RW 이므로 1-step 예측상태 = 마지막 filtered level)
##   ★ EWMA 관계: local-level 정상상태 칼만이득 K=1-λ ⇒ q/V 비가 implied λ 결정
## ============================================================================
cval <- 0.02 * mean(a^2)                       # Fuller(1996) QMLE-SV 오프셋
y_all <- log(a^2 + cval) + 1.2704
LOGCHI2_V <- pi^2 / 2                           # ≈ 4.9348

build_LL <- function(parm) dlmModPoly(order = 1, dV = LOGCHI2_V, dW = exp(parm))
BURN <- 36                                       # Kalman MLE 최소 히스토리
sig_kSV <- rep(NA_real_, N)
implied_lambda <- rep(NA_real_, N)
q_path <- rep(NA_real_, N)
last_par <- log(0.05)
for (t in (BURN+1):N) {
  yh <- y_all[1:(t-1)]
  fit <- tryCatch(
    dlmMLE(yh, parm = last_par, build = build_LL, method = "Brent",
           lower = -18, upper = 4),
    error = function(e) NULL)
  if (!is.null(fit) && fit$convergence == 0) last_par <- fit$par
  q_hat <- exp(last_par)
  mod <- build_LL(last_par)
  filt <- tryCatch(dlmFilter(yh, mod), error = function(e) NULL)
  if (is.null(filt)) next
  h_pred <- tail(as.numeric(filt$m), 1)         # m_{t-1|t-1} = 1-step 예측상태(RW)
  sig_kSV[t] <- sqrt(exp(h_pred))
  q_path[t] <- q_hat
  # implied EWMA λ: local-level 정상상태  K = (-q + sqrt(q^2+4qV))/(2V), λ=1-K
  Kss <- (-q_hat + sqrt(q_hat^2 + 4 * q_hat * LOGCHI2_V)) / (2 * LOGCHI2_V)
  implied_lambda[t] <- 1 - Kss
}
cat(sprintf("[kSV] 현 vintage q=%.4g  implied λ=%.4f (cf. 손설정 0.97)\n",
            q_path[N], implied_lambda[N]))

## ============================================================================
## [3] Kalman TV-beta → TE  via dlm 동적회귀
##   book_t = α_t + β_t·bm_t + e_t ,  e_t~N(0,σ_e²)
##   (α_t, β_t)' random walk : dW = diag(σ_α², σ_β²) ; MLE(IS-only, stride 12, PIT)
##   ex-ante TE² (월) = σ_e² + (β̂-1)²·v̂_bm + P_ββ·m2̂_bm + P_αα
##     · (β̂-1)²·v̂_bm : 시변 노출(오버레이 de-risk)이 벤치변동과 곱해진 체계적 기여
##     · P_ββ·m2̂_bm   : β 불확실성 기여(task 명시)
##   ⇒ 핵심질문: β_t 추적이 오버레이 스위칭 성분(진단 30%)을 자연 흡수하는가
## ============================================================================
build_reg <- function(parm) {
  m <- dlmModReg(X = X_hist, addInt = TRUE, dV = exp(parm[1]))
  diag(m$W) <- c(exp(parm[2]), exp(parm[3])); m
}
sig_kTB <- rep(NA_real_, N)
tb_term_sys  <- rep(NA_real_, N)   # (β-1)²·v_bm  (체계적 노출기여)
tb_term_bunc <- rep(NA_real_, N)   # P_ββ·m2_bm   (β 불확실성)
tb_term_res  <- rep(NA_real_, N)   # σ_e²
tb_term_aunc <- rep(NA_real_, N)   # P_αα
tb_beta      <- rep(NA_real_, N)   # β̂_{t|t-1}
last_par3 <- c(log(var(a[1:24])), log(1e-5), log(1e-4))
STRIDE <- 12
for (t in (BURN+1):N) {
  yb <- bk[1:(t-1)]; xb <- bm[1:(t-1)]
  # 파라미터 MLE: stride 마다 재추정(확장창 IS-only), 사이엔 직전 유지(전부 과거)
  if (((t - (BURN+1)) %% STRIDE) == 0) {
    X_hist <<- xb
    fit3 <- tryCatch(
      dlmMLE(yb, parm = last_par3, build = build_reg,
             method = "L-BFGS-B", lower = rep(-25, 3), upper = rep(2, 3),
             control = list(maxit = 120)),
      error = function(e) NULL)
    if (!is.null(fit3) && fit3$convergence == 0) last_par3 <- fit3$par
  }
  X_hist <<- xb
  mod <- build_reg(last_par3)
  filt <- tryCatch(dlmFilter(yb, mod), error = function(e) NULL)
  if (is.null(filt)) next
  nrw <- nrow(filt$m)
  m_last <- as.numeric(filt$m[nrw, ])                       # (α,β) filtered @ t-1
  C_last <- dlmSvd2var(filt$U.C[[nrw]], filt$D.C[nrw, ])    # 필터공분산 C_{t-1}
  R_t <- C_last + mod$W                                     # 예측공분산 R_t (RW)
  b_hat <- m_last[2]; a_hat <- m_last[1]
  Pbb <- R_t[2, 2]; Paa <- R_t[1, 1]
  se2 <- exp(last_par3[1])
  vbm  <- var(bm[1:(t-1)]); m2bm <- mean(bm[1:(t-1)]^2)
  sys  <- (b_hat - 1)^2 * vbm
  bunc <- Pbb * m2bm
  var_act <- se2 + sys + bunc + Paa
  sig_kTB[t] <- sqrt(max(var_act, 1e-12))
  tb_term_sys[t] <- sys; tb_term_bunc[t] <- bunc
  tb_term_res[t] <- se2; tb_term_aunc[t] <- Paa; tb_beta[t] <- b_hat
}
cat(sprintf("[kTB] 현 vintage β̂=%.3f  TE월분해: res=%.2e sys=%.2e βunc=%.2e αunc=%.2e\n",
            tb_beta[N], tb_term_res[N], tb_term_sys[N], tb_term_bunc[N], tb_term_aunc[N]))

## ============================================================================
## [4] 재현 검증 + head-to-head 평가
## ============================================================================
est_all <- list(expand_const = sig_exp, roll36 = sig_r36,
                ewma94 = sig_e94, ewma97 = sig_e97, regime_cond = sig_reg,
                kalman_SV = sig_kSV, kalman_TVbeta = sig_kTB)

## (a) 재현: 대조군은 원 프레임(t>=13 native) 으로 저장 CSV 와 일치 확인
saved <- fread(file.path(BASE, "walkforward_estimator_eval.csv"))
repro <- rbindlist(lapply(c("expand_const","roll36","ewma94","ewma97","regime_cond"),
  function(nm){ e <- eval_estimator(est_all[[nm]], a, N)
    data.table(estimator=nm, alert_native=e$alert_1p5_rate, ratio_native=e$realized_over_pred) }))
repro <- merge(repro, saved[, .(estimator, alert_saved=alert_1p5_rate,
              ratio_saved=realized_over_pred)], by="estimator", sort=FALSE)
repro[, alert_match := abs(alert_native - alert_saved) < 1e-9]
repro[, ratio_match := abs(ratio_native - ratio_saved) < 1e-9]
cat("\n===== [재현 검증] 대조군 native(t>=13) vs 저장 CSV =====\n")
print(repro[, lapply(.SD, function(x) if(is.numeric(x)) round(x,6) else x)])
cat(sprintf("→ 재현 일치: alert %d/5, ratio %d/5\n", sum(repro$alert_match), sum(repro$ratio_match)))

## (b) head-to-head: 공통 평가창(BURN 이후, 모든 추정기 finite) 에서 7종 재산출
fin_mat <- sapply(est_all, function(s) is.finite(s) & s > 0)
common <- which(rowSums(fin_mat) == length(est_all))
common <- common[common >= (BURN+1)]
cat(sprintf("\n===== [head-to-head] 공통 평가창 n=%d (t=%d..%d) =====\n",
            length(common), min(common), max(common)))
ht <- rbindlist(lapply(names(est_all), function(nm){
  e <- eval_estimator(est_all[[nm]], a, N, restrict = common)
  data.table(estimator=nm, n_eval=e$n_eval,
             realized_over_pred=e$realized_over_pred, pct_z_gt1=e$pct_z_gt1,
             alert_1p5_rate=e$alert_1p5_rate, current_TE_forecast_ann=e$current_TE_forecast_ann)
}))
setorder(ht, alert_1p5_rate)
print(ht[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(ht, file.path(OUT, "kalman_headtohead_eval.csv"))

## (c) 페어드 유의성: kalman_SV / kalman_TVbeta vs ewma97 (동일 공통창 z² 페어드)
z97 <- (a[common] / sig_e97[common])^2
paired <- rbindlist(lapply(c("kalman_SV","kalman_TVbeta"), function(nm){
  zk <- (a[common] / est_all[[nm]][common])^2
  dff <- zk - z97                                # <0 이면 예측정확도(분산비) 개선
  tt <- t.test(dff)                              # H0: 평균차=0
  data.table(vs="ewma97", cand=nm,
             mean_z2_cand=mean(zk), mean_z2_ewma97=mean(z97),
             mean_diff=mean(dff), t_stat=unname(tt$statistic), p_value=tt$p.value)
}))
cat("\n===== [페어드 유의성] z² (칸디데이트 - ewma97), 음수=개선 =====\n")
print(paired[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(paired, file.path(OUT, "kalman_paired_vs_ewma97.csv"))

## ============================================================================
## [5] 롤링 예측 vs 실현 곡선 + TV-beta 오버레이 흡수 진단
## ============================================================================
## 실현(전향 12m TE) 대비 각 추정기 예측 TE(ann)
realTE_fwd <- rep(NA_real_, N)
for (t in 1:N) if (t + 11 <= N) realTE_fwd[t] <- sd(a[t:(t+11)]) * ANN
curve <- data.table(date = d$date, realized_fwd12_TE = realTE_fwd,
  pred_ewma97 = sig_e97 * ANN, pred_const = sig_exp * ANN,
  pred_kSV = sig_kSV * ANN, pred_kTVbeta = sig_kTB * ANN,
  beta_TVbeta = tb_beta, exposure = d$exposure)
fwrite(curve, file.path(OUT, "kalman_rolling_curves.csv"))

## TV-beta 흡수 진단: 시변노출 항(β-1)²v_bm 이 실제 오버레이 활동과 동행하는가
## 오버레이 활동 proxy = (1 - exposure) [de-risk 강도]
val <- which(is.finite(tb_term_sys) & is.finite(d$exposure))
cor_sys_derisk <- cor(tb_term_sys[val], (1 - d$exposure)[val])
## kTB 예측이 오버레이-heavy 구간(exposure<0.9)에서 상승하는가
hi_der <- val[d$exposure[val] < 0.9]; lo_der <- val[d$exposure[val] >= 0.9]
cat(sprintf("\n[TV-beta 흡수진단] cor((β-1)²v_bm , de-risk강도)=%.3f | kTB TE ann: de-risk구간=%.4f 완전투자구간=%.4f\n",
            cor_sys_derisk,
            mean(sig_kTB[hi_der], na.rm=TRUE)*ANN, mean(sig_kTB[lo_der], na.rm=TRUE)*ANN))

## 현 vintage 예측 요약(각 추정기 t=N)
vint <- data.table(estimator = names(est_all),
                   current_TE_ann = sapply(est_all, function(s) s[N]*ANN))
cat("\n===== [현 vintage 예측 TE ann] =====\n"); print(vint)

## ============================================================================
## [6] 종합 저장
## ============================================================================
res <- list(
  as_of = "2026-07-13", book = "STR_1715_on_M4_R05_noLayer4_PG2",
  basis = "recon_backtested read-only · diagnostic only (no book/monitoring change)",
  method = "dlm state-space (dlmMLE/dlmFilter); no hand-rolled filter; QMLE-SV offset c=0.02*mean(a^2)",
  reproduction = list(alert_match = sum(repro$alert_match), ratio_match = sum(repro$ratio_match),
                      detail = repro),
  headtohead_common = list(n_common = length(common), t_start = min(common), t_end = max(common),
                           table = ht),
  paired_vs_ewma97 = paired,
  kalman_SV = list(current_q = q_path[N], implied_lambda = implied_lambda[N],
                   current_TE_ann = sig_kSV[N]*ANN, offset_c = cval, burn = BURN),
  kalman_TVbeta = list(current_beta = tb_beta[N], stride = STRIDE,
                       current_TE_ann = sig_kTB[N]*ANN,
                       term_res = tb_term_res[N], term_sys = tb_term_sys[N],
                       term_bunc = tb_term_bunc[N], term_aunc = tb_term_aunc[N],
                       cor_sys_derisk = cor_sys_derisk,
                       te_derisk_zone = mean(sig_kTB[hi_der], na.rm=TRUE)*ANN,
                       te_fullinv_zone = mean(sig_kTB[lo_der], na.rm=TRUE)*ANN),
  current_vintage_TE_ann = as.list(setNames(vint$current_TE_ann, vint$estimator)))
write_json(res, file.path(OUT, "kalman_ext_summary.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("\n[DONE] outputs →", OUT, "\n")
