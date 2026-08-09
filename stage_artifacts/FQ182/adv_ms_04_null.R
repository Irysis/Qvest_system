## FQ-182 적대검증 · STEP 9: ★귀무 시뮬레이션 (mechanical_selection 의 결정적 검사)
## 질문: "왜도 0(또는 상태-무관) 인 인공 계열에서도, 낙폭 경로선택만으로 같은 조건부 왜도차가 나오는가?"
## 귀무 3종 (전부 변동성 군집 + 두꺼운 꼬리 보존, 상태-의존성만 제거):
##   NULL_B  적합 GARCH(1,1) 재귀 + **부호 무작위화**한 표준화잔차 (모집단 왜도 = 0)
##   NULL_D  적합 GARCH(1,1) 재귀 + 경험적 표준화잔차 iid 재표집 (경험 왜도 보존, 상태-의존만 제거)
##   NULL_E  원수익 블록부트(60일) 후 dd252 **재계산** (국소 군집·극단 동반 보존 — 가장 보수적)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv9] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "adv_ms_input.rds"))$D)[order(Date)]
r_obs <- D$BM_Ret; n <- length(r_obs)
say("=== 입력 실측 === n=%d 일간 · %s~%s · sd %.5f", n, as.character(min(D$Date)), as.character(max(D$Date)), sd(r_obs))

skew1 <- function(v){v<-v[is.finite(v)];m<-length(v);s<-sd(v);if(m<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/m/s^3}

## ---- 빠른 우측 롤링최대 (van Herk 블록법) + 참조 대조 --------------------------
rollmax_right <- function(x, k = 252L) {
  m <- length(x); nb <- ceiling(m/k); xp <- c(x, rep(-Inf, nb*k - m))
  M <- matrix(xp, nrow = k)
  A <- apply(M, 2, cummax)
  B <- apply(M[k:1, , drop = FALSE], 2, cummax)[k:1, , drop = FALSE]
  a <- as.vector(A); b <- as.vector(B); out <- numeric(m)
  ii <- k:m; out[ii] <- pmax(b[ii - k + 1L], a[ii]); out[1:(k-1L)] <- cummax(x[1:(k-1L)]); out
}
idx_obs <- cumprod(1 + r_obs)
ref <- data.table::frollapply(idx_obs, 252L, max, align = "right")
mine <- rollmax_right(idx_obs, 252L)
say("  [rollmax 검증] 252+ 구간 max|diff| vs frollapply = %.3e", max(abs(mine[252:n] - ref[252:n])))
dd_of <- function(rr) { ix <- cumprod(1 + rr); ix / rollmax_right(ix, 252L) - 1 }
say("  [dd252 재현 검증] 관측 수익으로 재계산한 dd252 vs 저장본 max|diff|(252+) = %.3e",
    max(abs(dd_of(r_obs)[252:n] - D$dd252[252:n])))

## ---- 관측 통계량 (귀무와 동일 파이프라인으로 재산출) ---------------------------
stat_path <- function(rr, thr_vec = c(-0.20,-0.30), p_vec = NULL) {
  dd <- dd_of(rr); fw <- c(rr[-1], NA_real_)
  keep <- 252:(length(rr)-1L)            # 워밍업 제외 + 마지막 fwd 결측 제외
  dd <- dd[keep]; fw <- fw[keep]
  out <- list()
  for (j in seq_along(thr_vec)) {
    ## (i) 고정 문턱
    on <- dd <= thr_vec[j]
    d1 <- if (sum(on) >= 100 && sum(!on) >= 100) skew1(fw[on]) - skew1(fw[!on]) else NA_real_
    ## (ii) n-정합 문턱 (경계 동수 → 표본크기 교락 제거)
    d2 <- NA_real_; non2 <- NA_integer_
    if (!is.null(p_vec)) {
      q <- quantile(dd, p_vec[j], names = FALSE)
      on2 <- dd <= q
      non2 <- sum(on2)
      if (sum(on2) >= 100 && sum(!on2) >= 100) d2 <- skew1(fw[on2]) - skew1(fw[!on2])
    }
    out[[j]] <- c(diff_fixed = d1, n_on_fixed = sum(on), diff_matched = d2, n_on_matched = non2)
  }
  out
}
OBS <- stat_path(r_obs, c(-0.20,-0.30), NULL)
n_on_obs <- vapply(OBS, function(z) z[["n_on_fixed"]], numeric(1))
p_on <- n_on_obs / (n - 252)             # 귀무의 n-정합 비율
OBS <- stat_path(r_obs, c(-0.20,-0.30), p_on)
say("=== 관측 (귀무와 동일 파이프라인) ===")
for (j in 1:2) say("  thr %.0f%%: diff_fixed %+0.4f (n_on %d) · diff_matched %+0.4f (n_on %d, p_on %.4f)",
                   c(-20,-30)[j], OBS[[j]][["diff_fixed"]], OBS[[j]][["n_on_fixed"]],
                   OBS[[j]][["diff_matched"]], OBS[[j]][["n_on_matched"]], p_on[j])

## ---- GARCH 적합 (대칭 std-t) ---------------------------------------------------
suppressPackageStartupMessages(library(rugarch))
G <- readRDS(file.path(OUT, "adv_ms_garchfit.rds"))
cf <- G$coef; z_emp <- G$z[is.finite(G$z)]
say("=== GARCH(1,1)-t 계수 === mu %.6g · omega %.6g · alpha %.6g · beta %.6g · shape %.4g · (a+b)=%.5f",
    cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], cf[["shape"]], cf[["alpha1"]]+cf[["beta1"]])
say("  경험 표준화잔차 z: n=%d · sd %.4f · skew %+0.4f", length(z_emp), sd(z_emp), skew1(z_emp))

sim_garch <- function(z_draw, burn = 500L) {
  N <- n + burn; s2 <- numeric(N); e <- numeric(N)
  s2[1] <- var(r_obs); e[1] <- sqrt(s2[1]) * z_draw[1]
  for (i in 2:N) { s2[i] <- cf[["omega"]] + cf[["alpha1"]]*e[i-1]^2 + cf[["beta1"]]*s2[i-1]
                   e[i] <- sqrt(s2[i]) * z_draw[i] }
  (cf[["mu"]] + e)[(burn+1):N]
}
blockboot <- function(x, blk = 60L) {
  m <- length(x); nb <- ceiling(m/blk); st <- sample.int(m-blk+1L, nb, replace = TRUE)
  as.numeric(unlist(lapply(st, function(k) x[k:(k+blk-1L)])))[1:m]
}

B <- 500L; set.seed(20260809)
NULLS <- c("NULL_B_signflip_garch", "NULL_D_iidshape_garch", "NULL_E_blockboot_raw")
store <- list()
for (nm in NULLS) {
  M <- matrix(NA_real_, B, 6)
  t0 <- Sys.time()
  for (b in seq_len(B)) {
    rr <- switch(nm,
      NULL_B_signflip_garch = sim_garch(sample(z_emp, n+500L, TRUE) * sample(c(-1,1), n+500L, TRUE)),
      NULL_D_iidshape_garch = sim_garch(sample(z_emp, n+500L, TRUE)),
      NULL_E_blockboot_raw  = blockboot(r_obs, 60L))
    S <- stat_path(rr, c(-0.20,-0.30), p_on)
    M[b, ] <- c(S[[1]][["diff_fixed"]], S[[1]][["n_on_fixed"]], S[[1]][["diff_matched"]],
                S[[2]][["diff_fixed"]], S[[2]][["n_on_fixed"]], S[[2]][["diff_matched"]])
  }
  colnames(M) <- c("d20_fixed","non20","d20_matched","d30_fixed","non30","d30_matched")
  store[[nm]] <- M
  say("--- %s (%d회 · %.0f초) ---", nm, B, as.numeric(difftime(Sys.time(), t0, units="secs")))
  say("    고정문턱 ON일수: 관측 %d/%d vs 귀무 median %.0f/%.0f (유효 %d/%d)",
      n_on_obs[1], n_on_obs[2], median(M[,"non20"],na.rm=TRUE), median(M[,"non30"],na.rm=TRUE),
      sum(is.finite(M[,"d20_fixed"])), sum(is.finite(M[,"d30_fixed"])))
  for (tag in c("d20_matched","d30_matched","d20_fixed","d30_fixed")) {
    v <- M[, tag]; v <- v[is.finite(v)]
    ob <- switch(tag, d20_matched = OBS[[1]][["diff_matched"]], d20_fixed = OBS[[1]][["diff_fixed"]],
                      d30_matched = OBS[[2]][["diff_matched"]], d30_fixed = OBS[[2]][["diff_fixed"]])
    if (!length(v)) next
    pr <- mean(v >= ob); p2 <- mean(abs(v - median(v)) >= abs(ob - median(v)))
    say("    %-12s 관측 %+0.4f | 귀무 mean %+0.4f sd %0.4f | q05 %+0.4f q50 %+0.4f q95 %+0.4f q99 %+0.4f | P(귀무>=관측)=%.4f 양측p=%.4f %s",
        tag, ob, mean(v), sd(v), quantile(v,.05,names=FALSE), quantile(v,.50,names=FALSE),
        quantile(v,.95,names=FALSE), quantile(v,.99,names=FALSE), pr, p2,
        if (pr > 0.05) "★귀무 안 → 반증" else "귀무 밖")
  }
}

## ---- 결과 저장 -----------------------------------------------------------------
rows <- list()
for (nm in names(store)) { M <- store[[nm]]
  for (tag in c("d20_fixed","d20_matched","d30_fixed","d30_matched")) {
    v <- M[,tag]; v <- v[is.finite(v)]; if (!length(v)) next
    ob <- switch(tag, d20_matched=OBS[[1]][["diff_matched"]], d20_fixed=OBS[[1]][["diff_fixed"]],
                      d30_matched=OBS[[2]][["diff_matched"]], d30_fixed=OBS[[2]][["diff_fixed"]])
    rows[[length(rows)+1L]] <- data.table(null_model=nm, stat=tag, obs=ob, n_sim=length(v),
      null_mean=mean(v), null_sd=sd(v), q05=quantile(v,.05,names=FALSE), q50=quantile(v,.50,names=FALSE),
      q95=quantile(v,.95,names=FALSE), q99=quantile(v,.99,names=FALSE),
      p_one_sided=mean(v>=ob), p_two_sided=mean(abs(v-median(v))>=abs(ob-median(v))),
      inside_null = mean(v>=ob) > 0.05) } }
NR <- rbindlist(rows); fwrite(NR, file.path(OUT, "adv_mechanical_selection_null.csv"))
saveRDS(list(store=store, OBS=OBS, p_on=p_on), file.path(OUT, "adv_ms_null.rds"))
say("")
say("=== ★귀무 시뮬 요약 ===")
print(NR[, .(null_model, stat, obs=round(obs,4), null_sd=round(null_sd,4), q95=round(q95,4),
             p_one=round(p_one_sided,4), inside_null)])
say("=== STEP 9 완료 ===")
