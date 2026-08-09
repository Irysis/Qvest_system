## FQ-182 적대검증 — STEP 3: 극단 관측의 정체 + 최근 구간 데이터 무결성
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182"); say <- function(fmt, ...) { cat(sprintf(paste0("[ext] ", fmt, "\n"), ...)); flush.console() }

BD <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]
B  <- BD[is.finite(BM_Ret)][abs(BM_Ret) < 0.5]
nav <- cumprod(1 + B$BM_Ret)
B[, dd252 := nav / frollapply(nav, 252, max, fill = NA, align = "right") - 1]
B[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
B <- B[is.finite(dd252) & is.finite(fwd1)]
on <- B$dd252 <= -0.20

say("=== ON(dd<=-20%%) 표본 상위 +fwd1 10개 ===")
S <- B[on][order(-fwd1)][1:10, .(Date, dd252 = round(dd252,3), fwd1 = round(fwd1,4), fwd1_date = Date + 1)]
print(S)
say("=== ON 표본 하위 -fwd1 10개 ===")
print(B[on][order(fwd1)][1:10, .(Date, dd252 = round(dd252,3), fwd1 = round(fwd1,4))])
say("=== 전기간 |BM_Ret| 상위 12개 (ON 여부 포함) ===")
B[, is_on := on]
print(B[order(-abs(BM_Ret))][1:12, .(Date, BM_Ret = round(BM_Ret,4), dd252 = round(dd252,3), is_on)])

## ---- 최근 구간 원천 대조: benchmark.parquet (현행) vs 사전-수리 백업 ----
say("=== 최근 구간 무결성: benchmark.parquet 현행 vs 백업 ===")
cur <- as.data.table(read_parquet(".cache/benchmark.parquet"))[order(Date)]
say("  현행 benchmark.parquet: 행 %d · %s ~ %s", nrow(cur), min(cur$Date), max(cur$Date))
say("  2026-06 이후 BM_Ret 요약: n %d · 최소 %+.4f · 최대 %+.4f · sd %.4f",
    cur[Date >= as.Date("2026-06-01"), .N],
    cur[Date >= as.Date("2026-06-01"), min(BM_Ret, na.rm=TRUE)],
    cur[Date >= as.Date("2026-06-01"), max(BM_Ret, na.rm=TRUE)],
    cur[Date >= as.Date("2026-06-01"), sd(BM_Ret, na.rm=TRUE)])
say("  --- 2026-06-25 이후 일별 (Date / BM_Close / BM_Ret) ---")
print(cur[Date >= as.Date("2026-06-25"), .(Date, BM_Close = round(BM_Close,2), BM_Ret = round(BM_Ret,5))])

bk <- ".cache/benchmark.parquet.bak_20260808_081104_scalebreak"
if (file.exists(bk)) {
  b2 <- as.data.table(read_parquet(bk))[order(Date)]
  say("  백업(scalebreak): 행 %d · %s ~ %s", nrow(b2), min(b2$Date), max(b2$Date))
  M <- merge(cur[, .(Date, cur_ret = BM_Ret, cur_cl = BM_Close)], b2[, .(Date, bak_ret = BM_Ret, bak_cl = BM_Close)], by = "Date")
  df <- M[abs(cur_ret - bak_ret) > 1e-8]
  say("  ★현행-백업 BM_Ret 불일치일 = %d / %d 공통일", nrow(df), nrow(M))
  if (nrow(df)) print(utils::head(df[order(-abs(cur_ret - bak_ret))], 12))
}

## ---- 계열 정체 재확인: indices::kospi200 에도 같은 +20%% 일이 있는가 ----
IDX <- as.data.table(read_parquet(".cache/indices.parquet"))[order(Date)]
K <- data.table(Date = IDX$Date, lvl = IDX$kospi200)[is.finite(lvl)]
K[, r := c(NA_real_, lvl[-1]/lvl[-.N] - 1)]
say("=== indices::kospi200 |r| 상위 8 ===")
print(K[is.finite(r)][order(-abs(r))][1:8, .(Date, lvl = round(lvl,2), r = round(r,4))])

## ---- ★top-1 제거 후 재판정 (부트 se 재산출) ----
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
set.seed(20260809)
bbskew <- function(x, on, B = 800L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1)); o <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]; if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob])
  }
  o[is.finite(o)]
}
say("=== ★top-1 ON 관측 제거 후 정식 재판정 ===")
imax <- which(on)[which.max(B$fwd1[on])]
say("  제거 대상: 신호일 %s · fwd1 %+.4f (실현일 %s)", B$Date[imax], B$fwd1[imax], B$Date[imax+1])
for (tag in c("full", "drop_top1")) {
  keep <- rep(TRUE, nrow(B)); if (tag == "drop_top1") keep[imax] <- FALSE
  x <- B$fwd1[keep]; o2 <- on[keep]
  a <- skew1(x[o2]); of <- skew1(x[!o2]); d <- a - of
  bs <- bbskew(x, o2, 800L); se <- sd(bs)
  say("  %-10s ON_skew %+.4f · OFF_skew %+.4f · diff %+.4f · se %.4f · ratio %.3f · 부호뒤집힘 %s",
      tag, a, of, d, se, abs(d)/(2*se), if (a > 0 && of < 0) "YES" else "NO")
}
say("=== STEP 3 완료 ===")
