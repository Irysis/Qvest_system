# R9 — Self-Adversarial 결과를 risk_package 에 반영(ACCEPT 3건 수정 + REBUTTAL 2건 근거 등재)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
S5 <- readRDS(file.path(OUT,"risk_calc_stage5.rds"))
p <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector=FALSE)
ep <- S5$ep; TH <- S5$TH; SENS <- S5$SENS; BLK <- S5$BLK
dtl <- function(D) lapply(seq_len(nrow(D)), function(i) as.list(D[i]))

## SC1 (ACCEPT) — 국면 Sigma 의 소비 제한 명시
p$risk_summary$regime_sigma_heterogeneity$consumption_restriction <- list(
  scope="as-of 진단 전용",
  rule="structural_sigma_same_B(Sigma_panic / Sigma_normal)는 sig_date 2026-08-28 시점 표본 전체로 추정한 **as-of 구조 비교**다. 과거 의사결정일에 이 행렬을 그대로 소비하면 그 시점 기준 미래참조가 된다(C1). 백테스트 경로에서 국면 Sigma 가 필요하면 ex_ante_knowability 절차대로 **각 시점 이전 표본만으로** 재추정할 것.",
  forge_note="forge 가 전기간 백테스트에서 covariance_panic.parquet / covariance_normal.parquet 를 시점 무관하게 쓰면 PIT 위반이다. 사용 시 재추정 경로를 산출물에 명시하라.")

## SC4 (ACCEPT) — 에피소드 해상도 실증 + 판정 하향
p$risk_summary$regime_sigma_heterogeneity$episode_level_dispersion <- list(
  method="패닉 26개월을 연속 구간으로 묶어 에피소드 4건으로 환원하고, 각 에피소드의 실현 슬리브 vol 을 비패닉 평균 대비 배율로 산출",
  base_vol_ann_nonpanic=S5$base_vol,
  episodes=dtl(ep[, .(episode=brk, n_months=n, vol_ann=vol, mean_corr=corr, ratio_vs_nonpanic=ratio)]),
  ratio_range=c(min(ep$ratio), max(ep$ratio)), ratio_sd_across_episodes=sd(ep$ratio),
  reading="에피소드별 배율 0.53 / 0.78 / 1.36 / 0.57 — 에피소드 간 sd 0.385. 구조 Sigma 가 말하는 1.08 배는 이 산포 안에 완전히 파묻힌다. 26개월은 표본 크기가 아니라 **에피소드 4** 가 실질 자유도다(memory: 구속하는 건 월 수가 아니라 에피소드 수).",
  verdict_downgrade="국면별 Sigma 이질성의 **수준(배율)** 은 유의하다고 주장하지 않는다. 유의하게 말할 수 있는 것은 ①구성(structure) 축의 이동 — 시장성분 share +7.9pp ②상관은 움직이지 않는다는 부정 결과 ③사전 인지 불가(상관 0.169) 세 가지다.")
p$risk_summary$regime_sigma_heterogeneity$ex_ante_knowability$episode_resolution_note <-
  "n=20 은 월 단위이고 에피소드는 3건(첫 에피소드 제외)이다 — 상관 0.169 는 '정보 없음'의 강한 증거가 아니라 '정보를 검출할 검정력이 없음'에 가깝다. 두 서술의 차이를 흐리지 않기 위해 verdict 는 NO_TIMING_INFORMATION 로 두되 근거는 검정력 한계로 읽을 것."

## SC5 (REBUTTAL 근거) — EVT threshold 안정성
p$risk_summary$tail_risk$evt_threshold_stability <- list(
  method="GPD(POT) MLE 의 shape xi 를 threshold 분위수 4점에서 재적합",
  table=dtl(TH), xi_range=c(min(TH$xi), max(TH$xi)),
  reading="xi 가 0.101~0.156 로 전 구간 양수 — 두꺼운 꼬리(Frechet) 판정은 threshold 선택의 아티팩트가 아니다. 초과관측 133~532 로 표본도 충분.")

## SC6 (REBUTTAL 근거) — D 추정 민감도
p$diagnostics$specific_risk_sensitivity <- list(
  method="D 의 EWMA halflife(3/6/12개월) x 하한(median의 0.10/0.25/0.50배) 9조합 재추정",
  table=dtl(SENS), vol_ann_range=c(min(SENS$vol_ann), max(SENS$vol_ann)),
  spec_share_range=c(min(SENS$spec_share), max(SENS$spec_share)),
  reading="포트 연율 vol 0.687~0.690(스프레드 0.4%), 특이비중 2.67~3.49%. D 의 자유도 선택은 이 책의 위험 수준을 사실상 움직이지 않는다 — 25종 EW 집계에서 특이위험이 이미 상쇄되기 때문. 즉 특이분산 추정의 임의성은 결론의 약점이 아니다.")

## SC7 (ACCEPT) — 섹터 집중은 Sigma 안에 있다. top_common_risks 서술 교정
p$risk_summary$concentration$sector_block_variance_contribution <- list(
  method="Sigma 안에서 섹터 블록별 분산 기여 = sum_{i in S} w_i (Sigma w)_i / (w'Sigma w) · within = 블록 내부 공분산만",
  table=dtl(BLK),
  reading="반도체 13종(비중 52%)이 총분산의 58.9% 를 만든다(그 중 블록 내부 공분산만 36.9%p). 요인 라벨 'SEC_반도체 2.0%' 는 **시장성분 제거 후 잔여 섹터요인** 의 몫일 뿐이며, 반도체 집중의 실질 위험은 Market·x_mom·x_vol 을 통해 흐른다. 집중을 요인 라벨 share 로 읽으면 과소평가한다.",
  correction="risk_summary.top_common_risks 의 'Sector_반도체 (2.0%)' 는 요인-라벨 기준 값이다. 집중 판단은 본 블록 기여(58.9%)로 할 것.")
p$risk_summary$top_common_risks_note <- "요인-라벨 기준 분해. 종목집중/섹터집중의 실질 몫은 concentration.sector_block_variance_contribution 을 볼 것(반도체 블록 58.9%)."

## RF-R6 메시지 정량 보강
for (i in seq_along(p$red_flags)) if (identical(p$red_flags[[i]]$id, "RF-R6-CONCENTRATION"))
  p$red_flags[[i]]$message <- sprintf("섹터 집중 극단: 반도체 13/25종(비중 52%%) · 섹터 HHI 0.306 · ★Sigma 내 분산 기여 58.9%%(내부 공분산 36.9%%p). failure_rules 의 '>50%% 극단' 해당. 2026-08-29 체인완주 지시에 따라 ABORT 하지 않고 flag 로 이관.")

## self-adversarial 요약
p$self_adversarial <- list(
  performed=TRUE, method="Opus native adversarial reasoning (v8.2 — 외부 Codex 라운드 없음)",
  n_concerns=7L,
  classification=list(ACCEPT=3L, PARTIAL=2L, REBUTTAL=2L),
  concerns=list(
    list(id="SC1", axis="PIT/C1", verdict="ACCEPT",
         concern="국면 Omega 를 sig_date 전 표본으로 추정 — 과거 시점에서 소비되면 미래참조",
         action="regime_sigma_heterogeneity.consumption_restriction 신설 + forge 경고"),
    list(id="SC2", axis="추정기 선택 R4 P3", verdict="REBUTTAL",
         concern="bias statistic 이 실현수익을 참조하므로 알파 기반 선택 아닌가",
         rebuttal="1급 bias 는 유니버스에서 무작위 추출한 롱온리 25종 EW 포트 896 포트-월로 산출했다(알파 슬리브 아님). 측정 대상은 예측 vs 실현의 **산포 배율**이지 수익 수준이 아니며, SR/IR 는 이 라운드에서 단 한 번도 계산하지 않았다. 1급 게이트는 선언한 enum(PSD·cond)이고 ledoit_wolf 기각 사유도 등방 붕괴라는 구조 근거다. 슬리브 bias 는 진단 병기로만 실었다."),
    list(id="SC3", axis="Sigma PD", verdict="REBUTTAL",
         concern="eigen-floor 로 PD 를 인위적으로 만든 것 아닌가",
         rebuttal="floor 는 Omega 에만 걸었고 Sigma 는 floor 이전에도 min eig>0 · cond 163 이었다. floor 적용 후 Sigma cond 는 163->177 로 **악화**했다 — 유리한 수치를 만드는 방향이 아니다. 최종 PSD 는 발행된 covariance.parquet 을 다시 읽어 독립 고유분해로 재확인(min eig 5.93e-3)."),
    list(id="SC4", axis="국면 소표본", verdict="ACCEPT",
         concern="26개월/4에피소드로 국면 Sigma 배율을 말할 수 있는가",
         action="에피소드별 실현 배율 실측(0.53~1.36, sd 0.385) 등재 + 배율 주장 철회. 남기는 주장은 구조 share 이동·상관 불변·사전인지 불가 3건으로 축소"),
    list(id="SC5", axis="꼬리 지표 선택", verdict="PARTIAL",
         concern="fExtremes 부재로 GPD 를 자체 구현했고 threshold 는 임의 아닌가",
         action="threshold 4점 재적합으로 xi 안정성 실증(0.101~0.156 전부 양수). 다만 자체 구현이므로 fExtremes 파리티 검증은 미수행 — 그 한계를 명시"),
    list(id="SC6", axis="D 추정 임의성", verdict="REBUTTAL",
         concern="halflife 6M·하한 0.25x median 은 임의 선택",
         rebuttal="9조합 민감도에서 포트 vol 0.687~0.690, 특이비중 2.67~3.49%. 결론을 움직이지 않는다는 것을 수치로 보였다."),
    list(id="SC7", axis="섹터 위험 누락", verdict="ACCEPT",
         concern="반도체 52% 집중이 요인 share 2.0% 로만 보이는 것은 모형이 집중을 놓친 것 아닌가",
         action="Sigma 내 섹터 블록 기여 실측(반도체 58.9%, 내부 공분산 36.9%p) 등재 + top_common_risks 해석 주의 문구 삽입")),
  self_rationalization_check=list(
    forbidden_phrases_used=FALSE,
    audit="'영향 미미 / 관행적 허용 / 보수적이면 괜찮다 / 대부분 결과 동일' 사용 여부 자체 점검 — SC6 은 '미미'라고 쓰지 않고 9조합 수치 범위로 대체했고, SC4 는 '소표본이지만 방향은 맞다' 로 넘기지 않고 배율 주장 자체를 철회했다."),
  escalation_check=list(HIGH_count=3L, axiom_hard_fail=0L, pit_hard_violation=FALSE,
    sigma_pd_violation=FALSE,
    escalated=FALSE,
    rule="HIGH>=5 / AX hard FAIL>=3 / PIT hard violation / Sigma PD violation 중 해당 없음 → Q-Lead 자동 escalate 미발동. 단 challenge_flags 6건은 하류로 전달."))

write_json(p, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, null="null", na="null")
cat("[R9] risk_package.json 보강 기록 완료\n")
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id="WT-R20260829_004", package_type="risk_package",
  method_selected="ewma_hl126_eigenfloor_factor_model_BOmegaB_plus_D (self-adversarial patched)",
  input_file_paths=c("qepm/mailbox/worktask/WT-R20260829_004/alpha_package.json"),
  windows=list(list(name="self_adversarial_patch", start="2005-02", end="2026-08")),
  extra=list(patch="SC1/SC4/SC7 ACCEPT 반영 · SC2/SC3/SC6 REBUTTAL 근거 등재 · SC5 PARTIAL"))
cat("[R9] lineage 기록 완료\n")
