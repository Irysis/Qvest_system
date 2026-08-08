source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099D1AB_20260808_MECHANISM_TRIAGE_AND_DEDUP_SYMMETRY",
  verdict_type = "incumbent_confirmed",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★두 질문을 함께 닫았다 — ①dedup 원장이 비대칭인가(내 의심) ②미탐색 코호트에 기전이 있는가.",
    "①**내 의심은 기각된다**: dedup 텍스트에서 파트너로 지목된 코드 128종 중 자기 항목에 dedup 기재가 없는 것은 **2종뿐**(V07_EV_EBITDA·V14_EBIT_EV)이고, 그 둘은 V13_EV_Sales 가 '영향 의심 범위(미확정)' 로 적은 것이라 **확정 중복이 아니다 = 정상 기록**이다. 원장은 126/128 대칭이며 결함이 아니다. 다만 실제 누락 1건 발견 — V08_PSR 이 자신을 canonical, V20_SP 를 redundant 로 지목했는데 V20 쪽 기재가 없다. ⇒ **깨끗한 미탐색 26 → 25건 정정**.",
    "②**기전 분류(FQ-099d1a)가 이 코호트의 성격을 확정한다**: 25건 중 문헌 인용이 있는 것은 **2건뿐**(AC14_Discretionary_Accruals — Jones 모형 재량적 발생액 · C14_Revenue_Surprise — Jegadeesh-Livnat 2006). V20_SP(Barbee et al. 1996)는 중복으로 제외됐다. 나머지 22건은 설명 문장은 있으나 인용 없음, 1건은 공식만(GR04_GPA_Growth).",
    "★이것이 FQ-099d 의 '미탐색 재고' 프레이밍을 다시 한 번 눌러야 함을 뜻한다: 이 코호트는 **가설에서 나온 재료가 아니라 라이브러리 확장의 산물**(2026-03-24 일괄 등재·인용 2/25)이다. 수리 후 25건 전수 스크리닝은 **Factor Zoo 확장**이며 research_philosophy ①(Factor Zoo 축소) 위반이다.",
    "★따라서 수리의 정당화는 '25건을 평가하기 위해' 가 **아니다**. 정당화는 두 가지로 좁혀진다: ⓐ현행 51 팩터가 비-TTM 기준이라는 **correctness** 자체 ⓑFQ-099d2 의 재심 대상(기각 9건+, 특히 구조 사유로 떨어진 Q10_Gross_Margin). 미탐색 25건은 **기전 있는 2건만** 대기열에 올린다.",
    "★방법 기록: 중복 판정을 '자기 항목의 dedup 필드' 단일 축으로 하면 V20_SP 를 놓쳤다. **'남이 나를 지목했는가' 라는 역방향 축**이 잡았다. 원장 기반 판정은 양방향으로 물어야 한다(오늘 '검사기는 양방향으로 재라' 의 원장 버전)."),
  next_probes = c(
    "FQ-099d1a-1 — 기전 있는 2건(AC14_Discretionary_Accruals·C14_Revenue_Surprise)만 수리 후 평가 대기열 등재. AC14 는 Sloan 발생액 계열이라 기존 accrual 재고와 중복 확인 선행, C14 는 컨센서스 계열이라 생산 북의 C01_SUE·C04_ESBR 과의 상관 확인 선행(북이 이미 쓰는 채널이면 신규성 없음).",
    "FQ-099d1a-2 — 인용 없는 22건은 **개별 평가 금지**. 대신 교정 패널 위에서 한 번의 상관/중복 스크린으로 기존 팩터와의 신규성만 보고, 신규성 없는 것은 카탈로그에서 정리 제안(라이브러리 축소가 research_philosophy ① 정합).",
    "V20_SP dedup 기재 누락 1건 — 레지스터리 수리 항목. 칩 task_4811b0a6 작업 시 함께 처리 가능(같은 파일)."),
  consumer_surfaces = c("팩터랭킹", "선별라벨"),
  frontier_update = "FQ-099d1a/b 확정: dedup 비대칭 의심 기각(126/128 대칭) · 깨끗한 미탐색 26→**25** · 기전 인용 **2/25** ⇒ 수리 정당화를 'correctness + 재심 9건'으로 좁힘(미탐색 전수평가 아님) · Factor Zoo 확장 방지 · V20_SP 기재 누락 신규",
  live_trigger = "수리 완료 시 기전 있는 2건 + FQ-099d2 재심 대상만 착수. 인용 없는 22건은 신규성 스크린 1회로 갈음",
  evidence_refs = c("stage_artifacts/fq099/fq099d1a.R",
                    "stage_artifacts/fq099/fq099d1b_sym.R",
                    "stage_artifacts/fq099/fq099d1a_mechanism.csv",
                    "stage_artifacts/fq099/fq099d1_clean_final.txt")
)
cat("[close_fq099d1b] RC_OK\n")
