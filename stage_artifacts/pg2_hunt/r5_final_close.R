## r5 — 파이프라인 병목 등재 + 세션 최종 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[r5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★★파이프라인 병목 — '계약 준수 ∧ 직교' 교집합이 구조적으로 비어 있다",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state="unclaimed", note="2026-08-09 PG2 아크 최종 발견"),
  ev_rationale = paste0("STR_1675 가 4축 적대 검증을 통과했으나 계약 경로 밖이라 승격 불가였다. ",
    "그렇다면 **계약을 거친 계열 중에** 후보가 있는지를 세어봤고, 구조적 공백이 드러났다."),
  wall_check = paste0(
    "★40계열 계약 census: 10-component >= 8 인 계열 **6/40** · audit 보유 6. ",
    "그 6건의 rho = **0.766 ~ 0.945**(전부 북과 높은 상관) · IR 0.707~1.553. ",
    "반대로 rho<0.2 인 직교 계열은 10-component **0건**. ",
    "⇒ **'계약 준수 ∧ 직교' 교집합이 비어 있다.** '계약 준수 ∧ 비계보' 4건도 전부 rho>=0.766 이라 ",
    "부족분 0.520~0.679(유일 근접 WT_WT-S20260504_004 는 부족분 0.002 이나 rho **0.906**). ",
    "★기전: 하네스를 거친 전략 = **PG2 계보이거나 승격 과정 산출물**이고(WT_WT-S20260504_* · WT-D20260508_*), ",
    "직교한 전략들은 **탐색 단계에서 멈춰 계약 경로를 안 탔다**. ",
    "**승격 파이프라인이 곧 상관 필터로 작동**한 셈이다. ",
    "★C15 census: load_month_factors 경유 **20** · **직접 우회 9** · 미상 11. ",
    "우회 9건에 STR_1675 두 변형 포함(헤더는 'PIT 준수' 로 라벨). ",
    "⇒ 병목이 재료도 방법도 아니라 **파이프라인 구조**다."),
  next_action = paste0(
    "★next_probe(4) = ①**STR_1698 계약 재산출** — rho 0.192 · IR 0.560 · 부족분 **0.087**(무처리 최고) · ",
    "**C15 경유 확인**. 10-component 만 없다. 계열 연장(2024-04 종료, 칩 task_b065b34d) + `build_bt_result` 재산출로 ",
    "정식 자격 획득 가능. **가장 값싼 해소 경로**. ",
    "②C15 우회 9건의 carve-out 승인 여부 확인 — 도훈 판단. 승인되면 STR_1675 가 후보로 복귀한다. ",
    "③직교 계열 전수의 계약 재산출 비용 산정 — rho<0.3 인 계열이 몇 건이고 재산출에 무엇이 필요한가. ",
    "④★**후보 선별 순서 규약화** — 성과 측정 **전에** 계약 준수 3축(10-component·audit·load_month_factors)을 ",
    "먼저 센다. 오늘 STR_1675 에 4축 적대 검증을 다 돌린 뒤에야 하네스 밖임을 발견했다."),
  consumer_surfaces = c("전략 풀 재고 소비", "후보 선별 순서", "계약 재산출 우선순위",
    "C15 거버넌스", "병목지도 파이프라인 행"),
  revival_condition = "직교 계열 하나라도 계약 경로를 통과하면 즉시 book-marginal 재판정 — 레버(파킹)는 이미 검증돼 있다",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_PIPELINE_BOTTLENECK_20260809",
  verdict_type = "ceiling_reached_frontier_open",
  layer = "pipeline",
  mechanism_diagnosis = paste0(
    "도훈 지시 'PG2 를 이길 전략' 아크의 최종 진단. 자본 문턱 통과 0 건으로 끝났으나 ",
    "**병목이 세 층으로 분해**됐다: ①재료(팩터DB 331 전수 IR 최고 0.576 < 필요 0.717~0.925) ",
    "②방법(레버는 충분 — 파킹이 rho 를 전략 풀에서 음수까지 내린다. 단 강한 재료를 더 강하게 하는 레버는 없다) ",
    "③★**파이프라인** — 계약을 거친 6계열은 전부 rho 0.766~0.945(북 계보)이고, ",
    "직교한 계열(rho<0.2)은 10-component 0건. **'계약 준수 ∧ 직교' 교집합이 구조적으로 비어 있다.** ",
    "승격 파이프라인이 곧 상관 필터로 작동해 왔기 때문이다. ",
    "⇒ 새 알파는 '더 좋은 재료를 찾기' 보다 **직교 재료를 계약 경로로 통과시키기** 가 선결이다. ",
    "가장 값싼 대상 = STR_1698(rho 0.192 · IR 0.560 · 부족 0.087 · C15 경유 확인 · 10-component 만 부재)."),
  next_probes = c(
    "★STR_1698 계약 재산출 — 계열 연장(2024-04 종료) + build_bt_result. 정식 자격 획득 시 오늘 최고 후보가 살아난다",
    "C15 우회 9건의 carve-out 승인 여부 — 도훈 판단. 승인되면 STR_1675(4축 통과)가 후보로 복귀",
    "직교 계열 전수의 계약 재산출 비용 산정 — rho<0.3 계열 수와 재산출 요건",
    "★후보 선별 순서 규약화 — 성과 측정 전에 계약 준수 3축을 먼저 센다. 오늘은 4축 적대 검증을 다 돌린 뒤 하네스 밖임을 발견했다"),
  consumer_surfaces = c("전략 풀 재고 소비", "후보 선별 순서", "계약 재산출 우선순위",
    "C15 거버넌스", "병목지도 파이프라인 행"),
  frontier_update = sprintf("%s 등재 · 원장 218항목 · 병목지도 v60", nid),
  live_trigger = "직교 계열이 계약 경로를 통과하면 즉시 재판정 · C15 carve-out 승인 시 STR_1675 복귀",
  evidence_refs = c("stage_artifacts/pg2_hunt/r4_contract_census.csv",
    "stage_artifacts/pg2_hunt/s8_parked.csv", "stage_artifacts/pg2_hunt/s9_adversarial.R",
    "stage_artifacts/pg2_hunt/s7_census.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
