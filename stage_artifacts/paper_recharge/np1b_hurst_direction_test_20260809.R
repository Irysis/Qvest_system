#!/usr/bin/env Rscript
# np1b_hurst_direction_test_20260809.R — regime 라운드 next_probe 1 (고검정력 판)
#
# 질문: "하락도 추세다" 기전의 직접 검정. Hurst 는 지속성을 **방향 무관**으로 재는가?
#   그렇다면 H 는 다가올 하락월을 구별하지 못한다(= long-only 방어 전용 불가).
#   9개월 GFC 표본(0/9, p≈0.076 저검정력) 대신 **269개월 전체**를 쓴다.
#
# ★사전등록
#   H1(주장): E[H | 다음달 하락] ≈ E[H | 다음달 상승]  — 방향 무관
#   F1(반증): H 가 하락월에서 **유의하게 낮으면** 신호는 방어 정보를 갖고 있고
#             실패는 신호가 아니라 사상(mapping)에 있다 → Hurst 레인 재개.
#   사건 정의 3종: ret<0 · ret<-5% · ret<-10%
#     ([[project-label-eligibility-is-event-conditional-20260808]] — 자격은 (라벨,사건) 쌍에 붙는다.
#      한 정의에서의 무효를 다른 정의로 일반화하지 않는다.)
#   ★음성/양성 대조 의무: 같은 검정을 unified 방어라벨에도 돌린다. 그게 유의하지 않으면
#     **검정이 죽은 것**이지 신호가 없는 게 아니다(오탐 제거와 검사 사망은 겉보기가 같다).
#   검정력: 셀별 n·se·80% 검출가능차이를 **먼저** 보고한다.
# 자본 판정 아님(metric_type=diagnostic).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
M <- car[, .(bare = sum((weight_strategy / sum(weight_strategy)) * ret_fwd)),
         by = .(decision_date, eval_date)]
setorder(M, eval_date)
M[, hold_ym := format(decision_date, "%Y-%m")]

# H (홀딩월 시작 전 데이터만 — 어댑터와 동일 산출)
src <- new.env(parent = globalenv())
sys.source("02_Infrastructure/methods/adapters/hurst_trend_overlay.R", envir = src)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date = as.Date(Date), BM_Ret)]
setorder(bm, Date); bm <- bm[is.finite(BM_Ret)]
M[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]
M[, H := vapply(hold_start, function(hs) {
  w <- bm[Date < hs]; if (nrow(w) < 64L) return(NA_real_)
  src$.hurst_rs(tail(w, 252L)$BM_Ret) }, numeric(1))]

rg <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(ym = as.character(YM), Category = as.character(Category))]
M[, ym_sig := format(as.Date(format(decision_date, "%Y-%m-01")) - 1, "%Y-%m")]
M[rg, on = c(ym_sig = "ym"), uni := i.Category]
M[, uni_def := uni %in% c("CRISIS", "CAUTION")]

D <- M[is.finite(H) & !is.na(uni_def)]
say("검정 표본 %d개월 (%s ~ %s) · metric_type=diagnostic", nrow(D), min(D$hold_ym), max(D$hold_ym))

EVENTS <- list("ret<0" = 0, "ret<-5%" = -0.05, "ret<-10%" = -0.10)
res <- list()
for (nm in names(EVENTS)) {
  thr <- EVENTS[[nm]]
  D[, ev := bare < thr]
  n1 <- sum(D$ev); n0 <- sum(!D$ev)
  say("\n══ 사건 = %s · 발생 %d / 비발생 %d ══", nm, n1, n0)
  if (n1 < 5L) { say("  n<5 — 검정 불가(생략)"); next }

  # ── 검정력 먼저 ([[project-underpowered-nulls-regime-conditional-20260808]]) ──
  sdH <- stats::sd(D$H, na.rm = TRUE)
  se  <- sdH * sqrt(1 / n1 + 1 / n0)
  mde <- 2.80 * se        # 양측 α=.05, power .80 (1.96+0.84)
  say("  [검정력] H 표준편차 %.4f · se %.4f · 80%% 검출가능차이(MDE) %.4f (= H 표준편차의 %.2f배)",
      sdH, se, mde, mde / sdH)

  tt <- stats::t.test(H ~ ev, data = D)
  wt <- suppressWarnings(stats::wilcox.test(H ~ ev, data = D))
  dif <- mean(D[ev == TRUE]$H) - mean(D[ev == FALSE]$H)
  say("  [H] 사건월 평균 %.4f vs 비사건월 %.4f · 차이 %+.4f · Welch t=%.3f p=%.4f · MWU p=%.4f",
      mean(D[ev == TRUE]$H), mean(D[ev == FALSE]$H), dif, unname(tt$statistic), tt$p.value, wt$p.value)
  say("      → %s", if (tt$p.value < 0.05 && dif < 0) "★F1 반증: H 가 하락월에서 유의하게 낮다"
                    else if (abs(dif) < mde) sprintf("H1 유지 — 차이 %+.4f 가 MDE %.4f 미만(구별 불가)", dif, mde)
                    else "차이는 MDE 초과이나 유의하지 않음")

  # 양성 대조: 같은 사건 정의에서 unified 라벨은 판별하는가
  tab <- table(D$uni_def, D$ev)
  ft <- suppressWarnings(stats::fisher.test(tab))
  lift <- (mean(D[ev == TRUE]$uni_def)) / (mean(D$uni_def))
  say("  [양성대조 unified] 사건월 발화율 %.3f vs 전체 %.3f · lift %.2f · Fisher p=%.4g",
      mean(D[ev == TRUE]$uni_def), mean(D$uni_def), lift, ft$p.value)
  say("      → %s", if (ft$p.value < 0.05) "검정 살아있음(양성 대조 통과)" else "★양성 대조 실패 — 이 사건 정의에선 검정 자체가 무력")

  res[[nm]] <- list(event = nm, n_event = n1, n_nonevent = n0,
                    H_mean_event = round(mean(D[ev == TRUE]$H), 4),
                    H_mean_nonevent = round(mean(D[ev == FALSE]$H), 4),
                    H_diff = round(dif, 4), mde_80 = round(mde, 4),
                    t_p = signif(tt$p.value, 4), mwu_p = signif(wt$p.value, 4),
                    uni_lift = round(lift, 3), uni_fisher_p = signif(ft$p.value, 4))
}

say("\n══ 부가: H ↔ 다음달 수익 순위상관 (전체 %d개월) ══", nrow(D))
sp <- suppressWarnings(stats::cor.test(D$H, D$bare, method = "spearman"))
say("  Spearman rho=%.4f p=%.4f → %s", unname(sp$estimate), sp$p.value,
    if (sp$p.value < 0.05) "유의" else "비유의(H 는 다음달 수익 순위와 무관)")

out <- list(schema = "np1b_hurst_direction_test_v1", date = "20260809", metric_type = "diagnostic",
            prereg = list(H1 = "E[H|하락] ≈ E[H|상승] (방향 무관)",
                          F1 = "H 가 하락월에서 유의하게 낮으면 반증 — 실패는 신호가 아니라 사상"),
            n_months = nrow(D), events = res,
            spearman = list(rho = round(unname(sp$estimate), 4), p = signif(sp$p.value, 4)))
write(toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      "stage_artifacts/paper_recharge/np1b_hurst_direction_test_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/np1b_hurst_direction_test_20260809.json")
