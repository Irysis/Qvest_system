## _r13_emit_lcode.R — R13 L-code 적립 (mode=ramp, backtested, chain; 감쇠속도(oos) 축)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/ramp/ramp_loop.R")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
r13 <- fromJSON("outputs/ramp/r13_decay_summary_20260713.json")

lesson <- paste0(
 "RAMP R13 (FQ-026) = R12 메타진단 축전환 소비: construction 4축(비중2.930·vintage2.895·신선도2.852·비대칭퇴출2.937) 전부 cap-w ~2.94 포화 → ",
 "바인딩 실패 축=oos_retention(construction-invariant). 따라서 1차 endpoint=oos_retention(v2 cap-w act_bm)·cap-w 2차 병기로, ",
 "선별·퇴출 시간-함수형을 trailing '수준'에서 '감쇠속도/일관성'으로 전환(재료=realized active NW-t 불변, R7 교훈). 3-arm chain(selection_type=chain, config_hash d997ab856f3c4884, base parity Δ1.4e-5·level 재계산 Δ0). ",
 "결과(전 arm oos<<0.7·cap-w<2.95·paired<2.0·HARD 0/5 → config-scoped negative): ",
 "①D-1(감쇠속도 선별 페널티 z(lvl)+0.5·z(recent18−older18))=팩터모멘텀 수렴·붕괴 — cap-w 2.612→1.555·oos −0.076→−0.448(FM 대조군 1.322/−0.4478과 4째자리 차·사실상 동일)·Jaccard vs FM 0.713(71% 중첩)·rank AC 0.766∈(base0.859,FM0.666). 교차모드 prior(Alpha Decay Adaptive FM·IC Decay-Weighted FM MARGINAL, Cross-Factor Momentum FAIL, DIST-AR-007 DISTILLED_NEG) 실측 확증. ",
 "②D-2(F-1 구조·퇴출 트리거=감쇠속도 recent18<0 OR decay<−1.0)=1차 best이나 미소 — cap-w 2.503(<base 2.612)·oos +0.045(1차 best·base 대비 Δ+0.121)·post17SR −0.105→+0.048·Jaccard vs FM 0.440(구별)·vs base 0.884(base 위 퇴출). ",
 "③D-3(부분창 일관성 min(NW-t over 12m×3))=anti-momentum 최강(Jaccard vs FM 0.331 최저)이나 cap-w 2.164·oos −0.028·rank AC 0.513(12m NW-t 노이즈로 불안정). ",
 "★핵심: 감쇠속도=선별재료(D-1)→FM 수렴 붕괴 / 감쇠속도=퇴출트리거(D-2)→base 유지 소폭 개선 = '선별 규율 < 퇴출 규율' R11(armF)·R12(F-1) 테마의 감쇠-축 재확인. ",
 "★메타: D-2 oos Δ+0.121 = R12 best(ctrl armF cad3 +0.121)와 정확 동일 = oos 벽이 exit-rule-invariant로 확대 확증(퇴출-규율 계열 oos 천장 ~+0.12 = 문턱 0.7의 1/6). ",
 "즉 시간-함수형 축(선별·퇴출·일관성)은 cap-w(R10~R12 4축 포화)에 이어 oos축도 ~+0.12 천장으로 한계효익 소진 지대(R4~R13 config-scoped negative 누적). ",
 "cap-tier 국소화×cap-w 벽 불변(D-2/D-3 EW-oos 0.745/0.972 高이나 cap-w oos 붕괴 = long-only 횡단선택으로 cap-w 트랩 탈출 불가·FQ-015 확증). ",
 "endpoint 긴장 정직: 1차 IS-only 승자=D-1(IS paired −0.735 최소)인데 실제 oos 최악(−0.448=FM) = IS paired 단독 선택은 momentum-편향, 게이트 전체(oos 1차)가 자본화 차단(chain 규율 방어 작동). ",
 "적대검증 PARTIAL(7약점 C①~C⑦, FM 수렴 판별 task-의무 이행: D-1 수렴·D-2 구별·D-3 anti-momentum 실측). ",
 "next_probe: 감쇠축 정련(D-1a λ↓+penalty-only / D-1b 종목-레벨 감쇠 / D-2a rank×감쇠 AND-gate / D-2b 감쇠 대칭 충원 / D-3a 6m×2 겹침창 / D-3b EW-basis 배포 결정재료) + 메타 축전환(재료 축 R9 DART insider·basis 재분류 EW-real). "
)

res <- ramp_document(
  strategy_id = "RAMP_R13_DECAY_20260713",
  grade = "F",                       # config-scoped negative (자본 졸업 불가·screen-tier 미달; 방향 이동은 실측이나 net-불충분)
  lesson_text = lesson,
  construction_type = "composite",   # top-25 EW of NW-t-selected pure-factor composite (R6~R12 계보) — 감쇠속도는 시간-함수형만
  selection_type = "chain",          # 3-arm 독립 감쇠 기전 (sweep 아님·DSR 부적용·n_trials lineage=24)
  mechanism_hypothesis = paste0(
    "R12 메타진단(cap-w 4축 포화·바인딩 벽=oos construction-invariant) 소비 — oos를 1차 endpoint로 감쇠속도 선별/퇴출 시간-함수형 전환. ",
    "결과: 감쇠속도 선별(D-1)=FM 수렴 붕괴(oos −0.448) / 감쇠 퇴출(D-2)=base 유지 소폭 개선(oos +0.045, 천장 R12와 동일 +0.121). ",
    "oos 벽 exit-rule-invariant 확대 확증 = 시간-함수형 축 소진 지대·프론티어=재료축(DART insider)/basis 재분류(EW-real)."),
  core_reference = "L-RAMP-20260713_100638(R12 F-1 next_probe·축전환)·measurement-graduation §2 cap-w authoritative·project-selection-discipline-arc-r4r5r6·project-captier-alpha-localization·hypothesis_index(Alpha Decay Adaptive FM MARGINAL·DIST-AR-007)·challenge_note_r13_decay_20260713.md",
  portfolio_alpha_t = 2.503,         # cap-w authoritative best arm(D-2) — 자본 게이트 기준(<2.95)
  oos_retention = 0.0448,            # 1차 endpoint best(D-2, cap-w act_bm) — 자본 게이트 기준(<<0.7)
  oos_months = 77L,                  # OOS 블록(220 - 143 IS)
  falsification_attempts = list(
    list(test="FM 수렴 판별(Jaccard vs ctrl_factormom·rank AC·churn)", result="D-1 falsified(수렴·붕괴 Jaccard 0.713 oos=FM)·D-2 survived(구별 0.440)·D-3 survived(anti-mom 0.331)", effect_retained="D-2 감쇠퇴출만 base 유지"),
    list(test="풀 구성 변화(Jaccard vs base)", result="weakened", effect_retained="D-1 풀 재편 실재(0.579)나 FM방향 역효과"),
    list(test="oos subperiod(2017 경계)", result="weakened", effect_retained="D-2 이득 post-2017 국소·미소(+0.048 SR)"),
    list(test="EW-basis vs cap-w oos", result="D-2/D-3 EW-oos≥0.7이나 cap-w 붕괴", effect_retained="cap-tier 트랩 재확인")
  ),
  record_type = "performance",
  metrics = list(
    round = "R13", fq = "FQ-026", endpoint_primary = "oos_retention", endpoint_secondary = "port_t_capwt",
    config_scoped_negative = TRUE, any_graduation = FALSE, base_parity_delta = 1.39e-5,
    base_capwt = 2.6124, base_oos = -0.0759,
    D1_capwt = 1.555, D1_oos = -0.4481, D1_jaccard_FM = 0.713, D1_paired_full = -1.452,
    D2_capwt = 2.503, D2_oos = 0.0448, D2_oos_delta_vs_base = 0.1207, D2_jaccard_FM = 0.440, D2_jaccard_base = 0.884, D2_post17_sr = 0.048, D2_paired_full = -0.282,
    D3_capwt = 2.164, D3_oos = -0.0282, D3_jaccard_FM = 0.331, D3_rank_ac = 0.513, D3_ew_oos = 0.972,
    ctrl_factormom_capwt = 1.322, ctrl_factormom_oos = -0.4478,
    winner_IS_only = "armD1_decay_penalty", winner_is_paired_t = -0.735, best_oos_arm = "armD2_decay_exit", best_capwt_arm = "armD2_decay_exit",
    max_paired_full = -0.2824, oos_target = 0.7, gate_capwt = 2.95,
    fm_convergence_verdict = "D-1 converged to FM & collapsed (Jaccard 0.713, oos -0.448=FM); D-2/D-3 distinct (exit-discipline / anti-momentum)",
    oos_wall_verdict = "oos ceiling ~+0.12 exit-rule-invariant (D-2 delta +0.121 == R12 armF cad3); time-function axis exhausted zone (config-scoped negative R4~R13)",
    n_trials_r13 = 3, n_trials_lineage = 24, selection_type = "chain",
    config_hash = "d997ab856f3c4884", vintage_pin = "r6_session_20260711",
    verdict = "config-scoped negative (decay-speed selection config). oos primary endpoint moved +0.121 (D-2) but <<0.7; cap-w all<base; HARD 0/5. wall=cap-tier localization x cap-w, unchanged. frontier: material axis (DART insider) / basis reclass (EW-real deployment material)."
  ),
  dry_run = FALSE
)
cat("EMIT_DONE l_code=", res$l_code %||% res$lcode$l_code %||% "?", "\n")
str(res, max.level=1)
