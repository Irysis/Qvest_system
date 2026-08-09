## P5 — 프론티어 큐 등재 (번호 하드코딩 금지: 쓰기 직전 read → max+1 → 재읽기 확인)
##   ★2026-08-09 실사고: 병렬 세션 선점으로 번호가 충돌해 등재가 조용히 생략됐다.
##     이 라운드 착수 시점 max 는 210 이었는데 배선 도중 213 으로 올라갔다.
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")
say <- function(fmt, ...) cat(sprintf(paste0("[p5] ", fmt, "\n"), ...))

Q <- read_frontier_queue()                     # ★쓰기 직전 read
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-([0-9]+).*$", "\\1", ids[grepl("^FQ-[0-9]+", ids)])))
nums <- nums[!is.na(nums)]
NEW_ID <- sprintf("FQ-%d", max(nums) + 1L)
say("원장 항목 %d · 최대번호 %d → 배정 %s", length(ids), max(nums), NEW_ID)
if (NEW_ID %in% ids) stop("배정 번호가 이미 존재 — 중단")

entry <- list(
  id = NEW_ID,
  title = "★emission_guard 정체 3축 배선 완료 후 잔여 — 미선언 중복 5쌍 정본 지정 · 죽은 배출 3종(C15/D60/Q16) 기전 규명 · 근접쌍 0.995 밴드",
  status = "frontier_open",
  owner = "UNCLAIMED",
  lane = "infra_measurement_integrity",
  hypothesis = paste0(
    "FQ-210 이 적발한 정체 결손은 감시축을 붙여 **재발 검거**까지 왔다(본 라운드). 남은 것은 두 종류다: ",
    "(a) 이미 검거된 결함의 **처분** — 축 I 미선언 5쌍은 registry `dedup` 정본 지정이 없으면 매월 영구 발화하고, ",
    "영구 발화하는 경보는 곧 무시된다(가드 설계원칙 ② 가 경고한 실패 양식). ",
    "(b) 검거는 됐으나 **기전 미규명** — C15/D60/Q16 이 왜 횡단면 상수인지."),
  ev_rationale = paste0(
    "본 라운드 실측(2026-08-09, 재빌드 없음 · load_month_factors + emission_ledger 재판독). ",
    "3축을 emission_guard.R v1.1 에 배선하고 6개월(200506/201006/201406/201806/202206/202606) dry-run: ",
    "축 D 미선언 월 1~3종(C15 상시 · D60/Q16 은 201806·202206) / 선언 면제 13~15종(시장레벨). ",
    "축 T warn(modal_frac>=0.99) 0종 · watch(>=0.95) 0~1종(SE02). ",
    "축 I |rho|>=0.999 hit 55~63쌍 중 **미선언 정확히 5쌍**(6/6월 전부 동일한 5쌍) — ",
    "C01_SUE~C10_SUE_Persistence(1.000000) · C04_ESBR~C13_Revision_Breadth_3m(1.000000) · ",
    "C11_Earnings_Streak~M25_Earnings_Mom_Streak(0.999951~0.9999997) · ",
    "C01_SUE~C09_Earnings_Surprise_Sq(0.9999838~0.9999982) · C09~C10(추이적). ",
    "★문턱은 실측으로 확정: 미선언 월평균이 0.95→37쌍 / 0.98→16.2 / 0.99→14.8 / 0.995→7.2 / 0.999→5.0 / 0.9999→5.0. ",
    "0.999 에서 평평해지므로(0.9999 와 동일 5쌍) 그 지점이 자연 절단이고, registry dedup 선언 대조가 경보를 11.9배 줄인다(59.5→5.0)."),
  wall_check = paste0(
    "★잔여 위험은 '경보가 붙었으나 처분이 없다' 쪽이다. 축 I 5쌍은 매월 발화하지만 registry `dedup` 갱신 권한 밖(정본 지정 = 팩터 소유 판단)이라 본 라운드에서 손대지 않았다. ",
    "또한 축 I 는 경고만 늘리고 **선별은 그대로**다 — FQ-210 §5.4 확인대로 drop_alias_factors()/resolve_factor_canonical()/report_redundant_clusters() 의 실코드 소비자가 0이고 ",
    "registry `consumption_rule`(127종 선언)을 읽는 코드도 없다. 즉 기선언 224쌍도 선별·Ω 추정에서 계속 이중 투표한다(표준↔소비자 배선 지도 계통). ",
    "문턱 아래 미선언 근접쌍도 실측됨: D60_Leverage~Q16_Debt_to_Assets 0.9979(둘 다 죽은 배출 — 살아있는 월에서 서로 동일), ",
    "베타 계열 D12_Beta_126d~RE04_HighVol_Beta 0.9964 · D12~D20_EW_Beta_126 0.9960 · D20~RE04 0.9953 · C05_ESCR~C10 0.9952 · D02/D10/D31~D12 0.9931. ",
    "0.995 로 낮추면 월 7.2쌍이라 아직 실행가능하나, 베타 계열은 정의상 근접이 정상일 수 있어 **선언이 먼저**다(문턱을 먼저 낮추면 소음이 된다)."),
  data_gate = "없음 — 기존 월 parquet + emission_ledger.csv 재판독. 재빌드 불요(dry-run 6개월 26초). registry dedup 갱신은 판단 사안이지 데이터 사안이 아님.",
  next_action = paste0(
    "★next_probe(4) = ",
    "① 축 I 미선언 5쌍 정본 지정 — consensus 계열에서 한 신호(SUE)가 C01/C09/C10 3중, ESBR 이 C04/C13 2중, streak 이 C11/M25 2중 등록. ",
    "canonical 1개 + redundant 나머지로 registry `dedup.cluster` 부여하면 축 I 경보가 5→0 으로 떨어진다(경보 소멸이 목적이 아니라 **처분 기록**이 목적). ",
    "★C09 는 sign(sue)*sue^2 = 순증가 단조변환이라 '증폭' 주석과 달리 top-N 선별·rank-IC 어디서도 C01 과 구별되지 않는다 — 삭제가 아니라 canonical 위임이 정합. ",
    "② C15/D60/Q16 상수값 정체 규명 — Raw_Value 가 0 인지 다른 상수인지. C15 는 `.cons_history()` 가 4분기 아닌 4영업일을 보는 기전이 지목돼 있다(sue[1]==sue[2] → delta 0). ",
    "D60/Q16 의 2015-01 경계가 2026-08-08 DART 계정명 매칭 수리와 정합하는지 **vintage-swap 통제**로 확인(placebo/lag 는 이 계통을 못 잡는다). ",
    "소비면 영향: 부채/레버리지 팩터를 쓰는 모든 선별·Ω 추정이 2015~2025 구간에서 팩터 2종을 빈손으로 돌렸다. ",
    "③ dedup 소비 배선 — drop_alias_factors() 를 팩터 선별·Ω 추정 진입점에서 실제로 호출하지 않으면 선언 224쌍이 계속 이중 투표한다. 배선 후 book-marginal 영향 실측. ",
    "④ 단조변환 재등록 전수 — 본 라운드 격자는 Z 면(winsorize 1/99 + ±3 clip + 재표준화) 위였다. Raw_Value 면에서 다시 재면 clip 에 가려진 쌍이 더 나올 수 있다(FQ-210 next_probe ② 승계)."),
  consumer_surfaces = paste0(
    "①팩터 랭킹(중복 팩터가 같은 신호에 2~3표) ②Ω/공분산 추정(중복 축이 분산 구조 왜곡) ",
    "③선별 라벨(죽은 배출 3종은 2015~2025 구간 선별에서 빈손) ④risk model crowding ",
    "⑤monitoring(신규 팩터 해금 보고의 진위) ⑥factor-db-discovery 배터리 ⑦타 모드 이식(RAMP 순수팩터 추출 입력)"),
  revival_condition = paste0(
    "본 항목은 즉시 착수 가능(차단 없음). ①은 registry 쓰기 판단이라 팩터 소유 결정이 필요할 수 있음. ",
    "②는 vintage-swap 통제 설계 후 착수. ★부활신호: 축 I 미선언 쌍이 5 를 넘거나(새 중복 등록) 축 D 미선언이 3 을 넘으면 즉시 재우선."),
  source_refs = paste0(
    "배선: 02_Infrastructure/factor_db/emission_guard.R v1.1(factor_identity_check + emission_dedup_pairs + emission_load_identity_baseline) · ",
    "02_Infrastructure/factor_db/factor_db_builder.R(FACTOR_IDENTITY_BASELINE 전달·run_identity=TRUE) · ",
    "02_Infrastructure/factor_db/emission_declared_identity.json(시장레벨 15종 면제 래칫) · ",
    "검사: 08_Tests/factor_db/test_emission_identity_axes.R(8축 40케이스, 돌연변이 7종 전부 검출) + run_all_hooks.sh SUITES 등재 · ",
    "산출물: stage_artifacts/infra/emission_guard_identity_axes_20260809/ · 선행 감사: FQ-210 / 04_Research/01_reports/factor_emission_identity_audit_20260809.md"),
  created = format(Sys.Date(), "%Y-%m-%d")
)

Q$entries <- c(Q$entries, list(entry))
Q$updated <- format(Sys.Date(), "%Y-%m-%d")
write_frontier_queue(Q)

## ★재읽기 확인 — 기록이 실제로 도달했는가
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
if (!NEW_ID %in% ids2) stop("★재읽기에서 ", NEW_ID, " 미발견 — 등재 실패")
hit <- Q2$entries[[which(ids2 == NEW_ID)]]
say("재읽기 확인 OK — %s · status=%s · owner=%s · 총 항목 %d (이전 %d)",
    NEW_ID, hit$status, hit$owner, length(ids2), length(ids))
say("형식 정본 유지: %s", frontier_queue_format_ok())
writeLines(NEW_ID, "stage_artifacts/infra/emission_guard_identity_axes_20260809/FQ_ID.txt")
