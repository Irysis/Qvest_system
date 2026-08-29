# S5 — alpha_vector / confidence_vector / alpha_scores.parquet + beta-통제 검정력 (WT-R20260829_002)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%||%` <- function(a, b) if (is.null(a)) b else a
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
O <- readRDS(file.path(OUT, "s2_objects.rds")); P <- readRDS(file.path(OUT, "panel.rds"))
S <- O$S; R <- O$R; SIZE <- O$SIZE; fwd <- P$fwd

## ── beta-통제 대비의 검정력 (raw 대비는 시장노출이 sd 를 지배 — §2 정합) ──
ba_pw <- function(M, implied_ann, label, implied_src) {
  f <- lm(d ~ bm, data = M); ct <- coeftest(f, vcov = NeweyWest(f, lag=3, prewhite=FALSE))
  a_ann <- 12*ct[1,1]; t_a <- ct[1,3]
  se_ann <- abs(a_ann)/abs(t_a)
  mde80_ann <- 2.8016 * se_ann
  ratio <- implied_ann/mde80_ann
  list(label=label, alpha_ann=a_ann, t_alpha=t_a, se_alpha_ann=se_ann,
       mde80_annual=mde80_ann, implied_annual=implied_ann, implied_source=implied_src,
       ratio=ratio, expected_t=ratio*2.8016, power=pnorm(ratio*2.8016-1.96),
       disposition=if (ratio<0.15) "착수금지구간(우연 수준)" else if (ratio<0.70) "조건부(미결이 최빈 결말)" else "통상")
}
pw_beta <- list(
  axisA = ba_pw(O$C21, 0.0494, "Δ(cell2−cell1) β-통제 α",
                "IM2013 Table 1 — Down 포트 CAPM α −4.94%/yr (숏 레그 α 기여의 절대값)"),
  axisB = ba_pw(O$C42, abs(12*mean(O$C42$d[1:floor(nrow(O$C42)/3)])), "Δ(cell4−cell2) β-통제 α",
                sprintf("IS-only(전반 %d개월) 실측 앵커 — IM2013 은 집중 형태 효과크기 미제공",
                        floor(nrow(O$C42)/3))))

## ── 창 도달가능성 상한 (2.95 미달 보고 시 양성 대조 의무, §3) ──
##   이 창(259개월)에서 cell4 활성수익 계열의 sd 로 PORT_t 2.95 에 필요한 효과크기
pr4 <- O$cells$cell4_LO_top25$pr; act4 <- pr4$ret_net - pr4$benchmark_ret
reach <- list(
  n_months = length(act4), sd_monthly_active = sd(act4),
  required_active_ann_for_t2.95 = 2.95 * sd(act4)/sqrt(length(act4)) * 12,
  observed_active_ann = 12*mean(act4),
  note = "이 창에서 PORT_t 2.95 에 필요한 활성수익. 관측치와 나란히 읽어야 '신호 약함' 과 '창 짧음' 이 구분된다.")

## ── Fama-MacBeth 단면 기울기 (α̂ 스케일의 데이터 추정 — 하드코딩 금지) ──
SR <- merge(S, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
SR[, z := { r <- frank(score, ties.method="average"); q <- (r-0.5)/.N; qnorm(pmin(pmax(q,1e-4),1-1e-4)) }, by = Date]
fm <- SR[, { f <- lm(Ret_1m ~ z); .(b = coef(f)[2]) }, by = Date]
fm_t <- { m <- lm(fm$b ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
slope <- mean(fm$b)
cat(sprintf("[S5] FM slope(Ret_1m ~ z) = %.6f/월 (연 %.3f%%) NW-t=%.3f · n=%d\n",
            slope, 100*12*slope, fm_t, nrow(fm)))

## ── as_of 단면 α̂ / confidence ──
as_of <- max(S$Date)
CS <- S[Date == as_of]
CS[, z := { r <- frank(score, ties.method="average"); q <- (r-0.5)/.N; qnorm(pmin(pmax(q,1e-4),1-1e-4)) }]
CS[, alpha_hat := slope * z]                       # 1M 기대 초과수익 (FM 기울기 스케일)
# confidence: (1) 최근 6개월 랭크 안정성 (2) 유동성 여유 (3) 형성기 커버리지
hist <- S[Date > as_of - 200][, zz := { r<-frank(score,ties.method="average"); (r-0.5)/.N }, by=Date]
stab <- hist[, .(n_obs=.N, rank_sd=sd(zz)), by=Ticker]
liq <- fwd$liq_dt[Date == as_of, .(Ticker, adv)]
CS <- merge(CS, stab, by="Ticker", all.x=TRUE)
CS <- merge(CS, liq, by="Ticker", all.x=TRUE)
CS[, c_stab := 1 - pmin(1, (rank_sd %||% NA_real_)/0.30)]
CS[!is.finite(c_stab), c_stab := 0.4]
CS[, c_liq := pmin(1, log10(pmax(adv, 1e8)/2e8)/1.0)]
CS[!is.finite(c_liq), c_liq := 0.3]
CS[, c_cov := pmin(1, (n_obs %||% 0)/6)]
CS[!is.finite(c_cov), c_cov := 0.3]
CS[, confidence := pmin(1, pmax(0, 0.5*c_stab + 0.3*c_liq + 0.2*c_cov))]
setorder(CS, -alpha_hat)
cat(sprintf("[S5] as_of=%s · N=%d · alpha_hat [%.4f, %.4f] · conf median %.3f\n",
            as_of, nrow(CS), min(CS$alpha_hat), max(CS$alpha_hat), median(CS$confidence)))

## ── alpha_scores.parquet (전 패널 — 다운스트림 소비용) ──
PANEL <- copy(SR)[, .(Date, Ticker, score, z, alpha_hat = slope*z)]
PANEL <- merge(PANEL, unique(S[, .(Date, Ticker)]), by=c("Date","Ticker"))
arrow::write_parquet(PANEL, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[S5] alpha_scores.parquet: %d rows · %d months\n", nrow(PANEL), uniqueN(PANEL$Date)))

saveRDS(list(CS=CS, slope=slope, fm_t=fm_t, pw_beta=pw_beta, reach=reach), file.path(OUT,"s5_objects.rds"))
write_json(list(fm_slope_monthly=slope, fm_slope_nw_t=fm_t, n_months=nrow(fm),
                as_of_date=as.character(as_of), n_names=nrow(CS),
                power_beta_controlled=pw_beta, reachability_ceiling=reach),
           file.path(OUT,"s5_alpha_meta.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
cat("\n=== beta-통제 검정력 ===\n"); str(pw_beta, max.level=2)
cat("\n=== 창 도달가능성 ===\n"); print(unlist(reach[1:4]))
