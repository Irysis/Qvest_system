setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "INSTR_20260808_POWER_LABEL_AND_RUNNER_PATH",
  verdict_type = "capability_established",
  layer = "⑧위험모델/감시",
  mechanism_diagnosis = paste(
    "★적대검증이 도구 결함 2건을 냈고 둘 다 수리·검증했다. 리서치 판정이 아니라 계측 신뢰 복구다.",
    "① verdict_with_power 항진명제: required = t_threshold × sd/√n × 1.25 인데 호출자가 **arm 자신의 계열 sd** 를 넣으면 required = 2.5 × se_arm 이 되어 NEGATIVE_POWERED 가 '|t|≥2.5 ∧ |t|<2.0' 을 요구 = 논리적 도달 불가. ⇒ |t|<2 인 모든 셀이 기계적으로 INCONCLUSIVE_UNDERPOWERED 로 찍히고 라벨이 '|t|<문턱' 이상의 정보를 담지 않는다. WT-D20260808_001 P1/P2 12셀 전건이 이 상태였다.",
    "수리 = 관측 t·효과에서 se_arm 을 역산해 implied_t_threshold(= required/se_arm) 를 **항상 반환**한다. 문턱×팽창 근방이면 INCONCLUSIVE_BAR_RESTATES_T 를 발행해 함수가 스스로 '이 라벨은 정보 없음' 을 선언한다. ★바가 무엇을 재는지를 한 수치로 만들면 오용이 자기 신고된다 — 주석이 아니라 반환값으로.",
    "② 배터리 러너 경로 실패: run_contract_regression.R:26 구판이 commandArgs 의 --file= 로만 자기 위치를 잡는데, 이 저장소 헌법(R Execution Pattern)은 한글 경로 회피를 위해 Rscript -e 'source(...)' 를 강제하고 그 경로엔 --file= 이 없다 → grep character(0) → [1] NA → 자식 5개 전부 exit=5.",
    "★실패 모양이 함정: 'CRASHED: 5 / RESULT: FAIL' 로 보고돼 **계약이 깨진 것처럼 읽힌다**. 나도 처음엔 내 변경을 의심했고 '내가 안 건드린 4개도 크래시' 를 보고서야 러너를 의심했다. ⇒ 수리 오류문에 '이것은 계약 실패가 아니라 러너 경로 실패' 를 명시했다.",
    "실 소비자는 suite_totals_watch.sh:57 하나이며 --file 형태로 부르므로 **무음 프로덕션 실패는 없었다** — 죽어 있던 건 대화형/source() 경로다.",
    "검증: 케이스 67→74(위반 주입 3 = WT-001 실구성 n=295·sd 0.02560·t 1.2 픽스처화, 음성 대조 4 = 기존 3분기 보존). 호출 3경로(source / --file / 타 cwd+env) 전부 74/74 PASS."),
  next_probes = c(
    "INSTR-P1 소비자 감사 — required_effect/verdict_with_power 를 호출하는 지점을 전수 조회해 각 호출부가 sd_monthly 에 무엇을 넣는지(arm 자신 vs 외부 기준) 확인한다. WT-001 이 유일한 오용인지, 계통인지 갈린다. 오용이 여럿이면 sd 출처를 선언 필드로 강제하는 2차 수리가 필요하다.",
    "INSTR-P2 러너 자기위치 계통 점검 — 같은 --file= 가정을 쓰는 다른 러너(08_Tests/hooks/run_all_hooks.sh · 08_Tests/regime/run_all.R · ops 스크립트)가 있는지 확인. 헌법이 source() 를 강제하는데 --file= 를 전제하는 코드는 전부 같은 방식으로 죽는다.",
    "INSTR-P3 실패 모양 라벨 규약 — '도구 실패' 와 '대상 실패' 를 출력에서 구별하는 규약을 세울지 판단. 이번 건은 배터리가 'RESULT: FAIL' 로 대상 실패를 참칭했다. suite_totals_watch 가 이미 '수치 없음은 정상이 아니다' 가드를 갖고 있으므로 그 패턴의 확장 여부를 본다."),
  consumer_surfaces = c("위험모델감시", "선별라벨", "타모드이식"),
  frontier_update = "required_effect_size.R 진단 3필드 신설(se_arm·implied_t_threshold·negative_powered_reachable) + INCONCLUSIVE_BAR_RESTATES_T 판정 추가 · run_contract_regression.R 자기위치 resolver 4단(--file→CLAUDE_PROJECT_DIR→QM_ROOT→cwd, 실패 시 크게 실패) · 배터리 67→74 · INSTR-P1/P2/P3 신규",
  live_trigger = paste(
    "재개 조건: ① INSTR-P1 감사에서 sd_monthly 오용 호출부가 2건 이상 발견되면 즉시 2차 수리 착수(sd 출처를 선언 필드로 강제).",
    "② WT-D20260808_003 또는 후속 라운드가 검정력 판정을 낼 때 implied_t_threshold 가 문턱 근방으로 찍히면, 그 라운드의 '저검정력' 서술을 재작성한다(구 라벨로 이미 보고된 판정은 소급 재검토 대상).",
    "③ 다른 러너에서 같은 exit=5 전건 크래시가 관측되면 INSTR-P2 를 즉시 승격한다.",
    "★본 수리는 도구 신뢰 복구이지 리서치 판정이 아니다 — 어떤 알파 주장도 이 라운드에서 만들어지지 않았다."),
  evidence_refs = c("02_Infrastructure/contracts/required_effect_size.R",
                    "08_Tests/contract_regression/test_required_effect_size.R",
                    "08_Tests/contract_regression/run_contract_regression.R",
                    "stage_artifacts/wt001_verify/",
                    "memory:project-power-label-tautology-and-runner-path-20260808")
)
cat("[close_instr] RC_OK\n")
