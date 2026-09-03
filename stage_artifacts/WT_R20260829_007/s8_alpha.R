# S8 — alpha_hat / confidence_vector / alpha_scores.parquet
#   발행 신호 = strict-PIT 판 (fh_lag1d = 월말 직전 거래일 종가 기준 근접도) — S5b 판정 승계.
#   예측식 = 근접도 단일팩터. lambda 는 Fama-MacBeth 시계열 평균(데이터 추정 — 하드코딩 0).
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
O5b <- readRDS(file.path(OUT, "s5b_objects.rds"))
E0 <- O2$E0; P <- O4$P; X <- O5b$X; Wn <- O5b$Wn
rz <- function(v) { n <- sum(is.finite(v)); q <- (frank(v, ties.method="average", na.last="keep")-0.5)/n
  qnorm(pmin(pmax(q, 1e-4), 1-1e-4)) }
nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }

## ── strict 신호 위에서 lambda 재추정 (무통제 / 전통제) ──────────────────────
D <- merge(P, X[, .(Date, Ticker, fh_lag1d)], by = c("Date","Ticker"), all.x = TRUE)
CTRL <- c("jt6","logsize","ind6","rv63","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda","D35_RealVol_63d","lo52")
for (cc in c("fh_lag1d", CTRL)) D[, (paste0("z_",cc)) := rz(get(cc)), by = .(Date, mkt)]
fit_lam <- function(ctr) {
  vs <- c("z_fh_lag1d", if (length(ctr)) paste0("z_", ctr) else NULL)
  d <- D[, c("Date","Ret_1m", vs), with = FALSE]; for (v in vs) d <- d[is.finite(get(v))]
  d <- d[is.finite(Ret_1m)]
  co <- d[, { if (.N < 40L) NULL else as.list(coef(lm(as.formula(paste("Ret_1m ~", paste(vs, collapse=" + "))), data=.SD))) }, by=Date]
  list(lambda = mean(co$z_fh_lag1d, na.rm=TRUE), nw_t = nw_t(co$z_fh_lag1d), n = nrow(co)) }
L0 <- fit_lam(character(0)); L5 <- fit_lam(CTRL)
cat(sprintf("[S8] strict lambda(무통제)=%+.6f/월 (t %+.3f) | lambda(전통제)=%+.6f/월 (t %+.3f)\n",
            L0$lambda, L0$nw_t, L5$lambda, L5$nw_t))

PANEL <- copy(D[is.finite(fh_lag1d), .(Date, Ticker, mkt, fh_lag1d, fh_same_close = fh252, fh12m, lo52,
                                       Size, rv63, amih20, z_fh = z_fh_lag1d)])
PANEL[, alpha_hat := L0$lambda*z_fh - mean(L0$lambda*z_fh, na.rm=TRUE), by = Date]
PANEL[, alpha_hat_full_control := L5$lambda*z_fh - mean(L5$lambda*z_fh, na.rm=TRUE), by = Date]
PANEL <- merge(PANEL, unique(Wn[, .(Date, Ticker, in_top25 = TRUE)]), by = c("Date","Ticker"), all.x = TRUE)
PANEL[is.na(in_top25), in_top25 := FALSE]

## as_of 단면은 수익이 아직 실현되지 않은 최신 월말도 포함해야 한다
XS <- merge(E0[, .(Date, Ticker, mkt, Size, rv63, amih20, adv)], X[, .(Date, Ticker, fh_lag1d)],
            by = c("Date","Ticker"))
XS <- XS[is.finite(fh_lag1d)]
XS[, z_fh := rz(fh_lag1d), by = .(Date, mkt)]
XS[, alpha_hat := L0$lambda*z_fh - mean(L0$lambda*z_fh, na.rm=TRUE), by = Date]
XS[, alpha_hat_full_control := L5$lambda*z_fh - mean(L5$lambda*z_fh, na.rm=TRUE), by = Date]
as_of <- max(XS$Date)
hist <- XS[Date > as_of - 200][, zz := (frank(fh_lag1d, ties.method="average")-0.5)/.N, by = .(Date, mkt)]
stab <- hist[, .(n_obs = .N, rank_sd = sd(zz), vol_sd = sd(rv63, na.rm=TRUE)), by = Ticker]
CS <- merge(XS[Date == as_of], stab, by = "Ticker", all.x = TRUE)
CS[, c_stab := 1 - pmin(1, rank_sd/0.30)];                CS[!is.finite(c_stab), c_stab := 0.40]
CS[, c_liq  := pmin(1, log10(pmax(adv, 1e8)/2e8)/1.0)];   CS[!is.finite(c_liq), c_liq := 0.30]
CS[, c_cov  := pmin(1, n_obs/6)];                         CS[!is.finite(c_cov), c_cov := 0.30]
CS[, c_vol  := 1 - pmin(1, vol_sd/0.02)];                 CS[!is.finite(c_vol), c_vol := 0.40]
CS[, confidence := pmin(1, pmax(0, 0.35*c_stab + 0.25*c_liq + 0.15*c_cov + 0.25*c_vol))]
setorder(CS, -alpha_hat)
cat(sprintf("[S8] as_of=%s N=%d alpha_hat [%.5f, %.5f] conf median %.3f | top5 %s\n",
            as.character(as_of), nrow(CS), min(CS$alpha_hat), max(CS$alpha_hat), median(CS$confidence),
            paste(CS$Ticker[1:5], collapse=" ")))

OUTPANEL <- rbind(
  PANEL[, .(Date, Ticker, mkt, fh_lag1d, z_fh, alpha_hat, alpha_hat_full_control, in_top25)],
  XS[Date == as_of, .(Date, Ticker, mkt, fh_lag1d, z_fh, alpha_hat, alpha_hat_full_control, in_top25 = FALSE)][
    !PANEL[, .(Date, Ticker)], on = c("Date","Ticker")], fill = TRUE)
arrow::write_parquet(OUTPANEL[order(Date, -alpha_hat)], file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[S8] alpha_scores.parquet %d rows / %d months (%s ~ %s)\n", nrow(OUTPANEL), uniqueN(OUTPANEL$Date),
            min(OUTPANEL$Date), max(OUTPANEL$Date)))

## ── 중복성 (Factor Zoo 축소 ①) ──────────────────────────────────────────────
FDB <- O4$FDB
RD <- merge(PANEL[, .(Date, Ticker, fh_lag1d)], FDB, by = c("Date","Ticker"))
fns <- c("M06_High_52w","M17_Low_52w","M02_Mom_6_1","M07_IndMom","D35_RealVol_63d",
         "L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda")
redc <- lapply(fns, function(cc) { v <- RD[is.finite(get(cc)), .(r = cor(fh_lag1d, get(cc), method="spearman")), by = Date]
  list(factor = cc, mean_monthly_spearman = mean(v$r, na.rm=TRUE), n_months = nrow(v)) })
names(redc) <- fns
cat("[S8] 중복성 (월별 Spearman 평균 vs 발행 신호):\n")
for (k in fns) cat(sprintf("   %-18s %+0.4f\n", k, redc[[k]]$mean_monthly_spearman))

write_json(list(
  as_of_date = as.character(as_of), n_names = nrow(CS),
  published_signal = "fh_lag1d = Close_{t-1 거래일} / max(Close, 그 시점까지 252 거래일) — strict-PIT 판(S5b 판정 승계). ast_field_map A1 가용성 't1' 규칙 정합.",
  forecast_rule = "alpha_hat = lambda_FM * z(근접도, 시장-내 정규분위) - 단면평균. lambda_FM = 무통제 Fama-MacBeth 시계열 평균 기울기(데이터 추정). 병기 alpha_hat_full_control = 전 통제 사양 lambda 판.",
  lambda_no_control_monthly = L0$lambda, lambda_no_control_nw_t = L0$nw_t,
  lambda_full_control_monthly = L5$lambda, lambda_full_control_nw_t = L5$nw_t,
  lambda_attenuation = L5$lambda/L0$lambda,
  confidence_rule = "0.35*랭크안정성 + 0.25*유동성 + 0.15*커버리지 + 0.25*변동성안정성",
  redundancy_check = redc,
  redundancy_reading = "발행 신호와 등재 M06_High_52w 의 월별 Spearman 이 ~1 이다 — 본 재료는 신규 발굴이 아니라 기존 등재 팩터의 재검증이다(Factor Zoo 축소 원칙 1 정합)."),
  file.path(OUT, "s8_alpha_meta.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(CS = CS, PANEL = OUTPANEL, redc = redc, L0 = L0, L5 = L5),
        file.path(OUT, "s8_objects.rds"))
cat("[S8] done\n")
