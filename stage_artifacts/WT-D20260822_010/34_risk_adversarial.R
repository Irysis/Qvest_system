## WT-D20260822_010 — Self-Adversarial Challenge 실측 + risk_package 정정 반영
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[adv] ", f, "\n"), ...))
A <- list()

G <- readRDS(file.path(OUT, "30_risk_gate_objects.rds")); P <- as.data.table(G$P)
MJ <- fromJSON(file.path(OUT, "31_risk_measure.json")); CJ <- fromJSON(file.path(OUT, "32_risk_controls.json"))
AB <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))
AB[, Date := as.Date(Date)]
P2 <- merge(P, AB[, .(Date, Ticker, n_win, absorb)], by = c("Date","Ticker"), all.x = TRUE)
P2[, qs := cut(frank(score_orth) / .N, breaks = seq(0, 1, 0.2), labels = 1:5, include.lowest = TRUE), by = Date]

## SC-1 absorb 추정잡음 아티팩트 가설
QA <- P2[, .(n = .N, mean_n_win = mean(n_win, na.rm = TRUE), sd_absorb = sd(absorb, na.rm = TRUE),
             mean_abs_absorb = mean(abs(absorb), na.rm = TRUE), mean_sd0 = mean(sd0)), by = qs][order(qs)]
A$SC1_noise_artifact <- list(
  by_quintile = lapply(seq_len(nrow(QA)), function(i) as.list(QA[i])),
  obs_count_flat = TRUE, obs_count_range = range(QA$mean_n_win),
  sd_absorb_Q1_over_Q5 = QA$sd_absorb[1] / QA$sd_absorb[5],
  verdict = "PARTIAL — '관측수 부족' 버전은 기각(n_win 전 분위 ~60 평평). '고변동→absorb 추정분산 확대' 버전은 지지(Q1 sd 2.48배, 관측수 동일). 단 Q5 의 높은 sd0 은 이 설명으로 안 됨(부분 설명).",
  implication_risk_layer = "처분 불변 — 기전이 (a)대리든 (b)잡음-선택이든 위험모델 한계기여는 없음.",
  implication_alpha_layer = "권한 밖 — NP2 직교화 후 t -4.32 의 일부가 잡음-선택 아티팩트일 가능성. 판정하지 않고 next_probe NP5 등재.")

## SC-3 검출 하한
A$SC3_detection_floor <- list(
  mde_as_share_of_raw_relgap = MJ$R1_gate_recomputed$detectable_floor$mde_as_share_of_raw_relgap,
  surviving_point_measure = MJ$R1_gate_recomputed$surviving_share,
  surviving_point_controls_thr20 = CJ$injection_and_controls$M0_roll60m$surviving_share,
  corrected_label = "잔존 >= 30% 는 효과없음(powered null) / 잔존 < 30% 는 미결(underpowered)",
  verdict = "ACCEPT — 단독 '효과없음' 표기 철회, 하한 병기 문면으로 교체")

## SC-2 꼬리-지속성 동어반복 반박 (과거 꼬리 winsorize 후 vol 비 재산출)
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
FR <- as.data.table(SI$fwd_ret)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
R <- copy(FR); setorder(R, Ticker, Date)
R[, rw := pmax(Ret_1m, -0.20)]
R[, idx := seq_len(.N), by = Ticker][, win := pmin(idx, 60L)]
R[, m1 := frollmean(rw, n = win, adaptive = TRUE, na.rm = TRUE), by = Ticker]
R[, m2 := frollmean(rw^2, n = win, adaptive = TRUE, na.rm = TRUE), by = Ticker]
R[, `:=`(m1 = shift(m1, 1L), m2 = shift(m2, 1L), nh = shift(idx, 1L)), by = Ticker]
R[, sdw := sqrt(pmax(m2 - m1^2, 0))][is.na(nh) | nh < 18L | !is.finite(sdw) | sdw <= 0, sdw := NA_real_]
P3 <- merge(P2, R[, .(Date, Ticker, sdw)], by = c("Date","Ticker"))[is.finite(sdw)]
A$SC2_tail_persistence_tautology <- list(
  winsorized_sd_ratio_lo_hi = P3[grp == "lo", mean(sdw)] / P3[grp == "hi", mean(sdw)],
  raw_sd0_ratio_lo_hi = P3[grp == "lo", mean(sd0)] / P3[grp == "hi", mean(sd0)],
  n = nrow(P3),
  verdict = "REBUTTAL — 과거 -20% 이하를 winsorize 해 꼬리사건 정보를 제거해도 vol 비가 1.1515 로 원본 1.1541 과 사실상 동일. 두 군의 변동성 격차는 평시 변동성에서 온다.")

A$note <- "challenge_note_risk.md 와 1:1 대응. SC-4(관문 MDE 10.3배 과소) / SC-5(관문 내 결과 사용) / SC-6(FQ-058 차별점) 은 서술 항목이라 본 JSON 에 수치 없음."
A$metric_type <- "estimation_quality__adversarial"
write_json(A, file.path(OUT, "34_risk_adversarial.json"), pretty = TRUE, auto_unbox = TRUE, digits = 12)
say("34_risk_adversarial.json 기록")

## ── risk_package 정정 반영 ─────────────────────────────────────────────────
pk <- fromJSON(file.path(MBX, "risk_package.json"), simplifyVector = FALSE)
pk$findings$Q1_tail_layer$verdict <-
  "잔존 >= 30% 는 효과없음(powered null) / 잔존 < 30% 는 미결(underpowered) — 점추정 잔존 0.93%(measure) ~ 2.2%(controls thr -20%). ★단독 '효과없음' 표기는 SC-3 자기적발로 철회."
pk$findings$Q1_tail_layer$detection_floor_mde_share_of_raw <- A$SC3_detection_floor$mde_as_share_of_raw_relgap
pk$findings$Q1_tail_layer$tautology_rebuttal <- A$SC2_tail_persistence_tautology
pk$adversarial_ref <- "stage_artifacts/WT-D20260822_010/34_risk_adversarial.json"
pk$challenge_note_ref <- "qepm/mailbox/worktask/WT-D20260822_010/challenge_note_risk.md"
pk$challenge_flags[[length(pk$challenge_flags) + 1]] <- list(
  id = "RF-RX3", severity = "MEDIUM", to_agent = "alpha",
  claim = "배제집합이 'absorb 를 가장 못 추정한 종목' 집합과 겹친다",
  evidence = "score_orth 하위 20%(=배제집합)의 sd(absorb) 0.2688 은 상위 20% 0.1085 의 2.48배인데 추정 관측수 n_win 은 60.37 vs 59.23 으로 동일. 같은 분위가 sd0 최고(0.1384).",
  scope = "risk 층 처분은 불변(어느 기전이든 한계기여 없음). alpha 층 함의 = NP2 직교화 후 t -4.32 의 일부가 잡음-선택 아티팩트일 가능성 — risk 권한 밖이라 판정하지 않음.",
  action_requested = "absorb 추정 정밀도(표준오차)로 가중하거나 정밀도-분위 내에서 재층화한 뒤 NP2 를 재산출할 것(next_probe NP5).")
pk$next_probe[[length(pk$next_probe) + 1]] <- list(
  id = "NP5", title = "absorb 추정 정밀도 통제 후 NP2 재산출",
  statement = "배제집합이 신호 집합인지 잡음-꼬리 집합인지 분리한다. absorb 의 종목-월 표준오차를 산출해 (a) 정밀도 가중 또는 (b) 정밀도-분위 내 재층화 후 tail_dn_prob_diff 를 재측정. 신호가 정밀도 통제 후에도 남으면 SC-1 (b) 기각.",
  owner_lane = "alpha-research (risk 권한 밖)")
pk$next_probe[[length(pk$next_probe) + 1]] <- list(
  id = "NP6", title = "절단면-정합 중립성을 계약으로 — 기존 '직교화' 산출물 소급 점검",
  statement = "선형 랭크 직교화 후에도 분위 절단면에서 통제변수의 곱셈 스케일 비를 재는 검사(cut-aligned neutrality)를 계약화하고, 시스템 내 '직교화' 라벨 산출물에 소급 적용. 본 라운드에서 이 검사 하나가 라운드 전체의 전제를 뒤집었다.",
  owner_lane = "infra / architect")
write_json(pk, file.path(MBX, "risk_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 12,
           null = "null", na = "null")
say("risk_package.json 정정 반영 (Q1 라벨 / RF-RX3 / NP5 / NP6)")
say("challenge_flags = %d건 | next_probe = %d건", length(pk$challenge_flags), length(pk$next_probe))
