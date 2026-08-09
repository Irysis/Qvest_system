## =============================================================================
## FQ-229 (E2) — ①NP1 사이징 precheck(시대별 disp) ②findings.json ③큐 갱신
## ★큐 번호 하드코딩 금지: 쓰기 직전 read → max+1 → 기록 후 재읽기 (frontier_queue_io 경유)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[e2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
NWLAG <- 3L
nw_t <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

A  <- readRDS(file.path(OUT, "a1_results.rds")); DT <- as.data.table(A$DT)
B  <- readRDS(file.path(OUT, "b1_results.rds"))
B2 <- readRDS(file.path(OUT, "b2_results.rds"))
C1 <- readRDS(file.path(OUT, "c1_results.rds"))
C3 <- readRDS(file.path(OUT, "c3_results.rds"))
D  <- readRDS(file.path(OUT, "d1_results.rds"))
E1 <- readRDS(file.path(OUT, "e1_results.rds"))

## ---------------------------------------------------------------- NP1 사이징
say("================ NP1 사이징 precheck — 시대별 횡단면 분산 ================")
DT[, mod := as.integer(signal_ym >= "2017-01")]
de <- DT[mod == 0L, mean(disp_t)]; dm <- DT[mod == 1L, mean(disp_t)]
be <- DT[mod == 0L, mean(M26_Revenue_Mom)]; bm <- DT[mod == 1L, mean(M26_Revenue_Mom)]
say("disp_t 평균: 초기(<2017) %.4f · 현대 %.4f · 비 %.3f", de, dm, dm/de)
say("b_t  평균: 초기 %+.6f · 현대 %+.6f · 비 %.3f", be, bm, bm/be)
pred_bm <- be * (dm/de)
say("★분산만으로 예측되는 현대 평균 = 초기 %+.6f x 분산비 %.3f = %+.6f (실측 %+.6f · 설명분 %.1f%%)",
    be, dm/de, pred_bm, bm, 100*(be - pred_bm)/(be - bm))
say("   ⇒ NP1 은 '현대 감쇠의 몇 %%가 분산 축소인가'를 이 축으로 답할 수 있다 (n=283 연속, 분할 아님)")
np1_share <- 100*(be - pred_bm)/(be - bm)

## ---------------------------------------------------------------- findings
say("================ findings.json ================")
S1m <- A$S1[y == "M26_Revenue_Mom"]; S2m <- A$S2[y == "ss_M26_Revenue_Mom"]
HZ <- as.data.table(B$HZ); h0 <- HZ[h == 0L]; h1 <- HZ[h == 1L]
CMP <- fread(file.path(OUT, "c1_paired_comparison.csv"))
MAT <- as.data.table(B$MAT); DHZ <- as.data.table(D$HZ); DMAT <- as.data.table(D$MAT)

F <- list(
  round_id = "FQ-229", date = "2026-08-10", metric_type = "canonical_screen_diag",
  capital_claim = FALSE,
  prereg = "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/PREREG.md",
  parent = "FQ-225(disp_t t=+4.14) · FQ-161(M26 cap-w PORT_t +1.544) · FQ-223(롤오버 오염 18.2%)",
  headline = paste0("분산 의존은 **동시점에만** 실재한다(스케일 t +3.49 ∧ 기술 t +3.40). ",
                    "lag1 로는 이 표본이 '의존 없음'과 '자기상관만큼 전이'를 구별하지 못한다(80% 검정력 비율 0.703) ",
                    "⇒ 착수 전 폐기. 부수로 소비면 기하가 실측 확정됐다(단일 팩터 게이팅 = 랭킹 불변 no-op, |Δ|=0)."),
  power_precheck = list(
    verdict = "ABORT_BEFORE_LAUNCH",
    external_bar_basis = "FQ-225 동시점 disp 계수 x lag1 자기상관 (모형 가정 — 본 라운드가 별도 시험)",
    contemporaneous_slope = A$c_con, contemporaneous_t = A$t_con, lag1_autocorr = A$AC1,
    external_expected_slope = A$ext_expected,
    required_slope_power50 = A$req_full,
    required_slope_power80 = A$req_full * (2.0 + qnorm(0.80))/2.0,
    ratio_power50 = abs(A$ext_expected)/A$req_full,
    ratio_power80 = abs(A$ext_expected)/(A$req_full*(2.0 + qnorm(0.80))/2.0),
    observed_slope = S1m$c, observed_se = S1m$se,
    se_from_zero = abs(S1m$c)/S1m$se, se_from_attenuation = abs(A$ext_expected - S1m$c)/S1m$se,
    tool_verdict = A$PC[spec == "PC1-S1 연속(전표본)", verdict],
    implied_t_threshold = A$PC[spec == "PC1-S1 연속(전표본)", implied_t],
    bar_restates_t = A$PC[spec == "PC1-S1 연속(전표본)", bar_restates_t],
    binary_gate_effective_n = 283*0.30*0.70,
    note = paste0("★도구 바는 검정력 50% 바다(참효과=t_thresh x se ⇒ 기대 t=2.0). ",
                  "폐기 판정은 배수 0.999(50%)가 아니라 0.703(80%)에 근거한다.")),
  mechanism_decomposition = list(
    identity = "b_t = std_slope_t x disp_t / sd_z_t (재구성 최대오차 6.9e-18 — 항등식 성립)",
    h0_contemporaneous = list(
      M26 = list(S1_t = h0[factor=="M26_Revenue_Mom", S1_t], S2_t = h0[factor=="M26_Revenue_Mom", S2_t],
                 S1_r2 = h0[factor=="M26_Revenue_Mom", S1_r2]),
      M01 = list(S1_t = h0[factor=="M01", S1_t], S2_t = h0[factor=="M01", S2_t]),
      controls_C01_C02_C04_max_abs_t = max(abs(unlist(h0[factor %in% c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR"),
                                                         .(S1_t, S2_t)]))),
      reading = "동시점 의존은 기계적 스케일의 재진술이 아니다 — 표준화 기울기(기술) 자체가 분산에 반응한다. M26·M01 만, 컨센서스 3종은 무반응."),
    h1_lag1 = list(M26_S1_t = h1[factor=="M26_Revenue_Mom", S1_t], M26_S2_t = h1[factor=="M26_Revenue_Mom", S2_t],
                   max_abs_t_all_axes = max(abs(unlist(h1[, .(S1_t, S2_t)]))),
                   reading = "5축 x 2채널 전부 |t| < 1.71 — lag1 에서 절벽"),
    S3_differential_t = A$S3$t,
    moving_average_predictors = list(
      note = "지속-국면 가정 시험(e1 precheck — 판정 인용 금지)",
      ma3_S1_t = E1$PR[predictor=="ma3", S1_t], ma6_S1_t = E1$PR[predictor=="ma6", S1_t],
      ma12_S1_t = E1$PR[predictor=="ma12", S1_t],
      reading = "전이계수는 커지는데(0.461→0.735) S1 t 는 0 근방·음수로 간다 ⇒ '분산 국면' 프레임 미지지"),
    unregistered_cells_caveat = "지평 스캔 40셀 다중조회. h=2/3 및 대조축 셀(예: M01 h=2 S2 t −3.259)은 미등록 관측 — 판정 인용 금지."),
  consumption_surface = list(
    chosen = "복합신호 내 M26 상대 가중의 분산 조건부 조절 (ranking weight)",
    rationale = "분산은 월당 스칼라라 단독으로 횡단면 순서를 못 바꾼다. 상대 가중일 때만 순서가 바뀌고, 그 형태만 알파 범위 안이다.",
    rejected_signal_strength = list(
      claim = "단일 팩터 노출 스케일 = canonical top-25 EW 랭킹 불변 no-op",
      proof_empirical = list(m26_alone_port_t = as.numeric(C1$pt[["arm0_M26_alone"]]),
                             m26_x_G4_port_t = as.numeric(C1$pt[["arm0g_M26_x_G4"]]),
                             abs_delta = C1$noop_delta),
      note = "|Δ| = 0.00e+00 — 논증이 아니라 실측 사실. 선형 노출 축소 실패계열과 별개로 **구조적으로** 무효."),
    rejected_firing_month = "이진 on/off 는 off 달 점수가 전부 0 이 되어 top-25 가 동점 임의화로 무너진다 ⇒ 점수 변환으로 표현 불가, 노출 결정(옵티마이저/오버레이) 필요 — 알파 범위 밖",
    composite_effective_weights = as.list(round(C1$sds, 3)),
    composite_caveat = "raw z 열 합이라 등가-위험 가중이 아니다(C02 sd 1.632 지배). 재표준화 복합은 검증 안 됨 (가정)."),
  gate_forms_prereg_all = lapply(seq_len(nrow(MAT)), function(i) as.list(MAT[i])),
  transition = list(
    basis_note = "★FQ-161 의 +1.544 는 *M26 단독* 값이다. 복합 arm 과 나란히 놓고 '움직였다'로 읽지 않는다.",
    arm0_M26_alone_port_t = as.numeric(C1$pt[["arm0_M26_alone"]]),
    fq161_reference = 1.544, parity_abs_delta = abs(as.numeric(C1$pt[["arm0_M26_alone"]]) - 1.544),
    arm1_EW_composite_port_t = as.numeric(C1$pt[["arm1_EW_composite"]]),
    gated_arms = lapply(seq_len(nrow(CMP)), function(i) as.list(CMP[i])),
    binding_comparison = "무게이트 복합 대비 paired t(NW3)",
    max_abs_paired_t = max(abs(CMP$paired_t_nw3)), threshold = 2.0,
    sign_agreement_all = all(CMP$sign_agree),
    hard_2p95_caveat = paste0("arm5(복합+G4) PORT_t ", round(CMP[arm=="arm5_comp_G4", port_t], 4),
      " > 2.95 이나 기저가 이미 ", round(CMP[arm=="arm5_comp_G4", port_t_base], 4),
      " 이고 증분 paired t 는 ", round(CMP[arm=="arm5_comp_G4", paired_t_nw3], 3),
      " 다. canonical 은 스크리닝이며 graduation 권위는 forge+essence_score. oos_retention·calmar 미산출(calmar=NA)."),
    liquidity_ruler = "adv1_sameday_DEGRADED (FQ-181) — 월말-slim 입력이라 20일 평균 거래대금 불가. 전 arm 동일 자이므로 상대비교는 유효하나 PORT_t 절대수준을 헌법-자 수치로 인용 금지."),
  controls_and_injection = list(
    positive_control_h0 = "동시점 판별력 확인 — C01/C02/C04 전부 |t|<1.6, M26·M01 만 유의. 검정이 아무 축에나 반응하지 않는다.",
    control_gates_axis_null = lapply(seq_len(nrow(as.data.table(B2$INJ))), function(i) as.list(as.data.table(B2$INJ)[i])),
    control_verdict = "재료자격 축별 무작위-게이트 귀무 대비 유의(p<0.05) 축 0/5 (M26 백분위 66.3%)",
    consumption_injection = lapply(seq_len(nrow(as.data.table(C3))), function(i) as.list(as.data.table(C3)[i])),
    injection_reading = paste0("★ΔPORT_t 가 무작위 재배정 귀무 대비 p 0.016~0.028 로 나오나, **무게이트(Δ=0)가 이미 ",
      "귀무의 상위 80.4~91.6%** 다 — 귀무 중앙이 음수(월별 가중을 임의로 흔드는 것 자체가 해롭다)이기 때문. ",
      "분산 연결의 순증 백분위는 +5.6%p(G1) / +18.0%p(G4) 이고, 구속력 있는 무게이트 대비 paired t 는 +0.117 / +1.013 로 문턱 미달. ",
      "즉 확립된 것은 '분산 연결이 임의 가중보다 덜 해롭다'이지 '무게이트보다 낫다'가 아니다.")),
  contamination_robustness = list(
    common_window_months = D$common_n, plain_t = D$t_plain, repaired_t = D$t_ra,
    h0_S1_t = list(plain = DHZ[arm %like% "plain" & h==0, S1_t], repaired = DHZ[arm %like% "RA" & h==0, S1_t]),
    h0_S2_t = list(plain = DHZ[arm %like% "plain" & h==0, S2_t], repaired = DHZ[arm %like% "RA" & h==0, S2_t]),
    h1_S1_t = list(plain = DHZ[arm %like% "plain" & h==1, S1_t], repaired = DHZ[arm %like% "RA" & h==1, S1_t]),
    gates_improving = sum(DMAT$delta_t > 0), gates_total = nrow(DMAT),
    verdict = "오염판/수리판 양쪽에서 결론 불변 — h=0 유의 유지(수리판 S1 t +4.189), h=1 문턱 미달, 게이트 8/8 개선 없음"),
  np1_sizing = list(disp_early = de, disp_modern = dm, disp_ratio = dm/de,
                    b_early = be, b_modern = bm,
                    predicted_modern_from_disp = pred_bm, share_of_gap_explained_pct = np1_share),
  selection_type = "chain_diagnostic_prereg (argmax pick 없음 — DSR 부적용)",
  n_specs_prereg = 17,
  caveats = c(
    "FMB 계수 t 는 횡단면 신호력 — 실현 포트폴리오 초과수익(PORT_t) 아님. IC→PORT_t 전이 벽 적용",
    "graduation HARD 3종 미판정(oos_retention·calmar 미산출). 자본 주장 없음",
    "폐기 판정은 '의존 없음'이 아니라 '이 표본이 0과 감쇠함의치를 구별 못함'이다 (0 으로부터 0.75se · 감쇠함의치로부터 1.25se)",
    "유동성 자 adv1_sameday_DEGRADED — PORT_t 절대수준 인용 시 라벨 필수",
    "'EW 복합'은 등가-위험 가중이 아니다(열 sd 0.621~1.632). 재표준화 복합 미측정",
    "지평 스캔 40셀 다중조회 — h=2/3 및 대조축 셀은 미등록 관측",
    "c2/c3 귀무 B=250 (계산비용 제약) — p 0.012~0.048 의 해상도는 ±0.013(이항 se) 수준"),
  challenge_note = "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/challenge_note.md",
  artifacts_dir = "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/")
write_json(F, file.path(OUT, "fq229_findings.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("findings 저장 (%d bytes)", file.info(file.path(OUT, "fq229_findings.json"))$size)

## ---------------------------------------------------------------- 큐 갱신
say("================ 큐 갱신 (read -> max+1 -> 기록 -> 재읽기) ================")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
num <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nxt <- max(num, na.rm = TRUE) + 1L
say("현재 항목 %d · FQ 번호 max %d ⇒ 신규는 FQ-%03d 부터", length(ids), max(num, na.rm=TRUE), nxt)

i229 <- which(ids == "FQ-229")
if (!length(i229)) stop("[e2] FQ-229 부재 — 0은 정지 신호")
e <- Q$entries[[i229]]
e$status <- "config_scoped_negative_frontier_open"
e$wall_check <- paste0(
  "FQ-229 측정(2026-08-10): 분산 의존은 **동시점 전용**. h=0 스케일 t +3.491 ∧ 기술(표준화기울기) t +3.400 ",
  "(컨센서스 3종은 |t|<1.6 — 판별력 확인). h=1 은 5축x2채널 전부 |t|<1.71, M26 S1 t +0.747. ",
  "검정력: 외부기준(동시점계수 x 자기상관 0.462) 대비 80% 검정력 비율 0.703 ⇒ **착수 전 폐기**. ",
  "관측 기울기는 0 으로부터 0.75se · 감쇠함의치로부터 1.25se — 두 가설 어느 쪽도 기각 못함(의존 부재 주장 아님). ",
  "사전등록 게이트 G1~G4 재료자격 Δt 전부 음수(오염판 −0.079~−0.676 · 수리판 −0.287~−1.512, 8/8). ",
  "전이: M26 단독 PORT_t +1.5441(FQ-161 +1.544 parity) · 복합기저 +2.7413 · 게이트 복합 +2.81~+3.06 이나 ",
  "구속력 있는 무게이트 대비 paired t 최대 +1.013(문턱 2.0 미달) · ΔIR 최대 +0.0586, 부호 일치 4/4. ",
  "위반 주입(승수 무작위 재배정 B=250): p 0.016~0.028 로 보이나 **무게이트(Δ=0)가 이미 귀무 상위 80~92%** ",
  "(임의 월가중이 해롭기 때문) — 확립된 것은 '임의 가중보다 덜 해롭다'이지 '무게이트보다 낫다'가 아님. ",
  "★부수 확정(구조): 단일 팩터 게이팅 = 랭킹 불변 no-op |Δ|=0.00e+00 실측. ",
  "유동성 자 adv1_sameday_DEGRADED 라벨.")
e$next_action <- "FQ-230(현대 감쇠의 분산 귀속) · FQ-231(스칼라 시계열 예측자 소비면 라우팅) · FQ-232(헌법 유동성 자 복원)로 분기. lag 형태만 바꾸는 재시도는 e1 precheck(80% 검정력 비율 최대 0.702)로 미등재."
e$source_refs <- c(as.character(e$source_refs),
                   "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/fq229_findings.json",
                   "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/PREREG.md")
Q$entries[[i229]] <- e
say("FQ-229 갱신: status -> %s", e$status)

mkentry <- function(id, lane, title, hyp, ev, wall, gate, na_) list(
  id = id, lane = lane, title = title, hypothesis = hyp, ev_rationale = ev,
  wall_check = wall, data_gate = gate, owner = "alpha-research", status = "frontier_open",
  next_action = na_,
  source_refs = c("stage_artifacts/infra/fq229_m26_dispersion_gate_20260810/fq229_findings.json"))

NEW <- list(
  mkentry(sprintf("FQ-%03d", nxt), "attribution",
    "현대 구간 M26 감쇠의 분산 귀속 — 감쇠인가 분산 축소인가",
    paste0("FQ-225 는 현대 약화를 '판정 불가'로 남겼다(필요 818개월). 그러나 FQ-229 가 payoff 가 ",
           "**동시점 분산에 비례**함을 확정했으므로(h=0 S1 t +3.491), 시대 간 b_t 차이 중 분산 축소로 ",
           "설명되는 몫을 분리할 수 있다. 가설: 관측 감쇠의 상당분이 신호 열화가 아니라 횡단면 분산 축소다."),
    sprintf("사이징 실측(FQ-229 e2): disp 평균 초기 %.4f → 현대 %.4f (비 %.3f) · b_t 평균 %+.6f → %+.6f. 분산비만으로 예측되는 현대 평균 %+.6f ⇒ 시대 격차의 %.1f%% 설명. 연속 설계(n=283, 분할 금지)라 검정력 확보.",
            de, dm, dm/de, be, bm, pred_bm, np1_share),
    "미측정 — 본 항목이 측정 대상. FQ-225 의 '판정 불가'를 뒤집는 게 아니라 **다른 질문**(감쇠의 성분 분해)을 던진다.",
    "closed — 필요 입력 전부 보유(alpha_scores.parquet + FQ-229 월별 성분 CSV). 신규 수집 불요",
    "소비면 = monitoring 감쇠 판정의 국면 정규화(저분산 달의 낮은 payoff 를 신호 감쇠로 오독하는 것 차단). 사전등록 필수: 분산 정규화 계열 t 는 원계열보다 **낮다**(2.555 → 1.815)는 사실을 먼저 설명해야 함"),
  mkentry(sprintf("FQ-%03d", nxt + 1L), "infrastructure",
    "스칼라 시계열 예측자의 소비면 라우팅 규칙 등재 (국면라벨·vol·crowding 공통 벽)",
    paste0("월당 스칼라 예측자(분산·국면확률·vol·crowding)는 횡단면 순서를 단독으로 바꾸지 못한다. ",
           "FQ-229 가 이 기하를 실측 확정했다: ①단일 팩터 노출 스케일 = canonical 랭킹 불변 no-op ",
           "②이진 on/off 는 점수 변환으로 표현 불가(동점 임의화) ③복합 내 상대 가중만 알파 범위 안. ",
           "이 지도를 못박지 않으면 후속 스칼라 예측자가 같은 벽을 재발견한다."),
    "FQ-229 c1 실측: M26 단독 PORT_t +1.544110 vs M26xG4~ +1.544110, |Δ| = 0.00e+00 (구조적 사실, 논증 아님). 08-08 소비면 7종 순회 규약의 스칼라-예측자 판본.",
    "해당 없음 — 측정이 아니라 지도 등재. 단 등재 후 기존 큐의 스칼라-예측자 항목 재라우팅 필요 여부는 실측으로 확인",
    "closed",
    "06_Registry 소비면 지도에 스칼라-예측자 절 추가 + 기존 큐에서 '노출 스케일'을 소비면으로 적은 항목 census"),
  mkentry(sprintf("FQ-%03d", nxt + 2L), "infrastructure",
    "canonical_screen_bt 소비 경로의 헌법 유동성 자 복원 (adv1_sameday_DEGRADED)",
    paste0("월말-slim rawdata 를 넘기면 20일 평균 거래대금을 만들 수 없어 유동성 자가 ",
           "**월말 1일치 Vol×Close** 로 강등된다(FQ-181 경고 발화). 즉 2e8 필터가 헌법 자가 아니다. ",
           "이 경로로 산출된 PORT_t 절대수준(FQ-161 +1.544 포함)이 헌법-자 기준이 아니다."),
    "FQ-229 c1/c2 실행 전건에서 경고 발화 실측. 전 arm 동일 자라 상대비교는 무결하나, 절대수준 인용과 유동성 제약 준수 주장이 라벨 없이 유통될 위험.",
    "미측정 — 일간 rawdata 경유 시 PORT_t 및 편입 종목이 바뀌는지 A/B 필요",
    "closed — 일간 rawdata 보유(.cache/RAWDATA.parquet). slim 여부는 호출부 선택",
    "일간 입력으로 canonical_screen_bt 재실행해 M26 단독·복합 기저 PORT_t 변화 실측 → 변화 유의하면 기존 canonical 기록에 자-라벨 소급 부착")
)
for (x in NEW) { Q$entries[[length(Q$entries) + 1L]] <- x; say("신규 등재 %s — %s", x$id, x$title) }
res <- write_frontier_queue(Q)
say("기록 결과: 총 %d · 추가 %d · 삭제 %d", res$n, length(res$added), length(res$removed))

## 재읽기 검증 (침묵 실패 차단)
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
say("★재읽기: 항목 %d · FQ-229 status = %s · 신규 %s 존재 여부 %s",
    length(ids2), as.character(Q2$entries[[which(ids2 == "FQ-229")]]$status)[1],
    paste(sapply(NEW, function(x) x$id), collapse = "/"),
    all(sapply(NEW, function(x) x$id) %in% ids2))
if (!all(sapply(NEW, function(x) x$id) %in% ids2)) stop("[e2] ★재읽기에서 신규 항목 부재 — 침묵 실패")
say("완료.")
