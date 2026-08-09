## n2 — 파킹 분해 등재 + 최종 종료
## ★초판은 Bash heredoc 으로 썼다가 `\\d` 가 `\d` 로 먹혀 파싱 에러 —
##   메모리 카드 [[feedback-regex-word-boundary-silent-false]] 가 "이스케이프 스크립트는 Write 로" 라고
##   명시해둔 함정을 그대로 밟았다. 지식으로는 안 막힌다.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[n2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm = TRUE) + 1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★파킹 이득 분해 확정 — 구조 58% + 라벨정보 42%, 발화율 무관, 나쁜 라벨은 무작위보다 나쁘다",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state = "unclaimed", note = "2026-08-09 PG2 아크 최종 분해"),
  ev_rationale = paste0("파킹을 하루 종일 '일반 레버' → '(라벨,재료) 조건부' → '라벨이 전부' 로 세 번 서술했다. ",
    "L1(35.6%)과 L2(82.2%)가 발화율·선별 둘 다 달라 교락돼 있었으므로 4-arm 으로 갈랐다."),
  wall_check = paste0(
    "★12전략 x 4-arm(동일 73개월 창): L1 mega_spread(35.6%) 개선 **11/12** Δ중앙 **-0.4725** / ",
    "L2 unified(71.2%) 1/12 +0.6752 / **L2' unified(35.6%, 발화율 정합) 2/12 +0.3708** / ",
    "**rnd 무작위(35.6%) 11/12 -0.2720**. ",
    "①**발화율은 결정 변수 아님** — unified 를 35.6%로 조여도 2/12 실패 ⇒ **선별의 질**이 가른다. ",
    "②**구조 효과 실재** — 무작위 라벨도 11/12 개선. '적게 보유' 자체가 부족분을 줄인다. ",
    "③**라벨 정보가 그 위에** — L1 vs 무작위 Δ중앙 -0.202, L1 이 더 좋은 전략 11/12. ",
    "⇒ 파킹 이득의 **약 58%가 구조 · 42%가 라벨 정보**. ",
    "④★**unified 는 무작위보다도 나쁘다**(+0.371 vs -0.272, 0.64 차) = **역방향 정보**(좋은 달을 OFF 로 찍는다). ",
    "⇒ 좋은 라벨과 나쁜 라벨이 **무작위를 사이에 두고** 갈린다. **라벨 평가의 원점은 무작위 대조**다."),
  next_action = paste0(
    "★next_probe(4) = ①**좋은 라벨의 공통 성질** — mega_spread 는 무작위보다 0.202 낫고 unified 는 0.64 나쁘다. ",
    "라벨 후보를 더 넣어(jump_JM_State·β_R05·vol-state) '무작위 대비 부호' 로 줄 세우면 성질이 보인다. ",
    "②**구조 효과의 한계** — 무작위 파킹만으로 Δ-0.272 다. 발화율을 더 낮추면 구조 효과가 커지는가, ",
    "아니면 노출 손실이 이기는가(오늘 regime 오버레이 라운드는 노출 floor 0.80까지 방어가 평평했다). ",
    "③**unified 역방향의 소비** — 역방향 정보도 정보다. OFF 월 보유(반전)를 unified 로 재시도. ",
    "★단 jump_JM_State 반전은 이미 기각됐다(무작위 대비 0/8) — 같은 함정 주의. ",
    "④STR_1698 계열 연장 후 mega_spread 파킹(칩 task_b065b34d) — 라벨 적합성 11/12 확인됨."),
  consumer_surfaces = c("오버레이 라벨 선정", "파킹 레버 인용", "국면 라벨 설계", "book-marginal 후보 평가"),
  revival_condition = "새 라벨 확보 시 무작위 대조 원점으로 즉시 줄 세우기 · STR_1698 연장 시 즉시 적용",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

r <- close_round(
  round_id = "PG2_PARKING_DECOMPOSITION_20260809",
  verdict_type = "capability_established",
  layer = "method",
  mechanism_diagnosis = paste0(
    "파킹 이득을 구조와 라벨정보로 분해했다. 12전략 4-arm(동일 창): ",
    "무작위 라벨도 11/12 개선(-0.272)하므로 '적게 보유' 자체가 효과이고, ",
    "mega_spread 는 그보다 0.202 더 좋다(-0.4725, 11/12) — 라벨 정보가 그 위에 얹힌다. ",
    "발화율을 맞춘 unified(L2', 35.6%)는 여전히 2/12 실패하므로 발화율은 결정 변수가 아니라 **선별의 질**이 가른다. ",
    "★unified 는 무작위보다도 0.64 나쁘다 = 역방향 정보(좋은 달을 OFF 로 찍는다). ",
    "⇒ 좋은 라벨과 나쁜 라벨이 무작위를 사이에 두고 갈리며, **라벨 평가의 원점은 무작위 대조**다. ",
    "★이것으로 오늘 세 번 바뀐 파킹 서술이 완결된다: '일반 레버' → '(라벨,재료) 조건부' → '라벨이 전부' → ",
    "**'구조 58% + 라벨 42%, 발화율 무관'**. ",
    "★부수: 이 라운드 종료 스크립트를 Bash heredoc 으로 쓰다 백슬래시가 먹혀 파싱 에러 — ",
    "메모리 카드가 명시해둔 함정을 그대로 밟았다(Write 로 재작성). 지식으로는 안 막힌다."),
  next_probes = c(
    "좋은 라벨의 공통 성질 — 라벨 후보를 더 넣어 '무작위 대비 부호'로 줄 세우기. mega_spread +0.202, unified -0.64",
    "구조 효과의 한계 — 무작위 파킹만으로 -0.272. 발화율을 더 낮추면 구조 효과가 커지는가 노출 손실이 이기는가",
    "unified 역방향의 소비 — 역방향 정보도 정보다. 단 jump_JM_State 반전은 이미 기각(무작위 대비 0/8), 같은 함정 주의",
    "STR_1698 계열 연장 후 mega_spread 파킹 — 라벨 적합성 11/12 확인됨. 칩 task_b065b34d"),
  consumer_surfaces = c("오버레이 라벨 선정", "파킹 레버 인용", "국면 라벨 설계",
                        "book-marginal 후보 평가", "다음 세션 인수인계"),
  frontier_update = sprintf("%s 등재 · 메모리 카드 최종 분해 기입 · 원장 220항목", nid),
  live_trigger = "새 라벨은 무작위 대조 원점으로 먼저 줄 세운다 · STR_1698 연장 시 mega_spread 즉시 적용",
  evidence_refs = c("stage_artifacts/pg2_hunt/n1_rate_quality.csv",
                    "stage_artifacts/pg2_hunt/o1_grid.csv",
                    "stage_artifacts/pg2_hunt/p1_str1698_altlabel.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
