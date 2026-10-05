# Qvest 헌법 변경 이력 (CLAUDE.md에서 분리, 2026-06-10 P2 다이어트)

> CLAUDE.md는 "현재 유효한 헌법"만 담는다. 버전 연혁·릴리스 상세는 본 파일이 SOT.
> 최신 릴리스 상세: `qvest_v8_4_asymmetry_ml_sot.md` (**v8.4 — 주력 SOT**) · `qvest_v8_3_alpha_discovery_sot.md` (v8.3) · `qvest_v8_1_sot.md` (v8.1) · `qvest_v8_0_upgrade_plan.md` (v8.0)

## (v10.4 유지 · 버전 미변경) 09-26 중단분 배포 · B4 5축 · 유기체 O0a · 청정 레인 · 노출 표식 · 러너 재개 (2026-10-04)

**도훈**: `ORGANIC-EVIDENCE-SCOPE`([위임] 불인정 + 주제 결속) · `B4SIX-INHERIT-ORDER`(바닥 > carry) · `B4SIX-LEANLOOP-DOC` ·
`CLEAN-LANE-REINFORCE-BEFORE-FA`(평소 강화 + N 계상) · `ENTRY-7308-DISPOSITION`(park) · `EXPO-INHERITED-FLAGS`(포함). 09-26 위임 결정은 그날 묶음 한정.

배포 창(09-26 11:16 개시 → 10-04 08:16 종료 · 러너 정지 8일) 안에서 순차 배포(07:46~08:13 · 단계별 사후 점검 통과 · 키트 = `/c/tmp/qvest_deploy_1003`·세션 스크래치):
- **AXIS(B4-SIX)**: 신규 `reinforcement/rf_spec_axes.R`(축 등록부 6축 — 러너·promote·gates·block_design 파생) · B4 = 전결합 1 + 축별 LOO 6(B3 diag 시 6칸) ·
  대조 칸(B7_40·41) 승자 제외 · 승계 순서 바닥 > carry(config `spec_axes.inherit_order` 로 되돌림) · lean-loop.md '6블록×5 + B4 7칸 = 37'.
- **HUMAN(사람 규칙)**: P1-08 FIFO·entry priority/experiment · 레인 순서 · 세대당 신규 논문 · overlay_propose G1 · `rf_budget_auto` 가산 차단(B1 몫 = 최종 칸) ·
  `b5_budget`(compose_only 연속 K=2 → 상주+2칸) · B3 구조 축소(진단 1칸 keep B3_12 — 구조 사실 근거만).
- **CORE(유기체 O0a)**: 시행 로그 `06_Registry/rf_trial_log.jsonl` + 생산자 배선 · 결정 id 수리·기계 기록 · organic writer/guard/adapter/cmd · config `organic.*`(enabled=false · live 0).
- **AGRG**: `arm_gen_read_guard` 측정 구역에 `rf_decisions.jsonl`·`rf_trial_log.jsonl`·`06_registry/organic/` 추가(운영 결정 기록에 전기간 성과 수치가 이미 있었음 · 335/0).
- **CLEAN(청정 레인 + F_A floor)**: 성과 비소비 청정 기저 선정(`rf_clean_base.R` · 입력 열 전수 확인) · 청정 provenance · F_A v1(blocked · 후보 0) ·
  ★F_A v2 전 D1(청정 분기 앞 실행 전사 미대조)·D2(구판 분기 full 자격) 수리 필수(미스테이징).
- **EXPO(AutoMem 노출 표식 v2)**: 관문 패치(gates bc6cbf6ad140 · 34/0) + 원장 표식 1,387(+ 승계 · PROMO1 carry 누락 · 청정 재구현 전파 제외).
- **7308 park**(39/35 · active 0) · **PREREG 수리**(draft3 드라이런 DESIGN 0 · 남은 차단 = 측정 전 항목) · **LEVER**(B7 교체 후보 제외+전달량 `rf_engine_diag.json` · cap_core 는 사전등록 arm 스펙에서만) ·
  **1505.00328 청정 재구현 요청** 배치.
- 사고: Windows 임시 파일 자동 정리가 %TEMP% 세션 스크래치의 키트 일부를 삭제(10-03 11:10) → 키트를 `/c/tmp/` 로 이관(기억 카드).
- **F_A v2 D1·D2 수리(10-04 오전 · 배포 창 불요 — `rf_clean_base.R` 소비자 = F_A 생성기·검사뿐)**: D1 = 청정 분기가 같은 작업 디렉터리의 앞 회차 구현 전사·프롬프트(재구현 절·감사 원천 사본 전부)까지 판독 ·
  D2 = 가드 증명 없는 실행의 Read/Grep 이 청정 가드 허용 목록(단일 출처 `policies/arm_gen_read_guard.json::clean_lane.read_allow`) ∪ 자기 작업 디렉터리 밖이거나 실행 도구 사용 = 판독 불가(NA) ·
  설정 `clean_base_rule.config.json::exposure.transcript.unattested_scope`(부재 = stop) · 검사 `test_rf_clean_base.R` 104 → 117/0(X12 기대값 정정: 다른 엔진 열람 = 비노출 → 판독 불가 · 돌연변이 C31 red).
  **아키텍처 리뷰(10-04) 30일 규칙**: 이 수리 뒤 7일간 수리·배포 창 0(라운드 차단 결함만 예외) · 공급 순서 Calmar 우선(`SUPPLY-TARGET-WALL`)은 F_A v2 생성 시점(청정 후보 발생 시)에 적용 · B5 LLM 레인 유지(`B5-LLM-LANE-KEEP`).

---

## (v10.4 유지 · 버전 미변경) 09-25 미배포분 배포 · B5 경계 증발 수리 · A 레버 기반 (2026-09-26)

**도훈**: "지난 세션 미처리 Task 병렬 처리" · "일단 배포에 집중" · `RUNNER-B5-BOUNDARY-FIX` · `B4-SIX-AXIS-AND-CARRY-AXES` · `P1-06-CTRL-APPROVE` ·
`FA-CLEAN-BASE-PATH` · `AUTOMEM-EXPOSED-CELLS-DISPOSITION` · `PR-L1-POWER-MEASURE-FIRST` · `PR-L1-L2-ORDER` · `PR-L2-B7-EXCL-UNIT` ·
`PREREG-DRAFT2-Q-INTERPRETATIONS` · 위임("알파 창출력 강화를 명제로 자체 판단" + "결정 수치 보정도 위임" — 레지스터 `[위임]` 9건 · Grade A 기준 불변).

- **배포(Q 배포 창 11:16~ · 사후 점검 전부 불일치 0)**: R3R_rb 12:46(safety_guard 줄 이음 D2 · overlay_probe allowlist 레지스트리 eb940a5b) ·
  ALLOWP 13:29(B5 설계 프롬프트 허용 목록 127 · 1차는 run_all_hooks.sh 잠금 WinError 5 → 자동 원복) · RUNNER-B5-BOUNDARY-FIX 13:39(기전 레인이 B5 설계
  레인 산출을 덮지 못하게 · 경계 처리 누락 블록 tick 시작 백필 · 격자 재대조) + 7308 설계 기록 r2 복원 13:40 + stage_c 소비 보류 13:43 · CTRL 13:45(P1-06
  통제 칸 B1_0 carry 재현 · B1_N1..N4 null 희석 · 러너·관문 merge3) · INTEG 13:50(floor v2 소비 필드 · `contracts/b_ewcw_paired.R` · `selection_accounting.R::sa_subwindow`) · DRAFT2 13:50.
- **사고·발견**: 09-25 22:07 B5 설계 레인 8칸 설계를 같은 tick 의 B6 기전 백필 레인이 22:16 다른 5칸으로 덮어써 B5 블록의 G2·L-code·텔레그램이
  증발(경계 판정이 tick 시작 격자 8칸 기준) — 위 수리. B4 격자·승격 carry 에 B6·B7 축 누락(러너 963~999행 · promo1 41칸 중 36칸 buffer_2x 없이 측정) — 수리 스테이징 중.
  아침 재부팅 체인의 suite_totals 배터리가 운영 run_all_hooks.sh 를 2시간+ 점유 → 배포 차단(도훈 승인으로 중단 · 배포 뒤 재수집).
- **미배포(종료로 중단 · 인수인계 = 플랜 `qvest-1-drifting-eclipse.md` "09-26 종료 시점")**: B4-SIX · 청정 레인 강화 · 노출 표식 · 유기체 CORE·HUMAN · 사전등록 수리 · 레버 구현.
  러너는 배포 창 상태(enabled=false)로 의도 정지 — 남은 러너 변경 배포 뒤 복원.

---

## (v10.4 유지 · 버전 미변경) 측정 기준 전환 close_t1 · C11 2단계 · 무인 레인 기억 봉쇄 (2026-09-25)

**도훈**: `P0-05-STAGE1-RUN` · `P0-05-STAGE2-EPOCH` · `D-A-N-TIMING` · `A-GATE-VINTAGE-STAR` · `PIT-C11-FDB-FROM` · `PIT-C11-M4-S7-APPLY` ·
"P0 나머지 5개도 지금 진행" · "셧다운 안되는 수준에서 최대병렬" · `REINFORCE-ORGANIC-AUTONOMY`(완전 자율 — 설계 진행 중).

- **원장 측정 기준 전환**: 과거 강화 칸 전수를 보유 기반 재측정(`contracts/remeasure_from_holdings.R` · 1,211 산출물 · 실패 0 ·
  RAWDATA·벤치 md5 전후 불변) → `rf_rebase_driver.R` rebase 1,250칸(거부 0 · 구판은 `essence_history[close_d_legacy]` append-only) →
  `rfr_epoch`: `current_axis = exec_v2_close_t1`(승계 49). 미재측정 56칸(C11 35 · WT 사전형 12 · 08-29 파일럿 9)은 legacy 로 남아 A 보류.
  원장 계약 수치: B 332→220 · PORT_t≥2.95 117→39 · Calmar≥0.5 33→2. 산출·백업 = `04_Research/01_reports/p0_05_remeasure_20260925/`.
- **P0-08 표식**: 원장 586칸 — `selection_basis_full_sample_ic` 60 · `…_inherited` 501(--include-inherited, C1 D-E·A-GATE-VINTAGE-STAR 정합) ·
  `treatment_misspecified` 25. 최고 계보 22632 전체가 승계 표식 → A 보류. ★새 칸 자동 승계 부재(`rf_runner_gates.R:552`) = 신규 P0-14.
- **C11 2단계**(런북 `run_c11_phase2.sh` · 백업 `.cache/_c11_p2_backup/20260925_113012/`): JM 전방 필터 전 이력 · 국면 원장 재발행 ·
  AE 재산출 · m4 재초기화 · BCS · 월간 FDB 열(2000-06~ · MA01/02 제거) · 일간 FDB 전 월(phase6~9b, 75분). S9 = 최종 대조 20/0 ·
  C11 스위트 1,147/0(재실행). 첫 S9 의 1 fail·3 미측정은 검사 결함 — `test_pg2_c11_consumers` E2 픽스처가 S3 재발행으로 생긴 파일 스탬프를
  안 지워 '수리된 상류'가 됨(E0 자기검사 추가) · 신규 3종 요약 JSON 누락(추가).
- **P0-M1/M2 배포**(키트 `/c/tmp/qvest_kit_M1M2_0925`): 무인 LLM 레인 `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` 을 `rf_llm_agent_run` 단일 진입에서
  (27파일 이관 · 미경유 0) · `safety_guard.sh` 무인 레인 기억 쓰기 차단 → `06_Registry/memory_inbox/` · `arm_gen_read_guard.sh` 설계 레인
  확장(QVEST_DESIGN_LANE) + R2 실순회(좁힌 glob 우회 차단) + `hooks/policies/arm_gen_read_guard.json` · 설계 레인 4종 셸 통로 7종 금지.
  무인 작성 기억 카드 19장 `source: unattended_lane · review: pending`. P0-08(B08)·P0-09(B09) 는 08:39·08:47 설치.
- **P0-13 충실구현 A → A 자격 관문**(18:38 · 키트 `/c/tmp/qvest_kit_R1_0925`): `run_paper_replication.R` 이 grade A 면 `rf_a_eligibility` 정본을
  격리 환경으로 태워 `judge_request.eligible.json`(Judge 트리거) / `judge_request.held.json`(사유 코드) · 셀 판별 3조건(스위치 ∧ RF_CELL_SPEC ∧
  셀 엔진) · 러너 밖 수동 셀 A = `held:cell_outside_runner` · fail-closed. `a_eligibility_gate.json` 충실구현 회계 요건 chain. 문서 8곳 'B07 뒤 이관 예정' 문언 정정.
- **설계 레인 전기간 통계 통로 차단**(18:38 · R2): `arm_gen_read_guard.sh` 이름 층 STATS_RE + 내용 층(content_guard) + 좁힌 glob 순회 ·
  `rf_b1_design_lib.R` 교차 entry 수치 가림(발송 전 재도출 · 남으면 규칙 폴백). 서술형 문서·로그 통로 약 2,700건은 남음.
- **P0-08 as-of 상한 가드**(18:41 · R3/B08): `rf_factor_arms.R`·`rf_sleeve.R` asof 가 결정 시점보다 늦거나 NA/미래면 stop.
- **B5 설계 재료 교차 entry 수치 가림**(19:09 · D-E-B5-MATERIALS): `rf_b5_design_lib.R` — 자기 절 외 기본 가림 · (3) arm_id 순 · 발송 전 재검사 fail-closed.
- **P0-14 계보 기반 표식 자동 승계**(19:37 · 키트 `/c/tmp/qvest_kit_P014_0925`): 신규 `rf_lineage_flags.R`(계보 표식 술어 정본 — 원장 일괄 표식과 관문이
  같은 함수) · `rf_runner_gates.R` ⑤ 가 새 칸마다 선정 기저 승계(오염 집합 ⊆ 칸 팩터 · as-of 면제는 집합 원소 전부 증명 시만 · carry 출처 n 까지)와
  C11 격리(spec·arm·엔진 코드 스캔)를 재도출 · 판독 실패 = 보류(fail-closed) · 러너 SPEC 에 `selection_basis`·`selection_asof`(격자 스냅샷 폴백 칸 =
  full_sample_ic) · 충실구현 어댑터 engine_path 격리 스캔 · `register_module.R::.RM_ROOT` 설정 루트 결손 시 stop(샌드박스 운영 누출 근본 수리).
  22632 계보는 carry 가 남는 한 A 불가(as-of 재선정 새 칸 = floor v2).
- **P0-07 데이터 컷오프·빈티지 지문**(21:29 · 키트 `/c/tmp/qvest_kit_B07_0925`): `pin_cache.R` `pin_fp_v2` — 소비 열을 소비자 코드에서 재도출
  (Close·K200·KQ150·Ret·Size·Vol) · 행 키 정렬 원 비트 해시(맞교체 검출) · 지문 밖 원천(재무·컨센서스 등 엔진이 직접 읽는 패널)은 `unverified`
  → `vintage_unverified` 저널 · `rf_open_entry` 가 data_cutoff·data_fingerprint 기록 · 승격 자식 vintage_mismatch 저널 · 러너 병합(R1+P0-14 위 3-way).
  1차 키트 `deploy_b07.py` 퇴역(rollback 이 R1 이전 판으로 덮던 결함).
- **무인 러너 재개**(21:35 · `reinforce_auto_config.json` enabled=true · RUNNER-RESTART-AFTER-P0-14 · RUNNER-RESTART-RELAX): 현행 격자 ·
  유기체 live 0 · l2_auto·director 정지 유지. 뒤따름: R3R · V6 · 프롬프트 허용 목록 · B5 라벨 · 카탈로그 차단.
- **P2 기초**: `contracts/tilt_attribution.R`(21:38 · 공통 성분 분해 진단 — 등급 대체 아님) · floor v2 `rf_floor_v2.R`·`06_Registry/prereg/reference_floors_v2*.json`(21:39) ·
  `reinforcement/rf_prereg.R`(23:35 · 사전등록 스키마·writer·판정 · 초안 PR-L2/PR-L1 draft1).
- **배포 창 1차**(22:58 러너·B5 설계 레인 정지 → 23:34 tick 소진 → 23:35~38 배포 → 23:40 복원): V6(pit.md V6 절 as-of 조건부 IC ·
  lockbox 절에 ORGANIC-DE 예외 1줄 · 전기간 조건부 IC 소비 호출부 차단) · B5LAB(B5 재료 교차 entry 결과 라벨 가림 95→0) ·
  CATB(설계 레인 카탈로그·arm basis 성과 수치 차단 — 가린 사본 179).
- **사고(Q 과실)**: RUNNER-RESTART-RELAX 를 올릴 때 'b5_design.enabled=false' 를 설정 확인 없이 전제로 적었다(실제 true). 21:58 B5 설계 레인이
  교차 entry 결과 라벨 95건 노출 재료로 7308 B5_16~20 을 설계·측정 → 표식 `design_materials_cross_entry_labels`(possible · A 보류 · 재측정 없음 ·
  ORGANIC-DE Q④ 기본값). 교훈: 에이전트 보고의 설정 상태는 설정 파일에서 재도출한 뒤에만 결정 전제로 쓴다.
- **결정**: RUNNER-RESTART-AFTER-P0-14 · PR-L1-A4-DISPOSITION · D-E-B5-MATERIALS · D-E-V6-CONDITIONAL-IC · ORGANIC-DE((iii)+τ_D ·
  lockbox 폐지 조항의 유기체 입력 한정 예외) · ORGANIC-SCOPE · B3-STRUCTURAL-TRIM · ORGANIC-PRIORITY. 유기적 강화 설계 최종판 =
  `04_Research/01_reports/organic_reinforce_20260925/organic_design_final.md`(레버 감사·3설계 동봉).
- 되돌리기: 원장 = `ledger_l1_pre_epoch.json`/`pre_rebase_stage*.json` · P0-08 = `/c/tmp/p0_08_apply/backup_apply` · M1M2 = 키트 `rollback.sh` ·
  C11 = `run_c11_phase2.sh rollback <S> 20260925_113012` · R1/R2/R3 = 각 키트 `rollback.sh`(배포 직후 sha 와 같을 때만 복원).

---

## (v10.4 유지 · 버전 미변경) 리서치 디렉터 동결 — 흡수 Phase 0 (2026-09-24)

**도훈**: 디렉터 효용 검토 → `DIR-ABSORB`(결정·학습 층 퇴역, 진단·기록 부품은 P1-01·P3-01·P3-05·P3-07 로 흡수) ·
`DIR-PHASE0`(스위치 배선 + 동결) · `DIR-DIRECTION-SCORE`(방향 채점 폐기). 근거 = `04_Research/01_reports/director_review_20260924/director_verdict_20260924.md`
(디렉터가 바꾼 결정 0건 · 정정 전 수치 4.349/0.501 재방송 · C11 로 막힌 L2 개설 권고).

- `rf_director.R::dir_run` 이 `director.enabled` 를 실제로 읽는다(구판은 읽기만 하고 소비자 0 = 끌 수 없는 스위치) → config `false`.
  동결 = 계산·캐시·지도·결정 기록·방향 채점·텔레그램 0, exit 0 한 줄. 기존 캐시는 사료로 둔다. 로케일 가드·UTF-8 쓰기 검증 패치 동시 적용.
- 부팅: `Director: 동결(흡수 대기 · DIR-ABSORB …) · 대기결정 N` — 옛 캐시(정정 전 수치) 비전재 · config 판독 불가는 '?' ·
  `Rules: 폐기(DIR-DIRECTION-SCORE …)` (줄 삭제는 Phase 2, 부팅 줄 수 계약과 함께).
- `/qvest`: 1a 규칙 채점 단계 삭제 · '첫 선택지 = Director 권고 + human_override 기록' 규칙 삭제(선택지 ①②③ 고정).
- `research_continuity_guard.sh` W3(지도 신선도 넛지): 동결 중 침묵(갱신 주체 부재 — v9 W8 no-op 과 같은 사유).
- `axiom/replay/policy_state.R`: `QVEST_POLICY_UNATTENDED` 기본 0(자동 live 금지 · 소유 P1-07 · `DIR-ABSORB-ITEMS` ④).
- 되돌리기: config `director.enabled=true`(부팅·W3·rf_director 가 전부 종전 경로로 복귀) · qvest.md 는 git 이력.
- 검사(SUITES 등록): `test_rf_director_freeze.R`(8 · 산출 5종 0 · 양성 대조 · 게이트 제거 돌연변이 · 운영 3스위치) ·
  `test_continuity_w3_director_freeze.py`(4) · `test_boot_lean_director_line.R`(17 · F7~F9·M2) · `test_boot_lean_rules_line.R`(11) ·
  `test_policy_auto_live_rule.R`(29 · 기본값 off).
- 기존 결함(범위 밖): `test_map_freshness_content.R` 11 fail — HEAD 에서도 동일. 09-21 디렉터가 지도를 기계 형식(표 3행)으로 바꿔
  08-20 손 작성 형식(14행) 전제 단정이 깨진 것. 지도 퇴역(Phase 2)과 함께 처분.

---

## (v10.4 유지 · 버전 미변경) 무인 경보 소음·글자 깨짐 수리 (2026-09-24)

**도훈**: "무인스케줄러 task health 이건 왜 자꾸 뜨는거야?" · "글자 깨지는거도 확인해보고" · "의미없는거 같으면 없애버려도 돼".

(v10.4 유지) 09-24 무인 경보 소음·깨짐 — task_health: DR 자기보고 exit_1(완주+[7] 발송 확인) 경보 제외(되돌리기 `QVEST_TH_SELFREPORT_EXEMPT=0`) · morning_run 재시도 조건에서 관측자 마커 제외 · DR [0c] 적재 후 측정 + 하류(p3_forecast) 판정 제외(보고 줄 유지) · 같은 실패 서명 반복은 무음 요약 · `Qvest_MorningReboot.bat` `LC_ALL=C.UTF-8` → `LC_COLLATE/LC_TIME=C`(09-03 '호출부별 prefix' 결정 번복 — 신규 R 호출자 5곳 재발; 되돌리기 = export 복원) · telegram_notify.R 섞인 리터럴 균질화.

- 되돌리기(항목별): task_health 면제 = `QVEST_TH_SELFREPORT_EXEMPT=0` · seen 확정 조건 = `scheduler_task_health.sh` (D) 블록 삭제 ·
  재시도 마커 = `morning_run.sh` 재시도 블록을 `ls -1 …_${TODAY}.alert | head -1` 한 줄로 · [0c] 위치·하류 제외 = `daily_refresh.sh` 블록 원위치 +
  `freshness_audit.R` role 한 줄 삭제 · 서명 게이트 = `.cache/dr_fail_signature.json` 삭제(다음 실패가 '신규') 또는 [7] 블록 구판 · `tg_send(mute=)` 는 기본 FALSE 라 무영향.
- 검사(SUITES 등록): `test_scheduler_task_health_verdict.sh`(37) · `test_morning_run_retry_marker.sh` · `test_scheduler_bat_locale.sh` ·
  `test_telegram_literal_homogeneity.py` · `test_dr_fail_signature.R` · `test_dr_freshness_gate.py` · `test_boot_lean_director_line.R`(부재≠파손).
- 병행 소유라 패치로 대기 → 적용 완료: `rf_director.R` 로케일 가드·절단 검증(디렉터 동결과 함께) · `morning_briefing.sh` [5/5]
  `QVEST_FRESHNESS_QUIET=1`(러너 배리어 v2 SAFE 뒤 13:4x 적용 · `test_refresh_barrier.sh` 89/89 재확인). 발송은 [6a] 뒤 `mrs_daily_briefing.sh` 재감사 한 곳.

---

## (v10.4 유지 · 버전 미변경) 주간 증류 무인화 — 삭제 판단까지 LLM 위임 (2026-09-05)

**도훈 지시**: "주간 클리너에 자동 증류 기능까지 넣고 싶어" → 범위 ①안(digest + DIST 초안 + L-code) · 삭제 **전면 무인(LLM 판단 위임)** ·
"2계층 리서치 프로세스와 운용상 충돌없게".

### 왜 — 금지 조항이 지시와 충돌한 채 방치됐다
`.claude/skills/cleaner/SKILL.md` §2 의 "증류(digest·삭제 판단) 자동화 금지"(2026-07-04)는 2026-08-30 "모든 작업을 무인화" 와
정면으로 충돌한 채 남아 있었고, 그 사이 **증류 세션이 3주 오지 않았다** — digest 마지막 2026-08-15, `pending_5axis` 백로그
49건(07-17) → **104건**(09-05). 스윕은 매주 재료를 쌓았는데 소비자가 없었다. 도훈이 무인화 쪽으로 정합을 지시했다.

### 결정
- **무인 증류 레인 신설** — 스윕 직후 `claude -p`(stdin) 로 digest·DIST 자동초안(적대검증 5체크)·L-code·삭제를 완주.
- **역할 분담**: 에이전트 = *무엇을* 증류·삭제할지 판단. 기계 = 재도출로 **검증하고 집행**. 에이전트에겐 **Bash 가 없다** —
  스스로 못 지우고 삭제 요청 JSON 만 낸다. 집행 가드 = 보호목록 · 참조0 `git grep` · 최근 24h 수정분 제외 · 건수/용량 상한.
- **2계층 충돌 회피**: `Qvest_ReinforceAutoLoop`(~20분 주기, 칸 5개 + LLM 레인 3종)과 토 09:00 이 정면으로 겹친다.
  gate 가 reinforce claim(owner.json pid 생존)·sweep lock·distill claim 을 보고 겹치면 **연기**하고,
  `morning_run [0.75]` 일간 훅이 재시도해 한 주를 통째로 잃지 않는다. (착수 직후 실측에서 실제로 `reinforce_active` 를 잡았다.)
  ★**역방향도 막았다** — 게이트만 두면 "강화 중 증류 착수" 는 막히는데 "증류 중 강화 착수" 가 안 막힌다.
  둘 다 L-code 원장·`distilled_knowledge.json` 을 쓰므로 겹치면 lost update 다. `reinforce_auto_tick.sh` 가
  `distill_status=in_progress ∧ owner=auto_distill ∧ 나이<1h` 일 때만 물러난다(죽은 레인이 강화를 stale 6h 세우지
  않도록 1h 로 끊는다). 주 1회 20분짜리라 손실은 tick 1~2회.
- **불변**: DIST `proposed` → `distilled` 활성화는 여전히 도훈 승인(INV-6). 무인화가 옮긴 것은 *초안 작성자*이지 *활성화 게이트*가 아니다.
  공리(AX-*)는 별개 층으로 `refine_statement.R` R0~R6 이 무인 판정(2026-08-30) — 두 계층을 섞지 않는다.
- `/cleaner` 스킬은 **폴백 + 사후 검토** 경로로 재정의(SKILL §0.1 gate 판정부터 · 손으로 §1 반복 금지).

### 실측 — 양성 대조가 잡은 결함 (위반 주입만 쟀으면 못 봤다)
첫 검사에서 **위반 주입 5종은 전부 통과했는데 양성 대조가 실패**했다: 참조0 인 죽은 파일이 안 지워졌다.
원인 = 삭제 후보는 전부 `hygiene_report.json` 에서 나오는데 **그 파일이 후보 경로를 적어 둔다** → 문자 그대로 세면
모든 후보가 "참조 1건" → 삭제가 원리상 불가능. 주입 방향만 쟀다면 "가드 완벽 · 전부 거부" 로 초록이 나고
레인은 영영 아무것도 안 지웠을 것이다. 수리 = `ref_check_ignore` 로 **기록과 소비를 가르고**(감사 리포트·매니페스트·
불변 런 기록·이벤트 로그는 분모에서 제외) `n_refs_raw`·`refs_ignored_as_record` 를 매니페스트에 병기(조용한 완화 금지).
실데이터 재료 조립에서 글롭 누락 2건(`cache_cleanup_manifest_*`·`qepm/observability/*`)도 같은 축으로 적발.

### 파일
`cleaner_distill_run.sh`(레인) · `cleaner_distill_lib.R`(gate/materials/apply/notify · 격리 `QVEST_CD_ROOT`) ·
`06_Registry/cleaner_protected_paths.json`(경계 정본) · `reinforce_auto_config.json::cleaner_distill` + `llm.lanes.cleaner_distill` ·
배선 = `Qvest_WeeklyCleaner.bat` · `morning_run.sh [0.75]` · 표시기 정합 = `weekly_cleaner_sweep.R`(텔레그램·`next_action`) ·
`bootstrap.sh`(WARN 에 **나이 + 마지막 시도** 병기) · `reinforce_auto_tick.sh`(역방향 가드) ·
SKILL §0.1/§0.1b/§0.2/§2 · `artifact-storage.md` §8 3선 · `weekly_cleaner_sweep.R`/`rf_replication_auto.sh` 헤더(구 경계 사료화).
검사 = `08_Tests/ops/test_cleaner_distill.sh` **25항 전부 양방향**(gate 4 · materials 6 · 삭제 양성 2/주입 6 · DRY 1 · 역방향 가드 4), SUITES 등재.

## v10.4 — 강화 격자의 LLM 설계 · 적응 순서 · 승격 사슬 · 롤링/방어형 구제 (2026-09-04)

**도훈 지시**: "빠른 규칙 반복" 위에 (다)안 — B1 을 블록 진입 시 1회 LLM 설계로 · 최근 성과·개선 추세를 등급에 반영(F 확실히 구제) ·
방어형은 실제 벤치 하락월 기준으로 2계층 풀 자격 · LLM 레인별 노력수준 분리 · 텔레그램은 데스크가 읽는 물건으로.

### 결정
- **B1 = LLM 설계 1회/entry**, R 검증 실패 시 규칙 폴백. 기전이 낸 `next_block_design` 이 다음 블록의 셀 목록이 된다.
- **블록 순서 적응** (`rf_block_order_decide`): CAGR ≥ 0.16 ∧ Calmar < 0.64 → 위험 축 먼저. 기전 선호 우선.
- **승격 사슬** (`rf_promote.R`): 최고 ≥ B ∧ 부모 초과 ∧ 깊이 ≤ 3. carry = 팩터·비중·유니버스·오버레이. `count_paper=FALSE`.
- **구제** (`rolling_grade.R`·`defensive_score.R`): 36M 롤링 최근 통과율 ≥ 0.5 → F→C · 벤치 하락월 방어형 → `defensive_specialist` 풀 경로. 소급 F 74→C · 방어형 182.
- **충실도 감사 6축 팬아웃** (`rf_fidelity_fanout.sh`, 판독형 opus/max · 대조형 sonnet/high, R 결정론 병합).
- **LLM 레인** (`llm.lanes`): replication max · fidelity_audit xhigh · 나머지 high. fable-5-1 은 CLI 2.1.170 미지원으로 차단 기록.
- **회피 집행**: 기전 `avoid` 중 측정 무효 사유만 건너뜀(AX-000) · 부모 사슬 walk. **강등**: 승계 비중이 뒤 블록 유니버스에서 불가면 EW.
- **텔레그램**: relaxed 계약 · 블록 본문 + `이번 배치에서 알게 된 것` 후속 전체판(규칙, `rf_block_insights.R`) · 팬파레 · 라운드 리뷰.

### 실측 (09-04)
- 두 라운드(35+25칸) 최고 칸은 항상 첫 두 블록(B2_6 2.109 · B1_2 2.171). 유니버스·오버레이는 LOO 두 번 연속 순손실. MDD 45.9% 아래로 못 내려감.
- 승격 entry 두 세대의 B1 LLM 설계가 **argv 32K 상한**에서 미기동("설계 파일 부재") → 여섯 레인 stdin 전달로 수리.
- 파이프라인 점검: `count_paper` 키 부재 = 세지 말라 · 충실도 기각 안내 결정론적 유실 · 검사 픽스처가 운영 로그 오염 · 기전 6/15 빈 채 재시도 없음.

### 파일
`rf_b1_design.sh`·`rf_b1_design_lib.R` · `rf_lcode_mechanism.sh`·`_lib.R` · `rf_block_design.R` · `rf_lesson.R` · `rf_promote.R` ·
`rolling_grade.R` · `defensive_score.R` · `rf_fidelity_fanout.sh`·`rf_fidelity_merge.R` · `rf_arm_compat.R` · `rf_mech_backfill.R` ·
`rf_block_insights.R` · `rf_round_review.R` · `rf_grade_fanfare.R` · `rf_llm_env.sh`. 검사 = reinforce SKILL §0.3 끝의 목록.

## v10.3 — 강화 LLM 재귀 루프 · 횡단면 오버레이 축 신설 (2026-09-03)

**도훈 지시**: "강화프로세스에 LLM을 어떻게 활용할지 계획. 재귀적 자가발전이 가능한 형태로. 실제 전략 성과 개선이 가능하게."
**결정 3건**: 재귀 범위 = 카탈로그 arm만 · 자율성 = 등재 자동·측정 자동 · 오버레이 노출 = 종목별 벡터.

### 진단 — A등급 0/305 의 원인은 신호가 아니라 위험 축 기전 부재

측정 268셀에서 `port_t`(max 2.630/문턱 2.95)와 `calmar`(max 0.440/0.64)는 **충족 0%**, 84%가 5조건 중 0개.
막는 쪽은 CAGR 이 아니라 MDD 다 — CAGR 은 이미 최대 21.7%로 목표 16%를 넘겼는데
MDD 는 270셀 최저가 0.351(필요 ≤0.25), 벤치 자체가 52.9%다.
위험 축 유일 블록 B5 는 MDD −10% 대비 CAGR −23% 로 **Calmar 중앙값이 전 블록 최악(0.160)**.
기전: `Weight := Weight * oe` 의 `oe` 가 **월별 스칼라 1개**라 하락과 회복을 같은 비율로 깎는다.
기전 지도로 재보니 **B5 50 측정 중 40이 이미 포화된 세 칸에 몰려 있고 전부 스칼라 행**이었다 —
계열 라벨 6종이 다양해 보여 "오버레이는 다 해봤다" 로 오독되던 자리.

### Phase 0 — 기전 공간 확장 (LLM 아님)

- `rf_cell_engine.R`: 파일 디스패치 폴백 신설(`overlay_arms/<kind>.R`) — 기존 10 kind 는 사슬이 먼저 처리해 **코드 경로 무변경**
- 노출을 스칼라 ∪ 종목별 벡터로. 처치 확인 게이트를 2축(시간 ∨ 횡단면)으로 — 스칼라일 때 구판 조건과 **정확히 동치**
- 종목 상태 `.HOLD` 4축(beta·dbeta·ovol·bcorr) — 전부 누적합 확장창(C1)
- 첫 횡단면 arm `dbeta_tilt`: 낙폭 경험분포로 개입 강도, 하방베타 횡단면 순위로 차등 축소
- **실측 대조**(동일 기저·동일 위기): 스칼라 평균노출 0.749·완전현금 15/144개월 vs 벡터 0.887·**0/144개월**, 날짜 안 비중 sd 0.0148
- B2 배선 결함 수리 — `rf_pick_weight_arms()` 를 아무도 호출하지 않아 카탈로그 52종이 격자 밖에 있었다

### Phase 1~5 — 재귀 루프

| 단계 | 산출 | 성질 |
|---|---|---|
| probe | `overlay_probe.R` | 백테 0 소모로 등재 전 5축 검사. 위반 주입 5방향 전부 발화 |
| 포화 감지 | `rf_mechanism_map.R` | (action × state) 14칸. 표적 = 미포화 칸. 전 칸 포화면 **생성기를 안 부른다** |
| 생성 레인 | `rf_overlay_propose.sh` | `claude -p` 헤드리스. 프롬프트에 성과 수치 없음 |
| 등재 | `rf_overlay_admit.R` | R 이 등재. LLM 은 카탈로그를 못 쓴다 |
| 원장 | `overlay_arm_ledger.jsonl` | 측정 전 방출 기록. `selection_type` 구조적 파생(k>1 → sweep) |
| 교훈 | `rf_lesson.R` | 지표 되풀이(92%) → 기전 서술. carry 대비 위험·수익 이동으로 **대칭/비대칭 판정** |

### 안전 — "생성기는 성과를 보지 않는다" 를 구조로 만든다

★계획 초안의 구멍: `--add-dir` 는 쓰기만 가두고 **읽기를 안 가둔다**. Read 가 허용된 이상
생성 세션이 원장을 열면 셀별 등급·Calmar 가 다 보이고 그 주장은 거짓이 된다.
→ **신규 훅 `arm_gen_read_guard.sh`**(PreToolUse[Read|Grep|Glob], `QVEST_ARM_GEN=1` 일 때만).
평시 무발화. 등록 훅 12→13. 검사에 평시 음성 대조 + 생성 세션 위반 주입 3종 + Grep 우회 축 포함.

부수적으로 누출 스캐너가 **내가 쓴 첫 arm 도 잡았다** — 주석에 `calmar` 를 적었고, 측정 결과를
실행 소스에 쓰는 것이 곧 성과를 보고 고른 흔적이다. 근거는 카탈로그 `basis` 로 옮겼다.

**검증**: 강화 스위트 21종 + 신규 계약 4종. 배터리 편입 222/222.

---

## v10.2 — 강화 레인 근거 논문 의무 해제 · 원장 서술 의무 신설 (2026-09-03)

**도훈 지시**: "강화에는 근거논문 필요없게 배선해".
**계기**: 1계층 무인 레인을 멈추고 점검하다 두 결함이 같은 자리에서 드러났다.

### 1. 원장이 기록으로서 죽어 있었다 — idea 60% 공백

`sprintf()` 는 인자 하나만 길이 0이면 **경고 없이 결과 전체를 `character(0)`** 으로 만든다.
러너가 `SPEC$factor2$id %||% SPEC$factor2$kind` 를 넘기는데 factor2 없는 칸에서 양쪽 다 NULL →
idea 전체 소멸 → 원장에 `idea: []`. 실측 **305 시도 중 184건(60%)**, 여섯 entry 는 25칸 전부.
같은 기간 등급 결측은 4건뿐 — **측정은 살아 있는데 기록이 죽어 있었다.**

- 수리: `reinforce_auto_parallel.R`·`reinforce_auto_run.R` 조립부 `.s1()` 로 조각을 길이 1 강제
- ★막는 자리는 조립기가 아니라 **원장**: `rf_append_attempt` 에 서술 의무 가드 신설(근거 의무와 같은 층).
  조립기는 앞으로도 새로 생기지만 원장은 하나다.
- 계약: `test_reinforce_ledger.R` ⑧ — 위반 주입 4방향(`character(0)`/`""`/공백/`NULL`) + **함정 실재 확인**
  (이 런타임에서 `length(sprintf("a=%s", NULL)) == 0` 인지 직접 측정) + 러너 2종 정적 방어 확인
- spec 파일을 **원장 등록 성공 뒤에** 쓰도록 순서 교정 — 거부된 칸의 산출물이 남아 spec 5 vs 원장 4 였다

### 2. 근거 의무는 지키는 척만 하고 있었다 → 해제

계열→논문 표 `.RFF_FAMILY_PAPER` 가 8계열만 덮어 **선정 풀 332종 중 91종(27%)이 미매핑**
(accrual 25 · growth 21 · investor_flow 15 · crowding 14 · regime 10 · leverage 6).
깊이 1 셀은 논문 0건이라 거부되는데 **깊이 2+ 는 형제 계열의 논문으로 통과**했다 —
게이트가 시험 중인 축을 덮지 않는 근거로 충족되던 상태(누적 `root_paper_unmapped_family` 85회 발화).

- **해제 범위 = `rf_append_attempt`(강화 전용 진입점)뿐.** 충실구현은 `run_paper_replication` 의
  `source_paper` 를 쓰는 별도 경로라 불변 — 논문을 재현하는 단계에서 논문을 뺄 수는 없다.
- root_papers 는 있으면 그대로 기록. 시도 레코드에 **`evidence` = paper/method/none** 신설 —
  의무는 해제해도 "무엇에 기대어 돌았는가" 는 계속 셀 수 있어야 한다.
- 시도 레코드에 `unmapped_families` 도 기록 — 종전엔 `.cache` jsonl 에만 있어 원장만 읽으면 안 보였다.
- 축의 정당성은 이제 격자(`reinforce_program.json`)와 팩터 등록부가 진다.
- 계약 뒤집기(표기만 바꾸지 않고 **적립된 필드를 재도출**): `test_rf_root_papers.R` ③'/③''(none↔paper 양성 대조),
  `test_reinforce_ledger.R` ①(none/none/paper/method 4축). ★구판 ①은 '거부라서 카운트가 안 는다'는
  **부작용에 기대고** 있어서, 거부를 없애자 ②의 상한 시험이 한 칸 밀렸다 — 부작용도 계약의 일부다.

**검증**: 강화 스위트 16종 + `test_reinforce_auto` 117/0 + `test_reinforce_ledger` 18/0 + boot_currency 15/0.
**문서 정합**: CLAUDE.md 하드코딩 금지 절 · lean-loop.md(라운드 6단계·면제 목록) · reinforce SKILL(§description·§84·§102) · 원장 note 필드.

---

## v10.1 — v9 잔재 하네스 정리 · 무인 텔레그램 소음 수리 (2026-09-02~03)

**도훈 지시**: "v10 으로 업그레이드했다. 불필요하고 안 쓰게 된 인프라·검사기를 일괄 셧다운시키거나 v10 정합으로 패치" + "텔레그램에 계속 올라오는 무인 스케줄러·논문 라우터·좌초수리 알람도 같은 맥락으로 파악".
**방법**: 서브시스템 6종(훅·무인 러너·에이전트/스킬/룰·테스트 배터리·R 검사기·텔레그램 발송원) 전수 감사 → 제안마다 **적대 검증**(반증 시도) → 검증 통과분만 적용. finding 약 200건(keep 42 · patch 70 · shutdown 30 · ask_dohoon 12).
**규율**: 삭제 0 — 퇴역은 **★RETIRED 헤더 + 이동**이고 파일은 전부 존치(08_Tests·배터리가 경로로 직접 실행하므로). 롤백 = git.

### 1. 텔레그램 일일 소음 4종 — 실패가 아니라 **검사기 거짓 양성**이었다 (→ 0/일)

| 소음(매일) | 기전 | 수리 |
|---|---|---|
| `무인 스케줄러 경보 — task_health` | never_run(rc 267011) 작업의 LastRunTime 이 **1999-11-30 센티넬** → age 9,773일 > 9 로 staleness 발화. rc 축은 never_run 을 면제하는데 staleness 축만 빠진 **비대칭**. 08-30 등록된 주간작업 3종(AxiomActivate·AxiomReview·WeightCatalogGrow)이 매일 '정체 3' | `scheduler_task_health.sh` never_run 면제 + `.ps1` 센티넬 age null 화 + **전건 정상 시 마커 해소**(`sched_mark_resolved`, KNOWN 남아 있으면 보류). 검사 T8b/T8b2 + **돌연변이 T8c** |
| 논문 라우터 2건 | arXiv MCP 고정 30쿼리·recency 0 재크롤이 매일 같은 243편을 재부상시키는데 라우터 트리거가 '미소비' 로만 판정 → 매일 `claude -p`(≈5분) → 전건 redundant → 트리아지 1건 + 완주 알림 1건 = 정보량 0 | `paper_router_run.sh` **paper_key 사전 필터**(정본 `paper_id_norm.py`) — 신규 0 이면 route 스텁만 남기고 종료(스텁이 없으면 내일 백로그 축이 재소비). 완주 알림 기본 off. `mode_queue_axis_audit` 호출 제거. 검사 `test_paper_router_prefilter.sh` **양성 대조 포함 12/12**. ★09-03 07:16 실증: 243건 전건 기존 키 → claude 미호출 |
| 좌초 수리 경보 | 유실 worktree 15개 전부 브랜치 tip 이 v10 태그(`pre-v10-2layer`) 이전 = 폐기된 판의 잔재인데 감사기에 **세대(版) 개념이 없었고**, 스로틀이 '같은 날 1회' 뿐이라 동일 수치(127/19/1)를 7회 재발송 | `stranded_repairs_audit.sh` **legacy_pre_v10 분류**(tip < 태그 ∧ 미커밋 mtime < 태그 — 집계·JSON 에 남기고 경보 계수에서만 제외) + **발송 서명 게이트**. ★서명에서 경과 일수를 빼는 것이 핵심 — 넣으면 매일 달라져 게이트가 한 번도 억제하지 못한다. 09-02 20:08 실측: 유실 0 · 레거시 24 · 발송 0. 검사 T13/T13b/T13c |
| `curated_sources_missing` | CSV 는 26행 존재. `Qvest_MorningReboot.bat` 의 `LC_ALL=C.UTF-8`(bash 한글 파싱 방어용)을 Windows R 이 설정하지 못해 C 로케일로 뜨고, `read.csv(fileEncoding=)`(iconv 재인코딩)가 한글 열에서 **조용히 0행** | `read_sources` → `encoding=`(마킹만) + '존재하나 0행' 을 별도 사유 `curated_sources_unreadable` 로 분리. bat 은 무변경, **Rscript 직전에만** 로케일 prefix. 성공 런 뒤 `sched_mark_resolved paper_recharge`(09-03 묵은 마커 7건 해소 실증). 검사에 로케일 축 추가 12/12 |

부수: `unattended_line` 일일 집계에서 자체 발송 컴포넌트·자기 마커 제외 · paper_recharge 텔레그램은 신규 0·등록 0·죽은 링크 0·MCP 정상이면 침묵(상세 청크 상한 3, 표제 `[1계층] 논문 수집`) · 무인 경보 표제 `[무인]` 접두 · **`telegram_notify.R` 에 §5.6b 계층 표제 WARN 강제 지점 신설**(차단 아님 · `_layer_tag_missing.log` 적립) · 생성 R 스크립트 58개 아카이브 · 퇴역 레인 잔여 마커 3건 해소 · `events.jsonl` 회전 재가동(23,749→10,000행).

### 2. 계측이 낡은 목록을 초록으로 보고하던 자리 3곳

- **훅 검사기 3종**: `harness_health.sh` REQUIRED_HOOKS 가 ★RETIRED `governor_concord_certifier` 를 필수로 세고 v10 등록 훅 `book_write_guard`·(08-24 재등록) `backtest_contract_audit` 를 세지 않아 **두 파일이 사라져도 12/12 PASS** 였다 → 12종으로 동기(격리 양성 대조로 FAIL 실증) · `hook_fire_coverage.sh` UNCOVERED · `hook_integrity_check.sh` 직접 등록 래칫 4→6종 + 카운트 파생.
- **배터리 총계 파서**: 러너가 2026-08-24 에 `unmeasured` 구간을 추가해 FINAL 이 5-part 가 됐는데 `suite_totals_watch.sh` 는 4-part 를 정확히 요구 → 3-part 폴백이 **개별 테스트 줄**을 집어 hooks=12(실제 3,308)·fail=0(실제 6). 2026-08-20(1563→7)과 **같은 기전 재발** → 3단 앵커 + `hooks_unmeasured` 축 신설, 검사기에 현행 5-part 픽스처와 구판 돌연변이 추가(11/11).
- **v10 핵심 계약 9종이 UNMEASURED**: 러너 요약 JSON 한 줄이 없어 충실구현·강화 원장·L2 풀·BOOK writer/guard·Judge v2·비중상한 폐지 검사의 단언이 총계에 **0** 으로 들어가고 있었다 → 9종 전부에 요약 줄 추가.

### 3. 퇴역 (삭제 0 · ★RETIRED 헤더 + 이동)

- **에이전트** → `.claude/agents_retired_v10/`: `ramp-orchestrator`(RAMP v9.21 퇴임) · `blender`(발동조건 governor/PG2 소멸 — 2계층 결합은 strategy-rotation 승계) · `strategy-implementer`(핸드오프 대상 lean-forge 미구현) — 기존 execution·governor·monitoring 과 합류.
- **커맨드** → `.claude/commands_retired_v10/`(신설): `qlead`(v10 진입점 = /qvest 하나) · `ramp`.
- **스킬** → `.claude/skills_retired_v10/`(신설): `ramp` · `execution` · `monitoring` · `qvest-cert-paths` · `ensemble-design.md` · `pg2-allocation.md` · `axiom-io.md`.
- **프롬프트** → `02_Infrastructure/prompts/_retired_v10/`: governor/execution/monitoring/qlead init · qlead_spawn_template (+ `inject.R`·`axiom_rollback.R` 주입 목록 9→5 로 축소 — 사료에 공리를 주입하지 않는다).
- **훅**: pipeline 배관 3 + s0_enforcer 4 + pre-v9 미등록 10 = ★RETIRED 헤더. v9 해제분 중 폐지 개념을 **강제하는** 5종(agent_role_guard·worktask_sequence_enforcer·mandate_compliance_check·worktask_artifact_validator·unified_agent_guard)은 로직 무변경 + '재등록 금지' 경고 헤더. cert 데이터 층은 `governor_concord` 만 사문화(`_v10_retired` 키 · `qvest_cert_eval.py` 조기 반환 · **`cert_backfill_audit.R` R 가드** — bootstrap 7c 가 legacy 동결 디렉터리에 새 cert 를 쓰던 유일 경로를 이중으로 막았다).
- **무인 러너**: 퇴역 레인 러너·프롬프트·보조기 14종 헤더(이동 금지 — 08_Tests 가 경로로 호출) · `governor_weight_sum_check.sh` · `auto_sigma_weighting_ab.R` · `extract_book_carrier{,_d3}.R`. ★`auto_weighting_ab.R`·`auto_regime_overlay_ab.R` 은 **라이브**(overlay 큐 = v10 프론티어 ③)라 제외. 예약 미등록 고아 bat 4종 → `ops/scheduler/_unregistered/`.
- **bootstrap.sh**(health_full 전용): 7b/7c/7d/7e·PG2 status·standalone_track·mode_queue 절을 opt-in 스위치(`QVEST_LEGACY_BOOK_AUDIT` / `QVEST_V8_READINESS` / `QVEST_LEGACY_SPAWN_QUEUE` / `QVEST_LEGACY_MODEQ`) 아래로 내리고, 그 자리에 **BOOK 정본 1줄**(book_registry.json) 표면. 배너·꼬리 v10 재작성.

### 4. 문서·룰 정합 (측정 신뢰 축 우선)

`backtest-contract.md`·`python-policy.md`(살아있는 훅을 '해제' 로 오보 — 08-24 재등록 반영) · `measurement-graduation.md`(구 judge Gate C 폐지 명문 · 자본 tier→Graduation tier · monitoring→book-tracker · 참조 book_registry.R — **HARD 3종·DSR 경계·oos v2·holdout 규율은 무변경**) · `pit-validation.md`(방어선 표를 실측 2종으로 · C4 익년 3/31) · `harness.md`(11→12 distinct · v8.1 SOT 사료화) · `qvest-telegram/SKILL.md`(§5.6b 에 무인 발송 7종 **실측 포맷** 등재) · alpha-search 에이전트/커맨드(hurdle 인용 금지 → essence 권위) · worktask 커맨드 · forge/optimizer/risk/architect 에이전트 · `qvest-opt-style`·`kr-inverse-pattern-miner`(G-5 철회 반영 — settled-negative 는 금지 목록이 아니다) 등 30여 파일.

### 5. 도훈 결정 대기 (파괴적·외부 영향 — 실행하지 않았다)

예약작업 6건(AuditWatch 배터리 거부 · ReinforceAutoLoop 배터리 정책 · RAMP_AutoLoop Unregister · DART_Priority_Backfill 고아 · DART_Insider_Backfill 3시간 반복 · noLayer4_Monthly 이중화) · worktree 24개 처분 · `design_envelope_gate.sh` 등록 여부(훅 예산 12→13) · 강화 분모 20/25 정본 · Step 3b(noLayer4 일별 MTM) 발송 유지 여부.

## v10.0 — 2계층 리서치 재편 (2026-08-29)

**도훈 지시 전문 요지** (플랜 `~/.claude/plans/qvest-2-moonlit-galaxy.md` · 롤백 태그 `pre-v10-2layer` · 체크포인트 커밋 41eb28715):
1. **논문 라우팅 개편** — 수집 = "팩터 전략 리서치" 단일 목적(최신성 불요 — recency 180d 제거·relevance 정렬·고전 시드 11편). **중복 방지 규칙 신설** = `paper_key` 3단(axv > doi > ttl, 정본 `paper_id_norm.py`) + registry 619건 백필(실중복 1쌍 적발). 트리아지 v4 = {replication, skip} + `data_pipeline_required` verdict 신설(데이터 부재 = 기각 아님 — `data_pipeline_queue.json` 적재 후 파이프라인 구축).
2. **QEPM 재정의** — alpha 가설 설계 전기간 데이터. **lockbox 완전 폐지("반박 금지")** — 22개 지점 제거(schema required 완화·windowing 3-window·훅 4종 영구 퇴역·judge harness RETIRED). ⚠ C5 overlay SIGNAL_CUTOFF 는 PIT 기계 — 보존(diff 0). QEPM = alpha→risk→optimizer→forge + 등급 평가까지(FORGE_DONE→COMPLETED 전이 신설).
3. **Judge 분리** — PIT 검증 전담 별도 에이전트. **essence Grade A 확정 후에만 스폰**(모든 모드 공통). 검증 6축(C1~C15 감사·detect_lookahead 재실행·C5 타이밍·lag-1 스트레스·재현·selection 정직성) → `judge_verdict_v2`. 구 Gate C/D/E/F·8지표·lockbox 의무 폐지.
4. **1계층** = 논문 수집 → 공리 주입 → **완전 충실구현**(`run_paper_replication` + `replication_harness` — 롱숏·종목수·비중 논문 그대로, 유일한 변경 = 유니버스 K200∪KQ150. 등급은 15bps 순비용 판·논문 기준 병기) → 등급 → 미달 시 **강화 ≤25회**(★2026-09-01 재편으로 20→25 = 격자 5블록×5. 상한 정본은 원장 `max_attempts` 이고 이 문장은 그 사본이다. QEPM 기반, 축 = 멀티팩터/비중방법론/유니버스/리스크오버레이/결합, 원장 `reinforce_ledger_l1.json` — root_papers 없는 시도 기계 거부, 논문 3편마다 Q-Lead 결합 검토 의무) → A 시 Judge. 구 기계 사다리(reinforce_ladder) 퇴역.
5. **2계층** = 전략 로테이션 리서치 — **B등급 이상 풀**(2단 게이트: 계약 floor + essence grade floor, 실측 99→15모듈. 구 "등급무관 RCMA 차용" 폐기 — RCMA 는 배치 심사로 존치) × 논문 온디맨드 착수 × 리서치 1단위 등급 × **강화 무한**(국면식별/전략결합, 원장 l2) → A → Judge → BOOK. 목표 = 한국 특화 전천후 모델.
6. **BOOK** — governor/execution/monitoring 퇴역(monitoring → book-tracker 재편). `06_Registry/book/book_registry.json`(writer 자격검증 = A + judge pit_pass 재도출, append-only, `book_write_guard.sh` 훅이 직접 편집 차단 — governor_concord_certifier 자리 승계, 12 distinct 유지). **PG2 = BOOK_0001 이관**(`dohoon_mandate_20260829` — fresh essence 부재 정직 표기). 구 book_state.json = legacy 동결. Qvest = 리서치 시스템(실투자 집행 없음) — 트래킹 = `/book` frozen 스펙 재현.
7. **규칙** — /qvest 시 계층 질문 · 텔레그램 계층 표제 의무(`[1계층]`/`[1계층·강화 n/20]`/`[2계층]`/`[Judge]`/`[BOOK]`) · **종목별 비중 상한([0,0.20]) 인프라 전체 삭제**(등록 전략 frozen 스펙·비중방법 내부 파라미터는 별개 — 무변경) · 하드코딩 전면 금지 + 근거 논문 원문 링크 의무 · Q-Lead 오케스트레이션 전용 · 페르소나 정본 신설(`quant-identity.md` — 최정상급 퀀트·냉소는 방법론·리서치는 지난하다) · **무인 파이프라인 = 수집까지만**(morning_run 자동 리서치 4단계 철거).
- 신설 검사 8종(양방향·재도출): enforcer v10 4축 · replication 10축 · reinforce_ledger 11축 · judge_verdict 15축 · grade_floor 8축 · book_registry 8축 · book_write_guard 5축 · morning_rewire 13축. boot_currency 15/15 PASS.

## v9.21 — 논문 알파리서치 → 강화 프로세스 · 등급 일원화 (2026-08-24)

**도훈 지시 6건 + 후속 2건.** 플랜 = `~/.claude/plans/bright-dancing-snowflake.md`.

| # | 지시 | 이행 |
|---|---|---|
| ① | 강화 목표 등급 B→A | `reinforce_ladder_config.json::target_grade="A"`. ★부수 효과가 본체였다 — base 가 이미 B 면 3칸이 **전부 생략**되고 `capability_established` 가 발행되던 거짓양성을 원천 차단 |
| ② | 등급체계 1개로 | 권위 = `essence_score`(A/B/C/F). lean 라운드도 **항상** 산출(순환 의존 해제). `uncertain` 은 등급에서 제거(사유는 `metric_type` 이 보존) |
| ③ | 팩터 로테이션 → 전략 로테이션 | enum + alias + 경로 3종. prefix `FR` 유지 |
| ④ | QEPM = A등급 이상 심층리서치 | 모드 표 → 파이프라인 서술 |
| ⑤ | 기본 = 논문 알파리서치 → 강화 | 무인 러너 뒤 자동 기동(§2-d) |
| ⑥ | RAMP 모드 퇴임 | 진입점에서만 하차. 코드·데이터·L-code 73건 무손상 |
| ⑦ | "MDD 탈락은 빼줘" | `essence_score` 의 drawdown→`hard_fail` 추론 제거 |
| ⑧ | "hard_fail 조건에서 MDD만 걷어내면 되는거 아냐?" | 그 절단면이 정확했다 — 추론의 4개 논리합이 전부 drawdown 량이었다 |

### 실측 (전수 재계산 508 런 · `06_Registry/essence_regrade_20260824.json`)

| 축 | 전이 |
|---|---|
| ①MDD 탈락 제거 | F→B **2** · F→C **24** (계 26건). F 잔존 219 = 음의 알파(정당) |
| ②선행 드리프트(본 수정과 무관) | F→B 2 · F→C 10 |
| 권위 등급 **신규 발행** | NA 302건 → C 110 / F 192 (순환 의존으로 essence 가 아예 안 돌던 런) |

### ★실행 중 잡은 것 — 플랜대로 했으면 터졌을 3건

1. **등급 바닥 이중 조임**: 소스만 proxy→권위로 바꾸면 무인 레인 ADOPT(=L-code 적립 조건)가 **87%→1%** 로 붕괴한다(hurdle `{C,F}` 차단 13% vs essence 99%). 바닥을 도입 사유(IR −0.48 = 음의 알파)로 재단해 **권위 축 {F} · proxy 축 {C,F}** 로 분리.
2. **사다리 루프 미폐쇄**: `rl_candidates()` 가 원장을 안 읽어 매 실행이 같은 1위 후보를 다시 집었다. 무인 기동을 붙이기 **전에** 닫아야 했다(안 그러면 매일 아침 같은 전략만 태운다).
3. **텔레그램 v8 규격이 코드에 막힘**: `kv` key 영어 비율 검사가 `PORT_t`/`OOS retention` 을 하드 차단. 검사를 약화시키지 않고 whitelist 에 정본 표기만 추가.

### 계기 규율 (이 판의 관통 원칙)

**양성 대조 없는 계기는 방어선으로 세지 않는다.** `stage_dispatch.py::s7_grade_gate` 는 발화 이력 **0**(`TODO_PG0` 0 · `DONE_S7` 0)이고 상류 `pipeline_trigger.sh` 도 미등록이라, 정교한 재배선 대신 **최소 정정 + 사실 기록**으로 처리했다. 신규 검사 축은 전부 위반 주입·돌연변이 통제를 동반한다.

**배터리**: 182 스위트 · 기준선 3150→3208 pass · fail 4(전부 선행) · unmeasured 0.

---

## v8.4 헌법 전문 아카이브 (2026-08-23 v9 Lean Loop 이관)

> **직전 Active Version**: **Qvest v8.4 — Opus 5-Native · 4-Mode 헌법 · 실측 거버넌스 · 비대칭 알파 중심 재편(ML·수리통계 주력)** (세션 모델 정본 `claude-opus-5`. 발효 2026-08-13, 모델 라우팅 재핀 2026-08-08).
> **v9 도훈 결정 4건 (2026-08-23)**: ①게이트 2층 분리 + 자본 층 재보정 ②부활조건 Stop 훅 해제 → L-code 발행 시점으로 이동 ③QEPM 6-agent는 자본 층 입구로만 ④강한 감산(훅 ≤12(목표 11)·Stop 차단 0·부팅 ≤5줄·autoload 룰 2개·CLAUDE.md ≤8KB·테스트 수동).
> 아래는 v9 재작성 때 CLAUDE.md 에서 제거된 텍스트의 **전문(v8.4 판 원문 그대로)** 이다 — v8.x 서사·근거 정정·4 lane 상세·금지 4종·Multi-Agent 표·Axiom 요약·Q-Lead 역할 경계·훅 수 줄·Skills/Rules 2단 표 포함. **규범 효력 없음**(현행 헌법 = `CLAUDE.md`, 루프 절차 = `.claude/rules/lean-loop.md`, 자본 층 = `.claude/rules/measurement-graduation.md`). 리서치 방향 SOT(`qvest_v8_4_asymmetry_ml_sot.md`)와 확장 룰은 v9에서도 유효하다.

<details>
<summary>v8.4 CLAUDE.md 전문 (2026-08-13 ~ 2026-08-23)</summary>

# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v8.4 — Opus 5-Native · 4-Mode 헌법 · 실측 거버넌스 · 비대칭 알파 중심 재편(ML·수리통계 주력)** (세션 모델 정본 `claude-opus-5`. 2026-07-10 / **2026-08-08 QEPM 모델 라우팅 재핀 — 가설설계(`alpha-hypothesis`)만 `model: fable`, QEPM 나머지 전 구간 `model: opus`(현행 Opus 5)**. 구 2026-07-24 "핀 제거·세션 상속" 정책 대체. 폴백 = 한도 시 opus 재시도. SOT `02_Infrastructure/docs/rules/caching.md` 모델 라우팅 절)

> **★모델 표기 단일 출처**: 위 줄이 세션 모델의 **유일한 정본**이다(`boot_currency_check.sh` C0가 여기서 파생해 배너·상태라인 C1~C3를 대조). 다른 문서·룰은 모델명을 재기입하지 말고 "메인 세션 모델(정본 = 본 절)"로 위임할 것 — 재기입 지점이 2026-07-24 Fable 5 패치 후 3곳에서 동시 낙후된 전례.

**계보**: **v8.4** (현재 active) — 전체 계보(v6.4.0~)·릴리스 상세·검증 이력 = `02_Infrastructure/docs/CHANGELOG_constitution.md` (2026-07-24 C5 이관)
**Branch**: `main` (Qvest active — GitHub default)

**v8.4 핵심 (비대칭 알파 중심 재편, 도훈 mandate 2026-08-13)** — SOT `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md`:
- **주력 교체**: v8.3 도달 경로 ①(비-return 신규 원천)을 **주력에서 해제** → **기존 데이터풀 총동원 + ML·수리통계로 시장 비대칭 알파 도출**이 주력. 근거 = 비-return 5레인 중 **2건 데이터 게이트 폐쇄(도훈 08-09)** + 3건 실측 negative(insider 3-프레임 삼각-null · 계약 두 소비면 닫힘 · 담보/감사의견 SPARSITY_WALL). ★구조 판결 아님 — 부활 조건은 SOT §1
- **재편의 실측 근거 = ML 트랙이 자본 게이트를 하나도 못 통과했다** (`ml_complexity` 126건 원장 재판독 2026-08-13, `metric_type=registry_record`): sharpe 보유 84건에서 **MDD ≤25% 충족 0/84** · **PORT_t 기록 10건 중 ≥2.95 = 0건**(범위 −1.377~2.362) · **oos_retention 17건 중 게이트(≥0.7) 충족 2건**(음수 10건·중앙 −0.481). sharpe p25 0.492 / median 0.493 / max 0.756. 죽은 자리 = ①결합기(동일 3짝 metric 클러스터 16+9건 = 84 중 30% — 다른 결합 규칙이 같은 점을 낸다) ②사이징/selection(DPL 06-26 · uncertainty 07-05 2세션) ③평균 예측기 — ★**①은 2026-08-20 실측으로 기전 오귀속 확정**: 그 16+9 클러스터는 결합 규칙 수렴이 아니라 `batch_434` codegen 치환이 만든 **이명 복제본**이다(16/16 · 9/9 id 대응 실측). **결합 규칙은 실행된 적이 없다** ⇒ 이 클러스터를 근거로 한 "결합기 settled-negative" 는 INV-7 상 **비유효**. 복권 조건 = 치환-제외 클린셋(50건) 재판독에서 동일 클러스터 재현 시. 근거 = memory `project-batch434-alias-contamination-and-unapplied-audit-20260820`
- ★**근거 정정 2026-08-22 (도훈 헌법수정 권한 위임)**: 위 '126건' 은 **실험 집계가 아니라 `hypothesis_signature` 버킷 라벨**이다. 실측 — `ml_complexity` 태그 **131건 전부가 `hypothesis_signature` 필드값**이고(제목 표본 = 'Analyst Co-Coverage Lead-Lag Momentum' · 'Gross Profitability' = ML 라운드 아님), 131건 전체의 실제 기법 토큰은 **xgboost 8 · autoencoder 3 · random forest 2 · ridge 2 · lightgbm 1 · pca 1 이고 LSTM·Transformer 적합은 0건**. verdict 분포도 PASS 42 / MARGINAL 38 로 '전멸' 이 아니다. ⇒ **위 게이트-통과-0 수치 자체는 유효**하나(그 버킷의 등록 기록에서 산출됨), 그것을 **"ML 트랙을 충분히 시도했으나 실패했다" 로 읽는 것은 근거가 없다** — 실제 ML/DL 시도는 십수 건 규모다. 부수 실측: **분포-표적 툴킷이 설치만 되고 미사용** — 원장 등장 `properscoring`(CRPS) **0** · pinball **0** · optuna **0** · quantile_regression **0** · ngboost 1 · mapie 1 (venv 전 항목 정상 설치 확인)
- ⚠**자기정정 2026-08-13**: 초판이 쓴 *"126건 전부가 평균 표적 · 분포 표적 0건"* 은 **근거 없음** — `key_metrics` 에 표적 필드가 없어 셀 수 없고(자유 형식 패턴 감사), metric 보유도 84/126 이다. 정직 서술 = **"분포를 표적으로 명시한 라운드를 찾지 못했다"(미발견이지 부재 증명 아님)**. 재편은 위 게이트-통과-0 이 지탱하고, 표적 가설의 첫 시험은 Lane A 의 arm A(평균-표적 대조군) 재현이다
- **동기 서술(약)**: D03 Q5−Q1 평균 −5.10% vs 중앙값 +12.01% "부호 반대" — ⚠**중앙값·왜도 수치는 산문 기록뿐이고 구조화 출처 미확인**(08-13 재탐색에서 해당 WT 산출물에 `12.01` 부재). **Lane A 착수 0항 = 이 두 수치 재산출**, 미재현 시 이 동기 서술은 철회(재편 방향은 불변)
- **미소비 표면 = 일별 축**: 알파 리서치는 전부 월간 횡단면인데 데이터는 **9,005 거래일**(RAWDATA 14.06M행) + **flow_features_daily 1.25GB**(9.36M행 22피처, ⚠lag 43d 정체). 월간으로 접는 순간 분포 정보가 소멸 — 비대칭은 접히기 전에만 관측된다. ⚠factor DB 331 전수는 이미 소진(book-marginal 통과 0·계열 15종이 구속 해상도), 증분은 일별 원천에 있다
- **4 lane**: A 분포-표적 학습(1순위, 평균-표적 대조군 동반 의무) · **D 매크로 상태 조건부 비대칭**(2순위, 도훈 2026-08-13 추가 — 매크로는 **이미 적재 중**(오늘 07:04~07:07 갱신, lag 1d) 신규 수집 불요. 단 착수 전 4확인: `fred_macro_wide` 파생 5일 정체 · 계열별 시차 7~73일 불균질 · `macro_regime` 월말스탬프 마지막 행이 **진행 중인 달**이라 월중 조회 시 동월 look-ahead · flow 패널 43일 정체) · B 일별 축 정보 회수(PIT 최우선) · C 수리통계 구조 추정(ML의 음성 대조)
- **금지 4종(경로-scoped, INV-7)**: ML 결합기 · ML 사이징/selection · **표적이 "다음 달 평균 수익률"인 ML 라운드**(대조군으로만) · sweep 의 DSR 회피
- ★★**결합기 축 재분류 — settled-negative → 미측정(unmeasured) (2026-08-22, 도훈 권한 위임)**: 금지 ①(ML 결합기)의 근거가 **두 겹 모두 무효**임이 실측됐다 — ⓐ'126건' 은 실험 집계가 아니라 `hypothesis_signature` 버킷 라벨(본 세션 실측) ⓑ'동일 3짝 16+9' 는 codegen 치환의 이명 복제본이고 **결합 규칙 미실행**(2026-08-20 실측). 동시에 `FQ-237`(2026-08-22)이 **병목이 바로 이 마디에 있음을 실측**했다 — 선별 통계량 교체가 표적 통계량은 개선(Pearson IC t 3.18→3.77)했는데 PORT_t 는 악화(0.947→0.680) ⇒ 벽은 선별이 아니라 **결합·이산 top-N 소비 마디**. ⇒ **결합기 축은 '죽은 방향' 이 아니라 '측정된 적 없는 축' 으로 재분류**한다. **재진입 순서 강제**: ①먼저 **비-ML 결합 규칙** 사전등록 비교(FQ-237 NP1) — 비-ML 로 전이가 개선되면 ML 불요 ②그래도 미달일 때만 ML 결합기 라운드를 **사전등록·비-sweep**(argmax 선택 시 DSR ≥0.5 HARD)으로 허용 ③치환-제외 클린셋(50건) 재판독에서 동일 클러스터가 재현되면 **negative 복권**. 사이징/selection(②)·평균 표적(③) 금지는 **불변**(별도 실측 근거 보유)
- ★**금지 4종 범위 명시 (2026-08-22, 도훈 권한 위임)**: 금지는 **ML 의 용도 3종**(결합기 · 사이징/selection · 평균 표적)과 sweep DSR 회피에 걸린다. **ML 을 분포-표적 예측기로 쓰는 것은 금지 대상이 아니며 v8.4 주력 레인 ① 그 자체다** — 조건부 분위(pinball) · 예측 분포(NGBoost) · 꼬리초과확률 · CRPS 채점 · conformal 보정은 전부 허용. 위 08-22 근거 정정과 함께 읽을 것
- ★**자유도 분리의 상호작용 예외 (2026-08-22 신설, 도훈 권한 위임)**: "피처 교체와 표적 교체를 같은 라운드에 섞지 말 것" 은 판정 청결을 위한 규칙이나, 그대로 두면 **상호작용이 설계상 영구 미측정**이 된다(Lane A = 같은 월간 피처에 표적만 교체 → powered null / Lane B = 표적 고정에 피처만 일별로 → 평균 공간 효과없음 · 분포 공간 양성). ⇒ **두 주변부가 각각 독립 라운드로 측정된 뒤에는 상호작용 라운드를 허용**한다. 요건 3종: ①두 주변부 라운드의 round_id 와 판정을 명시 인용 ②상호작용 가설을 별도 사전등록 ③주변부 대비 증분을 paired 로 보고. 근거 = 2026-08-22 Lane A(FQ-233/241) · Lane B(FQ-234) 양 주변부 측정 완료
- **불변**: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent · Production Constraints(INV-7) · governor 수동 · v8.3 골격(dual-basis·프론티어 큐·지식 환류)

**v8.3 핵심 (알파 발굴 중심 재편, 도훈 mandate 2026-07-10)** — SOT `02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md`:
- **벽-정합 측정**: alpha 단계 선별 1급 지표 = canonical PORT_t(실측, IC는 advisory) — IC→PORT_t 전이 벽 정합. **dual-basis 진단**: cap-w HARD 판정 불변 + 기각 전 EW-유니버스 대비·cap-tier(MEGA/MID) 분해 확인 의무(post-2017 감쇠의 상당부분 = mega-cap 벤치 아티팩트 실측)
- **상설 프론티어 큐**: `06_Registry/alpha_frontier_queue.json` = "다음에 뭘 시도할지" SOT. 발굴 착수 전 hypothesis_index lookup + 큐 확인·owner 표기 의무. `dohoon_decision` 항목 세션 임의 착수 금지
- **지식 환류 수리**: hypothesis_index in-flight WT 인덱싱(병렬 중복실행 방지) · 주입면 frontier 현행화(settled-negative 광고 제거) · revival 발화 세션 도달 · screen-tier 회수 배관(dead 라벨 정리)
- **불변**: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent(슬림화 재제안 금지) · Production Constraints(INV-7) · governor 수동
- **텔레그램 v7 동반**: 비전공자 가독 3장치(쉬운 설명 섹션 + 판정 평문 + 자동 용어풀이 footer), 전문용어 유지

**v8.1 핵심 (흡수 — 8불릿 상세는 CHANGELOG_constitution.md 이관 아카이브 + `qvest_v8_1_sot.md`)**: 3-Mode 헌법(alpha-search **논문 완전 복제** + 유니버스 K200∪KQ150 고정 + 기간 2005~ 고정 · FR Lane3 · Axiom r7 복원) + 실측-only 거버넌스(measurement-graduation) + `register_module` 표준화·자동흐름(자본게이트 book confirm+실주문 2버튼만 수동).
**KR 데이터 한계 reference**: value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~ (`feedback-alpha-search-paper-replication`)

**★ Active SOT (단일 진실)**: `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md` (**v8.4 비대칭 재편 SOT** — 주력 레인 정본) + `qvest_v8_1_sot.md` (v8.1 설계 SOT) + `qvest_v8_3_alpha_discovery_sot.md` (v8.3 발굴 재편 SOT — 골격 승계, 도달 경로 ①만 해제) + `qvest_ast_v1_1_sot.md` (**AST 계층 v1.1** — 2026-07-25 도훈 승인: alpha 3층 스펙(AST-우선+escape 리프 4종)·PIT 3중 구조 예방·구조특징 사전분포. field_dictionary = `06_Registry/ast_field_map_v0.json`. C4 연간=3/31 확정) + `qvest_v8_0_upgrade_plan.md` (v8.0 base 흡수, retain)
**전임 SOT (흡수됨)**: `02_Infrastructure/docs/qvest_v6_4_sot.md` (v6.4 base 흡수, read-only retain)
**Legacy boundary**: `02_Infrastructure/docs/qvest_legacy_boundary.md` (v55 / S0~S7 격리)

본 CLAUDE.md는 헌법만. 절차는 `.claude/skills/`, 룰은 2단(`코어 6 = .claude/rules/ autoload` + `확장 11 = 02_Infrastructure/docs/rules/ on-demand` — 아래 Rules 절), 강제는 `02_Infrastructure/hooks/`, 역할은 `.claude/agents/`.

---

## Active Modes (4-Mode — 각자 평가·자가발전, 도훈 mandate 2026-06-05 / RAMP 추가 2026-06-17)

Qvest = 독립 리서치 모드 4개 (lifecycle ①②생산 → ③④소비; 진입점은 아래 `## Active Entrypoints`).
**각 모드 = 자기 평가체계 + 자기 자가발전** (L-code → mode-local axiom `AX-<MODE>-*`, `02_Infrastructure/docs/rules/axiom-engine.md` v8.0 E2E 검증). **평가체계(산출물 채점)는 모드별 자율 — 통일 금지.** 공유하는 건 *평가가 아니라 토대*: ① 정직 라벨 (`metric_type` proxy/backtested) ② 자본 게이트 (`book_state` = governor 수동+도훈) ③ **교차검증 global 공리** (자가발전 결과 중 backtested + r7 5축 + AX-008 + 도훈 confirm 통과분만 `AX-NNN`; 공유 *사실*이지 평가 통일 아님 — proxy·한 모드 loose 평가는 INV-1로 global 차단). SOT: `02_Infrastructure/docs/qvest_modes_sot.md`.

**① QEPM 모드 경로** (신호-only 알파 정밀 검증·편입):
```
WorkTask → [alpha-hypothesis] → alpha-research → risk-research → optimizer-research → forge → judge → governor
             └ 가설설계 구간(fable)  └────────────── 이하 전부 opus (Opus 5) ──────────────┘
```
**모델 라우팅 (2026-08-08 도훈 지시)**: `alpha-hypothesis`(Step 0 발굴 + ①메커니즘→②가설→③반증→④국면 경계) **만 `model: fable`**, QEPM 나머지 전 에이전트 `model: opus`. alpha-hypothesis 는 alpha-research의 *내부 구간 분리*이지 7번째 심사 단계가 아니다(6-agent 구조 불변 — 슬림화/확장 재제안 아님). 핸드오프 = `alpha_hypothesis.json`(alpha-research 가 승계, 재작성 금지). 상세 SOT: `02_Infrastructure/docs/rules/caching.md` 모델 라우팅 절.
각 agent spawn 시 **Self-Adversarial Challenge 의무** (v8.2 — Codex Round 제거, 메인 세션 모델(정본 = Active Version 절) 자체 적대검증: finalize 직전 약점 자가제기 → `challenge_note.md` 기록 → final. AX-008 3-source 중 1개).
**② alpha-search · ③ factor-rotation**: 각자 경량 경로 (각 skill + `## Active Entrypoints`).
**④ RAMP** (K-RAMP, 2026-06-17): 기존 전략풀 *소비* → 순수팩터 추출(통계 잠재팩터+FWL) → 팩터군 → M-code(역할 분업) → 리스크매니저 → 인베스터 에이전트 팩터배분. 거버넌스-우선 Gate 0~11 + CCS 13-score. 재귀 자가발전=Axiom 엔진 4번째 모드(modecode RAMP, backtested). 룰 `02_Infrastructure/docs/rules/ramp.md`, SOT `00_Lawbook/K_RAMP/`. governor 정지(자본 수동).

---

## Session Startup (MANDATORY)

새 세션 시작 시:
```
/qvest
```
Qvest 시스템 전체 구동. bootstrap.sh 실행 → 플러그인 리로드 → gap 확인.

## Session End (MANDATORY)

세션 종료 시:
- 메모리 파일 modified 시 `# 최종 업데이트:` date 갱신
- 새 L-code 추가 시 **아티팩트 emit → harvester 재수확** + MEMORY.md 헤더 갱신 (2026-07-25 도훈 승인 정정 — 구 표기 `methodology_active.md 등재`는 **부재 파일** 지시였음. 해당 md는 `methodology_archive.md`·`qepm/memory/methodology_memory.md`와 함께 저장소·메모리 어디에도 없으며, 현행 적립 경로는 `l_code*.json` 아티팩트 → `02_Infrastructure/axiom/lcode_harvester.py` → `.cache/lcode_corpus.json` → `02_Infrastructure/ops/build_knowledge_index.R` → `06_Registry/knowledge_index.json`. harvester 스캔범위 = 루트 `stage_artifacts/` + `04_Research/strategies/*/stage_artifacts/`. **2026-08-13 경로 정정** — 구 표기 `ops/build_knowledge_index.R` 은 **최상위 `ops/` 자체가 부재**라 실행되지 않는다(07-25 정정이 고친 것과 같은 계통의 경로 오기). ★**검색면(`hypothesis_index`)은 별개 빌더**다: `Rscript 02_Infrastructure/tools/hypothesis_index.R build` — **`build` 서브커맨드 필수**. 인자 없이 부르면 usage 만 찍고 **exit 0** 이라 호출자가 재빌드된 줄 오인한다(2026-08-13 실측: L-code 3건이 corpus 492 에는 들어갔는데 index 1204 에는 없었고, 인자 부여 후 1213 으로 회복). 적립은 **corpus 수확 + index build 둘 다** 해야 다음 라운드 Step 0 lookup 에 도달한다)
- infra 변경 시 관련 SOT/rules 문서 갱신 + 메모리 적립 (구 `infrastructure_state.md` 참조는 파일 부재 확인으로 2026-07-18 정정 — 도훈 승인)

---

## Core Rules

- **R + Python 공히 1급 허용** (v8.0, 2026-05-29 도훈 mandate — 기존 "R only" 폐지). 언어 선택은 도구적: R(tidyverse + data.table) / Python(venv `qvest_ml`). **PIT C1~C15 / Backtest Contract v1.0 / Production Constraints / lockbox-scope는 언어 무관 동일 적용.** Python backtest는 검증된 표준함수만(자체합성 금지) + 10-component `bt_result`는 R `build_bt_result` bridge 경유. 상세: `.claude/rules/python-policy.md`
- **NEVER modify** `05_Production/`, `01_Literature/`
- All output to `04_Research/` and `06_Registry/`
- Korean semi-formal tone (존댓말). User = Dohoon Kim (도훈), calls me "Q"

## 병렬 에이전트 실행 규칙

- 독립적 작업 2건+ → Agent tool 병렬 spawn 필수
- RAM 80% 이하 시 추가 spawn
- 코드 작성과 실행 분리 (메인 작성 → background spawn → 즉시 다음)
- Stage Gate artifact 작성은 메인 직접 (서브 위임 금지)

---

## Active Entrypoints

**4 리서치 모드** (도훈 mandate): ① **QEPM**(6-에이전트 풀파이프라인, `/worktask`) — 모듈 생산 · ② **alpha-search**(논문 1편 경량 검증, `/alpha-search`) — 모듈 생산 · ③ **factor-rotation**(국면조건부 모듈 배합 meta-layer, `/factor-rotation`) — 모듈 *소비* · ④ **RAMP**(K-RAMP, 기존 전략풀에서 순수팩터→팩터군→M-code→인베스터 에이전트 팩터배분, `/ramp`) — 풀 *소비* + 거버넌스-우선 Gate 0~11. ②③ 산출물은 `register_module()` 경유 표준화되며, 계약 floor 통과분만 ③④가 소비한다.

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask 생성 + 상태 + 전이 + admission (QEPM 모드) |
| `/alpha-search` | 논문/가설 경량 백테 검증 (alpha-search 모드) |
| `/factor-rotation <track>` | 국면조건부 모듈 배합 FR_XXXX (factor-rotation 모드. track∈{regime-engine, allocation}) |
| `/ramp <stage>` | K-RAMP 팩터배분 운용체계 RAMP_XXXX (RAMP 모드. Gate 0~11·CCS 13-score·실측-only·governor 정지. 룰 `docs/rules/ramp.md`) |

---

## Absolute Rules (1줄 reference)

- **PIT C1~C15**: `.claude/rules/pit.md`
- **Lockbox / Frozen Alpha Scope**: `02_Infrastructure/docs/rules/lockbox-scope.md` (정규 리서치 alpha/risk/optimizer만 적용. forge/monitoring/Q-Lead/execution = 폐기. 도훈 mandate 2026-05-09)
- **Self-Adversarial Challenge (Codex Round 대체)**: `02_Infrastructure/docs/rules/codex-round.md` (v8.2 — 외부 Codex Round 제거, 메인 세션 모델(정본 = Active Version 절) 자체 적대검증으로 finalize 직전 약점 자가제기 + `challenge_note.md` 기록. AX-008 3-source 중 1개)
- **Backtest Result Contract v1.0**: `.claude/rules/backtest-contract.md` (PerformanceAnalytics 표준 함수만)
- **Measurement Integrity + Graduation 허들 (v8.x)**: `.claude/rules/measurement-graduation.md` ⭐ (위반 = AX-002 동급. 실측 처리(canonical_screen_bt/build_bt_result + metric_type 라벨, proxy 손계산 금지) / portfolio-alpha t = forge-authoritative(NW lag-3) / graduation severity: PORT_t 2.95·DSR hard, rank-IC계열 advisory / admission = book-marginal ΔIR≥0.05 / DPL 구성레이어. E2E: FLOW proxy 3.55→forge 2.35)
- **Axiom Engine 2-Tier (v8.0)**: `02_Infrastructure/docs/rules/axiom-engine.md` ⭐ (원전 r7 복원 + 3-mode 2-tier(AS proxy→mode-local / QPM·FR backtested→global) + INV-1~7. mode-local AX-&lt;MODE&gt;-NNN / global AX-NNN. negative=provisional failure-ledger. 자동승격=documented·hook block은 주간 confirm. E2E 10/10. 위반=AX-002 동급)
- **Qvest 답변 원칙 (8원칙 + 5금지)**: `.claude/rules/answer-principles.md` (위반 = AX-002 동급)
- **Continuity Firewall (포기 원천차단, 2026-07-15 도훈 mandate)**: `02_Infrastructure/docs/rules/continuity-firewall.md` ⭐ (누적 실패 후 '끝남 표현'으로 라운드 마감 = Stop 훅 **block 강제속행**. 4레이어: L1 차단 실효 + L2 독립 semantic 판정(`continuity_gate.py`) + L3 건설적 종료계약(`close_round()` — next_probe≥2·소비면·부활조건 강제) + L4 자가발전(`continuity_cases.json`). ★어휘가 아니라 계약이 게이트 — 종결 단어를 지워도 통과 못 함, 계속을 *생산*해야 함. 판정 자체는 불차단(AX-000·INV-7 정합). 위반 = AX-002 동급)
- **Telegram v7 SOT**: `.claude/skills/qvest-telegram/SKILL.md` (단일 규칙. `tg_agent_brief()` 진입점, 약어 풀이 + **비전공자 3장치**(쉬운 설명 섹션·판정 평문·자동 용어풀이 footer — 전문용어 유지) 자동, 표준 5섹션 권장)
- **Caching + Model Routing Discipline**: `02_Infrastructure/docs/rules/caching.md` (2026-07-24 Fable 5 개정 — 1h TTL 실측·모델 핀 제거/상속·폴백 opus·wakeup은 대상-기반, 구 ≤270s 규칙 폐기)
- **Harness Engineering (Hooks Tier 1~6)**: `02_Infrastructure/docs/rules/harness.md`
- **Factor DB + Forge 자원**: `02_Infrastructure/docs/rules/factor-db.md` (C13~C15 + load_month_factors 경유)
- **Axioms (AX-000~008)**: `.claude/rules/axioms.md`
- **R 측 Windows 이식성 계약**: `02_Infrastructure/docs/rules/r-portability.md` ⭐ (2026-07-25 도훈 "승격해". 금칙 6종 — ①`system2(env=)`(환경변수 아닌 **인자 주입**) ②스크립트 최상위 `on.exit()`(**미발화** → cleanup dead code) ③선행 `/` 경로 하드코딩·`startsWith(p,"/")` 절대경로 판정·루트를 `dir.exists()`로 신뢰 ④resolver 우선순위는 `CLAUDE_PROJECT_DIR` 먼저 ⑤`system()/system2()` 문자열에 쉘 리다이렉션·`&&` 주입(**셸 미경유 → 리터럴 argv**. 2026-08-02 추가 — 빈 출력이 '변경 없음'으로 읽혀 `git_dirty` 79건 위장) ⑥`regmatches`를 **TRE 색인** 위에서 사용(2026-08-02 추가 — Windows TRE는 매치 위치를 **UTF-16 코드유닛**으로 보고하는데 `regmatches`/`substr`은 **코드포인트**로 자름 → 매치 **앞**의 이모지 1개당 추출 창 1칸 밀림. **길이는 맞아 오류가 아니라 그럴듯한 쓰레기**가 나옴. `perl=`/`fixed=`/`useBytes=TRUE`로 회피. ★**count-only는 위반 아님** — 밀리는 건 위치이지 개수가 아님). 공통 기전 = **존재 검사로 정체성 검사 대체 / 결손을 정상값으로 내려앉힘**(⑥만 반대 방향 = **정상값 모양의 오답**). 강제 = `08_Tests/hooks/test_r_portability.R`(baseline 래칫 69건 + 금칙⑥ 개수 래칫 44 site/19 파일 + 위반 주입 12종, suite 22/22) + `08_Tests/hooks/test_lineage_git_state.R`(행동 수준 11/11, 돌연변이로 검출력 실증), 둘 다 배터리 편입. 위반 = AX-002 동급)
- **Research Philosophy (7 QEPM Modern Trends)**: `02_Infrastructure/docs/rules/research_philosophy.md` ⭐ (Charter-level SOT `02_Infrastructure/docs/qvest_research_philosophy.md` v1.0 2026-05-14. Factor Zoo 축소 / Cost-aware / Uncertainty-aware / Direct Portfolio / Crowding / Implementation / Attribution. 분기별 review + trigger-based 보강. 위반 = AX-002 동급)

---

## Project Goals

### 존재의의: 이 시스템은 알파시킹 기계다 (도훈 mandate 2026-08-02)

프로세스·하네스·게이트·거버넌스는 **알파 발굴을 신뢰할 수 있게 만드는 수단**이지 목적이 아니다. 세션 자원 배분의 기본값은 **알파 라운드 전진**(FQ 큐 소비·가설 실측·판정)이며, 인프라 작업은 ① 알파 라운드를 실제로 막는 결함 ② 측정 신뢰를 훼손하는 결함(PIT/proxy/침묵 실패)에 한정해 즉시 수리하고, 그 외 위생성 개선은 태스크 분리(chip)로 넘긴다. 가용 사이클이 생기면 "인프라를 더 다듬을까"가 아니라 "다음 알파 가설이 무엇인가"를 먼저 묻는다.

### 제1목표: 미래참조 없는 전략 설계 (PIT 완전 준수) — 성과보다 우선

### 제2목표: SR 2.5+ / CAGR 16%+ / MDD <25% (SR 2.0→2.5 상향, 2026-05-29 도훈 mandate — KR 구조적 상승 반영)

도달 경로 (**2026-08-13 v8.4 재편 — 도훈 mandate**. 구 2026-07-10 v8.3 순위 대체): ① **비대칭 알파 도출**(기존 데이터풀 총동원 + ML·수리통계·**매크로**. 표적을 **평균 → 분포**로 교체 — 조건부 분위·왜도·꼬리초과확률. 4 lane = A 분포-표적 학습 / D 매크로 상태 조건부 / B 일별 축 회수 / C 수리통계 구조추정. SOT `qvest_v8_4_asymmetry_ml_sot.md`) ② **screen-tier 재고 회수 + EW-대비/cap-tier 재분류**(overlay 큐 드레인 · 벤치-아티팩트 기각 후보 재라우팅, FQ-006~008) ③ overlay 잔여 정교화(실증 유일 β 레버이나 clean 잔여폭 좁음 — 07-05/06 양방향 negative 실측).
**주력에서 해제 (2026-08-13 도훈 지시, 구 ①)**: 비-return 신규 원천 FQ-001~005 — 2건은 **도훈이 데이터 게이트를 닫았고**(08-09 공매도/신용대차), 3건은 실측 negative. ★구조 판결 아님, 부활 조건은 SOT §1(INV-7).
잔차-직교 sleeve 스태킹은 07-05 RAMP R1 config-scoped 미달(survivors 0, §6) — 구조판결 아님·frontier 조건부. 신규 standalone **평균-표적** return-파생 팩터 사냥은 16/16 FAIL posterior + factor DB 331 전수 book-marginal 통과 0으로 최후순위(계열 15종이 구속 해상도).

### 제약 (방침)

- 기존 인프라 극한 활용 (Factor DB / DART / FRED / ECOS / QuantiWise)
- 크로스마켓 / 대체데이터 금지
- 확장 허용: ML / 수리통계 / 물리학 / 카오스이론

---

## Production Constraints

<!-- FRONTIER_AXES_START — 기계 앵커(2026-08-17). axiom_context_inject.sh 가 이 구간을 런타임 파싱해 에이전트 주입면의 '봉투 안 레버 프론티어' 줄을 만든다. 캐시 없음 = 이 줄을 고치면 다음 spawn 부터 즉시 반영. 마커 삭제/이동 시 훅은 하드코딩 폴백으로 떨어지고(회귀 없음) 08_Tests/hooks/test_frontier_axes_derive.sh 가 FAIL 한다. -->
> **★이것은 배포 현실이 정의한 문제의 고정 축이다 — 최적화로 없앨 변수가 아니다.** AX-000 따름정리: 이 봉투 *안에서* 풀어라; 제약 완화(>25종·short 허용·유동성 하향 등)를 레버로 제시하는 것은 게임을 이기는 게 아니라 바꾸는 것이다(실패지식 제약 방화벽 — `02_Infrastructure/docs/rules/axiom-engine.md` INV-7). 조건-안 레버만 프론티어 — 현행(**2026-08-13 v8.4 갱신**): ① **비대칭 표적**(분포-표적 학습 · 일별 축 정보 회수 · 수리통계 구조 추정 — 주력) ② screen-tier 재고 회수(overlay 큐) ③ EW-대비/cap-tier 재분류 ④ overlay 잔여·잔차sleeve(조건부)·multi-sleeve·composite. ★**2026-08-22 추가 — 현행 최우선 병목 = 분포-표적 소비 계약 부재**: 세 라운드(FQ-236 매크로 · FQ-233/241 월간팩터 320종 · FQ-234 일별 flow)가 서로 다른 데이터 축에서 독립 수렴 — **신호는 분포(중앙값·왜도)에 있고 소비면은 평균을 읽는다**(각각 flow채널 t +2.98 인데 분포귀결 부재 / cor(왜도기울기, 중앙값−평균 gap) −0.728 청정창 유지 / 중앙값 직교화 t 3.55 vs 평균 t 0.21). `screen_route` 에 `DISTRIBUTION_TARGET` 신설했으나(measurement-graduation.md §3) `canonical_screen_bt` 의 **분위-표적 측정 계약은 미구현** ⇒ 계약 신설이 리서치보다 선행한다. **DPL(06-26)·regime-conditional 교차결합(07-05)·ML/uncertainty sizing(07-05 2세션)은 settled-negative 실측 — 레버 아님**(부활신호 발화 시에만 재검토, INV-7).
⚠**①이 과거 ML 실패의 부활이 아님을 구분할 것**: 죽은 것은 ML 을 **결합기·사이징·평균 예측기**로 쓴 경로(126건 실측)이고, ①은 **표적 자체를 분포로 바꾸는** 미측정 축이다. 표적이 "다음 달 평균 수익률"인 ML 라운드는 **금지**(대조군으로만 등장) — SOT §6 금지 4종.
<!-- FRONTIER_AXES_END -->

| 제약 | 값 |
|---|---|
| 종목수 | max 25 (hook 강제, 도훈 mandate 2026-05-29 20→25) |
| 유동성 | 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD) |
| Long-only | weights ≥ 0 |
| Weight bounds | [0, 0.20] |
| Σw | = 1 (absolute) |
| Universe | KOSPI200 ∪ KOSDAQ150 |
| Transaction cost | 15bps one-way (cost_model_version v2.4_kr_retail_15bps — delta-based, 종목별 Δ보유명목 절대값에 레그당 과금. 2026-06-11 도훈 confirm. 구 v2.3 flat 기록과 비교 시 라벨 확인) |
| PIT | C1~C15 전체 (`.claude/rules/pit.md`) |

---

## Key Paths

- Project root: `C:/Users/99922/OneDrive/Quant_Module_Moltbot/` (OneDrive canonical, 도훈 mandate 2026-06-10. Git Bash: `/c/Users/99922/OneDrive/Quant_Module_Moltbot`)
- Infrastructure: `02_Infrastructure/` (config.R + 12 subdirs: data/ factor_db/ regime/ validation/ hooks/ agents/ telegram/ reports/ memory/ portfolio/ ops/ docs/ worktask/ contracts/ tools/ axiom/ prompts/)
- Strategies: `04_Research/strategies/STR_XXX_name/` (legacy retain)
- WT mailbox: `qepm/mailbox/worktask/{WT_ID}/`
- Stage artifacts: `stage_artifacts/WT_{ID}/`
- Memory: `C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/MEMORY.md`
- Env (User scope 영구): `QM_ROOT` + `QVEST_PY` + `~/.Renviron` 동일값 (경로 이전 시 이 3곳 + config.R 후보만 갱신)
- 산출물 저장 위치 규칙 (저장 4원칙 + 루트 13항목 고정 + retention): `02_Infrastructure/docs/rules/artifact-storage.md`

---

## R Execution Pattern

- `source('run_all.R')` pattern only (한글 path encoding 회피, NOT `--file=`)
- `cd` to strategy directory first, then `Rscript -e 'source("run_all.R")'`

---

## Multi-Agent Summary (v8.1 active 6 + 4 ondemand)

| Agent | 위치 | 역할 |
|---|---|---|
| **Q-Lead** | 메인 Claude 세션 (유일) | 오케스트레이션, agent spawn, memory commit, telegram 보고 |
| **alpha-hypothesis** ⭐fable | Agent tool | **가설설계 전담** (Step 0 발굴 + ①메커니즘 →②가설 →③반증 →④국면 경계) → `alpha_hypothesis.json`. ⑤AST·팩터 소싱·실측 금지 |
| **alpha-research** | Agent tool | α̂ 생성 (⑤AST 구성 + factor specs + ICIR + Harvey-t). 가설 승계(재작성 금지). Σ/weight 절대 금지 |
| **risk-research** | Agent tool | Σ + tail + stress + crowding + style. alpha 수정 금지 |
| **optimizer-research** | Agent tool | weights 결정 (MVO/HRP/CVaR/etc 자율). alpha/risk 재해석 금지 |
| **forge** | Agent tool | run_all.R + backtest 통합 (Pure function). target_weights/cov 수정 금지 |
| **judge** | Agent tool | Gate 0~18 + PIT 검증 |
| **governor** | Agent tool | PG0~PG3 admission + book_state |
| architect | Agent tool (ondemand) | 인프라 진단 |
| blender | Agent tool (ondemand) | 국면 배분 (Grade A 4건+ 시) |
| execution | Agent tool (ondemand) | TWAP/VWAP schedule (deployment 시) |
| monitoring | Agent tool (ondemand / cron) | live drift 월간 |

상세 절차: `.claude/skills/qvest-worktask/SKILL.md`

---

## Axioms (Level 0 — 요약)

전체: `.claude/rules/axioms.md` 또는 `_shared_prefix.md`

```
계층: AX-code (Lv0) > PIT C1-C15 (Lv1) > L-code (Lv2) > Signals (Lv3)
```

- **AX-000** [IMMUTABLE]: 한계는 법칙 아닌 방법의 한계 — 모든 목표는 엄밀함·창의성·반복으로 달성 가능. **3~4회 실패로 한계/dead-end 단정 금지**; 모든 수단 소진 또는 도훈 중단 지시까지 탐색 계속. 실측·PIT 결과는 정직 보고하되 탐색 중단 근거 아님 (2026-06-21 개정)
  - **따름정리(제약=고정 축, 2026-07-04)**: Production Constraints(고정 제약 7종+PIT)는 **문제의 고정 축이지 실패의 원인/레버가 아니다** — 실패를 제약에 귀속하거나 제약 완화를 레버로 제시 금지(실패지식 제약 방화벽, axiom-engine INV-7). 창의 부담은 봉투-안 방법에.
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터 조건부 평가 (crisis_alpha + Core 대비 MDD + bad/normal IC ratio)
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조
- **AX-003 / AX-004 / AX-005 / AX-007** [Distilled 강등 2026-07-05 — active Law 아님]: negative 공리 4종은 Distilled 탐색지도 이관(INV-7 재도전 대상, enforcement 대상 아님). 상세: `.claude/rules/axioms.md` Demoted 절 (DIST-QPM-006 / QPM-003 / AR-001 / AR-003)
- **AX-008** [process]: Verification Triangulation (Forge + Self-Adversarial + Architect 2/3 PASS)

위반 시 즉시 중단. Hook `axiom_enforcement_hook.sh` 자동 차단.

---

## Q-Lead 역할 경계 (Level 0)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / telegram 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (역할경계·lockbox 훅은 agent marker 존재 시에만 발화 — marker 자동 기록 메커니즘 부재. 실제 방어선 = R 계약(essence_score/registry_writer) + 게이트급 훅 + 수동 confirm. 2026-07-03 도훈 confirm, 아키텍처 감사)

---

## qepm 하이브리드 모드 (Q-Lead 전용)

```bash
cd qepm && Rscript -e 'source("scripts/hybrid_mode.R")'
```

주요 함수: `hybrid_commit()` / `hybrid_status()` / `hybrid_queue()` / `hybrid_daily_digest()`

---

## Slash Commands (`.claude/commands/`)

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask CRUD |
| `/alpha-search` · `/factor-rotation` · `/ramp` | 모드 진입 (Active Entrypoints 표 참조) |
| `/qlead` | Q-Lead session dashboard |
| (삭제 이력) | 커맨드 래퍼 8종 삭제(2026-07-05 `/forge` 등 7종 · 2026-06-10 `/scout`) — **동명 AGENT(.claude/agents/)·HOOK·SKILL은 현역 유지**. 상세 = DEPRECATION.md·CHANGELOG_constitution.md |

---

## Skills + Rules

### Skills (`.claude/skills/`) — domain-scoped

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WorkTask lifecycle 절차 (CLAUDE.md에서 이동) |
| `qvest-telegram` | 텔레그램 단일 SOT (v6) — 양식 / 약어 풀이 / Hook 정책 / caller 예시 통합 |
| (Phase 9 추가 예정) | qvest-hook-debug / qvest-cert-paths |

### Rules — 2단 구조 (2026-06-10 P2 다이어트: autoload 16→6)

**코어 6 (`.claude/rules/` — 매 세션 autoload)**: `pit.md` (C1~C15) · `axioms.md` (AX-000~008) · `answer-principles.md` (8원칙+5금지) · `backtest-contract.md` (bt_result 10-component) · `measurement-graduation.md` (게이트 2계층+HARD) · `python-policy.md` (R/Python 1급)

**확장 11 (`02_Infrastructure/docs/rules/` — 해당 작업 시 on-demand Read, 효력 동일. v8.2 codex-round.md = DEPRECATED 스텁)**:

| Rule | 로드 시점 |
|---|---|
| `harness.md` | hook 디버깅 시 (qvest-hook-debug skill) |
| `axiom-engine.md` | axiom 승격/주간 파이프라인 작업 시 |
| `factor-rotation.md` | factor-rotation 모드 진입 시 (SKILL이 참조) |
| `lockbox-scope.md` | lockbox 판단 시 (pit.md에 요약 잔존) |
| `factor-db.md` | factor DB 직접 작업 시 |
| `data_table_shift_convention.md` | shift/forward label 작성 시 (pit.md C-체크 연계) |
| `artifact-naming.md` | WT 핸드오프 파일 생성 시 |
| `artifact-storage.md` | 산출물 저장 위치 판단 시 |
| `caching.md` | 토큰/캐시 운영 판단 시 |
| `research_philosophy.md` | 분기 review 시 (본문 SOT는 docs/qvest_research_philosophy.md) |
| `r-portability.md` | R에서 `system2`/`system` 호출 · cleanup 등록 · 프로젝트 루트 해석 코드를 쓸 때 |

---

## Safety Rules

- NEVER modify `05_Production/` (promote_to_production() 만 예외)
- `01_Literature/` read-only
- All output to `04_Research/` and `06_Registry/`
- 기존 stage_artifacts/ + 178+ STR 결과 보존
- legacy v55/S0-S7 **파이프라인 데이터·전략 결과** 격리 (삭제 X) — `qvest_legacy_boundary.md`. (단 s0-s7 stage *스킬* 8종 + v53/v55 커맨드 래퍼는 2026-07-05 미사용 확인 후 삭제 — 역사는 git·legacy_boundary 보존. 격리는 산출물/데이터 대상이지 dead 코드파일 대상 아님)

---

## Release Status + 변경 이력

**SOT 분리 (2026-06-10 P2 다이어트)**: 버전 연혁·릴리스 상세는 `02_Infrastructure/docs/CHANGELOG_constitution.md` — CLAUDE.md는 현행 헌법만 담는다.
- 현행: **v8.4** (2026-08-13 비대칭 알파 중심 재편 — 도훈 mandate, SOT `qvest_v8_4_asymmetry_ml_sot.md`. 비-return 주력 해제 + ML·수리통계 분포-표적 3 lane 신설, 큐 FQ-233/234/235). base = **v8.3** (2026-07-10 알파 발굴 중심 재편, SOT `qvest_v8_3_alpha_discovery_sot.md` — 골격 승계, 도달 경로 ①만 해제) + **2026-07-24 Fable 5 정합 패치**(도훈 승인 C1/C5/C6 포함). 이전 버전·검증 이력 상세 = `CHANGELOG_constitution.md`.
- **현행 hook 등록 = settings.json 47 distinct .sh** (직접 29 + 라우터 dispatch 19 − 중복 `safety_guard` 1 = 47, **2026-08-16 실측 재산출** — `hypothesis_precheck_gate.sh` 라우터 dispatch 등재로 46→47. ★이 드리프트는 등재 2분 만에 `boot_currency_check.sh` C6 가 잡았다(선언 46 vs 실측 47) — 훅을 늘리면 이 줄도 함께 고칠 것. 구 46 분해는 2026-07-26 실측 — 2026-07-24 Fable 5 감사·C1~C10 실행(주입취약 4훅 env-경유·전달0 6종 복원·조기-exit·axiom주입 복원·dead 4건 해제) + **2026-07-25 `ast_spec_gate.sh` 등재**(AST v1.1 Step 3 기계 게이트). 배터리 15/15 PASS. 상세 `harness.md` 정합 절)

</details>

---

## alpha-search 제1원칙 근거 사건 아카이브 (2026-08-23 이관)

> v9 Lean Loop 감산으로 `.claude/skills/alpha-search/SKILL.md`(12KB → ≈4.5KB)에서 **사건 서사**만 이관.
> **원칙 자체는 SKILL.md 6불릿으로 현역 존치** — 여기 있는 건 그 6불릿이 왜 생겼는지의 근거 기록이다.

### 사건 1 — BSC(2015) faithful L/S 검증 → 롱숏 전면 불허 (도훈 mandate 2026-06-11)

- 경위: BSC(Bali-Subrahmanyam-Chabi-Yo 2015) 논문을 **논문대로** L/S 2×3 VW 구조로 충실 복제해
  검증(`STR_AS_BSC_20260611_153021`)했고, 그 직후 도훈이 정정했다.
- 정정 내용: 기존 "L/S는 논문대로" 조항을 **대체**한다 — 논문이 L/S여도 **검증 단계 포함 전면
  long-only로 사상**한다(long leg 기반, 스케일링류는 λ∈[0,1] 무레버리지 캡). 사상 사실과 논문
  원형과의 차이는 명시 보고하고, **L/S 수치는 판정 근거로 사용 금지**(산출했다면 진단 참고 라벨만).
- 이유: KR은 공매도 제약이 실투 조건이라 L/S 수치는 배포 가능한 형태의 성과가 아니다 —
  "논문 충실"과 "배포 가능"이 충돌하는 유일한 축이라 여기서만 원칙에 예외를 둔다.

### 사건 2 — residual momentum(Blitz-Huij-Martens 2011) 임의 변형 → 논문 완전 복제 원칙 성문화

- 경위: 잔차 모멘텀 논문 검증 중 Q-Lead가 종목수·비중·유니버스를 시스템 관습으로 임의 변형했다
  (**top20 · 순수스코어 가중 · KR_TOP500**). 도훈 정정: "논문 그대로 비중".
- 정정 내용: 팩터 구성 방법론(회귀 기간 예 36m · skip 예 11-1 · 표준화 · 윈도우 · 랭킹 방식),
  포트폴리오 비중(equal/value/decile/signal-proportional), 종목수·리밸 주기를 **논문 명시값 그대로**
  복제한다. 변형하면 그것은 논문 검증이 아니라 별개 전략이며 **검증 무효**다.
- 미명시 값만 시스템 표준으로 보충하고(PIT C1~C15 · 15bps · 유동성 2e8), 무엇을 보충했는지 명시한다.
- production constraint(max 25 등)와 논문(decile 등)이 충돌하면 **검증 단계는 논문 우선**,
  충돌 사실을 명시 보고한다(production 적용은 운용 단계 별도).

### 고정축 2종의 근거 (도훈 mandate 2026-06-05)

- **유니버스 K200∪KQ150 고정**: 외국 논문 유니버스(US NYSE/Russell/S&P)는 KR 직접 적용 불가
  (데이터 부재·시장구조 차이) → 모든 검증을 실투 유니버스로 고정(PIT 시변 멤버십). 소형주 논문도
  이 범위로 좁혀 검증한다(size effect 알파는 약화될 수 있으나 실투·비교 정합 우선).
  방법론·비중·종목수는 복제하되 **유니버스만** 단일 고정.
- **백테 기간 2005-01-01~ 고정**: KR value/재무 데이터 한계(book-to-market 2002-08~) + FF3 36m 회귀
  → FF 의존 전략 실효 2005-08. 가격 기반 전략은 1990~ 가능하나 비교 일관성 위해 2005 통일
  (factor DB `M08_Residual_Mom`은 1995~ 있어 2000 우회가 가능했으나 논문 FF3 복제 충실을 택함).

---

## Release Status (v6.4.0 → v8.4)

| Release | 일자 | 핵심 |
|---|---|---|
| ✅ **문서 정합 — INDEX 재동기** | 2026-08-16 | `00_Lawbook/INDEX.md` v8.1.0 3-Mode(2026-06-12) → **v8.4 4-Mode** 갱신 — 2개월·헌법 4회 전이(v8.2→v8.3→AST v1.1→v8.4)분 낙후 복구. 실측 대조로 **구판 오류 3건 적발**: `state_transitions.json` 위치 오기(`worktask/` → 실제 `02_Infrastructure/hooks/policies/`) · 텔레그램 경로 오기(`qepm/telegram/` → 실제 `02_Infrastructure/telegram/`) · `qepm/memory/methodology_memory.md`를 **부재 파일인데 존재하는 양 기재**. 갱신 내역: §0 헌법 계층 4단 신설(CLAUDE.md → `.claude/rules/` → `docs/rules/` → `00_Lawbook/`) · §1 SOT를 v8.4/v8.3/AST v1.1까지 확장 · §5 axiom **"8건(000~005,007,008)" → 실측 active 4건(000/001/002/008) + Distilled 강등 4건** · v8.3/v8.4 운영 SOT(`alpha_frontier_queue`·`layer_bottleneck_map`·`hypothesis_index`·`method_registry`·`continuity_cases`) 추가 · §7 Skills/Agents/Commands 신설 · Self-Adversarial 절 모델명 하드코딩 제거(CLAUDE.md Active Version 정본 위임). **낙후 기전 진단 = 개수 박제(`8 axioms`/`30 hook`/`203 paper notes`) + 경로 축약** → Maintenance에 규약 3종 명문화(숫자 박제 금지 / 루트 기준 전체 경로 / 갱신 후 경로 전수 검증). 검증: 문서 백틱 경로 72개 기계 추출 → 실참조 전부 존재. 파생 칩 `task_da53ea06`(확장 룰 축약 ~25건 정규화 + 문맥-인지 경로 검사기 — `harness.md`/`codex-round.md`의 `codex_round_contract.json` 위치 오기 포함). |
| ✅ **v8.4** | 2026-08-13 | **비대칭 알파 중심 재편** (도훈 mandate). 주력 교체: v8.3 도달 경로 ①(비-return 신규 원천)을 **주력에서 해제** → **기존 데이터풀 총동원 + ML·수리통계·매크로로 시장 비대칭 알파 도출**. 근거 = `ml_complexity` **126건 원장 재판독**에서 ML 트랙이 자본 게이트를 하나도 통과 못 함: **MDD ≤25% 충족 0/84** · **PORT_t ≥2.95 = 0/10**(범위 −1.377~2.362) · **oos_retention ≥0.7 = 2/17**(음수 10건·중앙 −0.481). 죽은 자리 = ①결합기(동일 3짝 metric 클러스터 16+9건 = 84의 30%) ②사이징/selection ③평균 예측기. ⚠**①의 기전 서술은 2026-08-20 반증됐다** — 그 클러스터는 "다른 결합 규칙이 같은 점을 낸다"가 아니라 **batch_434(06-12/13) keyword-fallback 치환 실행이 만든 이명 복제본**이다(ledger 0.493×16 → catalog `1cc257b9` 전원, 0.492×9 → `3be89a6f` 전원, **16/16·9/9 id 대응**). 결합 규칙은 실행된 적이 없으므로 이 클러스터를 근거로 한 "결합기 settled-negative"는 **INV-7 비유효 negative**다. 게이트-통과-0 자체는 유지될 공산이나 sharpe 84건 중 34건(40%)이 중복 그룹이라 **분모가 오염**됐다. 전수 = `04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820/`. ★**금지 4종 중 'ML 결합기'의 재검토는 도훈 판단 사항**(v8.4 SOT·CLAUDE.md 미반영 상태). ⇒ **표적을 평균 → 분포로 교체**(조건부 분위·왜도·꼬리초과확률). **4 lane**: A 분포-표적 학습(1순위, 평균-표적 대조군 동반 의무) · D 매크로 상태 조건부(2순위) · B 일별 축 정보 회수(PIT 최우선) · C 수리통계 구조 추정. **금지 4종**(경로-scoped, INV-7): ML 결합기 · ML 사이징/selection · 표적이 "다음 달 평균 수익률"인 ML 라운드(대조군으로만) · sweep의 DSR 회피. 큐 FQ-233/234/235/236. 불변: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent · Production Constraints(INV-7) · governor 수동 · v8.3 골격. SOT `qvest_v8_4_asymmetry_ml_sot.md`. ⚠**자기정정 6건 동반** — 초판의 "126건 전부가 평균 표적·분포 표적 0건"은 **근거 없음**(`key_metrics`에 표적 필드가 없어 셀 수 없고 metric 보유는 84/126). 정직 서술 = "분포를 표적으로 명시한 라운드를 찾지 못했다"(미발견이지 부재 증명 아님). |
| ✅ **AST 계층 v1.1 채택** | 2026-07-25 | 도훈 원안 v1.0 → 4-agent 실측 검증(wf_f40cca21) → 수정 6건(M1 escape 리프 4종·M2 registry 승격·M3 3중 구조 예방·M4 essence_score 사이드카·M5 judge advisory 한정·M6 N≥30) 반영 채택. **Step 0: C4 연간 availability = 익년 3/31 확정**(pit.md 개정 — 구 'annual 5월' 폐기, xlsx Q4 +45d는 수리 항목). field_dictionary = `06_Registry/ast_field_map_v0.json`(전 데이터 58그룹 실측 전수, wf_85fe98c6 — 부산물: 멤버십 2026-03-31 종점·벤치 date32 미병합·SJM 스테일 적발, 칩 2건 발행). SOT `qvest_ast_v1_1_sot.md`. graduation HARD 3종·6-agent·헌장 자율성 불변. |
| ✅ **v8.3 + Fable 5 정합 패치** | 2026-07-24 | Fable 5 하네스 전수 감사(57-agent 워크플로우 + 2-렌즈 적대검증, finding 115 = keep 45/변경 70) — 도훈 의뢰 "Fable 5 정합 + 과잉 훅/스킬/프롬프트 비판 점검". **모델**: 세션 = `claude-fable-5`, 에이전트 `model: opus` 핀 11종 전제거(무핀=상속, 폴백=한도 시 opus) · caching.md 전면 재작성(1h TTL·≤270s wakeup 폐기·TeamCreate/Codex 절 삭제). **훅**: 주입형 fail-open 하드게이트 4종 env-경유 수리 · 전달 0 훅 6종 additionalContext 복원(0ab8b039 회귀) · ★axiom_context_inject SyntaxError 수리(07-13 이후 Agent 공리주입 침묵 결손) · Read/W·E 조기-exit(비매치 Read 0.8→0.16s) · sr_provenance_pre_certifier dispatch 해제(no-op 실증) · milestone push 브랜치 버그 → 등록 48 distinct(직접 32+라우터 16), battery **11/11 PASS**. **스킬**: telegram-protocol 스텁·worktask 구스킬 삭제, style 스킬 게이트수치·DPL 광고 현행화, MG changelog 8.3KB·qvest.md Version 8KB 이관(autoload 다이어트). 보고서 `04_Research/01_reports/fable5_harness_audit_20260724.md`. **당일 도훈 승인·실행: C1**(codex 유령 플러그인 해제 — 미설치 실증, DEPRECATION.md 동시 개정) · **C5**(CLAUDE.md 역사 블록 → 본 파일 "이관 아카이브", 24.2→21.8KB) · **C6**(_shared_prefix 중복 스텁화 21.9→15.2KB — answer_principles/backtest_contract 포인터화·stage_order/s0_debate 삭제·telegram v7 스텁, health Hard 0). **C2~C4·C7~C10도 07-25 도훈 일괄 승인·실행** — C2 Read 훅 2건·C9 SubagentStop 해제(→ 등록 45 distinct = 직접 29+라우터 16) · C10 milestone legacy 레인 제거 · C7 exec/mon opus 재핀(예외 2종) · C3 skillOverrides(off 2+user-invocable 3 스텁) · C4 inverse-miner 재작성 · C8 스케줄러 opus 폴백. battery 11/11·harness_health 27/27. **C1~C10 전량 실행 — 감사 큐 소화**. |
| ✅ **v8.3** | 2026-07-10 | 알파 발굴 중심 재편 (도훈 mandate "실제 알파를 발굴하기 위한 목적으로 아키텍처 재편"). 5축 병렬 조사 → 마찰점 F1~F10 → move M1~M11: **M1** alpha 단계 selection_objective에 canonical_port_t 1급 추가(IC advisory 강등, stale 졸업기준 measurement-graduation §3 정합화) · **M2** canonical_screen_bt에 diag_ew_universe/diag_cap_tier 비파괴 진단(cap-w HARD 권위 불변) · **M5** 상설 frontier 큐 `06_Registry/alpha_frontier_queue.json` · **M6** hypothesis_index in-flight WT 인덱싱 · **M7** 주입면 현행화(settled-neg frontier 광고 제거+revival 주입) · **M8 경량** DPL_FEATURE 발급 중단·FR_RCMA 조건부화 · **M9** cluster_extractor 스키마 보존 · **M4** 인입 체인 백로그 합류+침묵정지 경보화. 불변: HARD 3종·6-agent·Production Constraints·governor 수동. 동반: 텔레그램 v7(비전공자 3장치, 전문용어 유지). SOT `qvest_v8_3_alpha_discovery_sot.md`. |
| ✅ **v8.2** | 2026-06-30 | Codex Critic Round 제거 — Opus 4.8 자체 적대검증(self-adversarial challenge)으로 중복, AX-008 Codex→Self-Adversarial 치환(3-source 2/3 불변). QEPM 5단계 draft→codex→challenge_note→final → in-agent self-adversarial. 자산 archive(`_archive_codex_round_v8_2/`) + `qvest-codex-round` skill DELETED. S0 Debate codex·RAMP Codex·codex CLI 플러그인은 별개 유지. |
| ✅ **v8.1.1** | 2026-06-10 | 완벽 수리 + P2 구조 개편. OneDrive canonical 단일화(도훈 mandate) · hook 47/47 부활 · Python/arrow/codex 체인 복구 · env 3중 안전망(QM_ROOT/QVEST_PY/.Renviron) · 헌법모순 일소(max25/TO11 전 계층) · 게이트 2계층(screening tier 신설) · rules autoload 16→6 다이어트 · axiom harvest 백필(corpus 95). |
| ✅ **v8.1.0** | 2026-06-05 | 3-Mode 헌법(각자 평가·자가발전) + 실측-only 거버넌스 + register_module 자동흐름 + Axiom r7 복원. |
| ✅ **v8.0.0** | 2026-05-29 | R+Python 1급 · SR 2.5 · measurement-graduation(WS1/2/3) · agent effort · Dynamic Workflow. |
| ✅ **v7.2.1** | 2026-05-02 | Memory Knowledge Hardening. Axiom JSON SOT (8 active) + memory_health 12-check + 15 readiness + auto-push hook. 도훈 audit 32 critical 모두 반영. |
| ✅ **v7.2.0** | 2026-05-02 | v8 readiness gate 14-check write mode strict PASS + CHANGELOG + 3-day soak. |
| ✅ **v7.1.0-lite** | 2026-05-02 | Solo Operator productivity 5 sprint (qvest_search + qvest_wt + INDEX.md + 3 workflow examples). 15 atomic commits. |
| ✅ **v7.0.1** | 2026-05-02 | 도훈 흠 4건 fix (synthetic cleanup / cert_rules data layer / harness_health hook 제거 / qvest_observe error masking). |
| ✅ **v7.0.0** | 2026-05-02 | Hardening 7 sprint. "검증 가능한 소프트웨어 커널" — 우회 불가능한 실행 계약. 14 schema + sm_validated_advance + events.jsonl + qvest_observe + legacy_write_block. E2E 12/12 PASS. |
| ✅ **v6.4.0** | 2026-05-01 | Harness Kernel Stabilization. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine. |

**검증 기록**: v7.2.1 strict run (2026-05-02, 구 WSL 머신): 30/30 hooks · 15/15 readiness · memory_health hard 0. **v8.1.1 (2026-06-10, 현 머신)**: hook 47/47 + 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 · memory_health hard 0 (HARD_7 신설 포함).

**v8 후속 (이연)**:
- v7.3 candidate: AX-002/003/004/005 advisory → block 강화 / AX-007/008 hook hard-block 검토
- v7.x ext: SQLite event DB (현 JSONL fallback) / Daily brief Telegram SLO / Dashboard Shiny UI
- v8.x: qvest_hook_router 단일 진입 전환(이벤트당 1 spawn — 1주 soak 후), daily_refresh 구조 전환

## 변경 이력 (상세)

- **문서 정합** — 2026-08-16 — `00_Lawbook/INDEX.md` 재동기(v8.1.0 → v8.4). INDEX Maintenance 규약("인프라 reorg / 헌법 버전 전이 시 INDEX 갱신 + CHANGELOG 기록 의무") 이행 기록. ★**본 CHANGELOG 자신도 같은 낙후를 겪고 있었다** — 위 v8.4 행은 이때 함께 소급 기재됐다(2026-08-13 전이 시점에 기록되지 않음). 이는 "규약은 있는데 강제하는 기계가 없다"는 구조 문제의 직접 증거이며, 낙후 탐지 자동화가 후속 검토 항목으로 열려 있다. 상세 = Release Status 표 2026-08-16 행.
- **v8.4** — 2026-08-13 — 비대칭 알파 중심 재편 (도훈 mandate). ML 트랙 126건이 자본 게이트를 **하나도** 통과하지 못한 실측(MDD 0/84 · PORT_t 0/10 · oos_retention 2/17)을 근거로 **표적을 평균에서 분포로 교체**. 미소비 표면 = factor DB(331 전수 book-marginal 통과 0, 계열 15종이 구속 해상도)가 아니라 **일별 축**(9,005 거래일 · `flow_features_daily` 1.25GB/9.36M행) — 알파 리서치가 전부 월간 횡단면이라, **월간으로 접는 순간 분포 정보가 소멸**한다(비대칭은 접히기 전에만 관측된다). 매크로는 **이미 적재 중**(lag 1d)이라 신규 수집 불요이나 착수 전 4확인 의무: `fred_macro_wide` 파생 5일 정체 · 계열별 시차 7~73일 불균질 · `macro_regime` 월말스탬프 마지막 행이 **진행 중인 달**이라 월중 조회 시 동월 look-ahead · flow 패널 43일 정체. 비-return FQ-001~005 주력 해제는 **구조 판결 아님** — 2건은 도훈이 데이터 게이트를 닫았고(08-09 공매도/신용대차) 3건은 실측 negative이며, 부활 조건은 SOT §1(INV-7). ⚠**과거 ML 실패의 부활과 구분할 것**: 죽은 것은 ML을 결합기·사이징·평균 예측기로 쓴 경로이고, v8.4는 **표적 자체를 분포로 바꾸는** 미측정 축이다. SOT `qvest_v8_4_asymmetry_ml_sot.md`.
- **v8.3** — 2026-07-10 — 알파 발굴 중심 재편 (도훈 mandate). 진단: 인입 고갈(논문 큐 empty + 헤드리스 claude 지출한도 침묵 정지) · IC-first 선별(전이 벽 부정합) · cap-w 벤치 monoculture(아티팩트 기각) · screen-tier/지식 환류 단절. 이행: worktask schema/guard/prompt PORT_t-정합 + canonical_screen_bt dual-basis 진단 + frontier 큐 + hypothesis_index in-flight + inject 현행화 + 인입 경보화 + hurdle_gate dead 라벨 정리 + 텔레그램 v7. 게이트·제약·6-agent 불변. SOT `qvest_v8_3_alpha_discovery_sot.md` (M3/M10/M11 등 staged 항목 포함).
- **v8.2** — 2026-06-30 — Codex Critic Round 제거 (도훈 mandate). QEPM 파이프라인 외부 Codex 적대검증을 폐지하고 메인 에이전트 Opus 4.8 자체 적대검증(self-adversarial challenge)으로 통합 — 중복 제거. AX-008 Verification Triangulation의 source를 `Forge + Codex + Architect` → `Forge + Self-Adversarial + Architect`로 치환(3-source 중 2/3 PASS 불변). 연계: settings.json 훅 3개 등록 제거 · state_transitions.json `codex_critic_response` required 제거 · 6 agent 정의 self-adversarial 전환 · `qvest-codex-round` skill DELETED · 스크립트/프롬프트 archive(`02_Infrastructure/hooks/_archive_codex_round_v8_2/` · `02_Infrastructure/prompts/_archive_codex_round_v8_2/`) · `codex-round.md` = DEPRECATED 스텁. **유지(별개 시스템)**: S0 Debate codex · RAMP "Codex"(역할명) · enabledPlugins `codex@openai-codex`(S0/RAMP codex CLI). inventory SOT: `00_Lawbook/DEPRECATION.md`.
- **v8.1.1** — 2026-06-10 — 완벽 수리(아키텍처 전수 감사 → hook 전멸·메모리 단절·인터프리터 전멸 복구) + P2 구조 개편(게이트 2계층 / rules 다이어트 / 측정 사다리 / axiom 3축 충전 / MCP 재구축). 커밋 95ad9513 · 93da0bbf 외.
- **v8.1.0** — 2026-06-05 — 3-Mode 헌법 승격 + alpha-search 표준(논문 완전 복제·K200∪KQ150·2005~) + bootstrap 패치.
- **v8.0.0** — 2026-05-29 — Axiom 엔진 리뉴얼(r7 복원) + 측정 무결성 + Graduation 허들 재설계.
- **v7.2.1** — 2026-05-02 Session 76 — Memory Knowledge Hardening release (도훈 audit 32 critical 반영). Axiom JSON SOT (active 8건) + memory_health 12-check + 15 readiness + auto-push Stop hook. 신규 SOT `qvest_v7_2_1_sot.md` 발행. L-273~L-275.
- **v7.2.0** — 2026-05-02 — v8 readiness gate 14 check write mode strict PASS + CHANGELOG v7.2.0 entry + 3-day soak.
- **v7.1.0-lite** — 2026-05-02 — Solo Operator productivity (qvest_search + qvest_wt + INDEX.md + 3 examples). 15 atomic commits.
- **v7.0.1** — 2026-05-02 — Hardening patch (도훈 흠 4건 fix).
- **v7.0.0** — 2026-05-02 — Hardening 7 sprint release. "검증 가능한 소프트웨어 커널" 패러다임 (Codex 외부 평가 "SW 아키텍처 약함" → 우회 불가능한 실행 계약). L-272.
- **v6.4.0** — 2026-05-01 Session 75 — Harness Kernel Stabilization release. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine + dry-run 30/30 + E2E 10/10. L-269~L-271.
- **v6.4 Sprint 1** — 2026-05-01 Session 75 — Active SOT 단일화 + CLAUDE.md 경량화 (436 → ~270 lines) + skills/rules 8 신규.
- **v6.3.3** — 2026-05-01 — v6.0 Codex Critic Round 3중 장치 영구 정착 (L-269)
- **v6.3.2** — 2026-05-01 — Cert Auto-Issuance Paths 명문화 + Layer 4 deferred
- **v6.31** — 2026-04-28 — Charter v1.2 §10 Certification System
- **v6.0** — 2026-04-23 — QEPM 3-Agent WorkTask 도입
- **v5.5** — 2026-04-19 — v55 strict
- **v5.3** — 2026-04-13 — v53 TeamCreate + Hook 17종

(구 plan 참조였던 `/home/quant/.claude/plans/nifty-tickling-hinton.md`는 WSL 시대 경로 — 도달 불가, 내용은 v6.4 SOT에 흡수됨.)

---

## 이관 아카이브 (2026-07-24 도훈 승인 C5 — CLAUDE.md 역사 블록 다이어트, 원문 verbatim 보존)

> CLAUDE.md "헌법만" 원칙(2026-06-10 P2) 정합 — 아래 블록들은 CLAUDE.md에서 본 파일로 이관되고 본문에는 포인터만 남음. 내용 무손실.

### 계보 (구 CLAUDE.md 표기)

> ⚠ 아래 한 줄은 **2026-07-24 이관 시점의 verbatim 스냅샷**이라 "현재 active"가 그때 기준(v8.3)이다 — 보존 원칙상 원문을 고치지 않는다. **현행 계보는 위 Release Status 표가 권위**: … → v8.2 → v8.3 → AST v1.1 → **v8.4** (2026-08-13~ 현재 active).

v6.4.0 → v7.0.0 → v7.0.1 → v7.1.0-lite → v7.2.0 → v7.2.1 → v8.0.0 → v8.1.0 → v8.2 → **v8.3** (현재 active)

### v8.1 핵심 (구 CLAUDE.md 블록 — 3-Mode 정립 + 실측-only + 모듈 자동흐름, 도훈 mandate 2026-06-05)

- **3-Mode 헌법**: alpha-search 제1원칙(**논문 완전 복제** + 유니버스 K200∪KQ150 고정 + 기간 2005~ 고정) · factor-rotation Lane3(모듈 국면배합, RCMA 등급무관 양방향) · Axiom **r7 원전 복원**(5축 boolean-AND + 3-mode 2-tier + INV-1~7)
- **실측-only 거버넌스**: measurement-graduation(real-computation 의무 · portfolio-α t forge-authoritative · oos_retention≥0.7·calmar≥0.64 HARD · DSR 다중검정스타일only · book-marginal ΔIR≥0.05). proxy 손계산 graduation 폐지
- **모듈 표준화 + 자동흐름**: `register_module` 공용계약(**contract_pass+backtested+frozen+hash/build/cost floor 필수, 등급은 무관**) · 계약 미충족 산출은 `module_quarantine` 보존 · `build_module_performance`는 FR input-floor allowlist 소비 · run_factor_rotation 신선도 자동인식 · ML/DPL register 다리(register_research_outputs) · **E2E 4축 배선 닫힘**(자본게이트 book confirm+실주문 2버튼만 수동)
- **KR 데이터 한계 reference**: value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~ (`feedback-alpha-search-paper-replication`)
- **부팅 패치(v8.1)**: bootstrap에 RAWDATA K200/KQ150 컬럼 검증 + 데이터 캐시 존재·신선도 검증 추가
- **v8.0 흡수(retain)**: R+Python 1급 · SR 2.5 · agent effort(judge/gov xhigh) · axiom_context_inject · harness_perf_eval · artifact-naming
- **미완(후속)**: residual momentum 사이클 register/factor_analysis 디버깅 · WT_WT-* cleanup · axiom global 실가동

### Multi-Agent Team v53 절 (구 CLAUDE.md)

v53 TeamCreate 패턴은 v8.1에서 Agent tool spawn으로 대체됨. TeammateIdle/TaskCompleted hook은 settings.json에서 등록 해제 (스크립트는 FS retain — `02_Infrastructure/docs/rules/harness.md` 참조). tmux rc listener는 v8.0에서 폐지. 상세: `.claude/skills/qvest-worktask/SKILL.md` Section 7.

### Release Status 상세 (구 CLAUDE.md — 이전 버전·검증 이력)

- 이전: **v8.2** (2026-06-30 도훈 mandate — Codex Critic Round 제거, Opus 4.8 자체 적대검증 대체. 훅 3개 archive · AX-008 Codex→Self-Adversarial 3-source 2/3 불변 · state_transitions codex required 제거 · qvest-codex-round skill 삭제 · codex-round.md DEPRECATED. 별개 S0/RAMP Codex 유지 — 단 enabledPlugins는 2026-07-24 C1로 해제)
- 이전: **v8.1.1** (2026-06-10 완벽 수리 + P2 구조 개편 — hook 47/47 부활(당시 기준) · OneDrive canonical · 게이트 2계층 · rules autoload 6 코어)
- 최근 검증: (v8.3+F5 패치) hook_e2e_battery 11/11 PASS · router selftest PASS (2026-07-24) / (v8.2) router selftest PASS · hook_e2e_battery 10/11(codex 케이스 제거, 잔여 FAIL=python3 환경) · health HARD-fail 0 (2026-06-30) / (v8.1.1) hook 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 (2026-06-10)
