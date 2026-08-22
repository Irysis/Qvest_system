## WT-D20260822_010 — 착수 전 관문(NP4 규약) + 노출 중립성 실증
## 사전등록: stage_artifacts/WT-D20260822_010/PREREG_GATE.json (본 스크립트 실행 전 봉인)
## ★본 스크립트는 처치(filtered) 백테스트를 실행하지 않는다 — 관문이 먼저다.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say  <- function(f, ...) cat(sprintf(paste0("[pc] ", f, "\n"), ...))
J <- list()

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/distribution_target_screen.R")   # 직교화 계약 함수 (재구현 금지)
stopifnot(exists(".dts_orthogonalize_by_date"), exists(".dts_z_by_date"), exists(".dts_wins_by_date"))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

## ── A. 입력 ────────────────────────────────────────────────────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
for (d in list(fwd_ret, bench, liqf, SIZE)) d[, Date := as.Date(Date)]
say("fwd_ret 컬럼: %s", paste(names(fwd_ret), collapse = ","))

CLEAN <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1] == "production_parity_verified")   # 헌법 §7b

NP <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/alpha_scores.parquet"))
NP[, Date := as.Date(Date)]
AB <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))
AB[, Date := as.Date(Date)]
fwdNP <- readRDS("stage_artifacts/WT-D20260813_006/fwd.rds")
LIQNP <- as.data.table(fwdNP$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]

say("NP2 패널 %d행/%d월 (%s~%s) | absorb_panel %d행/%d월",
    nrow(NP), uniqueN(NP$Date), as.character(min(NP$Date)), as.character(max(NP$Date)),
    nrow(AB), uniqueN(AB$Date))

## A-2. 동일 객체 확인 — absorb_raw(NP2 소비면) vs absorb(WT-009 소비면)
chk <- merge(NP[, .(Date, Ticker, absorb_raw)], AB[, .(Date, Ticker, absorb)], by = c("Date","Ticker"))
ident <- chk[is.finite(absorb_raw) & is.finite(absorb)]
J$object_identity <- list(
  n_matched = nrow(chk), n_both_finite = nrow(ident),
  max_abs_diff = if (nrow(ident)) max(abs(ident$absorb_raw - ident$absorb)) else NA_real_,
  pearson = if (nrow(ident) > 2) cor(ident$absorb_raw, ident$absorb) else NA_real_,
  note = "WT-009 는 absorb_panel$absorb, NP2 는 alpha_scores$absorb_raw 를 소비했다. 같은 원천인지 실측 확인.")
say("객체 동일성: 매칭 %d행 / 최대 절대차 %.3g / cor %.6f",
    nrow(chk), J$object_identity$max_abs_diff, J$object_identity$pearson)

## ── B. 직교화 축 재구성 (NP2 표본·NP2 규약 verbatim) ────────────────────────
SC <- NP[is.finite(absorb_raw), .(Date, Ticker, score = absorb_raw, win_vol, log_size)]
n0 <- nrow(SC)
SC <- merge(SC, LIQNP, by = c("Date","Ticker"), all.x = TRUE)
SC <- SC[is.na(adv) | adv >= 2e8][, adv := NULL]
say("NP2 표본: liq 전 %d → 후 %d행", n0, nrow(SC))
CTL <- c("win_vol","log_size")
keepv <- Reduce(function(a, b) a & b, lapply(CTL, function(cc) is.finite(SC[[cc]])))
S_ctl <- SC[keepv]
for (cc in CTL) S_ctl[, (cc) := (frank(get(cc)) / .N) - 0.5, by = Date]   # control_transform = "rank" (sealed primary)
for (cc in CTL) S_ctl[, (cc) := .dts_z_by_date(get(cc)), by = Date]
S_ctl[, score_reg := score]
.dts_wins_by_date(S_ctl, "score_reg", c(0.01, 0.99))
.dts_orthogonalize_by_date(S_ctl, "score_reg", CTL, "score_orth")
ORTH <- S_ctl[is.finite(score_orth), .(Date, Ticker, score_orth)]
say("직교화 축: %d행/%d월 (NP2 표본·rank 통제·winsor[0.01,0.99] 회귀좌변 전용)",
    nrow(ORTH), uniqueN(ORTH$Date))
J$orth_axis <- list(n_rows = nrow(ORTH), n_months = uniqueN(ORTH$Date),
  transform = "rank", winsorize_probs = c(0.01, 0.99), controls = CTL,
  contract = "distribution_target_screen.R::.dts_orthogonalize_by_date",
  regression_sample = "NP2 표본(liq 2e8 통과 absorb 패널) — NP2 verbatim",
  cor_with_raw_pooled = cor(S_ctl$score, S_ctl$score_orth, use = "complete.obs"))
say("raw absorb 대비 직교화축 pooled cor = %.4f", J$orth_axis$cor_with_raw_pooled)

## ── C. base 경로 VERBATIM (WT-009 parity2) ─────────────────────────────────
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
d0map <- data.table(d0 = sort(unique(fwd_ret$Date)))[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN)[, map_ym := format(Date - 1, "%Y-%m")]
CLd <- merge(CL, d0map, by.x = "map_ym", by.y = "ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date = d0, Ticker, sc = score_eff)], SIZE, by = c("Date","Ticker"))
S0 <- merge(S0, liqf, by = c("Date","Ticker"), all.x = TRUE)
S0 <- S0[is.na(adv) | adv >= 2e8]
top25_capw <- function(S) {
  dd <- sort(unique(S$Date)); W <- vector("list", length(dd))
  for (i in seq_along(dd)) { sub <- S[Date == dd[i]]; if (nrow(sub) < 25) next
    setorder(sub, -sc); hd <- head(sub, 25)
    W[[i]] <- data.table(Date = dd[i], Ticker = hd$Ticker, w = cap_norm(hd$Size)) }
  rbindlist(W) }
Wb_full <- top25_capw(S0)
rb_full <- weighted_screen_bt(Wb_full, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT010_base_full", strategy_id = "WT010_base_full")
say("base anchor(%d m): PORT_t=%.4f (target 3.0583) IR=%.4f",
    rb_full$n_months, rb_full$portfolio_alpha_t_nw_lag3, rb_full$information_ratio)
if (abs(rb_full$portfolio_alpha_t_nw_lag3 - 3.0583) > 0.01) stop("ANCHOR FAIL — 사전등록 STOP. 측정 무효.")
J$base_anchor <- list(port_t = rb_full$portfolio_alpha_t_nw_lag3, ir = rb_full$information_ratio,
                      n_months = rb_full$n_months, target = 3.0583, pass = TRUE)

## ── D. 배제집합 (X=0.20, WT-009 관례) ──────────────────────────────────────
common_d0 <- sort(intersect(unique(S0$Date), unique(ORTH$Date)))
common_d0 <- as.Date(common_d0, origin = "1970-01-01")
S <- S0[Date %in% common_d0]
SM <- merge(S, ORTH, by = c("Date","Ticker"), all.x = TRUE)
mk_filter <- function(SMin, X, col) {
  S2 <- copy(SMin)
  S2[, thr := { v <- get(col); v <- v[is.finite(v)]
                if (length(v) >= 30L) quantile(v, X, type = 7, names = FALSE) else -Inf }, by = Date]
  S2[, excluded := is.finite(get(col)) & get(col) <= thr]
  S2 }
SMx <- mk_filter(SM, 0.20, "score_orth")
cov_tab <- SMx[, .(n_cand = .N, n_fin = sum(is.finite(score_orth)),
                   n_ex = sum(excluded), n_left = sum(!excluded)), by = Date]
say("paired 공통월 %d | 월평균 후보 %.1f / 축 커버 %.1f%% / 배제 %.1f / 잔여 %.1f (min %d)",
    length(common_d0), cov_tab[, mean(n_cand)], 100*cov_tab[, sum(n_fin)/sum(n_cand)],
    cov_tab[, mean(n_ex)], cov_tab[, mean(n_left)], cov_tab[, min(n_left)])
J$grid <- list(common_months = length(common_d0), base_months = uniqueN(S0$Date),
  orth_months = uniqueN(ORTH$Date), common_start = as.character(min(common_d0)),
  common_end = as.character(max(common_d0)))
J$census <- list(mean_cand = cov_tab[, mean(n_cand)], coverage = cov_tab[, sum(n_fin)/sum(n_cand)],
  mean_excluded = cov_tab[, mean(n_ex)], mean_left = cov_tab[, mean(n_left)],
  min_left = cov_tab[, min(n_left)], months_left_lt25 = cov_tab[, sum(n_left < 25)], n_months = nrow(cov_tab))

## ── E. ★노출 중립성 실증 (1급 진단, WT-009 대비) ───────────────────────────
SZ <- merge(SMx[, .(Date, Ticker, excluded)], SIZE, by = c("Date","Ticker"))
SZ[, srank := frank(Size)/.N, by = Date]
szt <- SZ[, .(e = mean(srank[excluded]), k = mean(srank[!excluded])), by = Date][is.finite(e) & is.finite(k)]
Wb <- top25_capw(S)
SZt <- merge(Wb[, .(Date, Ticker, w)], SZ[, .(Date, Ticker, excluded, srank)], by = c("Date","Ticker"))
neu <- list(
  all_excl_srank = mean(szt$e), all_keep_srank = mean(szt$k),
  all_gap = mean(szt$e - szt$k), all_gap_nw_t = nw_t(szt$e - szt$k), n_months = nrow(szt),
  top25_excl_srank = SZt[excluded == TRUE, mean(srank)], top25_keep_srank = SZt[excluded == FALSE, mean(srank)],
  top25_excl_meanw = SZt[excluded == TRUE, mean(w)], top25_keep_meanw = SZt[excluded == FALSE, mean(w)],
  wt009 = list(all_excl_srank = 0.29958445470238, all_keep_srank = 0.551799941323013,
               all_gap = -0.252215486620633, all_gap_nw_t = -26.6,
               top25_excl_meanw = 0.017831025267214, top25_keep_meanw = 0.0447634152417682))
neu$gap_residual_share <- abs(neu$all_gap) / abs(neu$wt009$all_gap)
say("★중립성: 전후보 배제 srank %.4f vs 잔류 %.4f (gap %+.4f, NW t %+.2f) | WT-009 gap %+.4f",
    neu$all_excl_srank, neu$all_keep_srank, neu$all_gap, neu$all_gap_nw_t, neu$wt009$all_gap)
say("★중립성(top25 내): 배제 srank %.4f vs 잔류 %.4f | 배제 평균비중 %.4f vs 잔류 %.4f (WT-009: %.4f / %.4f)",
    neu$top25_excl_srank, neu$top25_keep_srank, neu$top25_excl_meanw, neu$top25_keep_meanw,
    neu$wt009$top25_excl_meanw, neu$wt009$top25_keep_meanw)
say("   raw 축 대비 잔존 gap 비율 = %.3f (0 = 완전 중립, 1 = 미개선)", neu$gap_residual_share)
J$exposure_neutrality <- neu

## ── F. 꼬리 실현 재현 + 조건부 격차 ────────────────────────────────────────
retcol <- setdiff(names(fwd_ret), c("Date","Ticker"))[1]
RT <- fwd_ret[, .(Date, Ticker, Ret_1m = get(retcol))]
say("fwd_ret 수익 컬럼 = %s", retcol)
Q <- copy(SMx)
Q[, thr_hi := { v <- score_orth; v <- v[is.finite(v)]
   if (length(v) >= 30L) quantile(v, 0.80, type = 7, names = FALSE) else Inf }, by = Date]
Q[, qlo := excluded]
Q[, qhi := is.finite(score_orth) & score_orth >= thr_hi]
QR <- merge(Q[, .(Date, Ticker, qlo, qhi)], RT, by = c("Date","Ticker"))
QR[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
J$tail_realization <- list(lo = QR[qlo == TRUE, mean(tail_hit)], hi = QR[qhi == TRUE, mean(tail_hit)],
  all = QR[, mean(tail_hit)], n_lo = QR[qlo == TRUE, .N], n_hi = QR[qhi == TRUE, .N],
  wt009_raw = list(lo = 0.0505548705302096, hi = 0.0223275134679042),
  note = "부호는 lo > hi 여야 NP2 정합(저-흡수 = 하방꼬리 多).")
say("꼬리 실현율(소비 유니버스): 배제군 %.3f%% / 상위군 %.3f%% / 전체 %.3f%%  [WT-009 raw: 5.055%% / 2.233%%]",
    100*J$tail_realization$lo, 100*J$tail_realization$hi, 100*J$tail_realization$all)

TOP <- merge(Wb[, .(Date, Ticker, w)], SMx[, .(Date, Ticker, excluded)], by = c("Date","Ticker"), all.x = TRUE)
TOP <- merge(TOP, RT, by = c("Date","Ticker"), all.x = TRUE)
TOP[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
cond <- TOP[!is.na(excluded), .(n = .N, tail_rate = mean(tail_hit), mean_ret = mean(Ret_1m, na.rm = TRUE),
                                mean_w = mean(w)), by = excluded]
setorder(cond, excluded)
gap <- cond[excluded == TRUE, tail_rate] - cond[excluded == FALSE, tail_rate]
n_ex_top25 <- TOP[!is.na(excluded), sum(excluded)] / uniqueN(TOP$Date)
mw_ex <- TOP[excluded == TRUE, mean(w)]
say("조건부(base top-25 내): 배제 tail %.4f (n=%d, wbar=%.4f) vs 잔류 tail %.4f (n=%d, wbar=%.4f) | gap %+.6f",
    cond[excluded==TRUE, tail_rate], cond[excluded==TRUE, n], cond[excluded==TRUE, mean_w],
    cond[excluded==FALSE, tail_rate], cond[excluded==FALSE, n], cond[excluded==FALSE, mean_w], gap)
J$conditional_on_top25 <- list(table = as.data.frame(cond), tail_gap = gap,
  n_excluded_per_month = n_ex_top25, mean_weight_excluded = mw_ex,
  wt009 = list(tail_gap = 0.00654685, n_excluded_per_month = 4.42164179104478,
               mean_weight_excluded = 0.017831025267214))

## ── G. ★관문 산술 (PREREG_GATE 봉인식) ─────────────────────────────────────
M_emp <- { a <- TOP[tail_hit == TRUE & is.finite(Ret_1m), mean(Ret_1m)]
           b <- TOP[tail_hit == FALSE & is.finite(Ret_1m), mean(Ret_1m)]; abs(a - b) }
sd_m <- 0.015948597895229; n_m <- length(common_d0)
mde80_m <- (qnorm(0.975) + qnorm(0.80)) * sd_m / sqrt(n_m)
P1_m <- gap * n_ex_top25 * mw_ex * 0.20
P2_m <- gap * n_ex_top25 * mw_ex * M_emp
ratio <- max(P1_m, P2_m) / mde80_m
J$gate <- list(
  sd_monthly = sd_m, n_months = n_m, mde80_monthly = mde80_m, mde80_annual_pp = 1200*mde80_m,
  tail_event_magnitude_P1 = 0.20, tail_event_magnitude_P2_empirical = M_emp,
  P1_monthly = P1_m, P1_annual_pp = 1200*P1_m,
  P2_monthly = P2_m, P2_annual_pp = 1200*P2_m,
  ratio = ratio, threshold = 0.10, pass = (ratio >= 0.10),
  wt009_ratio = 0.123880658156625 / 3.27570277405716,
  formula = "PREREG_GATE.json gate_arithmetic — max(P1,P2)/MDE80")
say("관문: MDE80 = %.6f/월 (연 %.4f%%p) | P1 = %.6g/월 (연 %.4f%%p) | P2(M=%.4f) = %.6g/월 (연 %.4f%%p)",
    mde80_m, 1200*mde80_m, P1_m, 1200*P1_m, M_emp, P2_m, 1200*P2_m)
say("★★관문 ratio = %.4f (문턱 0.10) -> %s   [WT-009 = %.4f = 1/%.0f]",
    ratio, ifelse(ratio >= 0.10, "PASS — 측정 진행", "FAIL — 측정하지 않고 중단"),
    J$gate$wt009_ratio, 1/J$gate$wt009_ratio)

## ── H. PIT ────────────────────────────────────────────────────────────────
source("02_Infrastructure/validation/overlay_pit_guard.R")
d0s <- sort(unique(SM$Date))
res <- sapply(seq_along(d0s), function(i){ d0 <- d0s[i]; hs <- as.Date(format(d0+20,"%Y-%m-01"))
  tryCatch({assert_overlay_pit(d0, hs, "orth_absorb_excl"); TRUE}, error=function(e) FALSE)})
inj <- sapply(seq_along(d0s), function(i){ d0 <- d0s[i]; hs <- as.Date(format(d0+20,"%Y-%m-01"))
  tryCatch({assert_overlay_pit(hs+27, hs, "orth_absorb_INJ"); TRUE}, error=function(e) FALSE)})
say("PIT: assert %d/%d PASS | 위반주입 %d/%d 통과(0 이어야 정상)", sum(res), length(res), sum(inj), length(inj))
J$pit <- list(assert_pass = sum(res), assert_n = length(res), injection_pass = sum(inj),
  detector_alive = (sum(inj) == 0))

saveRDS(list(SMx = SMx, Wb = Wb, S = S, ORTH = ORTH, common_d0 = common_d0, RT = RT),
        file.path(OUT, "00_precheck_objects.rds"))
write_json(J, file.path(OUT, "00_precheck.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done — gate pass = %s", J$gate$pass)
