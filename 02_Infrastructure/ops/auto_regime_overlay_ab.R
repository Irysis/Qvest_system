#!/usr/bin/env Rscript
# auto_regime_overlay_ab.R — H2 regime 오버레이 A/B (도훈 mandate 2026-06-18, "regime H2 바로 진행").
#
# 목적: §6 SR2.5 유일 입증 레버 = overlay. 현 book 오버레이(M4 BOCPD × AR × R05 tail)에 *추가/대체* regime 신호가 SR 개선하는지 검증.
#   후보 regime 신호: ① unified_regime_signal(MSM+FRED+KTRI+VEA 앙상블 — book의 M4와 *다른* 탐지기) ② vol-target(변동성 타겟팅, 더 granular).
#   각 후보를 (a) standalone 오버레이 (b) book 오버레이에 *stacked* 로 테스트. 비교: bare / book_L5 / 후보들.
#   AX-001 v2: 방어형은 조건부 평가 — CRISIS 라벨 월에서 손실 완화·crisis_alpha 동반 산출.
# 토대: 가중=strategy(현 book) 고정, exposure 스칼라만 변경(weighted_screen_bt exposure_dt). 캐리어 selection 고정.
# PIT: regime 신호는 *직전 월말*(decision 이전 known) lag 적용. vol-target은 trailing 12m(strictly before). 자본 admit 없음(측정만).
# 단일스레드(arrow): OMP_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN = "1")
source("02_Infrastructure/ops/auto_weighting_ab.R")   # build_period_bench / build_overlay_exposure / WEIGHTERS$strategy
source("02_Infrastructure/validation/overlay_pit_guard.R")  # assert_overlay_pit (C5 HARD, 2026-07-06 도훈 지시)

# ── (2026-08-09 basis 수리 ①) 캐리어는 carrier_meta.json 에서 파생 ──────────────
#   구판은 `carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet` **하드코딩**이었다.
#   그 캐리어는 2026-06-18 빌드 · book_state 2026-06-02 기준인데, 그 사이 book 은 07-19 로
#   갱신돼 admitted_ids = `STR_1715_on_M4gAE_R05_noLayer4_PG2`(오토인코더 + Layer4 제거)가 됐다.
#   즉 이 하네스는 **07-02 에 도훈이 FINAL 로 제거 지시한 Layer4/overlay 구성**을 기준선으로 재고 있었다.
#   optimizer 레인이 08-08 에 같은 결함으로 7주간 퇴역 PG2 를 기준선으로 썼고(도훈 적발),
#   그 수리(1안 ④)와 **같은 형태**로 맞춘다 — 하드코딩이 아니라 meta 경유가 "현 PG2 자동 추종"이다.
.carrier_from_meta <- function() {
  mp <- "06_Registry/book_carrier/carrier_meta.json"
  if (!file.exists(mp)) stop("[regime_ab] carrier_meta.json 부재 — 캐리어 미빌드. extract_book_carrier_d3.R 선행.")
  mt <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  p <- as.character(mt$parquet %||% NA)
  if (is.na(p) || !file.exists(p)) stop("[regime_ab] carrier_meta$parquet 무효: ", p)
  cat(sprintf("[regime_ab] 캐리어(meta 경유) = %s [strategy=%s]\n", basename(p), mt$strategy %||% "?"))
  p
}
CARRIER <- NULL   # ★하드코딩 제거. 기본값은 호출 시 .carrier_from_meta() 로 지연 해석.
# regime Category → exposure(=1-cash) 디리스크 스케줄 (book deprecated cash NORMAL10/CAUTION20/CRISIS40 정합 + RISK_ON full)
CAT_EXPOSURE <- c(RISK_ON = 1.00, NEUTRAL = 1.00, CAUTION = 0.70, CRISIS = 0.40, RISK_OFF = 0.40)
VT_TARGET_M <- 0.055   # 월간 목표 변동성(~19% 연율) 고정상수(lookahead 없음). long-only no-lev → exposure=min(1, target/trailing).
VT_WIN <- 12L

.prev_month_ym <- function(d) format(as.Date(format(as.Date(d), "%Y-%m-01")) - 1, "%Y-%m")

#' 후보 regime exposure 스케줄(Date=eval_date, exposure) PIT 직전월 lag.
build_unified_cat_exposure <- function(periods) {
  # ★(2026-08-09) 신호 행의 실제 Date 도 함께 끌어온다 — PIT 컷오프를 **가정하지 말고 실측**해야
  #   assert_overlay_pit 이 대용품이 아니라 진짜 사용시점을 검사한다([[feedback-identify-before-existence-check]]).
  u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[
        , .(ym_sig = as.character(YM), Category = as.character(Category), sig_date = as.Date(Date))]
  pr <- as.data.table(copy(periods))
  pr[, ym_sig := .prev_month_ym(decision_date)]            # 직전 월말 신호(decision 이전 known)
  pr[u, on = "ym_sig", `:=`(Category = i.Category, sig_date = i.sig_date)]   # data.table join (base merge 회피)
  pr[, exposure := as.numeric(CAT_EXPOSURE[Category])]
  pr[is.na(exposure), exposure := 1.0]                     # 신호 결측 → full(no overlay)
  list(exp = pr[, .(Date = eval_date, exposure)],
       cat = pr[, .(Date = eval_date, regime_sig = Category)],
       # 홀딩월 = month(decision_date) (실측: decision→eval 간격 31일, 월 겹침 0.000)
       pit = pr[!is.na(sig_date), .(used_cutoff = sig_date,
                                    holding_start = as.Date(format(decision_date, "%Y-%m-01")))])
}
#' vol-target exposure: bare 포트 gross 수익 trailing 12m sd → min(1, target/vol). PIT(strictly before).
build_voltarget_exposure <- function(bare_gross) {       # bare_gross: data.table(Date, r) eval_date 순
  setorder(bare_gross, Date); n <- nrow(bare_gross); exp <- rep(1.0, n)
  for (i in seq_len(n)) {
    if (i > VT_WIN) {
      v <- sd(bare_gross$r[(i - VT_WIN):(i - 1)], na.rm = TRUE)
      if (is.finite(v) && v > 0) exp[i] <- min(1.0, VT_TARGET_M / v)
    }
  }
  data.table(Date = bare_gross$Date, exposure = exp)
}

#' @param book_exposure_source "carrier_invested"(정본) | "layer5"(구판, A/B 대조용)
#' @param extra_exposures  named list: 이름 -> data.table(Date=eval_date, exposure). 논문 유래 후보 합류점.
run_regime_overlay_ab <- function(carrier_path = NULL, cost_bps = 15,
                                  book_exposure_source = "carrier_invested",
                                  extra_exposures = list()) {
  if (is.null(carrier_path)) carrier_path <- .carrier_from_meta()
  car <- as.data.table(read_parquet(carrier_path))[selected == TRUE & !is.na(ret_fwd)]
  car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
  periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)
  bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
  W_strat <- car[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
  bare_gross <- car[, .(r = sum((weight_strategy / sum(weight_strategy)) * ret_fwd)), by = .(Date = eval_date)]

  # ── (2026-08-09 basis 수리 ②) book 오버레이 노출의 정본 = 캐리어 `invested` ──────
  #   구판은 build_overlay_exposure() → 05_Production 2-1 `period_returns_layer5.csv` 의
  #   m4_weight_lag × beta_threshold_lag × beta_R05_V5 를 읽었다. 그 CSV 는 **07-02 에 제거 지시된
  #   Layer4/faith 오버레이 구성**의 산출물이라, book_L5 팔이 "현 book 오버레이"가 아니라
  #   **퇴역 오버레이**를 재고 있었다(그리고 모든 *_x_book stacked 팔이 그걸 상속했다).
  #   D3 캐리어는 북 실측 노출을 `invested` 컬럼으로 들고 있다(net 재현 cor 0.9999) — 그게 정본.
  #   ★구판 경로는 지우지 않고 인자로 남긴다: 두 basis 를 같은 창에서 나란히 재야
  #     "무엇이 바뀌었나"를 수치로 말할 수 있다(측정 없는 교체 = 또 다른 선언).
  .layer5_exp <- function() {
    bx <- build_overlay_exposure()                           # list(exposure, ref) 또는 NULL
    e <- if (is.null(bx)) NULL else if (is.data.frame(bx)) as.data.table(bx) else as.data.table(bx$exposure)
    if (is.null(e)) NULL else e[, .(Date = as.Date(Date), exposure = as.numeric(exposure))]
  }
  book_exp <- NULL; book_basis <- NA_character_
  if (identical(book_exposure_source, "carrier_invested") && "invested" %in% names(car)) {
    book_exp <- unique(car[, .(Date = eval_date, exposure = as.numeric(invested))])
    book_basis <- "carrier_invested"
  } else {
    book_exp <- .layer5_exp()
    book_basis <- if (is.null(book_exp)) "none" else "layer5_legacy"
    if (identical(book_exposure_source, "carrier_invested"))
      cat("[regime_ab] ★캐리어에 invested 부재 — 구판 layer5 로 낙하(basis 라벨에 기록)\n")
  }
  cat(sprintf("[regime_ab] book 오버레이 basis = %s (평균 노출 %.4f)\n", book_basis,
              if (is.null(book_exp)) NA_real_ else mean(book_exp$exposure, na.rm = TRUE)))

  uc <- build_unified_cat_exposure(periods); uni_exp <- as.data.table(uc$exp)
  vt_exp <- as.data.table(build_voltarget_exposure(bare_gross))

  # ── (2026-08-09) C5 오버레이 신호 타이밍 HARD 가드 ────────────────────────────
  #   홀딩월 = 수익이 벌리는 캘린더 월 = month(decision_date) (실측: decision→eval 간격 median 31일,
  #   두 날짜의 월이 겹치는 비율 0.000). 신호는 홀딩월 **시작 전** 데이터만 — 현 구현은
  #   .prev_month_ym(decision_date) 의 월말이라 컷오프 < 홀딩월 시작. 그 사실을 선언이 아니라
  #   **매 실행 검사**로 만든다(2026-07-06 BearProb 실사고 재발 방지 · pit.md C5).
  #   ★컷오프는 가정이 아니라 uc$pit 의 **실제 신호 행 Date** 다.
  assert_overlay_pit(uc$pit$used_cutoff, uc$pit$holding_start, label = "regime_ab/unified_cat")

  # lag1 스트레스: 신호를 한 달 더 미룬 판. base 대비 붕괴하면 동월 누출 의심(유일 판별검정).
  uni_lag1 <- copy(uni_exp); setorder(uni_lag1, Date)
  uni_lag1[, exposure := shift(exposure, 1L, fill = 1.0)]

  # stacked = book × candidate (data.table join)
  stack <- function(a, b) { a[as.data.table(b), on = "Date", .(Date, exposure = x.exposure * i.exposure)] }
  uni_x_book <- if (!is.null(book_exp)) stack(book_exp, uni_exp) else uni_exp
  vt_x_book  <- if (!is.null(book_exp)) stack(book_exp, vt_exp)  else vt_exp

  # ★논문 유래 후보 합류점. extra_exposures 의 원소는 **함수**다
  #   (method_registry::wrap_exposure_adapter 가 계약검사를 두른 exposure_schedule).
  #   여기서 ctx 를 만들어 호출한다 — 스케줄을 미리 만들어 넘기면 어댑터가 periods 를 못 봐서
  #   PIT 컷오프를 자기 창에 맞춰 신고할 수 없다(계약의 핵심이 그 신고다).
  .ctx <- list(periods = periods[, .(decision_date, eval_date)], bare_gross = copy(bare_gross))
  .extra_dt <- list()
  for (.nm in names(extra_exposures)) {
    .e <- tryCatch(extra_exposures[[.nm]](.ctx),
                   error = function(err) { cat(sprintf("[regime_ab] 어댑터 %s 예외: %s — 제외\n",
                                                       .nm, conditionMessage(err))); NULL })
    if (is.null(.e)) { cat(sprintf("[regime_ab] 어댑터 %s 계약 미통과 — 제외\n", .nm)); next }
    .e <- as.data.table(.e)
    .extra_dt[[.nm]] <- .e
    # 논문 후보도 standalone / book-stacked 두 형태로 잰다 — 기존 후보와 같은 대우.
    if (!is.null(book_exp)) .extra_dt[[paste0(.nm, "_x_book")]] <- stack(book_exp, .e)
  }
  if (length(extra_exposures) && !length(.extra_dt))
    cat("[regime_ab] ★등재 어댑터는 있으나 계약 통과 0건 — 조용히 넘기지 않고 호명\n")

  scen <- c(list(bare = NULL, book_L5 = book_exp,
                 uni_cat = uni_exp, uni_cat_lag1 = uni_lag1, uni_cat_x_book = uni_x_book,
                 voltgt = vt_exp, voltgt_x_book = vt_x_book),
            .extra_dt)
  res <- list()
  for (nm in names(scen)) {
    r <- weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway = cost_bps,
                            run_id = paste0("h2_", nm), strategy_id = paste0("h2_", nm), exposure_dt = scen[[nm]])
    avg_exp <- if (is.null(scen[[nm]])) 1.0 else mean(scen[[nm]]$exposure, na.rm = TRUE)
    res[[nm]] <- data.table(scenario = nm, abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
                            IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3, avg_exposure = avg_exp,
                            # ★basis 를 행에 박는다 — 나중에 이 수치를 인용할 때 어느 오버레이
                            #   기준선 위에서 잰 것인지 파일만 보고 알 수 있어야 한다(§7b).
                            book_basis = book_basis, carrier = basename(carrier_path), n_months = r$n_months)
  }
  tab <- rbindlist(res, fill = TRUE)

  # AX-001 v2: crisis-conditional eval — 신호가 CRISIS/CAUTION 라벨한 월에서 bare vs overlaid 손실 비교
  cr <- as.data.table(bare_gross)[as.data.table(uc$cat), on = "Date"]   # Date, r, regime_sig
  be <- if (is.null(book_exp)) data.table(Date = bare_gross$Date, book_e = 1.0) else book_exp[, .(Date, book_e = exposure)]
  cr[be, on = "Date", book_e := i.book_e]; cr[is.na(book_e), book_e := 1.0]
  cr[uni_exp, on = "Date", uni_e := i.exposure]; cr[is.na(uni_e), uni_e := 1.0]
  cr[, crisis := regime_sig %in% c("CRISIS", "CAUTION")]
  crisis_tab <- cr[, .(n = .N,
                       bare_mean = mean(r), book_mean = mean(r * book_e),
                       uni_mean = mean(r * uni_e), uni_x_book_mean = mean(r * book_e * uni_e)),
                   by = .(crisis)]

  list(tab = tab, crisis = crisis_tab, n_months = nrow(bench_dt),
       book_basis = book_basis, carrier = basename(carrier_path),
       # ★등재 수와 **실제 합류 수**를 따로 낸다 — 계약 미통과가 등재 수에 묻히면
       #   "논문이 소비됐다"가 거짓이 된다(등재≠처분 계통).
       n_extra_registered = length(extra_exposures),
       n_extra_joined = length(.extra_dt),
       extra_joined = names(.extra_dt),
       pit = list(label = "regime_ab/unified_cat",
                  max_used_cutoff = as.character(max(uc$pit$used_cutoff)),
                  min_gap_days = as.numeric(min(uc$pit$holding_start - uc$pit$used_cutoff))))
}

if ((sys.nframe() == 0L || identical(environment(), globalenv())) && Sys.getenv("QVEST_REGIME_AB_NORUN") != "1") {
  cat("\n##### H2 regime 오버레이 A/B — unified 앙상블(MSM+FRED+KTRI+VEA) + vol-target vs 현 book 오버레이 #####\n")
  out <- run_regime_overlay_ab()
  cat(sprintf("\n=== H2 시나리오 비교 (strategy 가중 고정, %d개월 vs KOSPI200) ===\n", out$n_months))
  print(out$tab)
  cat("\n=== AX-001 crisis-conditional (신호 CRISIS/CAUTION 라벨 월) 월평균수익 ===\n")
  print(out$crisis)
  fwrite(out$tab, "06_Registry/book_carrier/h2_regime_overlay_ab.csv")
  fwrite(out$crisis, "06_Registry/book_carrier/h2_regime_crisis_eval.csv")
  cat("\n주: book_L5=현 book 오버레이. uni_cat=앙상블 regime standalone. uni_cat_lag1=신호 1개월 추가지연(동월누출 판별).\n")
  cat("    *_x_book=book에 stacked(추가레버 검증). voltgt=변동성타겟. adopt 수동.\n")
  cat(sprintf("    basis: book_exposure=%s · carrier=%s · PIT 최소 간격 %.0f일\n",
              out$book_basis, out$carrier, out$pit$min_gap_days))
}
