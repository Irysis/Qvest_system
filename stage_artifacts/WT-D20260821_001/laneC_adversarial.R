## Self-Adversarial Challenge 실측 부속 (WT_D20260821_001_LANEC)
## ★전부 **사후(post-hoc) 진단**이다. 사전등록 §4/§5/§6 판정을 뒤집지 않는다(§10).
##   목적 = 등록된 판정의 **해석**이 어디까지 지탱되는지 스스로 적대 검증.
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260821_001/laneC_adversarial.R")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
OUT <- "stage_artifacts/WT-D20260821_001"
full <- readRDS(file.path(OUT, "laneC_full.rds"))
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x - m
  s <- sum(e^2)/n; for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }
bt <- sort(as.Date(full$LIN$L_mean$pr$date))
hl <- lapply(full$HOLD, function(h) split(h$Ticker, as.character(h$Date)))
jac <- function(a, b) { u <- length(union(a,b)); if (u == 0) NA_real_ else length(intersect(a,b))/u }
js  <- function(p) sapply(as.character(bt), function(d) jac(hl[[p[1]]][[d]], hl[[p[2]]][[d]]))
T_P    <- list(c("ML_mean","L_mean"), c("ML_q50","L_q50"), c("ML_q90","L_q90"))
ML_INT <- list(c("ML_mean","ML_q50"), c("ML_mean","ML_q90"), c("ML_q50","ML_q90"))
LN_INT <- list(c("L_mean","L_q50"),   c("L_mean","L_q90"),   c("L_q50","L_q90"))
mat <- function(ps) sapply(ps, js)
jT <- rowMeans(mat(T_P)); jMml <- rowMeans(mat(ML_INT)); jMln <- rowMeans(mat(LN_INT))
jM_all <- rowMeans(cbind(mat(ML_INT), mat(LN_INT)))

## 무작위 선택 기대 Jaccard (25종 무작위 2회 추출의 기대 중첩)
sc <- as.data.table(read_parquet(file.path(OUT, "laneC_scores.parquet")))
Nm <- sc[, .N, by = .(Date = as.Date(Date))][Date %in% bt]
ej <- mean(sapply(Nm$N, function(n) { k <- 25; e <- k*k/n; e/(2*k - e) }))

f1d <- list(
  concern = paste("사전등록 F1 의 J̄_M(6쌍 합산)이 LINEAR 내부쌍과 ML 내부쌍을 한 통에 평균한다.",
                  "그런데 사전등록 §2.1(3) 이 세 선형 arm 에 **동일 설계행렬 + 동일 유지열 K_m** 을 강제했다",
                  "— 손실함수만 다르다. 즉 선형 arm 끼리는 구조적으로 닮도록 설계돼 있고,",
                  "그 동질성이 J̄_M 을 밀어올려 F1 을 기계적으로 FAIL 쪽으로 끈다."),
  j_bar_T = mean(jT), j_bar_M_ML_internal = mean(jMml), j_bar_M_LINEAR_internal = mean(jMln),
  j_bar_M_pooled_prereg = mean(jM_all),
  contrast_vs_pooled  = list(gap = mean(jT)-mean(jM_all), nw3_t = nw_t(jT - jM_all),
                             note = "사전등록 판정축 — FAIL"),
  contrast_vs_ML_internal = list(gap = mean(jT)-mean(jMml), nw3_t = nw_t(jT - jMml),
                             note = "★부호 반대 — 표적 축 군집이 강하게 확인됨"),
  contrast_vs_LINEAR_internal = list(gap = mean(jT)-mean(jMln), nw3_t = nw_t(jT - jMln),
                             note = "선형 내부 동질성(공유 K_m)이 지배"),
  linear_over_ml_homogeneity_ratio = mean(jMln)/mean(jMml),
  random_selection_expected_jaccard = ej,
  disposition = paste("사전등록 F1 판정(FAIL)은 **그대로 유지**한다(§10 측정 후 문턱 변경 금지).",
                      "단 pooled J̄_M 은 서로 반대 방향의 두 부분모집단 평균이라 기전 해석의 기준선으로는",
                      "교란돼 있다 — 이 분해는 판정 번복이 아니라 **재등록 next_probe 의 근거**다."))

## 경고월(rq 'possibly singular design') 민감도 — 사후, 라벨된 진단
cond <- readRDS(file.path(OUT, "laneC_conditioning.rds"))
cond[, sig_date := sort(unique(as.Date(sc$sig_date)))][, warned := nzchar(warn)]
cond <- merge(cond, unique(sc[, .(sig_date = as.Date(sig_date), Date = as.Date(Date))]), by = "sig_date")
wa <- cond[warned == TRUE]$Date
sens <- lapply(list(c("mean","ML_mean","L_mean"), c("q50","ML_q50","L_q50"), c("q90","ML_q90","L_q90")),
  function(p) {
    j <- merge(as.data.table(full$ML[[p[2]]]$pr)[, .(date = as.Date(date), m = ret_net)],
               as.data.table(full$LIN[[p[3]]]$pr)[, .(date = as.Date(date), l = ret_net)], by = "date")
    j[, w := date %in% wa]; da <- j$m - j$l; dc <- j[w == FALSE]$m - j[w == FALSE]$l
    list(pair = p[1], n_all = length(da), ann_pct_all = 100*12*mean(da), t_all = nw_t(da),
         n_clean = length(dc), ann_pct_ex_warned = 100*12*mean(dc), t_ex_warned = nw_t(dc)) })
names(sens) <- c("mean","q50","q90")

## L_mean vs ML_mean — SR 격차가 평균에서 오는가 변동성에서 오는가
j <- merge(as.data.table(full$LIN$L_mean$pr)[, .(date = as.Date(date), l = ret_net)],
           as.data.table(full$ML$ML_mean$pr)[, .(date = as.Date(date), m = ret_net)], by = "date")
var_dec <- list(
  linear_monthly_mean = mean(j$l), linear_monthly_sd = stats::sd(j$l),
  ml_monthly_mean = mean(j$m), ml_monthly_sd = stats::sd(j$m),
  mean_diff_ann_pct = 100*12*(mean(j$m) - mean(j$l)),
  sd_ratio_ml_over_linear = stats::sd(j$m)/stats::sd(j$l),
  total_sr_linear = full$LIN$L_mean$sr_total, total_sr_ml = full$ML$ML_mean$sr_total,
  mdd_linear = full$LIN$L_mean$mdd, mdd_ml = full$ML$ML_mean$mdd,
  reading = paste("평균 수익 차는 통계적으로 구분되지 않는데(paired t -0.27) 월 sd 는 ML 이 1.16배,",
                  "MDD 는 64.0% vs 48.9%. ⇒ L_mean 의 total SR 우위(0.7575 vs 0.6039)는",
                  "**평균이 아니라 변동성/경로**에서 온다. 이는 '선형이 더 낫다'는 평균-효과 주장이 아니라",
                  "**분산 관측**이며, 사전등록에 없던 축이므로 next_probe 로만 소비한다."))

write_json(list(round_id = "WT_D20260821_001_LANEC",
  status = "POST_HOC_ADVERSARIAL_DIAGNOSTIC — 사전등록 판정 불변(§10)",
  f1_baseline_decomposition = f1d,
  warned_month_sensitivity = list(
    note = paste("rq.fit(method='fn') 이 'possibly singular design' 경고를 낸 39개월.",
                 "스코어 붕괴 없음(월 sd 정상·상수월 0)이나 세 arm 전부 그 달 rank-IC 가 약하다",
                 "— q50 기준 0.0027 vs 정상월 0.0399. 즉 q50 특유 결함이 아니라 '어려운 달' 지표."),
    n_warned_months = length(intersect(as.character(bt), as.character(wa))), n_total = length(bt),
    pairs = sens,
    reading = "경고월 제외 시 라벨 전환 없음(3쌍 전부 |t|<2.0 유지) — P1 결론은 이 축에 강건하다."),
  variance_decomposition_L_mean_vs_ML_mean = var_dec),
  file.path(OUT, "laneC_adversarial.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("저장: laneC_adversarial.json\n")
cat(sprintf("F1 분해 — T %.4f | M(ML내부) %.4f (t %+.2f) | M(LIN내부) %.4f (t %+.2f) | M(pooled) %.4f (t %+.2f)\n",
  mean(jT), mean(jMml), nw_t(jT-jMml), mean(jMln), nw_t(jT-jMln), mean(jM_all), nw_t(jT-jM_all)))
