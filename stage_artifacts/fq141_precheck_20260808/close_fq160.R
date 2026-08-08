# close_fq160.R — FQ-160 재정의 라운드 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "FQ160_20260808_QUEUE_RESULT_SCHEMA_ABSENT",
  verdict_type = "capability_established",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "원안(창 메타를 wall_check 에 추가)의 전제가 어긋났다 — wall_check 는 측정 기록이 아니라 가설 시점의 예상 서술이다.",
    "실측: wall_check 실질 보유 157/164 중 창 정보(n=/개월/연-월) 보유는 2건(1.3%)이고, 내용 표본이 전부 '전이 벽은 미검증' 류 사전 서술.",
    "실제 결함은 결과 계층의 스키마 부재다: 코어 11 필드 외 필드명이 109종이고 139/164(84.8%) entry 가 임시 결과 필드를 보유한다.",
    "동의어 군집 실재 — 결과(result/result_ref/result_lcode/result_artifacts/result_20260725/alpha_round_result/direction_a_result/ev_check_result/key_finding),",
    "판정(verdict/verdict_date/verdict_artifact/measured_verdict), 사전확인(precheck_measured/precheck_result/precheck_20260808), 부활(revival_conditions/signal/trigger), 소비면 5종.",
    "★알파 차단 근거: 소비자가 109개 이름을 알아야 하므로 소비 코드를 쓸 수 없고, 실제로 이번 세션에서 NP-157c 산출물(창 길이별 핸디캡 지도)을 기존 기각 164건에 결합하지 못해 소비가 멈췄다.",
    "★자기 기여 정직 표기: 필자가 이번 세션에 np_a_result/np_157c/precheck_20260808 3개를 보탰다. 스키마가 없으니 매 세션이 자기 이름을 짓는 것이 국소 합리적이었고 그래서 109종이 됐다 — 부주의가 아니라 스키마 부재가 원인."),
  next_probes = c(
    "NP-160a 읽기 어댑터 선행(원장 무수정) — 109종에서 정본 키로의 매핑 테이블을 만들고 '이 FQ 의 측정 창은?' 질의 응답 가능 비율을 실측. 이 커버리지가 스키마 도입 EV 의 상한이다(낮으면 새 스키마를 강제해도 기존 지식은 여전히 소비 불가)",
    "NP-160b 창 메타 역추출 가능성 — source_refs/result_artifacts 가 가리키는 산출물에서 측정 창을 회수할 수 있는 비율. 큐 본문에 없어도 아티팩트에는 있을 수 있고 이것이 NP-157c 소비의 실제 관문",
    "NP-160c 도입 순서 결정 — 어댑터 없이 신규 쓰기만 강제하면 '신규는 정본 · 기존은 109종' 이원화가 고착된다. 어댑터 선행 vs 강제 선행의 분기 비용을 실측으로 결정"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식", "monitoring"),
  frontier_update = "FQ-160 원안 폐기·재정의(결과 계층 스키마 부재) · NP-160a/b/c 신규 · 스키마 전면 도입은 원장 전면 수정이라 도훈 판단 대기",
  live_trigger = "NP-160b 회수율이 높게 나오면 NP-157c 지도를 기존 기각에 즉시 결합 가능 — 그 시점에 재측정 우선순위 산출 착수",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/fq160_queue_result_schema_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/fq157c_findings.md")
)
cat("[close_fq160] RC_OK\n")
