## WT-D20260809_003 P6 — ★ID 충돌 정정
## 사고: p5 가 FQ-167/168 을 등재하려 했으나 **병렬 세션이 먼저 쓴 ID** 라 조용히 생략됐다.
##       스크립트는 "생략" 을 출력했고 write 는 성공(추가 0) — 침묵 실패는 아니었으나
##       close_round frontier_update 서술("FQ-167/168 신규 등재")이 **거짓이 됐다**.
## 처분: ①점유자 정체 확인 ②내 항목을 미사용 ID 로 재등재 ③거짓 서술 정정 기록
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p6] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))

say("=== 점유자 정체 확인 (존재 검사 아닌 정체 검사) ===")
for (k in c("FQ-167","FQ-168")) {
  e <- Q$entries[[which(ids == k)]]
  say("  %s | %s | %s", k, substr(e$status, 1, 34), substr(gsub("[\r\n]+"," ", e$title), 1, 74))
}

## 미사용 ID 탐색 — 숫자 접미 최대값 + 1 부터
nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$", "\\1", ids)))
nums <- nums[is.finite(nums)]
say("=== 미사용 ID 탐색: 현 최대 FQ-%d ===", max(nums))
free <- c(); n <- max(nums)
while (length(free) < 2L) { n <- n + 1L; cand <- sprintf("FQ-%03d", n)
  if (!(cand %in% ids)) free <- c(free, cand) }
say("  배정: %s", paste(free, collapse = ", "))

mine <- list(
  list(id = free[1], lane = "measurement_integrity",
    title = "rank-IC 왜도-취약성 전수 — vol/tail 계열에서 평균/순위 괴리 스크린",
    hypothesis = paste0(
      "WT-D20260809_003 이 D03_EWMA 단독에서 rank-IC(+0.0322, t +3.00)와 decile 평균 기울기(spearman -0.685)의 ",
      "구조적 괴리를 기전과 함께 확립했다(중앙값 기울기 +0.503 · (평균-중앙값) 격차 spearman -0.988 · 왜도 -0.842). ",
      "기전이 '신호 x 수익왜도 상관' 이라면 vol/tail 계열 전반에 같은 취약성이 있어야 한다. ",
      "vol/tail 계열(FQ-108d 대상 8종)에 spearman(dec,mean) vs spearman(dec,median) 부호 일치를 전수 스크린한다."),
    ev_rationale = paste0(
      "저비용(동일 패널·동일 코드 재사용). 계열-wide 면 rank-IC 기반 재료 자격 판정의 **적용 경계**를 실측으로 그을 수 있다 ",
      "— measurement-graduation §2 의 rank-IC ADVISORY 강등에 지금까지 없던 기전 근거가 붙는다."),
    wall_check = paste0(
      "진단 라운드 — 자본 주장 없음. ★본 라운드의 목적 자체가 **1건 관측의 계열 일반화를 막는 것**이므로, ",
      "결과가 D03 단독이면 '일반화 금지' 확립이 곧 판정이다(memory: 한 항목의 negative 를 다른 항목에 일반화 금지)."),
    data_gate = "없음",
    owner = "미배정 (WT-D20260809_003 NP-1 · challenge_note W-5)",
    status = "frontier_open",
    next_action = "①vol/tail 8종 decile 평균·중앙값 프로파일 산출 ②부호 갈림 표 ③갈리는 재료의 왜도·sd 프로파일 대조 ④갈림 여부를 factor_registry 라벨로 노출 제안",
    source_refs = list("stage_artifacts/WT_D20260809_003/alpha_validation.json",
                       "memory: project-transition-wall-shape-heterogeneity-20260809")),
  list(id = free[2], lane = "consumption_surface",
    title = "형태별 소비면 대응의 실측 — HUMP 재료의 상단절단이 실제로 작동하는가",
    hypothesis = paste0(
      "WT-D20260809_003 이 형태 3종(MONOTONE_TOP / HUMP / 상단-역전형)을 동일 프레임에서 확립하고 ",
      "형태->소비면 대응을 제안했으나 **각 형태에서 실제 소비면 성과를 잰 적이 없다** — 대응은 현재 가설이다. ",
      "Q01_EB(HUMP, argmax D8, top -3.41%)에서 상단절단(D8~D9 선별)이 top-25 대비 cap-w PORT_t 를 개선하는지 직접 검정한다."),
    ev_rationale = "형태 진단을 라운드 1번 절차로 제도화하려면 대응이 실측으로 뒷받침돼야 한다. 아니면 그럴듯한 분류학만 남는다.",
    wall_check = paste0(
      "max 25 · long-only · [0,0.20] · Sw=1 · 유동성 2e8 불변. 분위 선택은 sweep 이라 챔피언 선택 시 DSR HARD 적용. ",
      "★착수 전 required_effect 바 산출 의무 — 분위 선택은 표본을 쪼개 검정력이 급감한다(2026-08-08 3/3 실증)."),
    data_gate = "없음 (stage_artifacts/WT_D20260809_003/merged_panel.rds 재사용)",
    owner = "미배정 (WT-D20260809_003 NP-2 · challenge_note W-4)",
    status = "frontier_open",
    next_action = "①착수 전 검정력 바 산출, 미달이면 형태 착수 전 폐기 ②Q01 D8~D9 선별 vs top-25 paired NW3 ③M26(MONOTONE_TOP) 음성 대조 ④해상도 불변성 확인",
    source_refs = list("stage_artifacts/WT_D20260809_003/alpha_validation.json",
                       "stage_artifacts/WT_D20260809_003/challenge_note.md (W-4)")))

for (e in mine) { Q$entries[[length(Q$entries) + 1L]] <- e; say("  %s 등재", e$id) }

## FQ-166 의 next_action 에 정정 부기 (거짓 서술 교정)
i <- which(ids == "FQ-166")
Q$entries[[i]]$next_action <- paste0(Q$entries[[i]]$next_action,
  " ★정정(2026-08-09): 후속 등재 ID 는 FQ-167/168 이 아니라 **", free[1], "/", free[2],
  "** — 원 등재 시도가 병렬 세션 선점 ID 와 충돌해 생략됐고 close_round 서술이 일시 부정확했다. 재등재 완료.")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)

Q2 <- read_frontier_queue(); id2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
say("=== 재읽기 검증 ===")
say("  항목 %d · %s %s · %s %s", length(id2), free[1], free[1] %in% id2, free[2], free[2] %in% id2)
writeLines(toJSON(list(collision = c("FQ-167","FQ-168"), reassigned = free,
  note = "close_round frontier_update 의 'FQ-167/168 신규 등재' 는 부정확했고 본 파일이 정정 기록이다."),
  auto_unbox = TRUE, pretty = 2), "stage_artifacts/WT_D20260809_003/id_collision_correction.json")
say("=== P6 완료 ===")
