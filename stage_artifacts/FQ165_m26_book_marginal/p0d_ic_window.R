## ============================================================================
## FQ-165 P0d — 두 신호가 **어느 홀딩월을 예측하는가**를 IC 로 실측한다 (라벨 신뢰 금지).
## 배경(P0c): 두 패널의 Ret_1m 컬럼은 panel_month 의 *익월* 실현수익과 cor 0.92~0.96.
##   그런데 북 재현 엔진(phi_sweep_under_overlay.R)은 decision_date=M 에서 **M 월을 보유**한다.
##   ⇒ 컬럼 라벨과 엔진 규약이 어긋나 보이므로, 신호 자신의 예측력으로 판별한다.
## 판별: score_eff(M) 의 rank-IC 를 realized(M) 과 realized(M+1) 에서 각각 잰다.
##   북이 실제로 수익을 내는 창이 어디인지 = 엔진 규약 검증. M26 도 같은 자로 잰다.
## ★이 결과가 M26 을 base 에 붙일 때의 오프셋을 결정한다. 추정 금지 — 실측으로 고정.
## ============================================================================
suppressMessages({library(data.table); library(arrow)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
P <- readRDS(file.path(OUT, "p0_inputs.rds")); ap <- P$ap; m26 <- P$m26; raw <- P$raw

ym <- function(d) as.integer(format(d, "%Y"))*12L + as.integer(format(d,"%m"))
ap[, ymi := ym(Date)]; m26[, ymi := ym(Date)]

trading <- sort(unique(raw$Date))
mo <- data.table(Date = trading)[, ymi := ym(Date)][, .(first_d = min(Date)), by = ymi]
setorder(mo, ymi); mo[, next_first := shift(first_d, -1L)]
mo <- mo[is.finite(as.numeric(next_first))]
REAL <- rbindlist(lapply(seq_len(nrow(mo)), function(i)
  raw[Date > mo$first_d[i] & Date <= mo$next_first[i],
      .(ret_real = prod(1+Ret, na.rm=TRUE)-1), by = Ticker][, ymi := mo$ymi[i]][]))
setkey(REAL, ymi, Ticker)
cat(sprintf("[D0] 실현수익 패널: rows=%d · months=%d (%s~%s)\n", nrow(REAL), uniqueN(REAL$ymi),
            min(mo$ymi), max(mo$ymi)))

nwt <- function(x, L=3){ x <- x[is.finite(x)]; n <- length(x); if(n<10) return(NA_real_)
  m <- mean(x); e <- x-m; s <- sum(e^2)/n
  for (l in 1:L){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(L+1))*ga }
  m/sqrt(s/n) }

probe <- function(sig_dt, sig_col, label) {
  rbindlist(lapply(0:2, function(k) {
    j <- merge(sig_dt[is.finite(get(sig_col)), .(ymi, Ticker, s = get(sig_col))],
               REAL[, .(ymi_r = ymi - k, Ticker, ret_real)],
               by.x = c("ymi","Ticker"), by.y = c("ymi_r","Ticker"))
    ic <- j[, .(ic = if (.N >= 20) suppressWarnings(cor(s, ret_real, method="spearman")) else NA_real_), by = ymi]
    ic <- ic[is.finite(ic)]
    data.table(signal = label, holding_offset = k, n_months = nrow(ic),
               mean_ic = mean(ic$ic), t_nw3 = nwt(ic$ic))
  }))
}

cat("\n=== [D1] 신호 → 홀딩월 오프셋 스캔 (holding_offset=0 이면 decision 월 = 보유월) ===\n")
R <- rbind(probe(ap,  "score_eff",       "base score_eff (STR_1715)"),
           probe(m26, "M26_Revenue_Mom", "M26_Revenue_Mom"))
print(R)
fwrite(R, file.path(OUT, "p0d_ic_window.csv"))

cat("\n[D1] 읽는 법: 각 신호가 최대 IC/t 를 내는 holding_offset 이 그 신호의 **실제 예측 창**이다.\n")
best <- R[, .SD[which.max(fifelse(is.na(t_nw3), -Inf, t_nw3))], by = signal]
print(best)
saveRDS(list(REAL = REAL, scan = R, best = best), file.path(OUT, "p0d_ic_window.rds"))
cat("\n[saved] p0d_ic_window.csv / .rds\n")
