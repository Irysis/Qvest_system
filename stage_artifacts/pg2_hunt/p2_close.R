suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/close_round.R")
CORR <- paste0(
  "\u2605\u2605\u2605\uc815\ubc00\ud654(2026-08-09 p1): \ud30c\ud0b9\uc740 **\uc77c\ubc18 \ub808\ubc84\uac00 \uc544\ub2c8\ub77c (\ub77c\ubca8, \uc7ac\ub8cc) \uc30d\uc5d0 \uc870\uac74\ubd80**\ub2e4. ",
  "STR_1698 \uc5d0 `unified_regime_signal_daily` \uc758 Regime_Score(low) \ub77c\ubca8\ub85c \ud30c\ud0b9\ud558\ub2c8 ",
  "\ubd80\uc871\ubd84\uc774 **0.087 \u2192 0.227~0.493 \uc73c\ub85c \uc545\ud654**\ud588\ub2e4(243\uac1c\uc6d4 \ucc3d). ",
  "rho \ub294 0.192 \u2192 0.123 \uc73c\ub85c \ub0b4\ub824\uac00\ub294\ub370 **IR \uc774 0.560 \u2192 0.089~0.370 \uc73c\ub85c \ub354 \ud06c\uac8c \ubb34\ub108\uc84c\ub2e4** ",
  "\u2014 \uc774 \ub77c\ubca8\uc758 OFF \uc6d4\uc774 \uc774 \uc804\ub7b5\uc5d0\uac8c\ub294 \uc88b\uc740 \ub2ec\uc774\ub77c \ubca4\uce58\ub85c \uac08\uc544\ud0c0\uba74 \uc54c\ud30c\ub97c \ubc84\ub9b0\ub2e4. ",
  "\uadc0\ubb34 \ucc3d \uac8c\uc774\ud2b8\ub3c4 \uc815\ud569: \u0394rho -0.0263 \u00b7 \ubc31\ubd84\uc704 **12.4%% \u00b7 inside TRUE**. ",
  "\u2605\uc624\ub298 12\uacc4\uc5f4\uc5d0\uc11c \ubcf8 '\ud30c\ud0b9\uc774 rho \ub97c \uc74c\uc218\uae4c\uc9c0 \ub0b4\ub9b0\ub2e4(11/12 \uac1c\uc120)' \uc740 ",
  "**FQ-191 mega_spread \ub77c\ubca8 \u00b7 73\uac1c\uc6d4 \ucc3d** \uc5d0\uc11c\uc600\uace0, \ub77c\ubca8\u00b7\ucc3d\uc744 \ubc14\uafb8\uc790 **\ubd80\ud638\uac00 \ub4a4\uc9d1\ud614\ub2e4**. ",
  "\u21d2 \ud30c\ud0b9 \uc774\ub4dd \uc778\uc6a9 \uc2dc **\ub77c\ubca8\uacfc \ucc3d\uc744 \ubc18\ub4dc\uc2dc \ubcd1\uae30**\ud560 \uac83. ",
  "\u2605STR_1698 \uc740 **\ubb34\ucc98\ub9ac\uac00 \ucd5c\uc120**(\ubd80\uc871\ubd84 0.087, \uc624\ub298 \ucd5c\uc18c)\uc774\uba70, ",
  "\uc5f0\uc7a5\ud574\ub3c4 FQ-191 \ub77c\ubca8\uc774 \uc774 \uc7ac\ub8cc\uc5d0 \ub9de\ub294\ub2e4\ub294 \ubcf4\uc7a5\uc740 \uc5c6\ub2e4. \uce74\ub4dc: [[project-parking-is-label-material-conditional-20260809]]")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
hit <- 0L
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% c("FQ-213","FQ-215")) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORR)
    hit <- hit + 1L; say("정밀화 기입 %s", ids[k])
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d항목 · 기입 %d건", length(read_frontier_queue()$entries), hit)
r <- close_round(
  round_id = "PG2_PARKING_CONDITIONALITY_20260809",
  verdict_type = "config_scoped_negative",
  layer = "method",
  mechanism_diagnosis = paste0(
    "STR_1698(오늘 최고 후보, 부족분 0.087)의 파킹 장벽을 다른 라벨로 우회하려 했으나 ",
    "결과가 **반대로 나왔다** — 부족분이 0.087에서 0.227~0.493으로 악화. ",
    "rho는 내려가는데(0.192→0.123) IR이 더 크게 무너진다(0.560→0.089~0.370). ",
    "그 라벨의 OFF 월이 이 전략에게 좋은 달이라 벤치로 갈아타면 알파를 버리는 것이다. ",
    "★따라서 오늘 하루 인용한 '파킹 = 검증된 일반 레버'는 정밀화가 필요하다 — ",
    "그 결과는 FQ-191 라벨·73개월 창에서였고, 라벨·창·재료가 바뀌면 부호가 뒤집힌다. ",
    "**파킹은 (라벨, 재료) 쌍에 조건부**다. ",
    "★대리 축 재현 확인(proxy_axis)과 귀무 창 게이트(subsample_null)를 동반해 돌렸고, ",
    "귀무 창이 백분위 12.4% inside TRUE로 '이 창은 특별하지 않다'를 독립 확인했다."),
  next_probes = c(
    "STR_1698 무처리 retrofit — 파킹으로 개선되지 않으므로 무처리(부족분 0.087)로 계약 컴포넌트를 만들고 평가. build_bt_result 경유",
    "FQ-191 라벨 적용 가능성 — 계열 연장(2024-04 종료) 후에만 가능. 단 unified 라벨에서 반대가 나왔으므로 맞는다는 보장 없음. 칩 task_b065b34d",
    "파킹 이득의 라벨-재료 조건 규명 — 어떤 (라벨, 재료) 쌍에서 작동하는가. 12계열 x 2라벨로 교차표를 만들면 조건이 보인다",
    "파킹 인용부 전수 정정 — 오늘 여러 산출물에 '일반 레버'로 적었다. 라벨·창 병기로 정정 필요"),
  consumer_surfaces = c("오버레이 설계", "파킹 레버 인용", "book-marginal 후보 평가", "국면 라벨 선정"),
  frontier_update = "FQ-213/215 정밀화 · 메모리 카드 신규 · 원장 219항목",
  live_trigger = "STR_1698 계열 연장 시 FQ-191 라벨 재시도 · 또는 무처리 retrofit 완료 시 재판정",
  evidence_refs = c("stage_artifacts/pg2_hunt/p1_str1698_altlabel.csv",
                    "stage_artifacts/pg2_hunt/s8_parked.csv"))
say("close_round: %s", if (is.list(r)) "OK" else as.character(r))
