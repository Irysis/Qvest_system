## ============================================================================
## ae_crisis_tripwire.R — 비지도 오토인코더(AE) regime 이상탐지 → crisis 조기경보 tripwire (배관)
##   R? (WT-D20260718_007 소비면, 2026-07-19). monitoring 배관 · 자본/배포 아님 · governor 무관.
##
## 목적: WT-D20260718_007 실측 = 비지도 AE 이상탐지가 급성 위기를 구조적으로 포착
##   (2008 GFC 9/9개월 방어 vs 현행 M4 BOCPD 6/9 · 지도학습 transformer 0/9 · 2022 AE 3 vs M4 0).
##   AE reconstruction error("정상" 시장 동역학 이탈도)를 monitoring crisis 조기경보 tripwire로 소비.
##   M4(BOCPD 국면 오버레이)를 *보완*하는 급성-OOD(out-of-distribution) 경보 — 자본/배포 신호 아님.
##
##   ★설계 원리(WT-004 근본원인 공격): 지도학습 transformer는 2008/COVID/2022 급락을 놓침
##     (OOD 급락은 in-sample analog 필요). AE는 "정상"만 학습해 이탈(고 recon error)을 flag —
##     급락이 학습에 없어도 이상으로 잡힘. 라벨 無 → OOD 문제 구조적 회피.
##
## 3-state 라벨 (M4 보완 관점):
##   • AE_ACUTE_ALERT  — AE 발화 ∧ M4 미발화 = "M4가 놓칠 급성 OOD"(2008 3건·2022 3건 실적)
##   • BOTH_CONFIRM    — AE 발화 ∧ M4 발화 = 강confirm (양자 합의 급락)
##   • M4_ONLY         — AE 미발화 ∧ M4 발화 = M4 소관 (완만/추세 de-risk)
##   • CALM            — 양자 미발화
##
## PIT: AE 이탈도 = walk-forward AE(≤t 데이터로만 학습, 미래 금지, self-check last_feat_date<decision_date=0)
##   산출. monitoring 단계는 lockbox 무관·최신 신선 신호 소비(.claude/rules/pit.md lockbox-scope).
##   AE·M4 동일 frozen 스냅샷(WT-D20260718_007_r1 pin, byte-identical book 측정) — apples-to-apples
##   vintage-pin(measurement-graduation §7). AE fire rate가 M4 fire rate 0.126에 IS-매칭(노출 중립).
##
## 상류(신선화 — 무거움, 온디맨드):
##   AE 신호 재산출 = python ae_regime_walkforward.py (walk-forward AE, torch, 11 market/macro feat).
##   본 writer는 최신 AE parquet을 *소비*(insider_safe_live_track이 filing_delay_watch를 소비하듯).
##   신규 월 필요 시 walk-forward 재실행 후 본 writer가 신규 발화 register + dedup.
##
## 규율: 단일스레드 · arrow io(2) · OneDrive temp-rename · book_state/05_Production/outputs.ramp
##   무변경(monitoring 배관만) · cov/weights 미산출(역할경계) · 자동조치 없음(도훈 재료) ·
##   임계값 사전 고정(sweep 금지) · idempotent(재실행 register 0·dedup). 텔레그램 = 신규 발화 시만
##   monitoring agent가 tg_agent_brief 발송(본 writer는 telegram_pending 플래그 + dedup 원장만 관리).
##
## 사용:
##   cd 02_Infrastructure/reports && Rscript -e 'source("ae_crisis_tripwire.R")'   # compute (기본)
##   AE_MARK_SENT=2026-05-01 Rscript -e 'source("ae_crisis_tripwire.R")'            # 발송 후 dedup 원장에 기록
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))
setDTthreads(1)
try(arrow::set_io_thread_count(2L), silent = TRUE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

ROOT     <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PIN_TAG  <- "WT-D20260718_007_r1"
PIN_DIR  <- file.path(ROOT, ".cache/pins", PIN_TAG)
AE_PARQ  <- file.path(ROOT, "stage_artifacts/WT_D20260718_007/ae_regime_signal.parquet")  # 상류 AE 신호(소비)
M4_CSV   <- file.path(PIN_DIR, "period_returns_layer5.csv")                                # M4 BOCPD(동일 pin)
OUT      <- file.path(ROOT, "qepm/observability/ae_crisis_tripwire_latest.json")
TL_CSV   <- file.path(ROOT, "qepm/observability/ae_crisis_tripwire_timeline.csv")           # 차트용 타임라인
OUT_DIR  <- dirname(OUT)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

BOOK <- "STR_1715_on_M4_R05_noLayer4_PG2"

## ── 사전 고정 파라미터 (sweep 금지 — 변경은 도훈 mandate) ─────────────────────
M4_FIRE_RULE      <- "m4_weight_lag < 1"   # M4 BOCPD de-risk 발화 (fire rate 0.1264, AE τ 매칭 기준)
## AE fire = fire_seq | fire_pt (두 detector 중 하나라도 recon-error > IS-calibrated τ).
##   τ = training-window recon error의 quantile(1 - 0.126) → M4 fire rate에 노출 중립 매칭.
## 급성도(acuity) = 발화 detector의 초과배율 max(ae/τ):
ACUITY_ELEVATED_HI <- 1.5   # (1.0, 1.5]  ELEVATED
ACUITY_ACUTE_HI    <- 2.5   # (1.5, 2.5]  ACUTE   / >2.5 EXTREME
## crisis 검증 창(KR 급락월) — 보고용 고정 라벨
CRISIS_WINDOWS <- list(
  list("2008_GFC",  "2008-08-01", "2009-04-30"),
  list("2011_Euro", "2011-08-01", "2011-10-31"),
  list("2018_sell", "2018-10-01", "2018-12-31"),
  list("COVID",     "2020-02-01", "2020-04-30"),
  list("2022_bear", "2022-01-01", "2022-10-31"))

ymi <- function(d) { d <- as.Date(d); as.integer(format(d, "%Y")) * 100L + as.integer(format(d, "%m")) }

## ── 1. 상류 AE 신호 로드 ─────────────────────────────────────────────────────
if (!file.exists(AE_PARQ))
  stop(sprintf("ae_crisis_tripwire: AE 신호 부재 (%s) — ae_regime_walkforward.py 먼저 실행", AE_PARQ))
ae <- as.data.table(read_parquet(AE_PARQ))
ae[, decision_date := as.Date(decision_date)]
ae[, last_feat_date := as.Date(last_feat_date)]
ae[, ym := ymi(decision_date)]
## AE fire = 두 detector union (급성 tripwire 민감도). 초과배율 = 발화 detector 중 max(ae/τ).
ae[, ae_fire := as.integer(fire_seq == 1L | fire_pt == 1L)]
ae[, exceed_seq := ae_seq / tau_seq]
ae[, exceed_pt  := ae_pt  / tau_pt]
ae[, exceed_max := pmax(fifelse(fire_seq == 1L, exceed_seq, -Inf),
                        fifelse(fire_pt  == 1L, exceed_pt,  -Inf))]
ae[!is.finite(exceed_max), exceed_max := pmax(exceed_seq, exceed_pt)]  # 미발화월도 근접도 기록
ae[, dual_detector := as.integer(fire_seq == 1L & fire_pt == 1L)]

## PIT self-check (미래참조 0 확인 — AE 계약 재검증)
pit_bad <- sum(ae$last_feat_date >= ae$decision_date, na.rm = TRUE)

## ── 2. M4 BOCPD 신호 로드 (동일 pin — apples-to-apples) ──────────────────────
if (!file.exists(M4_CSV))
  stop(sprintf("ae_crisis_tripwire: M4 layer5 부재 (%s)", M4_CSV))
l5 <- fread(M4_CSV)
l5[, rym := as.integer(gsub("-", "", realized_ym))]
l5[, m4_fire := as.integer(m4_weight_lag < 1)]
m4 <- l5[, .(rym, regime, m4_weight_lag, m4_fire)]

## ── 3. join (year-month) + 3-state ───────────────────────────────────────────
d <- merge(ae, m4, by.x = "ym", by.y = "rym", all.x = TRUE)
d <- d[order(decision_date)]
d[, state := fifelse(ae_fire == 1L & m4_fire == 1L, "BOTH_CONFIRM",
              fifelse(ae_fire == 1L & (m4_fire == 0L | is.na(m4_fire)), "AE_ACUTE_ALERT",
              fifelse(ae_fire == 0L & m4_fire == 1L, "M4_ONLY", "CALM")))]
d[, acuity := fifelse(ae_fire == 0L, "NONE",
               fifelse(exceed_max <= ACUITY_ELEVATED_HI, "ELEVATED",
               fifelse(exceed_max <= ACUITY_ACUTE_HI, "ACUTE", "EXTREME")))]

## consecutive AE fire (latest 로부터 연속 발화월 수)
rf <- rev(d$ae_fire)
consec <- 0L; for (v in rf) { if (isTRUE(v == 1L)) consec <- consec + 1L else break }

## ── 4. 기존 트랙 로드 (idempotent register + dedup 원장) ─────────────────────
if (file.exists(OUT)) {
  TRK <- fromJSON(OUT, simplifyVector = FALSE)
  firings    <- if (is.null(TRK$firings)) list() else TRK$firings
  sent_for   <- if (is.null(TRK$alert_dedup$telegram_sent_for)) character(0)
                else unlist(TRK$alert_dedup$telegram_sent_for)
  created_at <- TRK$created_at %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
} else {
  firings <- list(); sent_for <- character(0)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
}
existing_dates <- vapply(firings, function(f) as.character(f$decision_date), character(1))
now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

## ── 4a. AE_MARK_SENT 모드 (발송 후 dedup 원장 기록 — idempotent) ─────────────
mark_sent <- Sys.getenv("AE_MARK_SENT", "")
if (nzchar(mark_sent)) {
  sent_for <- unique(c(sent_for, mark_sent))
}

## ── 5. 신규 발화 register (ae_fire==1 월만, dedup) ───────────────────────────
n_new <- 0L; new_dates <- character(0)
fire_rows <- d[ae_fire == 1L]
for (i in seq_len(nrow(fire_rows))) {
  r <- fire_rows[i]
  dd <- as.character(r$decision_date)
  if (dd %in% existing_dates) next
  firings[[length(firings) + 1L]] <- list(
    decision_date = dd,
    holding_ym    = r$ym,
    state         = r$state,
    acuity        = r$acuity,
    dual_detector = as.logical(r$dual_detector),
    ae_seq = round(r$ae_seq, 4), tau_seq = round(r$tau_seq, 4), fire_seq = as.integer(r$fire_seq),
    ae_pt  = round(r$ae_pt , 4), tau_pt  = round(r$tau_pt , 4), fire_pt  = as.integer(r$fire_pt),
    exceed_max = round(r$exceed_max, 3),
    m4_weight_lag = round(r$m4_weight_lag %||% NA_real_, 4),
    m4_fire = if (is.na(r$m4_fire)) NA else as.integer(r$m4_fire),
    regime_label = r$regime %||% NA_character_,
    registered_at = now_iso)
  n_new <- n_new + 1L; new_dates <- c(new_dates, dd)
}

## ── 6. latest state 판정 ─────────────────────────────────────────────────────
lr <- d[.N]
latest <- list(
  decision_date = as.character(lr$decision_date),
  holding_ym    = lr$ym,
  model_year    = lr$model_year,
  ae_seq = round(lr$ae_seq, 4), tau_seq = round(lr$tau_seq, 4), fire_seq = as.integer(lr$fire_seq),
  ae_pt  = round(lr$ae_pt , 4), tau_pt  = round(lr$tau_pt , 4), fire_pt  = as.integer(lr$fire_pt),
  exceed_seq = round(lr$exceed_seq, 3), exceed_pt = round(lr$exceed_pt, 3),
  exceed_max = round(lr$exceed_max, 3),
  ae_fire = as.integer(lr$ae_fire), dual_detector = as.logical(lr$dual_detector),
  m4_weight_lag = round(lr$m4_weight_lag %||% NA_real_, 4),
  m4_fire = if (is.na(lr$m4_fire)) NA else as.integer(lr$m4_fire),
  regime_label = lr$regime %||% NA_character_,
  state = lr$state, acuity = lr$acuity,
  last_feat_date = as.character(lr$last_feat_date),
  consecutive_ae_fire_months = consec,
  interpretation = switch(lr$state,
    AE_ACUTE_ALERT = "AE 급성 이상 발화 ∧ M4 미발화 = M4가 놓칠 급성 OOD 경보 (2008 GFC·2022 실적). 도훈 재료 — 자동조치 없음",
    BOTH_CONFIRM   = "AE ∧ M4 동시 발화 = 강confirm (양자 합의 급락). 도훈 재료 — 자동조치 없음",
    M4_ONLY        = "M4 단독 발화 = M4 소관 (완만/추세 de-risk). AE 이상 미감지",
    CALM           = "양자 미발화 = 정상 국면"))

## telegram_pending: 최신월이 AE 발화 ∧ 아직 미발송
latest_pending <- (lr$ae_fire == 1L) && !(as.character(lr$decision_date) %in% sent_for)

## ── 7. 최근 12개월 상태 시퀀스 (요약) ────────────────────────────────────────
last12 <- tail(d, 12)
state_seq <- lapply(seq_len(nrow(last12)), function(i) list(
  decision_date = as.character(last12$decision_date[i]),
  state = last12$state[i], acuity = last12$acuity[i],
  exceed_max = round(last12$exceed_max[i], 2),
  m4_fire = if (is.na(last12$m4_fire[i])) NA else as.integer(last12$m4_fire[i])))

## ── 8. 역사 검증 (전 매칭 기간 + crisis 창) ──────────────────────────────────
dm <- d[!is.na(m4_fire)]
state_counts <- as.list(table(factor(dm$state, levels = c("CALM","AE_ACUTE_ALERT","BOTH_CONFIRM","M4_ONLY"))))
state_counts <- lapply(state_counts, as.integer)
crisis_val <- list()
for (cw in CRISIS_WINDOWS) {
  s <- dm[decision_date >= as.Date(cw[[2]]) & decision_date <= as.Date(cw[[3]])]
  if (nrow(s) == 0L) next
  crisis_val[[cw[[1]]]] <- list(
    n_months = nrow(s),
    ae_fire = sum(s$ae_fire), m4_fire = sum(s$m4_fire),
    ae_acute_alert = sum(s$state == "AE_ACUTE_ALERT"),
    both_confirm = sum(s$state == "BOTH_CONFIRM"),
    m4_only = sum(s$state == "M4_ONLY"))
}

## ── 9. 차트용 타임라인 CSV (exceedance + M4 fire) ────────────────────────────
tl <- d[, .(decision_date, exceed_seq = round(exceed_seq, 4), exceed_pt = round(exceed_pt, 4),
            fire_seq, fire_pt, ae_fire, m4_fire, state, acuity, regime)]
fwrite(tl, TL_CSV)

## ── 10. JSON 저장 (OneDrive temp-rename) ─────────────────────────────────────
n_firings_total <- length(firings)
n_ae_acute <- sum(vapply(firings, function(f) identical(f$state, "AE_ACUTE_ALERT"), logical(1)))
n_both     <- sum(vapply(firings, function(f) identical(f$state, "BOTH_CONFIRM"), logical(1)))
out <- list(
  schema  = "ae_crisis_tripwire_v1",
  purpose = paste0("비지도 AE regime 이상탐지 → crisis 조기경보 tripwire. M4(BOCPD)를 *보완*하는 급성-OOD ",
                   "경보(2008 GFC 9/9 vs M4 6/9 실측). monitoring 배관 · 자본/배포 아님 · governor 무관 · 자동조치 없음(도훈 재료)."),
  book = BOOK,
  metric_type = "regime_anomaly_monitoring",
  created_at = created_at, updated_at = now_iso, as_of = format(Sys.Date()),
  upstream = list(
    ae_signal  = "stage_artifacts/WT_D20260718_007/ae_regime_signal.parquet (walk-forward AE recon-error, 소비)",
    ae_refresh = "python ae_regime_walkforward.py (walk-forward AE·torch·11 market/macro feat) — 무거움·온디맨드. 본 writer는 최신 parquet 소비",
    m4_signal  = "period_returns_layer5.csv m4_weight_lag<1 = M4 BOCPD de-risk 발화 (fire rate 0.1264)",
    vintage_pin = paste0(PIN_TAG, " — AE·M4 동일 frozen book 스냅샷(byte-identical, apples-to-apples, §7 vintage-pin)")),
  rules = list(
    ae_fire = "fire_seq | fire_pt (recon-error > IS-calibrated τ = quantile(1-0.126), M4 fire rate 노출 중립 매칭). 사전 고정·sweep 금지",
    m4_fire = M4_FIRE_RULE,
    state   = paste0("AE_ACUTE_ALERT(AE∧¬M4=M4가 놓칠 급성 OOD) / BOTH_CONFIRM(AE∧M4=강confirm) / ",
                     "M4_ONLY(¬AE∧M4=M4 소관) / CALM. 자동조치 없음·자본 아님"),
    acuity  = sprintf("발화 detector max(ae/τ): ELEVATED (1,%.1f] / ACUTE (%.1f,%.1f] / EXTREME >%.1f · dual_detector=seq∧pt. 사전 고정",
                      ACUITY_ELEVATED_HI, ACUITY_ELEVATED_HI, ACUITY_ACUTE_HI, ACUITY_ACUTE_HI)),
  pit_self_check = list(
    ae_last_feat_before_decision = pit_bad,
    ok = (pit_bad == 0L),
    note = "AE walk-forward last_feat_date < decision_date (미래참조 0). monitoring은 lockbox 무관·최신 신선 소비"),
  latest = latest,
  latest_state_seq_12m = state_seq,
  historical_validation = list(
    n_months_matched = nrow(dm),
    date_range = c(as.character(min(dm$decision_date)), as.character(max(dm$decision_date))),
    ae_fire_rate = round(mean(dm$ae_fire), 4),
    m4_fire_rate = round(mean(dm$m4_fire), 4),
    state_counts = state_counts,
    crisis_windows = crisis_val,
    headline = "2008 GFC: AE 9/9 방어(M4 6/9·transformer 0/9) — AE_ACUTE_ALERT 3건이 M4 미포착 급성월. 2022 bear: AE 3 vs M4 0(전량 AE_ACUTE_ALERT)."),
  alert_dedup = list(
    telegram_pending = latest_pending,
    pending_decision_date = if (latest_pending) as.character(lr$decision_date) else NA_character_,
    telegram_sent_for = as.list(sent_for),
    dedup_rule = "신규 발화(최신월 ae_fire==1 ∧ decision_date ∉ telegram_sent_for)에만 텔레그램. AE_MARK_SENT env로 발송 후 원장 기록. spam 방지"),
  run_summary = list(
    n_firings_total = n_firings_total,
    n_ae_acute_alert_total = n_ae_acute,
    n_both_confirm_total = n_both,
    n_new_this_run = n_new,
    new_firing_dates = as.list(new_dates),
    marked_sent_this_run = if (nzchar(mark_sent)) mark_sent else NA_character_),
  firings = firings,
  timeline_csv = "qepm/observability/ae_crisis_tripwire_timeline.csv",
  provenance = list(
    parent = "WT-D20260718_007 (비지도 AE regime detector-swap vs M4 BOCPD)",
    writer = "02_Infrastructure/reports/ae_crisis_tripwire.R",
    discipline = paste0("monitoring 배관 · 자본/배포 아님 · governor 무관 · 자동조치 없음(도훈 재료) · ",
                        "book_state/05_Production/outputs.ramp 무변경 · cov/weights 미산출 · 임계 사전 고정(sweep 금지) · idempotent")))

tmp <- paste0(OUT, ".tmp_", Sys.getpid())
write_json(out, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
if (file.exists(OUT)) file.remove(OUT)
invisible(file.rename(tmp, OUT))

## ── 11. 콘솔 요약 ────────────────────────────────────────────────────────────
cat(sprintf("\n[ae_crisis_tripwire] 비지도 AE crisis 조기경보 tripwire — %s (배관·자본 아님)\n", format(Sys.Date())))
cat(sprintf("   상류 AE: %d월(%s..%s) · PIT self-check(미래참조)=%d [%s]\n",
            nrow(ae), as.character(min(ae$decision_date)), as.character(max(ae$decision_date)),
            pit_bad, ifelse(pit_bad == 0L, "OK", "FAIL")))
cat(sprintf("   역사 3-state(%d월): CALM %s · AE_ACUTE_ALERT %s · BOTH_CONFIRM %s · M4_ONLY %s\n",
            nrow(dm), state_counts[["CALM"]], state_counts[["AE_ACUTE_ALERT"]],
            state_counts[["BOTH_CONFIRM"]], state_counts[["M4_ONLY"]]))
cv08 <- crisis_val[["2008_GFC"]]
if (!is.null(cv08)) cat(sprintf("   2008 GFC 검증: AE %d/%d · M4 %d/%d · AE_ACUTE_ALERT %d\n",
            cv08$ae_fire, cv08$n_months, cv08$m4_fire, cv08$n_months, cv08$ae_acute_alert))
cat(sprintf("   ▶ 현재 상태(%s): %s / %s · exceed=%.2f× · dual=%s · consec=%d월\n",
            latest$decision_date, latest$state, latest$acuity, latest$exceed_max,
            latest$dual_detector, latest$consecutive_ae_fire_months))
cat(sprintf("   register: 신규 %d(%s) · 총 %d발화(AE_ACUTE %d·BOTH %d)\n",
            n_new, ifelse(length(new_dates), paste(new_dates, collapse=","), "-"),
            n_firings_total, n_ae_acute, n_both))
cat(sprintf("   텔레그램: pending=%s%s\n", latest_pending,
            if (nzchar(mark_sent)) sprintf(" (marked_sent=%s)", mark_sent) else ""))
cat(sprintf("[ae_crisis_tripwire] → %s\n", OUT))
