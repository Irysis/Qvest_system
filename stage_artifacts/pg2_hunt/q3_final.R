## q3 — FQ-215 정정 + 세션 최종 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[q3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

CORR <- paste0(
  "★★정정(2026-08-09 q1/q2): '계약 준수 ∧ 직교 교집합이 **구조적으로 비어 있다**' 는 과했다. ",
  "초판 census 가 **10-component 파일명만** 보고 판정해 `performance_summary.json` 의 ",
  "`walkforward_integrity`·`lockbox`·`prelb`·`subperiods` 같은 **다른 형식의 검증 기록**을 못 봤다. ",
  "게이트(`harness_compliance.R`)에 대체 검증 축을 추가해 재census 한 결과: ",
  "직교(rho<0.3) 비계보 **23계열** 중 검증 기록 보유 **1건** = `STR_1698_WT008_M08_Swap` ",
  "(tier **validated_needs_retrofit** · C15 via_contract ✓ · 10-component 0 · rho +0.192 · IR +0.560 · **부족분 0.087**). ",
  "⇒ 교집합은 **비어 있지 않고 하나뿐**이며, 공백의 정체는 '검증 안 됨' 이 아니라 **10-component 형식의 부재**다. ",
  "병목 진단(22/23 이 검증 기록 없음)은 유지되나 서술을 **'하나뿐'** 으로 약화한다. ",
  "★그 하나가 오늘 아크 최고 후보다 — 남은 장벽은 **계열이 2024-04 에 끝난 것** 하나뿐이고(파킹 겹침 51<60), ",
  "연장하면 검증된 파킹 레버(rho 를 전략 풀에서 **음수까지** 내림)를 걸 수 있다. 칩 task_b065b34d 가 정확히 그 작업. ",
  "★게이트 제작 중 내 오류 3건 추가 자가검거: ①파일명만 보고 판정(대체 검증 미인식) ",
  "②대체 검증 스캔이 재귀로 대형 트리를 훑어 **10분 타임아웃**(측정 전 게이트가 느리면 아무도 안 쓴다) ",
  "③단일 tier 사다리가 c15 없이는 10-component 를 무시해 **PG2(11/11·audit PASS)를 'unvalidated' 로 오분류** ",
  "— 오분류를 막으려 만든 게이트가 스스로 오분류했다. 셋 다 검사로 고정(`test_harness_compliance.R` **26/26**).")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
hit <- 0L
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% c("FQ-213","FQ-215")) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORR)
    hit <- hit + 1L; say("정정 기입 %s", ids[k])
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d항목 · 정정 %d건", length(read_frontier_queue()$entries), hit)

r <- close_round(
  round_id = "PG2_HARNESS_GATE_20260809",
  verdict_type = "capability_established",
  layer = "pipeline",
  mechanism_diagnosis = paste0(
    "오늘 아크의 마지막 층. STR_1675 가 4축 적대 검증을 통과한 **뒤에야** 계약 경로 밖임을 발견해 ",
    "라운드가 통째로 낭비됐다 — **순서가 틀렸다**(성과 측정 전에 준수를 세야 한다). ",
    "그 뿌리를 계약 `harness_compliance.R` 로 기계화했다: 3축(10-component · audit · C15 접근방식) + ",
    "대체 검증 기록 인식 → 6단 tier. 검사 `test_harness_compliance.R` **26/26**, ",
    "★전부 **실제 저장소 경로**로 돈다(합성 픽스처 아님). ",
    "★그리고 이 게이트가 즉시 내 결론 하나를 정정했다 — '계약 준수 ∧ 직교 교집합이 구조적으로 비어 있다' 가 ",
    "**'하나뿐이다'** 로 바뀌었고(STR_1698, tier validated_needs_retrofit), 공백의 정체가 ",
    "'검증 안 됨' 이 아니라 **10-component 형식 부재**임이 드러났다. ",
    "★게이트 제작 중 내 오류 3건 추가 발생(대체 검증 미인식 · 10분 타임아웃 · 준수 재료를 미검증 오분류) — ",
    "**오분류를 막으려 만든 게이트가 스스로 오분류**했고 셋 다 검사로 고정했다."),
  next_probes = c(
    "★STR_1698 계열 연장 + retrofit — 오늘 아크 최고 후보(rho 0.192·IR 0.560·부족 0.087·tier validated_needs_retrofit). 남은 장벽은 2024-04 종료 하나. 칩 task_b065b34d",
    "harness_compliance 의 소비자 배선 — 후보 평가 진입점(book_marginal 호출부·전략 풀 스캔)에 assert 를 걸어 '표준은 있는데 소비자 0' 재발 방지",
    "직교 22계열의 검증 기록 부재 확인 — 정말 없는지, 아니면 또 다른 형식인지. 오늘 이미 한 번 형식 때문에 오분류했다",
    "C15 우회 9건의 carve-out 승인 여부(도훈) — 승인 시 STR_1675(4축 통과)가 후보 복귀"),
  consumer_surfaces = c("후보 선별 순서", "전략 풀 재고 소비", "계약 재산출 우선순위",
    "C15 거버넌스", "계약 검사 배터리"),
  frontier_update = "FQ-213/215 정정 · harness_compliance.R 계약 신설(26/26) · 원장 219항목",
  live_trigger = "STR_1698 계열이 연장되면 즉시 파킹 적용 + retrofit → book-marginal 재판정",
  evidence_refs = c("02_Infrastructure/contracts/harness_compliance.R",
    "08_Tests/contract_regression/test_harness_compliance.R",
    "stage_artifacts/pg2_hunt/q2_tier_census.csv", "stage_artifacts/pg2_hunt/q1_retrofit_scope.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
