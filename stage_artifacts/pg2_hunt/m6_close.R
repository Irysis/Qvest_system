## m6 — 라벨 부호 라운드 등재 + 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m6] ")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm = TRUE) + 1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★★라벨의 성질은 **부호**다 — 17종 중 무작위급 0개, 내가 나쁜 라벨이라 세 번 부른 축이 뒤집으면 1위",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state = "unclaimed", note = "2026-08-09 PG2 아크 라벨 부호 라운드"),
  ev_rationale = paste0("FQ-216 next_probe ① 실행. 무작위 대조를 원점으로 라벨 후보 17종",
    "(unified 연속축 7종 x 양방향 + jump 2종 + mega_spread)을 동일 12전략·동일 73개월·발화율 35.6% 통일로 줄 세웠다."),
  wall_check = paste0(
    "★**무작위급(|Δ|<=0.05) 0개** — 좋음 7 / 나쁨 10 으로 완전 이봉. 축은 전부 정보를 담고 **부호만 갈린다**. ",
    "1위 Regime_Score_high **-0.4679**(11/12) · Regime_Score_smooth_high -0.2964(**12/12**) · ",
    "mega_spread -0.2021(11/12) · 최하 KTRI_Score_high +0.9739(0/12). ",
    "7축 중 5축이 '국면 점수가 좋다고 할 때 보유' 방향에서 좋음(MSM_Crisis_Prob 만 양방향 실패). ",
    "★★자기정정: o1/n1/n2 에서 unified(Regime_Score **low**)를 '무작위보다 0.64 나쁜 역방향 정보' 로 ",
    "세 번 서술했는데, **같은 축을 뒤집으면 17종 1위**다 = 나쁜 라벨이 아니라 **부호를 반대로 건 좋은 축**. ",
    "여집합 아님(35.6% low/high 는 다른 꼬리). ",
    "★긴 창 확인(사전등록 falsifier 2종 고정): 216~267개월에서 개선 **12/13** · Δ vs 무작위 -0.1651 · ",
    "raw 판본도 12/13 · 귀무 창 게이트 inside 4/5 ⇒ **생존**. ",
    "★막힌 길 개통: mega_spread 73개월로는 STR_1698(2024-04 종료) 겹침 51<60 이라 **측정 불가**였는데 ",
    "Regime_Score 439개월로 243개월 측정됨 — **라벨 교체가 계열 연장(칩 task_b065b34d)보다 쌌다**. ",
    "★단 STR_1698 은 통과 아님: 점추정 ΔIR +0.0613(문턱 위)이나 **verdict_ci UNRESOLVED** ",
    "(90% CI [-0.0320, +0.1458], P(>=0.05) 57.7%) + **harness tier `unvalidated`(AX-002 차단)**. ",
    "deflation: 무처리 부족분 +0.0866 이 13전략 중 최소였고 파킹 Δ(-0.171)는 중앙(-0.117) 수준 = ",
    "**파킹이 특별한 게 아니라 출발점이 가장 좋았다**. ",
    "PIT 는 통과(간격 2일 · lag0 동월판이 오히려 최악 +0.624 = 누출 반증). ",
    "취약: lag +1 -0.085 → +2 +0.274 → +3 +0.359 = 신호 기억 ~1개월, 타이밍 여유 0."),
  next_action = paste0(
    "★next_probe(4) = ①**부호 사전등록** — 축 7종의 좋은 방향이 5/7 에서 '국면 점수 양호 시 보유' 로 ",
    "일치했다. 새 축은 **재기 전에 부호를 선언**하고 맞히는지 보면 기전 가설이 검정된다(현재는 사후 선택). ",
    "②**MSM_Crisis_Prob 만 양방향 실패** — 7축 중 유일. 이 축이 왜 정보가 없는지가 나머지 6축이 ",
    "왜 있는지를 말해줄 수 있다. ",
    "③**신호 기억 1개월의 수리** — lag+2 에서 급락한다. 평활 창을 늘리면 기억이 늘어나는가, ",
    "아니면 정보가 사라지는가(Regime_Score_smooth 는 이미 평활판인데 raw 와 12/13 동률). ",
    "④**STR_1698 하네스 적격화** — 통계는 UNRESOLVED 지만 `unvalidated` 는 통계 이전 문제다. ",
    "10-component 계약 retrofit 없이는 어떤 수치도 자본 주장이 안 된다(STR_1675 와 동일한 벽)."),
  consumer_surfaces = c("오버레이 라벨 선정", "국면 라벨 설계", "파킹 레버 인용",
                        "book-marginal 후보 평가", "screen_route 라우팅"),
  revival_condition = "새 라벨/축 확보 시 무작위 대조 원점 + 양방향 동시 측정 의무 · STR_1698 retrofit 완료 시 재측정",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_LABEL_SIGN_20260809",
  verdict_type = "capability_established",
  layer = "method",
  mechanism_diagnosis = paste0(
    "라벨 17종을 동일 12전략·동일 창·동일 발화율에서 무작위 대조 원점으로 줄 세웠다. ",
    "무작위급이 **0개**이고 좋음 7 / 나쁨 10 으로 완전히 이봉이다 — 축은 전부 정보를 담고 있고 ",
    "**갈리는 것은 부호뿐**이다. 이것이 어제부터의 파킹 서술을 마지막으로 교정한다: ",
    "'unified 는 무작위보다 나쁜 라벨' 이 아니라 **내가 부호를 반대로 걸었던 좋은 축**이었다 ",
    "(Regime_Score_high -0.4679 = 17종 1위 vs Regime_Score_low +0.6524 = 최하위권, 같은 축). ",
    "긴 창(216~267개월)에서 12/13 생존하고 귀무 창 게이트 inside 4/5 다. ",
    "★부수 성과: 라벨 교체가 **계열 연장보다 쌌다** — mega_spread 73개월로는 겹침 51<60 이라 ",
    "측정 자체가 불가했던 STR_1698 이 Regime_Score(439개월)로는 243개월 측정된다. ",
    "★그러나 통과는 아니다: verdict_ci UNRESOLVED(CI 가 0 을 포함) + harness `unvalidated`(AX-002). ",
    "그리고 정직한 deflation — 그 전략은 무처리 부족분이 13종 중 최소였고 파킹 이득은 중앙 수준이라 ",
    "**파킹이 특별한 게 아니라 출발점이 좋았다**. ",
    "★측정면 결함 1건 수리: 없는 리스트 필드 → numeric(0) → sprintf character(0) → cat 이 ",
    "**보고 줄을 통째로 삭제**(오류·경고 없음). 귀무 게이트가 두 스크립트 연속 침묵한 원인이 이것이었고 ",
    "나는 두 번 다 subsample_null 쪽을 의심했다. report_guard.R + 위반주입 24/24 로 못박음."),
  next_probes = c(
    "부호 사전등록 — 7축 중 5축이 '국면 점수 양호 시 보유' 로 일치. 새 축은 재기 전에 부호를 선언해 기전 가설을 검정",
    "MSM_Crisis_Prob 만 양방향 실패한 이유 — 유일한 예외가 나머지 6축이 왜 작동하는지를 말해줄 수 있다",
    "신호 기억 1개월의 수리 — lag+2 에서 급락(-0.085→+0.274). 평활 창 확장이 기억을 늘리는가 정보를 지우는가",
    "STR_1698 하네스 적격화 — `unvalidated` 는 통계 이전 문제. retrofit 없이는 어떤 수치도 자본 주장 불가"),
  consumer_surfaces = c("오버레이 라벨 선정", "국면 라벨 설계", "파킹 레버 인용",
                        "book-marginal 후보 평가", "다음 세션 인수인계"),
  frontier_update = sprintf("%s 등재 · 메모리 카드 2건 신규 + 파킹 카드 정정 · report_guard 계약 신설", nid),
  live_trigger = "새 라벨은 **양방향 동시**로 재고 무작위 대조를 원점으로 삼는다 · 나쁘게 나오면 버리기 전에 반전판 측정",
  evidence_refs = c("stage_artifacts/pg2_hunt/m1_label_ranking.csv",
                    "stage_artifacts/pg2_hunt/m2_long_window.csv",
                    "stage_artifacts/pg2_hunt/m3_adversarial.rds",
                    "08_Tests/contract_regression/test_report_guard.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
