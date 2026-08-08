# close_np_a.R — FQ-141 NP-A 라운드 계약 마감
# ★Rscript -e 에 한글을 넣으면 Windows 인코딩으로 침묵 실패한다(헌법 R Execution Pattern).
#   반드시 파일로 써서 source() 할 것.
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "FQ141_NPA_20260808_BENCH_DECOMPOSITION",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "capw-EW 격차는 벤치 수익차(연 +3.82%, 월 0.269%)이며 arm 무관 상수다.",
    "n=167 비교가능 arm 12개에서 d_alpha_ann sd=0.00106(스프레드 0.359%p), cap-w 벤치 평균 고유값 1개.",
    "항등식 active_capw - active_ew = -d 에서 ret_net 이 소거되므로 포트폴리오-측 개입으로 격차 자체는 줄일 수 없다.",
    "독립 정합: 다른 창(SS_ n=96)에서 d 2.46배일 때 |gap| 2.36배로 동반 이동.",
    "FQ-141 원안(선별-측 사이즈 중립)은 WT-006 R4 가 유니버스 재구성 7변형 전부 cap-w<1.277 로 이미 측정.",
    "살아있는 축은 비중-측 cap-tilt(R4 1.277->2.100)이나 HARD 2.95 미달."),
  next_probes = c(
    "FQ-156 비중-측 cap-tilt 를 WT-007 composite arm 에 이식해 R4 lift 재현 여부 - 재현되면 전이 벽 실제 높이 ~2.1 확정",
    "FQ-157 핸디캡 d 의 연도별/국면별 분해 - d 축소 국면 실재 시 국면-조건부 자본 자격 면이 열림",
    "FQ-158 dual_basis 산출부 해석 경계 기계 라벨 - conflation 4단 전파 재유입 차단"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "FQ-141 -> np_a_measured_bench_side_constant_20260808 · 신규 FQ-156/157/158 등재 · layer_bottleneck_map v48 정정 주석",
  live_trigger = "FQ-156 재현 시 비중-측이 유일 사이즈 레버로 확정 / d 축소 국면 발화 시 FQ-157 즉시 착수",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_a_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np_a_bench_diff.csv",
                    "04_Research/method_frontier/wt006_exog_forecast/R4_synthesis.json")
)
cat("[close_np_a] RC_OK\n")
