## r1 — STR_1675 계열 등재 + 라운드 종료 + STR_1698 신선도 태스크 분리
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[r1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★STR_1675 계열 — 오늘 유일하게 4축 적대 검증 통과 (파킹 후 음의 상관 + 요구조건 초과)",
  status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state="complete", session="832fa2fc", note="FQ-212 전략풀 라운드 2026-08-09"),
  ev_rationale = paste0("팩터DB 331 전수가 통과 0 으로 끝난 뒤 표적을 'IR 0.7+ 재료' 로 확정하고 ",
    "**완성 전략 풀**(팩터가 아닌 조립된 포트폴리오)을 book-marginal 로 처음 측정했다."),
  wall_check = paste0(
    "★인벤토리: 후보 파일 1,052 → 월별 계열 추출 **52** → 중복 18쌍 제거 → **유효 독립 40**. ",
    "커버리지 census: PG2 겹침 중앙 258개월 · 파킹 적용 가능 **39/40**(불가 1건 = STR_1698 이 2024-04 종료). ",
    "★무처리 측정(40계열): 1급 통과 0 · **cor(rho, IR) = +0.712** — 높은 IR 은 예외 없이 높은 상관과 함께 온다. ",
    "rho<0.4 32계열 IR 중앙 +0.054 vs rho>=0.4 6계열 IR 중앙 +0.875. 331 라운드 구조가 전략 풀에서도 재현. ",
    "★★파킹 레버 적용(창 정합 12계열): rho **+0.225 → −0.005**(인하 12/12) · IR +0.021 → +0.245(상승 11/12) · ",
    "부족분 +0.636 → +0.164(개선 11/12) ⇒ **1급 통과 3/12**. ",
    "팩터 슬리브는 파킹해도 rho 0.32 가 바닥이었는데 **완성 전략은 음의 상관까지 간다**. ",
    "★★★적대 검증 4축: ",
    "①중복 — STR_1675 두 변형 Pearson **0.765**(구분됨, 중복 아님) · vs pilot11 0.671 ",
    "②무작위 파킹 200회 대비 백분위 **97.0% / 97.0%** / 91.0% ",
    "③**귀무 창 1000회**(subsample_null) 백분위 **2.5% / 2.5%** (inside FALSE) / 22.9%(inside TRUE) ",
    "④연도별 제외 ΔIR 부호 유지 **7/7 / 7/7 / 7/7** ",
    "⇒ **STR_1675_QRebal_Hybrid · STR_1675_B_monthly 가 4축 전부 통과**. pilot11 은 ③에서 탈락. ",
    "★비교: 오늘 계약 슬리브는 귀무 창에서 백분위 14.8%(inside TRUE)로 탈락했다 — STR_1675 는 2.5% 로 통과. ",
    "**근거가 한 단계 강하다.** ",
    "⚠자본 주장 불가: CI 하단 >= 0.05 **0/12**. 최고 ΔIR +0.1301 의 CI **[−0.0600, +0.2506]** 가 0 을 포함. ",
    "73개월에서 문턱 0.05 는 se ~0.093 이라 점추정이 넘어도 판별 불가 — verdict_ci 전건 **UNRESOLVED**."),
  next_action = paste0(
    "★next_probe(4) = ①**STR_1675 계열의 정체 규명** — 두 변형(QRebal_Hybrid · B_monthly)이 무엇으로 만들어졌는지 ",
    "생산 코드 확인. Pearson 0.765 로 구분되나 같은 계보일 수 있다. 계보가 같으면 독립 후보는 1건이다. ",
    "②**창 확장** — 파킹 라벨이 73개월뿐이라 CI 가 0 을 포함한다. 라벨을 전 기간으로 확장하거나 ",
    "다른 라벨로 같은 검증을 재현하면 검정력이 붙는다. ",
    "③**PIT 검증** — 이 전략들의 NAV 가 PIT-clean 한지 확인(오늘 저장 패널 동월 look-ahead 전례). ",
    "생산 코드 경로에서 재산출해 parity 확인 의무. ",
    "④**나머지 28계열 파킹 적용** — 이번엔 부족분 상위 12건만 쟀다. 전수로 확장."),
  consumer_surfaces = c("오버레이 후보", "book-marginal 후보 평가", "전략 풀 재고 소비",
    "FQ 큐 우선순위", "병목지도 자본 행"),
  revival_condition = "창이 확장돼 CI 하단이 문턱을 넘거나, PIT 검증 통과 후 governor 심사 대상이 되면",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_STRATEGY_POOL_20260809",
  verdict_type = "screen_tier_routed",
  layer = "material",
  mechanism_diagnosis = paste0(
    "표적을 'IR 0.7+ 재료' 로 확정한 뒤 팩터가 아닌 **완성 전략 풀**을 처음 book-marginal 로 쟀다. ",
    "무처리로는 1급 통과 0 이고 **cor(rho, IR) = +0.712** 로 331 라운드의 구조가 재현됐다 ",
    "(높은 IR 은 높은 상관과 함께 온다). ",
    "그런데 **파킹 레버가 전략 풀에서는 팩터보다 훨씬 강하게 작동**했다 — rho 중앙 +0.225 → **−0.005**, ",
    "팩터 슬리브의 바닥 0.32 를 넘어 음의 상관까지 간다. 부족분 중앙이 +0.636 → +0.164 로 개선되며 1급 3/12 통과. ",
    "★적대 4축(중복·무작위 파킹·귀무 창·창 이동)에서 **STR_1675 두 변형이 전부 통과**했고, ",
    "특히 귀무 창 백분위 **2.5%**(계약 슬리브는 14.8% 로 탈락한 관문)를 넘었다. ",
    "⇒ 오늘 아크에서 **근거가 가장 강한 후보**다. ",
    "⚠단 CI 하단이 문턱을 못 넘어(0/12, 최고 CI [−0.060, +0.251]) 자본 주장은 불가하며 ",
    "라우팅은 오버레이 후보 + 증거 누적 대기다."),
  next_probes = c(
    "STR_1675 두 변형의 계보 규명 — Pearson 0.765 로 구분되나 같은 생산 코드에서 나왔을 수 있다. 같으면 독립 후보는 1건",
    "창 확장 — 파킹 라벨 73개월이 CI 를 0 근처에 묶는다. 전 기간 라벨 또는 다른 라벨로 같은 4축 검증을 재현",
    "PIT 검증 — 전략 NAV 가 PIT-clean 한지 생산 코드 경로에서 재산출해 parity 확인(저장 패널 동월 look-ahead 전례)",
    "나머지 28계열 파킹 적용 — 이번엔 부족분 상위 12건만 측정했다. 전수 확장",
    "STR_1698_WT008_M08_Swap 계열 연장 — 무처리 부족분 0.087 로 최고였으나 2024-04 종료로 파킹 불가(겹침 51<60)"),
  consumer_surfaces = c("오버레이 후보", "book-marginal 후보 평가", "전략 풀 재고 소비",
    "screen_route 회수", "병목지도 자본 행"),
  frontier_update = sprintf("%s 등재 · 원장 217항목", nid),
  live_trigger = "창 확장으로 CI 하단이 0.05 를 넘거나 PIT 검증 통과 시 governor 심사 상신 (admit 은 도훈 수동)",
  evidence_refs = c("stage_artifacts/pg2_hunt/s3_strategies_lineage.csv",
    "stage_artifacts/pg2_hunt/s7_census.csv", "stage_artifacts/pg2_hunt/s8_parked.csv",
    "stage_artifacts/pg2_hunt/s9_adversarial.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
