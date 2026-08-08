# emit_vectors.R — 최신 sig_date 의 alpha_vector / confidence_vector 조각 생성
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)
  library(sandwich);library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001")
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[, Date:=as.Date(Date)]
cat(sprintf("[emit] alpha_scores nrow=%d MONTHLY n_month=%d %s~%s\n", nrow(A), uniqueN(A$Date),
            min(A$Date), max(A$Date)))
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
RET <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
BM  <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
RB  <- merge(RET,BM,by="Date")[, .(Date,Ticker,act=Ret_1m-BM_Ret)]

# 배포 스코어 z (제외 종목은 NA 처리 — 선별 제외이지 '음의 알파 예측'이 아님)
A[, zs := { s <- fifelse(excluded_by_q01, NA_real_, m01_score)
            ok <- is.finite(s); r <- rep(NA_real_,.N)
            if (sum(ok)>=20L && sd(s[ok])>1e-8) r[ok] <- (s[ok]-mean(s[ok]))/sd(s[ok]); r }, by=Date]

# 스케일: 전표본 FMB 기울기 (실측 — 임의 계수 아님)
D <- merge(A[is.finite(zs), .(Date,Ticker,zs)], RB, by=c("Date","Ticker"))
sl <- D[, { ok<-is.finite(zs)&is.finite(act)
  if (sum(ok)>=10L && sd(zs[ok])>1e-8) .(b=unname(coef(lm(act[ok]~zs[ok]))[2])) else .(b=NA_real_) }, by=Date][is.finite(b)]
fit <- lm(sl$b ~ 1)
t_nw <- as.numeric(lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit,lag=3L,prewhite=FALSE))[1,3])
SCALE <- mean(sl$b)
cat(sprintf("[emit] 배포 스코어 z→월 active FMB 기울기 = %+.5f/월 (연 %+.2f%%/1sd, NW t=%+.2f, n=%d개월)\n",
            SCALE, 100*12*SCALE, t_nw, nrow(sl)))

# rank stability (전월 대비 순위 변화) → confidence 구성요소
setorder(A, Ticker, Date)
A[, rk_now := frank(-m01_score, na.last="keep"), by=Date]
A[, n_m := .N, by=Date]
A[, rk_prev := shift(rk_now), by=Ticker]
A[, rk_stab := 1 - pmin(1, abs(rk_now-rk_prev)/n_m)]

LAST <- max(A$Date)
L <- A[Date==LAST & is.finite(zs)][order(-zs)]
cat(sprintf("[emit] sig_date=%s  배포 대상 %d종목 (제외 %d종목)\n", LAST, nrow(L), A[Date==LAST & excluded_by_q01, .N]))

# confidence: 통계 신뢰(라운드 미확립 → 상한 낮음) + rank 안정성 + 커버리지
GLOBAL_CONF <- 0.25   # 본 라운드가 한계기여를 확립하지 못했음을 반영 (INCONCLUSIVE)
L[, conf := round(pmin(1, pmax(0, 0.5*GLOBAL_CONF + 0.35*fifelse(is.finite(rk_stab), rk_stab, 0.5) + 0.15*1)), 3)]
L[, alpha := round(zs * SCALE, 6)]

av <- setNames(as.list(L$alpha), L$Ticker)
cv <- setNames(as.list(L$conf),  L$Ticker)
writeLines(toJSON(av, auto_unbox=TRUE, digits=NA), file.path(OUT,"alpha_vector_frag.json"))
writeLines(toJSON(cv, auto_unbox=TRUE, digits=NA), file.path(OUT,"confidence_vector_frag.json"))
saveRDS(list(scale=SCALE, scale_t_nw=t_nw, n_month=nrow(sl), sig_date=as.character(LAST),
             n_names=nrow(L), n_excluded=A[Date==LAST & excluded_by_q01, .N]),
        file.path(OUT,"emit_meta.rds"))
cat(sprintf("[emit] alpha_vector %d entries / confidence_vector %d entries 저장\n", length(av), length(cv)))
cat(sprintf("[emit] alpha 범위 [%+.5f, %+.5f] 중앙 %+.5f\n", min(L$alpha), max(L$alpha), median(L$alpha)))
