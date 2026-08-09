## FQ-138 종결 — 원장 환류 + next_probe + close_round + 텔레그램
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ138")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-138")
Q$entries[[i]] <- make_claim(Q$entries[[i]], "complete", "Q-Lead 2026-08-09",
  "사전등록 실행 완료 — 4축 적대검증 전부 통과. 자본 주장 없음(gate_eligible=false).")
Q$entries[[i]]$status <- "prereg_executed_survives_20260809"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ138/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★사전등록(2026-08-08) 실행 완료 — **4축 적대검증 전부 통과**. ",
  "1급 DiD(POOL_EW 대조): delta **연 +26.09%** · NW3 t **+3.705** · n 79 · 절편 연 −4.36%. ",
  "★★순풍 가설 **정면 기각**: SIG_ON 연 +25.74% vs **NEU_ON 연 −1.05%** — 사전등록이 'NEU_ON 이 SIG_ON 에 근접하면 순풍' 이라 했는데 근접하지 않는다. ",
  "①NEU 구성 민감도: 무작위 25종 50회 t 중앙 +2.723, 5~95% [+1.69,+3.67], **t>0 100%** ",
  "②위약 200회: |t|>=2 비율 **0.045**(이론 5%와 정합=파이프라인 정상) · 실측 백분위 1.000 · **p_one 0.0000** ",
  "③2026 오염 제외: 연 +26.09%→**+27.10%**(103.8% 잔존)·t +3.806 — 국면 ON 27개월 중 2026 은 **1개월**뿐. 오염 산물 아님 ",
  "④신호 정체 확인: 초판이 집은 n_contracts 는 **원 스크립트 참조 0회** 오답 → 정본 **score = w_amt/Size** 역추적 확정. ",
  "★★부수 발견: 계약 패널 종목수익에 물리불가 68건 중 **63건이 2026**(최대 +15,285%) = 2026 벤치 결함의 **종목-계열 판본**(칩 task_5452df6a 와 같은 뿌리, 미수리). ",
  "⚠한정: 사전등록이 pass/fail 을 금지했다(구간추정 라운드) · gate_eligible=false · capital_claim=none · n 79개월/ON 27개월로 검정력 여유 없음 · HARD 3종 미측정.")
Q$updated <- "2026-08-09"

nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$", "\\1", ids))); nums <- nums[is.finite(nums)]
k <- max(nums); free <- character(0)
while (length(free) < 2L) { k <- k + 1L; c0 <- sprintf("FQ-%03d", k); if (!(c0 %in% ids)) free <- c(free, c0) }
say("배정 ID: %s", paste(free, collapse=", "))

new <- list(
  list(id = free[1], lane = "non_return",
    title = "★계약 국면-조건부 알파의 **자본 경로** — HARD 3종 측정 (FQ-138 생존 후속)",
    hypothesis = paste0(
      "FQ-138 이 국면-조건부 초과분(연 +26.09%, t +3.705)이 순풍과 구별됨을 사전등록 4축 검증으로 확립했다. ",
      "그러나 그 라운드는 **자본 자격을 주장하지 않았다**(gate_eligible=false). ",
      "국면-조건부 운용 규칙(ON 월에만 계약 top-25, OFF 월엔 현금/벤치)의 **HARD 3종**(PORT_t 2.95 · oos_retention 0.7 · calmar 0.64)을 측정한다. ",
      "무조건부 SIG PORT_t 는 +0.581 로 크게 미달이므로, 국면 조건부가 그것을 자본 문턱까지 올리는지가 질문."),
    ev_rationale = "이 저장소에서 **비-return 재료가 자본 문턱에 도전하는 첫 사례**. 데이터·신호·국면 정의 전량 기지불이고 사전등록도 이미 있다.",
    wall_check = paste0(
      "★국면 OFF 월 처리를 **사전등록으로 고정**할 것 — 현금/벤치/유지 중 사후 선택 금지. ",
      "max 25 · long-only · [0,0.20] · Σw=1 · 유동성 2e8 불변. 국면 스위칭 회전율을 |Δ보유명목|×15bps 로 실과금. ",
      "★2026 오염 미수리 — 제외판을 정본으로 하고 수리 후 포함판 재측정."),
    data_gate = "없음 (gridx_* + panelx_A 재사용)",
    owner = "UNCLAIMED — FQ-138 이 발행. claim_state.R 경유 착수.",
    status = "frontier_open",
    next_action = "①OFF 월 처리 사전등록 고정 ②HARD 3종 측정(2026 제외판) ③국면 스위칭 비용 실과금 ④oos_retention 은 essence_score 권위 경유",
    source_refs = list("stage_artifacts/FQ138/validation.json",
                       "stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json")),
  list(id = free[2], lane = "measurement_integrity",
    title = "★2026 오염의 **종목-계열** 판본 — 벤치 결함이 아니라 원천 결함인가",
    hypothesis = paste0(
      "오늘 두 경로에서 2026 이상이 확인됐다: ①벤치 계열(gap 3.62배·p99 초과 18.4%·2026-07-31 +19.98% vs 종목중앙 +4.40%) ",
      "②**계약 패널 종목수익**(물리불가 68건 중 63건이 2026, 최대 +15,285%). ",
      "①만이면 벤치 접합 결함이지만 ②까지면 **원천 수집/조정 결함**이다(스플릿·액면·통화 미조정 등). ",
      "두 결함이 같은 뿌리인지 다른 뿌리인지 가른다 — 수리 범위가 달라진다."),
    ev_rationale = "칩 task_5452df6a 가 벤치만 다룬다. 종목 계열까지면 수리 범위와 오염 산출물 목록이 크게 늘어난다.",
    wall_check = "측정무결성 라운드 — 자본 주장 없음. read-only 진단. 05_Production 수정 금지.",
    data_gate = "없음",
    owner = "UNCLAIMED — FQ-138 이 발행. ★칩 task_5452df6a 와 범위 대조 필수.",
    status = "frontier_open",
    next_action = "①물리불가 68건의 Ticker·Date 전수 목록화 ②RAWDATA 원본에서 동일 종목-일자 확인 ③스플릿/액면변경 이벤트와 대조 ④벤치 결함과 날짜가 겹치는지",
    source_refs = list("stage_artifacts/FQ138/validation.json (axis4)",
                       "stage_artifacts/FQ182/p5_bench_stock_gap.csv")))
for (e in new) { Q$entries[[length(Q$entries)+1L]] <- e; say("  %s 등재", e$id) }
write_frontier_queue(Q)
id2 <- vapply(read_frontier_queue()$entries, function(e) as.character(e$id)[1], "")
say("재읽기: %s · FQ-138 claim=%s", paste(sprintf("%s=%s", free, free %in% id2), collapse=" · "),
    claim_state(read_frontier_queue()$entries[[i]])$state)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-138", verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "계약수주 신호의 국면-조건부 초과분은 국면 순풍과 구별된다. 사전등록이 의심한 교락(국면 ON = 메가캡이 지는 달 = ",
    "소형 편향 top-25 EW 의 순풍, mega_spread 와 벤치 핸디캡 d 의 상관 +0.896)은 중립 대조로 소거되며, ",
    "NEU_ON 이 연 −1.05% 로 사실상 0 이라 순풍 가설이 정면 기각된다. DiD delta 연 +26.09%(t +3.705)는 ",
    "대조군 구성(무작위 50회 t>0 100%)·위약 200회(귀무 |t|>=2 4.5%, p_one 0.0000)·2026 오염 제외(오히려 +27.10%로 강화) ",
    "네 축을 전부 통과한다. 사후 선택이었던 원 발견이 사전등록 재판정에서 살아남았다."),
  next_probes = c(
    paste0(free[1], " 자본 경로 — 국면-조건부 운용 규칙의 HARD 3종 측정. 무조건부 PORT_t +0.581 을 국면 조건부가 문턱까지 올리는가. ★OFF 월 처리를 사전등록으로 고정할 것."),
    paste0(free[2], " 2026 오염의 종목-계열 판본 — 벤치 접합 결함인가 원천 수집 결함인가. 수리 범위가 달라진다."),
    "★clean OOS 소비 — 사전등록이 '2026-08-08 이후 관측월은 자동 clean OOS' 라 명시했다. 아직 소비하지 않았다. 월이 쌓이면 별도 재판정.",
    "국면 정의의 이식성 — mega_spread 는 KR 고유 구성이다. 다른 국면 축(유동성·수급)에서도 계약 신호가 조건부 초과를 내는지.",
    "기전 규명 — 왜 메가캡이 지는 달에 계약 신호가 강해지는가. FQ-139 가 기관 후속매수를 기각했고 외국인 단독으로 좁혔다. 국면 의존은 여전히 미설명."),
  consumer_surfaces = c(
    "①팩터 랭킹 — ★국면-조건부 가중의 첫 실증 근거. 단 자본 자격은 별도(HARD 3종 미측정)",
    "②유니버스 필터 — 미측정(FQ-126 이 대기 중이나 선행 조건 있음)",
    "③오버레이/국면 — ★가장 자연스러운 소비면. 국면 ON 에서만 계약 sleeve 활성화하는 구조",
    "④위험모델 — 미측정",
    "⑤monitoring — mega_spread 는 t-1 관측이라 PIT 자명. 국면 tripwire 로 즉시 사용 가능",
    "⑥선별 라벨 — '계약 재료 = 국면 조건부 유효' 라벨 등재 가능",
    "⑦타 모드 — FR 의 국면-조건부 모듈 배합에 계약 sleeve 후보로 제공"),
  frontier_update = paste0("FQ-138 status=prereg_executed_survives_20260809 · claim=complete · ",
                           paste(free, collapse=" · "), " 신규 등재"),
  live_trigger = paste0("★본 라운드는 negative 가 아니지만 부활 조건에 준하는 조건을 남긴다: ",
    "①2026 오염 수리 후 포함판에서 부호가 유지될 때 정본 갱신 ②clean OOS 월이 12개 이상 쌓이면 재판정 ",
    "③HARD 3종 미달 시 국면-조건부는 자본이 아니라 **오버레이/선별 라벨** 소비면으로 라우팅."),
  layer = "①재료 (비-return)",
  evidence_refs = c("stage_artifacts/FQ138/validation.json",
                    "stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json",
                    "stage_artifacts/FQ138/p1_spread.csv"))
say("=== FQ-138 종결 ===")
