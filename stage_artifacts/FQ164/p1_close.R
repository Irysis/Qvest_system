## FQ-164 종결 — 착수 전 폐기 판정 + 회전율 축 종합 + claim 전이
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ164")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

V <- list(
  round_id = "FQ-164", parent = "WT-D20260809_001 NP-1",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  verdict = "ABORTED_BEFORE_MEASUREMENT — 가설의 전제가 사전 확인에서 깨짐",

  hypothesis_premise = "부분-리밸(점수는 fresh 유지, 하위 k개만 교체)은 **경계 churn 만 잘라내므로** 상위 신선도를 보존한 채 비용을 줄인다 — staleness 와 달리 교환이 비대칭일 수 있다",

  premise_broken = list(
    p1_churn_not_at_boundary = list(
      monthly_turnover = "12.2 / 25종 = 48.9%",
      rank_profile = "이탈 종목 직전 순위 중앙 **15.0** · 신규 진입 현재 순위 중앙 **16.0**",
      bottom_share = "이탈 중 하위권(rk>15) **48.7%** · 신규 중 하위권 **49.5%**",
      reading = "★교체가 경계에 몰려 있지 않다 — 이탈·신규 모두 약 절반만 하위권이고 **상위권에서도 절반이 갈린다**. 교체 상한은 경계 churn 만 자르는 게 아니라 상위 교체까지 막는다."),
    p2_turnover_creates_value = list(
      out_group = 0.01351, keep_group = 0.01756, new_group = 0.01729,
      new_minus_out = "+0.00378/월 = **연 +4.54%**", t = 1.048, n_months = 282L,
      reading = "★★**교체가 가치를 만든다** — 나가는 종목이 들어오는 종목보다 나빴다. 교체를 막으면 연 4.5%를 버리고 회전율 비용 몇 %를 아끼는 **불리한 거래**가 된다.",
      honesty = "t 1.048 로 유의하지 않다. 그러나 판정 근거는 유의성이 아니라 **부호가 가설과 반대**라는 것 — 가설은 '교체가 소모' 를 전제했다.")),

  turnover_axis_synthesis = list(
    staleness_FQ178 = "점수를 늙히는 축 — 회전율 11.74→3.73/yr(−68%)에 비용절감 1.20%p ≈ gross 손실 1.17%p = **1:1 교환**, paired 11셀 전부 비유의",
    partial_rebal_FQ164 = "교체를 제한하는 축 — 교체가 연 +4.54% 가치를 만들므로 **불리한 교환**",
    conclusion = "★★**M26 의 회전율 11.74/yr 는 낭비가 아니라 필요 비용**이다. 신호 수명이 짧아 자주 갈아타야 하고, 갈아타는 것이 실제로 이득이다. 회전율 축은 이 재료에서 레버가 아니다.",
    implication = "FQ-178 이 확인한 '비용 채널 +0.497 t' 는 실재하나 **회수 불가능**하다 — 두 회수 경로가 모두 닫혔다."),

  guard_first_use_log = list(
    context = "오늘 신설한 claim_state.R 의 첫 실전 사용",
    fix_1 = "구판 owner 자유 문자열 판정이 '완료 — Q-Lead session cee0bdd0' 를 놓쳐 FQ-165 중복 착수 직전까지 감 → 선언 필드 도입",
    fix_2 = "★신판이 **거울상 결함** — bare `도훈` 패턴이 'UNCLAIMED — ... 도훈 지시' 를 dohoon 으로 오분류해 착수를 막음. 원인 = ①명시 선언을 부수 언급보다 나중에 검사 ②패턴 과대. 수리 = 명시 선언 최우선 + 상태 토큰만 좁게",
    fix_3 = "★재진입 미지원 — 스크립트가 claim 을 쓴 뒤 후단에서 죽자 재실행이 **자기 claim 에 막힘**. 수리 = my_session 인자로 재진입 허용(단 complete/dohoon/blocked 는 내 것이어도 차단)",
    tests = "08_Tests/contract_regression/test_claim_state.R — 위반 주입 **36/36 PASS**(양성 대조·거울상 재현·재진입 포함)",
    lesson = "★세 번 고쳐서 작동했다. 그리고 세 결함이 각각 다른 방향(false negative → false positive → 재진입)이라 **한 방향만 시험한 테스트로는 못 잡는다**."),

  honest_caveats = c(
    "p2 의 신규−이탈 +4.54%(t 1.048)는 유의하지 않다 — '교체가 가치를 만든다' 를 확립으로 쓰지 말 것. 판정은 **가설 전제의 반대 부호** 확인이다",
    "교체군 성과 비교는 비용 미반영 gross — 실제 교체는 15bps 를 낸다. 그래도 4.54%p 대비 회전율 비용은 작다",
    "M26 단일 재료 관측 — 다른 재료에서 교체가 소모일 수 있다(FQ-090 원 질문은 챔피언 신호 대상이었다)"),

  artifacts = c("p0_claim_precheck.R", "p0_churn.csv", "p0_perf.csv"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — %s", V$verdict)

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-164")
Q$entries[[i]] <- make_claim(Q$entries[[i]], "complete", "Q-Lead 2026-08-09",
  "착수 전 폐기 — 가설 전제(교체가 소모)가 실측에서 반대로 확인됨. result_ref 참조.")
Q$entries[[i]]$status <- "aborted_premise_broken_20260809"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ164/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★착수 전 폐기 — 가설 전제가 사전 확인에서 깨졌다. ",
  "①교체가 경계에 몰려 있지 않다: 이탈 직전순위 중앙 **15.0** · 신규 현재순위 중앙 **16.0** · 하위권(rk>15) 비율 이탈 48.7%/신규 49.5% ",
  "⇒ 상위권에서도 절반이 갈리므로 교체 상한은 경계뿐 아니라 **상위 교체까지 막는다**. ",
  "②★★교체가 **가치를 만든다**: 이탈군 익월 +0.01351 vs 신규군 +0.01729, **신규−이탈 +0.00378/월 = 연 +4.54%**(t 1.048, 282개월). ",
  "교체를 막으면 연 4.5%를 버리고 회전율 비용 몇 %를 아끼는 **불리한 거래**다. ",
  "★★회전율 축 종합(FQ-178 + 본 라운드): staleness = 1:1 교환 · 부분-리밸 = 불리한 교환 ",
  "⇒ **M26 의 회전율 11.74/yr 는 낭비가 아니라 필요 비용**이다. 비용 채널(+0.497 t)은 실재하나 **회수 경로가 둘 다 닫혔다**. ",
  "⚠t 1.048 로 유의하지 않다 — 판정 근거는 유의성이 아니라 **부호가 가설과 반대**라는 것.")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 기록 · 재읽기 claim state=%s",
    claim_state(read_frontier_queue()$entries[[i]])$state)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-164", verdict_type = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "부분-리밸의 전제는 '교체가 경계에서 일어나는 소모' 인데 둘 다 틀렸다. ",
    "교체 종목의 순위 중앙이 15~16 으로 상위권에서도 절반이 갈리고, 이탈군 익월 수익이 신규군보다 연 4.54% 낮다 ",
    "— 즉 교체가 소모가 아니라 가치 창출이다. 교체 상한은 경계 churn 만 자르는 게 아니라 그 가치를 함께 자른다. ",
    "FQ-178 의 staleness(1:1 교환)와 합치면 회전율 축의 두 회수 경로가 모두 닫혔고, ",
    "M26 의 회전율 11.74/yr 는 신호 수명이 짧은 재료의 **필요 비용**으로 확정된다."),
  next_probes = c(
    "★교체 가치의 재료 의존성 — M26 은 신호 수명이 짧아(lag1 retention 0.233) 교체가 이득이었다. 수명이 긴 재료(모멘텀 등)에서는 반대일 수 있다. FQ-090 원 질문은 챔피언 신호 대상이었으므로 그쪽에서 재측정.",
    "교체 가치의 유의성 확립 — +4.54%(t 1.048)는 비유의다. 부호는 명확하나 크기를 주장하려면 검정력 보강 필요(현 n=282).",
    "비용 채널의 제3 회수 경로 — staleness·부분리밸이 닫혔다. 남은 축은 실행(체결 스케줄·시가/종가 선택)이며 이는 execution 에이전트 소관.",
    "★claim_state 배선 — 계약은 만들었고 첫 실전에서 3회 수리했으나 **다른 라운드 스크립트는 아직 안 쓴다**. 배선 없으면 dead(2026-08-08 교훈).",
    "교체 종목의 사후 성과를 신호 강도로 분해 — 이탈군이 나빴던 것이 '점수가 떨어져서' 인지 '원래 나쁜 종목' 인지 미분리."),
  consumer_surfaces = c(
    "①팩터 랭킹 — ★변화 없음이나 중요: M26 의 높은 회전율은 결함이 아니라 재료 성질. 회전율 페널티로 감점하면 안 된다",
    "②유니버스 필터 — 해당 없음",
    "③오버레이 — 해당 없음",
    "④위험모델 — 해당 없음",
    "⑤monitoring — 교체군 성과 격차(신규−이탈)를 상시 지표로 두면 신호 열화를 조기 감지 가능",
    "⑥선별 라벨 — negative 라벨: '회전율 축은 M26 에서 레버 아님(두 경로 모두 닫힘)'",
    "⑦타 모드 — 교체 가치 측정 절차를 FR·RAMP 의 회전율 논의에 이식"),
  frontier_update = "FQ-164 status=aborted_premise_broken_20260809 · claim=complete (선언 필드)",
  live_trigger = paste0("재개 조건: ①수명이 긴 재료(모멘텀 등)에서 교체가 소모로 확인될 때 ",
    "②교체 가치가 유의하게 음수인 구간·국면이 발견될 때 ③실행 축(체결 스케줄)에서 비용 회수 경로가 열릴 때. ",
    "★폐기는 **M26·이 교체 구조** 한정이며 회전율 축 일반의 판결이 아니다."),
  layer = "④construction/전이",
  evidence_refs = c("stage_artifacts/FQ164/validation.json", "stage_artifacts/FQ164/p0_perf.csv",
                    "stage_artifacts/FQ178/validation.json"))
say("=== FQ-164 종결 ===")
