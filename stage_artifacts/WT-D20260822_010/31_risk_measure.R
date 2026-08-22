## WT-D20260822_010 — risk 층 측정
## 사전등록 30_risk_PREREG.json / 관문 30_risk_gate.json 준수.
## 실행 대상 = 관문 통과분(R3) + 관문 산술 자체가 답인 축(Sigma 흡수 분해).
## R1/R1b/R1c/R2 는 관문 미달 → 개선지표로 측정하지 않는다(산술만 보고).
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say  <- function(f, ...) cat(sprintf(paste0("[msr] ", f, "\n"), ...))
set.seed(20260822)
J <- list()

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
           error = function(e) NA_real_)
}
MDE80 <- function(sd_m, n) 2.802 * sd_m / sqrt(n)

G  <- readRDS(file.path(OUT, "30_risk_gate_objects.rds")); P <- as.data.table(G$P)
GJ <- fromJSON(file.path(OUT, "30_risk_gate.json"))
PC <- fromJSON(file.path(OUT, "00_precheck.json"))
n_m <- uniqueN(P$Date); p_lo <- mean(P$grp == "lo")

## ══ 1. R1 관문 재계산 — 수준-정규화 회계 (v2 스크립트의 차분 회계 정정) ══════
## 문제: M0 가 꼬리 '수준' 을 1.33배 과대예측한다. 차분(raw − predicted)으로 공제하면
##       수준 오차가 격차 공제에 새어 들어가 증분의 **부호가 뒤집힌다**(-0.0036 vs +0.0003).
## 정정: 상대격차(=격차/수준)로 비교한다 — 수준-불변 회계.
lev_real  <- P[, mean(Ret_1m <= -0.20)]
gp <- P[, .(lo = mean(Ret_1m[grp == "lo"] <= -0.20), hi = mean(Ret_1m[grp == "hi"] <= -0.20),
            plo = mean(p0[grp == "lo"]), phi = mean(p0[grp == "hi"])), by = Date]
gap_real  <- mean(gp$lo - gp$hi); lev_pred <- P[, mean(p0)]; gap_pred <- mean(gp$plo - gp$phi)
relgap_real <- gap_real / lev_real; relgap_pred <- gap_pred / lev_pred
survive_share <- 1 - relgap_pred / relgap_real
R1_effect_corrected <- 0.05 * relgap_real * survive_share
mde_R1 <- GJ$gate$R1$mde80
J$R1_gate_recomputed <- list(
  accounting = "level_normalized_relative_gap",
  realized = list(level = lev_real, gap = gap_real, rel_gap = relgap_real,
                  rate_lo = mean(gp$lo), rate_hi = mean(gp$hi), ratio_lo_hi = mean(gp$lo)/mean(gp$hi)),
  model_M0 = list(level = lev_pred, gap = gap_pred, rel_gap = relgap_pred,
                  rate_lo = mean(gp$plo), rate_hi = mean(gp$phi), ratio_lo_hi = mean(gp$plo)/mean(gp$phi)),
  absorbed_share_by_vol_scaling = 1 - survive_share,
  surviving_share = survive_share,
  effect_5pct_units = R1_effect_corrected, mde80 = mde_R1,
  ratio = abs(R1_effect_corrected) / mde_R1, threshold = 0.10,
  pass = abs(R1_effect_corrected) / mde_R1 >= 0.10,
  v2_script_naive_diff_accounting = GJ$gate$R1$effect,
  why_corrected = "차분 회계는 M0 의 수준 과대예측(1.33x)을 격차 공제에 흘려 부호를 뒤집는다. 두 회계의 답이 MDE 보다 크게 갈리므로 회계 선택이 판정을 지배 — 수준-불변 회계를 채택하고 양쪽을 다 기록한다.")
say("R1 재계산: 실현 상대격차 %.4f vs M0 예측 상대격차 %.4f → 흡수 %.1f%%, 잔존 %.1f%%",
    relgap_real, relgap_pred, 100 * (1 - survive_share), 100 * survive_share)
say("R1 관문: 효과 %.6f / MDE80 %.6f = ratio %.4f → %s",
    R1_effect_corrected, mde_R1, abs(R1_effect_corrected)/mde_R1,
    ifelse(abs(R1_effect_corrected)/mde_R1 >= 0.10, "PASS", "FAIL(측정 중단)"))
say("  실현 비율 lo/hi = %.4f | M0 예측 비율 lo/hi = %.4f",
    mean(gp$lo)/mean(gp$hi), mean(gp$plo)/mean(gp$phi))

## R1 의 '검출 가능 하한' — 무엇을 배제할 수 있는가
J$R1_gate_recomputed$detectable_floor <- list(
  mde_as_share_of_raw_relgap = mde_R1 / (0.05 * relgap_real),
  reading = "MDE80 이 raw 판별력의 이 비율에 해당한다 — 이보다 큰 잔존은 배제 가능, 이보다 작은 잔존은 미결.")

## ══ 2. Sigma 층 — 축이 변동성에 실려 있는가 (예측자-측, 형태 진단) ══════════
P[, qs := cut(frank(score_orth) / .N, breaks = seq(0, 1, 0.2), labels = 1:5,
              include.lowest = TRUE), by = Date]
QS <- P[, .(sd0 = mean(sd0), win_vol = mean(win_vol, na.rm = TRUE), n = .N), by = .(Date, qs)]
QSm <- QS[, .(sd0 = mean(sd0), win_vol = mean(win_vol, na.rm = TRUE)), by = qs][order(qs)]
J$vol_shape <- list(
  by_orth_quintile = as.list(QSm),
  sd0_lo_vs_hi = list(lo = P[grp == "lo", mean(sd0)], hi = P[grp == "hi", mean(sd0)],
                      ratio = P[grp == "lo", mean(sd0)] / P[grp == "hi", mean(sd0)]),
  winvol_lo_vs_hi = list(lo = P[grp == "lo", mean(win_vol, na.rm = TRUE)],
                         hi = P[grp == "hi", mean(win_vol, na.rm = TRUE)]),
  spearman_full_range = GJ$predictor_side$spearman_orth_vs_logsd0_mean,
  interpretation_note = "직교화는 win_vol(창 내 **일별** 수익 sd, 단기)에 대한 **선형(랭크)** 회귀다. 위험모델의 특이위험은 장기(60개월 월별) 변동성이며 서로 다른 양이다. 전 구간 선형상관이 0에 가까워도 **하위 20% 절단**은 잔차의 비선형 구조를 상속할 수 있다 — 분위별 형태로 확인.")
say("orth 분위별 sd0: %s", paste(sprintf("Q%s=%.4f", QSm$qs, QSm$sd0), collapse = " "))
say("orth 분위별 win_vol: %s", paste(sprintf("Q%s=%.5f", QSm$qs, QSm$win_vol), collapse = " "))
say("sd0 lo/hi 비 = %.4f (lo %.4f vs hi %.4f)", J$vol_shape$sd0_lo_vs_hi$ratio,
    J$vol_shape$sd0_lo_vs_hi$lo, J$vol_shape$sd0_lo_vs_hi$hi)

## ══ 3. R3 — 분산-축 한계 기여 (관문 통과: ratio 0.672) ═══════════════════════
## M1 = M0 에 score_orth 군별 스케일 k_t 를 곱함. k_t 는 **확장창 과거만**으로 추정(PIT C1).
qlike <- function(r, s2) log(s2) + r^2 / s2
setorder(P, Date); dts <- sort(unique(P$Date))
P[, z2 := (Ret_1m / sd0)^2]
fit_scale <- function(dt_idx, key) {
  ## 과거(<t) 표본에서 군별 평균 z^2 의 제곱근 = 스케일 보정계수
  past <- P[Date < dts[dt_idx]]
  if (nrow(past) < 3000L) return(NULL)
  past[, .(k = sqrt(mean(z2, na.rm = TRUE))), by = key]
}
res <- vector("list", length(dts))
for (i in seq_along(dts)) {
  ko <- fit_scale(i, "grp"); if (is.null(ko)) next
  kv <- fit_scale(i, "vq");  # PC2 positive control (vol quintile) — 아래에서 vq 정의 후 재실행
  cur <- P[Date == dts[i]]
  cur <- merge(cur, ko, by = "grp", all.x = TRUE)
  cur[!is.finite(k), k := 1]
  res[[i]] <- data.table(Date = dts[i],
    L0 = mean(qlike(cur$Ret_1m, cur$sd0^2)),
    L1 = mean(qlike(cur$Ret_1m, (cur$sd0 * cur$k)^2)))
}
QL <- rbindlist(res)
QL[, d := L0 - L1]
J$R3 <- list(metric = "name-level QLIKE, M0 vs M0+score_orth 군별 스케일(확장창 PIT)",
  n_months = nrow(QL), mean_improvement = mean(QL$d), nw_t = nw_t(QL$d),
  mde80 = MDE80(sd(QL$d), nrow(QL)),
  gate_ratio_prelaunch = GJ$gate$R3$ratio,
  mean_L0 = mean(QL$L0), mean_L1 = mean(QL$L1))
say("R3: QLIKE 개선 %.6f (NW t %.3f, n=%d) | MDE80 %.6f",
    mean(QL$d), J$R3$nw_t, nrow(QL), J$R3$mde80)

## PC2 양성 대조 — 같은 하네스에 **변동성 분위**를 넣으면 QLIKE 가 개선되어야 한다
P[, vq := cut(frank(win_vol) / .N, breaks = seq(0, 1, 0.2), labels = 1:5,
              include.lowest = TRUE), by = Date]
res2 <- vector("list", length(dts))
for (i in seq_along(dts)) {
  past <- P[Date < dts[i]]; if (nrow(past) < 3000L) next
  kv <- past[is.finite(z2), .(k = sqrt(mean(z2))), by = vq]
  cur <- merge(P[Date == dts[i]], kv, by = "vq", all.x = TRUE)
  cur[!is.finite(k), k := 1]
  res2[[i]] <- data.table(Date = dts[i], L0 = mean(qlike(cur$Ret_1m, cur$sd0^2)),
                          L1 = mean(qlike(cur$Ret_1m, (cur$sd0 * cur$k)^2)))
}
QL2 <- rbindlist(res2); QL2[, d := L0 - L1]
J$PC2_positive_control <- list(axis = "win_vol quintile", n_months = nrow(QL2),
  mean_improvement = mean(QL2$d), nw_t = nw_t(QL2$d), mde80 = MDE80(sd(QL2$d), nrow(QL2)),
  fired = isTRUE(mean(QL2$d) > 0 && abs(nw_t(QL2$d)) >= 2))
say("PC2 양성대조(win_vol 분위): 개선 %.6f (NW t %.3f) → %s",
    mean(QL2$d), J$PC2_positive_control$nw_t,
    ifelse(J$PC2_positive_control$fired, "발화(하네스 전도성 확인)", "미발화(하네스 무능 — R3 null 은 미결)"))

## ══ 4. crowding 층 — 관문 미달이므로 회귀 미실시. 진단 산출만 ════════════════
tilt <- as.data.table(G$tilt); PR <- as.data.table(G$PR)
J$R2_gate <- list(pass = FALSE, ratio = GJ$gate$R2$ratio, effect = GJ$gate$R2$effect,
  mde80 = GJ$gate$R2$mde80,
  reading = sprintf("crowding proxy 의 기전-함의 beta %.5f 는 MDE80 %.5f 의 %.1f%% — 268개월로는 원리적으로 검출 불가. 회귀를 돌리지 않는다.",
    GJ$gate$R2$effect, GJ$gate$R2$mde80, 100 * GJ$gate$R2$ratio),
  book_tilt = list(mean = mean(tilt$w_lo), sd = sd(tilt$w_lo),
                   range = c(min(tilt$w_lo), max(tilt$w_lo))))

J$metric_type <- "estimation_quality__canonical_inputs"
J$labels <- list()
write_json(J, file.path(OUT, "31_risk_measure.json"), pretty = TRUE, auto_unbox = TRUE, digits = 12)
saveRDS(list(QL = QL, QL2 = QL2, QSm = QSm, gp = gp), file.path(OUT, "31_risk_measure_objects.rds"))
say("완료 → 31_risk_measure.json")
