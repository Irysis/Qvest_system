## c4 — 원장 등재 + 병목 지도 갱신 (PG2 사냥 라운드 중간 수집)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[c4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-\\d+$", ids)])))
nx <- max(nums, na.rm = TRUE)

mk <- function(id, title, ev, wall, na, cs, rc) list(
  id = id, title = title, status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state = "complete", session = "832fa2fc", note = "PG2 사냥 라운드 2026-08-09 수집"),
  ev_rationale = ev, wall_check = wall, next_action = na,
  consumer_surfaces = cs, revival_condition = rc, created = "2026-08-09")

E <- list()
E[[1]] <- mk(sprintf("FQ-%03d", nx+1L),
  "★admission 문턱 ΔIR>=0.05 가 측정 해상도 아래 — 판정에 CI 병기 의무",
  paste0("도훈 지시('PG2 를 이길 전략 발견')로 book-marginal 측정 배관을 세우던 중 발견. ",
    "문턱이 표준오차보다 작으면 어떤 후보도 '통과' 를 신뢰할 수 없다 — 게이트 설계 수준 문제다."),
  paste0("블록부트(block=12) ΔIR 표준오차: 73개월 0.0935 / 108개월 0.0760 / 200개월 0.0565 / ",
    "**269개월(전기간) 0.0460** → 문턱 0.05 는 전기간에서도 **1.09 표준오차**. ",
    "2se 판별 필요 표본 ~**911개월(75.9년)** = 가용치 3.4배. rho/IR 을 바꿔도 0.92~1.30 범위로 불변. ",
    "★★비대칭 = **탈락 판정은 유효**(48재료 중앙 -0.1888 은 문턱에서 5.2se 밖) **통과 판정만 무효**."),
  paste0("완료 = 계약 `bm_delta_ir()` 에 `delta_ir_ci` + **`verdict_ci`** 신설(CI하단>=0.05 → BEATS_PG2 / ",
    "상단<0 → NO_IMPROVEMENT / 상단<0.05 → BELOW_THRESHOLD / 그 외 **UNRESOLVED**). ",
    "`bm_delta_ir_sweep()` 의 beats 를 CI 하단 기준으로 전환하고 beats_point 분리. ",
    "검사 `08_Tests/contract_regression/test_book_marginal_ci.R` **15/15**(위반 주입이 실사고 재현: ",
    "점추정 0.0500 통과 ∧ CI [-0.0168, 0.1229] → UNRESOLVED · 양성 대조 보존 확인). ",
    "★next_probe(2) = ①**도훈 판단 필요** — §4 문턱 서술에 CI 병기를 명문화할지(문턱 인하 아님, INV-7 준수). ",
    "②`portfolio_governor.R::pg1_admission_with_book_context()` 가 점추정으로 admit 판정하는지 배선 실측 — ",
    "그렇다면 같은 계통이 자본 게이트에 남아 있다."),
  c("book-marginal admission 판정", "governor PG1", "FQ wall_check 의 ΔIR 인용", "병목지도 자본 행"),
  "표본이 900개월대에 도달하거나, 문턱을 CI 하단 기준으로 재정의하는 도훈 결정이 있으면 재판정")

E[[2]] <- mk(sprintf("FQ-%03d", nx+2L),
  "★PG2 를 이기는 조건의 정량 지도 + 팩터DB 전면 부족 (부족분 중앙 1.063)",
  paste0("도훈 지시. '무엇을 찾아야 하는가' 를 닫힌 형태로 풀어 사냥의 표적을 정의했다."),
  paste0("해석해(시뮬과 5자리 일치): ΔIR>=0.05 필요 최소 슬리브IR = 상관 0.0 **0.380** / 0.2 0.659 / ",
    "0.4 **0.925** / 0.6 1.181 / 0.8 1.428. 최적 w **0.20~0.30**(더 키워도 개선 없음). ",
    "기전 대조: 무상관+IR동등 ΔIR **+0.3012** / 상관1.0 **0.0000** / 잡음 -0.0823 ⇒ **직교성이 유일 레버**. ",
    "★팩터DB 48재료 등간격 표본: 상관 중앙 **0.402**(0.2 미만 **0건**) · 슬리브IR 중앙 **-0.100**(0.5 초과 0건) ",
    "· ΔIR **0/48 양수** · 중앙 -0.1888 · **부족분 중앙 1.063**. ",
    "사망 기전 = 상관과 IR 이 **동시에** 부족(둘 다 만족 0/48)."),
  paste0("완료 = 요구조건 지도 산출 + 48표본 실측 + 정렬 확정(candidate month +2, 4중 증거). ",
    "★진행 중 = 331 전수 사냥(워크플로 wf_8c401997-47a, 8샤드 x 2-arm). ",
    "★next_probe(3) = ①**조합 축** — 서로 직교인 팩터 스택. ⚠단 착수 전 검정력 선언이 ",
    "OOS 108개월 se 0.077 로 자기 기각했다(사전등록 `combo_preregistration.json` 보존). ",
    "전기간 269개월 창으로 재설계하거나 구간추정 라운드로 라벨해야 착수 가능. ",
    "②**비-return 원천** — 계약 신호가 유일하게 근접한 이유가 IR 0.758 이었다면 DART insider·공매도/대차도 재라. ",
    "③파킹 라벨 대안 — FQ-191 라벨 말고 다른 국면 라벨로 상관을 더 낮출 수 있는가."),
  c("알파 재료 선별 기준", "FQ 큐 우선순위", "병목지도 재료 행", "book-marginal 후보 사전 여과"),
  "팩터DB 에 슬리브IR 0.9 이상 재료가 새로 들어오거나, 상관 0.2 미만을 만드는 구성이 발견되면 재도전")

E[[3]] <- mk(sprintf("FQ-%03d", nx+3L),
  "★조건부 파킹 = 상관을 낮추는 검증된 일반 레버 (단 재료 IR 부족은 못 고침)",
  paste0("계약 국면규칙이 상관을 0.564→0.140 으로 낮춰 문턱을 1.135→0.576 으로 41% 내린 것을 관찰. ",
    "이것이 계약 고유인지 일반 레버인지 DB 재료로 검정했다."),
  paste0("48재료 3-arm(무조건부/국면라벨/무작위파킹 30회), 전부 동일 73개월 창: ",
    "①상관 인하 +0.405→+0.317 (paired t **-6.983** p<0.00001, 37/48) ",
    "②ΔIR 개선 **48/48 전건** 중앙 +0.1223 (paired t +14.125) ",
    "③무작위 파킹 대비 우월 (paired t **+4.075** p 0.00018 · 95백분위 초과 **12.5%** vs 귀무 5%) ",
    "⇒ **일반 레버 확인**. ★그러나 파킹 적용 후에도 문턱 통과 **0/48** — 재료 IR 부족이 지배한다."),
  paste0("★next_probe(2) = ①**파킹 라벨의 정보 출처 규명** — FQ-191 라벨은 계약 mega_spread 기반인데 ",
    "왜 무관한 DB 재료에도 무작위 이상으로 작동하나(시장 국면 성분? 12.5% 가 어디서 오나). ",
    "귀무 5% 대비 2.5배는 작지만 유의하다. ②**파킹 강도 최적화** — ON 비율 35.6% 가 최적인가, ",
    "발화율을 바꾸면 상관 인하와 신호 손실이 어떻게 교환되나(오늘 확립: 노출 floor 0.80까지 방어는 평평)."),
  c("오버레이 설계", "국면 라벨 소비면", "슬리브 상관 인하 도구", "book-marginal 후보 개선"),
  "새 국면 라벨이 등장하거나, 파킹 후 슬리브IR 0.9 이상 재료가 나오면 재측정")

for (e in E) Q$entries[[length(Q$entries)+1L]] <- e
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("원장: %d → %d (신규 %d · 순수추가 %s)", n0, length(Q2$entries), length(E),
    length(Q2$entries) == n0 + length(E))
for (e in E) say("  등재 %s — %s", e$id, substr(e$title, 1, 56))

## 병목 지도
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v56 ("
if (length(gregexpr(anchor, txt, fixed=TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v57 (★★**도훈 지시 'PG2 를 이길 전략' 라운드 — 자본 행 귀속 재정의**[pg2_hunt]. ",
    "①**base 확보**: FQ-165/194 가 벽으로 본 `book_state.json` 부재는 벽이 아니었다 — production ",
    "`2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results` 에 10-component 전량 존재, IR **1.4160** 계약 재현(차 +0.000026). ",
    "②★**기전**: ΔIR 은 **분산 효과로만** 오른다 — 무상관+IR동등 **+0.3012** / 상관1.0 **0.0000** / 잡음 -0.0823. ",
    "**더 센 알파가 아니라 직교한 알파**가 표적. 요구조건 지도(해석해·시뮬 5자리 일치): 필요 최소 슬리브IR = ",
    "상관0.0 0.380 / **0.4 0.925** / 0.8 1.428, 최적 w 0.20~0.30. ",
    "③**재료 행**: 팩터DB 48표본 ΔIR **0/48 양수**, 상관 중앙 0.402(0.2 미만 0건)·슬리브IR 중앙 -0.100(0.5 초과 0건), ",
    "**부족분 중앙 1.063** — 상관과 IR 이 **동시에** 부족(둘 다 만족 0/48). ",
    "④**방법 행**: 조건부 파킹이 상관을 낮추는 **검증된 일반 레버**(48/48 개선 t+14.1 · 무작위 대비 t+4.08 p0.0002) ",
    "이나 파킹 후에도 통과 0/48 ⇒ **★병목은 방법이 아니라 재료**(v8.3 비-return 방향 정량 뒷받침). ",
    "⑤★★**측정 행 신규 — 문턱이 해상도 아래**: ΔIR 블록부트 se 가 **269개월 전기간에서도 0.0460** 이라 ",
    "문턱 0.05 는 1.09se, 2se 판별에 **911개월(76년)** 필요. **탈락 판정은 유효(5.2se 밖)·통과 판정만 무효**인 비대칭. ",
    "문턱 인하 아님(INV-7) — 계약 `bm_delta_ir()` 에 `verdict_ci` 신설로 **CI 병기**(검사 15/15, 위반 주입이 실사고 재현). ",
    "⑥**후보**: 계약수주 국면규칙 슬리브 상관 0.140·슬리브IR 0.758·ΔIR +0.0740, 귀무 3종 통과 ",
    "(타이밍 p0.036/셔플 p0.000/블록 p0.026) — 단 **CI 기준 통과 1/5**(w0.30 만 CI하단 +0.0662), ",
    "73개월·에피소드 14 ⇒ **UNRESOLVED, 오버레이 후보 + 증거 누적 대기**. 자본 편입 아님(governor 수동). ",
    "⑦부수 결손: PG2 `04_holdings.csv` **0행**(칩 task_be236d0c) · 정렬 offset candidate month **+2**(4중 증거). ",
    "상세 = `stage_artifacts/pg2_hunt/`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  ob <- charToRaw(enc2utf8(txt2)); writeBin(ob, mp)
  r2 <- readBin(mp, "raw", file.size(mp))
  say("지도 v57: %d → %d바이트 · CR %d(원 %d) · v57 %s · v56 보존 %s",
      length(raw), length(ob), sum(r2==as.raw(13)), sum(raw==as.raw(13)),
      grepl("v57", rawToChar(r2), fixed=TRUE), grepl("v56 (", rawToChar(r2), fixed=TRUE))
} else say("★지도 앵커 불일치 — 건너뜀")
say("=== c4 완료 ===")
