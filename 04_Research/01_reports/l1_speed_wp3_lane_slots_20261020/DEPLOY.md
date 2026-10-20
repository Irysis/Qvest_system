# WP3 배포 절차서 — 충실구현 레인 다중 슬롯 · GPU 임대 · 쓰기 잠금

- 근거 결정: `L1-SPEED-PLAN-20261020` · `L1-SPEED-LEVERS-20261020`(note: "레인 다중 슬롯 · 임대는 P2R05 GPU 단계 뒤 배포 · 동시 운영은 쓰기 잠금 배포 뒤")
- 계획서: `C:/Users/99922/.claude/plans/1-mellow-hartmanis.md` §11 · §12 · §13
- 브랜치: `worktree-agent-a379a174f353bfd3f` · 시험 기록: 같은 폴더 `TEST_RECORD.md`

## 0. 배포 조건

1. P2R05 GPU 단계(분위 DNN 261개월 + 재시드 261개월) 종료.
2. 도훈 확인.
3. 이 브랜치는 P2R05 핀 50개 파일(`prereg_draft.json::operational_pins`)을 하나도 고치지 않는다. 고친 파일은 아래 §1 목록이 전부다.

## 1. 바뀐 것

| 구분 | 파일 | 내용 |
|---|---|---|
| 신규 | `02_Infrastructure/ops/qv_lock.py` | 쓰기 잠금 정본(mkdir + 소유자 pid + 시작 시각 + stale 판정 + 시간 제한 · 회수 경합 방지 · 펜싱) · GPU 임대 API · CLI |
| 신규 | `02_Infrastructure/ops/qv_lock.R` · `qv_lock.sh` | 같은 디스크 형식의 R 판(잠금 본판 · 임대는 CLI 위임) · 셸 래퍼 |
| 신규 | `02_Infrastructure/ops/rf_replication_slots.py` | 슬롯 디스패처(tick) · 발행기(issue) · 논문 잠금 · GPU 인계함 · 구판 요청 인수 · 상태 · 일 소진량(burn) · 설정 켜기/끄기 |
| 신규 | `02_Infrastructure/ops/rf_compute_class.py` | 논문 계산 등급 판별(명시 > 구현 의존성 > 큐 메타 > cpu) |
| 수정 | `02_Infrastructure/ops/rf_replication_auto.sh` | 디스패처 위임(slots 설정 시) · 슬롯 작업자 경로 · 논문 잠금 펜싱 · 등급 관문(에이전트 전 · 측정 직전) · GPU 임대 보류 · 연쇄 표식 · 저널 slot 필드 |
| 수정 | `02_Infrastructure/ops/rf_replication_verify.R` | 요청 경로 = `QVEST_RP_REQUEST`(레인이 넘김 · 없으면 구판) · 슬롯 모드 공유 기록 잠금(`rf_replication.book`) · 슬롯 모드에서 '가장 최근 산출물' 폴백 금지 · 저널 slot 필드 |
| 수정 | `02_Infrastructure/programs/next_replication.R` | `--req` · `--only-key` · `--slot` · 슬롯 작업자 문맥이면 슬롯 발행기에 위임 |
| 수정 | `02_Infrastructure/ops/rf_reimplement_queue.R` | `only_key` · `slot` 인자 · `issued_request` = 실제 요청 경로 |
| 수정 | `02_Infrastructure/ops/rf_next_paper_pick.py` | `iter_candidates()` 노출 · `--only-key/--exclude/--want/--list`(인자 없으면 출력 바이트 동일) |
| 수정 | `02_Infrastructure/programs/program_registry.R` | pr_* 변경 함수 10종 = 읽기→고치기→쓰기 전체 잠금 · pr_save 재진입 잠금 + 펜싱 |
| 수정 | `02_Infrastructure/programs/q_judgment_ledger.py` · `session_resume.py` | 변경 명령 전체 잠금 + 펜싱(읽기 명령 무잠금) |
| 수정 | `02_Infrastructure/ops/boot_lean.sh` | `06_Registry/replication_slots/_status.json` 이 있으면 Queue 줄에 '레인 슬롯 n/N' (없으면 표기 없음) |
| 수정 | `06_Registry/superfan_components.json` | 레인 로그 규칙에 슬롯 로그 `replication_auto_{YYYYMMDD}_*.log` 추가(구판 로그도 그대로) |
| 수정 | `08_Tests/hooks/run_all_hooks.sh` | 새 시험 5개 SUITES 등재 |
| 결정 기록부 | `reinforce_ledger.R`(dr_*) | **고치지 않았다** — 09-25 O0a 부터 claim + CAS + 쓰기 전후 대조를 갖고 있다. 동시 writer 시험으로 실측 확인만 했다(TEST_RECORD ④) |

**동작 불변 조건**: `replication_lane.slots` 키가 없으면 레인은 구판 단일 슬롯 그대로다(시험 D3 · `test_replication_lane.sh` 89/89). 그래서 코드 병합과 슬롯 켜기를 두 단계로 나눌 수 있다.

## 2. 전환 순서

**Step 0 — 사전 점검**
- main 작업 트리의 미커밋 변경을 확인한다: `git status --short -- 02_Infrastructure/ops/rf_replication_auto.sh 02_Infrastructure/ops/rf_replication_verify.R 02_Infrastructure/programs/ 06_Registry/superfan_components.json 08_Tests/hooks/run_all_hooks.sh`
  - ★`gpu_handover.py`(P2R05)가 레인 스크립트에 `PYTORCH_CUDA_ALLOC_CONF` 줄을 넣었을 수 있다 — 있으면 먼저 커밋한 뒤 병합(충돌은 그 한 줄 · 둘 다 남긴다).
- 병합 전 롤백 태그: `git tag pre-wp3-lane-slots-<YYYYMMDD>`

**Step 1 — 레인 정지 · 구판 작업자 소진**
- `replication_lane.enabled = false`(마지막으로 `lane_hold.py pause "<사유>"` 사용 가능).
- 구판 claim 이 사라질 때까지 기다린다: `ls .cache/rf_replication.claim` → 없음.
- ★실행 중인 bash 스크립트 파일은 교체하지 않는다(Windows 에서 `os.replace` 거부 · 제자리 쓰기는 지연 판독 위험 — memory reference-running-bash-script-replace-refused). 구판 작업자가 끝난 뒤 병합한다.
- 예외: 구판 작업자를 기다릴 수 없으면 병합해도 된다 — 디스패처가 살아 있는 구판 claim 을 '점유자'로 본다(그 논문 제외 · GPU 논문이면 GPU 슬롯을 띄우지 않음 · CPU 면 CPU 용량 1 감산 — 시험 S7 · S8). 다만 위 파일 교체 위험은 그대로 남는다.

**Step 2 — 병합**
- main 에서 `git merge --no-ff worktree-agent-a379a174f353bfd3f`.
- 예상 충돌: `08_Tests/hooks/run_all_hooks.sh` SUITES(WP1 · WP4 가 항목을 더했을 수 있음 — 양쪽 다 남긴다) · `06_Registry/superfan_components.json`.

**Step 3 — 병합 뒤 시험(main 에서)**
```bash
.venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_qv_lock.py
Rscript 08_Tests/ops/test_qv_lock_cross.R
.venv_qvest_ml/Scripts/python.exe 08_Tests/ops/test_replication_slots.py
bash 08_Tests/ops/test_replication_slots_lane.sh
.venv_qvest_ml/Scripts/python.exe 08_Tests/programs/test_ledger_write_locks.py
bash 08_Tests/ops/test_replication_lane.sh
```

**Step 4 — 슬롯 켜기**
```bash
.venv_qvest_ml/Scripts/python.exe 02_Infrastructure/ops/rf_replication_slots.py config enable --cpu 2 --gpu 1
```
- 기록되는 것: `replication_lane.slots = {"cpu": 2, "gpu": 1}` · `replication_lane.gpu_lease = {default_cap_hours: 12, max_cap_hours: 12, basis}` · `slots_enabled_at` · `slots_note`.

**Step 5 — Superfan 요청 상태 규칙 추가**
`06_Registry/superfan_components.json` 의 `replication_lane.rules` 에 한 줄을 더한다(슬롯을 켠 뒤라야 파일이 있어 거짓 경보가 없다):
```json
{"id": "slots_state", "kind": "json_field", "file": "06_Registry/replication_slots/_status.json", "path": "worst_status",
 "bad_values": ["failed_needs_session", "failed"], "severity": "fail"}
```
구판 규칙 `request_state`(구판 요청 파일)는 그대로 둬도 된다 — 인수 뒤 그 자리는 `adopted_by_slot` 이라 경보가 나지 않는다.

**Step 6 — 레인 재개**
- `replication_lane.enabled = true`(마지막으로 `lane_hold.py resume "<사유>"` 사용 가능).
- 다음 틱(예약 작업 Qvest_ReinforceAutoLoop · 8분 · IgnoreNew 그대로)에서 디스패처가: 구판 요청 인수(등급 맞는 빈 슬롯) → 빈 슬롯 발행 → 작업자 분리 실행(nohup · 틱 환경 상속) → 틱은 곧바로 끝난다.

**Step 7 — 첫 두 틱 관찰**
- `python 02_Infrastructure/ops/rf_replication_slots.py status --line`
- `.cache/reinforce_auto_log.jsonl` 의 `slots_tick` · `slot_launched` · `legacy_request_adopted` · `claim_stale_reclaim`(slot 필드)
- 슬롯 로그 `.cache/scheduler_logs/replication_auto_<날짜>_<slot>.log`
- 메모리(작업자 = 검증기 R 1개가 RAWDATA 적재 · 3개 동시) · GPU(`nvidia-smi` — GPU 작업은 gpu1 하나만)

**Step 8 — 일 소진량**
```bash
.venv_qvest_ml/Scripts/python.exe 02_Infrastructure/ops/rf_replication_slots.py burn --days 7
```
- 슬롯 · 일별 논문 수 · 구현 에이전트 수(폴백 포함) · 구현 에이전트 분 · 감사 에이전트 수 · 한도 사건. 논문당 LLM 비용은 같고 슬롯 수만큼 소진 속도가 빨라진다.
- 한도 사건(`quota_hits`)이 생기면 `config enable --cpu 1 --gpu 1` 로 줄이고 도훈께 보고한다.

## 3. GPU 임대 — lane_hold · lane_pause 를 대체한다

서명(고정 · 원 세션 코어 실행기용 — R · py · sh 같은 의미):

| 언어 | 획득 | 해제 | 상태 |
|---|---|---|---|
| R | `source("02_Infrastructure/ops/qv_lock.R")` → `gpu_lease_acquire(holder, purpose, cap_hours = NULL, holder_pid = NULL)` | `gpu_lease_release(holder)` | `gpu_lease_status()` |
| py | `import qv_lock` → `qv_lock.gpu_lease_acquire(holder, purpose, cap_hours=None, holder_pid=None)` | `qv_lock.gpu_lease_release(holder)` | `qv_lock.gpu_lease_status()` |
| sh | `. 02_Infrastructure/ops/qv_lock.sh` → `gpu_lease_acquire <holder> <purpose> [cap_hours] [holder_pid]` | `gpu_lease_release <holder>` | `gpu_lease_status` |

- 반환: 획득 `{ok, reason: acquired|already_held|held_by_other, lease, note}` · 해제 `{ok, reason: released|not_held|held_by_other}` · 상태 `{state: free|held|expired|holder_dead|unreadable, holder, purpose, started_at, cap_hours, expires_at, remaining_h, elapsed_h}`.
- 파일: `.cache/gpu_lease.json`(`QVEST_GPU_LEASE` 로 덮기) · 이력 `.cache/gpu_lease_history.jsonl`(획득 · 해제 · 만료 · 보유자 사망).
- 의미:
  - 임대가 살아 있으면 GPU 슬롯은 **새 claim 을 보류**한다(디스패처가 띄우지 않고 · 작업자도 착수 직전에 한 번 더 본다). 진행 중인 GPU 작업(연쇄 포함)은 끝까지 간다. CPU 슬롯은 선점하지 않는다.
  - 상한 = 설정 `replication_lane.gpu_lease.max_cap_hours`(12) · 기본 = `default_cap_hours`(12). 더 긴 요청은 상한으로 자르고 note 를 남긴다. 같은 보유자의 재획득은 연장하지 않는다(상한은 시작 시각 기준).
  - 만료는 레인 틱이 파일만 보고 스스로 판정해 치운다(외부 감시 프로세스 없음 — 10-19 2.6일 정지 부류 제거).
  - `holder_pid` 를 주면 그 프로세스가 죽은 순간 만료 전이라도 풀린다. **곧 끝나는 CLI 의 pid 를 넘기지 말 것** — 긴 측정 스크립트 자신의 pid(R `Sys.getpid()` · 셸 `$(cat /proc/$$/winpid)`)만.
- 코어 실행기의 GPU 단계 순서: `gpu_lease_acquire` → (GPU 슬롯이 이미 돌던 작업이 있으면 끝날 때까지) `rf_replication_slots.py status --json` 의 gpu1 claim 이 `free` 이고 `nvidia-smi` 메모리가 빈 것을 확인 → 학습 → `gpu_lease_release`.

## 4. lane_hold · lane_pause 퇴역

- `04_Research/programs/P2_DEFENSE/P2R05_distribution_target/lane_hold.py` · `lane_hold_wait.sh` · `P2R03_conditional_overlay/lane_pause.py`: 배포 뒤 쓰지 않는다.
  - GPU 확보 = 임대(§3). 레인 전체 정지가 필요하면 `replication_lane.enabled` 를 직접 바꾼다(사람 결정).
  - 외부 감시(`lane_hold_wait.sh` + `detached_env.sh` 분리 실행)는 다시 띄우지 않는다.
- 파일 자체는 라운드 폴더의 사료로 남긴다. 정리는 P2R05 종료 세션의 몫이다(P2R05 핀은 아니지만 라운드 산출물).

## 5. 되돌리기

**설정만(코드 유지)**
1. `replication_lane.enabled = false` → 슬롯 claim 이 모두 사라질 때까지 기다린다(`ls .cache/rf_replication.claim.*`).
2. 진행 중이던 슬롯 요청(`06_Registry/replication_slots/<slot>/replication_request.json` 중 pending · in_progress · failed_needs_session) 1건을 구판 자리(`06_Registry/replication_request.json`)로 옮긴다 — 구판 레인은 그 자리만 본다. 나머지 슬롯 논문은 원장 미소비라 큐에서 다시 집힌다. 단, 재구현 대기열에서 `issued_request` 가 슬롯 경로인 항목은 `reserved` 로 되돌린다.
3. `python 02_Infrastructure/ops/rf_replication_slots.py config disable` → `slots` 키 제거 → 구판 단일 슬롯.
4. `replication_lane.enabled = true`.

**코드까지**
- `git revert -m 1 <병합 커밋>` 또는 `git reset --hard pre-wp3-lane-slots-<YYYYMMDD>`(공유 전일 때만).
- 쓰기 잠금은 하위호환이다(서명 · 반환 불변) — 되돌려도 원장 형식은 그대로다.
- 남는 잠금 디렉터리(`.cache/registry_locks/*.qvlock` · `.cache/qv_locks/` · `.cache/rf_replication.papers/`)는 구판이 읽지 않는다 — 지워도 된다.

## 6. 알려진 경계 · 남은 위험

- **메모리**: 슬롯마다 검증기가 RAWDATA 를 적재한다(수 GB). WP2 측정 서버 전까지는 `cpu: 2` 를 상한으로 권고한다.
- **공유 저널 동시 추가**: `reinforce_auto_log.jsonl` 은 여러 작업자가 한 줄씩 덧붙인다. Windows CRT 의 덧붙이기는 원자적이지 않아 아주 드물게 한 줄이 깨질 수 있다. 판독기는 깨진 줄을 건너뛴다. 기존 감사 팬아웃(6 에이전트)과 같은 수준의 위험이다.
- **검증기 공유 기록 구간**(팩터 등록 · 원장 L1 개설/접기 · 큐 미러 · 프로그램 큐 · 모듈 등재 · 스킵리스트)은 슬롯끼리 직렬화한다(`.cache/qv_locks/rf_replication.book.qvlock`). 측정은 병렬이다. 세션이 같은 원장을 동시에 쓰는 경우는 범위 밖이다(기존 위험 그대로).
- **패키지 자동 설치**: 검증기의 CRAN 자동 설치가 두 슬롯에서 겹치면 R 00LOCK 로 한쪽이 실패한다 → `dependency_install_failed` → 자동 재시도(auto_retries 3).
- **새 논문 착수 지연**: 슬롯이 논문을 끝내면 다음 논문은 다음 틱(≤ 8분)에 띄운다. 논문당 1~3시간 대비 5% 미만이다.
- **구판 요청 자리 = 받은편지함**: 세션이 `06_Registry/replication_request.json` 에 손으로 쓴 요청도 디스패처가 등급 맞는 빈 슬롯으로 인수한다.
  - ★반대로, 이미 슬롯에 들어간 논문의 요청을 고칠 때(세션 판정 `audit_ruling` · `failure=session_reverify` 등)는 **그 슬롯의 요청 파일**을 고친다 — `rf_replication_slots.py status` 가 어느 슬롯인지 보여 준다. 구판 자리에 쓰면 그 논문은 이미 다른 슬롯이 쥐고 있어 새 슬롯 작업자가 펜싱에서 `duplicate_held_elsewhere` 로 닫는다(중복 실행은 막히지만 판정은 전달되지 않는다).
  - `gpu_handover.py`(P2R05) 처럼 구판 요청 경로를 박아 둔 세션 도구는 배포 뒤 슬롯 경로를 받게 고쳐야 한다(그 도구는 라운드 폴더 · 이 브랜치 범위 밖).
- **임대는 선점하지 않는다**: 임대를 잡아도 GPU 슬롯에서 이미 돌던 작업은 끝까지 간다(요구 사양 그대로). 지금 당장 GPU 가 필요하면 세션이 GPU 작업자를 체크포인트에서 멈추는 별도 절차(10-18 `gpu_handover.py` 형)를 써야 한다 — 상설화 여부는 결정 대상.
- **예약 작업 맥락의 분리 실행**: 디스패처는 작업자를 `nohup … &` + `disown` 으로 띄우고 바로 끝난다. MSYS 쪽 생존(부모 셸 종료 뒤 자식 생존)은 실측했다(TEST_RECORD). 예약 작업(Task Scheduler)이 틱 종료 뒤 자식을 거두지 않는지는 배포 첫 틱에 Step 7 로 실측한다 — 슬롯 claim 이 틱 종료 뒤에도 살아 있고 슬롯 로그가 자라면 정상. 거둬진다면 설정 `replication_lane.launch_mode = "foreground"`(틱 안에서 차례 실행 · 처리량 이득 없음 · 구판과 같은 직렬)로 즉시 되돌리고 분리 방식을 바꾼다(환경변수 `QVEST_RP_LAUNCH` 가 설정보다 앞선다 — 검사용).
- **R 의 QM_ROOT**: R 은 `~/.Renviron` 의 QM_ROOT(운영 체크아웃)로 환경을 덮는다. worktree 에서 R 시험을 돌릴 때는 `R_ENVIRON_USER=<빈 파일>` 로 막아야 worktree 코드가 시험된다(TEST_RECORD §사건 참조).

## 7. 결정 대기

1. **GPU 임대 상한 12h** — 결정 note 의 '상한 12h/라운드'를 그대로 상한으로 썼다. 더 긴 GPU 단계가 필요하면 설정 `max_cap_hours` 를 도훈이 정한다.
2. **슬롯 수 기본 cpu 2 · gpu 1** — 메모리 실측 뒤 조정(Q 자율 · 한도 압박이면 도훈 보고).
3. **GPU 슬롯의 CPU 논문 수용** — 지금은 GPU 슬롯이 GPU 논문만 받는다(GPU 논문이 오면 바로 받게). GPU 논문이 큐에 없을 때 GPU 슬롯도 CPU 논문을 받게 할지는 처리량 · 대기 상충이라 결정 대상이다.
4. **토큰 단위 소진량** — 지금 소진량은 레인 저널 기반 대리 지표(세션 수 · 분)다. 토큰 단위로 재려면 `claude -p` 를 `--output-format json` 으로 바꿔야 한다(환경 실패 판정이 텍스트 출력을 grep 하므로 별도 작업).
