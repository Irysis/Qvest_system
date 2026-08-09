## w6 — 재규정 등재 + 아크 최종 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[w6] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

CORE <- paste0(
  "★★★재규정(2026-08-09 w4/w5 실측): '계약+mega_spread 가 특이 쌍' 서술을 **정도 차이로 약화**한다. ",
  "①ON월 상관 하락은 **전 재료 공통**이다 — 계약 Δrho −0.183 · V18_AM −0.175 · R17/V19 −0.153 · L11 −0.116 ",
  "(cov 비율 계약 0.386 vs V18 0.394). 계약은 가장 크지만 정도 차이다. ",
  "⇒ 백분위 0% 는 '유일하게 직교' 가 아니라 **자기 분포 대비 가장 낮음**이고, 이식 실패(0/24)와 정합한다 ",
  "(다른 재료도 같은 방향인데 1급이 절대 수준 아닌 자기 분포 기준이었다). ",
  "②선별은 국면 무관 — ON/OFF 보유 Jaccard **0.898**(타 재료 0.897), 보유 size 백분위 차 **정확히 0.0000**(p 1.000). ",
  "같은 종목을 담는데 상관이 갈리므로 원인은 선별이 아니라 **동조**다. ",
  "③횡단 분산 가설 **방향 반대로 기각** — ON 월 횡단 sd 0.1479 < OFF 0.1629(t −2.375, p 0.021). ",
  "분산이 커져 덜 닮는 게 아니라 수렴 구간인데 상관이 떨어진다. ",
  "④★★**라벨에 예측력이 없다** — cor(ms_t, PG2 active_t) **−0.405**(소형편향 해석 정합)인데 ",
  "FQ-138 이 쓴 t-1 FROZEN 판본은 cor(ms_{t-1}, active_t) **−0.015**. 대형-소형 축은 지속성이 없다. ",
  "★정렬·PIT 검증 통과(FQ-191 라벨 ↔ 직접 산출 t-1 판본 **일치 100.0%**). ",
  "⇒ ON 월 = '대형이 진 달의 **다음** 달' 이고 그 축은 다음 달 구조를 거의 예측하지 못한다. ",
  "**예측력 없는 라벨 위에서 계약 재료가 IR 0.758 을 냈다**는 것이 남은 사실이다.")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries); hit <- 0L
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% c("FQ-206","FQ-208")) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORE)
    hit <- hit + 1L; say("재규정 기입 %s", ids[k])
  }
}
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★새 질문 — '왜 ON월에는 모든 슬리브가 북과 덜 움직이나' (계약 특이성에서 일반 현상으로)",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state = "unclaimed", note = "2026-08-09 아크가 질문을 이 형태로 좁혀 남김"),
  ev_rationale = paste0("w4 가 ON월 상관 하락을 **전 재료 공통**으로 확정했다(Δrho −0.116~−0.183). ",
    "'계약이 왜 특별한가' 는 잘못된 질문이었고, 답을 찾으면 **모든 재료에 적용되는 레버**가 된다."),
  wall_check = paste0("확립: ①전 재료 공통 하락 ②선별 무관(보유 Jaccard 0.898·size 차 0.0000) ",
    "③횡단 분산 가설 방향 반대 기각(ON sd 0.1479 < OFF 0.1629) ④라벨 예측력 없음(t-1 상관 −0.015) ",
    "⑤설명 후보 7종 전건 기각. **현상 실재·설명 미해명**."),
  next_action = paste0("★next_probe(4) = ",
    "①**cov 분해** — active_i·active_s 를 공통 요인(시장·size·모멘텀)과 잔차로 회귀 분해해 ",
    "ON월에 **어느 성분의 공분산이 줄어드는지** 귀속. 지금은 총 cov 만 봤다(0.386배). ",
    "②**무작위 26개월 부분집합 대조** — t-1 라벨에 예측력이 없다면 ON 26개월은 준-무작위 부분집합에 가깝다. ",
    "무작위 26개월 1000회에서 Δrho 분포를 만들어 계약의 −0.183 이 그 분포 안인지 확인. ",
    "★이것이 가장 결정적이다 — 분포 안이면 **현상 자체가 표본 산물**이다. ",
    "③**다른 incumbent 대조** — PG2 아닌 book(예: STR_1631)에서도 같은 ON월 하락이 나타나는가. ",
    "PG2 고유면 '쌍의 성질', 아니면 시장 구조. ",
    "④x2/x9 의 두 대조가 갈린 이유 — 무작위 **타이밍** 대비 백분위 15% vs 무작위 **신호** 대비 0%. ",
    "이 비대칭이 무엇을 뜻하는지 규명(신호가 특별한가, 타이밍이 특별한가)."),
  consumer_surfaces = c("국면 라벨 설계", "book-marginal 후보 평가", "오버레이 설계", "미해명 현상 추적"),
  revival_condition = "①~④ 중 하나가 답을 주면 즉시 재개 — 특히 ②가 '분포 안' 이면 이 아크 전체가 표본 산물로 재분류된다",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재 · 재규정 %d건", n0, length(read_frontier_queue()$entries), nid, hit)

r <- close_round(
  round_id = "PG2_REFRAME_20260809",
  verdict_type = "ceiling_reached_frontier_open",
  layer = "material",
  mechanism_diagnosis = paste0(
    "계약 특이성을 파고들다 **질문 자체가 틀렸음**을 실측으로 확인했다. ON월 상관 하락은 계약 고유가 아니라 ",
    "**전 재료 공통**이고(Δrho −0.116~−0.183, 계약이 최대일 뿐), 선별은 국면과 무관하며(보유 Jaccard 0.898, ",
    "size 차 0.0000), 횡단 분산 가설은 방향이 반대로 기각됐다(ON sd 0.1479 < OFF 0.1629). ",
    "★그리고 라벨 자체에 예측력이 없다 — 동시 상관 −0.405 인 대형-소형 축이 t-1 로는 −0.015 로 사라진다. ",
    "정렬·PIT 는 검증 통과(직접 산출 t-1 판본과 일치 100.0%). ",
    "⇒ 질문이 '계약이 왜 특별한가' 에서 **'왜 ON월에는 모든 슬리브가 북과 덜 움직이나'** 로 바뀐다. ",
    "이건 훨씬 일반적이고 답을 찾으면 레버가 된다. 가장 결정적인 다음 검정은 ",
    "**무작위 26개월 부분집합 1000회 대조** — 계약의 Δrho −0.183 이 그 분포 안이면 현상 자체가 표본 산물이다."),
  next_probes = c(
    "★무작위 26개월 부분집합 1000회로 Δrho 귀무분포 산출 — 계약의 −0.183 이 분포 안이면 이 아크 전체가 표본 산물로 재분류. 가장 결정적이고 가장 싸다",
    "cov 분해 — active 를 공통 요인(시장·size·모멘텀)과 잔차로 나눠 ON월에 어느 성분의 공분산이 줄어드는지 귀속. 지금은 총 cov(0.386배)만 안다",
    "다른 incumbent 대조 — PG2 아닌 book 에서도 같은 ON월 하락이 나타나는가. PG2 고유면 '쌍의 성질', 아니면 시장 구조",
    "x2/x9 두 대조가 갈린 이유 — 무작위 타이밍 대비 백분위 15% vs 무작위 신호 대비 0%. 이 비대칭의 의미 규명"),
  consumer_surfaces = c("국면 라벨 설계", "book-marginal 후보 평가", "오버레이 설계",
    "미해명 현상 추적", "다음 세션 인수인계"),
  frontier_update = sprintf("%s 등재(UNCLAIMED) · FQ-206/208 재규정 · 원장 214항목", nid),
  live_trigger = "무작위 부분집합 대조가 '분포 안' 이면 계약 후보를 표본 산물로 재분류 · '분포 밖' 이면 현상 확정 후 cov 분해로 진행",
  evidence_refs = c("stage_artifacts/pg2_hunt/w4_comovement.csv", "stage_artifacts/pg2_hunt/w5_regime_sanity.R",
    "stage_artifacts/pg2_hunt/w2_adaptivity.csv", "stage_artifacts/pg2_hunt/x9_circularity.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
