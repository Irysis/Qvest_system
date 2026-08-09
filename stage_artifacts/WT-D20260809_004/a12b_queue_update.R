setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- sapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else e$id)
i <- which(ids == "FQ-173"); stopifnot(length(i) == 1L)
e <- Q$entries[[i]]

e$status <- "measured_layer_attribution_negative"
e$measured_at <- "2026-08-09"
e$measured_by <- "alpha-research (WT-D20260809_004)"
e$measure_result <- list(
  primary_metric = "canonical top-25 EW cap-w PORT_t (canonical_screen_bt, NW lag-3)",
  common_window_months = 209L,
  common_window = "2009-03-31 ~ 2026-07-31 (beta_s burn-in 구속. 설계 초안의 '2003~ 280개월'은 expanding z 36m + beta 36m burn-in 미반영)",
  arms_port_t = list(R0_growth_only = 1.746, B_lambda0 = 1.090,
                     C_combined_l0.5 = 1.299, C_combined_l1.0 = 1.399,
                     Craw_literal_l0.5 = 1.062, Craw_literal_l1.0 = 1.066,
                     A_tilt_random_l0.5_mean20seed = -0.889,
                     A_tilt_random_l1.0_mean20seed = -1.163,
                     A0_base_random_mean20seed = -1.039),
  layer3_only_full_window_284m_port_t = 2.479,
  increment_c_minus_b_annual_pct = list(l0.5 = 1.094, l1.0 = 1.369),
  increment_t_nw3 = list(l0.5 = 1.07, l1.0 = 0.98),
  placebo_percentile_block12_200draws = list(l0.5 = 80.5, l1.0 = 71.0),
  power_observed_over_required = list(l0.5 = 0.46, l1.0 = 0.39),
  power_verdict = "INCONCLUSIVE_BAR_RESTATES_T — '기각' 라벨 미발동 (FQ-172 비대칭 규약)",
  hard_gate = "PORT_t 2.95 전건 미달. graduation·상신 자격 없음. 자본 주장 없음."
)
e$verdict_summary <- paste0(
  "층 분해(F3) 사전등록 규칙대로 처분: 틸트 단독 arm 무효(PORT_t -0.889~-1.163, 20시드) ∧ ",
  "결합-종목선택 증분 비유의(t 0.98~1.07, 플라시보 71~80분위) → **인플레 층 제외, 종목선택 알파로 재라벨**. ",
  "★단 '무효'가 아니라 '미확립' — 관측/필요 0.39~0.46 으로 검정력 조건 미충족이라 소비면 종료 근거 아님. ",
  "★★적대검증 정정: primary falsification(beta_s 부호-채널 정합 0.649, p 0.0005)은 **시장베타 교락**이다 — ",
  "같은 예측표를 섹터 시장베타로 채점하면 0.822 로 더 잘 맞고, 시장중립화 beta_s^orth 로 재검정하면 ",
  "0.600 / stride-12 0.571 / p 0.0845 로 유의성 상실. 채널 확인 주장 철회.")
e$artifacts <- list(
  alpha_package = "qepm/mailbox/worktask/WT-D20260809_004/alpha_package.json",
  alpha_validation = "stage_artifacts/WT-D20260809_004/alpha_validation.json",
  preregistration = "stage_artifacts/WT-D20260809_004/preregistration.json",
  prereg_amendment = "stage_artifacts/WT-D20260809_004/prereg_amendment_1.json",
  challenge_note = "qepm/mailbox/worktask/WT-D20260809_004/challenge_note.md",
  alpha_scores = "stage_artifacts/WT-D20260809_004/alpha_scores.parquet"
)
e$next_probes <- c(
  "NP-1 층3 단독을 EW-유니버스 기준으로 재판정 — cap-w FAIL(1.746/2.479) 이나 EW-대비 3.001/3.126, 보유 90.6%가 OTHER tier (v8.3 M2 벤치 미스매치 형태). screen_route 재분류 검토.",
  "NP-2 성장 합성 IC 감쇠 진단 — 2003-2014 0.0406(t 5.22) → 2015-2019 0.0102(t 1.12) → 2020-2026 0.0148(t 1.63). 컨센 커버리지 확대(724→2629종목) 교락인지 재료 소진인지 커버리지-정합 부분표본으로 분리.",
  "NP-3 인플레 틸트 부활 경로 — ①beta burn-in 36→24 로 창 +36개월 ②정원 대신 종목-레벨 beta_i 랭킹(승계 후보 3)으로 증분 분산 축소 ③심한 국면 조건부(월<-10% 등, 라벨 자격은 사건 정의에 조건부).",
  "NP-4 beta_s 패널 소비면 — 시장중립화 후에도 유틸 0.815·건강관리 0.809·철강 0.794 견고. 선택 알파로는 실패했으나 위험모델 섹터 노출 예산 / 오버레이 입력 / 유니버스 필터 면 미측정.",
  "NP-5 C01_SUE 를 dedup canonical C05_ESCR 로 교체한 3종 합성 재측정 (DUPC-005 redundant 해소).",
  "NP-6 양(+) 예측 실패 2섹터 기전 진단 — KR '에너지'=정유(원가=원유)라 전가력 아닌 재고효과 지배 가능. 채널 재정식화 후보."
)
e$revival_condition <- paste0(
  "INV-7 경로-scoped. 부활 신호: ①NP-3 ①~③ 중 하나로 관측/필요 >= 1.0 을 확보 ",
  "②beta_s^orth 기반 예측 일치율이 독립 창에서 0.60+ 재현 ③오버레이/위험모델 소비면(NP-4)에서 유의. ",
  "본 라운드는 '연속 틸트도 무효'라는 강한 지식을 주장하지 **않는다** — 검정력이 그 결론을 지지하지 않는다.")
e$in_flight_since <- NULL
e$in_flight_note <- NULL
e$next_action <- "NP-1(EW-basis 재판정) 또는 NP-4(beta_s 소비면) 착수 — 소유자 미정"

Q$entries[[i]] <- e
write_frontier_queue(Q)
cat("FQ-173 갱신 완료\n")
