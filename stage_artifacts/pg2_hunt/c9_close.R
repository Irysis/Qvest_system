## c9 — PG2 사냥 라운드 종료 계약 + 원장 등재
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[c9] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE) + 1L)

Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★합성 축도 닫힘 — 기전은 작동하나 재료 IR 이 출발점부터 낮다 (전수 331 + 합성 8셀)",
  status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state = "complete", session = "832fa2fc", note = "PG2 사냥 2026-08-09"),
  ev_rationale = paste0("도훈 지시 'PG2 를 이길 전략'. 단일 팩터 331 전수 0/331 후 남은 갭이 IR 이므로 ",
    "합성(분산 효과)이 직접 레버였다. 요구조건 지도가 가리킨 유일한 남은 축."),
  wall_check = paste0(
    "★전수 331: 무조건부 상관 중앙 **+0.4203(양수 331/331, 최소 +0.083)** · IR 중앙 -0.083 · ΔIR 양수 0.3% / ",
    "파킹 상관 중앙 +0.3242 · IR 중앙 -0.090 · ΔIR 양수 2.7% · **통과 0/331 양 arm**. ",
    "부족분 중앙 0.834 · 최소 **0.142(V18_AM parked: 상관 0.243·IR 0.576·필요 0.717)**. ",
    "★합성 8셀(K 2/3/5/8 x 2arm, 고유 27재료 greedy): verdict_ci **BEATS_PG2 0건**(UNRESOLVED 6·BELOW 2). ",
    "최고 K8 parked ΔIR +0.0071 < **단일 최고 V18_AM +0.0201** ⇒ 합성이 단일을 못 넘는다(희석). ",
    "★단 기전은 실재: parked IR K2 0.413→K8 **0.521** 단조 증가 · 상관 uncond K2 0.308→K8 0.242. ",
    "무작위 합성 대조(40회x4셀): 문턱 통과 **0.0% 전 셀** · 선별 백분위 parked K3 97.5% K8 **100%** (uncond 80/90%) ",
    "⇒ 선별은 **파킹 arm 에서만** 유의. ",
    "★부수: 중복 팩터 2쌍 검거 — R17_Market_Leverage≡V19_Debt_to_Market(r 0.9991) · L06_Zero_Trade_Days≡L20_Trade_Frequency(r 1.000000)."),
  next_action = paste0(
    "★next_probe(4) = ①**V18_AM 단독 심화** — 부족분 0.142 로 유일한 가시권. 이 재료의 IR 을 0.576→0.717 로 ",
    "올리는 조건-안 레버(보유기간·밴드 소비·파킹 발화율 최적화)를 각각 재라. ",
    "②**중복 팩터 전수 검거** — 근접 30건에서만 2쌍이 나왔다. 331 전수 상호상관으로 유효 독립 개수를 산출하라 ",
    "(오늘 폐지풀 라운드에서 명목 195→유효 85 전례). 중복은 합성의 분산 효과를 죽인다. ",
    "③**비-return 원천 확대** — 계약수주(IR 0.758)가 팩터DB 최고(0.576)를 넘는 유일한 재료였다. ",
    "DART insider·공매도/대차·뉴스를 같은 book-marginal 자로 재라. ",
    "④**상관이 331/331 양수인 이유의 구조 분해** — 최소가 +0.083 이다. long-only·동일유니버스·top-25 중 ",
    "어느 제약이 하한을 만드는지 분해하면 조건-안 회피 경로가 보일 수 있다(제약 완화 아님)."),
  consumer_surfaces = c("알파 재료 선별 기준", "합성/composite 설계", "FQ 큐 우선순위", "병목지도 재료 행"),
  revival_condition = "슬리브 IR 0.72 이상 재료가 등장하거나, 상관 0.1 미만을 만드는 구성이 발견되면 재도전",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("원장 %d → %d · %s 등재 (순수추가 %s)", n0, length(Q2$entries), nid, length(Q2$entries)==n0+1L)

r <- close_round(
  round_id = "PG2_HUNT_20260809",
  verdict_type = "config_scoped_negative",
  layer = "material",
  mechanism_diagnosis = paste0(
    "도훈 지시 'PG2(IR 1.416) 를 이길 전략 발견'. book-marginal ΔIR>=0.05 를 자로 삼아 ",
    "팩터DB 331 전수 x 2arm + 합성 8셀 + 계약수주 신호를 측정했다. **통과 0건**. ",
    "기전은 두 축으로 분해된다: ①상관 — 같은 유니버스 long-only top-25 라 **331/331 전건 양수**(최소 +0.083, 중앙 0.420). ",
    "조건부 파킹이 이를 0.324 로 낮추는 검증된 일반 레버이나(48/48 개선 t+14.1, 무작위 대비 t+4.08 p0.0002) 충분치 않다. ",
    "②IR — 팩터DB 슬리브 IR 중앙 -0.090, 최대 0.576. 상관 0.24 에서 필요치는 0.717 이라 부족분 중앙 0.834. ",
    "합성은 IR 을 K 와 함께 단조 증가시키지만(K2 0.413→K8 0.521) **단일 최고를 못 넘는다**(희석). ",
    "⇒ ★병목은 방법이 아니라 **재료**다. 유일하게 필요치를 넘긴 IR(0.758)은 비-return 원천(계약수주)이었다. ",
    "★부수 확립: admission 문턱 0.05 가 269개월 전기간에서도 1.09 표준오차 — **통과 판정만 해상도 아래**이고 ",
    "탈락 판정은 유효한 비대칭. 계약(verdict_ci)과 governor(해상도 경고)에 반영했다."),
  next_probes = c(
    "V18_AM 단독 심화 — 부족분 0.142 로 유일한 가시권. IR 을 0.576→0.717 로 올리는 조건-안 레버(보유기간·밴드 소비·파킹 발화율)를 각각 측정",
    "중복 팩터 전수 검거 — 근접 30건에서 2쌍(r 0.9991·1.000000). 331 전수 상호상관으로 유효 독립 개수 산출. 중복은 합성 분산효과를 죽인다",
    "비-return 원천 확대 — 계약수주 IR 0.758 이 팩터DB 최고 0.576 을 넘은 유일 재료. DART insider·공매도/대차를 같은 자로 측정",
    "상관 331/331 양수의 구조 분해 — 최소 +0.083. long-only / 동일유니버스 / top-25 중 어느 제약이 하한을 만드는지 귀속(제약 완화 아님, 조건-안 회피 경로 탐색)",
    "governor 배선 후속 — pg1 의 ADMIT 결정 규칙을 CI 기반으로 바꿀지는 도훈 판단(FQ-199). 현재는 해상도 경고만 부가"),
  consumer_surfaces = c(
    "알파 재료 선별 기준 (요구조건 지도)", "오버레이 설계 (조건부 파킹 레버)",
    "governor PG1 admission 판정", "병목지도 재료·측정 행", "FQ 큐 우선순위"),
  frontier_update = sprintf("FQ-199/200/201 + %s 등재 · 병목지도 v57", nid),
  live_trigger = paste0("슬리브 IR 0.72 이상 재료 등장 · 상관 0.1 미만 구성 발견 · ",
    "또는 계약수주 신호의 국면 ON 월이 누적돼 CI 하단이 문턱을 넘으면 재판정"),
  evidence_refs = c("stage_artifacts/pg2_hunt/c6_full_table.csv",
    "stage_artifacts/pg2_hunt/c7_composite.R", "stage_artifacts/pg2_hunt/c8_random_control.csv",
    "02_Infrastructure/contracts/book_marginal.R",
    "08_Tests/contract_regression/test_book_marginal_ci.R",
    "08_Tests/contract_regression/test_governor_dir_resolution.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
