# close_fq157.R — FQ-157 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "FQ157_20260808_D_ERA_STRUCTURE",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "전이 벽 핸디캡 d(cap-w 유니버스 벤치 − EW 유니버스 벤치)는 구조적 상수가 아니라 시대 의존이며 pre-2017 에는 부호가 반대였다.",
    "실측 167개월: pre2017(n=53) d_ann -0.0689 / post2017(n=114) +0.0802, 월 차 0.01243 t=2.253 p=0.0256.",
    "2012~2015 는 매년 음수(-7.5%~-18.7%) = 같은 top-25 EW 포트가 그 시기엔 더 쉬운 벤치를 만났다.",
    "핸디캡은 post-2017 현상이고 2025(+24.5%)~2026 상반기(+98% 연율)에 극단 집중된다.",
    "함의: cap-w PORT_t 기각 판정 중 최근 창 비중이 큰 것은 시대 성분을 포함한다. 알파가 있다는 뜻이 아니라 벽 높이가 시변이며 현재 극단값이라는 뜻.",
    "정합: POOL_EW 월 평균 d 0.27425% 는 NP-A 표와 정확 일치(연 환산차 3.89 vs 3.29 는 기하/산술 규약 차이).",
    "한계: 2026 은 n=6 로 노이지 · regime_daily_v2 에 이산 국면 라벨 컬럼 부재로 국면별 분해 미실행 · d 수준 자체는 전기간 NW t~0.78 로 0 과 유의 구분 안 됨(확정된 건 시대 간 차이)."),
  next_probes = c(
    "NP-157a 이산 국면 라벨 패널(msm_daily_latest/macro_regime)로 국면별 d 분해 — 단 FQ-119 라벨 자격 관문(recall>base 그리고 fisher p<0.05) 통과분만 소비(무판별 라벨 소비는 유해 실증됨)",
    "NP-157b FQ-156 통합 — cap-tilt 우위와 d 가 같은 시대 축에서 움직이는지 직접 대조. 예측: 같은 현상이면 pre-2017 에서 cap-tilt 우위가 사라져야 한다. ★그런데 R4 는 pre-2020 t=1.95 vs 2020+ t=0.99 로 반대 방향 = 현 시점 이 예측은 반증 우세이며, 재현되면 cap-tilt 에 벤치 허깅 외 잔여 성분이 있다는 뜻",
    "NP-157c 최근 창 노출 지도 — 어떤 cap-w 기각들이 2025~2026 에 얼마나 노출됐는지 계량해 시대 성분이 큰 순으로 재측정 후보 우선순위화"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "monitoring"),
  frontier_update = "FQ-157 측정 완료 · FQ-156 은 precheck_reframed(paired 1.224 비유의)로 재정의 · NP-157a/b/c 후속",
  live_trigger = "d 가 pre-2017 수준으로 축소되는 시대/국면이 관측되면 그 조건에서 기각된 cap-w 후보 재측정이 정당해짐(벤치 변경 아니라 재측정 시점 선택)",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/fq157_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/fq157_d_by_year.csv",
                    "stage_artifacts/fq141_precheck_20260808/np_a_findings.md")
)
cat("[close_fq157] RC_OK\n")
