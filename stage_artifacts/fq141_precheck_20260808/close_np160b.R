# close_np160b.R — NP-160b 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "NP160B_20260808_WINDOW_RECOVERY_CEILING",
  verdict_type = "capability_established",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "큐 164건 중 아티팩트에서 측정 창을 역추출할 수 있는 비율 = 40/164 (24.4%, 하한 — entry 당 최대 8파일 탐침).",
    "실제 해결되는 경로를 1개 이상 보유 = 80/164 (48.8%).",
    "★결정 함의: 읽기 어댑터만으로 닿는 과거 지식이 최대 1/4 이므로 스키마 도입을 '과거 회수'로 정당화할 수 없다 — 정당화 근거는 앞으로의 라운드(신규 쓰기 강제)여야 하고, NP-160c 도입 순서도 강제 선행 쪽으로 좁혀진다.",
    "★★감사 도구 자체가 같은 축에서 2회 오답 — 1차: source_refs 원소를 무조건 경로로 보고 존재 검사(그 필드는 memory:/trigger:/parent: 등 비-경로 참조 다수) → '끊긴 참조 34.8%' 철회.",
    "2차(수리본에서 재발): 경로 판별을 '슬래시 포함 토큰' 모양 휴리스틱으로 바꿨더니 21/21 · 248/258 · R33/R37 · P1/P2/P3 · 3M/6M · 474/474 · mid/large 같은 산문 속 비율/병렬을 경로로 셌다 → '경로 토큰 87.8% / 미해결 39.0% / 경로 전무 9.1%' 철회.",
    "공통 기전 = 경로로 식별되지 않은 문자열에 존재 검사를 건 것. 이 저장소가 반복 검거해온 '존재 검사로 정체성 검사 대체' 를 감사 도구가 재현했고 1차를 고치며 2차를 새로 만들었다.",
    "24.4%/48.8% 가 살아남는 이유 = 양성으로 확립된 값이라서다. 산문 토큰은 os.path.exists 를 통과할 수 없고 통과한 파일에서 창 패턴이 매칭돼야 성공으로 계상되므로 거짓 양성이 성공을 만들 경로가 없다(거짓 음성은 가능 → 하한)."),
  next_probes = c(
    "NP-160b1 회수된 40건의 창 분포 실측 — 창 종료월/길이가 2025~2026 에 몰려 있으면 NP-157c 지도의 실효 소비가 가장 오염된 구간에 집중되므로 40건만으로도 가치가 크다. 분산돼 있으면 표본이 얇아 우선순위 산출이 불안정",
    "NP-160b2 경로 식별을 모양이 아니라 정체로 — 큐에 artifact_paths 선언 배열을 두면 이 감사가 휴리스틱 없이 성립한다. 본 라운드의 2회 오답이 그 필요의 실증",
    "NP-160b3 탐침 상한(entry 당 8파일) 완화 시 24.4% 가 얼마나 올라가는지 — 하한을 조이는 저비용 축"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "monitoring", "타모드이식"),
  frontier_update = "NP-160b 측정 완료(24.4% 하한) · NP-160c 답이 강제-선행 쪽으로 좁혀짐 · NP-160b1/b2/b3 신규 · 철회 수치 3종 명시",
  live_trigger = "artifact_paths 선언 필드 도입 시 본 감사를 휴리스틱 없이 재실행해 하한을 정확값으로 대체",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np160b_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np160b_per_entry.json",
                    "stage_artifacts/fq141_precheck_20260808/np160b_window_recovery.py")
)
cat("[close_np160b] RC_OK\n")
