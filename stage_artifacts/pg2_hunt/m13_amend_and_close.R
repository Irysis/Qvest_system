## m13 — FQ-217 정정(구 정렬 산물 표기) + 정렬 결함 라운드 등재 + 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m13] ")

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i217 <- which(ids == "FQ-217")
if (length(i217) != 1L) stop("FQ-217 를 원장에서 찾지 못함 — 정정 중단")
Q$entries[[i217]]$title <- paste0("★★라벨 17종 줄 세우기 — **무작위급 0개(이봉)만 생존**, ",
  "부호 서사·bm_gap 예측력·STR_1698 문턱초과는 **파킹 벤치 정렬 결함 산물로 철회**")
Q$entries[[i217]]$wall_check <- paste0(
  "★★★정정(같은 날 m9~m12): 초판 wall_check 는 **파킹 OFF 월 벤치가 +1 어긋난 자** 위에 있었다. ",
  "정렬 수리 후 재측정(m11, 사전등록 falsifier Spearman<0.5 통과 — 실측 **+0.750**): ",
  "**생존** = 무작위급 0개 이봉(신 좋음8/나쁨7/무작위급0, 구 7/10/0) · ",
  "Regime_Score_smooth_high **12/12** 구·신 상위2 · mega_spread 11/12 · Cash_Pct 발화율 86~100%로 문턱 무의미. ",
  "신 1위 = VEA_Score_high -0.6387. ",
  "**철회** = ①'Regime_Score high 1위/low 최하위 = 부호를 반대로 걸었다' → 수리 후 **양방향 다 좋음**",
  "(low -0.2433 · high -0.2065, 둘 다 11/12) ②'MSM_Crisis_Pro_low 는 나쁨' → **-0.2250 좋음**(부호 반전 2건째) ",
  "③'7축 중 5축이 같은 방향' → **단일 방향 규칙 없음**(high 4 · low 2 · 양방향 1) ",
  "④bm_gap 예측력 rho +0.815(p .0002) → **+0.156(p .594)** 사전등록 falsifier 발동, 규칙 소멸 ",
  "⑤STR_1698 '첫 문턱 초과' → 부족분 -0.085 → **+0.0859**, ΔIR +0.0613 → **+0.0233**, ",
  "P(>=0.05) 57.7% → **19.4%**, 귀무 창 inside TRUE → **FALSE(백분위 95.3%)** ⑥β수확 반증 라운드 무효. ",
  "⚠긴 창 '12/13 생존' 은 **재측정 안 함 — 인용 금지**. ",
  "★유효 잔존: '라벨 교체가 계열 연장보다 쌌다'(mega_spread 73개월 → Regime_Score 439개월로 ",
  "STR_1698 측정 가능) — **측정 가능과 통과는 별개**. ",
  "★자본 주장을 안 한 것이 유일한 방어였다(초판에서도 verdict_ci UNRESOLVED + harness unvalidated 가 차단).")
Q$entries[[i217]]$next_action <- paste0(
  "★next_probe(4, 정정판) = ①**긴 창 재측정** — 216~267개월 '12/13' 은 구 정렬 위. bm_park() 로 재측정. ",
  "②**예측 규칙 재시도** — 전략 안 보고 라벨 품질을 예측하는 성질은 **미확립**(bm_gap 소멸). ",
  "정렬 수리 자로 다시 후보를 세운다(에피소드 수·런길이·자기상관은 구 정렬서도 |rho|<0.5 였다). ",
  "③**'무작위급 0개' 의 검정** — 두 정렬 모두에서 나온 가장 강건한 사실. 라벨 후보를 더 넣어도 ",
  "중립이 안 나오는지 보면 '국면 라벨은 무해할 수 없다' 가 시험된다. ",
  "④STR_1698 하네스 적격화(`unvalidated`) — 통계 이전 문제이며 정렬과 무관하게 남아 있다.")
Q$entries[[i217]]$revival_condition <- paste0(
  "모든 파킹 측정은 bm_park() 경유(정렬 선언 필드 동반) · 구 정렬 수치 인용 시 반드시 철회 표기 병기")
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm = TRUE) + 1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★★파킹 벤치 정렬 결함 — 계약은 평가 시점에 정렬하는데 구성은 계약 밖이었다",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state = "unclaimed", note = "2026-08-09 측정면 결함 + bm_park 계약"),
  ev_rationale = paste0("m8 β 검정에서 무작위 라벨 파킹의 실현 β 0.636 이 OFF 비율 0.644 와 거의 같은 것을 보고 의심. ",
    "정렬돼 있으면 β ~ 0.95 여야 한다."),
  wall_check = paste0(
    "★12전략 중 **10건이 +1 어긋남**(offset0 상관 -0.06~+0.12 = 사실상 0, +1 에서 0.42~0.75). ",
    "파킹 `ifelse(on, r, benchmark_ret)` 의 OFF 월에 **한 달 전 벤치**를 넣고 있었다. ",
    "기전 = `bm_delta_ir` 내부 정렬은 **평가 시점**인데 파킹 **구성**은 그 호출 이전 계약 밖이고, ",
    "슬리브 재고(`s1_inventory.rds`)가 **`date` 를 버리고 `m` 만 남겨** 월-라벨 규약이 소실. ",
    "inc 는 월초 앵커(2004-02-02), 슬리브는 다른 규약. ",
    "★inc 자체는 무결(원천 두 CSV exact-date 조인, 오프셋 스캔 0 최대. cor 0.666/β 0.706 은 ",
    "vol 오버레이 북의 실제 성질). ",
    "★피해: 라벨 부호 2건 반전 · bm_gap 예측력 소멸 · STR_1698 문턱초과 소멸 · β검정 무효. ",
    "★**집계는 견디고 개별 판정은 뒤집힌다** — 순위 Spearman 0.750 보존. ",
    "수리 = `bm_park()`(정렬 실측·선언 + AMBIGUOUS_LOWCOR + INSUFFICIENT_OVERLAP) + 검사 **24/24**. ",
    "★★필드명 `offset_measured` 가 부호 방향을 이름으로 못 말해 **위반주입 4/4 가 반대로 읽혔다** — ",
    "`offset_inc_minus_sleeve` 개명이 수리의 절반."),
  next_action = paste0(
    "★next_probe(3) = ①**같은 결함의 다른 지점** — `by=\"m\"` 조인으로 두 계열을 붙이는 코드가 ",
    "저장소에 몇 군데인가. 계약 밖 전처리가 정렬을 가정하는 지점을 census. ",
    "②**슬리브 재고 재생성** — `s1_inventory` 가 `date` 를 보존하면 규약 소실이 원천 차단된다. ",
    "③**지문 일반화** — '무작위 대조의 β 가 OFF 비율에 수렴' 처럼, 정렬 결함을 드러내는 ",
    "산술 지문을 다른 구성(오버레이·블렌드·스택)에 대해서도 도출해 검사로 승격."),
  consumer_surfaces = c("파킹 측정", "book-marginal 후보 평가", "오버레이 구성",
                        "슬리브 재고 생성", "계약 밖 전처리 감사"),
  revival_condition = "새 파킹/오버레이 구성 코드 작성 시 즉시 bm_park() 경유 · 무작위 대조 β 지문 확인",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("FQ-217 정정 완료 · %s 등재 · 원장 %d항목", nid, length(read_frontier_queue()$entries))

r <- close_round(
  round_id = "PG2_PARKING_ALIGNMENT_REPAIR_20260809",
  verdict_type = "capability_established",
  layer = "measurement",
  mechanism_diagnosis = paste0(
    "라벨 순위 라운드의 downstream 을 검정하다 무작위 대조의 실현 β(0.636)가 OFF 비율(0.644)과 ",
    "거의 같은 것을 발견했다. 정렬돼 있으면 0.95 여야 한다. 추적 결과 파킹의 OFF 월 대체 벤치가 ",
    "**12전략 중 10건에서 한 달 어긋나** 있었다. `bm_delta_ir` 는 내부 정렬을 갖지만 그건 평가 시점이고 ",
    "파킹 **구성**은 그 호출 이전, 계약 밖에서 내가 손으로 한 merge 였다. ",
    "슬리브 재고가 `date` 를 버리고 월 인덱스만 남겨 규약 정보가 소실된 것이 뿌리다. ",
    "★수리 후 재측정에서 사전등록 falsifier(Spearman<0.5)는 통과했으나(+0.750) ",
    "**헤드라인 5건이 철회**됐다 — 부호 서사, 방향 규칙, bm_gap 예측 규칙, STR_1698 문턱 초과, β 검정. ",
    "집계(순위)는 견디고 개별 판정은 뒤집힌다. ",
    "★내가 자본 주장을 하지 않은 것이 유일한 방어였다 — verdict_ci UNRESOLVED 와 harness ",
    "`unvalidated` 가 초판에서도 이미 막고 있었다. 통계가 아니라 **계약 두 겹**이 막았다. ",
    "★수리는 `bm_park()` 로 파킹 구성을 계약 안에 넣는 것이고, 그 과정에서 필드명 `offset_measured` 가 ",
    "부호 방향을 이름으로 말하지 못해 위반주입 4/4 가 반대로 읽혔다 — 개명이 수리의 절반이었다."),
  next_probes = c(
    "같은 결함의 다른 지점 census — by=\"m\" 조인으로 두 계열을 붙이는 계약 밖 전처리가 몇 군데인가",
    "슬리브 재고 재생성 — s1_inventory 가 date 를 보존하면 규약 소실이 원천 차단된다",
    "긴 창 재측정 — 216~267개월 '12/13 생존' 은 구 정렬 위 수치라 인용 금지 상태",
    "지문 일반화 — '무작위 대조 β 가 OFF 비율에 수렴' 같은 산술 지문을 다른 구성에 대해 도출해 검사로 승격"),
  consumer_surfaces = c("파킹 측정", "book-marginal 후보 평가", "오버레이 구성",
                        "슬리브 재고 생성", "다음 세션 인수인계"),
  frontier_update = sprintf("FQ-217 wall_check 정정 · %s 등재 · 메모리 카드 신규1+전면개정1 · bm_park 계약", nid),
  live_trigger = "파킹/오버레이 구성은 bm_park() 경유 · 무작위 대조 β 가 OFF 비율에 수렴하면 정렬 의심",
  evidence_refs = c("stage_artifacts/pg2_hunt/m9_alignment_audit.R",
                    "stage_artifacts/pg2_hunt/m11_realigned_ranking.csv",
                    "stage_artifacts/pg2_hunt/m12_bmgap_realigned.csv",
                    "08_Tests/contract_regression/test_bm_park.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
