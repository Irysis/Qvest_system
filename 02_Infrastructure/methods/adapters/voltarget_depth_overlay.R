# voltarget_depth_overlay.R — regime 노출 어댑터 chain step 4 (2026-08-09).
# 사전등록: stage_artifacts/paper_recharge/prereg_voltarget_depth_20260809.json
#
# ★step 3(VolRateMatched) 기전 진단 1줄: 발화율을 29.5%→27.5% 로 맞춰도 ΔMDD -0.1746(개선 없음)이고
#   구속 낙폭 구간(2006-01~06) 발화 0/6. 반면 원본 voltgt(발화 71%)는 6/6 잡는다.
#   ⇒ voltgt 의 방어는 **절대 문턱** min(1, 0.055/vol) 에서 오지 상대 분위에서 오지 않는다
#     (2006 포트 vol 은 절대로는 목표의 1.6~2배지만 최근 60개월 분포로는 상위 30% 밖).
#   ⇒ 발화율 축은 막혔다. 남은 축 = **노출 깊이**.
#
# ★질문: 발화(절대 문턱)는 그대로 두고 **얼마나 줄이나**만 완화하면 IR 대가가 줄면서 방어가 남는가?
#   voltgt 는 평균 노출 0.793 까지 연속 축소한다(ΔIR -0.508). 바닥을 두면?
#
# ★대조 설계 — 바닥의 효과를 격리한다:
#   · `exposure_schedule_nofloor` = 바닥 없음 (통제)   ← 하네스 내장 voltgt 와 같은 규칙이되 PIT 만 엄격
#   · `exposure_schedule`         = 바닥 0.70 (처리)
#   두 팔의 차이 = 바닥 효과. 하네스 내장 voltgt 와 직접 비교하면 **PIT 차이(shift-1 vs shift-2)가 교락**되므로
#   반드시 이 파일 안의 nofloor 를 통제로 쓴다.
#
# ★자유 파라미터 0개: 목표 0.055·창 12 = 하네스 내장 voltgt 상수 그대로.
#   바닥 0.70 = CAT_EXPOSURE CAUTION 재사용. **바닥값을 흔들면 그 순간 sweep 이다 — 1개 값만 잰다.**
#
# ★PIT: 홀딩월 M 의 vol 은 **M-2 까지**의 포트 월수익만(M-1 은 M 첫날에야 확정).
#   used_cutoff = eval_date[i-2] < hold_start[i]. 하네스 내장 voltgt(shift-1)보다 보수적이다.

suppressMessages({ library(data.table) })

VT_TARGET_M <- 0.055   # 하네스 내장 voltgt 와 동일
VT_WIN      <- 12L
FLOOR       <- 0.70    # CAT_EXPOSURE CAUTION 재사용

.vt_core <- function(ctx, use_floor) {
  pr <- as.data.table(ctx$periods)
  pr[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  setorder(pr, eval_date)
  pr[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]
  bg <- as.data.table(ctx$bare_gross); setorder(bg, Date)
  if (nrow(bg) != nrow(pr)) { cat("[VolTargetDepth] bare_gross 행수 불일치 — 제외\n"); return(NULL) }

  n <- nrow(pr); expo <- rep(1.0, n); cut <- rep(as.Date(NA), n)
  for (i in seq_len(n)) {
    hi <- i - 2L                                    # ★M-2 까지만 (엄격 PIT)
    if (hi < VT_WIN) { cut[i] <- pr$hold_start[i] - 1L; next }
    s <- stats::sd(bg$r[(hi - VT_WIN + 1L):hi], na.rm = TRUE)
    cut[i] <- bg$Date[hi]
    if (is.finite(s) && s > 0) expo[i] <- min(1.0, VT_TARGET_M / s)
  }
  if (use_floor) expo <- pmax(FLOOR, expo)
  cut[is.na(cut)] <- pr$hold_start[is.na(cut)] - 1L
  lbl <- if (use_floor) sprintf("floor%.2f", FLOOR) else "nofloor"
  fired <- expo < 1 - 1e-12
  .ep <- format(pr$hold_start, "%Y-%m") >= "2006-01" & format(pr$hold_start, "%Y-%m") <= "2006-06"
  cat(sprintf("[VolTargetDepth:%s] %d개월 · 발화 %d (%.1f%%) · 평균노출 %.4f · 최저노출 %.3f · 구속구간 발화 %d/%d\n",
              lbl, n, sum(fired), 100 * mean(fired), mean(expo), min(expo), sum(fired[.ep]), sum(.ep)))
  # ★발화율 계약은 신고하지 않는다 — 이 어댑터는 **절대 문턱**이라 목표 발화율 개념이 없다.
  #   (신고하지 않으면 래퍼가 검사를 건너뛴다 = 계약상 정상. 없는 목표를 지어내지 않는다.)
  list(exposure = data.table(Date = pr$eval_date, exposure = expo), used_cutoff = cut)
}

#' 처리군 — 바닥 0.70
exposure_schedule <- function(ctx) .vt_core(ctx, use_floor = TRUE)
#' 통제군 — 바닥 없음 (PIT 만 엄격한 voltgt)
exposure_schedule_nofloor <- function(ctx) .vt_core(ctx, use_floor = FALSE)
