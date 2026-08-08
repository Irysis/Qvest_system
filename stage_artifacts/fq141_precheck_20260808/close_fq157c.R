# close_fq157c.R — NP-157c 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "FQ157C_20260808_WINDOW_EXPOSURE",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "전이 벽 핸디캡 d 는 측정 창 길이에 단조 의존한다(2026-06 종료 기준 12m +0.6953 / 36m +0.2371 / 60m +0.1477 / 167m +0.0329).",
    "★2025+ 18개월을 제외하면 149개월(2012-08~2024-12) d_ann = -0.0223 로 부호가 뒤집힌다 — cap-w 벤치가 EW 유니버스를 이기지 못했다.",
    "2025+ 단독 d_ann +0.4898, 전기간 평균에 대한 기여 149.6%(나머지가 음수라 100% 초과). 검산 (149*-0.0223 + 18*0.4898)/167 = 0.0329 일치.",
    "즉 갈림은 2017 이 아니라 2025 이며, 전기간 +3.29% 는 최근 18개월이 단독 생성한 점추정이다.",
    "★★단 어떤 창에서도 유의하지 않다(단순 t 0.87~1.82, p 전부 >0.07) — 본 라운드의 진술은 점추정 구성과 측정 오염이지 확립된 효과가 아니다.",
    "주장하지 않는 것: 기각 알파가 실은 통과했을 것이라는 추론(포트는 자기 알파 필요), 핸디캡 실재(유의 미달), 벤치 변경(고정 축 INV-7 금지 — 이건 재측정 창 선택 문제)."),
  next_probes = c(
    "NP-157c1 기각 목록에 창 메타데이터 부착 — 현행 큐 wall_check 는 PORT_t 는 적지만 측정 창(개월수/종료월)을 일관되게 적지 않아 이 지도를 기각 건에 결합할 수 없다. wall_check 스키마에 window_months/window_end 요구가 선행 과제",
    "NP-157c2 2025+ 18개월의 정체 규명 — mega-cap 집중이 어떤 종목/섹터에서 왔는지. 재현 가능한 레짐인지 단발 사건인지가 재측정 타이밍을 좌우",
    "NP-157c3 NW 보정 t 로 유의성 재산출 — 현재는 단순 t. 월간 자기상관이 있으면 t 는 더 낮아져 '유의하지 않다'는 결론이 강화될 뿐 뒤집히지 않는다(방향 예측 명시)"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "monitoring"),
  frontier_update = "NP-157c 측정 완료 · NP-157c1/c2/c3 신규 · FQ-157 의 pre/post2017 분할보다 국소적(갈림은 2025)",
  live_trigger = "d 가 pre-2025 수준(0 또는 음수)으로 복귀하는 구간이 관측되면 2025~2026 창 수집 기각의 재측정이 정당해짐 — 단 재측정 창을 먼저 사전등록할 것(창-선택 자유도가 새 다중검정 문제가 됨)",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/fq157c_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/fq157c_window_exposure.csv",
                    "stage_artifacts/fq141_precheck_20260808/fq157_findings.md")
)
cat("[close_fq157c] RC_OK\n")
