# p7_crosssectional_signals.R — 라벨 lane R2: 횡단면·미시구조 신호로 NORMAL-위기월을 잡을 수 있나
# 배경(P6): 벤치 파생 순진신호 4종(낙폭·변동성·3m수익·변동성비) 전건 FAIL(precision≈기저).
#   현 라벨 CRISIS+CAUTION 은 PASS 이나 MDD 를 만든 월은 NORMAL 라벨 밖(P6b).
# 시험: rawdata 횡단면 집계에서 파생한 5종 — 벤치 시계열이 아니라 **종목 간 구조**를 본다.
# ★PIT 엄수: feature 는 decision_date 이전 일자만. 문턱은 expanding(past-only) 분위수.
# 판정축: precision > 기저 ∧ binomial p<0.05 (+ NORMAL-위기월 recall 별도 보고)
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
setorder(R, decision_date)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]
raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, TV := Close*Vol]
cat(sprintf("[rawdata] %s행 %s~%s\n", format(nrow(raw), big.mark=","), min(raw$Date), max(raw$Date)))

## --- 일별 횡단면 집계 1회 (종목 간 구조) ---
DA <- raw[, .(n = .N,
              ew = mean(Ret, na.rm=TRUE),                 # EW 시장수익
              disp = sd(Ret, na.rm=TRUE),                 # 횡단면 분산(수익 분포 폭)
              frac_neg = mean(Ret < 0, na.rm=TRUE),       # 하락 종목 비율
              tv = sum(TV, na.rm=TRUE)), by=Date]
setorder(DA, Date)
DA <- DA[n >= 100]
cat(sprintf("[daily agg] %d일\n", nrow(DA)))

## --- 월별 feature: decision_date '이전' 일자만 ---
feat <- rbindlist(lapply(seq_len(nrow(R)), function(i) {
  dd <- R$decision_date[i]
  h <- DA[Date < dd]                                       # ★strict <
  if (nrow(h) < 300) return(data.table(decision_date=dd, disp20=NA_real_, breadth=NA_real_,
                                       absorb=NA_real_, turn_z=NA_real_, disp_trend=NA_real_))
  t20 <- tail(h, 20); t60 <- tail(h, 60); t250 <- tail(h, 250)
  # 동조화(absorption 근사) = EW 지수 변동성 / 평균 종목 변동성. 높을수록 한 방향 동조 → 취약
  absorb <- sd(t60$ew) / pmax(mean(t60$disp), 1e-12)
  data.table(decision_date = dd,
    disp20     = mean(t20$disp),                                   # 횡단면 분산 수준
    breadth    = mean(1 - t20$frac_neg),                           # 상승 종목 비율(낮을수록 약세 확산)
    absorb     = absorb,
    turn_z     = (mean(log(t20$tv)) - mean(log(t250$tv))) / pmax(sd(log(t250$tv)), 1e-12),
    disp_trend = mean(t20$disp) / pmax(mean(t60$disp), 1e-12))     # 분산 급확대
}))
D <- merge(R[, .(decision_date, eval_date, regime, gross=gA)], feat, by="decision_date")
setorder(D, decision_date)

## --- 타깃: expanding q10 (past-only) ---
D[, thr := sapply(seq_len(.N), function(i) if (i <= 36L) NA_real_ else quantile(gross[1:(i-1)], 0.10, names=FALSE))]
D[, crisis := is.finite(thr) & gross <= thr]
E <- D[is.finite(thr) & is.finite(absorb)]
base <- mean(E$crisis)
n_normal_crisis <- sum(E$crisis & E$regime %in% c("NORMAL","BULL"))
cat(sprintf("\n[평가] %d개월 | 위기월 %d (기저 %.1f%%) | 그중 NORMAL/BULL 라벨 %d개 = 현 라벨 사각\n",
            nrow(E), sum(E$crisis), 100*base, n_normal_crisis))

expq <- function(x, p, min_n=36L) sapply(seq_along(x), function(i) if (i <= min_n) NA_real_ else quantile(x[1:(i-1)], p, names=FALSE, na.rm=TRUE))
ev <- function(fire, nm) {
  fire <- fire & !is.na(fire)
  tp <- sum(fire & E$crisis); nf <- sum(fire); nc <- sum(E$crisis)
  tp_blind <- sum(fire & E$crisis & E$regime %in% c("NORMAL","BULL"))
  p <- if (nf > 0) binom.test(tp, nf, p=base, alternative="greater")$p.value else NA_real_
  data.table(signal=nm, 발화=nf, TP=tp, recall=round(tp/nc,3), precision=round(ifelse(nf,tp/nf,NA),3),
             기저대비=round(ifelse(nf,(tp/nf)/base,NA),2), p=round(p,4),
             사각_TP=tp_blind, 사각_recall=round(tp_blind/max(n_normal_crisis,1),3),
             자격=ifelse(!is.na(p) && p<0.05 && nf>0 && (tp/nf)>base, "PASS","FAIL"))
}
E[, `:=`(q_disp=expq(disp20,0.80), q_bre=expq(breadth,0.20), q_abs=expq(absorb,0.80),
         q_turn=expq(turn_z,0.80), q_dt=expq(disp_trend,0.80))]
out <- rbindlist(list(
  ev(E$regime %in% c("CRISIS","CAUTION"), "[기준] 현 라벨 CRISIS+CAUTION"),
  ev(E$disp20     >= E$q_disp, "횡단면 분산 ≥ exp-q80"),
  ev(E$breadth    <= E$q_bre,  "상승종목비율 ≤ exp-q20"),
  ev(E$absorb     >= E$q_abs,  "동조화(absorption) ≥ exp-q80"),
  ev(E$turn_z     >= E$q_turn, "거래대금 z ≥ exp-q80"),
  ev(E$disp_trend >= E$q_dt,   "분산 급확대 ≥ exp-q80"),
  ev(E$absorb >= E$q_abs & E$breadth <= E$q_bre, "동조화 ∧ 약세확산"),
  ev((E$absorb >= E$q_abs | E$breadth <= E$q_bre) & !(E$regime %in% c("CRISIS","CAUTION")),
     "★(동조화 ∨ 약세확산) ∧ 라벨 사각지대")))
cat("\n===== 횡단면·미시구조 신호 (기저 대비) =====\n"); print(out)
cat(sprintf("\n[기저율] %.3f | 사각지대(NORMAL/BULL 라벨 위기월) %d개가 회수 표적\n", base, n_normal_crisis))
fwrite(out, "stage_artifacts/tilt_realign_20260808/p7_crosssectional.csv")
