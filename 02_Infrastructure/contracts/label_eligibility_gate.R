## label_eligibility_gate.R — 라벨 자격 관문 (FQ-119)
##
## 왜 필요한가 — 2026-08-03 실측 3건이 같은 곳을 가리켰다:
##   ① WT-017/019: 국면 라벨 CRISIS recall 0.096 < base rate 0.457 (fisher p 0.388)
##      = 라벨이 위기를 위기로 못 잡는데 그 라벨로 오버레이/배분을 재고 있었다.
##   ② WT-D20260803_006: 음성대조로 기존 국면 라벨 적중 0.3669 — 독립 재확인.
##   ③ WT-019: 무판별 라벨을 소비면에 강행하면 **발화 월수에 비례해 유해**(paired -3.77).
##      "틀려도 보험"이 반증됐다 — 판별력 없는 라벨은 중립이 아니라 손실이다.
##
## ★핵심: 라벨의 소비(오버레이·배분·필터·tripwire) 이전에 **라벨 자체가 자격이 있는가**를 묻는다.
##   자격 없는 라벨을 소비면에 태운 라운드는 그 결과가 양수든 음수든 해석 불가다.
##
## 사용:
##   source("02_Infrastructure/contracts/label_eligibility_gate.R")
##   g <- label_eligibility(label_on, event_true)     # 둘 다 논리형 벡터(같은 길이)
##   if (!g$eligible) stop(g$reason)                  # 소비 측정 착수 금지
##
## 반환: list(eligible, recall, base_rate, lift, fisher_p, n, n_on, n_event, reason, verdict)

`%||%` <- function(a, b) if (is.null(a)) b else a

## 문턱 — 사전 고정(sweep 금지). 근거는 위 실측 3건.
LABEL_GATE_ALPHA <- 0.05   # fisher 단측 p 문턱

#' 라벨 자격 판정
#'
#' @param label_on   논리형. 그 시점에 라벨이 켜졌는가(PIT: 사전 관측가능해야 함)
#' @param event_true 논리형. 그 시점이 실제로 표적 사건이었는가(실현 기준)
#' @param alpha      fisher 단측 p 문턱
#' @return list — eligible 이 FALSE 면 소비 측정 착수 금지
label_eligibility <- function(label_on, event_true, alpha = LABEL_GATE_ALPHA) {
  stopifnot(length(label_on) == length(event_true))
  ok <- !is.na(label_on) & !is.na(event_true)
  lab <- as.logical(label_on)[ok]
  evt <- as.logical(event_true)[ok]
  n <- length(lab)

  ## 빈 입력·상수 입력이 '합격'으로 새지 않게 — 결측은 결측으로 보고한다
  ##   (실사고 계통: 빈 결과가 PASS 로 읽히는 것. 여기서는 UNMEASURABLE 로 분리.)
  if (n == 0L)
    return(list(eligible = NA, recall = NA_real_, base_rate = NA_real_, lift = NA_real_,
                fisher_p = NA_real_, n = 0L, n_on = 0L, n_event = 0L,
                verdict = "UNMEASURABLE_NO_DATA",
                reason = "공통 관측 0 — 자격 판정 불가(합격 아님)"))
  n_on <- sum(lab); n_event <- sum(evt)
  if (n_on == 0L || n_on == n || n_event == 0L || n_event == n)
    return(list(eligible = NA, recall = NA_real_, base_rate = mean(evt), lift = NA_real_,
                fisher_p = NA_real_, n = n, n_on = n_on, n_event = n_event,
                verdict = "UNMEASURABLE_DEGENERATE",
                reason = sprintf("라벨 또는 사건이 상수(n_on=%d/%d, n_event=%d/%d) — 판별력 정의 불가",
                                 n_on, n, n_event, n)))

  ## recall = 라벨이 켜졌을 때 실제 사건일 확률(정밀도 축).
  ##   base_rate 는 그냥 사건 빈도 — 라벨이 아무 정보도 없으면 recall ≈ base_rate 가 된다.
  recall    <- mean(evt[lab])
  base_rate <- mean(evt)
  lift      <- recall / base_rate

  ## 단측 Fisher — "라벨 ON 이 사건과 양의 연관" 만 자격으로 인정(반대 방향은 자격 아님)
  tab <- matrix(c(sum(lab & evt), sum(lab & !evt),
                  sum(!lab & evt), sum(!lab & !evt)), nrow = 2)
  fp <- tryCatch(stats::fisher.test(tab, alternative = "greater")$p.value,
                 error = function(e) NA_real_)

  passed <- isTRUE(recall > base_rate) && isTRUE(fp < alpha)
  list(
    eligible = passed, recall = recall, base_rate = base_rate, lift = lift,
    fisher_p = fp, n = n, n_on = n_on, n_event = n_event,
    verdict = if (passed) "ELIGIBLE" else "INELIGIBLE_NO_DISCRIMINATION",
    reason = if (passed)
      sprintf("자격 통과 — recall %.3f > base %.3f (lift %.2fx), fisher p %.4f < %.2f",
              recall, base_rate, lift, fp, alpha)
    else
      sprintf(paste0("자격 미달 — recall %.3f vs base %.3f (lift %.2fx), fisher p %.4f. ",
                     "★이 라벨로 소비면(오버레이/배분/필터/tripwire)을 측정하지 말 것: ",
                     "판별력 없는 라벨은 중립이 아니라 발화 월수에 비례해 유해하다(WT-019 paired -3.77)."),
              recall, base_rate, lift, fp)
  )
}

#' 소비 측정 착수 직전 호출용 — 미달이면 중단시킨다
assert_label_eligible <- function(label_on, event_true, label_name = "label", alpha = LABEL_GATE_ALPHA) {
  g <- label_eligibility(label_on, event_true, alpha = alpha)
  if (isTRUE(g$eligible)) { message(sprintf("[label_gate] %s: %s", label_name, g$reason)); return(invisible(g)) }
  stop(sprintf("[label_gate] %s 자격 미달 — 소비 측정 착수 금지.\n  %s\n  verdict=%s",
               label_name, g$reason, g$verdict), call. = FALSE)
}
