## =============================================================================
## FQ-223 (E) — 자기 적대검증의 정량 부분
##
## 자가제기 concern #7: "수리 arm 의 5월 평균계수가 0.00071 → 0.00420 으로 크게 올랐다.
##   그런데 5월은 n=23(연 1회) 이다. Δt +0.65 가 소수 셀에 얹혀 있으면
##   문턱 단일값 취약성([[project-threshold-single-draw-fragility-20260802]]) 그대로다."
##
## 시험 3종:
##  (1) 블록 부트스트랩(block=12) — Δt 의 분포. 0 을 포함하는가.
##  (2) leave-one-year-out — 한 해를 빼면 Δt 부호가 뒤집히는가.
##  (3) 두 arm 이 **같은 재표본**에서 동시에 문턱 2.0 을 넘는 비율 (판정 안정성).
##
## 읽기 전용. 새 판정 발행 아님 — 기존 판정의 취약성 계측.
## =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[e1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}

CO <- fread(file.path(OUT, "b3_coefs_by_arm.csv"))
say("arm 목록: %s", paste(unique(CO$arm), collapse=" | "))
W <- dcast(CO, signal_ym ~ arm, value.var = "est")
setnames(W, make.names(names(W)))
nm <- names(W); say("컬럼: %s", paste(nm, collapse=" | "))
col_plain <- grep("plain", nm, value = TRUE)[1]
col_ra    <- grep("4.*탐지", nm, value = TRUE)[1]
col_fake  <- grep("7\\.1|FAKE_7", nm, value = TRUE)[1]
if (is.na(col_plain) || is.na(col_ra)) stop("[e1] arm 컬럼 식별 실패 — 중단")
say("식별: plain=%s · RA=%s · FAKE7/1=%s", col_plain, col_ra, col_fake)
W <- W[order(signal_ym)]
W <- W[is.finite(get(col_plain)) & is.finite(get(col_ra))]
n <- nrow(W); say("공통 %d개월", n)
t_p0 <- nw_t(W[[col_plain]]); t_r0 <- nw_t(W[[col_ra]]); d0 <- t_r0 - t_p0
say("관측: t_plain %+.4f · t_RA %+.4f · Δt %+.4f", t_p0, t_r0, d0)

## ---- (1) 블록 부트스트랩 (block = 12개월, 시계열 의존 보존) ----
say("================ (1) 블록 부트스트랩 ================")
B <- 2000L; BL <- 12L; nb <- ceiling(n/BL)
dp <- W[[col_plain]]; dr <- W[[col_ra]]
df <- if (!is.na(col_fake)) W[[col_fake]] else rep(NA_real_, n)
bt <- matrix(NA_real_, B, 3)
for (b in seq_len(B)) {
  st <- sample.int(n - BL + 1L, nb, replace = TRUE)
  idx <- unlist(lapply(st, function(s) s:(s+BL-1L)))[seq_len(n)]
  bt[b,1] <- nw_t(dp[idx]); bt[b,2] <- nw_t(dr[idx])
  bt[b,3] <- if (!all(is.na(df))) nw_t(df[idx]) else NA_real_
}
dbt <- bt[,2] - bt[,1]
say("Δt 부트 분포: 중앙 %+.4f · 5%% %+.4f · 95%% %+.4f · Δt>0 비율 %.4f",
    median(dbt, na.rm=TRUE), quantile(dbt,.05,na.rm=TRUE), quantile(dbt,.95,na.rm=TRUE),
    mean(dbt > 0, na.rm=TRUE))
say("  ⇒ %s", if (quantile(dbt,.05,na.rm=TRUE) > 0) "★90%% 구간이 0 초과 — 개선 방향 안정"
    else "90%% 구간이 0 을 포함 — 개선 방향은 표본의존, 크기 주장 금지")
say("t_RA 부트: 중앙 %+.4f · 5%% %+.4f · ★t>=2.0 비율 %.4f",
    median(bt[,2],na.rm=TRUE), quantile(bt[,2],.05,na.rm=TRUE), mean(bt[,2] >= 2.0, na.rm=TRUE))
say("t_plain 부트: 중앙 %+.4f · 5%% %+.4f · ★t>=2.0 비율 %.4f",
    median(bt[,1],na.rm=TRUE), quantile(bt[,1],.05,na.rm=TRUE), mean(bt[,1] >= 2.0, na.rm=TRUE))
if (!all(is.na(bt[,3])))
  say("FAKE 7/1 부트 Δt: 중앙 %+.4f · 진짜 Δt 가 가짜를 상회하는 재표본 비율 %.4f",
      median(bt[,3]-bt[,1], na.rm=TRUE), mean(dbt > (bt[,3]-bt[,1]), na.rm=TRUE))

## ---- (2) leave-one-year-out ----
say("================ (2) leave-one-year-out ================")
W[, yr := substr(signal_ym, 1, 4)]
loo <- rbindlist(lapply(sort(unique(W$yr)), function(y) {
  s <- W[yr != y]
  data.table(drop_year = y, n = nrow(s), t_plain = nw_t(s[[col_plain]]),
             t_RA = nw_t(s[[col_ra]]), d = nw_t(s[[col_ra]]) - nw_t(s[[col_plain]]))
}))
say("LOO Δt: 중앙 %+.4f · 최소 %+.4f (%s 제외) · 최대 %+.4f · Δt<=0 인 해 %d/%d",
    median(loo$d), min(loo$d), loo[which.min(d), drop_year], max(loo$d), sum(loo$d <= 0), nrow(loo))
say("LOO t_RA: 최소 %+.4f (%s 제외) · t_RA<2.0 인 해 %d/%d",
    min(loo$t_RA), loo[which.min(t_RA), drop_year], sum(loo$t_RA < 2.0), nrow(loo))
say("LOO t_plain: 최소 %+.4f · t_plain<2.0 인 해 %d/%d", min(loo$t_plain), sum(loo$t_plain < 2.0), nrow(loo))
bad <- loo[t_RA < 2.0 | t_plain < 2.0]
if (nrow(bad)) for (i in seq_len(nrow(bad))) with(bad[i], say(
  "  ★취약: %s 제외 시 t_plain %+.3f · t_RA %+.3f", drop_year, t_plain, t_RA))

## ---- (3) 5월 셀 의존도 ----
say("================ (3) 단일 달 의존도 ================")
W[, mon := substr(signal_ym, 6, 7)]
for (m in c("04","05","06")) {
  s <- W[mon != m]
  say("  %s월 제외(n=%d): t_plain %+.4f · t_RA %+.4f · Δt %+.4f", m, nrow(s),
      nw_t(s[[col_plain]]), nw_t(s[[col_ra]]), nw_t(s[[col_ra]]) - nw_t(s[[col_plain]]))
}
say("  ⇒ 4·5월 둘 다 제외해도 Δt 가 남으면 개선이 그 두 달 밖에서도 온 것(6월 등 누출분 수리)")
s2 <- W[!(mon %in% c("04","05"))]
say("  4·5월 동시 제외(n=%d): t_plain %+.4f · t_RA %+.4f · Δt %+.4f",
    nrow(s2), nw_t(s2[[col_plain]]), nw_t(s2[[col_ra]]), nw_t(s2[[col_ra]]) - nw_t(s2[[col_plain]]))

fwrite(loo, file.path(OUT, "e1_loo_by_year.csv"))
fwrite(data.table(boot_delta = dbt, t_plain = bt[,1], t_RA = bt[,2], t_fake = bt[,3]),
       file.path(OUT, "e1_bootstrap_draws.csv"))
saveRDS(list(d0=d0, t_p0=t_p0, t_r0=t_r0, boot_d_q05=quantile(dbt,.05,na.rm=TRUE),
             boot_d_q95=quantile(dbt,.95,na.rm=TRUE), boot_pos=mean(dbt>0,na.rm=TRUE),
             tRA_ge2=mean(bt[,2]>=2.0,na.rm=TRUE), tplain_ge2=mean(bt[,1]>=2.0,na.rm=TRUE), loo=loo),
        file.path(OUT, "e1_results.rds"))
say("저장 완료 → %s", OUT)
