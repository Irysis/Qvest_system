suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[o2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")
G <- fread("stage_artifacts/pg2_hunt/o1_grid.csv")
CORR <- paste0(
  "\u2605\u2605\u2605\uc7ac\uc815\uc815(2026-08-09 o1 \uad50\ucc28\ud45c): \ud30c\ud0b9\uc740 '(\ub77c\ubca8, \uc7ac\ub8cc) \uc30d' \uc774 \uc544\ub2c8\ub77c **\ub77c\ubca8\uc774 \uc804\ubd80**\ub2e4. ",
  "12\uc804\ub7b5 x 2\ub77c\ubca8\uc744 **\ub3d9\uc77c 73\uac1c\uc6d4 \ucc3d**(\ub450 \ub77c\ubca8 \uacf5\ud1b5 \uc6d4)\uc5d0\uc11c \uad50\ucc28 \uce21\uc815\ud55c \uacb0\uacfc: ",
  "L1 mega_spread(ON 35.6%) \ubd80\uc871\ubd84 \uac1c\uc120 **11/12** \u00b7 \uc911\uc559 **-0.4725** \u00b7 paired t **-6.982** (p 0.00002) / ",
  "L2 unified(ON 82.2%) \uac1c\uc120 **0/12** \u00b7 \uc911\uc559 **+0.6621** \u00b7 paired t **+11.084** (p 0.00000). ",
  "\ub450 \ub77c\ubca8 \ud6a8\uacfc \uc0c1\uad00 **-0.324** \u00b7 \uac19\uc740 \ubc29\ud5a5 **1/12** ",
  "\u21d2 **\uc7ac\ub8cc\uac00 \uc544\ub2c8\ub77c \ub77c\ubca8\uc774 \uacb0\uc815\ud55c\ub2e4**(12\uc804\ub7b5 \uc804\uac74 \uac19\uc740 \ubc29\ud5a5\uc73c\ub85c \uac08\ub9bc). ",
  "\u2605\uae30\uc804 \ub2e8\uc11c: L2 \ub294 ON 82.2%% \ub77c **\ud30c\ud0b9\uc774 \uc544\ub2c8\ub77c \uc0ac\uc2e4\uc0c1 \uc0c1\uc2dc \ubcf4\uc720**\uc774\uace0, \ub098\uba38\uc9c0 18%% \ub9cc \ubca4\uce58\ub85c ",
  "\uac08\uc544\ud0c0\ub294\ub370 \uadf8 18%% \uac00 \uc88b\uc740 \ub2ec\uc774\ub77c \uc190\ud574\ub9cc \ubcf8\ub2e4. \ud30c\ud0b9\uc740 **'\uc801\uac8c \ubcf4\uc720\ud558\uace0 \uc798 \uace0\ub97c \ub54c'** \uc791\ub3d9\ud558\ub294 \uac83\uc73c\ub85c \ubcf4\uc778\ub2e4. ",
  "\u2605\u2605\ud568\uc758: STR_1698 \uc774 unified \ub77c\ubca8\uc5d0\uc11c \uc2e4\ud328\ud55c \uac83\uc740 **\uc7ac\ub8cc \ud0d3\uc774 \uc544\ub2c8\ub77c \ub77c\ubca8 \ud0d3**\uc774\ub2e4. ",
  "FQ-191 \ub77c\ubca8\uc744 \uac78 \uc218 \uc788\uc73c\uba74 \uc5ec\uc804\ud788 \uc720\ub9dd\ud558\uba70, \uc720\uc77c\ud55c \uc7a5\ubcbd\uc740 **\uacc4\uc5f4\uc774 2024-04 \uc5d0 \ub05d\ub09c \uac83**\uc774\ub2e4(\uce69 task_b065b34d). ",
  "\ub77c\ubca8\uc774 \ub9de\ub294\ub2e4\ub294 \uac83\uc740 **12/12 \ub85c \ud655\uc778**\ub410\ub2e4.")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
hit <- 0L
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% c("FQ-213","FQ-215")) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORR)
    hit <- hit + 1L; say("재정정 기입 %s", ids[k])
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d항목 · 기입 %d건", length(read_frontier_queue()$entries), hit)
r <- close_round(
  round_id = "PG2_LABEL_GRID_20260809",
  verdict_type = "capability_established",
  layer = "method",
  mechanism_diagnosis = paste0(
    "파킹 이득의 조건을 12전략 x 2라벨 교차표로 규명했다(동일 73개월 창). ",
    "L1 mega_spread(ON 35.6%)는 11/12 개선(중앙 -0.4725, t -6.982), ",
    "L2 unified(ON 82.2%)는 0/12 개선(중앙 +0.6621, t +11.084). ",
    "두 라벨 효과 상관 -0.324, 같은 방향 1/12. ",
    "★즉 파킹은 '(라벨, 재료) 쌍' 이 아니라 **라벨에 조건부**다 — 재료 간 일관성이 12/12. ",
    "기전 단서: L2는 ON 82.2%라 사실상 상시 보유이고 나머지 18%만 벤치로 갈아타는데 그 18%가 좋은 달이다. ",
    "⇒ 파킹은 '적게 보유하고 잘 고를 때' 작동한다. ",
    "★이것이 STR_1698 의 상태를 되돌린다 — unified 실패는 재료가 아니라 라벨 탓이고, ",
    "FQ-191 라벨이 맞는다는 것은 12/12로 확인됐다. 유일한 장벽은 계열 종료(2024-04)뿐이다."),
  next_probes = c(
    "★STR_1698 계열 연장 후 FQ-191 라벨 파킹 — 라벨 적합성은 12/12로 확인됐고 장벽은 데이터뿐. 칩 task_b065b34d",
    "발화율 vs 선별질 분리 — L1(35.6%)과 L2(82.2%)는 발화율도 선별도 다르다. 같은 발화율로 맞춘 unified 판본을 만들어 어느 축이 결정하는지 가른다",
    "라벨 후보 확장 — 현재 2종뿐. jump_JM_State·β_R05·vol-state를 같은 교차표에 넣어 '작동하는 라벨'의 공통 성질을 찾는다",
    "파킹 인용부 전수 정정 — 오늘 여러 산출물에 '일반 레버'로 적었다. '라벨 조건부 + 라벨명 병기'로 정정"),
  consumer_surfaces = c("오버레이 라벨 선정", "파킹 레버 인용", "book-marginal 후보 평가", "국면 라벨 설계"),
  frontier_update = "FQ-213/215 재정정 · 메모리 카드 갱신 · 원장 219항목",
  live_trigger = "STR_1698 연장 완료 시 FQ-191 파킹 즉시 적용 · 새 라벨 확보 시 교차표 확장",
  evidence_refs = c("stage_artifacts/pg2_hunt/o1_grid.csv",
                    "stage_artifacts/pg2_hunt/p1_str1698_altlabel.csv",
                    "stage_artifacts/pg2_hunt/s8_parked.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
