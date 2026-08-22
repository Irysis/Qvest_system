## WT-D20260822_009 — 산출물 발행 (alpha_scores.parquet / alpha_validation.json / alpha_package.json)
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT-D20260822_009")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260822_009")
say <- function(f,...) cat(sprintf(paste0("[e] ",f,"\n"),...))
rj <- function(p) fromJSON(file.path(OUT,p), simplifyVector = FALSE)
PRE <- rj("PREREG.json"); PC <- rj("00_precheck.json"); M <- rj("10_measure.json")
D <- rj("11_diag.json"); POS <- rj("12_poscontrol.json"); AT <- rj("13_attrib.json")
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector = FALSE)
O <- readRDS(file.path(OUT,"10_measure_objects.rds"))

## ── alpha_scores.parquet ───────────────────────────────────────────────────
SC <- O$SMx[, .(Date, Ticker,
   alpha_score = ifelse(excluded, NA_real_, sc),   # 배제군은 후보 자격 없음(랭킹 미부여)
   base_score_eff = sc, absorb, excluded)]
SC[, `:=`(metric_type = "weighted_screen",
          spec_id = "WT009_absorbLo20_exclusion",
          direction_note = "alpha_score = base score_eff(production_parity_verified) on 배제 후 잔여 유니버스. absorb 는 랭킹에 미등장 — 이진 배제 게이트로만 소비.")]
write_parquet(SC, file.path(OUT,"alpha_scores.parquet"))
say("alpha_scores.parquet %d행 / 배제 %d행", nrow(SC), SC[excluded==TRUE,.N])

## ── 판정 라벨 ──────────────────────────────────────────────────────────────
dir_ <- M$paired$delta_ir; t_ <- M$paired$paired_nw_t; md <- abs(M$paired$mean_d_active)
mde <- PC$power$mde_full_monthly
label <- if (dir_ >= 0.05 && t_ >= 1.70) "CONFIRMED" else
         if (dir_ >= 0.05 && t_ > 0) "DIRECTIONAL_UNDERPOWERED" else
         if (dir_ < 0 && t_ <= -1.70) "ADVERSE" else
         if (abs(dir_) < 0.05 && md < mde) "NULL_UNDERPOWERED" else
         "ADVERSE_DIRECTIONAL_DETECTION_UNRESOLVED"

V <- list(
  task_id = "WT-D20260822_009", as_of_date = "2026-08-22",
  hypothesis_title = HYP$selected$hypothesis_title,
  prereg_ref = "stage_artifacts/WT-D20260822_009/PREREG.json",
  selection_type = "preregistered_single_primary", n_trials = 1,
  dsr_applicability = "부적용(sweep 아님) — 수치 미산출, 사유 = 단일 사전등록 primary 1회 측정",

  measurement_integrity = list(
    base_anchor = M$base_anchor,
    pit = PC$pit,
    metric_types = list(primary = "weighted_screen (cap-w top25 cap_norm, net 15bps, contract 경유)",
                        dual_basis = "canonical_screen (EW top25) + canonical_screen_diag (EW-유니버스 벤치)"),
    capital_claim = "없음 — 본 라운드 수치로 graduation PASS 선언하지 않는다. HARD 3종 판정 권위 = forge + essence_score + discovery_graduation_gate.",
    liq_ruler = "screen_inputs.rds liqf (t-1 20d ADV) — canonical_screen_bt 는 attr 라벨 부재 경고를 발행했다(FQ-232). 자 자체는 헌법 정의(20d ADV>=2e8) 이나 라벨 미부착 상태로 소비했음을 명시한다."),

  positive_control = list(
    design = POS$design, delta_ir = POS$delta_ir, paired_nw_t = POS$paired_nw_t,
    annual_pp = POS$annual_pp, port_t_base = POS$port_t_base, port_t_pc = POS$port_t_pc,
    detected = POS$detected,
    conductivity_verdict = "PASS — 동일 창·동일 하네스에서 기측정 양성(MAX5 상위10% 배제)이 ΔIR +0.1642 / PORT_t 3.058→3.802 로 재현됐다(WT-014 원 +0.1692 / t 1.565 와 근사 일치). 따라서 본 라운드의 음성은 하네스·창의 무능이 아니다 — 다만 그 검출이 t 축에서는 1.566 에 그친다는 사실이 창-도달가능성 상한을 동시에 말한다."),

  power = list(
    measured_sd_monthly = PC$power$sd_monthly, sd_source = PC$measured_sd$source,
    n_months = PC$power$n_full, mde80_monthly = PC$power$mde_full_monthly,
    mde80_annual_pp = PC$power$mde_full_annual_pp,
    window_reachability = "이 창(268월, sd 1.595%/월)의 MDE80 = 3.27%p/yr. 기측정 최고 양성의 실효크기는 1.90%p/yr 로 그 아래이며 실측 NW t 1.566 에 그쳤다. ⇒ t 축에서 |t|>=1.70 은 실효크기가 기측정 양성의 1.1배 이상일 때만 가능하다.",
    mechanism_implied_effect = AT$mechanism_effect_size_arithmetic),

  primary_verdict = list(
    label = label,
    delta_ir = M$paired$delta_ir, gate = 0.05, gate_met = (M$paired$delta_ir >= 0.05),
    paired_nw_t = M$paired$paired_nw_t, mean_d_active_monthly = M$paired$mean_d_active,
    annual_pp = M$paired$annual_pp, n_months = M$paired$n,
    basis = M$paired$basis,
    port_t_base = M$base$port_t, port_t_filtered = M$filtered$port_t,
    reading = paste0("사전등록 primary 게이트(ΔIR >= +0.05) 를 **역방향으로** 미충족: 측정 ΔIR = ",
      sprintf("%+.4f", M$paired$delta_ir), " (게이트 크기의 ", sprintf("%.1f", abs(M$paired$delta_ir)/0.05),
      "배, 부호 반대). PORT_t 3.058 → 2.435. ",
      "부호(불리)의 통계적 확증은 미결이다(paired NW t ", sprintf("%+.3f", M$paired$paired_nw_t),
      ", |t| < 1.70). 그러나 **크기 축**은 미결이 아니다 — 같은 창의 양성 대조가 +0.1642 를 냈으므로 이 창은 ±0.16 규모의 ΔIR 을 분해한다."),
    label_map_defect = "★사전등록 label_map 결함 자기신고: {ΔIR < 0 이면서 |ΔIR| >= 0.05 이고 -1.70 < t < 0} 구간에 라벨이 정의돼 있지 않았다(ADVERSE 는 t <= -1.70 요구, NULL_* 는 |ΔIR| < 0.05 요구). 사후에 기준을 옮기지 않고 결함을 신고한 뒤 서술 라벨 ADVERSE_DIRECTIONAL_DETECTION_UNRESOLVED 를 부여한다 — 판정 자체(게이트 미충족 → 전이 없음)는 라벨과 무관하게 결정된다."),

  effectiveness = M$effectiveness,
  liq_tension = M$liq_tension,
  coverage = M$coverage,

  falsification = list(F1 = D$F1, F2 = D$F2,
    firings = sum(c(isTRUE(D$F1$fired), isTRUE(D$F2$fired))),
    inherited_from = "qepm/mailbox/worktask/WT-D20260822_009/alpha_hypothesis.json (alpha-hypothesis, model fable) — 재작성 없음",
    caveat_F1 = "fwd_foreign_3m_n / fwd_inst_3m_n 은 Size 정규화 값이고 배제군은 소형주 편중(size 백분위 0.300 vs 0.552, NW t -26.6) 이므로 유니버스 **중앙값** 대비 비교는 규모 중립이 아니다. 기각조건(t>=+2.0) 미충족이라는 판정은 승계 사양대로 유효하나, +1.208 이라는 부호(기전 예측과 반대)를 기전 반증의 근거로도 지지의 근거로도 읽지 않는다.",
    caveat_F2 = "absorb 는 월간 지속성이 있고 F2 는 홀딩월 관측이므로 t -8.934 의 상당 부분이 지속성의 기계적 반영일 수 있다. 또한 유효 월 n=42 로 작다. 기전 지지로 인용할 때 이 두 제한을 함께 적을 것."),

  mechanism_diagnosis = list(
    tail_replication_in_consumption_universe = D$tail_realization,
    conditional_on_top25 = D$conditional_on_top25,
    substitution_attribution = AT$substitution,
    size_bias = D$size_bias,
    mdd = D$mdd,
    core_finding = paste0(
      "★ 왜 실패했나 — 세 실측이 한 결론으로 모인다. ",
      "(1) NP2 의 꼬리 우위는 **소비 유니버스에서 재현된다**: liq 통과 base 후보 안에서 저-absorb 꼬리율 5.06% vs 고-absorb 2.23% (2.3배). ",
      "(2) 그런데 **평균은 움직이지 않는다** — base top-25 조건부로 배제대상 평균 월수익 +2.026% vs 잔류 +1.995% (배제대상이 오히려 높다), 교체된 종목만 보면 제거 +2.03% vs 추가 +1.95%. NP2 자신이 mean_spread |t| <= 1.03 로 평균-null 을 실측했고 그 사실이 여기서 그대로 나타난다. ",
      "(3) 그래서 **기전이 참이어도 포트폴리오 크기가 안 나온다**: 조건부 꼬리율 격차 0.65%p x 배제 4.42종 x 평균비중 1.78% x 꼬리 20% = 월 0.0103%(연 0.124%p) = Δactive sd 의 0.0065배. 이 창 MDE80(연 3.27%p)의 **1/26**. ",
      "⇒ 25종 cap-w top-N 에서 **평균-null 인 꼬리-only 재료를 유니버스 배제로 소비하면, 기전 편익(연 0.12%p)이 배제가 부수적으로 일으키는 노출 이동에 압도된다.** 실측된 노출 이동: 제거 종목 비중합 0.0788 vs 추가 종목 비중합 0.1810 (2.3배) + 규모 편중(배제군 size 백분위 0.300). ",
      "이것이 선행 양성(MAX5)과 갈리는 지점이다 — MAX5 배제의 기전은 복권형 **과대평가**(평균 미스프라이싱)였고 평균 축에서 값을 냈다. 배제 필터는 평균으로 값을 내며, 이 재료는 평균이 없다고 이미 측정돼 있었다."),
    mdd_refutation = paste0("가설의 path 는 '꼬리 배제 → MDD/calmar 개선' 을 주장했다. 실측: MDD 0.5587 → 0.5580 (+0.07%p), calmar 0.327 → 0.291 (악화). ",
      "25종 cap-w 포트에서 비중 1.78% 종목의 -20% 사건은 포트 -0.36% 이고, 포트 MDD 55.9% 는 시장 성분(β 약 0.92)이 만든다 — 개별 종목 꼬리 확률은 이 축에서 관측 가능한 크기가 아니다."),

  dual_basis = list(cap_w_primary = list(delta_ir = M$paired$delta_ir, port_t_base = M$base$port_t, port_t_filt = M$filtered$port_t),
    ew_screen = M$ew,
    divergence_note = "★ cap-w 는 불리(ΔIR -0.1153, PORT_t 3.058→2.435) 인데 EW 는 유리(ΔIR +0.0246, PORT_t 3.478→3.616) 이고 EW-유니버스 벤치 대비도 4.206→4.413 로 개선된다. 판정 권위는 사전등록대로 cap-w 이며 EW 로 판정을 뒤집지 않는다. 다만 이 갈림은 우연이 아니다 — 배제군이 소형주 편중이라 cap_norm 에서 비중이 작고(1.78%), EW 에서는 4% 를 차지한다. 즉 **재료의 편익이 발현되려면 배제 대상이 실질 비중을 가져야 하며, cap-w 는 구조적으로 그 조건을 파괴한다.** 이것은 다음 라운드의 라우팅 신호이지 본 라운드 판정의 예외가 아니다. (EW ΔIR +0.0246 도 게이트 +0.05 미달이라는 사실을 함께 적는다.)"),

  robustness = list(lag1 = M$lag1,
    lag1_reading = "lag1 이 base 판보다 **더 불리**하다(ΔIR -0.1443 vs -0.1153). 누출이라면 지연 시 편익이 소멸(개선 방향으로 붕괴)해야 하는데 반대 방향이다 — assert_overlay_pit 268/268 PASS + 위반 주입 0/268(검사기 생존)과 합쳐 look-ahead 신호 없음.",
    x_sensitivity_diagnostic_only = M$xdiag,
    x_reading = "X=10% +0.0117(t +0.379) / X=20%(판정) -0.1153 / X=30% -0.1336 — 단조 악화. X=10% 도 게이트 +0.05 미달이므로 사후 X 재선택은 판정을 바꾸지 못하며, 그 재선택 자체가 sweep 전환(DSR HARD)이다.",
    window_split = M$window_split,
    window_reading = "pre-2015-12 n=144 mean -3.01%p/yr (t -2.088) / post n=124 mean -0.23%p/yr (t -0.122). 불리가 초기 창에 집중. 청정창에서는 사실상 무효과이나 그 창의 MDE80 은 연 4.82%p 라 '무효과' 가 아니라 **미결**이다.",
    regime = M$regime_tab,
    regime_reading = "RISK_ON n=208 에서 -2.11 로 불리가 집중. 가설의 regime_scope 는 neutral/expansion 에서 성립을 예측했는데 실측은 반대 방향이다 — 국면 경계 예측이 빗나갔다(가설 자신이 '예측이 빗나가면 기전 재검토 신호' 라고 사전 명시). CRISIS n=15 는 표본이 작아 판독 불가."),

  prior_art = list(overlap_with_max5 = D$overlap_with_max5, marginal_over_max5 = D$marginal_over_max5,
    reading = "absorb 배제집합의 24.3% 만 MAX5 배제와 겹친다(역방향 48.5%) — 재발견이 아니다. 그러나 MAX5 필터 위에 absorb 를 얹으면 ΔIR_marginal -0.1774 로 역시 훼손한다. 두 재료가 겹치지 않는데도 한쪽만 값을 내는 것이 위 core_finding(평균 축 유무)의 방증."),

  screening_tier = M$screening,

  transition_gates = list(
    alpha_discovery_count_ge_1 = list(value = 1, pass = TRUE, note = "factor_specs 1건(absorb 배제 게이트)"),
    screen_pass = list(clause1_filtered = M$screening$clause1_pass_filtered, pass = M$screening$clause1_pass_filtered,
                       note = M$screening$caveat),
    falsification_firings_zero = list(firings = sum(c(isTRUE(D$F1$fired), isTRUE(D$F2$fired))), pass = TRUE),
    primary_gate_delta_ir = list(value = M$paired$delta_ir, threshold = 0.05, pass = (M$paired$delta_ir >= 0.05)),
    all_pass = FALSE,
    decision = "★ 전이 요청 없음. 사전등록 transition_gates 3종 중 형식 2종(alpha_discovery_count, falsification 0건)과 screening 1절은 충족하나, 라운드의 **판정 게이트인 ΔIR >= +0.05 가 역방향으로 미충족**(-0.1153)이다. 사전등록이 '하나라도 미충족이면 전이 요청 없이 negative 보고 — 협상 없음' 을 명시했으므로 risk-research 전이를 요청하지 않는다. screen_pass=TRUE 는 base 알파의 신호력이지 배제필터의 기여가 아니다(base 도 TRUE) — 이것을 전이 근거로 쓰지 않는다."),

  book_marginal = list(
    incumbent_base_convened = TRUE,
    base = "alpha_scores_str1715_268m_cleanT1.parquet (vintage_verified = production_parity_verified, §7b 라벨 게이트 통과, anchor PORT_t 3.0583 재현)",
    delta_ir = M$paired$delta_ir, threshold = 0.05, admit = FALSE,
    basis_caveat = "여기의 ΔIR 은 **screen-IR(cap-w top25 스크린)** basis 이며 §4 의 book recon NAV IR(net_active_recon_v1) 과 basis 가 다르다. 부호가 명확히 음수이므로 basis 차이가 판정을 바꾸지 않으나, 인용 시 basis 라벨 의무.",
    note = "book-marginal 은 소집 가능했고 실행됐다 — 결과가 DEFER/REJECT 방향일 뿐이다. governor admit 은 수동 영역이며 본 라운드는 admit 을 요청하지 않는다."),

  next_probe = list(
    "① 소비 형태 교체 — 평균-null 꼬리 재료를 **risk-side 로 라우팅**: absorb 를 tail/CVaR 추정의 입력(공동위험 아닌 종목별 하방 확률)으로 risk-research 가 소비할 때 CVaR/tail 예측이 개선되는지. 근거 = 꼬리율 격차가 소비 유니버스에서 2.3배로 재현(5.06% vs 2.23%)되고 top-25 조건부로도 잔존(3.38% vs 2.72%)하나 평균으로는 전이되지 않는다. 배제·랭킹은 평균 축 소비이므로 구조적으로 이 재료를 못 받는다.",
    "② 규모-중립 배제 — absorb 를 월별 log_size 에 직교화한 잔차로 배제집합을 정의해 재측정. 근거 = 본 라운드 배제군의 규모 편중이 실측(size 백분위 0.300 vs 0.552, NW t -26.6)이고 교체가 비중합 0.0788→0.1810 의 노출 이동을 일으켰다. NP2 는 직교화 공간에서도 tail_dn_prob_diff 생존(t -4.323 / -3.100)을 이미 측정했으므로 이는 사후 X 스윕이 아니라 **다른 사전측정 객체**의 소비다.",
    "③ EW/중형 슬리브 이식 — EW basis 에서 PORT_t 3.478→3.616, EW-유니버스 벤치 t 4.206→4.413 로 방향이 반대다(ΔIR +0.0246, 게이트 미달). 배제군이 실질 비중을 갖는 가중 체계에서만 편익이 발현될 수 있다는 구조 가설을 EW 기반 base 로 사전등록 재측정.",
    "④ 배제 크기 사전산술 규약 — 본 라운드가 드러낸 방법론 결함: 기전 함의 크기(연 0.124%p)가 창 MDE80(연 3.27%p)의 1/26 이었고 그 산술은 **측정 전에** 가능했다. 배제·필터형 라운드는 착수 전 '기전이 100% 전환될 때의 포트폴리오 함의 / Δactive sd' 를 계산해 사전등록에 기재하도록 계약(required_effect_size.R 계열)에 축을 추가할 것."),

  window_caveats = list(universe_exit_unrecorded_pre201512 = "268월 중 144월이 2015-11 이전 — 유니버스 이탈 미기록 창. 편향 방향 하방/중립(생존자 편향 아님).",
    benchmark = "bench = screen_inputs.rds 동봉 벤치(base parity 하네스와 동일). 하드코딩 benchmark_id 를 본 라운드가 재검증하지 않았음을 명시."),
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

write_json(V, file.path(OUT,"alpha_validation.json"), auto_unbox=TRUE, pretty=TRUE, digits=NA, na="null")
say("alpha_validation.json 기록 — label = %s", label)
saveRDS(V, file.path(OUT,"alpha_validation.rds"))
say("done")
