# S6 — α̂ / confidence / alpha_scores.parquet + β-통제 검정력 + 창 도달가능성
# WT-R20260829_003 · 예측식 = 회전율 층별 Fama-MacBeth (층화의 예측 표현 — 연속 composite 아님)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%||%` <- function(a, b) if (is.null(a)) b else a
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
P <- readRDS(file.path(OUT, "panel.rds")); O <- readRDS(file.path(OUT, "s2_objects.rds"))
S4 <- readRDS(file.path(OUT, "s4_objects.rds"))
E <- O$E; R <- O$R; ER <- O$ER; fwd <- P$fwd; bench <- O$bench

## ── 층별 Fama-MacBeth ───────────────────────────────────────────────────────
ER[, z := { r <- frank(score, ties.method="average"); q <- (r-0.5)/.N; qnorm(pmin(pmax(q,1e-4),1-1e-4)) }, by = Date]
fm <- ER[, { out <- lapply(1:3, function(v) { d <- .SD[vter == v]
               if (nrow(d) < 8L) return(data.table(vter=v, a=NA_real_, b=NA_real_))
               f <- lm(Ret_1m ~ z, data = d); data.table(vter=v, a=coef(f)[1], b=coef(f)[2]) })
             rbindlist(out) }, by = Date, .SDcols = c("vter","z","Ret_1m")]
fmc <- fm[, .(a = mean(a, na.rm=TRUE), b = mean(b, na.rm=TRUE),
              a_t = { m <- lm(a ~ 1, data = .SD); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) },
              b_t = { m <- lm(b ~ 1, data = .SD); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) },
              n = sum(is.finite(a))), by = vter][order(vter)]
cat("[S6] 층별 FM (월간):\n"); print(fmc)
## 층 간 절편 차 검정 (저회전 층 프리미엄의 회귀판)
fw <- dcast(fm, Date ~ vter, value.var = "a"); setnames(fw, c("Date","a1","a2","a3"))
fw <- fw[is.finite(a1) & is.finite(a3)][, d := a1 - a3]
mfw <- lm(d ~ 1, data = fw); ctfw <- coeftest(mfw, vcov = NeweyWest(mfw, lag=3, prewhite=FALSE))
fm_intercept_gap <- list(v1_minus_v3_monthly = mean(fw$d), annualized = 12*mean(fw$d),
                         nw_t = as.numeric(ctfw[1,3]), n = nrow(fw),
                         note = "층별 절편 차 = z 를 고정한 상태의 저회전 프리미엄(회귀판 1급 보조).")

## ── as_of 단면 α̂ ───────────────────────────────────────────────────────────
as_of <- max(E$Date)
CS <- copy(E[Date == as_of])
CS[, z := { r <- frank(score, ties.method="average"); q <- (r-0.5)/.N; qnorm(pmin(pmax(q,1e-4),1-1e-4)) }]
CS <- merge(CS, fmc[, .(vter, a, b)], by = "vter", all.x = TRUE)
CS[, fit := a + b*z]
CS[, alpha_hat_stratified := fit - mean(fit, na.rm = TRUE)]   # 층별 FM 실측 예측(데이터가 말하는 것)
## ★발행 스펙 = 사전등록 2급 arm B (저회전 V1 정의역 제한). V1 층 FM 기울기로 스케일 후 정의역 내 중심화.
b_v1 <- fmc[vter == 1L, b]
CS[, alpha_hat := NA_real_]
CS[vter == 1L, alpha_hat := b_v1*z - mean(b_v1*z)]
hist <- E[Date > as_of - 200][, zz := { r<-frank(score,ties.method="average"); (r-0.5)/.N }, by=Date]
stab <- hist[, .(n_obs = .N, rank_sd = sd(zz)), by = Ticker]
liq  <- fwd$liq_dt[Date == as_of, .(Ticker, adv)]
tstab <- E[Date > as_of - 200][, .(turn_sd = sd(tr)), by = Ticker]
CS <- merge(CS, stab, by="Ticker", all.x=TRUE); CS <- merge(CS, liq, by="Ticker", all.x=TRUE, suffixes=c("","_y"))
CS <- merge(CS, tstab, by="Ticker", all.x=TRUE)
CS[, c_stab := 1 - pmin(1, rank_sd/0.30)];      CS[!is.finite(c_stab), c_stab := 0.4]
CS[, c_liq  := pmin(1, log10(pmax(adv, 1e8)/2e8)/1.0)]; CS[!is.finite(c_liq), c_liq := 0.3]
CS[, c_cov  := pmin(1, n_obs/6)];               CS[!is.finite(c_cov), c_cov := 0.3]
CS[, c_turn := 1 - pmin(1, turn_sd/0.25)];      CS[!is.finite(c_turn), c_turn := 0.4]
CS[, confidence := pmin(1, pmax(0, 0.40*c_stab + 0.25*c_liq + 0.15*c_cov + 0.20*c_turn))]
setorder(CS, -alpha_hat, na.last = TRUE)
cat(sprintf("[S6] as_of=%s N=%d (spec domain V1 n=%d) alpha_hat[%.5f, %.5f] conf median %.3f\n",
            as_of, nrow(CS), sum(is.finite(CS$alpha_hat)),
            min(CS$alpha_hat, na.rm=TRUE), max(CS$alpha_hat, na.rm=TRUE), median(CS$confidence)))

## ── alpha_scores.parquet (전 패널) ──────────────────────────────────────────
PANEL <- merge(ER[, .(Date, Ticker, mkt, score, z, turn_form, tr, vter, advt)], fmc[, .(vter, a, b)], by = "vter")
PANEL[, fit := a + b*z]
PANEL[, alpha_hat_stratified := fit - mean(fit, na.rm=TRUE), by = Date]
PANEL[, alpha_hat := NA_real_]
PANEL[vter == 1L, alpha_hat := b_v1*z - mean(b_v1*z), by = Date]
PANEL <- PANEL[, .(Date, Ticker, mkt, score, z, turn_form, turnover_rank_mktint = tr, vter, advt,
                   alpha_hat, alpha_hat_stratified,
                   in_spec_domain_armB = vter == 1L, in_spec_domain_armC = vter %in% c(1L,2L))]
setorder(PANEL, Date, -alpha_hat_stratified)
arrow::write_parquet(PANEL, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[S6] alpha_scores.parquet: %d rows · %d months\n", nrow(PANEL), uniqueN(PANEL$Date)))

## ── β-통제 검정력 (2급 증분) ───────────────────────────────────────────────
arms <- S4$arms
ba_pw <- function(nm, implied_ann, implied_src) {
  m <- merge(arms[[nm]]$pr[, .(date, r = ret_net)], arms$A_uncond_top25$pr[, .(date, r0 = ret_net)], by="date")
  m <- merge(m, bench[, .(date = Date, bm = BM_Ret)], by = "date"); m[, d := r - r0]
  f <- lm(d ~ bm, data = m); ct <- coeftest(f, vcov = NeweyWest(f, lag=3, prewhite=FALSE))
  a_ann <- 12*ct[1,1]; t_a <- ct[1,3]; se_ann <- abs(a_ann)/abs(t_a); mde80 <- 2.8016*se_ann
  ratio <- implied_ann/mde80
  list(arm = nm, alpha_ann = a_ann, t_alpha = t_a, se_alpha_ann = se_ann, mde80_annual = mde80,
       implied_annual = implied_ann, implied_source = implied_src, ratio = ratio,
       expected_t = ratio*2.8016, power = pnorm(ratio*2.8016 - 1.96),
       disposition = if (ratio < 0.15) "착수금지구간(우연 수준)" else if (ratio < 0.70) "조건부(미결이 최빈 결말)" else "통상") }
LS_ANN_LO <- 0.0072; LS_ANN_HI <- 0.0218   # (1+0.0006)^12-1 / (1+0.0018)^12-1
src <- "LS2000 Table II/VI 승자 사이드 V1-V3 Year-1 (+0.06 ~ +0.18%/월) 의 연복리 환산"
power_incr <- list(
  C_exclude_V3_low  = ba_pw("C_exclude_V3_top25", LS_ANN_LO, src),
  C_exclude_V3_high = ba_pw("C_exclude_V3_top25", LS_ANN_HI, src),
  B_lowturn_V1_low  = ba_pw("B_lowturn_V1_top25", LS_ANN_LO, src),
  B_lowturn_V1_high = ba_pw("B_lowturn_V1_top25", LS_ANN_HI, src))

## ── 창 도달가능성 상한 (2.95 미달 보고 시 의무) ─────────────────────────────
reach <- lapply(names(arms), function(nm) {
  pr <- arms[[nm]]$pr; act <- pr$ret_net - pr$benchmark_ret
  list(arm = nm, n_months = length(act), sd_monthly_active = sd(act),
       required_active_ann_for_t295 = 2.95*sd(act)/sqrt(length(act))*12,
       observed_active_ann = 12*mean(act),
       coverage_ratio = (12*mean(act)) / (2.95*sd(act)/sqrt(length(act))*12)) })
names(reach) <- names(arms)

write_json(list(
  as_of_date = as.character(as_of), n_names = nrow(CS),
  fm_by_turnover_stratum = lapply(split(fmc, seq_len(nrow(fmc))), as.list),
  fm_intercept_gap_v1_minus_v3 = fm_intercept_gap,
  forecast_rule = "발행 스펙(arm B 사전등록) alpha_hat = b_V1 * z_mom - 정의역내 평균, V1(저회전 층) 정의역에만 정의. 병기 alpha_hat_stratified = (a_v + b_v * z_mom) - 단면평균 (층별 FM 실측 — 데이터가 말하는 것). a_v/b_v = 회전율 층 v 의 Fama-MacBeth 시계열 평균 계수(데이터 추정 — 하드코딩 0). 층화의 예측 표현이며 연속 composite 점수가 아니다.",
  power_increment_beta_controlled = power_incr,
  reachability_ceiling = reach),
  file.path(OUT, "s6_alpha_meta.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(CS = CS, fmc = fmc, PANEL = PANEL, power_incr = power_incr, reach = reach,
             fm_intercept_gap = fm_intercept_gap), file.path(OUT, "s6_objects.rds"))

cat("\n=== FM 층 절편 차 (V1-V3) ===\n")
cat(sprintf("%.4f%%/월 (연 %.2f%%) NW-t=%+.3f n=%d\n", 100*fm_intercept_gap$v1_minus_v3_monthly,
            100*fm_intercept_gap$annualized, fm_intercept_gap$nw_t, fm_intercept_gap$n))
cat("\n=== β-통제 증분 검정력 ===\n")
for (k in names(power_incr)) { x <- power_incr[[k]]
  cat(sprintf("%-18s a=%+6.2f%%/yr t=%+6.3f MDE80=%.4f implied=%.4f ratio=%.4f E[t]=%.3f power=%.3f %s\n",
              k, 100*x$alpha_ann, x$t_alpha, x$mde80_annual, x$implied_annual, x$ratio, x$expected_t, x$power, x$disposition)) }
cat("\n=== 창 도달가능성 ===\n")
for (k in names(reach)) { x <- reach[[k]]
  cat(sprintf("%-22s 필요 활성 %+.2f%%/yr · 관측 %+.2f%%/yr · 비율 %.3f (n=%d)\n",
              k, 100*x$required_active_ann_for_t295, 100*x$observed_active_ann, x$coverage_ratio, x$n_months)) }
