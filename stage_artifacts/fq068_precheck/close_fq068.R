source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ068_20260808_SEMI_PPI_R1R2",
  verdict_type = "config_scoped_negative",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "신규 비-return 재료(미국 반도체 PPI, FRED PCU334413334413) 2개 설계로 실측. hypothesis_index 0건 = 완전 미탐색 축이었다.",
    "★데이터/PIT 전제 확보: 시리즈 318개월(2000-01~2026-06) 인출 · ALFRED vintage 로 발표지연 실측 **중앙 43일(범위 40~105)** ⇒ 홀딩월 시작 시 확보 가능한 최신 참조월 = **M-2** 로 보수 고정.",
    "★유니버스 표현 가능성 선확인: K200∪KQ150 반도체 42종 중 **39종이 non-MEGA**(한미반도체·이수페타시스·주성엔지니어링·리노공업·원익IPS·이오테크닉스·DB하이텍·솔브레인 등) — top-25 EW 로 표현 가능한 횡단면 실재. 구성은 메모리 제조사가 아니라 **장비·소재**이므로 기전은 'ASP↑ → 제조사 capex↑ → 장비·소재 수주↑'.",
    "R1 섹터 타이밍(PPI 모멘텀 부호별 반도체 섹터 초과수익): 방향 3신호 모두 양수 일관(mom3 +3.93%/yr · mom6 +9.07% · mom12 +5.47%, non-MEGA mom6 +9.73%)이나 t 0.32~0.86.",
    "★R1 판정 = **INCONCLUSIVE_UNDERPOWERED**. 섹터 초과 계열 월 sd 0.0681 로 이진 ON/OFF 분할의 필요 효과가 **연 +29.73%**(mom6, 유효n 47.2)다. 관측 +9.07% 를 t=2.0 으로 확립하려면 유효n ~500 = **총 3,250개월(271년)** — 이 설계는 원리적으로 검출 불가.",
    "⇒ 설계 전환: 섹터 타이밍이 아니라 **횡단면 PPI-베타 팩터**(과거 36개월 rolling 회귀로 종목별 PPI 민감도 추정 → PPI 모멘텀 부호와 결합 → 횡단면 랭킹).",
    "R2 실측(275개월 · 64,672 종목-월): rank IC **-0.0112** · t_NW **-0.91** · ICIR -0.057 · IC>0 44.4%. 베타 단독도 IC -0.0046 (t_NW -0.36).",
    "★R2 판정 = **NEGATIVE_POWERED**(무검정력 아님). 이 설계는 IC 0.03 이면 기대 t 2.55, **IC 0.04 면 기대 t 3.40** 으로 검출 가능하다(t=2.0 필요 IC 0.0236). 관심 효과크기에서 검정력이 충분한데 관측은 부호마저 반대 ⇒ '나왔어야 하는데 안 나온' 진짜 음성.",
    "★오늘 세운 INCONCLUSIVE/NEGATIVE 구별 규약이 두 라운드를 정확히 갈랐다 — 같은 재료인데 설계에 따라 판정 성격이 다르다."),
  next_probes = c(
    "FQ-068a 하위섹터 분해 — 반도체 39종은 장비/소재/설계/후공정이 섞여 있다. PPI 기전(capex 파급)은 장비에만 걸릴 수 있으므로 Sector_Lv2 세분 또는 이름 기반 분류로 하위군별 IC 를 본다. 전체 IC 가 음수여도 하위군에서 갈릴 수 있고, 이는 sweep 이 아니라 기전이 지정하는 단일 분할이다",
    "FQ-068b 신호 형태 교체 — 현 신호는 'PPI 민감도 x 모멘텀 부호'다. 대안: PPI 수준의 추세 이탈(장기평균 대비 z), 또는 PPI 와 KR 반도체 수출물가/재고의 스프레드. R2 는 민감도-형태 하나를 기각한 것이지 재료 전체를 기각한 것이 아니다",
    "FQ-068c 소비면 전환 — 횡단면 랭킹에서 음성이면 오늘 반복 확인된 패턴상 **필터/제외 면**이 남는다. 'PPI 하락 국면에서 고민감도 종목 제외' 형태의 exclusion 이 랭킹과 다른 결과를 낼 수 있다(랭킹 死 → 필터 生 전례 실증됨)"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "오버레이", "타모드이식"),
  frontier_update = "FQ-068 R1(섹터타이밍)=검정력 부족·설계 불가 / R2(횡단면 PPI베타)=검정력 충분한 음성 · PPI 데이터+PIT 규약(M-2) 확보 · 반도체 non-MEGA 39종 표현 가능 확인 · FQ-068a/b/c 신규",
  live_trigger = "FQ-068a 하위섹터 분해에서 장비군 IC 가 양수로 갈리면 재료가 되살아난다 — 그 경우에도 자본 게이트는 별도",
  evidence_refs = c("stage_artifacts/fq068_precheck/np_fq068_r1.R",
                    "stage_artifacts/fq068_precheck/np_fq068_r2.R",
                    "stage_artifacts/fq068_precheck/np_fq068_r2power.R",
                    "stage_artifacts/fq068_precheck/fq068_ppi_raw.parquet")
)
cat("[close_fq068] RC_OK\n")
