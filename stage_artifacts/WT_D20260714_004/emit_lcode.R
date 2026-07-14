setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/axiom/lcode_emit.R")
lesson <- paste0(
"[canonical_screen 실측] R28 FQ-041 C06_TP_Gap frozen-book pruning 검증(R26 P1 settle, 도훈 지시 2026-07-14 book_enhancement) = CONFIG_SCOPED_NEGATIVE(C06 pruning book-marginal 자본) + HIGH-severity look-ahead 발견(escalate). ",
"★frozen 재구축 parity(challenge#1): off=+1(same-month factor_db) stored-theta median cor 0.913(R26 recon fid 0.914 재현) / off=0(T-1=production _recompute convention) 0.612. => 저장 268m frozen 패널 = same-month(M-end) factor vintage. ",
"★C06 counterfactual(6F-C06 vs 7F cap-w top-25 paired NW-t lag3): PIT-clean(off=0) stored-theta IS 0.850/HO 1.133(sub-2.0 미달) · production ic-theta IS 0.303/near no-op(C06 IC-theta 이미 self-deweight 가중~0). look-ahead basis(off=+1)에서만 IS 3.34/HO 2.03 통과=오염. => R26 IS-positive(recon 2.45)는 same-month look-ahead 아티팩트, holdout 붕괴(-0.60)는 remove-only recon-proxy 아티팩트(frozen renorm선 재현안됨 clean HO+1.13). ",
"★★look-ahead 발견(controlled: factor_db 월만 변경): off=0(T-1,PIT-clean)→off=+1(same-month) cap-w top-25 PORT_t 2.08~2.18× inflation(stored_S7 3.06→6.38). 저장 패널 직접 screen 5.24(clean 3.06과 LA 6.38 사이). 3축근거: parity 0.913 · factor_db_201506 내부 Date=2015-06-30(M-end)+load_month_factors same-month매핑 · controlled 2.1×. ",
"nuance(over-claim 방지): stored 패널 clean-forward(M-end→M+1) rank-IC t=5.92 > contemporaneous(M-end→M) 4.74 = 알파 자체 진짜 forward 예측력. look-ahead는 top-25 cap-w PORT_t magnitude 국한. live/forward recompute는 PIT-clean(T-1). => admission PORT_t(5.324)는 동월 vintage로 ~2× 부풀림, PIT-clean ~3.1. historical(same-month) vs forward recompute(T-1) 1개월 vintage seam. live는 backtest 하회 예상. ",
"dual-basis(M2): clean cap-w post2017_t 0.51~0.90 감쇠 상당부분=mega-cap 벤치 아티팩트(EW-uni post2017_t 1.21~1.78 생존, oos 1.16~1.66). ",
"방법론: cap-w authoritative+EW-uni dual-basis · off/theta 4cell 전수(argmax 없음, n_trials=1 chain, DSR sweep 부적용) · C02_EPS_Chg_1m 절대 제거금지 준수(C06만) · book_state 무변경 · pin R28_current_20260714. ",
"next_probe: P1(escalate) judge/PIT-agent가 stored 268m 패널 vintage seam 검증 + true admission PORT_t 재산출(clean~3.1) + live NAV corroborate; P2 production 재빌드 시 clean(T-1) convention 통일, C06는 self-deweight로 명시제거 무해(near no-op)."
)
res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R28_FQ041_C06_FROZEN_PRUNING",
  grade = "F",
  lesson_text = lesson,
  metric_type = "canonical_screen",
  construction_type = "book_marginal_frozen_recon_loo_c06_pruning",
  selection_type = "chain",
  mechanism_hypothesis = "frozen book SLEEVE_CORE-C06 재구축이 canonical cap-w PORT_t 개선인가 — PIT-clean(off=0) paired IS 0.85/HO 1.13 미달 + production ic-theta self-deweight near no-op. 부수: 저장 패널 same-month vintage look-ahead(PORT_t 2.1x inflation).",
  portfolio_alpha_t = 3.058,
  oos_months = 268L,
  core_reference = "FQ-041 R26 P1 (도훈 2026-07-14); parent L-AR-20260714_153519; production _recompute_alpha_asof.R; deltair_diag 2026-07-13; prereg_sha256 0cf27b32; base STR_1715_on_M4_R05_noLayer4_PG2",
  tags = c("book_enhancement","book_marginal","frozen_recon","c06_tpgap_pruning","loo_pruning",
           "screen_tier","config_scoped_negative","lookahead_finding","pit_escalate","vintage_seam",
           "same_month_factor_lookahead","self_deweight","recon_proxy_artifact","fq_041","captier_localization","frontier_open"),
  metrics = list(
    parity_off1_samemonth = 0.9132, parity_off0_T1 = 0.6115,
    c06_paired_is_clean = 0.850, c06_paired_ho_clean = 1.133,
    c06_paired_is_production_ictheta = 0.303,
    lookahead_inflation_capw = 2.085, stored_panel_port_t = 5.241,
    port_t_clean_off0 = 3.058, port_t_lookahead_off1 = 6.376,
    ic_contemporaneous_t = 4.74, ic_forward_plus1_t = 5.92,
    oos_retention_clean = 0.167, ewuni_port_t_clean = 3.77,
    next_probe = "P1 judge/PIT vintage seam 검증+true admission PORT_t 재산출(clean~3.1)+live NAV corroborate; P2 clean T-1 convention 통일"
  ),
  dry_run = FALSE
)
cat("[emit] l_code=", res$l_code %||% res$entry$l_code %||% "?", "\n")

## lineage (alpha_package write 후)
source("02_Infrastructure/worktask/lineage_utils.R")
tryCatch(record_package_lineage(
  task_id = "WT-D20260714_004",
  package_type = "alpha_package",
  method_selected = "C06 frozen recon LOO pruning (off/theta 4cell) + look-ahead finding",
  input_file_paths = c(
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet",
    ".cache/factor_db/factor_ic_monthly.parquet", ".cache/RAWDATA.parquet",
    "stage_artifacts/WT_D20260714_004/recon_panels.parquet")
), error=function(e) cat("[lineage] warn:", conditionMessage(e), "\n"))
cat("EMIT_DONE\n")
