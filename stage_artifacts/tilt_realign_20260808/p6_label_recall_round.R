# p6_label_recall_round.R — 라벨 lane R1: 상금 중 PIT 준수로 회수 가능한 몫
# 질문: 최악 10분위 월(오라클 27/269)을 *사전에* 잡을 수 있는 PIT-안전 신호가 있는가?
# 판정축(08-02 라벨 자격 관문): recall > base ∧ binomial p < 0.05. 현 라벨 baseline = 2/27.
# ★PIT 엄수: 모든 feature 는 decision_date 이전 데이터만. 문턱도 expanding(past-only) 분위수.
#   타깃(위기월) 정의 문턱도 expanding q10 — full-sample 분위수 사용은 C1 위반.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
setorder(R, decision_date)
cat(sprintf("[panel] %d개월 %s~%s\n", nrow(R), min(R$decision_date), max(R$decision_date)))

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
cat(sprintf("[benchmark] cols = %s | rows=%d\n", paste(names(bm), collapse=","), nrow(bm)))
dcol <- names(bm)[sapply(bm, function(x) inherits(x, "Date") || inherits(x, "IDate"))][1]
if (is.na(dcol)) { dcol <- grep("date|Date", names(bm), value=TRUE)[1]; bm[[dcol]] <- as.Date(bm[[dcol]]) }
rcol <- grep("^(BM_)?Ret|ret", names(bm), value=TRUE)[1]
ccol <- grep("Close|close|Index|Price", names(bm), value=TRUE)[1]
cat(sprintf("[benchmark] date=%s ret=%s close=%s\n", dcol, rcol, ccol))
setnames(bm, dcol, "Date")
bm <- bm[!is.na(Date)][order(Date)]
if (!is.na(rcol)) bm[, bret := as.numeric(get(rcol))] else bm[, bret := c(NA, diff(log(get(ccol))))]
bm <- bm[is.finite(bret)]
bm[, cum := cumprod(1+bret)]
cat(sprintf("[benchmark] 사용가능 %d행 %s~%s\n", nrow(bm), min(bm$Date), max(bm$Date)))

## --- PIT-안전 feature: decision_date '이전' 데이터만 ---
feat <- rbindlist(lapply(seq_len(nrow(R)), function(i) {
  dd <- R$decision_date[i]
  h <- bm[Date < dd]                                  # ★ strict <
  if (nrow(h) < 260) return(data.table(decision_date=dd, dd_12m=NA_real_, vol20=NA_real_, ret3m=NA_real_, vol_ratio=NA_real_))
  tail252 <- tail(h, 252); tail20 <- tail(h, 20); tail60 <- tail(h, 60); tail63 <- tail(h, 63)
  data.table(decision_date = dd,
    dd_12m    = tail(h$cum,1)/max(tail252$cum) - 1,           # 12개월 고점 대비 낙폭
    vol20     = sd(tail20$bret)*sqrt(252),                    # 20일 실현변동성(연율)
    ret3m     = prod(1+tail63$bret)-1,                        # 3개월 수익
    vol_ratio = sd(tail20$bret)/pmax(sd(tail60$bret),1e-12))  # 단기/중기 변동성 비
}))
D <- merge(R[, .(decision_date, eval_date, regime, gross=gA)], feat, by="decision_date")
setorder(D, decision_date)

## --- 타깃: expanding q10 (past-only 문턱) ---
D[, tgt_thr := sapply(seq_len(.N), function(i) if (i <= 36L) NA_real_ else quantile(gross[1:(i-1)], 0.10, names=FALSE))]
D[, crisis := is.finite(tgt_thr) & gross <= tgt_thr]
E <- D[is.finite(tgt_thr) & is.finite(dd_12m)]
base_rate <- mean(E$crisis)
cat(sprintf("\n[평가 표본] %d개월 (%s~) | 위기월 %d (기저율 %.1f%%)\n",
            nrow(E), min(E$eval_date), sum(E$crisis), 100*base_rate))

## --- 현 라벨 baseline ---
ev <- function(fire, nm) {
  tp <- sum(fire & E$crisis); fp <- sum(fire & !E$crisis); n_f <- sum(fire); n_c <- sum(E$crisis)
  rec <- if (n_c) tp/n_c else NA; prec <- if (n_f) tp/n_f else NA
  p <- if (n_f > 0) binom.test(tp, n_f, p=base_rate, alternative="greater")$p.value else NA_real_
  data.table(signal=nm, 발화=n_f, 발화율=round(100*n_f/nrow(E),1), TP=tp,
             recall=round(rec,3), precision=round(prec,3), 기저대비=round(prec/base_rate,2),
             p_value=round(p,4), 자격=ifelse(!is.na(p) && p<0.05 && !is.na(prec) && prec>base_rate, "PASS","FAIL"))
}
res <- list(ev(E$regime=="CRISIS", "현 라벨 CRISIS"),
            ev(E$regime %in% c("CRISIS","CAUTION"), "현 라벨 CRISIS+CAUTION"))

## --- 후보 신호: expanding 분위수 문턱 (past-only) ---
expq <- function(x, p, min_n=36L) sapply(seq_along(x), function(i) if (i <= min_n) NA_real_ else quantile(x[1:(i-1)], p, names=FALSE, na.rm=TRUE))
E[, `:=`(thr_dd = expq(dd_12m, 0.20), thr_vol = expq(vol20, 0.80),
         thr_r3 = expq(ret3m, 0.20), thr_vr = expq(vol_ratio, 0.80))]
res <- c(res, list(
  ev(is.finite(E$thr_dd)  & E$dd_12m    <= E$thr_dd,  "낙폭 dd_12m ≤ exp-q20"),
  ev(is.finite(E$thr_vol) & E$vol20     >= E$thr_vol, "변동성 vol20 ≥ exp-q80"),
  ev(is.finite(E$thr_r3)  & E$ret3m     <= E$thr_r3,  "3개월수익 ≤ exp-q20"),
  ev(is.finite(E$thr_vr)  & E$vol_ratio >= E$thr_vr,  "변동성비 ≥ exp-q80"),
  ev(is.finite(E$thr_vol) & is.finite(E$thr_dd) & E$vol20 >= E$thr_vol & E$dd_12m <= E$thr_dd, "변동성 ∧ 낙폭 (교집합)"),
  ev(is.finite(E$thr_vol) & is.finite(E$thr_dd) & (E$vol20 >= E$thr_vol | E$dd_12m <= E$thr_dd), "변동성 ∨ 낙폭 (합집합)")))
out <- rbindlist(res)
cat("\n===== 라벨 자격 관문 (recall>base ∧ p<0.05) =====\n"); print(out)
cat(sprintf("\n[기저율] %.3f — precision 이 이보다 커야 판별력 있음\n", base_rate))
fwrite(out, "stage_artifacts/tilt_realign_20260808/p6_label_recall.csv")
cat("[saved] p6_label_recall.csv\n")
