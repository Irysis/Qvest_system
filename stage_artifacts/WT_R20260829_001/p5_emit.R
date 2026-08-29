## p5_emit.R — WT-R20260829_001 Phase 5: alpha_vector / confidence_vector / inheritance
## 불확실성-인지 예측(P3, Liao-Ma-Neuhierl-Schilling 2025): 점추정이 아니라 하한 병기.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(sandwich); library(lmtest)})
setDTthreads(2)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_R20260829_001"

SC    <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
RET   <- as.data.table(read_parquet(file.path(OUT,"panel_returns.parquet")))
BENCH <- as.data.table(read_parquet(file.path(OUT,"panel_bench.parquet")))
FW    <- as.data.table(read_parquet(file.path(OUT,"panel_factors.parquet")))
for (nm in c("SC","RET","BENCH","FW")) { d <- get(nm); d[, Date := as.Date(Date)] }

.nwt <- function(x, lag=3L){ x <- x[is.finite(x)]; m <- lm(x ~ 1)
  as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,3]) }
.nwse <- function(x, lag=3L){ x <- x[is.finite(x)]; m <- lm(x ~ 1)
  as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,2]) }

## ── 1. 부모 신호(기저 RP_20260829_122020_9192 = JT1993 6-1 형성수익) 재구성 ────
## 형성수익 = t-2..t-7 월수익 로그합. 월수익은 RET(Date=신호월, Ret_1m=익월 실현)에서
## Date=t-k 의 Ret_1m 이 t-k+1 월 실현수익이라는 관계로 역산 — 저장 패널 재사용 아님.
MR <- RET[, .(Date, Ticker, mr = Ret_1m)]
setorder(MR, Ticker, Date)
MR[, gap := as.integer(Date - shift(Date,1L)), by=Ticker]
for (k in 1:6) MR[, paste0("l",k) := shift(log1p(mr), k), by=Ticker]
MR[, form_parent := l1+l2+l3+l4+l5+l6]
PAR <- MR[is.finite(form_parent), .(Date, Ticker, form_parent)]
J <- merge(SC, PAR, by=c("Date","Ticker"))
inh <- J[, .(rho = suppressWarnings(cor(score_min_all, form_parent, method="spearman")), n=.N),
         by=Date][n>=30]
ALPHA_INHERITANCE_COR <- mean(abs(inh$rho), na.rm=TRUE)
inh_mom <- merge(SC, PAR, by=c("Date","Ticker"))[, .(rho=suppressWarnings(cor(score_mom, form_parent, method="spearman")), n=.N), by=Date][n>=30]
cat(sprintf("[inheritance] |rho|(2way min-rank, 부모형성수익) 평균 = %.4f | (M02, 부모) = %.4f\n",
    ALPHA_INHERITANCE_COR, mean(abs(inh_mom$rho), na.rm=TRUE)))

## ── 2. 기대 초과수익 사상 — score_min_all → 1M active (Fama-MacBeth 기울기) ────
SR <- merge(SC, RET, by=c("Date","Ticker"))
SR <- merge(SR, BENCH, by="Date")
SR[, act := Ret_1m - BM_Ret]
fm <- SR[is.finite(score_min_all) & is.finite(act),
         { f <- try(lm(act ~ score_min_all), silent=TRUE)
           if (inherits(f,"try-error")) NULL else .(b = coef(f)[["score_min_all"]], n=.N) }, by=Date][n>=30]
b_hat <- mean(fm$b); b_se <- .nwse(fm$b); b_t <- .nwt(fm$b)
cat(sprintf("[map] FM 기울기 b(min-rank → 1M active) = %.5f (NW-se %.5f, t %.3f, n=%d월)\n",
    b_hat, b_se, b_t, nrow(fm)))
b_lb <- b_hat - 1.0*b_se        # 불확실성-인지 하한 (k=1)

## ── 3. 최신 단면 alpha_vector / confidence_vector ───────────────────────────
last_d <- max(SC$Date)
X <- SC[Date==last_d]
mu <- mean(X$score_min_all, na.rm=TRUE)
X[, alpha_hat    := b_hat * (score_min_all - mu)]
X[, alpha_hat_lb := b_lb  * (score_min_all - mu)]
## 배포 집합 = joint-top 셀 (score_joint 유한) — 셀 밖은 alpha 미발행(NA 아님, 0 아님: 제외)
DEP <- X[is.finite(score_joint)]
setorder(DEP, -score_min_all)

## confidence: ①리프 가용성(2/2) ②단면 랭크 안정성(직전월 대비 |Δrank|) ③부기간 안정성(상수, 낮음)
prev_d <- sort(unique(SC$Date)); prev_d <- prev_d[length(prev_d)-1L]
P <- SC[Date==prev_d, .(Ticker, prev = score_min_all)]
DEP <- merge(DEP, P, by="Ticker", all.x=TRUE)
DEP[, rank_stab := fifelse(is.finite(prev), 1 - pmin(1, abs(score_min_all - prev)), 0.4)]
SUBPERIOD_STABILITY <- 1/3    # 3개 부기간 중 1개만 양(+) NW-t (2.14 / -1.14 / -0.39)
DEP[, confidence := pmax(0, pmin(1, 0.5*rank_stab + 0.5*SUBPERIOD_STABILITY))]

cat(sprintf("[emit] as_of=%s | joint-top 셀 %d종목 | alpha_hat 범위 [%.4f%%, %.4f%%]/월 · 하한 [%.4f%%, %.4f%%]\n",
    as.character(last_d), nrow(DEP), 100*min(DEP$alpha_hat), 100*max(DEP$alpha_hat),
    100*min(DEP$alpha_hat_lb), 100*max(DEP$alpha_hat_lb)))

## 셀 인구 < 25 인 달 수 (AST gate 의 NA 인코딩과 0 인코딩이 갈리는 구간)
CP <- fread(file.path(OUT,"cell_population.csv"))
thin <- CP[tm==3 & ts==3 & N < 25, .N]
cat(sprintf("[emit] joint-top 셀 인구 < 25 인 달: %d / %d\n", thin, CP[tm==3&ts==3,.N]))

EM <- list(as_of_date = as.character(last_d),
  alpha_vector = setNames(as.list(round(DEP$alpha_hat, 6)), DEP$Ticker),
  alpha_vector_lower_bound = setNames(as.list(round(DEP$alpha_hat_lb, 6)), DEP$Ticker),
  confidence_vector = setNames(as.list(round(DEP$confidence, 4)), DEP$Ticker),
  fm_slope = list(b=b_hat, nw_se=b_se, nw_t=b_t, n_months=nrow(fm), k_shrink=1.0),
  alpha_inheritance_cor = ALPHA_INHERITANCE_COR,
  alpha_inheritance_cor_mom_axis = mean(abs(inh_mom$rho), na.rm=TRUE),
  n_deployed = nrow(DEP), thin_cell_months = thin, total_months = CP[tm==3&ts==3,.N])
write_json(EM, file.path(OUT,"alpha_emission.json"), auto_unbox=TRUE, na="null", digits=8)
cat("[p5] DONE\n")
