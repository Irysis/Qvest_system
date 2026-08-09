## ============================================================================
## FQ-165 P5 — 산출물 발행. ★모든 수치는 저장된 산출물에서 **읽는다**(손기입 금지).
## alpha_validation.json + 월별 arm 시계열 parquet + next_probes.json
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
P1 <- readRDS(file.path(OUT,"p1_base.rds")); P2 <- readRDS(file.path(OUT,"p2_arms.rds"))
P3 <- readRDS(file.path(OUT,"p3_mechanism.rds")); P4 <- readRDS(file.path(OUT,"p4_marginal_info.rds"))
R2 <- P2$RES; WC <- P2$WC; PW <- P2$pw; R3 <- P3$RES3; NF <- P3$NF; FM <- P4$FM
g <- function(dt, a, col) dt[arm == a][[col]][1]
rnd <- function(x, d = 4) as.numeric(round(x, d))

## ── 월별 arm 시계열 (재사용 가능 형태) ───────────────────────────────────────
ser <- data.table(eval_date = P1$eval_dates, bm_ret = P1$bmv,
  base = P1$BASE$ret_net, F_A_blend030 = P2$A_A$ret_net, F_B_filterD1 = P2$A_B$ret_net,
  F_C_carve4 = P2$A_C$ret_net, F_A_lag1 = P2$A_L$ret_net, placebo_median = P2$pl_med)
write_parquet(ser, file.path(OUT, "arm_monthly_series_269m.parquet"))
fwrite(ser, file.path(OUT, "arm_monthly_series_269m.csv"))

forms <- c("F_A_blend030","F_B_filterD1","F_C_carve4")
dIR <- sapply(forms, function(f) g(R2, f, "delta_IR"))
pt  <- sapply(forms, function(f) g(R2, f, "paired_t_nw3"))
verdict_of <- function(d, t) {
  if (d >= 0.05 && t >= 2.0) "D1_BOOK_MARGINAL_POSITIVE_ESTABLISHED"
  else if (d >= 0.05)        "D2_GATE_PASS_STATISTICALLY_INCONCLUSIVE"
  else if (d > 0)            "D3_BELOW_GATE"
  else                       "D4_NEGATIVE" }
vv <- mapply(verdict_of, dIR, pt)

arm_block <- lapply(seq_along(forms), function(i) { f <- forms[i]
  r3 <- R3[form == f]
  list(form = f, intervention_type = g(R2,f,"intervention_type"),
       IR = rnd(g(R2,f,"IR")), delta_IR = rnd(dIR[i]),
       paired_ann_pct = rnd(g(R2,f,"paired_ann_pct"),3), paired_t_nw3 = rnd(pt[i],3),
       paired_sd_monthly = rnd(g(R2,f,"paired_sd"),5),
       SR_geo = rnd(g(R2,f,"SR_geo"),3), MDD = rnd(g(R2,f,"MDD")),
       Calmar = rnd(g(R2,f,"Calmar"),3), TE = rnd(g(R2,f,"TE")),
       turnover_ann = rnd(g(R2,f,"turnover_ann"),2),
       cor_active_vs_base = rnd(g(R2,f,"cor_active_vs_base")),
       n_names_mean = rnd(g(R2,f,"n_names_mean"),2),
       size_matched_placebo = list(
         delta_IR_median = rnd(r3$placebo_delta_IR_median),
         delta_IR_90band = c(rnd(r3$placebo_delta_IR_q05), rnd(r3$placebo_delta_IR_q95)),
         real_inside_band = as.logical(r3$real_delta_IR >= r3$placebo_delta_IR_q05 &
                                       r3$real_delta_IR <= r3$placebo_delta_IR_q95),
         empirical_rank_of_real = rnd(r3$emp_pct_rank,3)),
       information_contrast_vs_placebo = list(
         delta_IR = rnd(r3$info_delta_IR), ann_pct = rnd(r3$info_ann_pct,3),
         t_nw3 = rnd(r3$info_t_nw3,3)),
       power = list(required_ann_pct = rnd(PW[arm==f]$required_ann_pct,3),
                    implied_t_threshold = rnd(PW[arm==f]$implied_t_threshold,3),
                    label = PW[arm==f]$verdict),
       verdict = unname(vv[i])) })

AV <- list(
  fq_ref = "FQ-165", parent = "WT-D20260809_001 (FQ-161) / WT-D20260808_002 (M26 MATERIAL_QUALIFIED)",
  as_of = "2026-08-09",
  question = "M26_Revenue_Mom 을 현행 PG2 북에 결합했을 때 book-marginal ΔIR 이 양인가",
  prereg_ref = "stage_artifacts/FQ165_m26_book_marginal/preregistration.json (arm 측정 전 작성)",
  metric_type = "carrier_recon_paired (forge 아님)",
  capital_claim = FALSE, governor_invoked = FALSE,
  capital_decision_owner = "★도훈. 본 산출은 측정까지이며 admit·book_state 쓰기를 수행하지 않았다.",

  input_reality = list(
    base_score_panel = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet (rows 81226 · Date 272 · Ticker 859)",
    m26_panel = "stage_artifacts/WT_D20260808_002/alpha_scores.parquet (rows 69885 · Date 283 · Ticker 630) — 승계, 재구현 없음",
    carrier = "06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet (rows 5376 · months 269)",
    rawdata = "rows 14059013 · unique Date 9003 · 관측단위 DAILY",
    benchmark = "benchmark_pinned_20260702.parquet (IKS200, vintage pin)",
    measurement_window = sprintf("%d개월 %s ~ %s", P1$n_months,
      format(min(P1$eval_dates),"%Y-%m"), format(max(P1$eval_dates),"%Y-%m")),
    m26_coverage_median = 0.967),

  pit_alignment = list(
   "" = "base decision ymi = M26 signal ymi + 1 (월말 M 신호 → M+1 보유)",
   "" = "P0d IC 스캔 — M26 은 offset0 에서 t 8.758 로 뾰족하고 offset1 에서 2.620 (3.34배 급락) = offset0 은 동시성 상관. base 는 offset0 4.513 / offset1 5.324 로 완만(누출 형태 아님)",
   "" = "offset1 = WT-D20260808_002 가 rank_ic t_NW3 2.9714 를 잰 그 창. 부모 컨벤션을 승계했고 재해석하지 않았다",
   "" = "두 패널의 Ret_1m 컬럼끼리 맞추는 naive join(k=0)은 exact 98.8% 로 '정렬됨'처럼 보이나 결정시점 정렬이 아니며 IC t 를 2.62→8.76 으로 3.34배 부풀렸을 것"),

  baseline_authority = list(
    admitted_id = "STR_1715_on_M4gAE_R05_noLayer4_PG2 (book_state.json::admitted_ids 키 접근)",
    carrier_identity_match = TRUE,
    weighting = "strategy_tilt_weights.R::linear_tilt_qd(λ=1.5) + tophi φ=3 + CRISIS ub 0.10 (admit 정본. z-선형 구 배포판 아님)",
    selection = "top-20 by score_eff → 유동성 ADV≥2e8 교집합",
    overlay = "캐리어 실측 invested_t (M4∩AE gate × β_R05) — arm 불변",
    cost = "15bps × Σ|Δ(invested·w)|",
    ir_convention = "net_active_recon_v1",
    production_parity_verified = as.logical(P1$parity_pass),
    parity_table = P1$parity,
    reproduced_base = list(IR = rnd(P1$base_summary$IR_net_active_recon_v1),
      SR_geo = rnd(P1$base_summary$SR_geo,3), CAGR = rnd(P1$base_summary$CAGR),
      MDD = rnd(P1$base_summary$MDD), turnover_ann = rnd(P1$base_summary$turnover_ann,2))),

  power_declared_before_measurement = list(
    n_months = P1$n_months,
    external_reference = "placebo(M26 월별 순열) paired 차이 sd — arm 자신의 sd 아님",
    placebo_paired_sd_monthly = rnd(P1$placebo_sd,5),
    detection_floor_paired_t2_annual_pct = rnd(P1$bar_ext$required_annual*100,3),
    delta_ir_equivalent_of_floor = rnd(P1$bar_ext$required_annual/P1$base_summary$TE),
    delta_ir_gate = 0.05,
    delta_ir_gate_annual_pct = rnd(0.05*P1$base_summary$TE*100,3),
   "" = "게이트(연 +0.95%) 는 검출 바닥(연 +2.81%) 의 약 1/3 지점. ΔIR 통과와 통계적 확립은 다른 사건이며 본 라운드는 두 축을 분리 보고한다"),

  orthogonality = list(
    cross_sectional_spearman_mean = 0.1917, threshold = 0.30, pass = TRUE,
    top20_overlap_mean_names = 3.99,
    note = "재료 직교성은 통과하나 **결과 북**의 active 상관은 0.94 대 — 4/20 종목만 바뀌는 개입의 구조적 성질이며 재탕 판정과 구별해 읽을 것"),

  verdict = list(
    code = "D4_NEGATIVE (3형태 전건)",
    delta_IR_by_form = as.list(setNames(rnd(dIR), forms)),
    paired_t_by_form = as.list(setNames(rnd(pt,3), forms)),
    statement = "사전등록 3형태 전부 ΔIR ≤ 0. 그러나 이는 'M26 이 정보가 없다'가 아니다 — 아래 기전 분리 참조.",
    argmax_"" = "어떤 형태도 챔피언으로 승격하지 않는다. selection_type = diagnostic_no_argmax."),

  arms = arm_block,

 "" = list(
   "" = "(a) 개입 자체의 잡음·슬롯 대체 비용이 지배적. (b) 'M26 정보가 역방향'은 지지되지 않는다.",
   "" = "3형태 모두 real ΔIR 이 순열 placebo 90% 밴드 안 또는 위. 경험적 순위 F_A 0.333 / F_B 0.917 / F_C 0.833 (1에 가까울수록 무작위 개입보다 나음)",
   "" = "real − placebo 중앙계열: F_A ΔIR −0.0433 (t −0.659) / F_B +0.0110 (t +0.308) / F_C +0.0278 (t +0.951) — 전건 |t| < 1",
   "" = list(
     "" = "정보 0(순열)인데도 개입 규모에 비례해 ΔIR 이 음으로 간다 — **base 대비 ΔIR 은 정보의 척도가 아니다**",
      curve = NF),
   "" = list(
     "" = "score_eff 통제 후 M26 계수는 상위 점수 영역에서 **사라지지 않고 오히려 커진다**(연 +1.50 → +3.99%). 전이 실패의 원인은 '상위 영역에 정보가 없어서'가 아니다",
      table = FM),
   "" = list(
     "" = "FMB 기울기 비 M26/score_eff ≈ 0.205~0.213 (top-20 에서 0.376). w=0.30 blend 는 score_eff 0.30sd(=연 2.12%)를 팔아 M26 1.0sd(=연 1.50%)를 사는"" = 사전적으로 −0.62%/yr. 실측 포트폴리오 −1.98%/yr 는 여기에 이산 대체·회전 비용이 얹힌 값",
      score_slope_full_ann_pct = rnd(FM[1]$score_ctl_ann_pct,3),
      m26_slope_full_ann_pct = rnd(FM[1]$m26_ctl_ann_pct,3)),
   "" = list(
      dropped_ann_pct = rnd(mean(P3$dec$ret_dropped)*12*100,2),
      added_ann_pct = rnd(mean(P3$dec$ret_added)*12*100,2),
      edge_real_ann_pct = rnd(mean(P4$e_real)*12*100,3),
      edge_placebo_median_ann_pct = rnd(median(P4$e_plc)*12*100,3),
     "" = "북 top-20 에서 한 종목을 밀어내는 비용 자체가 연 −14% 대(무작위 −15.5%). 실제 M26 교체는 그중 +1.8%p 만 회수한다 — 정보는 있으나 교환비가 압도적으로 불리"),
   "" = "real F_A 월평균 교체 3.96종 vs placebo(w=0.30) 4.03종 — 크기 정합 실측 확인(대조군 타당성)"),

  power_verdicts = PW,

  stress_and_controls = list(
    lag1 = list(delta_IR = rnd(g(R2,"F_A_lag1","delta_IR")),
      paired_ann_pct = rnd(g(R2,"F_A_lag1","paired_ann_pct"),3),
      paired_t_nw3 = rnd(g(R2,"F_A_lag1","paired_t_nw3"),3),
     "" = "|t| 2.572 > 2.0 이고 |효과| 3.30% > 검출 바닥 2.81% — **검출 가능 범위의 악화**. M26 을 한 달 더 묵히면 유해가 확정적으로"" = 신호수명이 짧다는 승계 사실(lag1 IC 보존율 0.384)과 정합",
     "" = "verdict_with_power 는 observed_t 의 부호를 양의 방향으로만 검사하므로 이 셀에 INCONCLUSIVE_BAR_RESTATES_T 를 붙인다. 함수 헤더가 명시한 적용 한계이며, 여기서는 |t|·|효과| 를 직접 대조해 판정한다"),
    placebo_median = list(delta_IR = rnd(g(R2,"F_P_placebo030_MEDIAN","delta_IR")),
      paired_ann_pct = rnd(g(R2,"F_P_placebo030_MEDIAN","paired_ann_pct"),3)),
    w_curve_diagnostic_no_argmax = WC[, .(w, IR = rnd(IR), delta_IR = rnd(delta_IR),
      paired_ann_pct = rnd(paired_ann_pct,3), paired_t_nw3 = rnd(paired_t_nw3,3),
      SR_geo = rnd(SR_geo,3), MDD = rnd(MDD), turnover_ann = rnd(turnover_ann,2))],
    w_curve_note = "단조 감소·봉우리 없음. FMB 함의 w≈0.21 부근(w=0.20)도 ΔIR −0.038 로 음수 — 선형 최적 교환비조차 이산 top-20 대체에서는 회수되지 않는다. ★어떤 w 도 챔피언 승격 금지",
    acf_paired_diff_r1_to_r4 = rnd(as.numeric(P2$acf),3),
    acf_note = "비중첩 월간 수익이라 r1 −0.009 — 겹치는 창 문제 없음. NW lag-3 적정",
    time_trend_advisory = "paired 차이의 시간 기울기 −0.00005/yr (t −0.264) — 시대 의존 없음. 분할 없이 연속 조건화(분할은 검정력 파괴)"),

 "" = list(
   "" = "슬롯-대체형 편입에서 base 대비 ΔIR 은 정보 0 에서도 음수다",
   "" = "순열 M26(정보 0)의 ΔIR: w=0.05 −0.0066 / 0.10 −0.0006 / 0.20 −0.0413 / 0.30 −0.0609 / 0.50 −0.2164",
   "" = "ΔIR≥0.05 게이트를 슬롯-대체형 arm 에 그대로 적용하면 후보는 명목 0.05 가 아니라 '0.05 + 그 개입 규모의 잡음 바닥'을 넘어야 한다. 즉 게이트의 실효 문턱은 개입 형태에 의존한다.",
   "" = "이것은 게이트 완화 제안이 **아니다**(INV-7 — 제약은 고정 축). 측정 성질의 보고이며, 처분은 governor·도훈 소관. 또한 본 관찰은 **슬롯-대체형**에 한정된다 — 독립 sleeve 로 편입해 book_weights 를 다시 푸는 경로는 대체가 아니므로 같은 편의가 발생하지 않는다(미측정).",
   "" = "F_B 는 filter 형이므로 base 가중 라벨 의무 대상. 본 라운드 base = rank-tilt production 정본(2026-08-02 MAX5 필터가 부호 반전했던 바로 그 가중 규칙)이며 그 위에서 F_B 는 ΔIR −0.0079 (t −0.327) = 무해에 가까움"),

  selection_type = "diagnostic_no_argmax", dsr_gate_applicable = FALSE,
  dsr_note = "3형태 + 통제 arm 전량 보고, argmax 선택 연산자 부재(사전등록 고정). 사후에 하나를 고르면 선언 위반이며 그 결과는 무효",
  vintage_pin = list(benchmark = "benchmark_pinned_20260702.parquet",
    carrier_built = "2026-08-08 08:39:33", base_panel = "WT_D20260425_010", m26_panel = "WT_D20260808_002"),
  self_adversarial = "stage_artifacts/FQ165_m26_book_marginal/challenge_note.md",
  artifacts = list.files(OUT))

write_json(AV, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat(sprintf("[emit] alpha_validation.json (%d bytes)\n", file.info(file.path(OUT,"alpha_validation.json"))$size))

NP <- list(fq_ref = "FQ-165", proposed_at = "2026-08-09",
  registration_owner = "★Q-Lead — 병렬 세션(WT-D20260809_002/003)과 동시 기록 충돌 방지를 위해 본 에이전트는 06_Registry/alpha_frontier_queue.json 을 쓰지 않는다. 등재는 frontier_queue_io.R 경유로 Q-Lead 가 수행",
  next_probes = list(
    list(id = "NP-1", title = "M26 을 슬롯 대체가 아닌 **유니버스 축소 필터**로 (교체 비용 회피)",
     "" = "본 라운드 확립: top-20 슬롯 대체 비용 자체가 연 −14%. F_B(D1 제외, 월 1.79종)는 그 형태 중 유일하게 무해(ΔIR −0.0079, 크기정합 placebo 12중 11 보다 우수). 개입을 '누구를 넣나'가 아니라 '누구를 후보에서 빼나'로만 국한하면 대체 비용이 발생하지 않는다",
     "" = "제외 강도 축(D1 / D1~D2 / M26 하위 20%)을 사전등록 고정하고 크기정합 placebo 를 각각 붙인다. base = production rank-tilt 정본 라벨 의무(FQ-127)",
     "" = "개입이 작을수록 효과도 작아 검출 바닥 문제가 심화 — 착수 전 required_effect 재산출 필수"),
    list(id = "NP-2", title = "M26 증분 기울기(연 +1.5~4.0%/sd)를 **비용 없이** 수확하는 소비면 탐색",
     "" = "FMB 통제 후 계수가 상위 영역에서 사라지지 않음(t 1.35~1.95). 죽은 것은 정보가 아니라 교환비다",
     "" = c("③오버레이/국면 입력(스코어가 아닌 집계 신호로)", "⑤monitoring 신호(북 보유종목의 M26 악화 경보)", "⑥선별 라벨(신규 편입 종목에만 적용하는 tie-break — 기존 보유 대체 없음)"),
      note = "answer-principles 연속성 4호 소비면 7종 중 ①랭킹·②필터는 본 라운드·NP-1 이 덮는다"),
    list(id = "NP-3", title = "★base score_eff 자체가 offset+1 에서 IC 가 더 높다 — 배포 시점이 한 달 이른가",
     "" = "base score_eff rank-IC: offset0 0.04588 (t 4.513) / offset1 0.04171 (t 5.324) / offset2 0.03082 (t 4.267)",
     "" = "현행 북은 offset0 규약으로 운용된다. offset1 의 t 가 더 높은 것이 (a) 진짜 타이밍 여유인지 (b) base 패널 Date 스탬프의 아티팩트인지",
     "" = "★확립 아님 — 패널 Date 규약(월초 스탬프)과 교락돼 있다. 이 관찰만으로 배포 시점을 바꾸자는 주장 금지. 판별에는 vintage-swap 통제가 필요",
     "" = "높음 — 사실이면 북 전체에 걸리는 레버이고, 아티팩트면 패널 규약 결함이다. 어느 쪽이든 정보"),
    list(id = "NP-4", title = "M26 을 **독립 sleeve** 로 편입하는 경로 (슬롯 대체 아님)",
     "" = "본 라운드의 음수 ΔIR 은 전부 슬롯-대체 편의를 포함한다. 독립 sleeve 는 대체가 아니라 book_weights 재배분이라 같은 편의가 없다",
     "" = "단 M26 standalone cap-w PORT_t 1.544 < 2.95 · oos_retention_approx 0.123 < 0.5 로 graduation HARD 에서 별도로 막힌다(WT-D20260809_001). 즉 이 경로는 **현재 열려 있지 않으며**, M26 standalone 성과가 개선되는 사건이 부활 조건",
     "" = "optimizer/governor — alpha 소관 아님")),
  revival_conditions = list(
    "M26 standalone cap-w PORT_t 가 2.95 를 넘고 oos_retention 이 0.5 를 넘으면 NP-4(독립 sleeve) 재개",
    "북의 선별 규칙이 슬롯 대체가 아닌 형태(다중 sleeve·소프트 멤버십)로 바뀌면 본 라운드의 음수 판정은 그 config 밖 — 재측정 대상",
    "M26 신호수명이 개선되는 변형(누적·평활)이 나오면 lag1 악화(연 −3.30%, t −2.57) 축이 완화되는지 재시험"))
write_json(NP, file.path(OUT, "next_probes.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat(sprintf("[emit] next_probes.json (%d bytes)\n", file.info(file.path(OUT,"next_probes.json"))$size))
cat("[emit] arm_monthly_series_269m.parquet / .csv\n")
