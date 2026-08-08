# close_np160b1.R — NP-160b1 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "NP160B1_20260808_WINDOW_IDENTIFICATION_UNESTABLISHED",
  verdict_type = "config_scoped_negative",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "회수 가능 40건에서 실제 창 값을 뽑으니 n_months 32건 · 종료월 17건(164 대비 10.4%)만 나왔고 종료월은 2026 이 11건으로 쏠렸다.",
    "★그러나 이 값들은 값 수준에서 신뢰할 수 없다 — 추출기가 '참조 파일 안의 월처럼 보이는 최대 숫자'를 취할 뿐 그것이 해당 FQ 의 측정 창이라는 식별이 없다.",
    "예: FQ-009 n=220 은 d3_deployability_dossier 문서 어딘가의 숫자일 수 있고 그 항목의 창이라는 보장이 없다.",
    "= 같은 세션에서 적립한 규약(존재/모양 검사 전에 정체 검사)을 추출기가 또 어겼다. 3회째 동일 축.",
    "★살아남는 진술: 종료월을 뽑을 수 있는 항목이 17/164(10.4%) 이고 값 수준 식별은 미확립이다.",
    "★함의 정정: NP-160b 의 24.4% 는 '창 정보가 존재하는 비율'이지 '그 항목의 창으로 식별된 비율'이 아니었다. 실사용 가능분은 그보다 낮고 확립되지 않았다.",
    "⇒ NP-157c 의 창-핸디캡 지도는 현재 기존 큐에 신뢰성 있게 결합할 수 없다. 결손은 데이터가 아니라 선언(식별)이다."),
  next_probes = c(
    "NP-160b2 승격(최우선) — 큐에 artifact_paths 와 measurement.window_months/window_end 를 선언 필드로 도입. 본 세션에서 모양 휴리스틱이 3회 연속 오답을 냈다는 것이 선언 필요의 실증이다. 추정으로는 이 문제를 못 넘는다",
    "NP-160b1a 표본 수동 검증 — 17건 중 5건을 사람이 직접 원 산출물과 대조해 '문서 속 숫자 vs 그 FQ 의 창' 일치율을 재고, 자동 추출의 실제 정확도 상한을 얻는다. 이 값이 낮으면 어댑터 경로는 접는다",
    "NP-157c 소비 경로 변경 — 기존 기각에 결합하는 대신, 앞으로의 라운드에 창 메타를 강제해 지도를 신규분에만 적용. 과거 결합을 포기하는 대신 즉시 소비 가능해진다"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "monitoring"),
  frontier_update = "NP-160b1 = 값 수준 식별 미확립 · NP-160b 24.4% 의 해석 정정(존재 비율이지 식별 비율 아님) · NP-160b2 최우선 승격",
  live_trigger = "선언 필드 도입 시 NP-157c 지도를 신규 라운드부터 즉시 결합 — 과거 소급은 NP-160b1a 정확도 실측 후 판단",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np160b_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np160b_per_entry.json")
)
cat("[close_np160b1] RC_OK\n")
