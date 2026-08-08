# close_fq156.R — FQ-156 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "FQ156_20260808_CAPTILT_PAIRED_CEILING",
  verdict_type = "config_scoped_negative",
  layer = "5_비중",
  mechanism_diagnosis = paste(
    "cap-tilt 계열의 증분 t 는 전 변형 천장 1.307 · 배포가능(제약 [0,0.20] 준수) 천장 1.258 로 문턱 2.0 에 미달한다.",
    "★shrink 다이얼은 증분에 대해 항등이다: mk_shrink 가 같은 25종목 위 EW 와 cap-비례의 볼록결합이고 baseline(ew_parity)이 그 EW 이므로,",
    "a_lambda - a_mom = (1-lambda)*(a_capprop - a_mom) 즉 양의 스칼라 배이고 t 는 스칼라에 불변이다.",
    "실측이 예측과 일치 — lambda 0/.25/.50/.75 에서 paired t 가 소수 3자리까지 1.307 동일(버그 아니라 항등의 지문). 캡만 비선형이라 capped 변형이 갈리고 전부 천장 아래.",
    "★선택 기준 결함: run_R4_bench_aware_weight.R:105 가 which.max(port_t) 로 최선을 고른다. standalone port_t 는 다이얼에 크게 반응하는데(2.474->1.662) 증분과 무관하다.",
    "paired 기준 배포가능 최선은 size_prop_cap(1.224)이 아니라 tilt_k0p5_cap(1.258).",
    "계통은 FQ-141/NP-A 와 동형 — 헤드라인 수치가 개선 여부에 정보 없는 축(벤치/다이얼)에 반응한다.",
    "덧붙여 2.100 이어도 oos_ret 0.374 · calmar 0.576 으로 HARD 2종이 PORT_t 와 독립 FAIL ⇒ 이 lane 은 자본 후보가 아니라 벽-높이 측정치."),
  next_probes = c(
    "NP-156a 선택 기준 한정 수리 — 스윕에 baseline 을 끝점으로 하는 혼합(shrink/blend) 계열이 포함된 경우에만 which.max(port_t) 가 다이얼을 고른다. which.max(port_t) 자체는 20+ 지점에 흔하고 대개 정상이므로 일괄 교체가 아니라 혼합-계열 포함 스윕만 식별해 paired 기준으로 교정",
    "NP-156b 증분 천장의 일반성 — 1.307 이 momentum 재료 고유인지 WT-007 composite 등 타 재료에서도 유사 천장인지 확인. standalone 아닌 paired 로만 채점. 재료 무관 천장이면 비중-측 사이즈 레버가 config-scoped 로 정리된다",
    "NP-157b 이월(미완) — R4 산출물에 시대 분할이 저장돼 있지 않아(results.csv/summary.json 모두 era 컬럼 부재) cap-tilt 우위와 d 의 시대 동조를 측정하지 못했다. weights parquet 은 best 변형 1개만 저장되고 momentum baseline active 계열 미저장이라 R4 파이프라인 재실행 필요. ★현 예측은 반증 우세(R4 서술이 pre-2020 우위가 더 큼 = 벤치허깅 가설과 반대)"),
  consumer_surfaces = c("비중방법", "팩터랭킹", "위험모델"),
  frontier_update = "FQ-156 = config-scoped negative(paired 천장 1.307/배포가능 1.258) · NP-156a/b 신규 · NP-157b 이월 미완 명시",
  live_trigger = "paired 기준 2.0 에 닿는 (재료, 가중) 조합이 하나라도 나오면 cap-tilt lane 재개 — 단 oos_ret 0.7 · calmar 0.64 는 별도 관문",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/fq156_paired_ceiling_findings.md",
                    "04_Research/method_frontier/wt006_exog_forecast/R4_bench_aware_weight_results.csv",
                    "04_Research/method_frontier/wt006_exog_forecast/run_R4_bench_aware_weight.R")
)
cat("[close_fq156] RC_OK\n")
