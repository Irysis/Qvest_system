## arm C 성과 측정 + arm A 대비 짝지은 검정 (FQ233_ARMC_20260820)
## 사전등록 PREREG_armC_20260820.md §2(primary = P_up - P_dn) §4(paired NW3 t, 문턱 ±2.0)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/fq233_probe0_20260813/armC_measure.R")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")   # .essence_dsr (진단 DSR — 자체합성 회피)
OUT <- "stage_artifacts/fq233_probe0_20260813"

inp <- readRDS(file.path(OUT, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                         Ret_1m = as.numeric(Ret_1m))]
## 벤치 — 일별→월간 표준함수 집계 후 ym 키 (armA/armB 와 동일 경로, 자구 승계)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(returns_dt[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
stopifnot(nrow(bench_dt) >= 0.95 * uniqueN(returns_dt$Date))

sc <- as.data.table(read_parquet(file.path(OUT, "armC_scores.parquet")))[, Date := as.Date(Date)]
cat(sprintf("스코어 %d행 · %d개월 (%s ~ %s)\n", nrow(sc), uniqueN(sc$Date),
            min(sc$Date), max(sc$Date)))

run_one <- function(col, tag) {
  s <- sc[, .(Date, Ticker = as.character(Ticker), score = as.numeric(get(col)))]
  r <- canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           strategy_id = paste0("FQ233_ARMC_", tag), run_id = "FQ233_ARMC_20260820")
  pr <- as.data.table(r$period_returns)
  px <- xts(pr$ret_net, order.by = as.Date(pr$date))
  list(tag = tag, res = r, pr = pr,
       sr_total = as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE)),
       cagr = as.numeric(Return.annualized(px, scale = 12, geometric = TRUE)),
       mdd  = as.numeric(maxDrawdown(px)),
       calmar = as.numeric(CalmarRatio(px, scale = 12)))
}

cat("\n=== primary = P_up - P_dn (사전등록 §2) ===\n")
C <- run_one("score", "tailprob_primary")
cat(sprintf("  total SR %+.4f · PORT_t %+.4f (p %.4f) · active IR %+.4f · CAGR %.2f%% · MDD %.2f%% · Calmar %.4f · TO %.2f · n=%d\n",
            C$sr_total, as.numeric(C$res$portfolio_alpha_t_nw_lag3),
            as.numeric(C$res$portfolio_alpha_t_pvalue), as.numeric(C$res$net_sr),
            100*C$cagr, 100*C$mdd, C$calmar, as.numeric(C$res$turnover_annual),
            as.numeric(C$res$n_months)))
## ★기간 손실 감시 (armA 가 199→101 로 조용히 잘렸던 사고의 재발 감시)
.exp_m <- uniqueN(sc$Date)
cat(sprintf("  기간 대조: 스코어 %d개월 → 백테 %s개월 (%.1f%%)\n",
            .exp_m, C$res$n_months, 100*as.numeric(C$res$n_months)/.exp_m))
if (as.numeric(C$res$n_months) < 0.95 * .exp_m) warning("★백테 기간 손실 — 축 조사 필요", call. = FALSE)

## ★사전등록 §3 은 secondary 를 Bowley(+CRPS·rank-IC 진단)로만 한정한다.
##   p_up/p_dn 단독 canonical 백테는 사전등록에 없으므로 **돌리지 않는다** —
##   arm B 에서 'q90 이 좋아 보인다' 가 primary 교체 유혹을 만든 그 표면이다.

cat("\n=== primary 검정: arm C − arm A 짝지은 NW lag-3 t ===\n")
A <- readRDS(file.path(OUT, "armA_canonical_result.rds"))
prA <- as.data.table(A$period_returns)[, .(date = as.Date(date), a = ret_net)]
prC <- C$pr[, .(date = as.Date(date), c = ret_net)]
j <- merge(prA, prC, by = "date")
cat(sprintf("  짝지은 달 %d (armA %d · armC %d)\n", nrow(j), nrow(prA), nrow(prC)))
stopifnot(nrow(j) >= 0.95 * min(nrow(prA), nrow(prC)))
d <- j$c - j$a
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }
t_paired <- nw_t(d)
cat(sprintf("  월평균 차이 %+.4f%%p · 연환산 %+.2f%%p · NW3 t = %+.4f\n",
            100*mean(d), 100*12*mean(d), t_paired))

verdict <- if (t_paired >= 2.0) "TAIL_PROB_TARGET_SUPPORTED" else
           if (t_paired <= -2.0) "TAIL_PROB_TARGET_INFERIOR" else "NOT_SUPPORTED_NO_DIFFERENCE"
cat(sprintf("\n★사전등록 §4 판정: paired NW3 t %+.4f vs ±2.0 → **%s**\n", t_paired, verdict))

## --- arm A 병기 (사전등록 §4 병기 의무: 양 arm SR·PORT_t·MDD·Calmar·회전율·diag rank-IC) ---
pxA <- xts(prA$a, order.by = prA$date)
A_sr <- as.numeric(SharpeRatio.annualized(pxA, Rf = 0, scale = 12, geometric = FALSE))
A_mdd <- as.numeric(maxDrawdown(pxA)); A_cal <- as.numeric(CalmarRatio(pxA, scale = 12))
metaA <- fromJSON(file.path(OUT, "armA_score_meta.json"))
metaC <- fromJSON(file.path(OUT, "armC_score_meta.json"))
cat(sprintf("\n[병기] armA total SR %+.4f · PORT_t %+.4f · MDD %.2f%% · Calmar %.4f · TO %.2f · diagIC %+.4f\n",
            A_sr, as.numeric(A$portfolio_alpha_t_nw_lag3), 100*A_mdd, A_cal,
            as.numeric(A$turnover_annual), metaA$diag_rank_ic_mean))
cat(sprintf("[병기] armC total SR %+.4f · PORT_t %+.4f · MDD %.2f%% · Calmar %.4f · TO %.2f · diagIC %+.4f\n",
            C$sr_total, as.numeric(C$res$portfolio_alpha_t_nw_lag3), 100*C$mdd, C$calmar,
            as.numeric(C$res$turnover_annual), metaC$diag$score$rank_ic_mean))

## --- 사전등록 §5: DSR 수치는 진단으로 산출·기록 (게이트 아님 — selection_type=chain) ---
##     repo 구현 .essence_dsr(BLdP 2014) 직접 호출 — 손계산/자체합성 회피.
stopifnot(all(c("ret_net", "benchmark_ret") %in% names(C$pr)))
act <- C$pr$ret_net - C$pr$benchmark_ret; act <- act[is.finite(act)]
dsr_diag <- NA_real_
if (length(act) >= 12 && sd(act) > 0) {
  mu <- mean(act); s <- sd(act)
  dsr_diag <- .essence_dsr(mu/s*sqrt(12), length(act), 1,
                           mean(((act-mu)/s)^3), mean(((act-mu)/s)^4), A = 12)
}
cat(sprintf("[진단] DSR(n_trials=1, chain — 게이트 부적용) = %s · active n=%d\n",
            ifelse(is.finite(dsr_diag), sprintf("%.4f", dsr_diag), "NA"), length(act)))

## --- 5-arm 서열표 (armB striking_pattern 승계 + arm C 행 추가. n=5 비독립 caution 승계) ---
B <- fromJSON(file.path(OUT, "armB_result.json"))
metaB <- fromJSON(file.path(OUT, "armB_score_meta.json"))
tab <- data.table(
  arm      = c("q10", "q50", "armA_mean", "q90", "armC_tailprob"),
  rank_ic  = c(metaB$diag$q10$rank_ic_mean, metaB$diag$q50$rank_ic_mean,
               metaA$diag_rank_ic_mean, metaB$diag$q90$rank_ic_mean,
               metaC$diag$score$rank_ic_mean),
  total_sr = c(B$secondary$total_sr[B$secondary$tag == "q10"], B$primary_result$total_sr,
               A_sr, B$secondary$total_sr[B$secondary$tag == "q90"], C$sr_total),
  port_t   = c(B$secondary$port_t[B$secondary$tag == "q10"], B$primary_result$port_t,
               as.numeric(A$portfolio_alpha_t_nw_lag3),
               B$secondary$port_t[B$secondary$tag == "q90"],
               as.numeric(C$res$portfolio_alpha_t_nw_lag3)))
setorder(tab, -rank_ic)
cat("\n=== 5-arm 서열표 (rank-IC 내림차순) ===\n"); print(tab)
sr_rank_inv <- cor(rank(tab$rank_ic), rank(tab$total_sr), method = "spearman")
cat(sprintf("  rank-IC 순위 vs total SR 순위 Spearman = %+.4f  (n=5 비독립 — 관찰이지 검정 아님)\n", sr_rank_inv))

write_json(list(
  round_id = "FQ233_ARMC_20260820", prereg = "PREREG_armC_20260820.md",
  measured_at = format(Sys.Date()),
  metric_type = "canonical_screen", selection_type = "chain",
  primary = "P_up - P_dn (꼬리초과확률 스프레드)", verdict = verdict,
  primary_result = list(total_sr = C$sr_total,
    port_t = as.numeric(C$res$portfolio_alpha_t_nw_lag3),
    port_t_p = as.numeric(C$res$portfolio_alpha_t_pvalue),
    active_ir = as.numeric(C$res$net_sr), cagr = C$cagr, mdd = C$mdd, calmar = C$calmar,
    turnover = as.numeric(C$res$turnover_annual), n_months = as.numeric(C$res$n_months),
    diag_rank_ic = metaC$diag$score$rank_ic_mean, diag_icir = metaC$diag$score$icir,
    dsr_diag_n_trials_1 = dsr_diag),
  armA_reference = list(total_sr = A_sr, port_t = as.numeric(A$portfolio_alpha_t_nw_lag3),
    mdd = A_mdd, calmar = A_cal, turnover = as.numeric(A$turnover_annual),
    diag_rank_ic = metaA$diag_rank_ic_mean, n_months = as.numeric(A$n_months)),
  paired_vs_armA = list(n_months = nrow(j), mean_diff_monthly = mean(d),
    mean_diff_ann_pct = 100*12*mean(d), nw3_t = t_paired, threshold = 2.0),
  secondary = metaC$secondary,
  striking_pattern_5arm = list(
    observation = "armB 가 n=4 에서 관찰한 'rank-IC 순서와 total SR 순서가 정확히 역순'(Spearman -1.0)은 arm C 를 5번째 점으로 넣자 -0.40 으로 약해진다. arm C 는 rank-IC 2위이면서 total SR 1위 — 그 서열 관찰의 **반례**다.",
    table = tab, rank_ic_vs_sr_spearman = sr_rank_inv,
    caution = "⚠n=5 이고 arm 들은 같은 패널·같은 피처·같은 워크포워드를 공유해 **독립이 아니다**(armB caution 승계). 게다가 5 arm 전부 |PORT_t| < 1.4 로 어느 것도 0 과 유의하게 다르지 않다 — 서열은 관찰이지 성과 주장이 아니며, 그 서열이 흔들린 것 역시 검정된 반증이 아니다.",
    consequence = "armB 가 이 관찰 위에 올렸던 서술('순위통계 개선이 top-N 평균 소비로 전이되지 않는다')은 n=4 관찰이었고 5번째 점이 그것을 지지하지 않는다. FQ-237 의 근거로 인용할 때 이 갱신을 함께 인용할 것."),
  basis_note = "1급 축 = total net SR + paired 월간 net NW lag-3 t. 계약 net_sr(=active IR 0.2628)과 혼용 금지(사전등록 §4 — arm A 가 밟은 함정).",
  mechanism_reading = "★이 라운드 최대 수확 = **개별 꼬리확률은 둘 다 음(-)의 rank-IC 인데 차분만 양(+)** 이다. p_up -0.0245 · p_dn -0.0454 인데 score = p_up - p_dn 은 +0.0331. 두 확률이 공통으로 싣는 성분(고변동 종목일수록 상·하방 꼬리 확률이 **동시에** 높아진다)이 차분에서 상쇄되고 방향 성분만 남는다는 읽기와 정합한다. ⚠이것은 진단 rank-IC 수준의 관찰이고, 실현 포트에서는 arm A 와 구분되지 않는다(paired NW3 t +0.0876). 즉 '표적을 꼬리확률로 바꾸면 순위 신호의 **구성**이 달라진다'까지는 실측이고, '실현 성과가 개선된다'는 미지지다.",
  honest_labels = list(
    "자본 자격 주장 아님 — PORT_t 0.8536(p 0.3933)은 HARD 2.95 에 한참 못 미치고, MDD 51.59% 는 제약 25% 의 2배, 회전율 17.42/yr 은 Implementation Discipline 11.0 초과, Calmar 0.2997 은 HARD 0.64 미달. 편입 후보를 만들지 않는다(사전등록 §7).",
    "★total net SR 0.7224 가 5 arm 중 1위지만 **개선 주장 아님** — 사전등록 §4 가 판정하는 축은 arm A 대비 paired NW3 t 이고 그 값 +0.0876 은 문턱 ±2.0 안이다. SR 격차(0.6039 -> 0.7224)를 성과 개선으로 읽는 것은 사전등록이 막은 사후 축 교체다.",
    "MDD 64.04% -> 51.59% 개선도 같은 이유로 주장 아님 — 사전등록에 MDD 검정이 없고 병기 의무 항목일 뿐이다.",
    "Bowley 왜도는 arm B 예측에서 **재학습 0회**로 파생(rank-IC -0.0115, 약). secondary 이며 primary 교체 대상 아님(사전등록 §3).",
    "CRPS 0.0752 는 분위 3개로 만든 **3점 앙상블 근사**이지 연속 분포 CRPS 가 아니다 — arm 간 비교량으로 쓰지 말 것.",
    "DSR 0.8558 은 selection_type=chain 이라 n_trials=1 로 산출됐고, 그 경우 repo 구현이 sr0=0 으로 퇴화시킨다(= PSR vs 0). **다중검정 보정이 실제로 걸리지 않은 수치**이며 게이트 아님(사전등록 §5)."),
  prereg_discipline_notes = list(
    "★p_up/p_dn 단독 canonical 백테를 **돌리지 않았다** — 사전등록 §3 이 secondary 를 Bowley(+CRPS·diag rank-IC)로 한정한다. arm B 에서 'q90 이 좋아 보인다'가 primary 교체 유혹을 만든 바로 그 표면이라, 측정 자체를 만들지 않는 쪽을 택했다.",
    "DSR — §5 는 '산출·기록'을 요구하는데 계약(essence_score.R)은 n_trials>1 에서만 DSR 을 낸다. 손계산 대신 repo 구현 .essence_dsr() 을 n_trials=1 로 직접 호출했고(자체합성 회피), 그 경우 PSR(0) 로 퇴화한다는 성격을 라벨로 붙였다.",
    "CRPS — §3 이 'properscoring, q10/50/90 대비 실현'이라 썼지만 분위 3개로는 연속 CRPS 가 나오지 않는다. crps_ensemble 3점 근사임을 caveat 로 명시했다(그냥 'CRPS' 로 보고했으면 arm 간 비교 가능한 양처럼 읽혔을 것).",
    "5-arm 서열 — arm C 가 rank-IC 2위 ∧ SR 1위라 arm B 의 '완전 역순'을 깬다. 이를 '표적 형태가 마침내 정렬됐다'는 성과 서술로 쓸 유혹이 있었으나 PORT_t 0.85(p 0.39)·paired t 0.09 이므로 서열 관찰로만 기록했다.",
    "basis — 1급 축을 total net SR 로 고정하고 계약 net_sr(=active IR)은 별도 필드로 병기했다(사전등록 §4 명시 사항)."),
  next_probes = list(
    "★p_up·p_dn 이 둘 다 음의 rank-IC 인데 차분만 양수인 구조의 기전 확인 — 두 확률을 변동성 대리변수로 회귀한 **잔차**의 rank-IC 를 측정. 공통성분이 정말 vol 이면 '꼬리확률을 vol-중립화해 쓰는' 별도 소비형이 생긴다.",
    "★검정력 사전 계산 — arm A/B/C 3 라운드가 전부 paired |t| < 1.3 이다. 198개월 paired 로 감지 가능한 최소 연환산 격차를 contracts/required_effect_size.R 로 **착수 전** 고정해야 '미지지'가 **미결(underpowered)** 인지 **종결(powered null)** 인지 갈린다. 현 상태로는 세 라운드 모두 라벨이 미확정이다.",
    "armB 의 4-arm 역순 관찰이 arm C 로 깨졌으므로 FQ-237(선별 목적함수 rank-IC -> 분위 스프레드)의 근거가 약해진다 — 서열 관찰의 진위를 팩터 수준(R32 320종)에서 top-N 실현과 대조해 재판정.",
    "MDD 64% -> 52% 는 본 라운드의 검정 대상이 아니었다 — 표적 형태의 효과가 평균이 아니라 **분산·하방**에 있을 가능성을 별도 사전등록으로(하방 통제 축 primary)."),
  note = "secondary 는 기록 전용 — 사전등록 §3 이 primary 교체·재학습을 금지한다."),
  file.path(OUT, "armC_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
saveRDS(list(C = C, paired = list(t = t_paired, d = d, j = j), tab = tab, dsr = dsr_diag),
        file.path(OUT, "armC_full.rds"))
cat("\n저장: armC_result.json · armC_full.rds\n")
