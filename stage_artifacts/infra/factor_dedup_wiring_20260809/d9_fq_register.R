#==============================================================================
# d9_fq_register.R — 이 라운드가 연 두 갈래를 큐에 등재
#   ★ID 하드코딩 금지: 쓰기 직전 원장 max+1 계산 → 기록 → **재읽기 확인**
#     (원장 consume_rule ② + 오늘 210→213 선점 사례)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- as.integer(sub("^FQ-", "", grep("^FQ-[0-9]+$", ids, value = TRUE)))
nxt <- max(nums) + 1L
cat(sprintf("[d9] 현재 항목 %d / 최대 FQ-%03d → 신규 FQ-%03d, FQ-%03d\n",
            length(ids), max(nums), nxt, nxt + 1L))

ID_A <- sprintf("FQ-%03d", nxt)       # .cons_history 무력 창 수리
ID_B <- sprintf("FQ-%03d", nxt + 1L)  # redundant 판정 + dedup opt-in 결정

e_a <- list(
  id = ID_A, lane = "infra_measurement_integrity",
  title = ".cons_history() 무력 롤링 창 수리 (C10/C13/C15 공통 뿌리)",
  hypothesis = paste(
    "consensus 파생 팩터 중 '최근 n분기 롤링' 을 표방하는 블록이 실제로는",
    "최근 n**영업일**을 본다. .cons_history() 는 원천 관측 행을 최신순으로 주는데",
    "원천 sue/esbr 이 일간이기 때문(관측 간격 중앙 1일, 2026-08-09 실측).",
    "결과: C10_SUE_Persistence = mean(sue[1:4]) 가 창 span 3~5일·고유값 1개로",
    "latest 와 비트동일(mean==latest 비율 1.0000, 2010/2018/2024 전 티커),",
    "C13_Revision_Breadth_3m 도 동일(span 2일). C15_Forecast_Error_Trend 의",
    "sue[1]-sue[2]==0 사망도 같은 뿌리. 창을 분기 관측으로 축약하면 세 팩터가",
    "**의도한 신호를 처음으로** 배출한다 — 신규 팩터 3종에 준하는 회수."),
  ev_rationale = paste(
    "회수 대상이 이미 배출 중인 코드 3종이라 등록·명명 비용이 0.",
    "C10 은 PEAD proxy 로 설계됐는데 PEAD 는 KR 에서 미검 축이다.",
    "단 실측 전 기대는 미상 — 창 수리가 신호를 만든다는 보장은 없다(현재는",
    "'중복'이 아니라 '아직 측정된 적 없음' 상태라는 것만 확실)."),
    wall_check = paste(
    "미측정. 수리 후 canonical_screen_bt 로 PORT_t 실측 필요.",
    "★수리하면 FQ-", nxt, " 이 만든 alias 선언(C10->C01, C13->C04)이 **무효**가 된다 —",
    "registry dedup 의 revisit_on 필드가 그 조건을 명시하고 있으니 재측정 후 재선언할 것."),
  status = "frontier_open", owner = "UNCLAIMED",
  blocked_by = NULL,
  source_ref = paste(
    "04_Research/01_reports/factor_emission_identity_audit_20260809.md §3 next_probe①;",
    "실측 stage_artifacts/infra/factor_dedup_wiring_20260809/d3_cons_history_spacing.csv;",
    "코드 02_Infrastructure/factor_db/compute_consensus.R:31-42(.cons_history), :249(C10), :292(C13), :331(C15)"),
  created = "2026-08-09")

e_b <- list(
  id = ID_B, lane = "infra_measurement_integrity",
  title = "redundant 113종 판정 + 소비자별 dedup=TRUE 결정 (이중 투표 잔여분)",
  hypothesis = paste(
    "de-dup 소비 배선(2026-08-09)은 **alias 만** 자동 축약한다. 실측상 그 효과는",
    "top-25 중 평균 1.33종(6개월 프로브)으로 작다. 반면 cluster 당 1종만 남기는",
    "상한 시나리오는 top-25 중 평균 **13.67종(55%)** 을 바꾼다 — 이중 투표의 질량은",
    "자동 축약분이 아니라 **미판정 redundant 113종/40 cluster** 에 있다.",
    "registry 규약상 redundant 는 자동 병합 금지(구성이 다른데 실측만 겹치는 쌍은",
    "리서치 판단)이므로, 남은 일은 배선이 아니라 **판정**이다."),
  ev_rationale = paste(
    "40 cluster 중 3+ 멤버가 14개(최대 DUPC-010 = 변동성 계열 14종).",
    "이 계열들이 선별 풀에서 한 신호에 14표를 준다면 ICIR 랭킹·Ω 추정 양쪽이",
    "왜곡된다(WT-D20260802_003 의 Ω 전소가 그 사례).",
    "동시에 '접으면 결함이 숨는다' 축도 실재한다 — V13_EV_Sales/V16_Tobins_Q 의",
    "무력 항 사례처럼 동일성이 **버그 서명**인 경우가 있어 일괄 병합은 금물."),
  wall_check = paste(
    "상한 13.67/25 는 EW 합성 프로브(diagnostic)이지 PORT_t 가 아니다 —",
    "판정 후보가 정해지면 canonical_screen_bt 로 재측정할 것.",
    "또한 소비자별 dedup=TRUE 전환은 리서치 결과를 바꾸므로 도훈 confirm 대상."),
  status = "frontier_open", owner = "UNCLAIMED",
  blocked_by = NULL,
  source_ref = paste(
    "실측 stage_artifacts/infra/factor_dedup_wiring_20260809/d8_impact_scenarios.csv;",
    "배선 02_Infrastructure/factor_db/factor_db_connector.R(load_month_factors/",
    "compute_rolling_ic_all/group_factors_by_family 의 dedup 인자),",
    "02_Infrastructure/factor_db/factor_dup_scan.R::collapse_alias_rows();",
    "검사 08_Tests/factor_db/test_factor_dedup_consumption.R"),
  created = "2026-08-09")

Q$entries <- c(Q$entries, list(e_a), list(e_b))
Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("[d9] 기록 결과 — 추가 %s\n", paste(res$added, collapse = ", ")))

# ── 재읽기 확인 (선언이 아니라 디스크에서 파생) ─────────────────────────────
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
for (i in c(ID_A, ID_B)) {
  hit <- which(ids2 == i)
  if (!length(hit)) stop("[d9] ★재읽기 실패 — ", i, " 이 원장에 없다")
  cat(sprintf("[d9] 재읽기 확인 %s: %s (status=%s owner=%s)\n", i,
              Q2$entries[[hit]]$title, Q2$entries[[hit]]$status, Q2$entries[[hit]]$owner))
}
cat(sprintf("[d9] 총 항목 %d (등재 전 %d)\n", length(ids2), length(ids)))
