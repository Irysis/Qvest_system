## x8 — 이식 아크(x5~x7) 원장 등재 + 라운드 종료 계약
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[x8] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)

Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★ON월 직교 기전은 이식 안 됨(0/24) — 계약+mega_spread 는 특이 쌍 · 라벨 방향성 2건은 가설",
  status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state="complete", session="832fa2fc", note="FQ-204 probe② 2026-08-09"),
  ev_rationale = paste0("x2 가 확립한 기전(라벨이 신호의 직교 구간을 고른다)이 계약 고유인지 일반인지 미검. ",
    "일반이면 모든 재료에 이식 가능한 레버이므로 최우선 검정 대상이었다."),
  wall_check = paste0(
    "★24셀 전수(재료 8 = 근접4+무작위4 x 라벨 3, 라벨은 **사전 고정**·argmax 금지·월말→익월 적용 PIT): ",
    "1급(ON월 rho 가 동일발화율 무작위 5% 아래) **0/24**. 최저 5%(XF_LL02+mega_spread)로 ",
    "계약+mega_spread 의 **0%** 를 아무도 재현 못 함. 다중검정 기대 1.2셀 대비 유의 아님. ",
    "⇒ **계약+mega_spread 는 특이 쌍**. ",
    "★부수(가설, 확증 아님): ⓐ`unified_Category` 8/8 전건 백분위<50(이항 p **0.0039**) = **일관되게 rho 인하**, ",
    "단 폭 부족(발화율 71.7%·에피소드 29 로 계약 35.6%/14 보다 완만 = 희석 의심). ",
    "ⓑ`jump_JM_State` 8/8 전건 백분위>50(p 0.0039) = 일관되게 rho 상승(역방향). ",
    "★★ⓑ의 반전 규칙(OFF 월 보유)을 x7 에서 직접 측정 → **기각**: 1급(무작위 타이밍 대비) **0/8**·백분위 중앙 18%, ",
    "2급(반전 vs 정상) 개선 **0/8**·중앙 −0.0443, IR 대가 **−0.230**. **라벨 정보 아니라 구조 효과**. ",
    "★내 예측 오류 1건: '반전이 rho 를 낮추는 것은 산술적 항등' 이라 선언했는데 실측 **0/8**(오히려 상승). ",
    "원인 = x6 이 잰 **ON월 부분상관**과 파킹 후 **전체계열 상관**은 다른 양이다. ",
    "다행히 그것을 '정보 0' 으로 **미리 선언**해 1급을 ΔIR 로 뒀기에 판정이 오염되지 않았다."),
  next_action = paste0(
    "★next_probe(3) = ①**unified_Category 의 희석 가설 검정** — 발화율 71.7% 를 계약 수준(35.6%)으로 ",
    "조이면 rho 인하 폭이 커지는가. 문턱 상향으로 발화율을 낮춘 판본 3종(50%/35%/20%)에서 ON월 rho 재측정. ",
    "★단 발화율을 낮추면 ON 월수가 줄어 검정력이 함께 떨어진다 — `required_effect_size.R` 로 착수 전 선언 의무. ",
    "②**계약의 특이성 국소화** — 계약+mega_spread 만 0% 인 이유가 (a)신호 성질 (b)라벨-신호 공통 원천 ",
    "(mega_spread 가 계약 데이터에서 유도됨) 중 어느 쪽인가. (b)면 순환이므로 **독립 라벨로 계약을 재측정**해야 한다. ",
    "★이것이 계약 후보의 **가장 큰 미검 위험**이다. ",
    "③라벨 후보 확장 — 현재 3종뿐이고 그중 하나가 계약-유도다. β_R05·vol-state·bear-prob 를 추가해 재검정."),
  consumer_surfaces = c("오버레이 라벨 설계", "book-marginal 후보 평가", "국면별 rho 분해 진단", "FQ 큐 우선순위"),
  revival_condition = "발화율 조정판에서 unified_Category 의 rho 인하 폭이 계약 수준에 도달하거나, 독립 라벨로 계약 특이성이 재현되면",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_TRANSPLANT_20260809",
  verdict_type = "config_scoped_negative",
  layer = "method",
  mechanism_diagnosis = paste0(
    "도훈 지시 'PG2 를 이길 전략' 아크의 후속. x2 가 확립한 기전 — 국면 라벨이 신호의 **직교 구간을 고르는 선택기** ",
    "(계약 ON월 rho 0.186 vs 무작위 0.399, 백분위 0%; 전체로는 무작위와 구분 안 됨 0.369 vs 0.378) — ",
    "이 일반 레버인지 24셀로 검정해 **0/24 이식 실패**. 계약+mega_spread 는 특이 쌍이다. ",
    "부수로 라벨 자체의 방향성 2건을 관측했으나(unified 인하 8/8, jump 상승 8/8, 각 p 0.0039), ",
    "jump 반전 규칙은 직접 측정에서 무작위 타이밍 대비 0/8 로 기각됐다(IR 대가 −0.230). ",
    "★남은 최대 위험: mega_spread 라벨이 **계약 데이터에서 유도**됐으므로 계약+mega_spread 의 특이성이 ",
    "신호 성질이 아니라 **라벨-신호 공통 원천(순환)** 일 수 있다. 독립 라벨로 계약을 재측정하기 전까지 ",
    "계약 후보의 직교성 주장은 잠정이다."),
  next_probes = c(
    "★계약 특이성 순환 검정 — mega_spread 가 계약 데이터 유도이므로 독립 라벨(β_R05·vol-state·bear-prob)로 계약 슬리브를 재측정. 순환이면 계약 후보의 직교성 주장이 무너진다. 이 아크 최우선",
    "unified_Category 희석 가설 — 발화율 71.7%를 50/35/20%로 조인 판본에서 ON월 rho 재측정. 착수 전 required_effect_size 선언 의무(ON 월수 감소로 검정력 동반 하락)",
    "라벨 후보 확장 — 현재 3종 중 1종이 계약-유도. β_R05·vol-state·bear-prob·유동성 국면을 추가해 24셀을 확장 재검정",
    "PG2 holdings 결손(칩 task_be236d0c) 수리 후 북 종목 필터 직접 측정 — 계약 유니버스 IR +0.349(12/12, p<1e-4)를 북에 직접 적용"),
  consumer_surfaces = c("오버레이 라벨 설계", "book-marginal 후보 평가 표준 진단(국면별 rho 분해)",
    "유니버스 필터 소비면", "FQ 큐 우선순위", "RAMP 팩터군 구성 사전입력"),
  frontier_update = sprintf("FQ-205 + %s 등재 · 원장 210항목", nid),
  live_trigger = "독립 라벨로 계약 특이성이 재현되면 직교성 주장 확정 · 재현 안 되면 계약 후보를 순환 산물로 재분류",
  evidence_refs = c("stage_artifacts/pg2_hunt/x2_parking_mechanism.R",
    "stage_artifacts/pg2_hunt/x5_transplant.csv", "stage_artifacts/pg2_hunt/x6_transplant_verdict.R",
    "stage_artifacts/pg2_hunt/x7_inversion.csv", "stage_artifacts/pg2_hunt/x3_filter.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
