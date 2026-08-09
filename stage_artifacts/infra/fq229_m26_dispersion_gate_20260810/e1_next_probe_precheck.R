## =============================================================================
## FQ-229 (E1) — next_probe 사전 확인 (착수 전 read-only 실측이 라운드 설계를 바꾼다)
##  질문: lag1 단일 관측이 잡음이라 실패한 것인가, 아니면 의존 자체가 동시점 전용인가?
##  ★사전등록 판정 아님 — 다음 라운드를 **띄울지 말지** 정하는 precheck 이다. 판정 인용 금지.
##  후보 예측자: 이동평균 분산(3/6/12개월, 전부 lag 처리) · 실현변동성 대리(시장 vol) · disp 예측잔차
## metric_type: precheck_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[e1] ", fmt, "\n"), ...)); flush.console() }
NWLAG <- 3L; T_THRESH <- 2.0
source("02_Infrastructure/contracts/required_effect_size.R")
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- solve(crossprod(X)); b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X*e)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE])/n; S <- S + w*(G+t(G)) }
  V <- XtXi %*% (n*S) %*% XtXi; se <- sqrt(pmax(diag(V),0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y-mean(y))^2)) }

A <- readRDS(file.path(OUT, "a1_results.rds")); DT <- as.data.table(A$DT); setorder(DT, signal_ym)
say("입력: %d개월 · disp_t 중앙 %.4f", nrow(DT), median(DT$disp_t))

## ---- 후보 예측자 (전부 t-1 까지의 정보만) --------------------------------
for (k in c(3, 6, 12)) DT[, (paste0("ma", k)) := shift(frollmean(disp_t, k), 1L)]
say("이동평균 예측자: %s",
    paste(sprintf("ma%d 유효 %d · disp_t 와의 cor %.3f", c(3,6,12),
                  sapply(c("ma3","ma6","ma12"), function(cc) sum(is.finite(DT[[cc]]))),
                  sapply(c("ma3","ma6","ma12"), function(cc) cor(DT$disp_t, DT[[cc]], use="complete.obs"))),
          collapse = " · "))

say("================ 후보 예측자별 S1(스케일) / S2(기술) — precheck ================")
PR <- rbindlist(lapply(c("disp_lag1","ma3","ma6","ma12"), function(px) {
  r1 <- ols_nw(DT[["M26_Revenue_Mom"]], DT[, .(x = get(px))])
  r2 <- ols_nw(DT[["ss_M26_Revenue_Mom"]], DT[, .(x = get(px))])
  ## 예측자→동시점 전이계수 (감쇠 배수)
  ra <- ols_nw(DT$disp_t, DT[, .(x = get(px))])
  data.table(predictor = px, n = r1$n[1], transfer_slope = ra[term=="x", est],
             S1_c = r1[term=="x", est], S1_t = r1[term=="x", t], S1_r2 = r1$r2[1],
             S2_c = r2[term=="x", est], S2_t = r2[term=="x", t], S2_r2 = r2$r2[1],
             req_slope_50 = T_THRESH * r1[term=="x", se],
             req_slope_80 = (T_THRESH + qnorm(0.80)) * r1[term=="x", se],
             ext_expected = A$c_con * ra[term=="x", est]) }))
PR[, ratio_80 := abs(ext_expected)/req_slope_80]
for (i in seq_len(nrow(PR))) with(PR[i], say(
  "  %-10s n=%3d · 동시점 전이계수 %.3f · S1 c %+.5f t %+.3f R2 %.4f | S2 t %+.3f · 외부기대 %+.5f vs 80%%바 %.5f (비율 %.3f)",
  predictor, n, transfer_slope, S1_c, S1_t, S1_r2, S2_t, ext_expected, req_slope_80, ratio_80))
best <- PR[which.max(ratio_80)]
say("★precheck 판정: 80%% 검정력 비율 최대 = %s (%.3f) ⇒ %s", best$predictor, best$ratio_80,
    if (best$ratio_80 >= 1) "이 예측자로는 다음 라운드가 검정력을 갖는다 — 등재 가치 있음"
    else "★어느 lag 예측자도 80%% 검정력 미달 — 같은 표본에서 lag 형태만 바꾸는 라운드는 띄우지 않는다")
say("   ※ 이것은 precheck 이다. 위 t 값들을 판정으로 인용하지 말 것(사전등록 밖 · 4 예측자 동시 조회).")

## ---- 소비면 재분류 재료: 동시점 의존이 쓰일 수 있는 유일한 자리 ----------
say("================ 동시점 의존의 소비 가능 자리 (구조 진단) ================")
say("동시점 disp 는 '그 달 시작 시점'에 미관측이므로 알파 신호로는 소비 불가(C1/C5).")
say("남는 자리는 **사후 귀속/진단**이다: 실현 active 를 disp 로 정규화하면 국면 교락이 걷힌다.")
say("  ⇒ 성과 귀속(Brinson 잔차 해석)·모니터링 임계선의 국면 정규화가 후보 소비면.")
nrm <- DT[is.finite(disp_t), .(signal_ym, b = get("M26_Revenue_Mom"), disp_t)]
nrm[, b_norm := b / disp_t]
nw_t2 <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }
say("  실측: 원계열 t %+.3f · disp 정규화 계열 t %+.3f (정규화가 잡음을 걷으면 t 상승)",
    nw_t2(nrm$b), nw_t2(nrm$b_norm))
say("  ⇒ %s", if (nw_t2(nrm$b_norm) > nw_t2(nrm$b))
  "동시점 분산 정규화가 신호 t 를 올린다 — 사후 귀속/모니터링 축에서 쓸 자리가 있다(예측 아님)"
  else "정규화가 t 를 올리지 않는다 — 이 자리도 비어 있다")

fwrite(PR, file.path(OUT, "e1_next_probe_precheck.csv"))
saveRDS(list(PR = PR, t_raw = nw_t2(nrm$b), t_norm = nw_t2(nrm$b_norm)),
        file.path(OUT, "e1_results.rds"))
say("저장 완료 -> %s", OUT)
