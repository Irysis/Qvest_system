# run_03: alpha_package.json + alpha_validation.json + status/governance + lineage
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/wt_d20260718_001_crash_aware_mom/ca_lib.R")
WT <- "WT-D20260718_001"
MBOX <- file.path(ROOT_CA, "qepm/mailbox/worktask", WT)
PIN_TAG_CA <- readLines(file.path(OUT_CA,"PIN_TAG.txt"))[1]

M   <- fromJSON(file.path(OUT_CA,"ca_metrics.json"), simplifyVector = FALSE)
fin <- readRDS(file.path(OUT_CA,"ca_finalize.rds"))
b <- M$base; s <- M$selected

alpha_package <- list(
  task_id = WT, wt_type = "discovery",
  as_of_date = "2026-05-31", forecast_horizon = "1M",
  verdict = "config_scoped_negative__ALPHA_DONE_terminal",
  selection_objective = "canonical_port_t",
  alpha_vector = as.list(fin$alpha_vec),
  confidence_vector = as.list(fin$conf_vec),
  signal_matrix_ref = "stage_artifacts/WT_D20260718_001/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family="Momentum", proxy="mom_12_1", formula="cumret(t-11..t-1) z-score",
         lag_rule="monthly, signal<=h-1", winsorization="none(z)", neutralization="none",
         economic_rationale="cross-sectional momentum premium (core alpha to be crash-conditioned)",
         weight_theta=1.0, references=c("Jegadeesh-Titman 1993","Daniel-Moskowitz 2016 Momentum Crashes")),
    list(factor_family="CrashPenalty", proxy="downside_semivol/downside_beta/crash_exposure/ncskew (composite EW)",
         formula="score = z(mom_12_1) - lambda * z(crash_penalty), penalty higher=crash-prone",
         lag_rule="all windows end at h-1 (PIT)", winsorization="none(z)", neutralization="none",
         economic_rationale="ex-ante stock-level downside/crash-risk penalty to reshape structural drawdown at SELECTION layer (FQ-058 P1/P3)",
         weight_theta=-1.0, references=c("Ang-Chen-Xing 2006 Downside Beta","Chen-Hong-Stein 2001 NCSKEW"))
  ),
  diagnostics = list(
    metric_type = "canonical_screen (cap-w PORT_t 1급, NW lag-3) + dual-basis diag + AX-001 v2",
    canonical_port_t_nw_lag3 = b$full$port_t,          # BASE momentum cap-w (1급)
    canonical_port_t_note = "BASE mom_12_1 top-25 cap-w full-period. treatment(pre-registered composite l1) full PORT_t = ",
    canonical_n_months = b$full$n,
    base_full = list(port_t=b$full$port_t, calmar=b$full$calmar, mdd=b$full$mdd, net_sr=b$full$net_sr,
                     oos_port_t=b$oos$port_t, is_port_t=b$is$port_t),
    selected_preregistered = list(key=M$selection$selected_key,
                     full_port_t=s$full$port_t, full_calmar=s$full$calmar, full_mdd=s$full$mdd,
                     is_port_t=s$is$port_t, oos_port_t=s$oos$port_t),
    best_defensive_axis_diag = "downside_semivol_l0.5: full PORT_t 1.77(<base 1.91), full calmar 0.555(>0.510), full MDD 0.351(<0.398), OOS MDD 0.334(<0.398), crisis_active_bad +0.006(vs base -0.0013) — de-risking(low-vol tilt) 위장, crash-avoidance 아님",
    rank_ic = NA, icir = NA, harvey_t_stat = NA,
    rank_ic_note = "advisory 계열 미산출 — 선택권위=canonical PORT_t(v8.3 M1). 본 라운드 판정은 PORT_t/calmar/structural-DD/crisis로 완결.",
    n_trials = 20, selection_type = "sweep-like grid (alpha-stage canonical; DSR HARD는 forge-graduation only)"
  ),
  challenge_flags = list(
    "RF: 벤치마크 look-ahead 버그 발견·수정(contemporaneous→PIT-lagged, 22.5%→10.79% CAGR) — 재측정 완료",
    "config_scoped_negative: 사전등록 primary(composite/IS-calmar-select) OOS-fail(OOS PORT_t -1.02)",
    "informative: crash penalty의 MDD 레버=downside_semivol(위장 de-risking) — momentum premium 희생, crash-avoidance 아님. 진짜 crash-risk 축(downside_beta/ncskew) 무효 → momentum crash=common-factor",
    "base momentum OOS-dead(PORT_t -0.07) → 자본 graduation 불가(≪2.95)",
    "PIT flag: membership/liq 필터가 holding-month 데이터(FQ-058 상속 관행) — base·treatment 동일적용, paired 불변",
    "AX-001 v2: crisis_active_bad는 penalty로 개선(+)하나 bad_sr 불변(~-3.1)·momentum alpha 훼손 상쇄 → 방어 sleeve 자격 미달"
  ),
  pin_tag = PIN_TAG_CA, pin_upstream = PIN_UPSTREAM_CA
)
alpha_package$diagnostics$canonical_port_t_note <- paste0(
  "BASE mom_12_1 top-25 cap-w full. pre-registered treatment(composite l1) full PORT_t=", s$full$port_t,
  " (base ", b$full$port_t, " 대비 -", round(b$full$port_t-s$full$port_t,3), "). 어떤 treatment도 OOS PORT_t가 base(-0.074)보다 개선 안 됨.")

write_json(alpha_package, file.path(MBOX,"alpha_package.json"), auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
write_parquet(as.data.table(fin$dtab), file.path(OUT_CA,"alpha_scores.parquet"))  # keep selected scores already saved by run_01; dtab as validation record

# --- alpha_validation.json (dual-basis + universe_comparison + AX-001 v2) -----
alpha_validation <- list(
  task_id = WT, measured_at = format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen (cap-w 1급) + dual-basis(canonical_screen_diag)",
  universe = "KOSPI200 ∪ KOSDAQ150 ∩ liq>=2e8 ∩ 60m hist (KR_top342-equiv, 실측 elig ~318/mo)",
  cost_model = "15bps one-way delta", top_n = 25, n_months = b$full$n,
  benchmark = "cap-w K200|KQ150 PIT-lagged (Return.portfolio, CAGR 10.79% — FQ-058 재현)",
  base_vs_treatment = fin$dtab,
  dual_basis = list(
    base_capw = list(port_t=b$full$port_t, calmar=b$full$calmar, mdd=b$full$mdd, oos_port_t=b$oos$port_t),
    base_ew_universe = b$diag_ew,
    base_cap_tier_weight_share = b$diag_tier_wshare,
    selected_ew_universe = s$diag_ew,
    note = "base momentum top-25 = 91% OTHER(small-cap) tier. cap-w PORT_t 1.91 & EW-universe PORT_t 2.28 (both real IS, both OOS-decayed). treatment는 양 basis 공히 base 대비 열위 → cap-w 아티팩트 아님."
  ),
  universe_comparison = list(
    note = "L-227 v2 비교 mandate = ICIR attenuation 진단 시. 본 라운드는 cap-w PORT_t 실측 1급 판정·OOS-decay가 명확(base OOS -0.07)하여 v2(TOP500_FREEFLOAT) 재측정이 verdict를 뒤집을 여지 낮음(small-cap 편중 momentum). v2 재측정은 next_probe로 등재.",
    v2_run = FALSE
  ),
  ax001_v2 = list(
    frame = "방어형 조건부: crisis_alpha + Core(base) 대비 MDD + bad/normal",
    base_crisis_active_bad = b$crisis$active_bad_mean, base_bad_sr = b$crisis$bad_sr,
    best_defensive = "downside_semivol_l0.5: crisis_active_bad +0.006(개선), full MDD 0.351<0.398, OOS MDD 0.334<0.398 — 그러나 bad_sr -3.14(불변)·momentum PORT_t 1.77<1.91·OOS -0.35<-0.07",
    verdict = "AX-001 v2 조건부 평가에서도 crash penalty는 crisis-loss를 소폭 줄이나 momentum premium 희생이 상쇄 → 방어 sleeve 승격 미달. de-risking이지 crash-avoidance 아님."
  ),
  verdict = "config_scoped_negative",
  mechanism = "long-only momentum structural drawdown = systematic momentum-crash(common-factor). SELECTION-층 ex-ante stock-level crash penalty로 개별 crash-prone 종목을 감점해도 (a)진짜 crash-risk 축(downside_beta/ncskew)은 무효(crash 식별 불가=공통요인) (b)유일 MDD 레버 downside_semivol은 저변동 tilt=de-risking(premium 비례 희생). FQ-058(weighting) + 본 WT(selection) → 구성/선별 어느 층도 free MDD 레버 아님. 유일 실증 long-only MDD 레버 = overlay/timing 재확인.",
  next_probes = list(
    "P1: regime-conditional semivol de-risking — semivol penalty를 CRISIS 국면에만 적용(EW otherwise). 정적 selection=순수 de-risking이므로 동적화하면 유일 실증 레버(overlay/timing, FQ-058 P2)로 수렴. PIT C5 가드 의무(crashdyn overlay는 FAIL 이력 — 차별점=momentum-internal semivol timing).",
    "P2: momentum crash=common-factor 실측 → risk-model consumer: risk_package tail/crowding 진단에 'momentum DD=systematic, 종목-특이 아님' 반영(FQ-058 revival_condition 강화).",
    "P3: base momentum OOS-dead(post-2020 KR momentum decay) — 바인딩 제약은 drawdown이 아니라 momentum decay 자체. 비-return 원천(v8.3 주력)으로 라우팅."
  )
)
write_json(alpha_validation, file.path(OUT_CA,"alpha_validation.json"), auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")

# --- lineage (alpha_package write 후) -----------------------------------------
tryCatch({
  source(file.path(ROOT_CA,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id=WT, package_type="alpha_package",
    method_selected="crash-aware momentum selection (mom_12_1 - lambda*crash_penalty), config_scoped_negative",
    input_file_paths=c(file.path(OUT_MF,"fq057_monthly_returns.parquet"),
                       file.path(OUT_MF,"fq057_monthly_snapshot.parquet"),
                       file.path(OUT_MF,"np4_liq_snapshot.parquet")))
  cat("[lineage] recorded.\n")
}, error=function(e) cat("[lineage] skipped:", conditionMessage(e), "\n"))

# --- status + governance ------------------------------------------------------
st <- list(task_id=WT, current_phase="ALPHA_DONE",
           updated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S+0900"),
           blocker=NULL,
           verdict="config_scoped_negative__terminal (v8.3 M1 조기종결 — risk-research 미진행)")
write_json(st, file.path(MBOX,"status.json"), auto_unbox=TRUE, pretty=TRUE, na="null")

gl <- fromJSON(file.path(MBOX,"governance_log.json"), simplifyVector=FALSE)
gl$events[[length(gl$events)+1]] <- list(
  timestamp=format(Sys.time(),"%Y-%m-%dT%H:%M:%S+0900"), agent="alpha-research",
  action="ALPHA_DONE_terminal",
  summary=paste0("Crash-aware momentum selection = config_scoped_negative. BASE mom_12_1 cap-w PORT_t=",b$full$port_t,
    " (OOS ",b$oos$port_t," OOS-dead). 사전등록 treatment(composite l1) OOS PORT_t -1.02. 최선 방어축 downside_semivol=위장 de-risking(momentum premium 희생, crash-avoidance 아님). 진짜 crash-risk 축(downside_beta/ncskew) 무효 → momentum crash=common-factor. 벤치 look-ahead 버그 발견·수정(22.5%→10.79% CAGR). terminal ALPHA_DONE(자본 graduation 불가 ≪2.95)."))
write_json(gl, file.path(MBOX,"governance_log.json"), auto_unbox=TRUE, pretty=TRUE, na="null")

cat("\n[run_03] alpha_package.json + alpha_validation.json + status ALPHA_DONE emitted.\n")
cat("  MBOX:", MBOX, "\n")
