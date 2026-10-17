## P2R03 종료 기록 — 등록부 결과(판정 · 철학 P2 · 보고 경로 · 시도 이력) — writer 경유(program_registry.R::pr_record_round)
##   상신(GRADE-V32-TIMING-EVENT-UNIT-20261018)은 발송 전에 dr_open 으로 따로 열었다(철학 P2 C-20261018-012).
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
library(jsonlite)
SA  <- "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay"
pre <- fromJSON(file.path(ROOT, SA, "prereg.json"), simplifyVector = FALSE)
ev  <- fromJSON(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/results/evaluation_visible.json"), simplifyVector = FALSE)
codes <- vapply(pre$cells, function(z) z$code, character(1))
pr_record_round("P2_DEFENSE", list(
  round_id = "P2R03_conditional_overlay", prereg = file.path(SA, "prereg.json"),
  prereg_md5 = unname(tools::md5sum(file.path(ROOT, SA, "prereg.json"))), status = "complete", n_variants = 14L,
  variants = as.list(codes),
  verdict = list(label = as.character(ev$verdict_label %||% ev$verdict), pass_both = list(), pass_one = list(), selected = list(),
                 held_lag1_slow = as.list(unlist(ev$held_lag1_slow)),
                 note = paste0("β 짝(같은 β 현금 사본) 깊은 위기 과반 0/14(최대 2/4) = 시변 노출 층 7종 모두 노출(β) 방어 또는 결정적 미달 · ",
                               "D5 추세 현금 · D7 재진입 = 꺾인 추세 위 2차 급락 2건(GFC · COVID)의 노출 경로(빠른 급락 β 짝 LT 3/4 · 일화 2/3 · 독립 사건 2 · HM t < 2 · 새 원천 아님 → 비교 기준 칸) · ",
                               "현금이 위기 뒤에 들어가 강세 참여 0~2/5 · D3 lag-1 붕괴 누출 조사 = 엔진 시점 단정 30칸 통과 · 누출 아님 · ",
                               "다음 = 상태 미전환 위기 표적 × 방어적 보유(원천 ③) × β 짝")),
  philosophy_p2 = "neutral (R-20261018-002)",
  superfan_t2 = "R-20261018-001 (도전 2 수용)",
  measurement = list(epoch = "all_hyg_px1000_2000_v1", ok = "30/30", vintage_groups = "E2 · E3 지문 동일 · 평가 지문 = 측정 지문",
                     attempts = "E2 RX0 4회 기동(10-17 20:22 재부팅 중단 · 22:19 rc=1 · 22:36 재측정 VRAM 넘침 · 10-18 03:53 도훈 승인 재기동 measure_now_vram.sh)"),
  report = file.path(SA, "ROUND_REPORT.md"), failure_map = file.path(SA, "failure_map.md")), root = ROOT)
cat("P2R03 recorded complete\n")
