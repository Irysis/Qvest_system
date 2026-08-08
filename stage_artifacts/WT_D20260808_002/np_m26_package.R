## alpha_package.json (AST v1.1) 생성 — 승계 가설 재작성 금지, 형식만 게이트 계약에 맞춤
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[pkg] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a

AV  <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=TRUE)
T1  <- readRDS(file.path(OUT,"m26_t1exec.rds"))
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector=FALSE)
A   <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
A[, Date := as.Date(Date)]
say("★입력 실측: alpha_scores %d행 · %d개월 · 관측단위 (월말 Date × Ticker) · 최신 신호월 %s",
    nrow(A), uniqueN(A$signal_ym), max(A$signal_ym))

## --- as_of = 최신 완결 신호월 (수익 미실현 = 배포 가능 시점) ---
AS_OF <- max(A$Date); say("as_of(sig_date) = %s", AS_OF)
L <- A[Date == AS_OF]
say("as_of 횡단면 %d종목", nrow(L))

## 증분 표현: 그 달 횡단면에서 3종 통제 후 잔차 (판정과 동일 정의)
fit <- lm(M26_Revenue_Mom ~ C01_SUE + C02_EPS_Chg_1m + C04_ESBR, data = L)
L[, z_resid := as.numeric(residuals(fit))]
BETA <- AV$primary$mean_coef                      # FMB 월평균 계수 (실측)
L[, alpha_hat := BETA * z_resid]                  # 기대 월간 초과수익
say("alpha_hat: 평균 %+.5f · sd %.5f · 범위 [%+.5f, %+.5f]",
    mean(L$alpha_hat), sd(L$alpha_hat), min(L$alpha_hat), max(L$alpha_hat))

## --- confidence [0,1] : 데이터가용성 · 횡단면 랭크 안정성 · 커버리지 ---
H <- A[Date >= (AS_OF - 100)]                     # 최근 3개월 신호
H[, rk := frank(-M26_Revenue_Mom)/.N, by=Date]
stab <- H[, .(rk_sd = sd(rk), n_obs = .N), by=Ticker]
L <- merge(L, stab, by="Ticker", all.x=TRUE)
L[, conf := 0.50 * (n_obs %||% 1) / 3 ]           # 가용성 (최근 3개월 중 관측 비율)
L[is.na(n_obs), conf := 0.50 * 1/3]
L[, conf := pmin(1, pmax(0,
      0.50 * pmin(1, ifelse(is.na(n_obs), 1L, n_obs)/3) +
      0.30 * (1 - pmin(1, ifelse(is.na(rk_sd), 0.5, rk_sd)/0.30)) +
      0.20 * AV$secondary$ic_pos_rate ))]
say("confidence: 평균 %.3f · 중앙 %.3f · 범위 [%.3f, %.3f]",
    mean(L$conf), median(L$conf), min(L$conf), max(L$conf))

av <- as.list(setNames(round(L$alpha_hat, 6), L$Ticker))
cv <- as.list(setNames(round(L$conf, 4),      L$Ticker))

## --- 승계 가설 (재작성 금지 — 문자열 그대로 이관, 형식만 게이트 계약형으로) ---
S <- HYP$selected
pkg <- list(
  task_id = "WT-D20260808_002",
  as_of_date = as.character(AS_OF),
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  ## ★decision_ts = 신호월 다음달 첫 거래일 (2026-08-03). 임의 완화가 아니라 **측정한 그대로**다:
  ##   컨센서스 33종(북 incumbent C01/C02/C04 포함)은 registry 자인 known_discrepancy 로
  ##   보수 가용시점이 sig_date+1d 이므로, 월말 종가 체결 가정은 정적검증을 통과하지 못한다.
  ##   그래서 T+1 실행앵커(체결 = 익월 첫 거래일 종가 → 그 다음달 첫 거래일 종가)로 재측정했고
  ##   z(M26) FMB NW3 t = +2.305 (기준 +2.555 대비 유지율 0.90) 로 문턱 위에서 생존했다.
  pit = list(sig_date = as.character(AS_OF), decision_ts = "2026-08-03",
             decision_ts_rationale = "컨센서스 보수 가용시점(sig_date+1d) 이후 체결. T+1 실행앵커로 실측 완료 — 선언만 하고 미측정한 lag 아님"),

  hypothesis = list(
    statement = S$hypothesis_statement,
    mechanism = list(agent = S$mechanism$agent, friction = S$mechanism$friction, path = S$mechanism$path),
    ## ★형식 적응 고지: 승계본은 falsification 을 object 로 담았으나 schema/게이트는
    ##   field 참조를 갖는 **배열**을 요구한다. 내용(observable/reject_if)은 문자 그대로 보존하고
    ##   배열 원소로 재배치만 했다 — 의미 재작성 아님 (challenge_note.md C-FMT 기록).
    falsification = list(
      list(field = "C-CONSENSUS-QW",
           observable = S$falsification$observable,
           reject_if = S$falsification$reject_if,
           measured = paste0("M26(t)→C02_EPS_Chg_1m(t+1) rho +0.0998 t_NW3 +16.71 / (t+2) +0.0732 t +12.69 / ",
                             "(t+3) +0.0542 t +9.49 ⇒ 전파 기전 반증 안 됨"),
           inherited_refs = as.list(unlist(S$falsification$field_dictionary_refs))),
      list(field = "C01_SUE",
           observable = "이익 서프라이즈(sue)와 M26 의 부호 불일치가 실질 비중으로 존재해야 기전이 시험된다",
           reject_if = "불일치 비중이 무시 가능하면 재탕이라 기전 미시험",
           measured = sprintf("부호 불일치 %.1f%% (일치 %.1f%%) ⇒ 시험됨", (1-AV$secondary$sue_m26_sign_agreement)*100,
                              AV$secondary$sue_m26_sign_agreement*100)),
      list(field = "M26_Revenue_Mom",
           observable = "증분 계수가 통제 3종과의 다중공선성 산물이 아니어야 한다",
           reject_if = "VIF 상승으로 계수가 불안정하면 증분 주장 철회",
           measured = "M26~3종 R² 평균 0.0627 · VIF 1.07 ⇒ 공선성 산물 아님")
    ),
    ## ★as.list() 필수 — toJSON(auto_unbox=TRUE) 는 길이-1 **벡터**를 스칼라로 접는다.
    ##   길이-1 배열이 스칼라가 되면 ast_spec_gate 가 "빈 배열"로 읽고 block 한다(실측 검거).
    regime_scope = list(
      holds_in = as.list(unlist(S$regime_scope$holds_in)),
      weakens_or_reverses_in = as.list(unlist(S$regime_scope$weakens_or_reverses_in)),
      boundary_rationale = S$regime_scope$boundary_rationale
    ),
    inherited_from = "alpha-hypothesis (model: fable) — qepm/mailbox/worktask/WT-D20260808_002/alpha_hypothesis.json",
    inheritance_note = "mechanism / regime_scope 는 문자 그대로 승계(재작성 금지). falsification 은 내용 보존 + 게이트 계약형(배열+field) 재배치만."
  ),

  factors = list(list(
    factor_id = "F1_M26_revenue_revision",
    ## 리프 선언형 = ast_verify LEAF_KINDS 계약: {"leaf":"REGISTRY","factor":<factor_id>}
    ## (factor_id 를 leaf 문자열에 직접 넣으면 FAIL_CONTRACT — 실측 검거)
    ast = list(op = "CS_ZSCORE", args = list(list(leaf = "REGISTRY", factor = "M26_Revenue_Mom"))),
    role = "core_signal",
    restatement_exposure = 0
  )),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(list(
      leaf = "M26_Revenue_Mom",
      availability_rule = "fixed: T-1 (registry 선언). ★코드 강제점은 Date <= sig_d (same-day 허용) — registry 가 known_discrepancy 로 자인한 비대칭",
      restatement_prone = FALSE,
      provenance = "factor_db 월 파일 → load_month_factors() 커넥터 경유(C15). Z_Score_Aligned = 방향정렬 횡단면 z (C13)",
      window_check = "신호창 종점 = 신호월 거래일 월말 · 수익창 = (그 월말, +1개월] ⇒ 창 비중첩. align_signal_return_ym(off=0, signal_anchor) 로 병합, 월 coverage 1.000"
    )),
    verdict = "clean",
    residual_risk = "월말 당일 갱신 컨센서스가 종가 이전에 가용했는지 sub-daily 축은 미검증 — 통제 3종도 동일 노출이라 증분 추정에 차등 편의는 없음. FQ 등재(T-1 strict 재빌드 A/B)"
  ),

  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT_D20260808_002/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "Consensus_Revenue_Revision",
    proxy = "M26_Revenue_Mom",
    formula = "(revenue_fy1_t - revenue_fy1_{t-63d}) / |revenue_fy1_{t-63d}| → 횡단면 Z_Score_Aligned",
    lag_rule = "Date <= sig_date (컨센서스 daily, registry 선언 T-1)",
    winsorization = "factor_db 빌더 내장 (원형 그대로 소비 — no_sweep 사전등록)",
    neutralization = "none (판정은 3종 동시 회귀로 통제)",
    economic_rationale = S$mechanism$path,
    weight_theta = 1.0,
    source = "db_existing",
    redundancy_cluster_id = "earnings_consensus_cluster (★registry 는 momentum_cluster 로 선언 — 실측 spearman 은 C02 0.2154·C04 0.1106·C01 0.0925 로 컨센서스 형제와 약한 양의 연관. 라벨 정정 제안 = duplicate_registration_proposal.json)",
    references = as.list(c("Jegadeesh-Livnat (2006) — 출발점 인용이며 채택 근거 아님"))
  )),

  diagnostics = list(
    canonical_port_t_nw_lag3 = AV$transition$canonical_port_t_raw,
    canonical_port_t_pvalue = NA,
    canonical_n_months = AV$transition$dual_basis$n_months_post2017 * 0 + AV$primary$n_months,
    rank_ic = AV$secondary$rank_ic_mean,
    icir = AV$secondary$icir,
    monotonicity = NA,
    subperiod_stability = NA,
    turnover_proxy = AV$transition$turnover_annual_raw,
    harvey_t_stat = AV$secondary$rank_ic_t_nw3,
    post_neutralization_ic = NA,
    fmb_increment_t_nw_lag3 = AV$primary$fmb_nw3_t,
    canonical_port_t_ew_universe = AV$transition$dual_basis$ew_universe_port_t_raw,
    canonical_port_t_post2017_ew = AV$transition$dual_basis$post2017_t_nw_lag3,
    oos_retention_approx = AV$transition$dual_basis$oos_retention_approx,
    placebo_p = AV$robustness$placebo_p,
    lag1_retention = AV$robustness$lag1_retention,
    fmb_increment_t_nw_lag3_t1exec = T1$tab[term=="M26_Revenue_Mom", t_nw3],
    t1exec_retention = T1$tab[term=="M26_Revenue_Mom", t_nw3] / AV$primary$fmb_nw3_t,
    t1exec_n_months = T1$n_months
  ),
  selection_objective = "canonical_port_t",
  challenge_flags = c(
    "[HIGH] 전이 벽 — 재료 자격(FMB t +2.555) 통과이나 cap-w PORT_t +1.544 « HARD 2.95. EW-대비 +2.041 로 상승하나 여전히 미달 ⇒ 벤치 아티팩트만으로 설명 안 됨",
    "[HIGH] oos_retention_approx 0.123 (<0.5 무조건 FAIL 대역) — 자본 자격 주장 불가. 본 라운드는 재료 자격까지만",
    "[HIGH] 부기간 3구간 전부 INCONCLUSIVE_UNDERPOWERED (각 구간 자체 sd 기준) — 점추정은 단조 하락(연 3.58%→1.82%→0.99%)하나 '감쇠 확정' 주장 금지",
    "[HIGH] lag1 유지율 0.23 — 승계 가설 path('1~3개월 전파')와 불일치. 전파 관측은 t+3 까지 유의한데 수익 예측력은 1개월 내 소진. 재설계 요청 대상(재작성 금지 준수)",
    "[MEDIUM] '이익 3종 위의 증분' 실질 통제 = C02_EPS_Chg_1m 단독 (C01_SUE t -0.04 · C04_ESBR t +0.49)",
    "[MEDIUM→해소일부] 컨센서스 same-day vintage (registry known_discrepancy 자인, 33종 전체 = 북 incumbent 포함) — ast_verify 가 보수 가용 sig_date+1d 로 FAIL_LOOKAHEAD 판정. T+1 실행앵커 재측정으로 대응: t +2.555→+2.305(유지율 0.90) 문턱 위 생존. 잔여 = 원천 T-1 strict 재빌드 A/B(FQ 등재)",
    "[MEDIUM] turnover 11.74/yr — Implementation Discipline 기준선 11.0/yr 초과",
    "[INFO] cap-tier 비중 OTHER 87.9% 는 편중 증거가 아님 — 유니버스 자체가 OTHER 압도(MEGA 10·MID 20 정의상 상한). 대조 없는 편중 해석 금지"
  ),
  method_shopping_log = list(candidates_tried = 1, n_trials = 1,
    method_log = list(list(name = "M26_Revenue_Mom (factor_db 산출 원형)", fmb_nw3_t = AV$primary$fmb_nw3_t, selected = TRUE)),
    note = "사전등록 no_sweep — 신호 변형(창 길이·정규화·업종중립) 열거 없음. selection_type 은 chain 도 sweep 도 아닌 단일 시험."),
  round_provenance = list(
    prereg = "stage_artifacts/c14_revsurprise/prereg.json",
    target_correction = paste0("원 사전등록 대상은 C14_Revenue_Surprise 였으나 factor_db 442개 월 파일 전 구간 0행(부재)이고, ",
      "같은 재료·같은 식의 M26_Revenue_Mom 이 이미 산출 중이므로 대상만 M26 으로 정정. ",
      "판정 규칙·문턱(|t|>=2.0)·분기(MATERIAL_QUALIFIED/REDUNDANT/NEGATIVE_POWERED/INCONCLUSIVE_UNDERPOWERED)는 불변 승계."),
    verdict = AV$primary$verdict
  )
)

dir.create(MB, recursive=TRUE, showWarnings=FALSE)
PKG <- file.path(MB, "alpha_package.json")
write(toJSON(pkg, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null"), PKG)
say("alpha_package.json 저장 (%d bytes)", file.size(PKG))

say("lineage 는 np_lineage.R 로 분리 기록(L-194 순서 준수)")
