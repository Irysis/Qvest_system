## WT-D20260822_010 — 반증 조건 집행 (N1/N2/N3) + 전이-벽 진단 + 노출제거 기여 분해
## 반증 조건은 alpha_hypothesis.json (alpha-hypothesis 가 독립 봉인) 에서 **읽어서** 집행한다.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[f] ", f, "\n"), ...))
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
ym_add <- function(ym,k){y<-as.integer(substr(ym,1,4));m<-as.integer(substr(ym,6,7))+k
  y<-y+(m-1L)%/%12L;m<-(m-1L)%%12L+1L;sprintf("%04d-%02d",y,m)}
D <- list()

HY <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_010/alpha_hypothesis.json"),
               simplifyVector = FALSE)
FAL <- HY$hypothesis$falsification
say("반증 조건 %d건 로드: %s", length(FAL), paste(sapply(FAL, function(z) z$id), collapse = " / "))
D$falsification_source <- "qepm/mailbox/worktask/WT-D20260822_010/alpha_hypothesis.json$hypothesis$falsification"

O  <- readRDS(file.path(OUT, "10_measure_objects.rds")); SMx <- O$SMx; Wb <- O$Wb; Wf <- O$Wf
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)]
SIZE <- as.data.table(SI$SIZE)[, Date := as.Date(Date)]
RET <- fwd_ret[, .(Date, Ticker, Ret_1m)]
NP <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/alpha_scores.parquet"))[, Date := as.Date(Date)]
AP <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))[, Date := as.Date(Date)]

## ── N1: 노출 중립성 (size + win_vol 대칭) ──────────────────────────────────
THR_N1 <- 0.126
SZ <- merge(SMx[, .(Date, Ticker, excluded)], SIZE[, .(Date, Ticker, Size)], by = c("Date","Ticker"))
SZ[, srank := frank(Size)/.N, by = Date]
szt <- SZ[, .(e = mean(srank[excluded]), k = mean(srank[!excluded])), by = Date][is.finite(e) & is.finite(k)]
size_gap <- mean(szt$e - szt$k); size_t <- nw_t(szt$e - szt$k)
VV <- merge(SMx[, .(Date, Ticker, excluded)], NP[, .(Date, Ticker, win_vol)], by = c("Date","Ticker"))
VV <- VV[is.finite(win_vol)][, vrank := frank(win_vol)/.N, by = Date]
vvt <- VV[, .(e = mean(vrank[excluded]), k = mean(vrank[!excluded])), by = Date][is.finite(e) & is.finite(k)]
vol_gap <- mean(vvt$e - vvt$k); vol_t <- nw_t(vvt$e - vvt$k)
n1_fired <- (abs(size_gap) >= THR_N1) || (abs(vol_gap) >= THR_N1)
say("N1 노출중립성: size gap %+.5f (|.|=%.4f, NW t %+.2f) | win_vol gap %+.5f (|.|=%.4f, NW t %+.2f) | 문턱 %.3f → 발화=%s",
    size_gap, abs(size_gap), size_t, vol_gap, abs(vol_gap), vol_t, THR_N1, n1_fired)
say("   raw 축 대조: size gap -0.25222 (WT-009 실측). 잔존 비율 size %.3f / vol (raw 실측치 부재 — 절대기준)",
    abs(size_gap)/0.252215486620633)
D$N1 <- list(id = "N1_exposure_neutrality", threshold = THR_N1,
  size_gap = size_gap, size_abs = abs(size_gap), size_nw_t = size_t, size_n_months = nrow(szt),
  vol_gap = vol_gap, vol_abs = abs(vol_gap), vol_nw_t = vol_t, vol_n_months = nrow(vvt),
  wt009_raw_size_gap = -0.252215486620633,
  residual_share_vs_raw_size = abs(size_gap)/0.252215486620633,
  fired = n1_fired,
  reading = if (n1_fired) "전제 반증 — 직교화가 노출을 충분히 제거하지 못했다" else
    "전제 성립 — 노출 이동이 문턱 아래로 제거됐다. 단 NW t 는 여전히 유의하므로 '완전 중립'이 아니라 '문턱-충족 중립'으로만 서술한다.")

## ── N2: 꼬리월 하락일 개인 순매수 (잔차-정의 집합) ─────────────────────────
Q <- copy(SMx)
Q[, thr_hi := { v <- score_orth; v <- v[is.finite(v)]
  if (length(v) >= 30L) quantile(v, 0.80, type = 7, names = FALSE) else Inf }, by = Date]
Q[, `:=`(qlo = excluded, qhi = is.finite(score_orth) & score_orth >= thr_hi)]
Q <- merge(Q[, .(Date, Ticker, qlo, qhi)], RET, by = c("Date","Ticker"))
Q[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
                                 col_select = c("Date","Ticker","Individual")))[, Date := as.Date(Date)]
RW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                 col_select = c("Date","Ticker","Ret","Vol","Close")))[, Date := as.Date(Date)]
DD <- merge(RW[is.finite(Ret) & Ret < 0, .(Date, Ticker, Vol, Close)], IV, by = c("Date","Ticker"))
DD[, hold_ym := format(Date, "%Y-%m")]
DN <- DD[, .(dn_flow = sum(Individual, na.rm = TRUE), dn_val = sum(Vol*Close, na.rm = TRUE), nd = .N),
         by = .(hold_ym, Ticker)]
QT <- Q[tail_hit == TRUE][, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
QT <- merge(QT, DN, by = c("hold_ym","Ticker"))
QT <- QT[nd > 0 & is.finite(dn_val) & dn_val > 0, .(Date, Ticker, qlo, qhi, dnint = dn_flow/dn_val)]
f2 <- QT[, .(sp = mean(dnint[qlo]) - mean(dnint[qhi]), n_lo = sum(qlo), n_hi = sum(qhi)),
         by = Date][is.finite(sp) & n_lo >= 2 & n_hi >= 2]
f2_t <- nw_t(f2$sp)
n2_label <- if (nrow(f2) < 30) "미결(n<30 — 판정 불가)" else
            if (isTRUE(f2_t >= 0)) "기각(부호 소멸/역전)" else
            if (isTRUE(f2_t <= -2.0)) "지지(유의 음수)" else "미결(부호 맞으나 유의 미달)"
n2_fired <- (nrow(f2) >= 30) && isTRUE(f2_t >= 0)
say("N2 하락일 개인지지(잔차정의): 월평균 %+.6f NW t=%+.3f n=%d → %s | 발화=%s  [raw 선례 -0.11419 / t -8.934 / n=42]",
    mean(f2$sp), f2_t, nrow(f2), n2_label, n2_fired)
D$N2 <- list(id = "N2_downday_individual_support_residual", mean_spread = mean(f2$sp), nw_t = f2_t,
  n_months = nrow(f2), label = n2_label, fired = n2_fired,
  wt009_raw = list(mean_spread = -0.114191317182449, nw_t = -8.93375933044921, n_months = 42))

## ── N3: 스마트머니 후속 (F1 승계) ──────────────────────────────────────────
FW <- AP[, .(Date, Ticker, smart = fwd_foreign_3m_n + fwd_inst_3m_n)]
M1 <- merge(SMx[, .(Date, Ticker, excluded)], FW, by = c("Date","Ticker"))[is.finite(smart)]
f1 <- M1[, .(sp = mean(smart[excluded]) - median(smart), n_e = sum(excluded)),
         by = Date][is.finite(sp) & n_e >= 3]
f1_t <- nw_t(f1$sp); n3_fired <- isTRUE(f1_t >= 2.0)
say("N3 스마트머니 후속: 월평균 %+.6f NW t=%+.3f n=%d → 발화(t>=+2.0)=%s  [WT-009 raw: +0.000533 / t 1.208]",
    mean(f1$sp), f1_t, nrow(f1), n3_fired)
D$N3 <- list(id = "N3_smart_money_followthrough", mean_spread = mean(f1$sp), nw_t = f1_t,
  n_months = nrow(f1), reject_threshold = 2.0, fired = n3_fired,
  wt009_raw = list(mean_spread = 0.000533167587016396, nw_t = 1.20843402106869))

D$fired_count <- sum(c(n1_fired, n2_fired, n3_fired))
say("★반증 발화 합계 = %d (게이트: 0 이어야 전이 자격)", D$fired_count)

## ── 전이-벽 진단: 고-score 조건부에서 배제집합의 우위가 남는가 ─────────────
TOP <- merge(Wb[, .(Date, Ticker, w)], SMx[, .(Date, Ticker, excluded, score_orth)], by = c("Date","Ticker"), all.x = TRUE)
TOP <- merge(TOP, RET, by = c("Date","Ticker"), all.x = TRUE)
TOP[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
cond <- TOP[!is.na(excluded), .(n = .N, tail_rate = mean(tail_hit), mean_ret = mean(Ret_1m, na.rm=TRUE),
   q10 = quantile(Ret_1m, 0.10, na.rm=TRUE), mean_w = mean(w)), by = excluded][order(excluded)]
print(cond)
mt <- TOP[!is.na(excluded), .(sp = mean(Ret_1m[excluded], na.rm=TRUE) - mean(Ret_1m[!excluded], na.rm=TRUE),
                              n_e = sum(excluded)), by = Date][is.finite(sp) & n_e >= 1]
say("전이-벽: base top-25 내 배제 vs 잔류 월수익차 %+.6f NW t=%+.3f (n=%d월) [WT-009 raw: -0.001831 / t -0.450]",
    mean(mt$sp), nw_t(mt$sp), nrow(mt))
D$transition_wall <- list(table = as.data.frame(cond), mean_spread_monthly = mean(mt$sp),
  nw_t = nw_t(mt$sp), n_months = nrow(mt),
  wt009_raw = list(mean_spread_monthly = -0.0018314385933408, nw_t = -0.449970728504493),
  reading = "음수 = 배제대상이 top-25 안에서 덜 벌었다(기전 정합). 양수 = 횡단면 우위가 고-score 조건부로 소멸/역전(전이-벽).")

## ── 노출 제거가 ΔIR 결손을 얼마나 회복했나 (본 라운드의 핵심 분해) ─────────
M <- fromJSON(file.path(OUT, "10_measure.json"))
d_raw <- -0.115272463602773; d_orth <- M$paired$delta_ir
D$exposure_removal_accounting <- list(
  delta_ir_raw_axis = d_raw, delta_ir_orth_axis = d_orth,
  recovered = d_orth - d_raw, deficit_vs_gate_raw = 0.05 - d_raw,
  recovery_share_of_deficit = (d_orth - d_raw) / (0.05 - d_raw),
  exposure_removed_share = 1 - abs(size_gap)/0.252215486620633,
  weight_ratio_raw = 2.29625, weight_ratio_orth = M$substitution$weight_sum_ratio,
  reading = paste0("노출 이동의 ", round(100*(1-abs(size_gap)/0.252215486620633),1),
    "% 를 제거했는데 ΔIR 결손은 ", round(100*(d_orth-d_raw)/(0.05-d_raw),1),
    "% 만 회복됐다 — 결손의 대부분은 노출 이동이 아니라 다른 원천이다."))
say("★노출제거 회계: ΔIR %+.4f(raw) → %+.4f(직교) = %+.4f 회복 / 게이트까지 결손 %.4f = %.1f%% 회복 (노출은 %.1f%% 제거)",
    d_raw, d_orth, d_orth - d_raw, 0.05 - d_raw, 100*(d_orth-d_raw)/(0.05-d_raw),
    100*(1-abs(size_gap)/0.252215486620633))

write_json(D, file.path(OUT, "11_falsify.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
