## w3 — 계약 특이성 7후보 기각 등재 + proxy_axis 계약 등재 + 라운드 종료
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[w3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nx <- max(nums, na.rm=TRUE)
mk <- function(id, title, ev, wall, na, cs, rc) list(
  id=id, title=title, status="frontier_open", owner="Q-Lead session 832fa2fc",
  claim=list(state="complete", session="832fa2fc", note="PG2 특이성 아크 2026-08-09"),
  ev_rationale=ev, wall_check=wall, next_action=na,
  consumer_surfaces=cs, revival_condition=rc, created="2026-08-09")

E <- list()
E[[1]] <- mk(sprintf("FQ-%03d", nx+1L),
  "★★계약 ON월 직교성 — 설명 후보 **7종 전건 기각**, 현상은 남음 (미해명 등재)",
  paste0("331 전수 통과 0 인 가운데 계약+mega_spread 만 ON월 rho +0.186(무작위 대비 백분위 0%)로 ",
    "직교했다. 이것이 무엇 때문인지 규명하려 후보를 하나씩 실측 기각했다."),
  paste0("★기각된 설명 7종(전부 실측): ",
    "①**순환** — mega_spread 는 `mean(ret_1m[top10]) − median(ret_1m)` = 시장 수익률(FQ138/p1_measure.R:53), 계약 데이터 아님. ",
    "②**교락(PG2 순풍)** — ON 더미 회귀 잔차 rho **+0.186** 로 소수3자리 불변. ",
    "③**표본 잡음** — 블록부트 CI **[−0.024, +0.210]** 가 무작위 중앙 0.399 미포함, leave-one-out 최대 이동 0.119. ",
    "④**유니버스 아티팩트** — 계약유니버스 무작위 rho 0.273 ≈ 전체유니버스 무작위 0.277. ",
    "⑤**발화율(희석)** — 71.7→50→35→20% 로 조여도 백분위 20→19→14→26%, 계약 0% 에 접근 안 함(spearman −0.200). ",
    "⑥**경제적 동조** — 계약 신호 총량 vs mega_spread spearman **−0.139~+0.103**(동시·lead1·lag1 전부 |0.3| 미만). ",
    "⑦**국면-적응성** — ON/OFF 보유 Jaccard **0.898**, 전환 시 인접 Jaccard 0.887 — 타 재료 중앙(0.897/0.886)과 소수3자리 동일. ",
    "★재구성 양성 대조 통과(계약 period_returns 대비 상관 **0.999998**)이므로 ⑦ 측정은 유효. ",
    "★이식도 실패(0/24) — 다른 (라벨,재료) 쌍이 이 현상을 재현하지 못한다. ",
    "⇒ **현상은 실재하고 설명은 없다.** 미해명으로 등재한다(억지 설명 금지)."),
  paste0("★next_probe(3) = ①**미검 후보 열거 재개** — 남은 축: ⓒ계약 신호의 **결측 구조**(공시가 없는 달의 ",
    "종목 구성 변화) ⓓ**타이밍 정렬**(공시→수익 시차가 국면별로 다른가) ⓔ**신호 분포 형태**(ON월에 ",
    "score 분포가 달라 top-25 컷이 다른 성격의 종목을 뽑는가). ⓔ가 가장 싸다 — 월별 score 분위 프로파일 비교. ",
    "②**계약 창 확장** — 79개월뿐이라 어떤 설명도 검정력이 낮다. 2019-12 이전 공시 데이터 확보 가능성 확인. ",
    "③**현상 자체의 재현성** — 다른 incumbent(PG2 아닌 book)에 대해서도 ON월 직교가 나타나는가. ",
    "PG2 고유면 '계약 vs PG2' 쌍의 성질이고, 아니면 계약 신호의 성질이다."),
  c("계약 후보 평가", "국면 라벨 설계", "book-marginal 후보", "미해명 현상 추적"),
  "설명 후보 ⓒⓓⓔ 중 하나가 지지되거나, 계약 창이 확장돼 검정력이 붙으면 재개")

E[[2]] <- mk(sprintf("FQ-%03d", nx+2L),
  "★대리 축 재현 계약 신설 — 오늘 3연속 오류의 뿌리를 기계로 차단",
  paste0("한 아크에서 같은 축으로 3번 틀렸다: ①한 이름만 조회하고 '수치 컬럼 부재' 결론(실제 7개) ",
    "②대리 축 방향 미확인(phi −0.394) ③`setorder(-phi)` 에서 NA 가 최대처럼 정렬돼 완벽한 축(phi 1.000)을 놓칠 뻔. ",
    "셋 다 정체 검사 생략이고, 잡아준 것은 규약이 아니라 **자기모순 관측**이었다."),
  paste0("★핵심 오독: **발화율을 맞추는 것은 재현이 아니다** — 같은 비율로 다른 달을 고를 수 있다. ",
    "실측: 발화율 71.7% 를 정확히 맞췄는데 월 일치율 **43.5%**(무작위 기대 59.5% **보다 낮음**). ",
    "★계약 `02_Infrastructure/contracts/proxy_axis.R` 신설 — `proxy_numeric_axes()`(전수 열거) · ",
    "`proxy_reproduction()`(일치율·phi·Jaccard + **무작위 기대 p²+(1−p)²** 병기) · ",
    "`proxy_select_axis()`(축×방향 전수 + **NA 안전 정렬**) · `assert_proxy_reproduces()`(미달 시 stop). ",
    "검사 `08_Tests/contract_regression/test_proxy_axis.R` **21/21** — ",
    "위반 주입이 실사고를 **수치까지 재현**(방향 오류 시 일치 43.5% vs 기대 59.5%), ",
    "발화율만 맞춘 무관 축은 초과 +0.4%p 로 거부."),
  paste0("★next_probe(2) = ①**소비자 배선** — 대리 축을 쓰는 기존 지점을 찾아 `assert_proxy_reproduces()` 를 ",
    "걸어라(오늘 확인한 '표준은 있는데 소비자 0' 계통 재발 방지). 후보 = 국면 라벨 소비처·overlay 신호·screen_route. ",
    "②**`canonical_screen_bt` holdings 공백** — 이 헬퍼는 holdings 를 산출하지 않아 필터·겹침 분석이 불가하다. ",
    "매번 선별을 재구성하고 양성 대조로 검증해야 한다(이번엔 상관 0.999998 통과). ",
    "소비면 7종 순회가 의무인데 그 배관이 없는 셈 — 진단용 holdings 필드 추가를 검토."),
  c("대리 축 사용 전반", "국면 라벨 소비처", "overlay 신호 설계", "계약 검사 배터리"),
  "대리 축을 쓰는 새 라운드가 열리면 이 계약 통과 의무")

for (e in E) Q$entries[[length(Q$entries)+1L]] <- e
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d (신규 %d)", n0, length(read_frontier_queue()$entries), length(E))
for (e in E) say("  등재 %s — %s", e$id, substr(e$title, 1, 52))

r <- close_round(
  round_id = "PG2_SPECIFICITY_20260809",
  verdict_type = "ceiling_reached_frontier_open",
  layer = "material",
  mechanism_diagnosis = paste0(
    "계약+mega_spread 의 ON월 직교성(rho +0.186, 무작위 대비 백분위 0%)에 대해 ",
    "설명 후보 **7종을 차례로 실측 기각**했다: 순환·교락·표본잡음·유니버스아티팩트·발화율희석·경제적동조·국면적응성. ",
    "각 기각은 대조군을 갖춘 직접 측정이며(순풍 제거 후 rho 소수3자리 불변 · 블록부트 CI 가 무작위 중앙 미포함 · ",
    "계약유니버스 무작위 0.273 ≈ 전체 0.277 · 발화율 궤적 spearman −0.200 · 총량 spearman |0.3| 미만 · ",
    "보유 Jaccard 0.898 vs 타재료 0.897), 재구성 경로는 양성 대조(상관 0.999998)로 검증했다. ",
    "이식도 0/24 로 실패했다. ⇒ **현상은 실재하고 설명은 없다.** 억지 설명을 만들지 않고 미해명으로 등재한다. ",
    "★부수: 이 아크에서 Q-Lead 오류 3연속(정체 검사 생략)이 났고 그 뿌리를 계약 `proxy_axis.R`(검사 21/21)로 막았다. ",
    "★부수2: `canonical_screen_bt` 가 holdings 를 산출하지 않아 소비면 분석에 매번 선별 재구성+검증이 필요하다."),
  next_probes = c(
    "미검 설명 후보 ⓔ 신호 분포 형태 — ON월에 score 분포가 달라 top-25 컷이 다른 성격의 종목을 뽑는가. 월별 분위 프로파일 비교로 가장 싸게 측정 가능",
    "미검 설명 후보 ⓒⓓ — 계약 신호의 결측 구조(공시 없는 달의 구성 변화) · 공시→수익 시차가 국면별로 다른가",
    "현상의 incumbent-의존성 — PG2 아닌 다른 book 에 대해서도 ON월 직교가 나타나는가. PG2 고유면 '쌍의 성질', 아니면 '신호의 성질'",
    "계약 창 확장 — 79개월뿐이라 어떤 설명도 검정력이 낮다. 2019-12 이전 공시 데이터 확보 가능성 확인",
    "proxy_axis 계약의 소비자 배선 — 대리 축을 쓰는 기존 지점에 assert 를 걸어라('표준은 있는데 소비자 0' 재발 방지)"),
  consumer_surfaces = c("계약 후보 평가", "국면 라벨 설계", "대리 축 사용 전반",
    "book-marginal 후보 평가", "계약 검사 배터리"),
  frontier_update = sprintf("FQ-%03d/%03d 등재 · 원장 213항목 · proxy_axis.R 계약 신설(21/21)", nx+1L, nx+2L),
  live_trigger = "설명 후보 ⓒⓓⓔ 중 하나가 지지되거나 계약 창이 확장되면 재개. 그 전까지 계약 후보는 '현상 실재·설명 미해명' 라벨로 인용",
  evidence_refs = c("stage_artifacts/pg2_hunt/w1_specificity.R", "stage_artifacts/pg2_hunt/w2_adaptivity.csv",
    "stage_artifacts/pg2_hunt/y2_confound.R", "stage_artifacts/pg2_hunt/z4_dilution.csv",
    "02_Infrastructure/contracts/proxy_axis.R", "08_Tests/contract_regression/test_proxy_axis.R"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
