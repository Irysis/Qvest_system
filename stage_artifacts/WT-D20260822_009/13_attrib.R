## 기전 크기 산술 + 교체 귀속 — "배제가 나쁜 종목을 뺐나, 더 나쁜 종목을 넣었나"
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite);library(sandwich);library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT-D20260822_009")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<6L)return(NA_real_);fit<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(fit,vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
say <- function(f,...) cat(sprintf(paste0("[a] ",f,"\n"),...))
O <- readRDS(file.path(OUT,"10_measure_objects.rds")); Wb<-O$Wb; Wf<-O$Wf
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
RET <- as.data.table(SI$fwd_ret)[,Date:=as.Date(Date)][,.(Date,Ticker,Ret_1m)]
B <- merge(Wb, RET, by=c("Date","Ticker")); F_ <- merge(Wf, RET, by=c("Date","Ticker"))
key <- function(d) paste(d$Date,d$Ticker)
B[, inF := key(.SD) %chin% key(F_)]; F_[, inB := key(.SD) %chin% key(B)]
rem <- B[inF==FALSE]; add <- F_[inB==FALSE]
say("교체 규모: 월평균 제거 %.2f종(비중합 %.4f) / 추가 %.2f종(비중합 %.4f)",
    nrow(rem)/uniqueN(B$Date), rem[,sum(w)]/uniqueN(B$Date),
    nrow(add)/uniqueN(F_$Date), add[,sum(w)]/uniqueN(F_$Date))
say("제거 종목 평균 월수익 %+.4f | 추가 종목 평균 월수익 %+.4f (차 %+.4f)",
    rem[,mean(Ret_1m)], add[,mean(Ret_1m)], add[,mean(Ret_1m)]-rem[,mean(Ret_1m)])
say("제거 종목 꼬리율(<=-20%%) %.3f%% | 추가 종목 꼬리율 %.3f%%",
    100*rem[,mean(Ret_1m<=-0.20)], 100*add[,mean(Ret_1m<=-0.20)])
say("제거 가중기여 월평균 %+.6f | 추가 가중기여 월평균 %+.6f",
    rem[,sum(w*Ret_1m)]/uniqueN(B$Date), add[,sum(w*Ret_1m)]/uniqueN(F_$Date))
## 기전 크기 산술: top-25 내 꼬리율 격차가 낼 수 있는 월 기대손익
tail_gap <- 0.03375527 - 0.02720842      # 11_diag 조건부 표 (배제대상 − 잔류)
n_excl_top25 <- nrow(rem)/uniqueN(B$Date)
w_excl <- rem[,mean(w)]
implied <- tail_gap * n_excl_top25 * w_excl * 0.20   # 꼬리 사건 1건 = -20% 가정
say("★기전 크기 산술: 조건부 꼬리율 격차 %.4f x 배제 %.2f종 x 평균비중 %.4f x 20%% = 월 %.6f (연 %.3f%%p)",
    tail_gap, n_excl_top25, w_excl, implied, 1200*implied)
say("   대조: 월별 Δactive 실측 sd = %.5f → 기전 함의 크기 / sd = %.4f (검출 필요 t 규모)",
    0.015949, implied/0.015949)
J <- list(
  substitution = list(mean_removed_names = nrow(rem)/uniqueN(B$Date), removed_weight_sum = rem[,sum(w)]/uniqueN(B$Date),
    mean_added_names = nrow(add)/uniqueN(F_$Date), added_weight_sum = add[,sum(w)]/uniqueN(F_$Date),
    removed_mean_ret = rem[,mean(Ret_1m)], added_mean_ret = add[,mean(Ret_1m)],
    added_minus_removed = add[,mean(Ret_1m)]-rem[,mean(Ret_1m)],
    removed_tail_rate = rem[,mean(Ret_1m<=-0.20)], added_tail_rate = add[,mean(Ret_1m<=-0.20)],
    removed_wcontrib = rem[,sum(w*Ret_1m)]/uniqueN(B$Date), added_wcontrib = add[,sum(w*Ret_1m)]/uniqueN(F_$Date),
    removed_mean_w = rem[,mean(w)], added_mean_w = add[,mean(w)]),
  mechanism_effect_size_arithmetic = list(
    conditional_tail_gap = tail_gap, n_excluded_in_top25 = n_excl_top25, mean_weight_excluded = w_excl,
    tail_event_magnitude = 0.20, implied_monthly_delta = implied, implied_annual_pp = 1200*implied,
    measured_sd_monthly = 0.015949, implied_over_sd = implied/0.015949,
    reading = "기전이 참이고 조건부 꼬리율 격차가 전부 배제 편익으로 전환돼도 포트폴리오 수준 함의는 월 단위로 Δactive sd 의 극히 일부다 — 이 크기는 268월 창의 MDE80(0.00273/월) 아래다. 즉 본 소비 형태는 기전이 참이어도 이 창에서 유의 검출이 불가능한 설계였다. 이 산술은 측정 **전에** 했어야 한다(자기 적대검증 C2)."))
write_json(J, file.path(OUT,"13_attrib.json"), auto_unbox=TRUE, pretty=TRUE, digits=NA, na="null")
say("done")
