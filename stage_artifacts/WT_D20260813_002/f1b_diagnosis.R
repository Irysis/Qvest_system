## f1b_diagnosis.R — F1_FAIL 기전 진단 (판정 변경 불가 · 사후 진단 라벨)
## 목적 3종:
##  (D1) TAIL 의 판별력이 단순 변동성 수준의 재포장인가 — 순수 vol 예측기 대조
##  (D2) TAIL 이 MSM 을 넘어 *증분* 정보를 갖는가 — MSM 직교화 잔차 AUC
##  (D3) 승계 가설 regime_scope holds_in[2] 이 지목한 곳 — "상태 라벨 중립인데 꼬리가 두꺼운 구간"
##       (가설이 '정보 우위가 성립한다면 가장 먼저 여기서 보여야 한다'고 명시 → 사후 낚시 아님)
## ★어느 결과도 F1 판정을 뒤집지 않는다. 판정은 사전등록 규칙으로 이미 확정(F1_FAIL).

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_002")
LG <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/label_eligibility_gate.R", envir = LG)

D <- as.data.table(readRDS(file.path(OUT, "f1_panel.rds")))
auc <- function(score, y) { y <- as.logical(y); ok <- is.finite(score)
  score <- score[ok]; y <- y[ok]
  if (sum(y) < 2 || sum(!y) < 2) return(NA_real_)
  r <- rank(score, ties.method = "average")
  (sum(r[y]) - sum(y)*(sum(y)+1)/2) / (sum(y)*sum(!y)) }
exp_z <- function(x) { n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) { s <- stats::sd(x[1:i]); if (is.finite(s) && s > 0) o[i] <- (x[i]-mean(x[1:i]))/s }; o }

## ── D1. 순수 변동성 대조 ───────────────────────────────────────────────────
## 같은 컷오프·같은 252d 창의 단순 실현변동성. 꼬리 특징 0개.
BD <- unique(as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","BM_Ret"))), by="Date")[order(Date)][is.finite(BM_Ret)][Date <= as.Date("2026-08-08")]
vol <- vapply(D$hold_start, function(cut) { r <- BD[Date < cut, BM_Ret]; if (length(r) < 252) return(NA_real_)
  stats::sd(tail(r, 252)) }, numeric(1))
D[, VOL := exp_z(vol)]

d1 <- data.table(
  predictor = c("TAIL","VOL","TAIL_SHAPE","MSM","BEAR"),
  auc_A = c(auc(D$TAIL,D$evt_A), auc(D$VOL,D$evt_A), auc(D$TAIL_SHAPE,D$evt_A),
            auc(D$MSM,D$evt_A), auc(D$BEAR,D$evt_A)))
cat("[D1] 순수 변동성 대조 (evt_A):\n"); print(d1)
cat(sprintf("[D1] spearman cor(TAIL, VOL) = %.3f   cor(VOL, MSM) = %.3f\n",
            cor(D$TAIL, D$VOL, method="spearman", use="complete.obs"),
            cor(D$VOL, D$MSM, method="spearman", use="complete.obs")))

## ── D2. MSM 직교화 잔차 — 증분 정보 ────────────────────────────────────────
## expanding OLS (인과): 각 t 에서 1..t 로 TAIL ~ MSM 적합 후 t 의 잔차
res_t <- rep(NA_real_, nrow(D))
for (i in 30:nrow(D)) {
  fit <- stats::lm(TAIL ~ MSM, data = D[1:i])
  res_t[i] <- D$TAIL[i] - stats::predict(fit, newdata = D[i])
}
D[, TAIL_resid_MSM := res_t]
## 대칭 검사 — MSM 을 TAIL 로 직교화한 잔차도 (어느 쪽이 어느 쪽을 포함하나)
res_m <- rep(NA_real_, nrow(D))
for (i in 30:nrow(D)) {
  fit <- stats::lm(MSM ~ TAIL, data = D[1:i])
  res_m[i] <- D$MSM[i] - stats::predict(fit, newdata = D[i])
}
D[, MSM_resid_TAIL := res_m]
d2 <- data.table(
  series = c("TAIL_resid_MSM (TAIL 이 MSM 위에 더하는 것)",
             "MSM_resid_TAIL (MSM 이 TAIL 위에 더하는 것)"),
  auc_A = c(auc(D$TAIL_resid_MSM, D$evt_A), auc(D$MSM_resid_TAIL, D$evt_A)),
  n = c(sum(is.finite(D$TAIL_resid_MSM)), sum(is.finite(D$MSM_resid_TAIL))))
cat("\n[D2] 증분 정보 (AUC 0.5 = 증분 없음):\n"); print(d2)

## ── D3. 가설이 지목한 구간 — 상태 중립인데 꼬리가 두꺼운 달 ────────────────
## MSM expanding percentile < 0.80 (상태 예측기가 경보하지 않는 달) 안에서 TAIL 판별력
exp_pct <- function(x) { n <- length(x); o <- rep(NA_real_, n); for (i in seq_len(n)) o[i] <- mean(x[1:i] <= x[i]); o }
D[, msm_pct := exp_pct(MSM)][, tail_pct := exp_pct(TAIL)]
S <- D[msm_pct < 0.80]
d3 <- list(
  n_subset = nrow(S), n_event = sum(S$evt_A), base_rate = mean(S$evt_A),
  auc_TAIL_in_calm = auc(S$TAIL, S$evt_A),
  auc_TAIL_SHAPE_in_calm = auc(S$TAIL_SHAPE, S$evt_A),
  auc_BEAR_in_calm = auc(S$BEAR, S$evt_A))
cat("\n[D3] 상태-중립 구간(MSM expanding pct < 0.80) 내부:\n"); str(d3)
gcalm <- LG$label_eligibility(S$tail_pct >= 0.80, S$evt_A)
cat(sprintf("[D3] label_eligibility(TAIL top20%% | calm): recall %.3f vs base %.3f (lift %.2fx) p=%.4f -> %s\n",
            gcalm$recall, gcalm$base_rate, gcalm$lift, gcalm$fisher_p, gcalm$verdict))

## ── D4. 양성 대조 — 잣대가 살아있는지 (실현 당월 vol 은 반드시 높은 AUC) ────
## ★검사기 자체 검증: 사후 정보를 넣으면 AUC 가 크게 올라야 한다. 안 오르면 잣대가 고장.
rvol_same <- vapply(D$hold_start, function(cut) {
  nx <- seq(cut, by = "month", length.out = 2)[2]
  r <- BD[Date >= cut & Date < nx, BM_Ret]; if (length(r) < 5) return(NA_real_); stats::sd(r) }, numeric(1))
cat(sprintf("\n[D4] 양성 대조 — 동월 실현변동성 AUC = %.4f (사후정보. 0.5 근처면 잣대 고장)\n",
            auc(rvol_same, D$evt_A)))

write_json(list(
  wt_id = "WT-D20260813_002", stage = "F1b_diagnosis",
  metric_type = "mechanism_observation_posthoc",
  note = "판정 변경 불가 — F1_FAIL 은 사전등록 규칙으로 확정. 본 산출은 기전 진단 전용.",
  D1_vol_control = d1,
  D1_cor = list(tail_vol = cor(D$TAIL, D$VOL, method="spearman", use="complete.obs"),
                vol_msm  = cor(D$VOL, D$MSM, method="spearman", use="complete.obs")),
  D2_incremental = d2,
  D3_calm_subset = d3,
  D3_eligibility = list(recall = gcalm$recall, base = gcalm$base_rate, lift = gcalm$lift,
                        p = gcalm$fisher_p, verdict = gcalm$verdict),
  D4_positive_control_same_month_vol_auc = auc(rvol_same, D$evt_A)
), file.path(OUT, "f1b_diagnosis.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
saveRDS(D, file.path(OUT, "f1_panel.rds"))
cat("\n[done] f1b_diagnosis.json written\n")
