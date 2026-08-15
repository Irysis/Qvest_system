## f1_mechanism.R — WT-D20260813_002 F1 기전 관측 (성과 독립)
## 사전등록: stage_artifacts/WT_D20260813_002/prereg_F1.json (측정 전 작성)
## 판정: 꼬리-표적 예측기(TAIL)가 실현 하방 꼬리월 판별에서 상태-예측기 2종을 상회하는가.

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/validation/overlay_pit_guard.R")
LG <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/label_eligibility_gate.R", envir = LG)

OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_002")

## ── 1. 벤치 일별 수익 (정본 = RAWDATA BM_Ret, 2026-08-08 IKS200 수리분) ──────
RB <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date", "BM_Ret")))
BD <- unique(RB, by = "Date")[order(Date)][is.finite(BM_Ret)]
## parity 대조 — 독립 원천과 상관 확인 (자체합성 아님, 원천 정합 검사)
BP <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date, BM_Ret2 = BM_Ret)]
par <- merge(BD, BP, by = "Date")
cat(sprintf("[parity] daily bench overlap n=%d  cor=%.6f\n", nrow(par),
            cor(par$BM_Ret, par$BM_Ret2, use = "complete.obs")))
## 말단 0 채움 구간 배제 (RAWDATA 최종 2영업일은 BM_Ret=0 로 관측됨)
BD <- BD[Date <= as.Date("2026-08-08")]
cat(sprintf("[bench] daily n=%d  %s ~ %s\n", nrow(BD), min(BD$Date), max(BD$Date)))

## ── 2. 월간 벤치 수익 — 표준함수만 (자체합성 금지) ──────────────────────────
bx  <- xts(BD$BM_Ret, order.by = BD$Date)
bm_m <- apply.monthly(bx, Return.cumulative)          # PerformanceAnalytics 표준
BM <- data.table(eom = as.Date(index(bm_m)), bm_ret = as.numeric(bm_m))
BM[, ym := format(eom, "%Y-%m")]
BM[, hold_start := as.Date(paste0(ym, "-01"))]        # 홀딩월 시작 = C5 컷오프
setorder(BM, hold_start)
cat(sprintf("[bench] monthly n=%d  %s ~ %s\n", nrow(BM), BM$ym[1], BM$ym[nrow(BM)]))

## ── 3. 꼬리 특징 — 홀딩월 시작 전 252 거래일만 ─────────────────────────────
.skew <- function(r) { m <- mean(r); s <- stats::sd(r); if (!is.finite(s) || s <= 0) return(NA_real_); mean((r - m)^3) / s^3 }
LB <- 252L
feat <- rbindlist(lapply(seq_len(nrow(BM)), function(i) {
  cut <- BM$hold_start[i]
  r <- BD[Date < cut, BM_Ret]                          # ★ 엄격히 홀딩월 시작 전
  if (length(r) < LB) return(NULL)
  r <- tail(r, LB)
  sdr <- stats::sd(r)
  data.table(ym = BM$ym[i], hold_start = cut, used_cutoff = cut, n_days = length(r),
             dn_semivol = sqrt(mean(pmin(r, 0)^2)),
             neg_skew   = -.skew(r),
             tail_exc   = mean(r < -0.02),
             tail_exc_std = if (is.finite(sdr) && sdr > 0) mean(r < -2 * sdr) else NA_real_)
}), fill = TRUE)
cat(sprintf("[feat] n=%d  %s ~ %s\n", nrow(feat), feat$ym[1], feat$ym[nrow(feat)]))

## ★ C5 HARD — 사용 컷오프가 홀딩월 시작 이후면 stop
assert_overlay_pit(feat$used_cutoff, feat$hold_start, label = "TAIL_features")
cat("[pit] assert_overlay_pit PASS (features)\n")

## ── 4. 상태-예측기 2종 — 같은 컷오프 규약 ──────────────────────────────────
MSMd  <- as.data.table(read_parquet(".cache/msm_daily_latest.parquet"))[order(Date), .(Date, Crisis_Prob)]
BEARd <- as.data.table(read_parquet(".cache/regime_jump_daily.parquet"))[order(Date), .(Date, Bear_Prob)]
last_before <- function(D, valcol, cutoffs) {
  X <- D[is.finite(get(valcol))][order(Date)]
  idx <- findInterval(cutoffs - 1, X$Date)             # Date <= cut-1  ==  Date < cut
  out <- rep(NA_real_, length(cutoffs)); ok <- idx >= 1
  out[ok] <- X[[valcol]][idx[ok]]
  attr(out, "asof") <- { a <- rep(as.Date(NA), length(cutoffs)); a[ok] <- X$Date[idx[ok]]; a }
  out
}
feat[, msm  := last_before(MSMd,  "Crisis_Prob", hold_start)]
feat[, bear := last_before(BEARd, "Bear_Prob",   hold_start)]
msm_asof  <- attr(last_before(MSMd,  "Crisis_Prob", feat$hold_start), "asof")
bear_asof <- attr(last_before(BEARd, "Bear_Prob",   feat$hold_start), "asof")
assert_overlay_pit(msm_asof,  feat$hold_start, label = "MSM_asof")
assert_overlay_pit(bear_asof, feat$hold_start, label = "BEAR_asof")
cat(sprintf("[pit] state predictors asof PASS. median gap MSM=%.1fd BEAR=%.1fd\n",
            median(as.numeric(feat$hold_start - msm_asof), na.rm = TRUE),
            median(as.numeric(feat$hold_start - bear_asof), na.rm = TRUE)))

## ── 5. 조인 + 개수 대조 ────────────────────────────────────────────────────
D <- merge(feat, BM[, .(ym, bm_ret)], by = "ym", all.x = TRUE)
setorder(D, hold_start)
theo <- nrow(feat)
D <- D[is.finite(bm_ret) & is.finite(msm) & is.finite(bear) & is.finite(dn_semivol) &
       is.finite(neg_skew) & is.finite(tail_exc) & is.finite(tail_exc_std)]
loss <- 1 - nrow(D) / theo
cat(sprintf("[join] theoretical=%d  final=%d  loss=%.2f%%\n", theo, nrow(D), 100 * loss))
if (loss > 0.05) stop(sprintf("[join] 손실 %.1f%% > 5%% — 키 컨벤션 의심, 중단", 100 * loss))

## ── 6. expanding z / percentile (C1 clean) ────────────────────────────────
exp_z <- function(x) { n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) { s <- stats::sd(x[1:i]); if (is.finite(s) && s > 0) o[i] <- (x[i] - mean(x[1:i])) / s }
  o }
exp_pct <- function(x) { n <- length(x); o <- rep(NA_real_, n)
  for (i in seq_len(n)) o[i] <- mean(x[1:i] <= x[i]); o }

D[, z_semivol := exp_z(dn_semivol)]
D[, z_negskew := exp_z(neg_skew)]
D[, z_tailexc := exp_z(tail_exc)]
D[, z_tailexc_std := exp_z(tail_exc_std)]
D[, TAIL       := rowMeans(cbind(z_semivol, z_negskew, z_tailexc), na.rm = FALSE)]
D[, TAIL_SHAPE := rowMeans(cbind(z_negskew, z_tailexc_std),        na.rm = FALSE)]
D[, MSM := msm][, BEAR := bear]

## expanding 안정화 — 사전등록: 월 60건 사전 이력 요구
D <- D[seq_len(.N) > 60L][is.finite(TAIL) & is.finite(TAIL_SHAPE)]
cat(sprintf("[eval] n=%d  %s ~ %s\n", nrow(D), D$ym[1], D$ym[nrow(D)]))

## ── 7. 사건 정의 ───────────────────────────────────────────────────────────
q10 <- stats::quantile(D$bm_ret, 0.10)
D[, evt_A := bm_ret <= q10]              # 하위 10분위 (전표본 분위 — 라벨 측 look-ahead 라벨됨)
D[, evt_B := bm_ret < -0.07]             # 절대 문턱 (고정)
cat(sprintf("[event] q10=%.4f  evt_A n=%d (%.1f%%)  evt_B n=%d (%.1f%%)\n",
            q10, sum(D$evt_A), 100*mean(D$evt_A), sum(D$evt_B), 100*mean(D$evt_B)))

## ── 8. AUC + 부트스트랩 ────────────────────────────────────────────────────
auc <- function(score, y) { y <- as.logical(y)
  if (sum(y) == 0 || sum(!y) == 0) return(NA_real_)
  r <- rank(score, ties.method = "average")
  (sum(r[y]) - sum(y) * (sum(y) + 1) / 2) / (sum(y) * sum(!y)) }

PRED <- c("TAIL", "TAIL_SHAPE", "MSM", "BEAR")
res <- rbindlist(lapply(PRED, function(p) data.table(
  predictor = p,
  auc_A = auc(D[[p]], D$evt_A), auc_B = auc(D[[p]], D$evt_B))))
print(res)

## expanding percentile top-20% 라벨 → 계약 label_eligibility
elig <- rbindlist(lapply(PRED, function(p) {
  lab <- exp_pct(D[[p]]) >= 0.80
  gA <- LG$label_eligibility(lab, D$evt_A); gB <- LG$label_eligibility(lab, D$evt_B)
  data.table(predictor = p, n_on = gA$n_on,
             recall_A = gA$recall, base_A = gA$base_rate, lift_A = gA$lift, p_A = gA$fisher_p, elig_A = gA$eligible,
             recall_B = gB$recall, base_B = gB$base_rate, lift_B = gB$lift, p_B = gB$fisher_p, elig_B = gB$eligible)
}))
print(elig)

## paired stationary block bootstrap on dAUC
set.seed(20260813L)
blockboot <- function(pa, pb, y, B = 2000L, bl = 6L) {
  n <- length(y); nb <- ceiling(n / bl); starts <- seq_len(max(1L, n - bl + 1L))
  vapply(seq_len(B), function(b) {
    idx <- unlist(lapply(sample(starts, nb, TRUE), function(s) s:(s + bl - 1L)))[seq_len(n)]
    idx <- idx[idx <= n]
    yy <- y[idx]; if (sum(yy) < 3 || sum(!yy) < 3) return(NA_real_)
    auc(pa[idx], yy) - auc(pb[idx], yy)
  }, numeric(1))
}
better_base <- res[predictor %in% c("MSM", "BEAR")][which.max(auc_A), predictor]
bb <- blockboot(D$TAIL, D[[better_base]], D$evt_A)
bb <- bb[is.finite(bb)]
p_gt0 <- mean(bb > 0)
cat(sprintf("[boot] TAIL vs %s (evt_A): dAUC point=%.4f  P(d>0)=%.3f  CI90=[%.4f, %.4f]  B_eff=%d\n",
            better_base, res[predictor=="TAIL", auc_A] - res[predictor==better_base, auc_A],
            p_gt0, quantile(bb, 0.05), quantile(bb, 0.95), length(bb)))

## ── 9. 사전등록 판정 규칙 적용 ─────────────────────────────────────────────
aT <- res[predictor == "TAIL", auc_A]; aM <- res[predictor == "MSM", auc_A]; aB <- res[predictor == "BEAR", auc_A]
eT <- elig[predictor == "TAIL", elig_A]
verdict <- if (isTRUE(aT > aM) && isTRUE(aT > aB) && isTRUE(p_gt0 >= 0.90) && isTRUE(eT)) {
  "F1_PASS"
} else if (isTRUE(aT > aM) && isTRUE(aT > aB)) {
  "F1_MARGINAL"
} else {
  "F1_FAIL"
}
cat(sprintf("\n★ F1 VERDICT = %s   (AUC TAIL %.4f / MSM %.4f / BEAR %.4f · P(d>0)=%.3f · eligible=%s)\n",
            verdict, aT, aM, aB, p_gt0, as.character(eT)))

## 진단 — 예측기 간 상관 (TAIL 이 vol 재포장인지)
cm <- cor(D[, .(TAIL, TAIL_SHAPE, MSM, BEAR)], method = "spearman")
cat("\n[diag] spearman cor:\n"); print(round(cm, 3))

## 부기간 (기술통계 — 판정 아님)
D[, sub := fifelse(hold_start < as.Date("2008-01-01"), "pre2008",
            fifelse(hold_start < as.Date("2017-01-01"), "2008_2016", "post2017"))]
sub <- D[, .(n = .N, n_evt = sum(evt_A),
             auc_TAIL = auc(TAIL, evt_A), auc_MSM = auc(MSM, evt_A), auc_BEAR = auc(BEAR, evt_A)), by = sub]
cat("\n[diag] subperiod (기술통계 — 검정력 부족, 판정 아님):\n"); print(sub)

saveRDS(D, file.path(OUT, "f1_panel.rds"))
write_json(list(
  wt_id = "WT-D20260813_002", stage = "F1", metric_type = "mechanism_observation",
  prereg = "stage_artifacts/WT_D20260813_002/prereg_F1.json",
  n_months = nrow(D), window = c(D$ym[1], D$ym[nrow(D)]),
  join_loss_pct = round(100 * loss, 3),
  event_A = list(rule = "bottom decile", q10 = q10, n = sum(D$evt_A), rate = mean(D$evt_A)),
  event_B = list(rule = "bm_ret < -0.07", n = sum(D$evt_B), rate = mean(D$evt_B)),
  auc = res, eligibility = elig,
  bootstrap = list(vs = better_base, block = 6, B_eff = length(bb),
                   d_auc = aT - res[predictor == better_base, auc_A],
                   p_gt0 = p_gt0, ci90 = as.numeric(quantile(bb, c(0.05, 0.95)))),
  spearman_cor = as.data.frame(cm), subperiod_descriptive = sub,
  verdict = verdict,
  pit = list(assert_overlay_pit = "PASS", cutoff_rule = "Date < first-day-of-holding-month",
             msm_caveat = "full-sample demean C1 — baseline 유리 방향(보수적)",
             bear_caveat = "SJM 전표본 적합 — 동일 보수 방향")
), file.path(OUT, "f1_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\n[done] f1_result.json written\n")
