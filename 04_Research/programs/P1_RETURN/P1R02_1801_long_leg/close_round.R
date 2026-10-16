## P1R02 종료 기록 — 등록부 라운드 항목에 결과(판정 · 철학 P2 · 보고 경로)를 덧붙인다(사전등록 경로 · md5 불변 — writer 가 검사)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
SA <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN/P1R02_1801_long_leg/prereg.json")
pr_record_round("P1_RETURN", list(
  round_id = "P1R02_1801_long_leg", prereg = "stage_artifacts/programs/P1_RETURN/P1R02_1801_long_leg/prereg.json",
  prereg_md5 = unname(tools::md5sum(SA)), status = "complete", n_variants = 1L, variants = list("P1R02_LONG"),
  verdict = list(H1 = "rejected", M1_t = -0.62, band = "숏 레그 의존", branch = "④ 롱온리 후보 아님",
                 note = "재검증 롱숏(고정 방향) = F · 1차 A 의 원천(동적 부호 층 · 학습 표본) 미분리 — 단일 차이 A/B 가 다음 탐침"),
  philosophy_p2 = "neutral (R-20261017-003)",
  report = "stage_artifacts/programs/P1_RETURN/P1R02_1801_long_leg/ROUND_REPORT.md"), root = ROOT)
cat("recorded complete\n")
