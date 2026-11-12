# 충실구현 레인 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: replication_lane`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#replication_lane` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 충실구현 레인(Qvest_ReinforceAutoLoop → reinforce_auto_tick · rf_replication_auto.sh)
- 일정: Qvest_ReinforceAutoLoop 8분 간격 틱(HH:02 · 10 · 18 · 26 · 34 · 42 · 50 · 58 — 11-12 실측) · 실행 중이면 다음 틱 거부 0x800710E0 = 정상
- 코드: `02_Infrastructure/ops/rf_replication_auto.sh`(슬롯 작업자) · `02_Infrastructure/ops/reinforce_auto_tick.sh` · `02_Infrastructure/ops/rf_replication_slots.py`(슬롯 · GPU 인계함 · 임대) · `02_Infrastructure/ops/rf_replication_verify.R`(측정 + 감사 관문) · `02_Infrastructure/ops/rf_fidelity_fanout.sh` · `rf_fidelity_merge.R` · `rf_fidelity_audit_lib.R`(감사 6축) · `02_Infrastructure/ops/rf_llm_env.sh`(모델 · 한도 문구 · 폴백) · `02_Infrastructure/alpha_search/run_paper_replication.R`
- 상태 파일: 슬롯 요청 `06_Registry/replication_slots/<slot>/replication_request.json` · 슬롯 요약 `06_Registry/replication_slots/_status.json` · GPU 인계함 `06_Registry/replication_slots/_gpu_inbox/*.json` · claim `.cache/rf_replication.claim.<slot>/` · 스킵리스트 `06_Registry/replication_skiplist.json` · 재구현 대기열 `06_Registry/reimplement_queue.json` · 사건 원장 `.cache/reinforce_auto_log.jsonl`(시각 있음 — 슬롯 로그 `replication_auto_<날짜>_<slot>.log` 는 줄에 시각이 없다)
- 감시 규칙:
- `lane_errors` (log_patterns): 틱 비정상 종료, R 오류, 레인 정지 사유, 감사 상충, 리프레시 잠금 stale, claim_live_long
- `lane_alive` (freshness): .cache/scheduler_logs/reinforce_auto_{YYYYMMDD}.log
- `request_state` (json_field): 06_Registry/replication_request.json(구판 — 11-12 현재 adopted_by_slot)
- `slots_state` (json_field): 06_Registry/replication_slots/_status.json · worst_status

## 알려진 고장 형태 (기억 카드 · 실측)

- ★(11-12 실측) **한도 문구가 바뀌면 환경 실패가 리서치 판정으로 굳는다.** `rf_llm_env.sh:62` `RF_LLM_LIMIT_RE` 가 모르는 문구(11-12: "You're out of usage credits. Switch to another model to continue.")면 ① Opus 폴백이 안 걸리고(`fell_back=0`) ② `model_quota_exhausted` 분류가 안 되고 ③ 엔진이 없으면 `no_engine` → 재시도 3회(틱당 1회 · 회당 ~8초) → 스킵리스트 `unreproducible`(논문당 ~40분). 엔진이 이미 있으면 한도로 끊긴 실행의 반쯤 고친 엔진이 그대로 측정된다(에이전트 rc ≠ 0 을 보는 관문이 없다 · 폴백 경로의 `_limit_partial` 치우기도 안 돈다). 같은 정규식을 `chain_gen_run.sh:129` · `rf_overlay_audit.sh:194` · 감사 팬아웃(`rf_llm_agent_run`)이 쓴다.
- ★(11-12) 감사 팬아웃의 Fable 판독형 3축(signal · portfolio · undeclared = required)이 한도로 미산출이어도 병합기는 대조형 축 하나가 adapted 면 `adapted` 를 낸다(`rf_fidelity_merge.R:100-102` · flag "required 축 0/3") → 처분 = proceed(`rf_fidelity_audit_lib.R:204-216` · 검사 B4 가 이 동작을 고정) → 측정 · 소비가 required 축 없이 진행된다.
- ★(11-12 · 10-17) 검증기의 패키지 추출(`rf_replication_verify.R:785-833` `.strip_strings` 가 줄 단위)이 여러 줄 R 원시 문자열(`r"---( … )---"`) 속 파이썬 슬라이스 `0::2` · `1::2` 를 R 패키지 '0' · '1' 로 읽는다 → install_incomplete → `verify_failed dependency_install_failed`.
- ★(11-12) 엔진이 torch 파이썬을 `Sys.getenv("QVEST_PY")` 먼저 고르면(1309.7119 `engine.R:351-352`) 사용자 QVEST_PY = 시스템 Python 3.15(torch 없음)가 잡혀 `ModuleNotFoundError: No module named 'torch'` → 그 변형 status=error(30~46초). 프롬프트는 venv torch 를 지시한다(`rf_replication_auto.sh:778 · 897`).
- ★(11-12) 감시기 키는 숫자를 '#' 으로 접어 만든다(`superfan_watch.py _norm`) — `failed_needs_session@<논문>` 은 논문이 달라도 같은 키(e3b093cc07fd)다. 이상 하나에 여러 논문의 서로 다른 원인이 섞인다 → 사건 원장(jsonl)으로 논문별로 가른다.
- (11-12) 재부팅이 데일리 리프레시 도중이면 잠금이 `pre_boot` stale 로 남는다 — 레인은 기다리지 않고 진행(설계) · 다음 리프레시가 잠금을 새로 잡는다. 경보 = 정보성.
- (11-12) 꺼진 슬롯(cpu1 · cpu2 — 11-10 1슬롯)의 claim 폴더가 11-07 09:22 그대로 남아 있다(슬롯 목록 밖이라 안 쓸린다) — 슬롯을 다시 켜면 죽은 소유자 회수 대상.
- claim 2시간이면 살아 있는 실행도 회수해 이중 실행할 수 있다(기억 카드 project-unattended-replication-lane-reclaims-live-runs-at-2h-20260913 · 09-15 수리 = claim_stale_hours 6 · 생존 소유자는 회수 안 함).
- 세션에서 띄운 레인의 'OAuth 만료'는 가짜 — 무인 인증 = 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN(기억 카드 reference-session-launched-lanes-inherit-desktop-auth-env-20261010).
- 주간 사용 한도(rate_limit · weekly limit)에 걸리면 틱마다 같은 줄을 남기고 초기화 시각까지 멈춘다(2026-10-15~16 실측).
- 재감사 번복 = audit_conflict(세션 판정 · 다음 논문 진행 — 기억 카드 project-audit-conflict-…-20261014).
- 실행 중이면 다음 틱이 거부된다(작업 결과 0x800710E0) — 정상.

## 기준선 — 정상일 때의 모습 (11-12 실측)

- 슬롯: gpu1 하나(도훈 11-10 1슬롯) · GPU 슬롯은 CPU 슬롯이 없으면 어떤 등급이든 받는다(`rf_replication_slots.py accepts`) · 발행 순서 = GPU 인계함(handoff.at → 파일명) → 재구현 대기열 reserved → 큐(next_paper_order).
- 한 논문의 단계와 시간: 에이전트 20~60분(정상) · 한도로 실패한 에이전트 ~8초 · 사전검사 수 초 · 감사 팬아웃 1~11분 · 변형 측정(분석기 25~31분 포함) CPU SVM 류 48분~9.6시간 · GPU 딥러닝 변형 42~58분 · 마지막 변형 뒤 후처리(역할 카드 · 재료 인계 · 모듈 등록 · 팩터 분석) ~7.5분 → verify_done.
- 논문 경계 틈: 작업자가 끝나면 다음 틱(≤ 8분)까지 claim = free. 연쇄 재구현(reimplement_chain)은 몇 초 만에 다시 잡는다(.chain 표식 · 깊이 > 0 작업자는 GPU 임대를 다시 보지 않는다).
- 측정 중 Rscript 작업 집합 ~1.8~1.9 GB(1309.7119 SVM 단계).

## 사건 기록 (최신이 위)

- 2026-11-12 — **Fable 크레딧 소진 문구 미인식 → no_engine 오분류 → 도훈 승인 재구현 2편 스킵리스트행** · 상태 = 진단됨 · 수리 대기(Q).
  - 증상: 감시기 e3b093cc07fd `failed_needs_session@…` ×9(04:17~11:17 스캔 — 한 키에 2411.13555 · 2507.01964 · 2412.12516 세 건). 09:38~10:42 에이전트 8회(fable/max) 전부 rc=1 · ~8초 · 출력 "You're out of usage credits. Switch to another model to continue." · fell_back=0 → no_engine → 10:10:03 2507.01964 · 10:50:03 2412.12516 스킵리스트 `unreproducible`(둘 다 재구현 대기열 decided_by dohoon · 10-17 재측정 승인 · 10-20 GPU 인계함 대기).
  - 근본 원인: 레인 모델 fable 전환(11-11 21:04 · LLM-LANE-FABLE-GENERATION-20261111) 뒤 11-12 03:33~04:19 사이 Fable 크레딧 소진 + 새 문구가 `RF_LLM_LIMIT_RE`(rf_llm_env.sh:62 · 09-17 뒤 무변경)에 안 걸림. 옛 문구 "You've reached your Fable limit. Switch to another model, or manage usage credits …" 는 'manage usage credits' 로 걸렸다. 분류 = 코드 결함(문구 목록 낡음) + 외부 원천 변화(문구 · 크레딧).
  - 곁가지: ① 2411.13555 03:33 verify_failed = 패키지 추출 오탐 '0,1'(원시 문자열) ② 04:19 같은 논문 에이전트가 엔진 · 신고서를 고친 뒤(04:14 · 04:17) 크레딧으로 끊겼는데 그대로 측정 · 소비(P1_RETURN 재료 인계 09:23) — 감사 required 0/3 ③ 1309.7119 감사도 required 0/3(10:58) · 변형 5개 중 ANN 2개 torch 부재 오류(QVEST_PY).
  - 수리안: 문구 추가(`out of usage credits|switch to another model`) + 검사 B+ 표본 · 스킵리스트 두 건 revoked · 재구현 대기열 reserved 재예약(GPU 창 뒤) · 2411.13555 · 1309.7119 감사만 재실행 검토. 보고서 = `20261112_2156_diagnosis.md`.
  - 22:02 재확인: Fable 여전히 소진 — 1109.3488(인계함 · auto_retries 2) 에이전트 8초 rc=1 · 같은 문구 → 옛 엔진(11-07)이 사전검사 pass 뒤 그대로 감사 · 측정으로 감(에이전트 rc 관문 없음). 다음 재시도 3/3 이 마지막 — 그 전 수리 없으면 스킵리스트행(추정 23:30~23:50).
  - 1309.7119 = 21:58:02 verify_done rc=0(정상 종료 · 원장 소비 · P2_DEFENSE 재료) — 변형 5 중 ANN 2 torch 부재 오류 · 감사 required 0/3.
  - 리프레시 잠금 stale 두 건 = 11-12 00:13 재부팅(가동 시간 역산)이 남긴 pre_boot 잠금 · 00:34 새 리프레시가 인수 · 21:51 잠금 파일 없음 → known.
- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
