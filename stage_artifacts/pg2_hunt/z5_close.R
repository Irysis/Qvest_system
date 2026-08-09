## z5 — 희석 가설 라운드 등재 + V18 사전등록 명시 폐기 + 라운드 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[z5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

## V18 사전등록 폐기 표기 (파일에 남겨 방치 금지)
p <- "stage_artifacts/pg2_hunt/v18_preregistration.json"
if (file.exists(p)) {
  V <- fromJSON(p, simplifyVector = FALSE)
  V$RETIRED_20260809 <- list(
    status = "retired_not_executed",
    reason = paste0("워크플로 종합이 근접군의 **함의 t** 를 산출했다 — 파킹 arm 최대 1.420(V18_AM), ",
      "에피소드(14) 보정 시 **0.622**. |t|>2 인 파킹 재료는 328 중 1건뿐. ",
      "⇒ 'V18_AM 이 부족분 1위' 라는 **순위 자체가 잡음 위에서 매긴 순위**이므로 심화는 잡음 추적이 된다. ",
      "무작위 대비 우위가 확립되기 전에는 이 재료를 파고들지 않는다."),
    revival = "V18_AM 의 슬리브 IR 이 에피소드-보정 |t| 2 를 넘거나, 파킹 창이 확장돼 검정력이 붙으면 재개",
    note = "사전등록을 쓰고 실행하지 않은 경우 **명시 폐기**한다(방치 시 후속 세션이 미완으로 오인)")
  writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), p)
  say("V18 사전등록 폐기 표기 완료")
}

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★희석 가설 기각 — 발화율은 국면 라벨의 rho 인하 폭을 설명하지 않는다",
  status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state="complete", session="832fa2fc", note="FQ-206 next_probe① 2026-08-09"),
  ev_rationale = paste0("x6 이 `unified_Category` 의 8/8 일관 rho 인하(이항 p 0.0039)를 관측했으나 ",
    "폭이 계약(백분위 0%)에 못 미쳤다. 발화율 71.7%(계약 35.6%)가 원인이라는 희석 가설이 ",
    "이식 실패(0/24)를 설명하는 유일한 후보였다."),
  wall_check = paste0(
    "★축 정합 선행: `Category==RISK_ON` ⟺ `Regime_Score` **하위 71.7%** — 일치 **100.0%** · phi **+1.000** ",
    "(7축 x 2방향 전수 탐색으로 확정). ",
    "★발화율 궤적(ON 192→134→94→54): 백분위 중앙 **20% → 19% → 14% → 26%** · ",
    "spearman(ON월수, 백분위) **−0.200** · <5% 통과 **0/8 전 발화율**. ",
    "⇒ 조여도 계약 수준(0%)에 접근하지 않고 rate20 에서는 오히려 악화. **희석 가설 기각**. ",
    "★x6 관측 자체는 재현됨(rate72 에서 <50% **8/8**, 중앙 20%) — 방향은 실재하나 폭이 그만큼일 뿐. ",
    "⇒ 이식 실패(0/24)의 원인은 '다른 라벨이 너무 완만해서' 가 **아니다**. 계약 특이성은 여전히 미해명. ",
    "★★Q-Lead 오류 3연속(같은 아크): ①`Active_Layers` 한 이름만 보고 '수치 컬럼 부재' 선언(실제 7개) ",
    "②대리 축 **방향 미확인**(phi −0.394 = 반대) ③`setorder(-phi)` 에서 **NA 가 최대처럼 정렬**돼 ",
    "완벽한 축(phi 1.000)을 놓칠 뻔. **셋 다 정체 검사 생략**이고, 잡아준 것은 규약이 아니라 ",
    "**자기모순**(같은 라벨이 x6 15% vs z1 75%)이었다."),
  next_action = paste0(
    "★next_probe(3) = ①**계약 특이성의 남은 후보** — 발화율이 아니면 무엇인가. ",
    "후보: ⓐ신호-라벨 **경제적 동조**(계약수주는 실물 사이클, mega_spread 는 대형-소형 상대성과 — ",
    "둘 다 경기 국면에 연동) ⓑ계약 슬리브의 **보유 종목이 국면에 따라 바뀌는 정도**(적응성). ",
    "ⓐ는 계약 신호와 mega_spread 의 시계열 상관·리드랙으로, ⓑ는 ON/OFF 보유 겹침률로 즉시 측정 가능. ",
    "②라벨 후보 확장 — β_R05·vol-state·bear-prob 를 추가해 24셀을 확장(현재 3라벨 중 1개가 계약-유도). ",
    "③**대리 축 재현 검사를 계약 함수로** — 오늘 3회 오류의 공통 뿌리다. ",
    "`assert_proxy_reproduces(orig_label, proxy_axis)` 로 일치율·phi·무작위 기대를 강제 출력."),
  consumer_surfaces = c("국면 라벨 설계", "오버레이 라벨 선정", "대리 축 사용 규약", "FQ 큐 우선순위"),
  revival_condition = "Category 를 만든 다변량 규칙이 규명되거나, 새 연속 국면 축이 추가되면 재검정",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_DILUTION_20260809",
  verdict_type = "config_scoped_negative",
  layer = "method",
  mechanism_diagnosis = paste0(
    "이식 실패(0/24)의 유일한 설명 후보였던 희석 가설 — '다른 라벨은 발화율이 너무 완만해서 rho 인하 폭이 작다' — ",
    "를 검정해 **기각**했다. 축 정합을 먼저 확정하고(`Category==RISK_ON` ⟺ `Regime_Score` 하위 71.7%, ",
    "일치 100.0% · phi 1.000), 발화율을 71.7→50→35→20% 로 조였으나 백분위 중앙이 20→19→14→26% 로 ",
    "계약 수준(0%)에 접근하지 않았다(spearman −0.200, <5% 통과 0/8 전 발화율). ",
    "⇒ 계약+mega_spread 의 특이성은 **발화율로 설명되지 않는다**. 남은 후보는 신호-라벨의 경제적 동조 또는 ",
    "슬리브의 국면-적응성이며 둘 다 즉시 측정 가능하다. ",
    "★부수: Q-Lead 오류 3연속(한 이름 조회로 '부재' 결론 · 대리 축 방향 미확인 · NA 정렬)이 모두 ",
    "**정체 검사 생략**이었고, 잡아준 것은 규약이 아니라 자기모순 관측이었다. ",
    "대리 축 재현 검사를 계약 함수로 승격하는 것이 재발 방지다."),
  next_probes = c(
    "계약 특이성 후보 ⓐ 경제적 동조 — 계약수주 신호와 mega_spread 의 시계열 상관·리드랙 측정. 둘 다 경기 국면 연동이면 ON월 직교성이 '같은 사이클의 서로 다른 위상' 으로 설명된다",
    "계약 특이성 후보 ⓑ 국면-적응성 — 계약 슬리브의 ON/OFF 보유 종목 겹침률. 국면에 따라 다른 종목을 담으면 북과의 상관이 국면별로 갈리는 것이 자연스럽다",
    "라벨 후보 확장 — β_R05·vol-state·bear-prob 추가해 이식 24셀을 확장(현재 3라벨 중 1개가 계약-유도라 독립 라벨이 2개뿐)",
    "★`assert_proxy_reproduces()` 계약 함수 신설 — 대리 축 사용 시 일치율·phi·무작위 기대(p²+(1−p)²)를 강제 출력. 오늘 3회 오류의 공통 뿌리를 기계로 막는다"),
  consumer_surfaces = c("국면 라벨 설계", "오버레이 라벨 선정", "대리 축 사용 규약",
    "book-marginal 후보 평가", "FQ 큐 우선순위"),
  frontier_update = sprintf("%s 등재 · V18 사전등록 명시 폐기 · 원장 211항목", nid),
  live_trigger = "Category 생산 규칙이 규명되거나 새 연속 국면 축이 추가되면 희석 가설 재검정",
  evidence_refs = c("stage_artifacts/pg2_hunt/z3_axis.csv", "stage_artifacts/pg2_hunt/z4_dilution.csv",
    "stage_artifacts/pg2_hunt/z2_labels.csv", "stage_artifacts/pg2_hunt/v18_preregistration.json"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
