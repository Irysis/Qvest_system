# S5 — alpha_hat 생성 + 신뢰도 + 진단 배터리
#   alpha_hat_{i,t} = lambda_t * z(score)_{i,t}   (lambda_t = **확장창 t 이전 월만** 사용 = PIT)
#   불확실성 인지(philosophy 3): alpha_lb = alpha_hat - k*SE(alpha_hat), k = 1
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
P <- readRDS(file.path(OUT, "panel.rds")); S4 <- readRDS(file.path(OUT, "s4_objects.rds"))
E <- S4$E; R <- P$fwd$returns_dt; bench <- P$fwd$bench_dt; SIZE <- P$SIZE
BURN <- 36L

D <- merge(E[, .(Date, Ticker, mkt, v01, mom61, pv, pm61, score, adv)],
           R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
D <- merge(D, bench[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
D <- merge(D, SIZE, by = c("Date","Ticker"), all.x = TRUE)
D[, act := Ret_1m - BM_Ret]
D[, z := (score - mean(score))/stats::sd(score), by = Date]
setorder(D, Date, Ticker)
ME <- sort(unique(D$Date))

## 월별 단면 기울기 (Fama-MacBeth 1단계): act ~ z
xs <- D[is.finite(act) & is.finite(z), {
  f <- lm(act ~ z); .(lam = coef(f)[2], se = summary(f)$coefficients[2,2], n = .N) }, by = Date]
setorder(xs, Date)

## 확장창 lambda (t 이전 월만 — PIT C1) + 그 정밀도
xs[, lam_pit := shift(cumsum(lam)/seq_len(.N), 1L)]
xs[, lam_sd  := { v <- rep(NA_real_, .N); for (i in 2:.N) v[i] <- stats::sd(lam[1:(i-1)]); v }]
xs[, k_pit   := shift(seq_len(.N), 1L)]
xs[, lam_se  := lam_sd/sqrt(k_pit)]
xs[k_pit < BURN, `:=`(lam_pit = NA_real_, lam_se = NA_real_)]
D <- merge(D, xs[, .(Date, lam_pit, lam_se, lam_t = lam_pit/lam_se)], by = "Date", all.x = TRUE)
D[, alpha_hat := lam_pit * z]
D[, alpha_se  := abs(lam_se * z)]
D[, alpha_lb  := alpha_hat - 1.0*alpha_se]

## 신뢰도 [0,1]: 자료완결 x 랭크안정 x lambda 정밀도
setorder(D, Ticker, Date)
D[, pv_prev := shift(pv), by = Ticker][, pm_prev := shift(pm61), by = Ticker]
D[, rank_jump := pmin(abs(pv - pv_prev) + abs(pm61 - pm_prev), 2)/2]
D[, c_stab := 1 - fifelse(is.finite(rank_jump), rank_jump, 0.5)]
D[, c_data := fifelse(is.finite(v01) & is.finite(mom61) & is.finite(adv), 1, 0) *
              pmin(1, log10(pmax(adv, 1))/log10(2e9))]
D[, c_prec := pmin(1, pmax(0, abs(fifelse(is.finite(lam_t), lam_t, 0))/2))]
D[, confidence := pmax(0, pmin(1, (c_data*c_stab)^0.5 * (0.5 + 0.5*c_prec)))]
setorder(D, Date, -score)

## ── 진단 배터리 (advisory) ─────────────────────────────────────────────────
icd <- D[is.finite(act) & is.finite(score), .(ic = suppressWarnings(cor(score, act, method = "spearman")), n = .N),
         by = Date][n >= 30L]
rank_ic <- mean(icd$ic); icir <- rank_ic/sd(icd$ic)
m_ic <- lm(icd$ic ~ 1)
ic_t_nw <- as.numeric(coeftest(m_ic, vcov = NeweyWest(m_ic, lag = 3, prewhite = FALSE))[1,3])
harvey_t <- ic_t_nw/sqrt(1 + (1 - 0)^2)   # 단일 검정(n_trials=1) — Harvey-Liu 보정 무증가
## 십분위 단조성
DEC <- D[is.finite(act) & is.finite(score)]
DEC[, dec := as.integer(cut(frank(score), quantile(frank(score), seq(0,1,.1)), labels = FALSE, include.lowest = TRUE)), by = Date]
decm <- DEC[, .(r = mean(act)), by = .(Date, dec)][, .(mean_act_ann = 12*mean(r)), by = dec][order(dec)]
mono <- suppressWarnings(cor(decm$dec, decm$mean_act_ann, method = "spearman"))
## 부기간 안정성
sub <- icd[, .(period = fifelse(Date < as.Date("2015-01-01"), "2005_2014",
                       fifelse(Date < as.Date("2020-01-01"), "2015_2019", "2020_2026")), ic)][
       , .(ic = mean(ic), n = .N), by = period]
subper_stab <- mean(sign(sub$ic) == sign(rank_ic))
## 중립화 후 IC (size + market — sector 미포함, 라벨 정확)
NEU <- D[is.finite(act) & is.finite(score) & is.finite(Size)]
NEU[, lsz := log(Size)]
NEU[, z_res := { f <- if (uniqueN(mkt) > 1L) lm(z ~ lsz + factor(mkt)) else lm(z ~ lsz); residuals(f) }, by = Date]
icn <- NEU[, .(ic = suppressWarnings(cor(z_res, act, method = "spearman")), n = .N), by = Date][n >= 30L]
post_neu_ic <- mean(icn$ic)
## turnover proxy (실측 후보 회전율)
to_ann <- S4$cand$cs$turnover_annual

## ── 저장 ───────────────────────────────────────────────────────────────────
SC <- D[, .(Date, Ticker, mkt, v01_z_aligned = v01, mom_6_1 = mom61,
            pct_rank_value = pv, pct_rank_momentum = pm61, score,
            z_score = z, lambda_pit = lam_pit, alpha_hat, alpha_se, alpha_lb,
            confidence, adv20_t1 = adv, size = Size)]
write_parquet(SC, file.path(OUT, "alpha_scores.parquet"))

asof <- max(ME)
AV <- SC[Date == asof & is.finite(alpha_hat)]
setorder(AV, -alpha_hat)
cat(sprintf("[S5] as_of=%s | universe=%d | alpha_hat mean=%.4f sd=%.4f | conf mean=%.3f\n",
            asof, nrow(AV), mean(AV$alpha_hat), sd(AV$alpha_hat), mean(AV$confidence)))
cat(sprintf("[S5] rank_ic=%.4f icir=%.3f ic_t_nw=%.3f mono=%.3f subper=%.2f post_neu_ic=%.4f TO=%.2f\n",
            rank_ic, icir, ic_t_nw, mono, subper_stab, post_neu_ic, to_ann))
print(decm); print(sub)

diag <- list(rank_ic = rank_ic, icir = icir, ic_t_nw_lag3 = ic_t_nw, harvey_t_stat = harvey_t,
             monotonicity = mono, decile_profile = decm, subperiod = sub,
             subperiod_stability = subper_stab, post_neutralization_ic = post_neu_ic,
             post_neutralization_spec = "log(Size) + market dummy (K200/KQ150). sector 미포함 — 라벨 정확성.",
             turnover_annual_measured = to_ann, ic_months = nrow(icd),
             lambda_pit = list(burn_in_months = BURN, last_lambda = tail(xs$lam_pit, 1),
                               last_lambda_t = tail(xs$lam_pit/xs$lam_se, 1),
                               note = "확장창 평균은 t-1 까지만 — 당월 단면 미사용(PIT C1/C2)"),
             as_of_date = as.character(asof), universe_size_asof = nrow(AV))
saveRDS(list(D = D, SC = SC, AV = AV, xs = xs, diag = diag), file.path(OUT, "s5_objects.rds"))
write_json(diag, file.path(OUT, "s5_diag.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
