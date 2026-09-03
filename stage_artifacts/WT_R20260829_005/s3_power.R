# S3 — 사전 검정력 계약 (Step 0 C) · 후보 포트폴리오 측정 **이전**에 실행
#  캘리브레이션 = AMP2013 일본 factor basis dSR = 0.88 - 0.77 = +0.11 (원문 Table I 재확인)
#  글로벌(+0.47~+0.77) 사용 금지 — 모멘텀이 죽은 시장이 KR 유사물 (설계 gate_calibration_source)
#  basis 정합: 논문 dSR 이 rank-weighted zero-cost factor basis 위의 값이므로
#              MDE 도 **같은 basis**(팩터 수준 zero-cost)에서 산출한다. basis 불일치 회피.
#  검정통계 = Sharpe 차 (Jobson-Korkie, Memmel 2003 보정) + measured NW 팽창
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
S2 <- readRDS(file.path(OUT, "s2_objects.rds")); E <- S2$E
P <- readRDS(file.path(OUT, "panel.rds")); R <- P$fwd$returns_dt

Z_A <- 1.959964; Z_B <- 0.8416212; T_THR <- Z_A + Z_B   # = 2.801585

## 팩터 basis (논문 식 (1)) — 시장-내 랭킹 후 pooled pct rank 로 결합
pctr <- function(x) (frank(x, ties.method = "average") - 0.5) / length(x)
D <- E[is.finite(bm_a) & is.finite(mom61)]
D[, `:=`(pv = pctr(bm_a), pm = pctr(mom61)), by = .(Date, mkt)]
D[, pc := 0.5*pv + 0.5*pm]
fac_ret <- function(dt, scol) {
  W <- dt[, { r <- frank(get(scol), ties.method = "average"); dev <- r - mean(r)
              .(Ticker = Ticker, w = (2/sum(abs(dev)))*dev) }, by = Date]
  merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))[, .(fr = sum(w*Ret_1m)), by = Date] }
FV <- fac_ret(D, "pv")[, .(Date, val = fr)]
FM <- fac_ret(D, "pm")[, .(Date, mom = fr)]
FC <- fac_ret(D, "pc")[, .(Date, cmb = fr)]
X <- Reduce(function(a,b) merge(a,b,by="Date"), list(FV, FM, FC))
n <- nrow(X)

sr_m <- function(x) mean(x)/sd(x)
sr_v <- sr_m(X$val); sr_c <- sr_m(X$cmb); sr_mo <- sr_m(X$mom)
rho_cv <- cor(X$cmb, X$val)

## Memmel(2003) 보정 Jobson-Korkie: Var(SR1-SR2) (per-period SR 단위)
var_dsr <- (1/n) * ( 2*(1 - rho_cv) + 0.5*(sr_c^2 + sr_v^2 - 2*sr_c*sr_v*rho_cv^2) )
se_dsr_iid <- sqrt(var_dsr)

## measured NW 팽창 (가정값 금지) — 짝지은 차 계열의 NW lag-3 SE / iid SE
d <- X$cmb - X$val
m0 <- lm(d ~ 1)
se_nw  <- sqrt(NeweyWest(m0, lag = 3, prewhite = FALSE)[1,1])
se_iid <- sqrt(vcov(m0)[1,1])
nw_infl <- se_nw / se_iid

se_dsr <- se_dsr_iid * nw_infl
mde80_dsr_m   <- T_THR * se_dsr                 # per-period SR 단위
mde80_dsr_ann <- mde80_dsr_m * sqrt(12)
implied_ann   <- 0.11                            # 일본 factor basis
implied_m     <- implied_ann / sqrt(12)
ratio      <- implied_m / mde80_dsr_m
expected_t <- ratio * T_THR
power      <- pnorm(expected_t - Z_A)
disp <- if (ratio < 0.15) "ABORT_ratio_below_0.15" else if (ratio < 0.70) "CONDITIONAL_undetermined_is_modal" else "NORMAL"

## 참고(비판정): 평균-차 축 MDE (연환산 = x12 산술합 — sqrt(12) 금지)
mde80_mean_ann <- T_THR * se_nw * 12

## 후보 포트폴리오 층의 설계 좌표 (판정 아님 · 좌표 병기)
port_n <- uniqueN(D$Date)

res <- list(
  meta = list(wt_id = "WT-R20260829_005", stage = "preregistered_power_contract",
    executed_before_any_portfolio_arm = TRUE,
    calibration_source = "AMP2013 Table I Japan stocks, Factor column: combo SR 0.88 - value SR 0.77 = +0.11 (원문 PDF 재확인)",
    calibration_excluded = "global stocks factor +0.77 / US +0.20 / Europe·UK 등 — 모멘텀 생존 시장 캘리브레이션 사용 금지(설계 gate_calibration_source)",
    basis = "rank-weighted zero-cost factor portfolio (AMP2013 eq.(1)) — 논문 dSR 과 동일 basis. 후보(롱온리 top-25) basis 와는 다른 양임을 명시.",
    test_statistic = "Sharpe difference, Jobson-Korkie with Memmel(2003) correction, correlated samples",
    t_threshold = T_THR, note_on_t_threshold = "z(0.80)+z(0.975)=2.8016 — 귀무 95분위(1.96)를 MDE 로 오칭하는 모드(i) 회피"),
  measured_inputs = list(n_months = n, portfolio_layer_n_months = port_n,
    sr_value_monthly = sr_v, sr_mom_monthly = sr_mo, sr_combo_monthly = sr_c,
    sr_value_ann = sr_v*sqrt(12), sr_combo_ann = sr_c*sqrt(12),
    rho_combo_value = rho_cv,
    sd_paired_diff_monthly = sd(d),
    se_paired_iid = se_iid, se_paired_nw_lag3 = se_nw, nw_inflation_measured = nw_infl),
  mde = list(se_dsr_iid_monthly = se_dsr_iid, se_dsr_nw_monthly = se_dsr,
    mde80_dSR_monthly = mde80_dsr_m, mde80_dSR_annualized = mde80_dsr_ann,
    mde80_mean_diff_annualized = mde80_mean_ann),
  verdict = list(implied_effect_dSR_ann = implied_ann, ratio = ratio,
    expected_t = expected_t, power = power, disposition = disp,
    abort_rule = "ratio < 0.15 -> 착수 중단 (설계 preregistered_power_contract.abort_rule)",
    honesty = "ratio 가 문턱을 넘어도 '검정할 자격'일 뿐이며, 비유의는 검정력이 충분할 때만 '효과 없음'이고 그 외에는 '미결'이다."),
  axis_A_exemption = "axis_A(알파 수준)는 논문 KR-유사물(일본) 함의 증분이 음수(-6.2%p)라 ratio 를 산출하지 않는다(설계 승계).")
write_json(res, file.path(OUT, "s3_power.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(X = X, D = D), file.path(OUT, "s3_objects.rds"))

cat(sprintf("\n[POWER] n=%d  SR_val=%.4f  SR_combo=%.4f  rho=%.4f  NW_infl=%.4f(measured)\n",
            n, sr_v, sr_c, rho_cv, nw_infl))
cat(sprintf("[POWER] MDE80(dSR) monthly=%.5f  annualized=%.4f   implied(JP factor)=%.4f\n",
            mde80_dsr_m, mde80_dsr_ann, implied_ann))
cat(sprintf("[POWER] ratio=%.4f  expected_t=%.4f  power=%.4f  -> %s\n", ratio, expected_t, power, disp))
