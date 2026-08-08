source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "BRIEF_20260808_SESSION_DISPATCH",
  verdict_type = "capability_established",
  layer = "8_위험모델감시",
  mechanism_diagnosis = paste(
    "오늘 세션(32라운드) 결론을 텔레그램 소비면으로 전개했다 — 2,235 bytes · 차트 1장(측정 창 길이별 벤치 핸디캡) 동반.",
    "전달 핵심: ①현행 운용 북 영향 없음(PG2 baseline 269m d_ann -0.0079 = 연 0.79% 순풍, 판정 불변) ②원인은 전략 구성이 아니라 벤치마크에 담긴 메가캡 급등(2025+ 삼성 51%+하이닉스 44%) ③기존 기각들은 장기 창에서 순풍을 받았으므로 유효 ④현재 ELEVATED 로 재도전 시점 아님.",
    "한계도 함께 전달: d 수준 유의성 미확립(t 0.87~1.82) · 국면 조건부 저검정력(연 27.7% 필요) · 감시 미배선 · 오늘 판정 16회 정정(다수가 직전 산출).",
    "★소비면 관점의 미완: 텔레그램은 소비면 7종 중 **하나**다. 오늘 아크 결론이 팩터랭킹·선별라벨·위험모델·타모드이식 면에 실제로 도달했는지는 **미확인**이다. L-code 5건 적립은 했으나 적립은 소비가 아니다(오늘 반복 확인한 계통).",
    "★보고 재현성 미확보: 브리핑이 주장한 수치는 감시가 미배선인 동안 다음 보고 시점에 자동 재산출되지 않는다. 같은 주장을 다시 하려면 수동 재계산이 필요하고, 그 사이 값이 바뀌어도 드러나지 않는다."),
  next_probes = c(
    "NP-보고a 보고 재현성 배관 — 브리핑이 인용한 수치(PG2 창 d_ann · 최근 12m/269m 핸디캡 · 현재 백분위)를 감시 산출물에서 직접 읽어오게 하면 다음 보고가 자동으로 최신값을 쓴다. 현재는 수동 재계산이라 값이 바뀌어도 조용하다. 칩 task_b32282e2 와 같은 배관",
    "NP-보고b 시각화 선택의 효용 검정 — 차트 1장(창 길이별 핸디캡)만 보냈으나 시대 분해(pre-2017 부호 반전, 5년 블록)가 더 결정적일 수 있다. 어느 시각화가 실제로 판단을 바꾸는지는 미측정이며, 오늘 세운 '배선 전 효용 검정' 원칙의 적용면",
    "NP-보고c 나머지 소비면 도달 확인 — 아크 결론이 팩터랭킹·선별라벨·위험모델·타모드이식에 닿았는지 순회. L-code 적립·지도 갱신은 했으나 그것을 소비로 읽는 것이 오늘 반복 검거한 오류다. 각 면에서 '이 결론이 무엇을 바꾸는가'를 1줄씩 확인"),
  consumer_surfaces = c("monitoring", "팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "세션 결론 텔레그램 전개 완료 · 나머지 소비면 6종 도달 미확인 · 보고 재현성 미배관 · NP-보고a/b/c 신규",
  live_trigger = "감시가 배선되면 브리핑 수치가 자동 최신화되어 보고 재현성 문제가 해소된다 — 그 전까지 재보고 시 수동 재산출 필수",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/send_session_brief.R",
                    "stage_artifacts/fq141_precheck_20260808/session_20260808_handicap_term_structure.png",
                    "qepm/observability/bench_handicap_watch_latest.json")
)
cat("[close_brief_dispatch] RC_OK\n")
