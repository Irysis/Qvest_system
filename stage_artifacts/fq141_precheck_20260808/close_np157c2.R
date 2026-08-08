# close_np157c2.R — NP-157c2 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "NP157C2_20260808_D_TICKER_ATTRIBUTION",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "2025+ 18개월의 전이 벽 핸디캡(d_ann +48.95%)은 두 종목이 만든다 — A005930 삼성전자 share 51.1%(평균 cap 비중 19.87%) + A000660 SK하이닉스 43.9%(12.26%), 상위 2 합 95.0% / 상위 3 98.8%.",
    "양수기여 HHI 0.2382 = 유효 종목수 4.2. 기여 종목 410 중 양수 198.",
    "상위 k 제거 시 d_ann: k=0 +0.4895 / k=1 +0.2392 / k=2 +0.0242(사실상 소멸) / k=3 +0.0056 / k=5 -0.0146 / k=10 -0.0495.",
    "⇒ 오늘 NP-A → FQ-157 → NP-157c 로 좁혀온 전이 벽은 최근 구간 점추정 기준으로 HBM/AI 메모리 사이클을 탄 반도체 메가캡 2종목이다. cap-w 벤치는 합산 ~32% 비중으로 담고 top-25 EW 는 구조적으로 못 담는다.",
    "레짐이 아니라 사건에 가깝다(유효 4.2). 단 KR 메가캡 집중 자체는 구조적이므로 '소수 메가캡이 cap-w 벤치를 지배할 수 있다'는 기전은 재현 가능하고 2025+ 의 크기가 에피소드다.",
    "★하지 않는 주장: 제약 완화(weight bound/25종목/cap-w 벤치는 고정 축, AX-000 따름정리·INV-7) · 기각 알파가 실은 통과했을 것 · 벤치 변경(재측정 창 선택 문제)."),
  next_probes = c(
    "NP-157c2a 기전의 역사적 재현성 — 과거 18개월 롤링 창마다 상위-2 share 분포를 산출. 분포가 두터우면 상시 기전이고 2025+ 만 극단이면 진짜 에피소드다. 재측정 타이밍 판단의 직접 근거",
    "NP-157c2b 제약-안 최대 추종 가능분 실측 — [0,0.20]·25종목 안에서 삼성+하이닉스를 담을 때 달성 가능한 최대 벤치 추종도. 완화가 아니라 고정 축 안에서 얼마나 좁힐 수 있는가의 측정",
    "NP-157c2c 반대 방향 점검 — 상위 2 제거 후 잔여에서 d 가 음수(k=5 -0.0146)라는 것은 나머지 시장에서 EW 가 cap-w 를 이긴다는 뜻. 잔여 구조가 안정적이면 소형·중형 tier 에서는 전이 벽이 반대 방향일 수 있다(미탐색 면)"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "NP-157c2 측정 완료 — 전이 벽 최근 구간의 정체 = 삼성전자+SK하이닉스 95% · NP-157c2a/b/c 신규",
  live_trigger = "NP-157c2a 에서 상위-2 지배가 과거에도 흔했던 것으로 나오면 2025+ 를 에피소드로 보는 현 판단을 철회하고 상시 기전으로 재분류",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np157c2_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np157c2_ticker_attribution.csv",
                    "stage_artifacts/fq141_precheck_20260808/fq157c_findings.md")
)
cat("[close_np157c2] RC_OK\n")
