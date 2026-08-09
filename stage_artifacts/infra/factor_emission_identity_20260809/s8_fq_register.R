## S8 — 프론티어 큐 등재 (번호 하드코딩 금지: read → max+1 → write → 재읽기 확인)
##   정본 writer 경유 (02_Infrastructure/ops/frontier_queue_io.R) — digits=NA / pretty=1 / 손실가드
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids)))
next_n <- max(nums, na.rm = TRUE) + 1L
NEW_ID <- sprintf("FQ-%03d", next_n)
cat("[s8] 기존 항목", length(Q$entries), "· 최대번호", max(nums, na.rm = TRUE),
    "→ 신규", NEW_ID, "\n")
if (NEW_ID %in% ids) stop("[s8] 번호 충돌: ", NEW_ID)

entry <- list(
  id = NEW_ID,
  title = "★factor_db 배출 정체 검사 — 죽은 배출 3종(C15·D60·Q16) + 미선언 중복 5쌍, emission_guard 정체축 부재",
  status = "frontier_open",
  owner = "Q-Lead session (infra hygiene round 20260809)",
  lane = "infra_measurement_integrity",
  hypothesis = paste0(
    "FQ-198 이 적발한 '가짜 신규 해금'(C10≡C01·C13≡C04·C15 무산출)은 단발 사고가 아니라 ",
    "emission_guard 의 축 결손이다 — 가드는 `n_rows>0` 만 보므로 (i) 다른 팩터와 값이 같은 배출과 ",
    "(ii) 횡단면 상수라 소비면에 0으로 도달하는 배출을 원리적으로 못 본다. 같은 함정의 다른 사례가 더 있을 것."),
  ev_rationale = paste0(
    "실측 확인(재빌드 없음, build_hash 20260809203741_8c9befe0 재판독). ",
    "정체 축: 표본 6월(2005/2010/2014/2018/2022/2026-06) × 커넥터 가시 331팩터(쌍 54,615) 월별 횡단면 spearman. ",
    "|rho|>=0.99 139쌍 = EXACT_BITWISE 16 / RANK_IDENTICAL 55 / NEAR 68. registry `dedup` 선언 대조 시 ",
    "기선언 101 · 미선언 38. 미선언 EXACT/RANK 5쌍 = C01_SUE≡C10_SUE_Persistence(rho 1.000000·maxdiff 0.000e+00) · ",
    "C04_ESBR≡C13_Revision_Breadth_3m(동일) · C11_Earnings_Streak≡M25_Earnings_Mom_Streak(rho 0.9999933~1.000000) · ",
    "C01_SUE≡C09_Earnings_Surprise_Sq(rho 0.9999838~0.9999982) · C09≡C10(추이적). ",
    "C09 = sign(sue)*sue^2 = 순증가 단조변환이라 순위가 구조적으로 동일 — 값 비교로는 다르고 랭크로만 잡힌다. ",
    "즉 consensus 계열에서 한 신호(SUE)가 C01/C09/C10 3중 등록, ESBR 이 C04/C13 2중, streak 이 C11/M25 2중."),
  wall_check = paste0(
    "살아있음 축: 반기 격자 61개월(199606~202606) 전수. 배출셀 19,090 중 소비면 도달 0 = 904셀. ",
    "DEAD_ALWAYS 16종(797셀) 중 15종은 시장레벨 상수(RE01/02/03/10~16·MA05/06/07·CR03·M31)로 빌더가 설계로 인정(682·719~721행) = 정당. ",
    "★비-시장레벨 진짜 죽은 배출 = C15_Forecast_Error_Trend 50/50월(200112~202606, 월 ~854행). ",
    "DEAD_PARTIAL 24종(107셀) 중 ★D60_Leverage · Q16_Debt_to_Assets 각 22/53월 = 2015-01~2025-12 연속 11년 전 구간 사망(월 2,753~2,968행). ",
    "기전 확정: 빌더 682행 `sd(winsorized raw) < 1e-12 → Z 전건 NA → Coverage FALSE`. ",
    "Q16/D60 은 compute 단계에서 !is.na() 필터 통과분만 배출하므로 그 행들은 **유한하되 횡단면 상수**다. ",
    "내부 대조로 원인 축 국소화: 같은 부채 원천을 쓰는 Q15_Debt_to_Equity 는 modal_frac 중앙 pre2015 0.5283 → 2015_2025 0.9370 → 2026+ 0.7141, ",
    "XF_LL01_DebtToCapital 0.5283 → 0.9361 → 0.7108 로 같은 창에서 준-사망까지 갔고, ",
    "시장가를 섞는 R17_Market_Leverage 는 0.1223 → 0.1054 → 0.1080 으로 무변 ⇒ 결손은 부채 원천 축에 국한(2015 경계)."),
  data_gate = "없음 — 기존 월 parquet + emission_ledger.csv 재판독만. 재빌드/재계산 불요(전체 감사 실측 소요 ~150초).",
  next_action = paste0(
    "★next_probe(4) = ① C15/D60/Q16 의 상수값 정체 규명(Raw_Value 가 0 인지 다른 상수인지). ",
    "C15 는 `.cons_history` 가 4분기 아닌 4영업일을 보는 기전이 이미 지목됨(sue[1]==sue[2] → delta 0). ",
    "D60/Q16 의 2015-01 경계가 DART 계정명 매칭 수리(2026-08-08)와 정합하는지 vintage-swap 통제로 확인. ",
    "② 단조변환 재등록(C09 형)이 다른 계열에도 있는지 Raw_Value 기준으로 전수 — z/winsorize 에 가려진 쌍이 더 있을 수 있다. ",
    "③ emission_guard 축 D/T/I 부착 시 경보량 dry-run 후 문턱 확정(소음이면 무시된다). ",
    "④ SE02_Consensus_Revision — modal_frac 중앙 0.957(27/43월 >=0.95) + 사망 10/53월, 선별 풀 소비 여부 확인 후 screen 자격 재판정."),
  consumer_surfaces = list(
    "factor_db 월 빌드 감시(emission_guard 축 D/T/I)",
    "팩터 선별 랭킹(중복 이중 투표 제거)",
    "위험모델 Ω 추정(중복 팩터의 rank 결핍)",
    "부채/레버리지 팩터를 쓰는 모든 라운드(2015~2025 구간 2종 빈손)",
    "registry dedup 선언 → 소비 배선(현재 소비자 0)"
  ),
  revival_condition = paste0(
    "emission_guard 에 정체/무분산 축이 배선되면 본 항목은 상시 감시로 전환. ",
    "그 전까지 신규 팩터 '해금' 보고는 값-동일성 검사를 통과한 것만 유효."),
  source_refs = list(
    "stage_artifacts/infra/factor_emission_identity_20260809/",
    "04_Research/01_reports/factor_emission_identity_audit_20260809.md",
    "02_Infrastructure/factor_db/emission_guard.R",
    "02_Infrastructure/factor_db/factor_dup_scan.R",
    "02_Infrastructure/factor_db/factor_db_builder.R:682,719-722,928,953",
    "02_Infrastructure/factor_db/compute_consensus.R:229-337",
    "FQ-198 / WT-D20260809_005"
  ),
  created = "2026-08-09"
)

Q$entries[[length(Q$entries) + 1L]] <- entry
Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat("[s8] write 결과 — 추가:", paste(res$added, collapse = ","),
    "· 삭제:", length(res$removed), "· 총", res$n, "\n")

## ★재읽기 확인 (병렬 세션 다수 — 쓴 것이 실제로 읽히는지 값으로 확인)
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
cat("[s8] 재읽기: 항목", length(Q2$entries), "· 신규 id 존재:", NEW_ID %in% ids2, "\n")
hit <- Q2$entries[[which(ids2 == NEW_ID)]]
cat("[s8] 재읽기 title:", substr(hit$title, 1, 60), "\n")
cat("[s8] 재읽기 status:", hit$status, "· next_action 길이:", nchar(hit$next_action), "\n")
stopifnot(NEW_ID %in% ids2, identical(hit$id, NEW_ID))
writeLines(NEW_ID, "stage_artifacts/infra/factor_emission_identity_20260809/FQ_ID.txt")
cat("[s8] 완료 —", NEW_ID, "\n")
