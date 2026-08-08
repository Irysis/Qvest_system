# close_np157c2a1c.R — NP-157c2a1c 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "NP157C2A1C_20260808_TAILWIND_ERA_AND_LOOKUP",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "순풍기와 역풍기는 대칭이 아니다 — 순풍기(2010~2014, d_ann -0.1116) 최대 음수기여 상위-2 는 A005490/A014470 이고 역풍기(2025~2026, +0.3743) 최대 양수기여 상위-2 는 A005930/A000660, 교집합 없음.",
    "같은 두 종목이 부호를 바꾼 것이 아니라 그때그때 이기는 메가캡이 다르다(순풍기에도 A005930 은 +0.0935 로 역풍 쪽 기여였고 POSCO 계열 음수기여에 압도됨). 기전은 종목 고유가 아니라 '메가캡 승자 집중' — NP-157c2a 의 상시 기전 재분류와 정합.",
    "★창별 핸디캡 조회표 산출(종료연도 x 창길이 -> d_ann 중앙값, 창 12/24/36/60/120/167/220/269).",
    "★★269개월 창은 종료연도 무관 전부 음수다(2012 -0.0216 ~ 2022 -0.0446, 2026 -0.0148). 이 저장소 표준 장기 창(PG2 baseline = 269m clean)에서는 cap-w 벤치가 오히려 약간 유리했다. 부호는 대략 167m~269m 사이에서 뒤집힌다(167m ending 2026 ~ +0.033).",
    "★★★따라서 '우리 기각들이 벤치 탓에 억울했다'는 읽기는 틀렸다 — 표준 장기 창 측정은 순풍을 받았으므로 그 기각들은 유효하며 보이는 것보다 강한 판정이다. 역풍은 짧고 최근인 창에 한정된다(36m ending 2026 = +0.2027).",
    "이것이 오늘 아크(NP-A -> FQ-157 -> NP-157c -> c2 -> c2a -> c2a1) 전체에 대한 경계 설정이다. 아크가 확립한 것은 '벽의 벤치-측 성분이 창 의존적'이라는 사실이지 '기각이 부당했다'가 아니다.",
    "한계: 조회표는 각 셀의 중앙값이라 같은 해 종료 창들의 분산이 없다 · d 수준 유의성 미확립 · 기각 항목 측정 창 식별 불가라 큐 자동 결합은 아직 불가(수동 적용만)."),
  next_probes = c(
    "NP-c1 PG2 baseline(269m clean)과 현행 book 측정 창에 조회표를 실제 적용해 순풍 크기를 명시 — 창을 아는 측정이라 즉시 가능하며 book 성과 서술에 측정 조건 라벨을 붙이는 첫 사례가 된다",
    "NP-c2 부호 반전 지점 정밀화 — 167m~269m 사이 어느 길이에서 d 가 0 을 지나는지. 그 길이가 역풍/순풍 중립 창이며 신규 측정의 창 길이 사전등록 기준으로 쓸 수 있다",
    "NP-c3 조회표 분산 병기 — 각 셀에 중앙값뿐 아니라 사분위를 넣어 라벨이 단일 draw 에 취약하지 않은지 확인(문턱 단일값 취약성 기록과 정합)"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "monitoring"),
  frontier_update = "창별 핸디캡 조회표 산출 · 표준 장기 창(269m)은 순풍 확정 = 아크의 경계 설정 · 순풍/역풍 비대칭(종목 고유성 기각) · NP-c1/c2/c3 신규",
  live_trigger = "NP-c1 이 PG2 baseline 의 순풍 크기를 내면 book 성과 서술에 측정 조건 라벨 부착 착수",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np157c2a1c_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1c_handicap_lookup.csv",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1_findings.md")
)
cat("[close_np157c2a1c] RC_OK\n")
