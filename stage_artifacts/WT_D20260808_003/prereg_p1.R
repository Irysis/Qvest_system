# =============================================================================
# prereg_p1.R — WT-D20260808_003 사전등록 (판정량 미열람 시점 고정)
#
#   P0 결과: (i) paired 형태 2종 모두 필요 >> 함의 → 착수 전 폐기(handoff 제1 조건)
#            (ii) F1 사전 실측 — 중립화가 β 갭을 부분만 닫음(−0.245 → −0.153 분위 /
#                 −0.269 → −0.209 top-25) → 사전등록 B3 조건(|갭| > 0.15 잔존) 충족
#   따라서 본 라운드는 (a) B3 격리 하에서 진행하고 (b) 판정 형태를 월-횡단면으로 전환한다.
#
#   ★ 본 스크립트는 판정량(중립 z 의 수익 기울기·분위 스프레드)을 계산·인쇄하지 않는다.
#      검정력 입력은 **월내 z 무작위 순열 placebo**(신호-맹목)에서만 얻는다.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/prereg_p1.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[prereg] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/required_effect_size.R")

P0 <- readRDS(file.path(OUT, "p0_panels.rds"))
p0j <- fromJSON(file.path(OUT, "precheck_p0.json"))
N <- P0$N; E <- P0$E; returns_dt <- P0$returns_dt; bench_dt <- P0$bench_dt
say("입력 재확인: N nrow=%d n_month=%d · E nrow=%d · returns nrow=%d MONTHLY",
    nrow(N), uniqueN(N$Date), nrow(E), nrow(returns_dt))

ACT <- merge(returns_dt, bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]
D <- merge(N[, .(Date, Ticker, q01, q01_n)], ACT, by = c("Date","Ticker"))
D <- D[is.finite(act) & is.finite(q01)]
say("판정 패널: %d행 %d개월 월평균 %.1f종목 (act = Ret_1m − BM_Ret)",
    nrow(D), uniqueN(D$Date), D[, .N, by = Date][, mean(N)])

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

# ── placebo 널 sd (신호-맹목: 월내 z 무작위 순열) ────────────────────────────
say("=== placebo 널 sd — 월내 무작위 순열 (판정량 미열람) ===")
null_sd <- function(dt, form = c("slope","q5q1","topq","top25"), n_seed = 20L) {
  form <- match.arg(form); sds <- numeric(n_seed)
  for (s in seq_len(n_seed)) {
    set.seed(2000L + s)
    v <- dt[, {
      zp <- sample(.N)                        # 월내 순열 = 널
      zz <- (zp - mean(zp))/sd(zp)
      switch(form,
        slope = .(v = unname(coef(lm(act ~ zz))[2])),
        q5q1  = { qr <- frank(zz)/.N; .(v = mean(act[qr > 0.8]) - mean(act[qr <= 0.2])) },
        topq  = { qr <- frank(zz)/.N; .(v = mean(act[qr > 0.8])) },
        top25 = { o <- order(-zz); .(v = mean(act[o[seq_len(min(25L, .N))]])) })
    }, by = Date]
    sds[s] <- sd(v$v, na.rm = TRUE)
  }
  list(sd_monthly = median(sds), sd_range = range(sds), n_seed = n_seed)
}
forms <- c("slope","q5q1","topq","top25")
nulls <- setNames(lapply(forms, function(f) null_sd(D, f)), forms)
n_m <- uniqueN(D$Date)
req <- lapply(nulls, function(x) required_effect(n = n_m, sd_monthly = x$sd_monthly, design = "full"))
for (f in forms) say("  %-6s 널 sd=%.5f (범위 %.5f~%.5f) → 필요 연 %+.2f%% (t=2.0, n=%d)",
                     f, nulls[[f]]$sd_monthly, nulls[[f]]$sd_range[1], nulls[[f]]$sd_range[2],
                     100*req[[f]]$required_annual, n_m)
# paired(중립−raw) 형태의 널 sd: 두 순열 신호의 차 — 상관 구조 반영
paired_null <- function(dt, form, n_seed = 20L) {
  sds <- numeric(n_seed)
  for (s in seq_len(n_seed)) {
    set.seed(3000L + s)
    v <- dt[, { zp1 <- sample(.N); zp2 <- sample(.N)
      z1 <- (zp1-mean(zp1))/sd(zp1); z2 <- (zp2-mean(zp2))/sd(zp2)
      f1 <- switch(form, slope = unname(coef(lm(act ~ z1))[2]),
                   q5q1 = { qr <- frank(z1)/.N; mean(act[qr>0.8]) - mean(act[qr<=0.2]) },
                   topq = { qr <- frank(z1)/.N; mean(act[qr>0.8]) })
      f2 <- switch(form, slope = unname(coef(lm(act ~ z2))[2]),
                   q5q1 = { qr <- frank(z2)/.N; mean(act[qr>0.8]) - mean(act[qr<=0.2]) },
                   topq = { qr <- frank(z2)/.N; mean(act[qr>0.8]) })
      .(v = f1 - f2) }, by = Date]
    sds[s] <- sd(v$v, na.rm = TRUE)
  }
  list(sd_monthly = median(sds), sd_range = range(sds))
}
pn <- setNames(lapply(c("slope","q5q1","topq"), function(f) paired_null(D, f)), c("slope","q5q1","topq"))
reqp <- lapply(pn, function(x) required_effect(n = n_m, sd_monthly = x$sd_monthly, design = "full"))
for (f in names(pn)) say("  paired(%s) 널 sd=%.5f → 필요 연 %+.2f%%",
                         f, pn[[f]]$sd_monthly, 100*reqp[[f]]$required_annual)

# ── 사전등록 문서 ────────────────────────────────────────────────────────────
PRE <- list(
  task_id = "WT-D20260808_003", fq_ref = "FQ-122 NP-1", locked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  inherits = "alpha_hypothesis.json (재작성 금지 — mechanism/falsification/regime_scope 승계)",
  p0_outcome = list(
    paired_forms_abandoned = TRUE,
    reason = "필요 효과 >> drag 함의: 바스켓형 필요 연 4.00% vs 함의 0.69% (비 0.17) · 필터형 필요 2.81% vs 함의 0.12% (비 0.04). 부모 라운드 INCONCLUSIVE_UNDERPOWERED 재발을 착수 전 회피(handoff 제1 조건 이행)",
    bench_drift_measured_ann_pct = p0j$bench_drift$full$ann_pct,
    F1_precheck = list(
      raw_quintile_gap = p0j$F1_precheck$raw$diff_quintile, raw_t = p0j$F1_precheck$raw$t_quintile,
      neutral_quintile_gap = p0j$F1_precheck$neutral$diff_quintile, neutral_t = p0j$F1_precheck$neutral$t_quintile,
      neutral_top25_gap = p0j$F1_precheck$neutral$diff_top25,
      verdict = "B3_FIRED — 사전등록 조건 '중립화 후 β 갭 < −0.15 잔존' 충족(분위 −0.153 · top-25 −0.209, 둘 다 NW t 유의). 섹터+사이즈는 β 채널을 span 하지 못한다",
      consequence = "전이 결과의 채널 귀속 주장 금지(사전등록 B3 처분). C3(β-직접 잔차화)는 본 라운드 arm 으로 추가하지 않는다(사전등록 밖 arm 금지) — 재설계 후보로만 승격 기록")),
  design_switch = list(
    from = "paired 포트폴리오 arm (top-25 바스켓 / 제외필터)",
    to = "월-횡단면 회귀 + 분위 조건부 평균 (전표본, FQ-068 R2 검정력 선례)",
    judgment_quantity = "FMB 월별 횡단면 기울기 (act ~ z_std) 의 시계열 평균 + NW lag-3 t · 및 중립−raw paired 기울기 차",
    canonical_role = "canonical_screen_bt 는 schema 필수 필드(canonical_port_t_nw_lag3) 기록 + Δmean/ΔSE 분해용으로 1회 실행하되, 본 라운드 판정 권위 아님(P0 에서 저검정력 확정). CI·검정력 라벨 병기 의무"),
  power = list(n_months = n_m,
    null_sd_monthly = lapply(nulls, function(x) x$sd_monthly),
    required_annual_pct = lapply(req, function(r) 100*r$required_annual),
    paired_null_sd_monthly = lapply(pn, function(x) x$sd_monthly),
    paired_required_annual_pct = lapply(reqp, function(r) 100*r$required_annual),
    rule = "판정 후 verdict_with_power() 로 INCONCLUSIVE_UNDERPOWERED vs NEGATIVE_POWERED 구별. 두 라벨을 같은 문장에 병기 금지"),
  arms = list(
    A1 = "raw Q01 — FMB 기울기 / 분위 조건부 act / rank-IC / monotonicity",
    A2 = "중립 Q01(섹터+log시총 잔차) — 동일 배터리",
    A3 = "A2 + F2 통제(MAX5 원변수 + vol63=D03_EWMA) 를 회귀에 추가 — 증분 잔존",
    A4 = "A2 + trailing β 통제 — β 채널 잔여분 진단(B3 격리 하 advisory)"),
  falsification_tests = list(
    F1 = "완료(P0) — 부분 소거. 판정: 사전등록 조건 미달 = B3",
    F2 = "MAX5 원변수 + vol63 통제 후 중립 Q01 증분 잔존. 사전 문턱: 통제 전 대비 기울기 잔존율 >= 0.30 (RF-A4 준용, 자의성 인정 — challenge_note_hypothesis §2 ACCEPT 반영해 여기서 고정)",
    F3 = "개인 순매수(시총 정규화) ~ 중립 z + log(Size) 월별 FMB. raw z 대비 부착 강도 비교. 동시기 관측 라벨 유지",
    F4 = "중립 z 5분위 평균 act + rank-IC + Harvey-t 병기. 'Harvey-t>=3 ∧ monotonicity<0.5' 지속 여부(B2 예고 관측)"),
  discrimination_3 = list(
    d1 = "수익-단위 분위 스프레드(Q5−Q1) raw vs 중립 — 평균·중앙값 병기(왜도 방어). 정보 증가 ⇒ 스프레드 확대 / 노이즈 축소 ⇒ 스프레드 불변·t 만 상승",
    d2 = "ΔPORT_t 의 Δmean vs ΔSE 분해 (canonical arm 2종)",
    d3 = "F3 주체 시그니처 부착"),
  branch_map = list(
    B1 = "전이 성립 — 단 B3 발화로 채널 귀속 주장 불가. 성립 시에도 '중립화가 수익-단위 정보를 늘렸다' 까지만",
    B2 = "IC-only — 기울기·스프레드 무변인데 rank-IC 만 상승 ⇒ 노이즈 축소 재분류 + 재료-불변 벽의 채널-축 확장(1급 정보, 실패 아님)",
    B3 = "★발화(P0) — 설계 전제 실패 격리",
    B4 = "시기 편중 — 연속 시간추세 상호작용(분할 금지). post-2015 회복 없으면 FQ-122 부활 조건 미충족",
    B5 = "필터면 — P0 에서 paired 폐기. 기술 기록만(CI), 판정 아님"),
  prohibitions = c("국면 분할 금지 — 연속 상호작용만, advisory·CI 보고",
                   "사전등록 밖 arm 추가 금지(C3 포함)",
                   "proxy 손계산·자체합성 금지 — canonical_screen_bt / build_monthly_forward_returns 계약 경유",
                   "자본 자격 주장 금지 · 제약 완화 제안 금지(INV-7)"))
write_json(PRE, file.path(OUT, "preregistration.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(list(D = D, nulls = nulls, paired_nulls = pn), file.path(OUT, "prereg_p1.rds"))
say("=== 사전등록 고정 → preregistration.json ===")
