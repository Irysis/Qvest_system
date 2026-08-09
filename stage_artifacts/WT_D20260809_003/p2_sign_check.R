## WT-D20260809_003 P2 — ★형태 주장 전 **부호 규약 정체 확인**
## 왜: P1 에서 D03_EWMA spearman -0.685(거의 INVERTED). 그런데 D03 은 변동성 계열이라
##     원열이 '높을수록 나쁨' 이면 이 음수는 **발견이 아니라 규약**이다.
##     존재 검사로 정체 검사를 대체하지 말 것 (feedback-identify-before-existence-check).
## 판정: 각 재료의 rank-IC 부호를 직접 재고, 원 라운드가 쓴 방향과 대조한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_003")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

B <- readRDS(file.path(OUT, "merged_panel.rds"))
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
X <- merge(B, as.data.table(P$ret)[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
say("패널 %d행 · %d개월", nrow(X), uniqueN(X$Date))

say("=== 재료별 rank-IC 부호 (score vs forward Ret_1m, 월별 spearman) ===")
cols <- c("M26_Revenue_Mom","Q01_EB","z_neutral","D03_EWMA","M01_PATHQ")
res <- rbindlist(lapply(cols, function(k) {
  D <- X[!is.na(get(k))]
  ic <- D[, .(ic = suppressWarnings(cor(get(k), Ret_1m, method = "spearman"))), by = Date][!is.na(ic)]
  data.table(material = k, n_months = nrow(ic), rank_ic_mean = mean(ic$ic),
             rank_ic_t_nw3 = .nw_t_mean(ic$ic, lag = 3L), pos_rate = mean(ic$ic > 0))
}))
print(res[, .(material, n_months, rank_ic_mean = round(rank_ic_mean, 5),
              rank_ic_t_nw3 = round(rank_ic_t_nw3, 3), pos_rate = round(pos_rate, 3))])

say("=== 정합성 판정 ===")
for (i in seq_len(nrow(res))) {
  s <- if (res$rank_ic_mean[i] > 0) "높을수록 좋음(정렬 O)" else "높을수록 나쁨(★역방향 — 상위분위=악재)"
  say("  %-18s rank-IC %+.5f (t %+.2f) -> %s", res$material[i], res$rank_ic_mean[i],
      res$rank_ic_t_nw3[i], s)
}

say("=== W1 패널이 D03/Q01 을 어떻게 썼는지 (원 라운드 의도) ===")
W1 <- as.data.table(arrow::read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet"))
say("  컬럼: %s", paste(names(W1), collapse = ", "))
say("  excl_d03_q20 분포: %s", paste(sprintf("%s=%d", names(table(W1$excl_d03_q20)),
                                              as.integer(table(W1$excl_d03_q20))), collapse = " · "))
say("  excl_q01_q20 분포: %s", paste(sprintf("%s=%d", names(table(W1$excl_q01_q20)),
                                              as.integer(table(W1$excl_q01_q20))), collapse = " · "))
## 배제 플래그가 어느 쪽 꼬리인지 = 원 라운드가 어느 끝을 '나쁨'으로 봤는지
for (k in c("d03","q01")) {
  fc <- paste0("excl_", k, "_q20"); sc <- if (k == "d03") "D03_EWMA" else "Q01_EB"
  if (!all(c(fc, sc) %in% names(W1))) next
  W <- W1[!is.na(get(sc))]
  m1 <- W[get(fc) == TRUE, mean(get(sc), na.rm = TRUE)]
  m0 <- W[get(fc) == FALSE, mean(get(sc), na.rm = TRUE)]
  say("  %s: 배제군 평균 %.4f vs 잔류군 %.4f -> 배제한 쪽 = %s",
      sc, m1, m0, if (m1 > m0) "고값 꼬리" else "저값 꼬리")
}

writeLines(toJSON(list(rank_ic = res, note = paste0(
  "형태 분류는 '점수가 높을수록 좋다' 를 전제한다. rank-IC 가 음수인 재료는 원열이 역방향이므로 ",
  "P1 의 spearman 부호를 그대로 발견으로 읽으면 안 된다.")), auto_unbox = TRUE, pretty = 2, digits = NA),
  file.path(OUT, "p2_sign_check.json"))
saveRDS(res, file.path(OUT, "p2_results.rds"))
say("=== P2 완료 ===")
