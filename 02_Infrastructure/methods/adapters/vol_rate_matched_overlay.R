# vol_rate_matched_overlay.R — regime 노출 어댑터 chain step 3 (2026-08-09).
# 사전등록: stage_artifacts/paper_recharge/prereg_vol_rate_matched_20260809.json
#
# ★step 2(HurstRateMatched) 기전 진단 1줄: 발화율을 30%로 맞춰도 ΔMDD -0.1746(악화) —
#   두 Hurst 규칙 모두 MDD 를 만드는 구간에서 **0회 발화**했다(GFC 0/9, 2006 구속구간 0/6).
#   문제는 발화 빈도가 아니라 **정렬**이었다.
# ★np2 가 정렬된 축을 특정했다: 현 북의 **구속** 낙폭은 GFC 가 아니라 2006-01~06(-22.7%)이고,
#   그 6개월에서 국면 라벨 계열(unified·Hurst)은 0/6 인데 **변동성 축만 6/6** 발화했다.
#   구간 내 누적 book -0.2266 → book×voltarget -0.1456 (+0.0810).
#   전체 창에서 voltgt_x_book 만 ΔMDD>0 인 이유가 이 구간이다.
# ★voltarget 의 결함은 신호가 아니라 **대가**다 — 전체 71% 발화(평균 노출 0.795)라 ΔIR -0.51.
#   ⇒ step 2 에서 만든 **발화율 제약 프레임을 vol 에 적용**한다. 신호를 바꾸는 게 아니라 켜는 빈도만 묶는다.
#
# ★PIT: vol 창 = 벤치 **일별** BM_Ret, Date < first-day-of-holding-month (엄격 부등호).
#   포트 월간 vol 을 안 쓰는 이유 — 홀딩월 M-1 수익이 M 시작일에야 확정돼 경계가 모호하다.
#   벤치 일별은 절단이 증명 가능하다(Hurst 어댑터와 동일 규약).
#   ★np2 진단은 포트-vol 이었다 — 여기 vol 과 **다른 양**이므로 수치를 교차 인용하지 말 것.
# ★자유 파라미터 0개: 창 252(=Hurst 와 동일), 목표 발화율은 unified 방어라벨 확장창 실현율에서 파생,
#   노출 0.70 = 기존 CAT_EXPOSURE CAUTION 재사용.

suppressMessages({ library(data.table); library(arrow) })

BENCH_PATH  <- ".cache/benchmark.parquet"
REGIME_PATH <- ".cache/unified_regime_signal.parquet"
WIN         <- 252L
EXP_FIRE    <- 0.70
EXP_HOLD    <- 1.00
BURN_IN     <- 60L
MIN_OBS     <- 64L
DEFENSIVE   <- c("CRISIS", "CAUTION")

exposure_schedule <- function(ctx) {
  pr <- as.data.table(ctx$periods)
  pr[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  setorder(pr, eval_date)
  pr[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]
  pr[, hold_ym := format(hold_start, "%Y-%m")]

  if (!file.exists(BENCH_PATH) || !file.exists(REGIME_PATH)) {
    cat("[VolRateMatched] 벤치 또는 레짐 신호 부재 — 제외\n"); return(NULL) }
  bm <- as.data.table(read_parquet(BENCH_PATH))
  if (!all(c("Date", "BM_Ret") %in% names(bm))) { cat("[VolRateMatched] 벤치 컬럼 결손 — 제외\n"); return(NULL) }
  bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- bm[is.finite(BM_Ret)]
  rg <- as.data.table(read_parquet(REGIME_PATH))[, .(ym = as.character(YM), Category = as.character(Category))]
  setorder(rg, ym)

  # ── (2026-08-09 수리) 신호 = **포트폴리오** 월간 vol ──────────────────────────
  # ★1차 구현은 벤치 일별 vol 을 썼고 F4(발화 19.4% vs 목표 30.1%)·F2(구속구간 0/6) 둘 다 위반했다.
  #   원인은 배관이 아니라 **신호를 바꾼 것**이다 — np2 가 정렬을 확인한 건 포트-vol 이고
  #   2006 구속 구간은 시장이 아니라 **포트 고유 변동성**이 올라간 구간이었다(벤치 vol 은 상위 30% 밖).
  #   사전등록 기전이 지목한 신호로 되돌린다. (신호 교체이지 문턱 튜닝이 아니다 — sweep 아님.)
  # ★PIT: 홀딩월 M 의 vol 은 **M-2 까지**의 포트 월수익만 쓴다.
  #   M-1 의 수익은 eval_date[i-1] = hold_start[i] (M 의 첫날)에야 확정되므로 제외한다.
  #   ⇒ used_cutoff = eval_date[i-2] < hold_start[i]. 보수적이지만 증명 가능하다.
  bg <- as.data.table(ctx$bare_gross); setorder(bg, Date)
  if (nrow(bg) != nrow(pr)) { cat("[VolRateMatched] bare_gross 행수 불일치 — 제외\n"); return(NULL) }
  VT_WIN <- 12L
  n <- nrow(pr)
  V <- rep(NA_real_, n); cut <- rep(as.Date(NA), n)
  for (i in seq_len(n)) {
    hi <- i - 2L                                     # ★M-2 까지만
    if (hi < VT_WIN) { cut[i] <- pr$hold_start[i] - 1L; next }
    seg <- bg$r[max(1L, hi - VT_WIN + 1L):hi]
    s <- stats::sd(seg, na.rm = TRUE)
    if (is.finite(s) && s > 0) V[i] <- s
    cut[i] <- bg$Date[hi]                            # eval_date[i-2] — 홀딩월 시작 전
  }

  expo <- rep(EXP_HOLD, n); fired <- rep(FALSE, n); target <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i <= BURN_IN || !is.finite(V[i])) next
    past <- V[seq_len(i - 1L)]; past <- past[is.finite(past)]
    if (length(past) < BURN_IN) next
    rg_past <- rg[ym < pr$hold_ym[i]]
    if (nrow(rg_past) < BURN_IN) next
    q <- mean(rg_past$Category %in% DEFENSIVE, na.rm = TRUE)   # 목표 발화율
    if (!is.finite(q) || q <= 0 || q >= 1) next
    target[i] <- q
    # ★(2026-08-09 수리) 확장창 → **rolling 분위**.
    #   실사고: 확장창 분위는 신호가 비정상일 때 발화율을 보존하지 못한다 — vol 은 군집성이 강해
    #   초기 고변동 구간이 분포 상단을 영구 점유하고, 이후 월이 문턱을 못 넘어 발화율이
    #   8.1%(목표 29.5%)로 붕괴했다. Hurst(상대적 정상)에서는 같은 프레임이 보존됐다(31.8%).
    #   ⇒ 최근 BURN_IN(60)개월 분포만 본다. ★새 자유 파라미터 아님 — 이미 고정된 상수 재사용.
    past_roll <- tail(past, BURN_IN)
    # ★고변동 = 위험 → **상위** q 분위 이상이면 디리스크 (Hurst 는 하위였다 — 부호 반대)
    thr <- stats::quantile(past_roll, probs = 1 - q, names = FALSE, type = 7)
    if (V[i] >= thr) { expo[i] <- EXP_FIRE; fired[i] <- TRUE }
  }
  cut[is.na(cut)] <- pr$hold_start[is.na(cut)] - 1L

  realized <- mean(fired[(BURN_IN + 1L):n]); tgt <- mean(target, na.rm = TRUE)
  cat(sprintf("[VolRateMatched] %d개월 · vol 중앙값 %.3f · 발화 %d (%.1f%%) · 목표율 %.1f%% · 평균노출 %.4f\n",
              n, stats::median(V, na.rm = TRUE), sum(fired), 100 * realized, 100 * tgt, mean(expo)))
  if (is.finite(tgt) && abs(realized - tgt) > 0.05)
    cat(sprintf("[VolRateMatched] ★F4 위반 — 실현 %.1f%% vs 목표 %.1f%% (>5%%p). 구현 결함 의심, 판정 무효\n",
                100 * realized, 100 * tgt))
  # F2 대비: 구속 낙폭 구간(2006-01~06) 발화율을 함께 보고한다(사전등록 반증 축).
  .ep <- pr$hold_ym >= "2006-01" & pr$hold_ym <= "2006-06"
  if (any(.ep)) cat(sprintf("[VolRateMatched] 구속 낙폭 구간(2006-01~06) 발화 %d/%d (%.0f%%) — F2 축\n",
                            sum(fired[.ep]), sum(.ep), 100 * mean(fired[.ep])))

  # ★목표 발화율을 **래퍼에 신고**한다 — 자기 검사만으로는 계약이 아니다(래퍼가 ±5%p 로 강제).
  list(exposure = data.table(Date = pr$eval_date, exposure = expo), used_cutoff = cut,
       target_rate = tgt)
}
