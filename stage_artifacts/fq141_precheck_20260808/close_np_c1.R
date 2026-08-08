source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC1_20260808_PG2_WINDOW_HANDICAP_LABEL",
  verdict_type = "capability_established",
  layer = "9_자본운영",
  mechanism_diagnosis = paste(
    "PG2 admit baseline 의 정확 창(269m, 2004-02~2026-06, n=269 확인)에서 벤치 핸디캡 d_ann = -0.0079 = 연 0.79% 순풍.",
    "즉 PG2 의 측정된 cap-w active 는 EW-유니버스 basis 대비 연 0.79% 높게 보인다. PORT_t 6.21 / CAGR 45.26% 에 비해 미미하므로 admit 판정을 뒤집지 않는다 — 라벨이지 보정이 아니다.",
    "대조: live series 271m -0.0142 / 296m -0.0182 / 최근 19m +0.3743 / 최근 36m +0.2027 / 2010~2014 순풍기 -0.1116.",
    "★부수 발견(중요): 256m S3(2005-02~2026-05) = +0.0060 인데 269m(2004-02~2026-06) = -0.0079 로 부호가 다르다. 시작월 13개월 차이가 핸디캡의 부호를 뒤집는다.",
    "⇒ 핸디캡은 창 길이만이 아니라 '어느 달이 포함되는가'에 민감하다. NP-c3 가 제기한 단일-draw 취약성이 실측으로 확인됐고, 조회표를 중앙값 단일값으로 소비하는 것은 위험하다.",
    "본 라운드가 확립한 것: 현행 book 의 측정 조건을 수치로 표기할 수 있게 됐고 그 값이 작다는 것. 확립하지 않은 것: 이 값으로 성과를 보정하는 규약(사전등록 필요, INV-7)."),
  next_probes = c(
    "NP-c3 승격(최우선) — 조회표 각 셀에 사분위 병기. 256m/269m 부호 반전이 실측됐으므로 중앙값 단일값 소비는 위험하다. 라벨을 붙이려면 그 라벨의 분산을 함께 표기해야 한다",
    "NP-c2 부호 반전 지점 정밀화 — 길이 축(167m~269m)뿐 아니라 시작월 축에서도 반전이 일어남이 확인됐다. '중립 창'을 길이 하나로 정의할 수 없으므로 (시작월, 길이) 2차원에서 d=0 등고선을 그려야 한다",
    "NP-c4 신규 — book 성과 서술에 측정 조건 라벨을 실제 부착할지 여부. 값이 0.79%/yr 로 작으므로 부착 EV 가 낮을 수 있다. 부착 전에 '이 라벨이 독자의 판단을 바꾸는가'를 물어야 한다(오늘 세션이 반복 확인한 배선 전 효용 검정)"),
  consumer_surfaces = c("monitoring", "선별라벨", "위험모델"),
  frontier_update = "PG2 baseline 핸디캡 라벨 산출(-0.79%/yr, admit 무영향) · 창 시작월 민감성 실측(256m vs 269m 부호 반전) · NP-c3 최우선 승격",
  live_trigger = "신규 measurement 의 창이 최근 24m 이내로 짧으면 d_ann 이 +0.2~+0.37 대이므로 라벨 부착 필수 — PG2 급 장기 창은 라벨 EV 낮음",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_c1_pg2_window.R",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1c_handicap_lookup.csv",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1c_findings.md")
)
cat("[close_np_c1] RC_OK\n")
