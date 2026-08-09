# probe_final_state.R — 최종 상태 read-only 확인 (★상태를 바꾸지 않는다 — run_fu_verify 의 교훈)
suppressPackageStartupMessages({library(jsonlite); library(arrow); library(data.table)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_001")
say <- function(f,...) cat(sprintf(paste0("[final] ",f,"\n"),...))
p <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
v <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
vf <- p$verification_followup_20260809
say("--- 정본 핵심값 (package) ---")
say("  F3 D03 t: lag3 %s → lag60 %s · MBB %s", vf$task1_f3_hac_correction$D03_EWMA$t_nw_lag3_SUPERSEDED,
    vf$task1_f3_hac_correction$D03_EWMA$t_nw_lag60, vf$task1_f3_hac_correction$D03_EWMA$t_mbb_L60_B2000)
say("  F3 Q01 t: lag3 %s → lag60 %s · MBB %s", vf$task1_f3_hac_correction$Q01_EB$t_nw_lag3_SUPERSEDED,
    vf$task1_f3_hac_correction$Q01_EB$t_nw_lag60, vf$task1_f3_hac_correction$Q01_EB$t_mbb_L60_B2000)
say("  섹터잔존 D03 %s / Q01 %s · 재현판정 %s / %s",
    vf$task3_sector_neutral_beta$headline_D03$retention_vs_raw,
    vf$task3_sector_neutral_beta$headline_Q01$retention_vs_raw,
    vf$task3_sector_neutral_beta$reproduction_verdict_D03, vf$task3_sector_neutral_beta$reproduction_verdict_Q01)
say("  패널 %s → %s행 · 위반주입 PASS %s", vf$task4_panel_repair$rows_before,
    vf$task4_panel_repair$rows_after, vf$task4_panel_repair$verification$injection_test_pass)
say("  challenge_flags %d (중복 %d) · self_adversarial %d concern",
    length(p$challenge_flags), sum(duplicated(unlist(p$challenge_flags))),
    vf$self_adversarial_challenge$concerns_raised)
say("--- validation 정합 ---")
say("  F3 D03 lag60 %s (package %s) · F2 D03 ctl t %s",
    v$falsification_observables$F3_beta_drag$D03$t_nw_lag60,
    vf$task1_f3_hac_correction$D03_EWMA$t_nw_lag60,
    v$falsification_observables$F2_agent_individual_flow$D03_turnover_ctl_t)
say("  b_D03 강등 %s · superseded 4종 보존 %s",
    grepl("미확립", v$verdict$b_D03),
    all(c(!is.null(v$falsification_observables$F3_beta_drag$superseded_20260808),
          !is.null(v$falsification_observables$F2_agent_individual_flow$superseded_20260808),
          !is.null(v$verdict$superseded_b_D03_20260808),
          !is.null(p$diagnostics$superseded_20260808_pre_liquidity_repair))))
say("--- 큐 ---")
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
i <- which(sapply(q$entries, function(x) identical(x$id,"FQ-122")))[1]
say("  FQ-122 서브라운드 status=%s · next_probe %d건 · 항목 총 %d",
    q$entries[[i]]$verification_followup_20260809$status,
    length(q$entries[[i]]$verification_followup_20260809$next_probe), length(q$entries))
say("--- 산출물 ---")
say("  verification_followup/ 파일 %d개", length(list.files(file.path(OUT,"verification_followup"))))
say("  challenge_note_followup.md %s", file.exists(file.path(OUT,"verification_followup/challenge_note_followup.md")))
