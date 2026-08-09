## 위기신호 역방향 — P4: **기계적·PIT-자명한 하락 정의** 위에서 도훈 가설 직접 검정
## 왜 이 설계인가: P3 에서 라벨 엔진 산출물이 위기를 표시하지 않음이 확인됐다(전·당·익월 전부 고수익).
##   기계적 정의는 (a) 월말 관측 가능 (b) 재적합 여지 0 (c) 정의가 곧 문서 — PIT 논쟁이 원천 소멸.
## ★사전 고정(측정 전): 1급 판정량 = forward 1M. 문턱 grid 는 전량 보고하며 argmax 선택 금지.
##   심각도 사다리를 함께 보는 이유 = 라벨 자격이 (라벨, 사건정의) 쌍에 붙는다는 기확립 사실.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/crisis_contrarian")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean

B <- readRDS(file.path(OUT, "p1_bench.rds"))$bench
setorder(B, Date)
say("=== 입력 실측 === 벤치 %d개월 · %s ~ %s · 관측단위 monthly · 월평균 %+.4f · sd %.4f",
    nrow(B), min(B$Date), max(B$Date), mean(B$BM_Ret), sd(B$BM_Ret))

r <- B$BM_Ret; n <- length(r)
## --- 신호 피처 (월말 t 시점 관측 가능. 미래 미참조) ---------------------------
cum3 <- rep(NA_real_, n)
for (i in 3:n) cum3[i] <- prod(1 + r[(i-2):i]) - 1        # 신호 피처(성과지표 아님)
nav <- cumprod(1 + r)
dd12 <- rep(NA_real_, n)
for (i in 12:n) dd12[i] <- nav[i] / max(nav[(i-11):i]) - 1
B[, `:=`(cum3 = cum3, dd12 = dd12,
         f1 = shift(BM_Ret, 1L, type="lead"),
         f2 = shift(BM_Ret, 2L, type="lead"),
         f3 = shift(BM_Ret, 3L, type="lead"))]
say("  피처: cum3 비결측 %d · dd12 비결측 %d (t 시점까지의 실현치만 사용 = PIT 자명)",
    sum(!is.na(B$cum3)), sum(!is.na(B$dd12)))

## --- 사전등록 grid --------------------------------------------------------------
grid <- rbind(
  data.table(fam = "S1_당월수익",   thr = c(-0.05, -0.10, -0.15)),
  data.table(fam = "S2_3개월누적",  thr = c(-0.10, -0.15, -0.20)),
  data.table(fam = "S3_12개월낙폭", thr = c(-0.10, -0.20, -0.30)))
say("=== 사전등록 grid %d셀 (argmax 선택 금지 — 전량 보고) ===", nrow(grid))

rows <- list()
for (i in seq_len(nrow(grid))) {
  fam <- grid$fam[i]; thr <- grid$thr[i]
  x <- switch(fam, "S1_당월수익" = B$BM_Ret, "S2_3개월누적" = B$cum3, "S3_12개월낙폭" = B$dd12)
  on <- !is.na(x) & x <= thr & !is.na(B$f1)
  off <- !is.na(x) & x > thr & !is.na(B$f1)
  n_on <- sum(on); n_off <- sum(off)
  if (n_on < 5L) { say("  %s <= %+.0f%% : n_ON %d (<5) — 측정 불가로 기록", fam, thr*100, n_on); next }
  sd_all <- sd(B$f1, na.rm = TRUE)
  se <- sd_all * sqrt(1/n_on + 1/n_off) * 1.25
  d1 <- mean(B$f1[on]) - mean(B$f1[off])
  d2 <- mean(B$f2[on], na.rm=TRUE) - mean(B$f2[off], na.rm=TRUE)
  d3 <- mean(B$f3[on], na.rm=TRUE) - mean(B$f3[off], na.rm=TRUE)
  rows[[length(rows)+1L]] <- data.table(
    family = fam, threshold_pct = thr*100, n_on = n_on, n_off = n_off,
    cur_on_ann = mean(B$BM_Ret[on])*12*100,
    f1_on_ann = mean(B$f1[on])*12*100, f1_off_ann = mean(B$f1[off])*12*100,
    f1_diff_ann = d1*12*100, f1_t = d1/se,
    f2_diff_ann = d2*12*100, f3_diff_ann = d3*12*100,
    required_ann = 2.0*se*12*100,
    hit_rate_on = mean(B$f1[on] > 0), hit_rate_off = mean(B$f1[off] > 0))
}
R <- rbindlist(rows)
R[, verdict := fifelse(abs(f1_t) >= 2.0, "SIGNIFICANT",
                fifelse(abs(f1_diff_ann) >= required_ann, "NULL_POWERED", "INCONCLUSIVE_UNDERPOWERED"))]
print(R[, .(family, thr = threshold_pct, n_on, cur_on_ann = round(cur_on_ann,1),
            f1_on_ann = round(f1_on_ann,1), f1_off_ann = round(f1_off_ann,1),
            f1_diff_ann = round(f1_diff_ann,1), f1_t = round(f1_t,2),
            required_ann = round(required_ann,1), verdict)])

say("=== 심각도 사다리 (같은 family 안에서 문턱이 깊어질수록) ===")
for (f in unique(R$family)) {
  S <- R[family == f][order(threshold_pct)]
  say("  %-14s : %s", f, paste(sprintf("%+.0f%%->%+.1f%%(t %+.2f, n %d)",
      S$threshold_pct, S$f1_diff_ann, S$f1_t, S$n_on), collapse = " | "))
}

say("=== 지속성: f2 · f3 ===")
print(R[, .(family, thr = threshold_pct, f1 = round(f1_diff_ann,1),
            f2 = round(f2_diff_ann,1), f3 = round(f3_diff_ann,1))])

say("=== 요약 ===")
say("  셀 %d · 유의(+) %d · 유의(−) %d · 검정력미달 %d",
    nrow(R), R[f1_t>=2,.N], R[f1_t<=-2,.N], R[verdict=="INCONCLUSIVE_UNDERPOWERED",.N])
say("  ★방향: forward 차이 양(+) 셀 %d / %d", R[f1_diff_ann>0,.N], nrow(R))
say("  ★적중률(익월 양수) ON vs OFF: %s",
    paste(sprintf("%s%+.0f%%: %.2f vs %.2f", R$family, R$threshold_pct, R$hit_rate_on, R$hit_rate_off), collapse=" | "))

fwrite(R, file.path(OUT, "p4_mechanical_cells.csv"))
saveRDS(list(cells = R, bench = B), file.path(OUT, "p4_results.rds"))
say("=== P4 완료 ===")
