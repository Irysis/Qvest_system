## WT-D20260822_010 — risk_package 발행 (진단 모드, optimizer 전이 없음)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[emit] ", f, "\n"), ...))
TID <- "WT-D20260822_010"; SIGD <- as.Date("2026-03-31")

G  <- readRDS(file.path(OUT, "30_risk_gate_objects.rds"))
GJ <- fromJSON(file.path(OUT, "30_risk_gate.json"))
MJ <- fromJSON(file.path(OUT, "31_risk_measure.json"))
CJ <- fromJSON(file.path(OUT, "32_risk_controls.json"))
P <- as.data.table(G$P); BK <- as.data.table(G$BK); tilt <- as.data.table(G$tilt)

## ── 1. crowding_score_per_factor (Phase 2.C 의무, Acadian 2026) ─────────────
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
CS <- NULL
crowd_status <- "unavailable"
try({
  RD <- as.data.table(open_dataset(file.path(ROOT, ".cache/RAWDATA.parquet")) |>
    dplyr::filter(Date >= as.Date("2026-01-01")) |> dplyr::collect())
  cur <- P[Date == max(P$Date)]
  FE <- rbindlist(list(
    data.table(Ticker = cur$Ticker, factor_name = "WT010_base_score",   exposure = cur$sc),
    data.table(Ticker = cur$Ticker, factor_name = "WT010_absorb_orth_tail", exposure = -cur$score_orth)))
  CS <- crowding_score_per_factor(FE, sig_date = max(P$Date), RAWDATA = RD, top_n = 25L)
  crowd_status <- "computed"
}, silent = FALSE)
if (!is.null(CS)) { say("crowding 산출:"); print(CS) } else say("crowding 산출 실패 → unavailable")

## ── 2. cap_tier_decomposition (v8.3.1 의무) ────────────────────────────────
BKs <- merge(BK, P[, .(Date, Ticker, Size, score_orth, excluded_p = excluded)], by = c("Date","Ticker"))
BKs[, szr := frank(Size) / .N, by = Date]
BKs[, tier := fifelse(szr >= 2/3, "MEGA", fifelse(szr >= 1/3, "MID", "SMALL"))]
CT <- BKs[, .(active_risk_share = sum(w) / BKs[Date == .BY$Date, sum(w)]), by = .(Date, tier)]
CTm <- BKs[, .(w = sum(w), n = .N), by = .(Date, tier)][, .(share = mean(w / sum(w) * 3), n = sum(n)), by = tier]
tier_w <- BKs[, .(w = sum(w)), by = .(Date, tier)][, tot := sum(w), by = Date][, .(share = mean(w / tot)), by = tier]
tier_lo <- BKs[, .(lo_w = sum(w[excluded_p]), w = sum(w)), by = .(Date, tier)][, .(lo_share_within_tier = sum(lo_w)/sum(w)), by = tier]
CTD <- merge(tier_w, tier_lo, by = "tier")
say("cap_tier: %s", paste(sprintf("%s w=%.3f lo내부비중=%.3f", CTD$tier, CTD$share, CTD$lo_share_within_tier), collapse = " | "))

## ── 3. method shopping log (R2-C, 상한 5) ──────────────────────────────────
msl <- list(candidates_tried = 4L, method_log = list(
  list(name = "rolling60m_full_window_normal", note = "v1 — frollmean 완전창 요구로 최소24 의도 무효(hist_n 전부 60), 패널 54%/208월 절단 + 정규근사 수준 2배 과대", selected = FALSE),
  list(name = "adaptive_rolling_min18_empirical_calib", note = "v2 — adaptive 창 + PIT 확장창 표준화잔차 경험분포. 커버리지 83.8%, 250월", selected = TRUE),
  list(name = "constant_vol", note = "위반 주입(판별력 0) — 흡수 0.0% 확인용", selected = FALSE),
  list(name = "winvol_daily_scaled", note = "alpha 층 통제축을 스케일로 사용 — 흡수 93.7%", selected = FALSE)),
  parallel_exec = FALSE, n_workers = 1L)

## ── 4. risk_package 조립 ───────────────────────────────────────────────────
gate_tbl <- CJ$final_gate_table
pkg <- list(
  task_id = TID, as_of_date = as.character(SIGD),
  agent = "risk-research", spec_version = "risk_init_v1.2",
  status = "GATE_STOP__DIAGNOSTIC_ONLY__NO_OPTIMIZER_TRANSITION",
  round_question = "absorb 직교화 tail 축이 위험모델(tail/stress · crowding · Sigma)을 개선하는가",
  prereg_ref = "stage_artifacts/WT-D20260822_010/30_risk_PREREG.json",
  selection_objective = "stress_robust",
  selection_objective_note = "R4 P3 준수 — 추정품질 지표(꼬리 캘리브레이션)로만 기저 모델 선택. alpha return/SR/IR 미참조.",

  exposure_matrix_ref = NULL, factor_covariance_ref = NULL,
  specific_risk_ref = NULL, security_covariance_ref = NULL,
  refs_null_reason = "착수 전 크기 관문 5/5 미달 → 처치 위험모델(M1)을 추정하지 않았고 optimizer 전이도 없다. 소비처 없는 Sigma 를 생산하는 것은 계산 낭비이자 '측정했다'는 오해를 만든다. 산출은 추정품질 진단에 한정.",

  gate = list(
    rule = "ratio = 기전-함의 개선폭 / MDE80; ratio < 0.10 이면 측정 중단",
    table = gate_tbl,
    verdict = "5/5 미달 — 착수 자격 없음",
    note = "R3 는 사전 순열 산술로는 0.672(통과)였으나 순열 귀무가 **추정기 자체의 추정오차**를 담지 않아 MDE 를 10.3배 과소평가했다. 실현 잡음으로 정정하면 0.065. 자가적발·기록."),

  risk_summary = list(
    top_common_risks = "not_estimated__gate_stop",
    crowding_flags = if (!is.null(CS)) as.list(CS$factor_name[which(CS$crowding_score >= 0.75)]) else list(),
    crowding_score_per_factor = if (!is.null(CS)) lapply(seq_len(nrow(CS)), function(i) as.list(CS[i])) else
      list(list(factor_name = "unavailable", crowding_score = NA, reason = "RAWDATA 스냅샷 로드 실패")),
    crowding_status = crowd_status,
    liquidity_flags = list(),
    stress_tests = "not_estimated__gate_stop",
    cap_tier_decomposition = list(
      basis = "book_weight_shares__base_top25_capw",
      tiers = lapply(seq_len(nrow(CTD)), function(i) list(
        tier = CTD$tier[i], book_weight_share = CTD$share[i],
        low_orth_share_within_tier = CTD$lo_share_within_tier[i])),
      dual_basis_divergence_flag = NA,
      note = "본 라운드는 신규 알파를 배치하지 않으므로 alpha_share/active_risk_share 는 산출 대상이 아니다. 축(score_orth) 노출이 cap-tier 에 어떻게 놓이는지만 기록.")),

  findings = list(
    Q1_tail_layer = list(
      verdict = "효과없음(powered null) — 개선 여지가 vol 스케일에 이미 흡수됨",
      absorbed_share_by_vol_scaling = MJ$R1_gate_recomputed$absorbed_share_by_vol_scaling,
      surviving_share = MJ$R1_gate_recomputed$surviving_share,
      realized_ratio_lo_hi = MJ$R1_gate_recomputed$realized$ratio_lo_hi,
      model_ratio_lo_hi = MJ$R1_gate_recomputed$model_M0$ratio_lo_hi,
      threshold_robustness = lapply(CJ$threshold_robustness, function(x)
        list(threshold = x$threshold, absorbed_share = x$absorbed_share)),
      detection_power_proof = list(
        const_vol_absorbed = CJ$injection_and_controls$CONST_none$absorbed_share,
        shuffled_vol_absorbed = CJ$injection_and_controls$SHUFFLED_sd0$absorbed_share,
        reading = "판별력 제거 base 두 종에서 흡수가 0.0%/1.6% 로 붕괴 — 계산기가 기계적으로 높은 값을 내는 게 아님(위반 주입 통과)."),
      metric_type = "estimation_quality"),
    Q2_crowding_layer = list(
      verdict = "미결(underpowered) — 측정하지 않음",
      gate_ratio = gate_tbl$R2$ratio,
      reading = MJ$R2_gate$reading,
      book_tilt_sd = MJ$R2_gate$book_tilt$sd,
      metric_type = "estimation_quality"),
    Q3_sigma_layer = list(
      verdict_common_risk = "미측정 — 별도 관문 필요(next_probe NP2)",
      verdict_specific_risk = "미결(underpowered) — R3 양성대조 미발화",
      R3_qlike_improvement = MJ$R3$mean_improvement, R3_nw_t = MJ$R3$nw_t, R3_mde80 = MJ$R3$mde80,
      PC2_positive_control_fired = MJ$PC2_positive_control$fired,
      PC2_nw_t = MJ$PC2_positive_control$nw_t,
      structural_reading = "축이 실려 있는 곳은 **분산이 아니라 분산의 U자 형태**다. score_orth 분위별 장기변동성 sd0 = Q1 0.1382 / Q2 0.1192 / Q3 0.1168 / Q4 0.1202 / Q5 0.1279 — 양끝이 높고 중간이 낮다. 전 구간 선형상관은 -0.042(사실상 0)인데 **하위 20% 절단**은 잔차의 이 비선형 구조를 상속해 sd0 이 1.154배 높다.",
      metric_type = "estimation_quality")),

  challenge_flags = list(
    list(id = "RF-RX1", severity = "HIGH", to_agent = "alpha",
         claim = "선행 전제 '직교화로 vol/size 노출이 제거됐다' 는 risk 층에서 성립하지 않는다",
         evidence = "N1 반증은 win_vol **백분위 격차** 0.0597 < 문턱 0.126 로 미발화했으나, 같은 배제집합의 **장기 변동성 수준**은 1.154배다. 위험모델이 쓰는 양은 백분위 격차가 아니라 곱셈 스케일이며, 이 스케일 차이 하나로 raw 꼬리 판별의 97.8% 가 설명된다(실현 lo/hi 비 1.4092 vs M0 예측 1.4091).",
         mechanism = "직교화는 win_vol(창 내 **일별** 수익 sd)에 대한 **선형 랭크 회귀**다. (a) 소비 형태가 **하위 분위 절단**이면 잔차의 U자 구조 때문에 선형 직교화가 절단면을 중립화하지 못한다. (b) 통제축(단기 일별 vol)과 위험모델이 쓰는 축(장기 월별 vol)은 다른 양이다.",
         scope = "alpha 층 판정(평균 basis ΔIR)에 대한 반박이 아니다 — alpha 결론은 불변. risk 층으로의 **이식 전제**만 반박한다.",
         action_requested = "없음(수정 요구 아님). 향후 '직교화 축' 을 risk/screen 층에 이식할 때 백분위-격차 문턱 대신 **소비 형태와 같은 절단면에서의 곱셈 스케일** 로 중립성을 재검할 것."),
    list(id = "RF-RX2", severity = "MEDIUM", to_agent = "self",
         claim = "본 라운드 관문의 순열 귀무가 MDE 를 10.3배 과소평가했다",
         evidence = "R3 사전 MDE80 0.00290 vs 실현 0.02998. 순열은 배정만 무작위화하고 처치 크기를 고정해 **추정기의 추정오차 분산**을 누락.",
         action_requested = "관문 MDE 규약 개정 — 라벨 순열 + 귀무 데이터에 추정기 재적합(이중 재표집).")),

  diagnostics = list(
    base_model = list(name = "adaptive rolling 60m monthly sd (min 18) + PIT 확장창 표준화잔차 경험분위",
      panel_rows = GJ$inputs$n_rows, panel_months = GJ$inputs$n_months,
      coverage_note = "sd0 커버리지 83.8%. v1 의 완전창 버그(패널 54%/장수티커 편중)는 수리됨."),
    method_shopping_log = list(risk_agent = msl),
    sample_alignment = GJ$sample_alignment,
    condition_number = NA, shrinkage_used = FALSE,
    regime_correlation_ref = NULL,
    pit = list(C1 = "rolling/expanding only — sd0 는 당월 제외 shift, 스케일 k 는 확장창 과거만",
               C5 = "score_orth = d0 시점, 결과 = d0 이후 1M forward(fwd_ret 계약)",
               C10 = "alpha 층 liqf(adv 2e8, t-1) verbatim 승계", C11 = "매크로 미사용",
               C14 = "IC 미접근", C15 = "Factor DB 직접 로드 없음")),

  consumption_surface_ruling = list(
    surface = "④ 위험모델·베타예산",
    status = "자유면 — FQ-233 분포-표적 자본화 차단 대상 아님",
    grounds = "본 산출은 (a) 자본 배분(weight/book)에 도달하지 않고 (b) forge-authoritative 성과 수치를 생산하지 않으며 (c) 판정 지표가 전부 추정품질 enum(R4 P3) 안에 있다. Q-Lead 2026-08-22 소비면 7종 판정의 ④항 자유면 승계.",
    capital_claim = "없음 — graduation 주장 금지 준수"),

  next_probe = CJ$next_probe,
  metric_type = "estimation_quality",
  emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))

write_json(pkg, file.path(MBX, "risk_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 12, null = "null", na = "null")
say("risk_package.json 기록")

## ── 5. lineage (write_json 이후 — R11 순서 엄수) ───────────────────────────
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id = TID, package_type = "risk_package",
    method_selected = "adaptive_rolling_min18_empirical_calib__gate_stop",
    input_file_paths = c(file.path(MBX, "alpha_package.json")),
    windows = list(list(name = "risk_panel", start = "2006-08-31", end = "2026-03-31")))
  say("lineage 기록 완료")
}, silent = FALSE)

## ── 6. R3 Challenge Authority — 반론 제기 ──────────────────────────────────
try({
  source("02_Infrastructure/worktask/worktask_manager.R")
  wt_challenge(TID, from_agent = "risk", to_agent = "alpha",
    reason = "직교화 노출중립 전제의 risk 층 비이식성 — N1 은 win_vol 백분위 격차 0.0597(<0.126)로 미발화했으나 동일 배제집합의 장기변동성 스케일은 1.154배이고 이것만으로 raw 꼬리 판별의 97.8%가 설명된다(실현 lo/hi 1.4092 vs 기저모델 예측 1.4091). alpha 판정 불변, risk 이식 전제만 반박.")
  say("wt_challenge 발행")
}, silent = FALSE)
say("완료")
