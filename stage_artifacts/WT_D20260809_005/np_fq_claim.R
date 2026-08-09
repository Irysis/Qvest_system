## FQ 등재 + CLAIM — 컨센서스 해금 4종 재료 자격 라운드
## ★ID 하드코딩 금지: 원장 최대 번호+1 계산 → 기록 → 재읽기로 존재 확인 (consume_rule 규약)
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
num <- suppressWarnings(as.integer(sub("^FQ-", "", ids)))
new_id <- sprintf("FQ-%03d", max(num, na.rm=TRUE) + 1L)
cat(sprintf("[claim] 원장 항목 %d · 최대번호 %d ⇒ 신규 %s\n", length(ids), max(num,na.rm=TRUE), new_id))

## ★충돌 실측 기록: 프롬프트가 지시한 'FQ-174' 는 병렬 세션이 다른 주제로 선점 중
fq174 <- Q$entries[[which(ids=="FQ-174")]]
cat(sprintf("[claim] 기존 FQ-174 = '%s' (owner: %s) ⇒ ID 충돌 확인, 신규 번호로 등재\n",
            substr(fq174$title,1,50), substr(fq174$owner,1,40)))

WT <- "WT-D20260809_005"
e <- list(
  id = new_id,
  lane = "non_return",
  title = "해금된 컨센서스 4종(C10/C13/C15/C18) 재료 자격 — 북 incumbent 3종 위 증분",
  hypothesis = paste0(
    "FQ-163 빌더 수리 + 2026-08-09 factor_db 전면 재빌드(build_hash 20260809203741_8c9befe0)로 ",
    "442개월 전 구간 0행이던 C10_SUE_Persistence·C13_Revision_Breadth_3m·C15_Forecast_Error_Trend·",
    "C18_Earnings_CAR_3d 가 실제로 실렸다. 이 4종은 M2x 에 등가물이 없어 저장소에서 한 번도 측정된 적이 없다. ",
    "북 incumbent 컨센서스 3종(C01_SUE·C02_EPS_Chg_1m·C04_ESBR) 을 통제한 뒤에도 각각 증분 설명력이 남는가."),
  ev_rationale = paste0(
    "선례 = M26_Revenue_Mom(WT-D20260808_002) 가 동일 프레임에서 FMB NW3 t +2.555 로 재료 자격 획득. ",
    "재료비용 0(재빌드 완료·팩터 DB 상주) · 하네스 100% 재사용(np_m26_increment.R). ",
    "C18 은 이벤트-CAR 성격으로 비-return 인접 신규 재료 후보(v8.3 주력 lane)."),
  wall_check = paste0(
    "★재료 자격까지만 주장 가능 — 자본 주장 금지. 선례 M26 이 재료 자격(t 2.555)은 얻고 전이는 미달",
    "(cap-w PORT_t 1.544 < 2.95 · oos_retention 0.123 · 회전율 11.74 > 11.0). ",
    "IC→PORT_t 전이 벽은 본 라운드에서 해소되지 않는다. n_trials=4 · selection_type=preregistered_family_grid."),
  data_gate = "없음 — 재빌드 완료 확인(C10/C15/C18 각 300개월 · C13 303개월). 단 유효 관측(non-NA × 유니버스 교집합)은 P0 사전 확인에서 실측.",
  owner = sprintf("CLAIMED alpha-research %s (2026-08-09) — 프롬프트가 지시한 'FQ-174' 는 병렬 세션 선점(폐지풀 ML 앙상블)이라 %s 로 재배정", WT, new_id),
  status = "in_flight_20260809",
  next_action = "P0 사전 확인(유효월·커버리지·spearman·required_effect) → 통과 시 4종 각각 별도 primary 로 FMB 증분 회귀.",
  source_refs = list(
    "parent: FQ-163 (compute_consensus.R 침묵 스킵 7종 수리 + 전면 재빌드)",
    "frame: stage_artifacts/WT_D20260808_002/np_m26_increment.R (M26 재료 자격 선례 t +2.555)",
    "build_hash: 20260809203741_8c9befe0"
  ),
  registered = "2026-08-09",
  registered_by = sprintf("alpha-research %s", WT)
)
Q$entries[[length(Q$entries)+1L]] <- e
write_frontier_queue(Q)

## ★재읽기로 존재 확인 (선언에서 파생 금지)
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(x) as.character(x$id)[1], character(1))
ok <- new_id %in% ids2
cat(sprintf("[claim] 재읽기 확인: %s 존재=%s · 총 항목 %d (이전 %d)\n", new_id, ok, length(ids2), length(ids)))
if (!ok) stop("[claim] 등재 실패 — 병렬 세션 충돌 의심")
writeLines(new_id, "stage_artifacts/WT_D20260809_005/FQ_ID.txt")
