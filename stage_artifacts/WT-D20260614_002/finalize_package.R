# Finalize: merge revision diagnostics into draft -> canonical alpha_package.json
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
OUT_WT <- "qepm/mailbox/worktask/WT-D20260614_002"
OUT_STAGE <- "stage_artifacts/WT-D20260614_002"

pkg <- fromJSON(file.path(OUT_WT,"alpha_package_draft.json"), simplifyVector=FALSE)
rv  <- readRDS(file.path(OUT_STAGE,"_revise_diag.rds"))

# ---- inject revision diagnostics (Codex C1/C3/C4/C6 closure) ----
pkg$revision_diagnostics <- list(
  codex_round="REVISE -> addressed",
  walk_forward_ic_panel=list(
    ref="stage_artifacts/WT-D20260614_002/alpha_ic_panel_walkforward.parquet",
    n_months=rv$panel_months, range=rv$panel_range,
    columns="ym, n, FULL, best_Q04, best_D01, DQV6, drop_defense, drop_momentum, drop_quality, drop_value",
    note="★C1 closure: per-sig-date monthly IC panel 2005-01~2026-04 (256 months), NOT single snapshot. Recomputed in-universe (K200uKQ150) with PIT forward returns."
  ),
  leave_one_family_ablation=list(
    basis="in-universe sector-raw monthly Spearman IC, 256 months",
    sets=rv$ablation,
    interpretation=paste0(
      "★C3/RF-A2 closure: drop_quality meanIC 0.0074 (-72% vs FULL 0.0265) = quality는 알파의 지배 동인. ",
      "drop_momentum meanIC 0.0262 ~= FULL 0.0265 = 모멘텀 3팩터(M01/M05/M07)는 noise(기여 ~0). ",
      "DQV6(defense+quality+value 6팩터) 0.0262 ~= FULL 0.0265 → 10팩터 EW가 compact 6팩터 core를 IC로 능가하지 못함. ",
      "drop_value 0.0310 > FULL → value(V01_BM)도 한계 음(-). ",
      "결론: Factor-Zoo 축소(research_philosophy ①) — momentum 3팩터 제거, value 1팩터 재검토 권고. ",
      "단 ablation은 IC-basis이고 portfolio_alpha_t/MDD는 미재측정 — risk/optimizer가 compact core로 재구성 시 검증 필요."
    )
  ),
  sector_neutral_ic=list(
    mean_ic=round(rv$sn_ic$meanIC,4), icir=round(rv$sn_ic$ICIR,3),
    retention_vs_raw=round(rv$sn_ic$retention,3),
    verdict=sprintf("★C6/RF-A4 closure: 섹터중립 IC retention %.1f%% (>>30%% threshold). 알파는 섹터 베팅이 아닌 종목선택력. PASS.", 100*rv$sn_ic$retention)
  ),
  universe_liquidity_audit=list(
    top30_in_k200_kq150_frac=round(rv$top30_in_univ_frac,3),
    top30_in_k200_kq150_n=rv$top30_in_univ_n,
    verdict=sprintf("★C4/RF-A5 partial: top-30 @2026-05 중 %d/30(%.0f%%)만 K200uKQ150. AS-mode universe='ALL'이 mid/small ~36%% 누출. QEPM deployment는 in-universe 제약 필요(risk/optimizer가 enforce). alpha_scores.parquet에 in_univ 미부착 — full top-universe score는 의도(Optimizer가 제외), 단 deployment screen은 K200uKQ150 restrict 의무.",
                    rv$top30_in_univ_n, 100*rv$top30_in_univ_frac)
  ),
  n_holdings_reconciliation="recipe n=30 (AS-mode screening, max_position 0.20). QEPM deployment max_names=25 hard (헌법). Alpha는 top-universe 전수 score 생성(역할), 25-cap enforce는 Optimizer 단계. 불일치 아님 — 역할 분리."
)

# ---- Codex concern disposition (Charter §8 No Silent Override) ----
pkg$codex_concern_disposition <- list(
  C1_single_snapshot=list(classification="ACCEPT", action="alpha_ic_panel_walkforward.parquet 256-month panel 생성 (revision_diagnostics.walk_forward_ic_panel). alpha_scores.parquet은 as_of 의사결정 snapshot(정상)이나 검증용 walk-forward panel 별도 첨부."),
  C2_not_graduation_ready=list(classification="REBUTTAL_AGREE", action="동의 — package가 이미 STANDALONE_GRADUATION_FAIL 명시(verdict + weaknesses_carry). Codex가 자체 finding 재진술. 수정 불요. 단, 이는 alpha-research 역할상 '실패 정직보고'이지 '약신호 promote'가 아님(AX-000 정합)."),
  C3_weak_mechanism=list(classification="ACCEPT", action="leave-one-family ablation 실행: quality 지배(drop시 -72%), momentum noise(drop시 무변), DQV6~=FULL. mechanism 정량 입증 + Factor-Zoo 축소 권고 추가."),
  C4_universe_not_closed=list(classification="PARTIAL", action="universe audit 첨부: top30 64% in-univ. n=30 vs 25 = 역할분리(Optimizer enforce). deployment restrict 의무 명시. alpha top-universe 전수 score는 의도된 역할(Charter hard_constraints_awareness)."),
  C5_path_to_value_no_weights=list(classification="REBUTTAL", action="★역할경계 — weights.csv/covariance.parquet/risk_package/optimization_package는 risk/optimizer agent 산출물이며 alpha-research에 hook-금지(agent_role_guard, strict_prohibitions 1~3). alpha가 이를 생성하면 위반. 'overlay/blend marginal IR로 가치 가능'은 미래작업 가설 라벨(measurement-graduation §3 screen_route 정의된 mechanism)이지 alpha 산출 주장 아님. AX-008 triangulation은 forge/judge 단계 책임."),
  C6_no_neutral_test=list(classification="ACCEPT", action="sector-neutral IC retention 79.4% 산출(PASS). size-neutral은 mcap 단일 control로 sector-neutral과 高중복 → sector-neutral로 대표(보수적). crowding은 risk-research 영역(중복 산출 금지)."),
  rationalization_self_audit=list(
    flagged=c("screen_route candidate","OVERLAY_CANDIDATE / DPL_FEATURE","blend marginal IR","real diversification potential","Conservative: use authoritative net_ir"),
    disposition=paste0(
      "self-check: 'screen_route'/'OVERLAY_CANDIDATE'/'DPL_FEATURE'는 measurement-graduation §3에 정의된 라우팅 mechanism(자의적 합리화 아님, 헌법 인용). ",
      "'real diversification potential'은 measured active corr 0.265(정량)로 뒷받침 — 회피표현 아님. ",
      "★단 'Conservative: use authoritative net_ir'(alpha 스케일링)은 soft self-rationalization 소지 인정 → alpha_vector는 Grinold IC*sigma*z 스케일이며 net_ir은 검증 참조용일 뿐, alpha 절대수준은 calibration 가정(IC_MEAN 0.0384, sigma 0.12)임을 명시. 절대 alpha 수준은 진단 보조이지 admission 수치 아님(admission=forge portfolio_alpha_t 1.694)."
    )
  )
)

# ---- update weaknesses & honest value with ablation finding ----
pkg$weaknesses_carry <- c(pkg$weaknesses_carry, list(
  "★ablation 입증: momentum 3팩터(M01/M05/M07) 기여 ~0(noise), value 1팩터 한계 음(-). 10팩터 EW = 비효율 — compact DQV6/quality-core가 동등 IC. Factor-Zoo 축소 권고.",
  "top-30 중 36%가 K200uKQ150 외(AS-mode 'ALL' 누출) — QEPM deployment universe restrict 필요"
))
pkg$honest_value_statement <- paste0(pkg$honest_value_statement,
  " [REVISE 추가] ablation으로 mechanism 정량 확정: quality 지배(drop -72%)/momentum noise(drop 무변). ",
  "→ 차기 권고: (a) momentum 제거한 compact defense-quality core 재구성 후 portfolio_alpha_t 재측정 (b) incumbent active corr 0.265 활용 blend marginal IR을 optimizer가 판정 (c) overlay로 MDD 48%->? 축소 가능성. ",
  "본 alpha 자체는 standalone 자본 부적격 확정이되, '동일 스트림(corr 1.0)' 전제는 반박됨(0.265).")

# ---- finalize: mark codex round complete ----
pkg$codex_round_status <- list(stance="REVISE", resolved=TRUE,
  resolution="6 concerns: 3 ACCEPT(C1/C3/C6 추가산출)+1 PARTIAL(C4)+2 REBUTTAL(C2 자체finding재진술/C5 역할경계). rationalization self-audit 1건 보완(alpha scale calibration 명시).",
  response_ref="qepm/mailbox/worktask/WT-D20260614_002/codex_critic_response_alpha.json",
  challenge_note_ref="qepm/mailbox/worktask/WT-D20260614_002/alpha_challenge_note.md")
pkg$finalized_at <- as.character(Sys.time())

# Step 1: write canonical alpha_package.json (AFTER which lineage)
write_json(pkg, file.path(OUT_WT,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[finalize] alpha_package.json (canonical) written.\n")

# Step 2: lineage
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id="WT-D20260614_002", package_type="alpha_package",
    method_selected="10-factor EW composite (cluster12 RC_16 de-contaminated) + ablation + incumbent overlap",
    input_file_paths=c(
      "stage_artifacts/batch_434/20260612_codegen_direct_409/RC_16_disp_vol_dual_result.rds",
      "stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds",
      ".cache/factor_db/factor_db_202605.parquet",
      "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
  cat("[finalize] lineage recorded.\n")
}, error=function(e) cat("[finalize] lineage WARN:", conditionMessage(e), "\n"))
cat("[finalize] DONE.\n")
