## ============================================================================
## FQ-165 P0c — Ret_1m 컬럼이 **어느 캘린더 월의 수익인가**를 rawdata 로 직접 특정한다.
## 왜: k=0 정렬(base 월초 M ↔ M26 월말 M)은 두 해석이 가능하다 —
##   (해석1) M26 신호는 M 월초 이전 정보로 만들어졌고 Ret_1m 은 M 월 수익 (PIT clean)
##   (해석2) M26 신호는 M 월말 정보로 만들어졌는데 Ret_1m 이 M 월 수익 (동월 look-ahead)
## 라벨(Date/signal_ym)로 판정하지 않는다 — rawdata 실현수익과 대조해 월을 확정하고,
## 그 다음 신호의 vintage 를 별도로 조사한다.
## ============================================================================
suppressMessages({library(data.table); library(arrow)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
P <- readRDS(file.path(OUT, "p0_inputs.rds")); ap <- P$ap; m26 <- P$m26; raw <- P$raw

ym <- function(d) as.integer(format(d, "%Y"))*12L + as.integer(format(d,"%m"))
ap[, ymi := ym(Date)]; m26[, ymi := ym(Date)]

## --- 월별 실현수익 (rawdata, 월 첫 거래일 다음날 ~ 다음달 첫 거래일) ---
trading <- sort(unique(raw$Date))
mo_first <- data.table(Date = trading)[, ymi := ym(Date)][, .(first_d = min(Date)), by = ymi]
setorder(mo_first, ymi)
mo_first[, next_first := shift(first_d, -1L)]

realized <- function(target_ymi) {
  r <- mo_first[ymi == target_ymi]
  if (!nrow(r) || is.na(r$next_first)) return(NULL)
  raw[Date > r$first_d & Date <= r$next_first,
      .(ret_real = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker][, ymi := target_ymi][]
}

test_ymi <- c(ym(as.Date("2010-03-01")), ym(as.Date("2015-07-01")), ym(as.Date("2022-11-01")))
cat("=== [C1] Ret_1m 컬럼의 캘린더 월 특정 (rawdata 실현수익 대조) ===\n")
out <- rbindlist(lapply(test_ymi, function(t0) {
  rbindlist(lapply(-1:1, function(k) {
    rr <- realized(t0 + k); if (is.null(rr)) return(NULL)
    a <- merge(ap[ymi == t0 & is.finite(Ret_1m), .(Ticker, ret_col = Ret_1m)], rr, by = "Ticker")
    m <- merge(m26[ymi == t0 & is.finite(Ret_1m), .(Ticker, ret_col = Ret_1m)], rr, by = "Ticker")
    data.table(panel_ymi = t0,
               panel_month = format(as.Date(sprintf("%d-%02d-01", (t0-1)%/%12, (t0-1)%%12+1)), "%Y-%m"),
               realized_offset = k,
               base_n = nrow(a), base_cor = if(nrow(a)>30) cor(a$ret_col, a$ret_real) else NA_real_,
               base_exact = if(nrow(a)>0) mean(abs(a$ret_col-a$ret_real) < 1e-6) else NA_real_,
               m26_n = nrow(m), m26_cor = if(nrow(m)>30) cor(m$ret_col, m$ret_real) else NA_real_,
               m26_exact = if(nrow(m)>0) mean(abs(m$ret_col-m$ret_real) < 1e-6) else NA_real_)
  }))
}))
print(out)
cat("\n[C1] 읽는 법: realized_offset=0 에서 cor≈1 이면 그 패널의 Ret_1m 은 **panel_month 당월** 수익.\n")
cat("            offset=+1 에서 cor≈1 이면 **익월(forward)** 수익.\n")
fwrite(out, file.path(OUT, "p0c_calendar.csv"))

## --- C2. 신호 vintage 조사: M26 이 당월 정보를 쓰는가 (동월 누출 혐의 시험) ---
## 방법 = M26 신호를 1개월 지연(lag1) 시켜도 IC 가 유지되는가 + 동월 수익과의 동시 상관.
j <- merge(m26[is.finite(M26_Revenue_Mom), .(ymi, Ticker, M26 = M26_Revenue_Mom, ret_col = Ret_1m)],
           m26[is.finite(M26_Revenue_Mom), .(ymi_prev = ymi, Ticker, M26_prev = M26_Revenue_Mom)],
           by.x = c("ymi","Ticker"), by.y = c("ymi_prev","Ticker"), all.x = TRUE)
lagd <- m26[is.finite(M26_Revenue_Mom), .(ymi = ymi + 1L, Ticker, M26_lag1 = M26_Revenue_Mom)]
j <- merge(j, lagd, by = c("ymi","Ticker"), all.x = TRUE)
ic <- j[is.finite(ret_col), .(
  ic_same = if (sum(is.finite(M26)) >= 20) cor(M26, ret_col, method="spearman", use="complete.obs") else NA_real_,
  ic_lag1 = if (sum(is.finite(M26_lag1)) >= 20) cor(M26_lag1, ret_col, method="spearman", use="complete.obs") else NA_real_
), by = ymi]
ic <- ic[is.finite(ic_same)]
nwt <- function(x){ x <- x[is.finite(x)]; n <- length(x); if(n<10) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:3){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/4)*ga }
  m/sqrt(s/n) }
cat(sprintf("\n[C2] M26 rank-IC (당월 라벨 기준): same-vintage 평균 %+.4f (t_NW3 %+.3f, n=%d)\n",
            mean(ic$ic_same), nwt(ic$ic_same), nrow(ic)))
cat(sprintf("     lag1(1개월 묵힌 신호)     평균 %+.4f (t_NW3 %+.3f, n=%d) · 보존율 %.3f\n",
            mean(ic$ic_lag1, na.rm=TRUE), nwt(ic$ic_lag1), sum(is.finite(ic$ic_lag1)),
            mean(ic$ic_lag1, na.rm=TRUE)/mean(ic$ic_same)))
fwrite(ic, file.path(OUT, "p0c_vintage_ic.csv"))
cat("\n[saved] p0c_calendar.csv / p0c_vintage_ic.csv\n")
