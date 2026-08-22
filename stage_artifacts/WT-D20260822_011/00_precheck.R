## WT-D20260822_011 — 착수 전 관문 (epsilon tie-break, 여백-보존 소비 형태)
## 사전등록: stage_artifacts/WT-D20260822_011/PREREG_GATE.json (본 스크립트 실행 전 봉인)
## ★본 스크립트는 처치(tie-break) 백테스트를 실행하지 않는다 — weighted_screen_bt 호출은 base anchor 1회뿐.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260822_011")
say  <- function(f, ...) cat(sprintf(paste0("[pc] ", f, "\n"), ...))
J <- list()
PG <- fromJSON(file.path(OUT, "PREREG_GATE.json"))

source("02_Infrastructure/contracts/weighted_screen_bt.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]), error = function(e) NA_real_)
}
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}

## ── A. 객체 승계 (재구현 금지 — PREREG design.object_inheritance) ──────────
SRC <- "stage_artifacts/WT-D20260822_010/00_precheck_objects.rds"
O <- readRDS(SRC)
SMx <- as.data.table(O$SMx); Wb010 <- as.data.table(O$Wb); S <- as.data.table(O$S)
common_d0 <- O$common_d0; RT <- as.data.table(O$RT)
J$inheritance <- list(source = SRC, md5 = unname(tools::md5sum(SRC)),
  smx_rows = nrow(SMx), months = length(common_d0),
  low_orth_per_month = SMx[, sum(excluded)] / length(common_d0),
  note = "WT-010 verbatim — 직교화축/표식/base 재구현 없음")
say("승계: SMx %d행 / %d월 / 월평균 표식(low_orth) %.1f종 | md5 %s",
    nrow(SMx), length(common_d0), J$inheritance$low_orth_per_month, substr(J$inheritance$md5, 1, 12))

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)]
bench   <- as.data.table(SI$bench)[, Date := as.Date(Date)]
SIZE    <- as.data.table(SI$SIZE)[, Date := as.Date(Date)]

## ── B. base anchor STOP ────────────────────────────────────────────────────
rb <- weighted_screen_bt(Wb010, fwd_ret, bench, cost_bps_oneway = 15,
        run_id = "WT011_base", strategy_id = "WT011_base_common")
say("base anchor(%dm): PORT_t=%.14f (target %.5f) IR=%.6f",
    rb$n_months, rb$portfolio_alpha_t_nw_lag3, PG$anchor_stop$target, rb$information_ratio)
if (abs(rb$portfolio_alpha_t_nw_lag3 - PG$anchor_stop$target) > PG$anchor_stop$tolerance)
  stop("ANCHOR FAIL — 사전등록 STOP. 측정 무효.")
J$base_anchor <- list(port_t = rb$portfolio_alpha_t_nw_lag3, ir = rb$information_ratio,
  n_months = rb$n_months, target = PG$anchor_stop$target, pass = TRUE)

## ── C. 선정 규칙 (벡터화) + base 재현 검증 ─────────────────────────────────
SEL <- SMx[, .(Date, Ticker, sc, Size, excluded)]
pick25 <- function(eps) {
  D <- copy(SEL)[, sc_adj := sc - eps * as.numeric(excluded)]
  setorder(D, Date, -sc_adj)
  D[, rk := seq_len(.N), by = Date]
  hd <- D[rk <= 25L]
  hd[, w := cap_norm(Size), by = Date]
  hd[, .(Date, Ticker, w, sc, excluded)]
}
Wb <- pick25(0)
chkb <- merge(Wb[, .(Date, Ticker, w)], Wb010[, .(Date, Ticker, w010 = w)], by = c("Date","Ticker"))
J$base_reproduction <- list(n_base = nrow(Wb010), n_matched = nrow(chkb),
  max_abs_w_diff = if (nrow(chkb)) max(abs(chkb$w - chkb$w010)) else NA_real_)
say("base 재현: %d/%d 종목 매칭 / 최대 가중 절대차 %.3g",
    nrow(chkb), nrow(Wb010), J$base_reproduction$max_abs_w_diff)
stopifnot(nrow(chkb) == nrow(Wb010), J$base_reproduction$max_abs_w_diff < 1e-12)

## ── D. beta_hat (base-only 구조량) → epsilon 도출 ──────────────────────────
SB <- merge(SEL, RT, by = c("Date","Ticker"), all.x = TRUE)
setorder(SB, Date, -sc); SB[, rk := seq_len(.N), by = Date]
NB <- SB[rk <= 40L & is.finite(Ret_1m)]
slopes <- NB[, {
  if (.N >= 10L && sd(sc) > 0) as.numeric(coef(lm(Ret_1m ~ sc))[2]) else NA_real_
}, by = Date]$V1
beta_hat <- mean(slopes[is.finite(slopes)])
sd_sc <- sd(SEL$sc, na.rm = TRUE)
f <- PG$epsilon_selection$f
dtail_ref <- PG$epsilon_selection$delta_tail_ref
M_ref <- PG$epsilon_selection$M_ref
EPS <- f * dtail_ref * M_ref / beta_hat
J$epsilon <- list(beta_hat = beta_hat, beta_n_months = sum(is.finite(slopes)),
  beta_nw_t = nw_t(slopes[is.finite(slopes)]), sd_score_eff_pooled = sd_sc,
  f = f, delta_tail_ref = dtail_ref, M_ref = M_ref, epsilon = EPS,
  epsilon_in_sd_units = EPS / sd_sc,
  formula = PG$epsilon_selection$formula,
  provenance = "구조 도출 — 성과로 고르지 않았다. 단일 값, sweep 아님.")
say("beta_hat = %.6f (월별 top-40 횡단면 slope 평균, n=%d월, NW t=%.2f) | sd(score_eff)=%.4f",
    beta_hat, J$epsilon$beta_n_months, J$epsilon$beta_nw_t, sd_sc)
say("★ epsilon = f(%.4f) * dtail_ref(%.6f) * M_ref(%.5f) / beta_hat = %.6f (= %.4f sd 단위)",
    f, dtail_ref, M_ref, EPS, EPS/sd_sc)

## ── E. census 함수 (백테 없음) ─────────────────────────────────────────────
kk <- function(d) paste(d$Date, d$Ticker)
turn_of <- function(W) {   # weighted_screen_bt 규약과 동일: traded_t = sum|w_t - w_{t-1}|
  dts <- sort(unique(W$Date)); tr <- numeric(length(dts))
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_c","_p"))
    m[is.na(w_c), w_c := 0]; m[is.na(w_p), w_p := 0]
    tr[i] <- sum(abs(m$w_c - m$w_p)); prev <- cur }
  data.table(Date = dts, traded = tr) }
TURN_B <- turn_of(Wb); turn_base_m <- mean(TURN_B$traded)

census <- function(eps) {
  Wt <- pick25(eps)
  kb <- kk(Wb); kt <- kk(Wt)
  disp <- Wb[!(kb %chin% kt)]          # base 에 있었는데 밀려남
  ins  <- Wt[!(kt %chin% kb)]          # 새로 들어옴
  if (nrow(disp) == 0L) return(NULL)
  disp <- merge(disp, RT, by = c("Date","Ticker"), all.x = TRUE)
  ins  <- merge(ins,  RT, by = c("Date","Ticker"), all.x = TRUE)
  disp[, th := is.finite(Ret_1m) & Ret_1m <= -0.20]
  ins[,  th := is.finite(Ret_1m) & Ret_1m <= -0.20]
  nm <- length(common_d0)
  W_disp <- disp[, sum(w)] / nm
  W_ins  <- ins[,  sum(w)] / nm
  dtail  <- disp[, mean(th)] - ins[, mean(th)]
  ## 구조적 여백 상한 검증: max_i sc_disp - min_j sc_ins < eps (월별)
  mg <- merge(disp[, .(hi = max(sc)), by = Date], ins[, .(lo = min(sc)), by = Date], by = "Date")
  mg[, gap := hi - lo]
  ## 실현 평균 score 격차 (짝 순서 대응)
  setorder(disp, Date, -sc); disp[, r := seq_len(.N), by = Date]
  setorder(ins,  Date, -sc); ins[,  r := seq_len(.N), by = Date]
  pr <- merge(disp[, .(Date, r, sc_d = sc, w_d = w, ret_d = Ret_1m)],
              ins[,  .(Date, r, sc_i = sc)], by = c("Date","r"))
  ## Delta_active 산포(nuisance) — 평균은 게이트에 쓰지 않는다
  gser <- merge(ins[,  .(gi = sum(w * fifelse(is.finite(Ret_1m), Ret_1m, 0))), by = Date],
                disp[, .(gd = sum(w * fifelse(is.finite(Ret_1m), Ret_1m, 0))), by = Date], by = "Date")
  gser[, g := gi - gd]
  sd_gate <- sd(gser$g)
  n_m <- nrow(gser)
  mde80 <- (qnorm(0.975) + qnorm(0.80)) * sd_gate / sqrt(n_m)
  TT <- turn_of(Wt)
  cost_m <- 15e-4 * (mean(TT$traded) - turn_base_m)
  benefit <- W_disp * dtail * M_ref
  mloss   <- W_disp * beta_hat * eps
  net     <- benefit - mloss - cost_m
  list(eps = eps, n_swap_pm = nrow(disp)/nm, W_disp = W_disp, W_ins = W_ins,
       mean_w_disp = disp[, mean(w)], mean_w_ins = ins[, mean(w)],
       tail_disp = disp[, mean(th)], tail_ins = ins[, mean(th)], dtail_repl = dtail,
       mean_ret_disp = disp[, mean(Ret_1m, na.rm=TRUE)], mean_ret_ins = ins[, mean(Ret_1m, na.rm=TRUE)],
       margin_bound_max = mg[, max(gap)], margin_bound_ok = (mg[, max(gap)] < eps + 1e-12),
       realized_margin_mean = pr[, mean(sc_d - sc_i)],
       months_fired = nrow(mg), fire_share = nrow(mg)/nm,
       sd_gate = sd_gate, mde80 = mde80, n_gate_months = n_m,
       turnover_monthly = mean(TT$traded), turnover_delta_annual = 12*(mean(TT$traded) - turn_base_m),
       cost_monthly = cost_m, benefit_monthly = benefit,
       margin_loss_upper_monthly = mloss, net_implied_monthly = net,
       ratio = net / mde80,
       ceiling_ratio = (W_disp * dtail * M_ref) / mde80)
}

## ── F. 사전 고정 epsilon 의 관문 ───────────────────────────────────────────
C1 <- census(EPS)
if (is.null(C1)) stop("사전 고정 epsilon 에서 교체 0건 — 설계 무발동.")
say("--- 사전 고정 epsilon = %.6f ---", EPS)
say("교체 %.3f종/월 (발동월 %.1f%%) | 여백상한 검증: max(sc_disp)-min(sc_ins)=%.6f < eps ? %s",
    C1$n_swap_pm, 100*C1$fire_share, C1$margin_bound_max, C1$margin_bound_ok)
say("displaced 꼬리율 %.4f%% vs inserted %.4f%% (dtail %+.6f) | 평균수익 disp %+.5f vs ins %+.5f",
    100*C1$tail_disp, 100*C1$tail_ins, C1$dtail_repl, C1$mean_ret_disp, C1$mean_ret_ins)
say("편익 %.6g/월 − 여백손실상한 %.6g − 비용 %.6g = 순함의 %+.6g/월 (연 %+.4f%%p)",
    C1$benefit_monthly, C1$margin_loss_upper_monthly, C1$cost_monthly,
    C1$net_implied_monthly, 1200*C1$net_implied_monthly)
say("sd_gate=%.6f (n=%d) → MDE80=%.6f/월 (연 %.4f%%p)", C1$sd_gate, C1$n_gate_months, C1$mde80, 1200*C1$mde80)
say("★★ ratio = %.4f (문턱 0.10) → %s", C1$ratio, ifelse(C1$ratio >= 0.10, "PASS", "FAIL"))
J$gate <- C1
J$gate$threshold <- 0.10
J$gate$pass <- (C1$ratio >= 0.10)

## ── G. 설계공간 상한 (census 전용, 백테 0회, 구성 승계 0건) ────────────────
grid <- c(0.01,0.02,0.05,0.10,0.15,0.20,0.30,0.50,0.75,1.00,1.50,2.00,5.00) * sd_sc
FB <- rbindlist(lapply(grid, function(e) {
  z <- census(e); if (is.null(z)) return(NULL)
  data.table(eps = e, eps_sd = e/sd_sc, n_swap_pm = z$n_swap_pm, W_disp = z$W_disp,
    dtail = z$dtail_repl, sd_gate = z$sd_gate, mde80 = z$mde80,
    benefit = z$benefit_monthly, mloss = z$margin_loss_upper_monthly,
    net = z$net_implied_monthly, ratio = z$ratio, ceiling_ratio = z$ceiling_ratio,
    margin_ok = z$margin_bound_ok) }))
say("--- 설계공간 상한 (여백손실 0 · 비용 0 낙관) ---")
for (i in seq_len(nrow(FB)))
  say("  eps=%.4f (%.2f sd) 교체%.2f종/월 dtail=%+.5f MDE80=%.6f | ceiling=%.4f | net-ratio=%+.4f",
      FB$eps[i], FB$eps_sd[i], FB$n_swap_pm[i], FB$dtail[i], FB$mde80[i], FB$ceiling_ratio[i], FB$ratio[i])
sup_ceiling <- max(FB$ceiling_ratio, na.rm = TRUE)
say("★★ sup_e ceiling_ratio = %.4f (문턱 0.10) → %s", sup_ceiling,
    ifelse(sup_ceiling >= 0.10, "일부 epsilon 은 원리적으로 가능", "어떤 epsilon 도 관문 통과 불가"))
J$feasibility_bound <- list(table = as.data.frame(FB), sup_ceiling_ratio = sup_ceiling,
  threshold = 0.10, any_epsilon_feasible = (sup_ceiling >= 0.10),
  backtests_run_on_grid = 0L,
  note = PG$feasibility_bound$not_a_sweep)

## ── H. WT-010 관문 추정자 재검 (편익 대비항 정정) ──────────────────────────
J$wt010_gate_recheck <- list(
  wt010_reported_ratio = 0.146496205485856,
  wt010_dtail_used = 0.00804952700257582,
  wt010_dtail_vs_replacement = 0.0030983733539892,
  wt010_sd_used = 0.015948597895229,
  wt010_sd_realized_d_active = 0.0202280940341029,
  corrected_ratio = 0.146496205485856 * (0.0030983733539892/0.00804952700257582) *
                    (0.015948597895229/0.0202280940341029),
  reading = "WT-010 관문은 편익을 '배제군 vs 잔류군' 격차로, 산포를 WT-009 상수로 계산했다. 대비항을 '배제군 vs 대체편입군'으로 정정하고 산포를 실현치로 바꾸면 관문 값이 문턱 아래로 내려간다 — 즉 그 라운드는 통과하지 말았어야 했다. 두 정정 모두 측정 전에 계산 가능했다(대체편입군은 랭킹으로 결정되는 결정론적 집합).")
say("WT-010 관문 정정: 0.1465 → %.4f (문턱 0.10)", J$wt010_gate_recheck$corrected_ratio)

## ── I. N1 노출 중립성 (displaced 집합 재스코프) ────────────────────────────
Wt1 <- pick25(EPS); kb <- kk(Wb); kt <- kk(Wt1)
disp1 <- Wb[!(kb %chin% kt)]; ins1 <- Wt1[!(kt %chin% kb)]
VOL <- NULL
vp <- ".cache/rawdata.rds"
SZr <- merge(SIZE[, .(Date, Ticker, Size)], data.table(Date = common_d0), by = "Date")
SZr[, srank := frank(Size)/.N, by = Date]
n1 <- merge(rbind(disp1[, .(Date, Ticker, grp = "disp")], ins1[, .(Date, Ticker, grp = "ins")]),
            SZr[, .(Date, Ticker, srank)], by = c("Date","Ticker"), all.x = TRUE)
n1m <- n1[is.finite(srank), .(d = mean(srank[grp=="disp"]), i = mean(srank[grp=="ins"])), by = Date][is.finite(d) & is.finite(i)]
J$N1_displaced <- list(scope = "displaced vs inserted (실제 교체가 일어난 종목)",
  size_srank_disp = mean(n1m$d), size_srank_ins = mean(n1m$i),
  size_gap = mean(n1m$d - n1m$i), size_gap_abs = abs(mean(n1m$d - n1m$i)),
  size_gap_nw_t = nw_t(n1m$d - n1m$i), n_months = nrow(n1m), threshold = 0.126,
  fired = (abs(mean(n1m$d - n1m$i)) >= 0.126),
  wt010_low_orth_set = list(size_abs = 0.0815245766029775, vol_abs = 0.0597352879667346, fired = FALSE))
say("N1(displaced vs inserted): size srank %.4f vs %.4f (gap %+.4f, |gap| vs 0.126 → %s, NW t %+.2f)",
    J$N1_displaced$size_srank_disp, J$N1_displaced$size_srank_ins, J$N1_displaced$size_gap,
    ifelse(J$N1_displaced$fired, "FIRED", "미발화"), J$N1_displaced$size_gap_nw_t)

## ── J. PIT ────────────────────────────────────────────────────────────────
source("02_Infrastructure/validation/overlay_pit_guard.R")
d0s <- sort(unique(SMx$Date))
res <- sapply(d0s, function(d0){ hs <- as.Date(format(d0+20,"%Y-%m-01"))
  tryCatch({assert_overlay_pit(d0, hs, "eps_tiebreak"); TRUE}, error=function(e) FALSE)})
inj <- sapply(d0s, function(d0){ hs <- as.Date(format(d0+20,"%Y-%m-01"))
  tryCatch({assert_overlay_pit(hs+27, hs, "eps_tiebreak_INJ"); TRUE}, error=function(e) FALSE)})
say("PIT: assert %d/%d PASS | 위반주입 %d/%d 통과(0 이어야 정상)", sum(res), length(res), sum(inj), length(inj))
J$pit <- list(assert_pass = sum(res), assert_n = length(res), injection_pass = sum(inj),
  detector_alive = (sum(inj) == 0))

## ── K. 최종 판정 ──────────────────────────────────────────────────────────
J$decision <- list(
  fixed_epsilon_ratio = C1$ratio, sup_ceiling_ratio = sup_ceiling, threshold = 0.10,
  proceed_to_measurement = (C1$ratio >= 0.10) && (sup_ceiling >= 0.10),
  rule = "PREREG_GATE gate_arithmetic.pass_rule + feasibility_bound.stop_rule")
say("★★★ 최종: 사전고정 ratio %.4f / sup ceiling %.4f → %s",
    C1$ratio, sup_ceiling, ifelse(J$decision$proceed_to_measurement, "측정 진행", "측정하지 않고 중단 보고"))

saveRDS(list(Wb = Wb, SEL = SEL, EPS = EPS, C1 = C1, FB = FB, RT = RT),
        file.path(OUT, "00_precheck_objects.rds"))
write_json(J, file.path(OUT, "00_precheck.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done — gate pass = %s", J$gate$pass)
