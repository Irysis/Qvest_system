# S6 — alpha_validation.json + alpha_package.json (AST v1.1) + lineage
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(arrow)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_004")
rj <- function(f) fromJSON(file.path(OUT, f), simplifyVector = FALSE)
S2 <- rj("s2_mech.json"); S3 <- rj("s3_side.json"); S4 <- rj("s4_candidate.json"); S5 <- rj("s5_diag.json")
HYP <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
P <- readRDS(file.path(OUT, "panel.rds"))
E <- O4$E_cand; M_cand <- O4$M_cand
R <- as.data.table(P$fwd$returns_dt)[!is.na(Ret_1m)]
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)

## ── alpha_vector / confidence_vector (as_of = 최종 신호월) ───────────────────
as_of <- max(E$Date)
LAST <- E[Date == as_of][order(-score_final)]
panic_last <- LAST$panic_use[1]
# z 축 정규화: 패닉월이면 pool 내부 z(-vol), 아니면 z_mom (100-offset 제거)
LAST[, z_axis := if (panic_last == 1L) score_final - 100*pool else score_final]
# 스케일: 월별 횡단면 OLS 기울기(Ret_1m ~ score) 의 확장창 평균 = as_of 시점 가용 전정보
DZ <- merge(E[, .(Date, Ticker, score_final, pool, panic_use)],
            R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
DZ[, z_axis := fifelse(panic_use == 1L, score_final - 100*pool, score_final)]
slp <- DZ[, {f <- stats::lm.fit(cbind(1, z_axis), Ret_1m); .(b = f$coefficients[2])}, by = Date]
slope_m <- mean(slp$b[is.finite(slp$b)])
TOP <- head(LAST, 25L)
alpha_vec <- setNames(as.list(round(slope_m * TOP$z_axis, 8)), TOP$Ticker)

# confidence: 데이터 커버리지 · 횡단면 랭크 안정성 · 부기간 안정성
PREV <- E[Date == sort(unique(E$Date))[length(unique(E$Date))-1L]]
rk_now <- LAST[, .(Ticker, rn = frank(-score_final, ties.method="first"), N = .N)]
rk_prv <- PREV[, .(Ticker, rp = frank(-score_final, ties.method="first"), Np = .N)]
rk <- merge(rk_now, rk_prv, by = "Ticker", all.x = TRUE)
rk[, stab := 1 - pmin(abs(rn/N - rp/Np), 1)][is.na(stab), stab := 0.5]
sv_last <- O2$sv[Date == as_of, .(Ticker, cov = pmin(n_i/126, 1))]
CF <- merge(TOP[, .(Ticker)], rk[, .(Ticker, stab)], by="Ticker", all.x=TRUE)
CF <- merge(CF, sv_last, by="Ticker", all.x=TRUE)
CF[is.na(cov), cov := 0.5][is.na(stab), stab := 0.5]
sub_stab <- num(S5$subperiod_stability)
CF[, conf := pmax(0, pmin(1, 0.45*cov + 0.35*stab + 0.20*sub_stab))]
conf_vec <- setNames(as.list(round(CF$conf, 6)), CF$Ticker)

## ── AST (코드와 1:1) ─────────────────────────────────────────────────────────
mom_leaf <- list(leaf = "SPECIAL_OP", escape_contract = list(
  op_name = "JT1993_FORMATION_LOG_SUM_J6_SKIP1",
  code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R",
  description = "월간 수익 로그합 t-7..t-2 (J=6 형성 · 최근 1개월 skip). 월간 집계 연산이 O 최소집합에 없어 escape.",
  walk_forward = TRUE, inputs = c("A1_RAWDATA_OHLCVS_daily:Ret"),
  no_future_leaf = TRUE))
panic_leaf <- list(leaf = "SPECIAL_OP", escape_contract = list(
  op_name = "PANIC_REGIME_IB_AND_EXPANDING_VOL_MEDIAN",
  code_path = "stage_artifacts/WT_R20260829_004/s2_mech.R",
  description = paste("I_B(직전 24개월 누적 KOSPI200 수익 < 0, DM2016 ex-ante 정의) AND",
                      "vol_hi(직전 126거래일 시장 실현변동성 > 그 시점까지의 확장창 중앙값, 최소 36개월 이력).",
                      "확장창 분위 연산이 O 최소집합에 없어 escape — TS_* 는 고정창만 표현한다."),
  walk_forward = TRUE,
  inputs = c("A4_benchmark_kospi200:BM_Close", "A4_benchmark_kospi200:BM_Ret"),
  signal_cutoff_rule = "first-day-of-holding-month (overlay_signal_cutoff) · used_cutoff = signal_month_end (strict t-1: 신호는 Date < 신호일 만 사용)",
  no_future_leaf = TRUE))
vol_node <- list(op = "CS_ZSCORE", args = list(list(op = "MUL", args = list(
  list(op = "TS_STD", window = 126L, args = list(
    list(op = "TS_LAG", k = 1L, unit = "d", args = list(list(leaf = "A1_RAWDATA_OHLCVS_daily:Ret"))), 126)), -1))))
pool_node <- list(op = "CLIP", args = list(
  list(op = "SUB", args = list(51, list(op = "CS_RANK", args = list(mom_leaf)))), 0, 1))
panic_branch <- list(op = "ADD", args = list(
  list(op = "MUL", args = list(pool_node, 100)), vol_node))
base_branch <- list(op = "CS_ZSCORE", args = list(mom_leaf))
AST <- list(op = "IF_ELSE", args = list(panic_leaf, panic_branch, base_branch))
# 방언 병기: ast_verify.py 는 children + DIV; schema.json 은 args + DIV_GUARD.
to_children <- function(n) {
  if (!is.null(n$leaf)) return(n)
  n$children <- lapply(n$args, function(a) if (is.list(a)) to_children(a) else a)
  n$args <- NULL; n }
AST_children <- to_children(AST)

## ── 사전등록 판정 ────────────────────────────────────────────────────────────
prereg <- list(
  F1_risk_predictability = list(
    preregistered = "슬리브 월간 실현분산 확장창 AR(1) OOS R^2 <= 0 이면 조건화 대상 부재 → 기각",
    measured_oos_r2 = num(S2$F1_risk_predictability$oos_r2_level),
    positive_control_market = num(S2$F1_risk_predictability$positive_control_market_ar1_oos_r2),
    us_anchor_wml = 0.5782, verdict = S2$F1_risk_predictability$verdict,
    reading = "위험은 예측된다. 단 미국 롱숏 WML(57.8%)의 1/3 수준이고, 우리 시장 자신(19.0%)보다도 낮다 — 롱온리 승자 슬리브는 BSC 가 이용한 지속성을 그만큼 갖지 않는다."),
  F2_component_attribution = list(
    preregistered = "특이성분 OOS R^2 가 시장성분을 넘지 못하면 이 축은 사실상 시장변동성 타이밍 → 기각",
    idio_oos_r2 = num(S2$F2_component_attribution$oos_r2$idio_comp),
    market_comp_oos_r2 = num(S2$F2_component_attribution$oos_r2$market_comp),
    market_share_of_variance = num(S2$F2_component_attribution$market_share_of_total_variance_median),
    us_anchor = list(idio = 0.4706, market_comp = 0.2087, market_share = 0.23),
    verdict = S2$F2_component_attribution$verdict,
    reading = sprintf(paste("★이 라운드의 진짜 관문이 여기서 닫혔다. 롱온리 승자 top-25 의 총위험 중 시장성분이 중앙값 %.1f%%로",
                    "BSC 의 WML(23%%) 대비 %.1f배이고, 예측 가능한 부분도 시장성분(%.4f) > 특이성분(%.4f) 이다.",
                    "즉 조건화할 대상은 있으나(F1) 그 대상은 특이위험이 아니라 시장노출이며,",
                    "이 경로는 우리 시스템에서 기실패(L-AS-VM_20260607 · DIST-AR-051)한 시장변동성 타이밍과 같다."),
                    100*num(S2$F2_component_attribution$market_share_of_total_variance_median),
                    num(S2$F2_component_attribution$market_share_of_total_variance_median)/0.23,
                    num(S2$F2_component_attribution$oos_r2$market_comp),
                    num(S2$F2_component_attribution$oos_r2$idio_comp))),
  F3_dm_optionality_winner_leg = list(
    preregistered = "beta_BU >= 0 이면 반등월 beta 부족 경로는 KR 롱온리에 미이식",
    beta_BU = num(S3$F3_dm_optionality_winner_leg$beta_BU),
    beta_BU_t = num(S3$F3_dm_optionality_winner_leg$beta_BU_t),
    us_anchor_winner_decile = -0.215, verdict = S3$F3_dm_optionality_winner_leg$verdict,
    reading = sprintf(paste("KR 승자 롱온리의 베어장 up-market beta 증분 = %+.3f 로 US 승자 데실(-0.215)의 %.1f배다.",
                            "부호는 경로 존재를 지지하나 t %+.2f 로 유의하지 않다 — 크지만 미결.",
                            "가설설계 challenge_flags 의 C5(반등월 beta 보정) 승격 조건을 부분 충족한다."),
                      num(S3$F3_dm_optionality_winner_leg$beta_BU),
                      abs(num(S3$F3_dm_optionality_winner_leg$beta_BU))/0.215,
                      num(S3$F3_dm_optionality_winner_leg$beta_BU_t))),
  F4_agent_reality = list(
    preregistered = "패닉월 주체별 순매수 대비가 비패닉월과 구별되지 않으면 agent 기전 기각",
    individual = S3$F4_agent_reality$individual, foreign = S3$F4_agent_reality$foreign,
    institutional = S3$F4_agent_reality$institutional,
    verdict = S3$F4_agent_reality$verdict,
    reading = sprintf(paste("★구별은 되는데 방향이 반대다. 설계가 명명한 주체는 '패닉에 청산당하는 개인 + 저가 재진입하는 외국인·기관' 인데,",
                    "실측은 패닉월에 개인이 순매수로 돌아서고(%+.3f -> %+.3f ADV일, NW-t %+.2f)",
                    "기관이 순매도로 돌아선다(%+.3f -> %+.3f, NW-t %+.2f). 외국인은 무변화(NW-t %+.2f).",
                    "따라서 F4 는 '기전 부재' 가 아니라 '명명한 주체의 역할이 뒤바뀜' 을 판정한다 —",
                    "설계 승계 원칙상 본 에이전트는 mechanism 을 재작성하지 않고 challenge_note 로 재설계를 요청한다."),
                    num(S3$F4_agent_reality$individual$mean_nonpanic), num(S3$F4_agent_reality$individual$mean_panic),
                    num(S3$F4_agent_reality$individual$nw_t),
                    num(S3$F4_agent_reality$institutional$mean_nonpanic), num(S3$F4_agent_reality$institutional$mean_panic),
                    num(S3$F4_agent_reality$institutional$nw_t), num(S3$F4_agent_reality$foreign$nw_t))),
  F5_primary_treatment = list(
    status = "CANCELLED_BY_SESSION_DISCIPLINE",
    note = paste("2026-08-29 도훈 지시 ① — arm 배터리 폐지. 대비 arm 기반 1급 검정(F5)은 취소되고",
                 "판정은 체인 종점의 essence 등급으로 옮겨간다. 본 단계는 후보 1건의 실측 좌표만 발행한다.",
                 "참고로 후보-A0 관측 차는 Calmar", sprintf("%+.4f", num(S4$power_contract$observed_d_calmar)),
                 "· SR", sprintf("%+.4f", num(S4$power_contract$observed_d_sr)), "이며 둘 다 음수다.")),
  F6_post2017_hard = list(
    preregistered = "post-2017 단독 구간 통과를 HARD 로 본다(L-AS-BSC_20260611 next_probe 흡수)",
    candidate_calmar = num(S4$F6_post2017$candidate$calmar), A0_calmar = num(S4$F6_post2017$A0$calmar),
    d_calmar = num(S4$F6_post2017$d_calmar), d_sr = num(S4$F6_post2017$d_sr),
    n_months = num(S4$F6_post2017$candidate$n), verdict = S4$F6_post2017$status,
    reading = "post-2017 단독에서 후보 Calmar 0.115 < 무조건화 0.203. 위험 축 개선이 그 창에서 발생하지 않는다."),
  F7_alpha_guard = list(
    preregistered = "beta-통제 alpha 가 무조건화 대비 -1.0%p 초과 하락하면 reject",
    candidate_alpha_ann_pct = 100*num(S4$F7_alpha_guard$candidate_alpha_ann),
    baseline_alpha_ann_pct = 100*num(S4$F7_alpha_guard$A0_alpha_ann),
    delta_pp = num(S4$F7_alpha_guard$delta_pp), verdict = S4$F7_alpha_guard$status,
    reading = "위험 개선 없이 알파만 -1.34%p 태웠다. 표적 분리의 반대편 못이 발화한 경우다."),
  F8_overlay_pit = list(
    preregistered = "assert_overlay_pit HARD · lag1 스트레스 · strict-PIT A/B · first-day-of-holding-month 컷오프",
    item1_assert = S4$overlay_pit_F8$item1_assert_overlay_pit,
    item2_lag1 = S4$overlay_pit_F8$item2_lag1_stress,
    item3_strict_ab = S4$overlay_pit_F8$item3_strict_ab,
    item4_cutoff = S4$overlay_pit_F8$item4_cutoff_rule,
    verdict = "PASS",
    reading = paste("네 항 모두 통과. ★양성 대조가 핵심이다 — 신호를 1개월 앞당겨 홀딩월 자신의 데이터로 계산한",
                    "위반 주입판은 Calmar 0.228 로 후보(0.183) 대비 +24.5% 인플레하며 무조건화(0.206)마저 넘는다.",
                    "즉 BearProb 실사고와 동형으로, 이 축에서 '오버레이가 작동한다' 는 외관은 1개월 동월 누출로",
                    "전량 제조된다. 계기가 실제로 발화함을 실증했으므로 이 A/B 는 빈 방어선이 아니다.")))

## ── alpha_validation.json ────────────────────────────────────────────────────
mono_dir <- -num(S5$monotonicity)   # dec1 = 최고점수 규약 → 부호 반전이 정상 단조
validation <- list(
  wt_id = "WT-R20260829_004", as_of_date = "2026-08-29",
  metric_type = "canonical_screen",
  measurement_authority = "canonical_screen_bt (screening 실측). SR/Calmar/oos_retention 판정 권위 = forge build_bt_result + essence_score.R",
  session_discipline = list(
    single_measurement = "arm 배터리·형태 분해 셀·탐색 arm·아티팩트 대조·무신호 대조 미구축(2026-08-29 도훈 지시 ①).",
    prerequisites_not_arms = "A0(무조건화)는 F1/F2 가 검정하는 슬리브 자신이자 2/20 cell4 승계 좌표이고, lag1/violation 판은 F8 PIT 계기다 — 셋 다 대비 arm 아님.",
    chain_obligation = "지시 ② — 음성 판정이 체인을 멈추지 않는다. 본 패키지는 risk→optimizer→forge 가 그대로 소비 가능한 완전형으로 발행한다."),
  mandatory_prior_run_disclosure = list(
    L_AS_BSC_20260611_153021 = list(grade = "B",
      note = "BSC2015 KR 롱온리 복제 — SR 0.74 · CAGR 12.0% · MDD 38.6%(Calmar 0.31) · post-2017 alpha t 0.18 소멸",
      relation = "같은 논문·같은 시장·같은 레버 계열. 차별점은 ①현금 없는 구성 교체 ②국면 조건부 발화 ③캐리어(J6 top-25 EW 월간 vs 12-2 VW 데실) ④post-2017 HARD 흡수 넷뿐이고 그 넷은 약하다."),
    L_AS_DM_20260612_080422 = list(grade = "F",
      note = "DM 동적가중 mu/sigma^2 기각(dyn 0.478 < raw 0.558 < cvol 0.596)",
      relation = "mu-hat 성분 전면 배제 — 본 후보에 mu 예측기 없음(코드 실증: score 는 momentum rank 와 실현변동성만 사용)"),
    DIST_AR_036 = list(label = "settled-negative",
      note = "종목단 crash 회피 selection 축", relation = "본 후보는 selection 이 아니라 국면-조건부 구성 교체 — 단 F2 실패로 그 구분의 실익이 사라졌다(아래 재포장 자기신고 참조)"),
    self_report_repackaging = list(
      verdict = "PARTIAL_REPACKAGING",
      statement = paste("현금 스케일링으로 회귀하지 않았다(Sigma w = 1 · 현금 0 · 레버리지 0 · n_max 25 실측).",
                        "그러나 F2 가 닫히면서 이 축의 실질은 '시장노출을 구성으로 조금 줄이는 것'(beta 1.058 -> 1.036)으로 드러났고,",
                        "그건 C3(노출 스케일링)와 형태만 다른 같은 방향이다. 설계가 예고한 '형태 하나의 거리' 가",
                        "실측에서 그 하나마저 얇았다고 정직 기록한다."))),
  power_contract = S4$power_contract,
  preregistered_verdicts = prereg,
  candidate_spec = S4$meta$spec,
  candidate_measured = S4$candidate,
  succession_coordinate_A0 = S4$A0_succession_coordinate,
  inherited_coordinate_parity = list(
    inherited_cell4_port_t = 1.294, measured_A0_port_t = num(S4$A0_succession_coordinate$port_t),
    inherited_beta_ctl_alpha_pct = 5.14, measured_beta_ctl_alpha_pct = 100*num(S4$A0_succession_coordinate$alpha_beta_ctl_ann),
    inherited_beta = 1.058, measured_beta = num(S4$A0_succession_coordinate$beta),
    verdict = "PARITY — 2/20 cell4 좌표가 독립 재구축에서 재현됐다(양성 대조)"),
  cap_tier = S4$cap_tier, firing = S4$firing,
  advisory_battery = list(
    rank_ic = num(S5$rank_ic), rank_ic_base_momentum = num(S5$rank_ic_base_momentum),
    icir = num(S5$icir), harvey_t_stat = num(S5$harvey_t_stat),
    monotonicity = mono_dir,
    monotonicity_convention = "dec1 = 최고점수. 원시 Spearman(dec, mean ret) = -0.855 이므로 방향 정합(부호 반전 기재).",
    subperiod_active_sr = S5$subperiod_active_sr, subperiod_stability = num(S5$subperiod_stability),
    post_neutralization_ic = num(S5$post_neutralization_ic),
    net_active_sr = num(S5$net_active_sr), turnover_annual = num(S5$turnover_annual),
    deflated_sharpe_ratio = num(S5$deflated_sharpe_ratio), n_trials_cumulative = 4,
    dsr_gate_note = S5$dsr_gate_note, cost_feasibility = S5$cost_feasibility),
  redundancy = S5$redundancy,
  mechanism_evidence = list(F1 = S2$F1_risk_predictability, F2 = S2$F2_component_attribution,
                            F3 = S3$F3_dm_optionality_winner_leg, F4 = S3$F4_agent_reality,
                            regime_signal = S2$regime_signal),
  overlay_stage_boundary_decision = list(
    question = "가설설계 W6 escalate — A1(구성 교체)은 alpha 인가 optimizer 인가",
    decision = paste("alpha 구간은 ①후보의 alpha-hat 점수 패널 ②PIT-clean 국면/변동성 신호 시계열만 발행한다.",
                     "period_returns_production.csv 는 canonical_screen_bt(top-25 EW 고정규격) 경유 *스크리닝 실측*이며",
                     "비중 결정이 아니다. 노출·비중으로의 실제 적용은 optimizer/forge 소관이다."),
    pit_s0s1_note = "국면은 alpha 원천이 아니라 위험 조건자로 쓰였다(패닉월 점수는 pool 내부 저변동 순서일 뿐 수익 예측이 아님). 공분산·비중·최적화 산출 0.",
    downstream_inputs = list(
      regime_signal = "stage_artifacts/WT_R20260829_004/regime_signal_timeseries.parquet",
      stock_pred_vol = "stage_artifacts/WT_R20260829_004/stock_pred_vol_panel.parquet",
      sleeve_rv = "stage_artifacts/WT_R20260829_004/sleeve_realized_variance.parquet")),
  artifacts = S5$artifacts)
write_json(validation, file.path(OUT, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")

## ── alpha_package.json ───────────────────────────────────────────────────────
flags <- list(
  sprintf("[F2 FAIL — 이 라운드의 실질 판정] 롱온리 승자 top-25 의 총위험 중 시장성분 중앙값 %.1f%%(BSC WML 23%% 의 %.1f배)이고 예측 가능한 성분도 시장(OOS R^2 %.4f) > 특이(%.4f). 조건화할 대상은 있으나 그 대상이 특이위험이 아니다 — 축의 전제가 절반만 성립한다.", 100*num(S2$F2_component_attribution$market_share_of_total_variance_median), num(S2$F2_component_attribution$market_share_of_total_variance_median)/0.23, num(S2$F2_component_attribution$oos_r2$market_comp), num(S2$F2_component_attribution$oos_r2$idio_comp)),
  sprintf("[F4 방향 반전 — 승계 mechanism 결함, 재작성 금지·재설계 요청] 명명한 agent 는 패닉에 청산당하는 개인 / 저가 재진입하는 기관 인데 실측은 정반대다(개인 순매수 전환 NW-t %+.2f, 기관 순매도 전환 NW-t %+.2f, 외국인 무변화 NW-t %+.2f). Charter 원칙 8 에 따라 hypothesis 를 수정하지 않고 challenge_note.md 에 재설계 요청으로 기록.", num(S3$F4_agent_reality$individual$nw_t), num(S3$F4_agent_reality$institutional$nw_t), num(S3$F4_agent_reality$foreign$nw_t)),
  sprintf("[F6 FAIL] post-2017 단독 Calmar %.3f < 무조건화 %.3f (n=%d개월). L-AS-BSC_20260611 의 next_probe(HARD)가 그대로 발화했다.", num(S4$F6_post2017$candidate$calmar), num(S4$F6_post2017$A0$calmar), as.integer(num(S4$F6_post2017$candidate$n))),
  sprintf("[F7 FAIL] beta-통제 alpha %+.2f%%p (%.2f -> %.2f%%/yr). 위험 개선 없이 알파만 태운 경우 — 표적 분리의 반대편 못.", num(S4$F7_alpha_guard$delta_pp), 100*num(S4$F7_alpha_guard$A0_alpha_ann), 100*num(S4$F7_alpha_guard$candidate_alpha_ann)),
  sprintf("[★검정력은 충분했다] Calmar ratio %.3f · E[t] %.3f · power %.3f (블록 부트스트랩 block=12 SE %.4f, B=%d) / SR ratio %.3f · power %.3f. 사전등록 효과크기는 KR 앵커(L-AS-BSC_20260611)의 절반으로 감쇠한 값이다. 관측 차는 Calmar %+.4f · SR %+.4f 로 둘 다 음수 — 이 음성은 '미결' 이 아니라 powered null 이며 처분이 다르다.", num(S4$power_contract$calmar$ratio), num(S4$power_contract$calmar$expected_t), num(S4$power_contract$calmar$power), num(S4$power_contract$calmar$se_blockboot), as.integer(num(S4$power_contract$B)), num(S4$power_contract$sharpe$ratio), num(S4$power_contract$sharpe$power), num(S4$power_contract$observed_d_calmar), num(S4$power_contract$observed_d_sr)),
  sprintf("[★PIT 양성 대조] 신호를 1개월 앞당긴 위반 주입판은 Calmar %.3f(strict 대비 %+.1f%% 인플레)로 무조건화(%.3f)마저 넘는다. 이 축에서 '오버레이가 작동한다' 는 외관은 동월 누출로 전량 제조된다 — BearProb 실사고와 동형. lag1 스트레스는 붕괴 없음(%+.1f%%).", num(S4$overlay_pit_F8$item3_strict_ab$positive_control_violation_probe$calmar), 100*num(S4$overlay_pit_F8$item3_strict_ab$positive_control_violation_probe$inflation_calmar), num(S4$A0_succession_coordinate$calmar), 100*num(S4$overlay_pit_F8$item2_lag1_stress$rel_change_calmar)),
  sprintf("[재포장 자기신고 PARTIAL] 현금 스케일링 회귀는 없었다(Sigma w=1 · 현금 0 · 레버리지 0 · n_max %d 실측 · 비패닉월 보유 중복도 %.3f). 그러나 F2 가 닫히면서 실질이 'beta 를 %.3f -> %.3f 로 구성으로 조금 줄이기' 로 드러났고, C3(노출 스케일링)와의 거리가 설계가 예고한 '형태 하나' 보다도 얇았다.", as.integer(num(S4$candidate$n_names_max)), num(S4$firing$mean_overlap_nonpanic), num(S4$A0_succession_coordinate$beta), num(S4$candidate$beta)),
  sprintf("[미탐색 인접] F3 beta_BU = %+.3f (US 승자 데실 앵커 -0.215 의 %.1f배, t %+.2f 비유의). 가설설계 challenge_flags 의 C5(패닉월 고beta 승자 편입 = 부호 반대 축) 승격 조건을 부분 충족 — 다만 표적이 절대위험이면 상충한다.", num(S3$F3_dm_optionality_winner_leg$beta_BU), abs(num(S3$F3_dm_optionality_winner_leg$beta_BU))/0.215, num(S3$F3_dm_optionality_winner_leg$beta_BU_t)),
  "[하드코딩 고지] pool = top-50(=2N) 은 논문 미명시 축이다. 25 를 전부 교체 가능한 최소 pool 이라는 근거로 단일 고정했고 sweep 하지 않았다(단일 측정 규율). POOL_OFFSET 100 은 순서 보장용 상수로 판정에 무관하다.",
  "[역할 경계] 종목 위험은 단변량 실현변동성 126일만 사용했다 — 공분산 기반 위험기여(marginal contribution to risk)는 Risk agent 소관이라 alpha 구간에서 추정하지 않았다. 따라서 '변동성 기여 상위 교체' 는 기여가 아니라 변동성 수준 교체로 구현됐다(설계 대비 약화 — 정직 기록).",
  "[검정력 계약 vs 체인 완주 충돌 해소] 가설설계 (C) 는 ratio<0.15 시 착수 중단을 규정하나 실측 ratio 는 착수금지구간 밖이다(Calmar 1.11 · SR 0.85). 지시 ②(체인 완주)와의 충돌 지점 미발생.",
  "[★PIT 수리 — 계기가 잡아낸 실제 결함] ast_verify.py 가 초판에서 A1_RAWDATA_OHLCVS_daily:Ret 의 same-day 사용을 LOOKAHEAD 로 적발했다(ref_ts+t1 > decision_ts). 이를 받아 종목 실현변동성 126일 · 시장 실현변동성 126일 · I_B 24개월 누적 종가를 전부 strict t-1(Date < 신호일)로 조이고 전 측정을 재실행했다. AST 는 TS_LAG(k=1, unit=d) 로 그 수리를 표현한다. 재측정 후 검증기 방언 probe = PASS(max_avail_ts 2026-08-28 <= decision_ts 2026-08-28 · violations 0).",
  "[계약 표면 분열 — 하네스 수리 대상] 정본(schema.json 방언) 판정은 FAIL_CONTRACT 이나 사유는 전부 표기 형식이다(리프 문자열+escape_contract vs FIELD 분해 평면 / args vs children / bare scalar vs {const:n}). 같은 트리를 검증기 방언으로 옮긴 probe 는 PASS 이고 leaf_count 4 · op_count 11 로 동일하다. 003 라운드가 기록한 DIV/DIV_GUARD 분열과 같은 계통이며 본 트리는 나눗셈을 쓰지 않아 그 갈래에는 닿지 않는다.")

pkg <- list(
  task_id = "WT-R20260829_004",
  strategy_id = "WT-R20260829_004_JT1993_regime_conditional_composition_derisking",
  as_of_date = "2026-08-29", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  wt_type = "reinforcement", keyword_axis = "risk_overlay",
  pit = list(sig_date = as.character(as_of),
             decision_ts = as.character(as_of),
             cutoff_rule = "overlay signal cutoff = first-day-of-holding-month (assert_overlay_pit PASS)"),
  hypothesis = list(
    statement = HYP$selected$hypothesis_title,
    mechanism = HYP$selected$mechanism,
    falsification = HYP$selected$falsification$observable,
    regime_scope = HYP$selected$regime_scope),
  hypothesis_inheritance = list(
    source = "qepm/mailbox/worktask/WT-R20260829_004/alpha_hypothesis.json",
    designed_by = "alpha-hypothesis (opus)",
    rewritten_by_alpha_research = FALSE,
    note = "mechanism / falsification / regime_scope 전량 승계 — 재작성 금지(Charter 원칙 8). F4 가 드러낸 agent 방향 반전은 수정이 아니라 challenge_note.md 재설계 요청으로 처리."),
  ast = AST, ast_children_dialect = AST_children,
  ast_dialect_note = paste("구조 방언 병기: schema.json #/definitions/ast_node 는 args, ast_verify.py 는 children 를 읽는다.",
                           "정본(ast)은 schema 형식이고 ast_children_dialect 는 검증기 형식이다. DIV/DIV_GUARD 는 본 트리에 미사용."),
  factors = list(list(
    factor_id = "F1_regime_conditional_composition",
    ast = AST, role = "core_signal", restatement_exposure = 1,
    restatement_note = "A1_RAWDATA_OHLCVS_daily 는 수정주가 전기간 재작성 대상(restatement_prone)")),
  combination_rule = "z_score_aligned_weighted_sum",
  combination_note = "국면 지시자에 따른 두 z 축의 배타적 가중(비패닉 = 모멘텀 1.0 / 패닉 = pool 내부 저변동 1.0). IF_ELSE 로 표현.",
  verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
    list(leaf = "A1_RAWDATA_OHLCVS_daily:Ret", availability_rule = "fixed: t-1 close", restatement_prone = TRUE),
    list(leaf = "A4_benchmark_kospi200:BM_Close", availability_rule = "fixed: t-1 close", restatement_prone = FALSE),
    list(leaf = "SPECIAL_OP:JT1993_FORMATION", availability_rule = "walk_forward, t-2..t-7 월간 수익만", restatement_prone = TRUE),
    list(leaf = "SPECIAL_OP:PANIC_REGIME", availability_rule = "walk_forward 확장창 · 신호월말까지", restatement_prone = FALSE)),
    verdict = "clean",
    notes = paste("C1 확장창만(AR(1)·확장창 중앙값 전부 walk-forward) · C2 동일자 순환 없음 ·",
                  "C6 K200/KQ150 시변 멤버십 · C10 유동성 20일 평균 t-1 · C13 방향정렬 z 만 ·",
                  "C15 는 미해당(Factor DB parquet 직접 로드 없음 — 중복성 진단에서만 load_month_factors 경유).",
                  "DM2016 의 I~_U(동시대 up-market 더미)는 F3 진단 회귀에만 쓰였고 신호·선별·비중에 진입하지 않았다.")),
  alpha_vector = alpha_vec, confidence_vector = conf_vec,
  alpha_vector_note = paste("as_of", as.character(as_of), "· 패닉여부", panic_last,
    "· alpha-hat = (월별 횡단면 OLS 기울기의 확장창 평균", sprintf("%.6f", slope_m), ") x z_axis.",
    "z_axis 는 패닉월이면 pool 내부 z(-vol126), 아니면 z(모멘텀). 상위 25종만 발행(전 유니버스 점수는 parquet)."),
  signal_matrix_ref = "stage_artifacts/WT_R20260829_004/alpha_scores.parquet",
  regime_signal_ref = "stage_artifacts/WT_R20260829_004/regime_signal_timeseries.parquet",
  stock_pred_vol_ref = "stage_artifacts/WT_R20260829_004/stock_pred_vol_panel.parquet",
  sleeve_realized_variance_ref = "stage_artifacts/WT_R20260829_004/sleeve_realized_variance.parquet",
  period_returns_production_ref = "stage_artifacts/WT_R20260829_004/period_returns_production.csv",
  factor_specs = list(
    list(factor_family = "Momentum", proxy = "JT1993 J=6 formation (skip 1M)",
         formula = "sum_{k=2..7} log(1 + r_{t-k}^{monthly})",
         lag_rule = "t-1 close (price)", winsorization = "none (rank/z only)",
         neutralization = "none (진단으로 log-Size 중립화 IC 병기)",
         economic_rationale = "underreaction/delayed overreaction — 기저 신호 승계(RP_20260829_122020_9192)",
         weight_theta = 1.0, redundancy_cluster_id = "momentum_price_6m",
         references = list("Jegadeesh & Titman 1993 JF")),
    list(factor_family = "Risk (conditional)", proxy = "126d realized volatility (univariate)",
         formula = "sd(Ret, 126d) * sqrt(252), 패닉월 pool 내부 오름차순 선택",
         lag_rule = "t-1 close · 신호월말까지", winsorization = "none",
         neutralization = "none",
         economic_rationale = "국면 조건부 위험 경로 재형성 — 현금·레버리지 없이 구성으로만(BSC2015 의 스케일 자유도가 long-only Sigma w=1 에 부재)",
         weight_theta = 1.0, redundancy_cluster_id = "low_volatility_realized",
         references = list("Barroso & Santa-Clara 2015 JFE", "Daniel & Moskowitz 2016 JFE"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(S4$candidate$port_t),
    canonical_port_t_pvalue = as.numeric(O4$M_cand$cs$portfolio_alpha_t_pvalue),
    canonical_n_months = num(S4$candidate$n_months),
    canonical_port_t_note = "canonical_screen_bt(top_n=25, EW, 15bps) 실측 · metric_type=canonical_screen",
    portfolio_alpha_t_beta_controlled = num(S4$candidate$t_alpha_beta_ctl),
    portfolio_alpha_beta_controlled_ann = num(S4$candidate$alpha_beta_ctl_ann),
    beta = num(S4$candidate$beta),
    ew_universe_port_t = num(S4$candidate$ew_univ_port_t),
    sr = num(S4$candidate$sr), cagr = num(S4$candidate$cagr), mdd = num(S4$candidate$mdd),
    calmar = num(S4$candidate$calmar),
    sr_calmar_note = "canonical_screen 계열 파생값 — 판정 권위는 forge build_bt_result + essence_score.R",
    rank_ic = num(S5$rank_ic), icir = num(S5$icir), harvey_t_stat = num(S5$harvey_t_stat),
    harvey_t_note = "rank-IC 시계열 NW t — portfolio-alpha t 와 다른 양(measurement-graduation §2). 둘 다 병기.",
    monotonicity = mono_dir, subperiod_stability = num(S5$subperiod_stability),
    post_neutralization_ic = num(S5$post_neutralization_ic),
    turnover_proxy = num(S5$turnover_annual),
    net_of_cost_active_sr = num(S5$net_active_sr),
    deflated_sharpe_ratio = num(S5$deflated_sharpe_ratio),
    n_names_max = num(S4$candidate$n_names_max)),
  alpha_discovery_count = 0,
  selection_objective = "canonical_port_t",
  n_trials = 1, selection_type = "chain",
  n_trials_cumulative = 4,
  preregistered_verdicts = prereg,
  power_contract = S4$power_contract,
  overlay_pit_F8 = S4$overlay_pit_F8,
  mandatory_prior_run_disclosure = validation$mandatory_prior_run_disclosure,
  overlay_stage_boundary_decision = validation$overlay_stage_boundary_decision,
  session_discipline = validation$session_discipline,
  challenge_flags = flags,
  validation_ref = "stage_artifacts/WT_R20260829_004/alpha_validation.json")
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_004", package_type = "alpha_package",
  method_selected = "JT1993 J6 top-25 EW + 국면조건부(패닉월) pool-내 저변동 구성 교체 — 단일 실투형 후보",
  input_file_paths = c(file.path(OUT, "panel.rds"), file.path(OUT, "s2_mech.json"),
                       file.path(OUT, "s3_side.json"), file.path(OUT, "s4_candidate.json"),
                       file.path(OUT, "s5_diag.json"), file.path(OUT, "alpha_validation.json")))

cat(sprintf("[S6] alpha_package.json 발행 · alpha_vector %d 종목 · as_of %s (panic=%d) · slope=%.6f\n",
            length(alpha_vec), as.character(as_of), panic_last, slope_m))
cat(sprintf("[S6] verdicts: F1=%s F2=%s F3=%s F4=%s F6=%s F7=%s F8=PASS\n",
            prereg$F1_risk_predictability$verdict, prereg$F2_component_attribution$verdict,
            prereg$F3_dm_optionality_winner_leg$verdict, prereg$F4_agent_reality$verdict,
            prereg$F6_post2017_hard$verdict, prereg$F7_alpha_guard$verdict))
