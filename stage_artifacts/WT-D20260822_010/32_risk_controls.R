## WT-D20260822_010 — 흡수(absorption) 주장의 양방향 검사 + 관문 산술 자가정정
## 목적 1: "vol 스케일이 99% 흡수" 가 기계적 아티팩트가 아님을 **위반 주입 + 양성 대조**로 증명.
## 목적 2: R3 관문의 순열 잡음이 실현 잡음을 10배 과소평가한 사실을 정량 기록(자가적발).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[ctl] ", f, "\n"), ...))
set.seed(20260822)
J <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

G <- readRDS(file.path(OUT, "30_risk_gate_objects.rds")); P <- as.data.table(G$P)
GJ <- fromJSON(file.path(OUT, "30_risk_gate.json"))
MJ <- fromJSON(file.path(OUT, "31_risk_measure.json"))

## ── 흡수 계산기: 임의 base vol 추정치 s 에 대해 (실현 상대격차 vs 모델 상대격차) ──
## 모델 예측 꼬리확률 = 과거 표준화잔차 z=r/s 의 경험분포로 -thr/s 를 평가 (PIT 확장창)
absorption <- function(svec, thr, label) {
  D <- data.table(Date = P$Date, grp = P$grp, r = P$Ret_1m, s = svec)[is.finite(s) & s > 0]
  setorder(D, Date); dts <- sort(unique(D$Date)); D[, z := r / s]
  zl <- split(D$z, D$Date); pastz <- numeric(0); out <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    if (length(pastz) >= 2000L) {
      sp <- sort(pastz); sub <- D[Date == dts[i]]
      sub[, p0 := findInterval(-thr / s, sp) / length(sp)]
      out[[i]] <- sub[, .(Date = dts[i],
        rlo = mean(r[grp == "lo"] <= -thr), rhi = mean(r[grp == "hi"] <= -thr),
        plo = mean(p0[grp == "lo"]),        phi = mean(p0[grp == "hi"]))]
    }
    pastz <- c(pastz, zl[[as.character(dts[i])]])
  }
  A <- rbindlist(out)
  lev_r <- mean(c(rep(A$rlo, 1), rep(A$rhi, 1)))  # placeholder, 아래서 정확히
  lev_r <- weighted.mean(c(mean(A$rlo), mean(A$rhi)), c(mean(P$grp=="lo"), mean(P$grp=="hi")))
  lev_p <- weighted.mean(c(mean(A$plo), mean(A$phi)), c(mean(P$grp=="lo"), mean(P$grp=="hi")))
  rg_r <- (mean(A$rlo) - mean(A$rhi)) / lev_r
  rg_p <- (mean(A$plo) - mean(A$phi)) / lev_p
  list(label = label, threshold = thr, n_months = nrow(A),
       realized_rate_lo = mean(A$rlo), realized_rate_hi = mean(A$rhi),
       model_rate_lo = mean(A$plo), model_rate_hi = mean(A$phi),
       realized_rel_gap = rg_r, model_rel_gap = rg_p,
       absorbed_share = rg_p / rg_r, surviving_share = 1 - rg_p / rg_r,
       realized_ratio = mean(A$rlo)/mean(A$rhi), model_ratio = mean(A$plo)/mean(A$phi))
}

## ── A. 위반 주입 / 양성 대조: base 모델을 일부러 무력화하면 흡수가 사라져야 한다 ──
bases <- list(
  M0_roll60m   = P$sd0,                              # 본 라운드의 기저 위험모델
  CONST_none   = rep(median(P$sd0), nrow(P)),        # ★위반 주입: 판별력 0 → 흡수 ~0 이어야
  WINVOL_alpha = P$win_vol * sqrt(21),               # alpha 층이 직교화에 쓴 축(일별 sd → 월 환산)
  SHUFFLED_sd0 = P[, sd0[sample(.N)], by = Date]$V1  # ★위반 주입: 날짜 내 sd0 뒤섞기 → 흡수 ~0
)
A <- list()
for (nm in names(bases)) {
  a <- try(absorption(bases[[nm]], 0.20, nm), silent = TRUE)
  if (inherits(a, "try-error")) { say("%s 실패", nm); next }
  A[[nm]] <- a
  say("[thr -20%%] %-13s: 실현비 %.4f | 모델비 %.4f | 흡수 %.1f%% (잔존 %.1f%%)",
      nm, a$realized_ratio, a$model_ratio, 100*a$absorbed_share, 100*a$surviving_share)
}
J$injection_and_controls <- A
J$control_verdict <- list(
  detection_power_proven = isTRUE(A$CONST_none$absorbed_share < 0.25 && A$SHUFFLED_sd0$absorbed_share < 0.25),
  reading = "판별력을 제거한 base 두 종(상수 vol / 날짜내 뒤섞은 vol)에서 흡수율이 붕괴하면, M0 의 높은 흡수율은 계산기가 기계적으로 내는 값이 아니라 실측이다.")

## ── B. 문턱 강건성 — 흡수율이 특정 문턱의 산물인가 ──────────────────────────
TH <- list()
for (thr in c(0.15, 0.20, 0.25, 0.30)) {
  a <- try(absorption(P$sd0, thr, sprintf("M0_thr%.2f", thr)), silent = TRUE)
  if (inherits(a, "try-error")) next
  TH[[as.character(thr)]] <- a
  say("[문턱 -%.0f%%] 실현비 %.4f | 모델비 %.4f | 흡수 %.1f%% (n=%d월)",
      100*thr, a$realized_ratio, a$model_ratio, 100*a$absorbed_share, a$n_months)
}
J$threshold_robustness <- TH

## ── C. R3 관문 자가정정 — 순열 잡음 vs 실현 잡음 ────────────────────────────
J$R3_gate_selfcorrection <- list(
  prelaunch_permutation_sd_based_mde80 = GJ$gate$R3$mde80,
  realized_mde80 = MJ$R3$mde80,
  understatement_factor = MJ$R3$mde80 / GJ$gate$R3$mde80,
  prelaunch_ratio = GJ$gate$R3$ratio,
  corrected_ratio = GJ$gate$R3$effect / MJ$R3$mde80,
  corrected_pass = (GJ$gate$R3$effect / MJ$R3$mde80) >= 0.10,
  defect = "순열 귀무는 **배정만** 무작위화하고 처치 크기를 기전-함의 값에 고정했다. 실제 추정기는 스케일 계수 k 를 데이터에서 **추정**하므로 추정오차 분산이 추가된다. 순열 잡음은 이 성분을 담지 않아 MDE 를 과소평가한다.",
  fix_rule = "관문의 MDE 는 (a) 라벨 순열 + (b) **추정기 자체를 귀무 데이터에 적합**시키는 이중 재표집으로 얻어야 한다. 본 라운드는 (b) 를 빠뜨렸다.")
say("R3 관문 자가정정: 사전 MDE80 %.5f vs 실현 %.5f (%.1f배 과소) → 정정 ratio %.4f (%s)",
    GJ$gate$R3$mde80, MJ$R3$mde80, J$R3_gate_selfcorrection$understatement_factor,
    J$R3_gate_selfcorrection$corrected_ratio,
    ifelse(J$R3_gate_selfcorrection$corrected_pass, "PASS", "FAIL — 사전에 알았다면 착수 안 함"))

## ── D. R1b 관문 재계산 (정정된 R1 효과 반영) ────────────────────────────────
r1_new <- MJ$R1_gate_recomputed$effect_5pct_units; r1_old <- GJ$gate$R1$effect
sc <- (r1_new / r1_old)^2                       # 2차항이므로 제곱 스케일
sc_mde <- abs(r1_new / r1_old)                  # 순열 잡음은 |delta| 에 비례
J$R1b_recomputed <- list(effect = GJ$gate$R1b$effect * sc, mde80 = GJ$gate$R1b$mde80 * sc_mde,
  ratio = (GJ$gate$R1b$effect * sc) / (GJ$gate$R1b$mde80 * sc_mde),
  pass = ((GJ$gate$R1b$effect * sc) / (GJ$gate$R1b$mde80 * sc_mde)) >= 0.10)
say("R1b 재계산 ratio %.4f (%s)", J$R1b_recomputed$ratio, ifelse(J$R1b_recomputed$pass, "PASS", "FAIL"))

## ── E. 최종 관문 표 ─────────────────────────────────────────────────────────
J$final_gate_table <- list(
  R1  = list(ratio = MJ$R1_gate_recomputed$ratio,        pass = FALSE, basis = "수준-정규화 재계산"),
  R1b = list(ratio = J$R1b_recomputed$ratio,             pass = J$R1b_recomputed$pass, basis = "R1 정정 반영"),
  R1c = list(ratio = GJ$gate$R1c$ratio,                  pass = GJ$gate$R1c$pass, basis = "사전 산술"),
  R2  = list(ratio = GJ$gate$R2$ratio,                   pass = GJ$gate$R2$pass,  basis = "사전 산술"),
  R3  = list(ratio = J$R3_gate_selfcorrection$corrected_ratio,
             pass = J$R3_gate_selfcorrection$corrected_pass, basis = "실현 잡음으로 정정"))
J$metric_type <- "estimation_quality__controls"
write_json(J, file.path(OUT, "32_risk_controls.json"), pretty = TRUE, auto_unbox = TRUE, digits = 12)
say("완료 → 32_risk_controls.json")
