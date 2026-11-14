# P1S03 사전등록 초안 v3 변경분 격리 점검

- 점검자: 격리 변경분 점검(서브에이전트)입니다. 이 판의 설계 · 구현에 참여하지 않았고, 측정 결과를 보지 않았습니다. Q 의 진술 · `changes_after_*` · 커밋 메시지는 진술로만 읽었습니다. 판정은 파일 · 코드 재도출로 했습니다. 범위는 v2 → v3 변경분과 지난 점검 v2 끝의 '초안 v3 를 만들 때' 기준뿐입니다(전면 재점검 아님).
- 대상(md5): `round_spec.json` v3 **eb987bbd57c8b333901a32f3d10d0afe** · `prereg_draft.json` v3 06a5111d · `prereg_draft.md` 4895dad3 · `specs/P1S03_FVALU_RX0.json` c23f930e · `drafts.json` 477ccb97(v3 항목 review null) · `tools/init_p1s03_v3.R` d9b8b5a0(HEAD 8837890d 대비 1줄) · `DESIGN.md` 8cfc93c6 · `tick_hold` a9f0bd0b · `standing_rules.md` c5470d7b. 비교 기준 = HEAD 의 v2(`round_spec.json` 85a4d6a4 · `prereg_draft.json` 2bb35411 · `prereg_draft.md` d8bdf8cf) · v1(86c86e8fc — '같은 것' 확인용).
- 시각: 2026-11-14 약 21:48 ~ 22:03 KST · HEAD 시작 `f89084e5e` · 끝 `ecda88b47`
  - 점검 중 다른 세션 변경 3건입니다. ① 판 표식 원장 `06_Registry/factor_db_vintage.json` 미커밋 수정(21:51:22 — 새 줄 · M-1). ② 커밋 ecda88b47(21:55 · P1R04 측정 셸 대기 조건 — 핀 대상 아님). ③ 끝(22:01)에 판 폴더에 미추적 `tools/init_p1s03_v4.R` 이 생겼습니다(이 점검 대상 밖 · 열지 않음).
  - 대상 파일 md5 는 시작 · 끝(22:01:46)이 같습니다.
- **판정: revise**
- **건수: 필수 1 · 권고 0 · 선택 2**
  - 필수 M-1 은 v3 변경분의 결함이 아닙니다. v3 생성(21:47:14) 뒤에 판 표식 원장에 새 줄이 붙어, v3 의 판 표식 글이 등록 시점 사실이 아니게 됐습니다. Q 가 21:54 에 이미 'v3 는 등록하지 않고 판 표식 글만 바꾼 v4'로 정했으므로, 지시대로 재조사 없이 'v4 에서 바뀜'으로만 적고 v4 에 필요한 확인 세 가지만 붙였습니다.
  - 그 밖의 v3 변경분은 v2 지적 9건(필수 1 · 권고 1 · 선택 7)을 해소했습니다. 잔여는 작은 서술 둘(S-1 · S-2)입니다.
  - 잎 차이 · 초안 재생성(손 편집 0) · 정보 경계(`rc_after_tau_leaks` 빈 결과) · 불변 구역 · 핀 37(불일치 0)은 재도출과 맞습니다.

## 0. 정보 경계 · 한 일

- 연 것
  - 판 폴더: `round_spec.json` v3 · v2(HEAD) · v1(86c86e8fc) · `prereg_draft.json` · `.md` v3 · v2 · `drafts.json` · 시드 칸 사양 v3 · v1 · `tools/init_p1s03_v3.R` 전문 · `git diff` · `tools/init_p1s03_v2.R` 머리 · `DESIGN.md`(머리 · §3 · §6 · §7 · §8) · `tick_hold` · `prereg_draft_review_v2.md` 전문.
  - 코어 v4: `util.R`(60-229 — τ_D 검사 두 함수) · `pins.R`(1-80) · `register.R`(1-150) · `standing.R`(152-252 쓰기 검사 · 1700-1760 standing-check CLI) · `p4.R`(grep — 저위험 꼬리표 · 판 표식 판독) · `load.R`. `RELEASES.json` v4 요약 필드.
  - 계약 · 운영: `contracts/factor_db_vintage.R`(1-96 · grep) · `run_paper_replication.R`(grep — 판 표식 기록) · P1R04 `tools/p1r04_measure.sh`(grep · ecda88b47 diff 줄) · `.cache/scheduler_logs/p1r04_measure_state.txt`(셸 상태 1줄).
  - 원장 · 등록부: `factor_db_vintage.json` 은 마지막 6줄의 id · completed_at · decision · scope 와 `_doc` 의 진행 중 규약 한 문장만 읽었습니다(항목 note 안 읽음).
  - 이름 · 시각만: P1R04 `results/`(0개) · P1S03 `results/`(0개) · `stage_artifacts/programs/P1_RETURN/` 의 P1S03(없음) · `99_Archive/p1r04_aborted_measure_20261113_1030/`(파일 이름 · 시각) · P1R04 `tools/`(lowrisk 두 파일).
- 안 연 것: 모든 `results/**` 파일 내용(보관 폴더 포함) · `verdict.json` · `evaluation_visible.json` · `authoritative_remeasure.json` · `standing_visible.json` · 상설 원장 본문 · 텔레그램 기록 · 철학 · 판단 리뷰 본문 · 공유 노트 폴더 · 판 표식 원장 항목 note · 결정 기록부 본문(이번엔 안 봄).
- 우연 열람(쓰지 않음 · 옮겨 적지 않음)
  - `git log` 제목 6de5d0678(이음매 세션의 P1R03 7 엔진 재측정 커밋)에 한 카테고리의 등급 이동 표기가 있었습니다. 같은 사실이 세션 맥락의 메모리 색인에도 있습니다. 이 점검의 판단에 쓰지 않았습니다.
  - P1R04 셸 상태 줄에는 자료 수리 서술만 있고 성과 수치는 없습니다.
- 돌린 것
  - Rscript 3개(스크래치 폴더 · `QM_ROOT` 명시 · 쓰기는 스크래치뿐).
    - `verify_v3.R`: τ_D 검사(사양 전체 · 바뀐 잎 각각 · 시드 · 초안) · 엄격 검사 `rc_input_issues`(참고) · `rc_pins_compute` 와 초안 핀 대조 · `rc_pins_mismatches` · 매니페스트 · 불변 구역 파싱 비교.
    - `regen_v3.R`: `rc_draft` 본문(register.R:46-59)과 같은 계산을 drafted_at = 디스크 값으로 해 json · md 를 스크래치에 썼습니다. `rc_standing_validate`(check_pin · check_seeds) · standing-check 와 같은 시드 회계 계산 · `rc_standing_rules_md` 재생성(스크래치) · 생성 함수 핀도 봤습니다.
    - `fdv_check.R`: `fdv_ledger` · `fdv_stamp` 판독(읽기 전용).
  - Python: 잎 단위 diff(v2 → v3 · v1 → v3 · 초안) · 원장 필드 판독.
  - 그 밖: git show/diff/log/status · md5sum · ls.
  - 하지 않은 것: `round.sh` 쓰기 명령 · 생성기 재실행 · standing-check CLI(판 폴더 `standing_rules.md` 를 다시 쓴다 — standing.R:1746) · 커밋 · 스테이지.
- 쓴 것: 이 파일 1개(저장소). 그 밖은 스크래치 폴더뿐입니다. P1S03 `results/` 0개 · 등록본 없음을 끝에 다시 확인했습니다.

## 1. 항목 점검 (1–5)

| # | 항목 | 결과 | 근거(재도출) |
|---|---|---|---|
| 1 | 잎 차이 | **Q 진술과 같음** · 초안 차이 = 사양 차이 + 파생 3잎 · 손 편집 0 | 사양 잎 134 → 135. 바뀜 7: `/hypothesis` · `/exposures[2]` · `[4]` · `/conclusion_scope[8]` · `[9]` · `[13]` · `/pins/basis`. 더함 1: `/changes_after_review[2]`. 지움 0. 노출 8 · 결론 25 · changes_after_superfan 2 그대로입니다. 초안 json 잎 286 → 287: 사양 8잎 + `draft_version` 2 → 3 · `drafted_at` · `spec_md5` 입니다. `pins` · `core` · `rules_resolved` · `sentences` · `cells` · `behavior_card_cfg` · `status` 는 0 차이입니다. 재생성: 스크래치 계산 json 06a5111d · md 4895dad3 = 디스크(바이트 동일). md 는 basis · changes 를 그리지 않습니다(register.R:28-42). 그래서 md 차이 = 제목 · md5 줄 · 가설 · 노출 [2] [4] · 결론 [8] [9] [13] 뿐입니다. 생성기 diff 1줄(:29 VMEAS) = 결론 [9] 의 '도훈 결정과 같은 id'(VLAST = D2DEC) |
| 2 | 바뀐 글의 사실성(지금) | 판 표식 글 = v3 시점 사실 · **새 줄 때문에 v4 에서 바뀜(M-1)** · 나머지 맞음 · 잔여 2(S-1 · S-2) | 표 1-a |
| 3 | 정보 경계 | `rc_after_tau_leaks` = **빈 결과** · τ_D 뒤 성과 수치 없음 | 사양 v3 전체 0 · 바뀐 8잎 각각 0 · 시드 0. 초안 json 전체 2건은 메타입니다(`drafted_at` 날짜 · R 판 날짜 — v2 도 같음). 엄격 검사 `rc_input_issues`(처방 입력용 · 참고) 적중은 세 종류이고 모두 v2 와 같은 종류의 오탐입니다: 결정 id 의 YYYYMMDD(관례) · 가설 'OOS … 0.55'(문턱 이름) · changes_after_review[2] 'OOS … S-1'(지적 번호를 지표로 읽음). 노출 [2] 는 엄격 검사도 통과합니다(v2 의 '2023' 적중 해소 = S-2). 노출 [2] 새 글의 '7'은 엔진 수 · '11-14'는 노출 날짜입니다 |
| 4 | 그대로여야 하는 것 | **불변** · 핀 불일치 0 | 파싱 비교 v2 = v3: rules · cells · selection · standing_cfg · tests · behavior_card_cfg · standing · template · purpose · tau_d · core_version · changes_after_superfan · pins.files · 노출 [0] [1] [3] [5]-[7] · 결론 [0]-[7] [10]-[12] [14]-[24]. 시드 c23f930e = HEAD = 초안 칸 md5. 핀: `rc_pins_compute`(v3 사양) 37 = 초안 37(경로 집합 같음 · md5 불일치 0). v2 초안 핀 = v3 초안 핀(순서 · md5). 매니페스트 95d4a286 = RELEASES v4. `rc_pins_mismatches`(초안 v3) = 0(패키지 · R 4.6.2 같음). 행동 카드 사본 6a2a1d21 = 정본. 생성 함수 핀 = 지금(fn_md5 80f8311f · like_md5 080cfea8). `rc_standing_validate`(check_pin · check_seeds) = TRUE |
| 5 | 등록 직전 할 일 ↔ DESIGN §8 | 네 가지 모두 §8 '등록 직전 확인'에 있음 · 지금 셋 충족 · **'D2 completed_at' 조건은 새 줄로 부족(M-1)** | §8(DESIGN.md:38): standing-check · P1R04 `results/evaluation_visible.json` 없음 · `rc_pins_mismatches` 0 · D2 항목 completed_at. 지금 상태: ① standing-check 와 같은 계산 — 시드 회계 45 = 규칙 45(`rc_standing_own_nf` · 원천 P1R03 + P1R04 · 칸 45 · 재측정 · 불일치 · 미상 · 미검증 0) · 규칙 문서 재생성 c5470d7b = 디스크 ② P1R04 `results/` 0개. 셸은 21:53:42 '보류(세션) — 그 판 표식 줄 completed_at 뒤 다시 띄운다 · results 빔'이고, ecda88b47 로 '마지막 줄 완료' · 'P1S03 등록본 파일' 대기를 더했습니다. 그래서 P1R04 평가가 P1S03 등록보다 앞설 길이 셸 쪽에서도 닫혔습니다(R-1 시점 문제 해소) ③ 0 ④ D2 completed_at 2026-11-14T21:40:39+09:00 채워짐. 다만 그 뒤에 진행 중 줄이 하나 더 붙었습니다(M-1) |

### 1-a. 바뀐 글의 사실성(잎별)

| 잎 | v3 서술 | 판단(재도출) |
|---|---|---|
| 가설(:9) | T0 15 비교 상대 = 같은 자료 판(D2 줄 뒤) P1R04 기준 칸 · P1R03 칸 = 앞 자료 판 · 이음매 · D1 = IS 무영향 설계 · D2 = IS 수익률 일부 행 정정 | 비교 상대 교체 = v2 M-1 처방대로입니다. D1 scope = 23팩터 목록이고 커밋 ab249291e 제목이 202603~202611 달로 적습니다(IS 무영향 설계 서술과 맞음). 판 표식 id 부분은 **새 줄 때문에 v4 에서 바뀜** |
| 노출 [2](:127) | 'OOS(τ_D 뒤)' + **새 노출 고지**(이음매 세션 D1 재측정 통지의 P1R03 7 엔진 시험 창 Calmar · 11-14) | 연도 표기 교체 = v2 S-2 입니다. 새 고지는 5f7528c44(17:08:19)가 더했고, 원천 사건은 6de5d0678(17:07:38 · P1R03 7 엔진 재측정)과 시각 · 엔진 수가 맞습니다. 노출 시점에 규칙 · 문턱 · 칸 · 선택은 이미 고정돼 있었고(v1 = 11-13 · v1 → v3 불변), 이 판은 선택이 없습니다(엔진마다 독립). 그래서 노출이 판정에 닿을 길은 없습니다. 고지 자체는 맞게 한 것입니다. 다만 Q 진술('S-2')과 changes_after_review[2] 에 이 추가가 빠졌습니다 → S-1 |
| 노출 [4](:129) | '초안 v3 는 등급 v3.5 핀 교체 · D1 · D2 판 표식 뒤 · P1R04 재측정 결과 전' · '바뀐 것' · '같은 것' 목록 · 등록 직전 재확인 | 시점: v3 21:47:14 > D2 21:40:39 · P1R04 `results/` 0개로 사실입니다. '바뀐 것'(시드 시행 수 2 → 45 · 기대 구체화 C-055 · C-056 · 통과 보고 push_each → daily_summary · 문장 · 회계 문구 · 코어 판 · 자료 판 글)은 v1 → v3 재도출과 맞습니다. 사양은 purpose · hypothesis · accounting.rule · report.pass · pins.files(같은 16 · 순서만) · basis · 목록이 바뀌었고, 시드는 회계 2잎만 바뀌었습니다. '같은 것'(자격 규칙 · 문턱 · 입구 · 갈래 · 판 번호 · 시드 엔진 · 구성 · 축)은 rules · standing_cfg.scan · track · edition · 시드 비회계 잎 0 차이와 맞습니다. 잔여 2(등급 v3.5 핀 · 'T1 11칸 뒤') → S-2. 'D1 · D2 판 표식 뒤' 표현은 **v4 에서 바뀜** |
| 결론 [8](:143) | T0 기대 = 같은 자료 판 P1R04 기준 칸 · P1R03 과 다르면 '원천 판정과 다름' + 원인 기록 · P1R04 와 다르면 판 경로부터 | v2 M-1 처방대로입니다. 판 표식 id · 원인 서술은 **v4 에서 바뀜**(v4 주의점 → M-1 (a)) |
| 결론 [9](:144) | 판 표식 = D2 줄(결정과 같은 id) 뒤 측정분만 기저 자격 | v3 시점 사실입니다(원장 D2 id = 결정 id). **새 줄 때문에 v4 에서 바뀜** — 진행 중 줄이 있으면 범위에 닿는 측정은 전부 낡고, 자체 사양 칸은 모든 수리에 닿습니다(factor_db_vintage.R:17-18) |
| 결론 [13](:148) | 저위험 확인 셋째 길 = 원천 라운드 `results/lowrisk_tags.json` 참 · 판독 불가 = 꼬리표 · 변환기 `tools/p1r04_lowrisk_tags.R` | p4.R:88(lowrisk_confirm_pending 사유 — '파일 판독 불가 = 꼬리표 · 영수증이 없어도 건다') · :101-103(`<원천 라운드>/results/lowrisk_tags.json`) 과 맞습니다. 변환기는 P1R04 `tools/` 에 있습니다(11-14 16:15). = v2 S-6 |
| pins.basis(:190) | 등록부 · 결정 기록부 제외 근거 · 재핀 때 등록부 prereg_md5 도 함께 | 등록부 = 원천 칸 · 선언 입력(standing.R:9 읽기 전용 · :223 · :909-911)입니다. 결정 기록부 = 선언 입력(:911) · 저위험 해제(p4.R:88 'status = resolved')입니다. 9662d7983 은 P1R04 `prereg.json` 과 `06_Registry/research_programs.json` 을 함께 고쳤습니다. = v2 S-3 |
| changes_after_review[2](:164) | v2 점검 반영 목록(사양 · 판 폴더) | 사양 쪽 M-1 · R-1 · S-2 · S-3 · S-6 은 위와 같이 사실입니다. 판 폴더 쪽도 사실입니다: S-1(DESIGN :3 생성기 이름 · §3 n_family 45 · §6 회계 규칙 · §7 부분 측정 · §8 순서) · S-4(v2 생성기 :8 `stop` · v3 생성기 :15-16 등록본 있으면 중단) · S-5 · S-7(§8). 빠진 것 1(노출 [2] 새 고지 → S-1) · 판 표식 id 부분은 v4 에서 바뀜 |

### 1-b. v2 지적별 해소

| v2 | 결과 | 근거 |
|---|---|---|
| M-1 판 표식 글 · T0 비교 상대 · 해제 조건 | v3 기준 해소 → **v3 생성 뒤 새 줄로 다시 열림(이 점검 M-1)** | 가설 · 결론 [8] [9] · DESIGN §8 ① ③ · tick_hold = D2 줄 id 로 대조 일치(v3 시점). 원장 마지막 줄은 21:51:22 부터 D2-XF-FILL-RESTORE-20261114 |
| R-1 노출 [4] 목록 · 등록 시점 | 대체로 해소 · 잔여 → S-2 | 목록 · '같은 것' = v1 → v3 재도출. 시점은 사양 문장 · §8 · P1R04 셸 파일 대기(ecda88b47)로 해소 |
| S-1 DESIGN 낡은 줄 | 해소 | DESIGN :3 · §3 · §6 · §7 · §8 순서 |
| S-2 노출 OOS 연도 | 해소 | 노출 [2] 엄격 검사 통과 |
| S-3 핀 근거 | 해소 | 표 1-a pins.basis |
| S-4 생성기 재실행 가드 | 해소 | init_p1s03_v2.R:7-8 · init_p1s03_v3.R:15-16 |
| S-5 standing-check | 해소(절차) · 지금 계산 충족 | DESIGN §8 · 항목 5 ① |
| S-6 저위험 셋째 길 | 해소 | 표 1-a 결론 [13] |
| S-7 시드 대조 지문 | 해소 | DESIGN §8 해제 절차 |

## 2. 지적

### 필수

**M-1. v3 는 등록 대상이 아닙니다 — v3 생성 뒤 판 표식 원장에 진행 중 줄이 붙었습니다(Q 21:54 결정과 같음 · 재조사 생략)**

- 근거
  - 원장 마지막 줄은 `D2-XF-FILL-RESTORE-20261114` 입니다. decision 은 'RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114(D2 팩터 DB 재계산의 부작용 수리 …)', completed_at 은 빈 문자열이고, scope 는 7팩터(V01_BM · V02_EP · V03_CFP · V08_PSR · GR01 · GR02 · GR03)입니다. 파일 기록은 21:51:22 · 미커밋이고, v3 생성(21:47:14)보다 뒤입니다.
  - v3 의 판 표식 글(가설 · 결론 [8] [9] · 노출 [4] 'D1 · D2 판 표식 뒤' · changes_after_review[2])과 DESIGN §8 '등록 직전 확인' · 해제 조건 ① · tick_hold 는 'D2 줄이 마지막'을 전제합니다. 이 글들은 **새 줄 때문에 v4 에서 바뀝니다**.
- v4 를 만들 때 볼 것(짧게)
  - (a) 생성기 서술이 새 줄과 안 맞습니다
    - v3 생성기의 마지막 줄 검사(:23-25)는 completed_at 을 보지 않습니다. decision · note 에 D2 결정 id 가 있으면 통과하므로 새 줄도 통과합니다.
    - 그대로 다시 돌리면 VLAST = 새 줄 id 가 됩니다. 그런데 고정 서술 '(D2 — RAWDATA 원천 단절 행 Ret 정정 …)'(:29)과 결론 [8] '판 표식 VLAST = RAWDATA 원천 단절 행 Ret 정정'(:82)은 새 줄(팩터 DB 7팩터 채움 행 복원)을 잘못 설명하게 됩니다.
    - 줄별로 나눠 씁니다. D2 = RAWDATA Ret 정정(P1R03 과 다를 까닭) · 보충 줄 = D2 팩터 DB 재계산에서 빠진 채움 행 복원(측정 시작 조건)입니다.
    - DESIGN §8 이 생성 · 점검은 진행 중 줄에서 먼저 해도 된다고 적었으므로 생성기의 완료 미검사는 허용입니다. 그러면 등록 쪽 검사가 완료를 봐야 합니다(아래 (b)).
  - (b) 판 표식 원장 형식 — 이 판의 지적이 아니라 전달입니다(소관 = 이음매 세션 · `factor_db_vintage` 구성요소)
    - 새 줄 completed_at 은 `""` 입니다(원장 :171).
    - 계약은 진행 중을 null 로만 받고 `""`는 형식 오류로 멈춥니다(factor_db_vintage.R:17-18 · :89-90). 이 점검에서 `fdv_ledger` · `fdv_stamp` 를 불러 보니 둘 다 'completed_at 형식 … (진행 중이면 null) — D2-XF-FILL-RESTORE-20261114' 오류였습니다. 원장 `_doc` 은 '비우면 진행 중'이라 적어 계약과 어긋납니다.
    - P1R04 셸의 대기 검사(Python — 빈 문자열 = running · :39-40 · ecda88b47 `vtail_done`)는 맞게 기다립니다. 반면 계약 경로는 그동안 판독 불가로 닫힙니다(fail-closed). 계약 경로 = 측정 기록 판 표식 `.rp_fdv_stamp`(run_paper_replication.R:466-498) · 기저 풀 `.rcp4_fdv`(p4.R:134-142 → stale NA).
    - Python 검사는 형식이 틀린 완료 시각도 'done'으로 읽습니다. 그래서 이 판의 등록 직전 '판 표식 완료' 확인은 계약으로 합니다: `fdv_ledger` 판독 성공 ∧ `fdv_stamp()$in_progress` 없음 ∧ 마지막 줄 completed_at 채워짐.
  - (c) 판 폴더 · 순서
    - DESIGN §8 의 '등록 직전 확인'(D2 항목 completed_at) · 해제 조건 ① · `tick_hold`:1 을 '판 표식 원장 마지막 줄(지금 D2-XF-FILL-RESTORE-20261114 · 뒤에 더 붙으면 그 줄) 완료'로 고칩니다. §8 제목의 '(초안 v2 — …)' 표기도 고칩니다.
    - 새 줄 scope 에 V 계열 4팩터가 있습니다. 시드(FVALU)와 대조 상대 `P1R04_FVALU_R0` 둘 다 그 줄 완료 뒤에 재야 '같은 자료 판' 대조가 성립합니다. P1R04 셸은 이미 마지막 줄 완료와 P1S03 등록본을 기다립니다(ecda88b47 · 21:53 상태 줄) — 확인만 하면 됩니다.
    - 보충 수리가 핀 파일(37)에 닿으면 v4 초안 핀이 그 md5 를 담게 됩니다. 등록은 줄 완료 뒤에 하고(DESIGN §8 의 standing.R:231 사유와 같음), 그때 `rc_pins_mismatches` 0 을 다시 봅니다.

### 권고

없음.

### 선택

- **S-1. 노출 [2] 의 새 노출 고지가 변경 기록에 없습니다**
  - 근거: 노출 [2](:127)의 '(이음매 세션의 D1 재측정 통지에 실린 P1R03 7 엔진 시험 창 Calmar 포함 — 11-14)'는 5f7528c44 가 생성기에 더한 새 사실입니다. changes_after_review[2](:164)는 'S-2 노출 OOS 연도 표기 → τ_D 뒤'만 적었고, 이 점검의 Q 진술도 [2] 를 S-2 로만 설명했습니다. 지난 점검 기준의 '그대로' 목록 밖 변경이라 기록이 있어야 추적됩니다.
  - 판정에는 무해합니다. 노출 뒤 규칙 · 문턱 · 칸 · 선택 · 시드가 바뀌지 않았고(v1 → v3 재도출), 이 판은 선택이 없습니다.
  - 고치는 법: v4 changes_after_review 에 '노출 [2] 에 11-14 시험 창 노출 고지 추가(5f7528c44 · 규칙 고정 뒤 · 판정 무관)' 한 줄을 더합니다.
- **S-2. 노출 [4] 의 잔여 서술 둘(v2 R-1 잔여 · 작음)**
  - '바뀐 것' 목록에 등급 v3.5 6파일 핀이 없습니다. 같은 잎 첫 문장('등급 v3.5 핀 교체 … 뒤에 만들었다')에만 있습니다. v2 R-1 ④ 가 짚은 그대로입니다. '코어 판(v4)'은 pins.core 만 가리킵니다.
  - '(T1 11칸 뒤) 중단'은 보관 폴더 이름 · 시각으로 보면 '10칸 완료 · 11번째(ICONS) 측정 중 중단'입니다(fp_start 11 · fp_end 10 · ICONS 는 10:30 fp_start 뿐).
  - 고치는 법: v4 에서 목록에 '등급 v3.5 핀(6파일)'을 넣고, '10칸 뒤(11번째 측정 중)'으로 고칩니다.

### 초안 v4 를 만들 때(v3 → v4 변경분 점검 기준)

- 그대로여야 하는 것
  - rules · cells · selection · standing_cfg · tests · behavior_card_cfg · purpose · pins.files · pins.basis 를 그대로 둡니다.
  - 시드 c23f930e 를 그대로 둡니다(등록부 원천 칸이 그대로면).
  - 노출 [0] [1] [3] [5]-[7] 과 결론 [0]-[7] · [10]-[24] 를 그대로 둡니다.
  - 노출 [2] 는 그대로 둡니다. 새 노출이 생기면 더하고 기록합니다.
  - 핀 37 경로를 그대로 둡니다. 보충 수리가 핀 파일에 닿지 않았다면 md5 도 같습니다.
- 바뀌어야 하는 것
  - 사양: 가설 · 결론 [8] [9] 의 판 표식 글(M-1 (a) — 줄별 서술) · 노출 [4](초안 판 번호 · 'D1 · D2 · 보충 줄 뒤' · S-2) · changes_after_review 더함(이 점검 v3 · S-1)입니다.
  - 판 폴더: DESIGN §8 · tick_hold(M-1 (c))입니다.
- 확인 방법
  - 잎 차이가 위 목록뿐인지 봅니다.
  - 판 표식 id 가 원장 마지막 줄과 같고 그 줄이 계약 판독으로 완료인지 봅니다(M-1 (b)).
  - `rc_after_tau_leaks` 빈 결과를 봅니다.
  - 등록 직전 standing-check 시드 회계 = 규칙 · P1R04 평가 산출 없음 · `rc_pins_mismatches` 0 을 봅니다.

## 3. 못 본 것

- 생성기 재실행 2회 md5 동일(Q 진술)은 재도출하지 않았습니다(실행 금지). 생성기 글(:54-69 · :74-108 · :127-141)과 사양 바뀐 잎을 읽어 대조했습니다(VLAST = D2 결정 id 일 때 글자 그대로 일치). 지금 원장으로 다시 돌리면 VLAST 가 새 줄 id 가 되어 md5 가 달라집니다(M-1 (a)).
- 새 줄의 내용 · 영향 크기 · 진행 상황 · 보충 수리가 닿는 코드는 보지 않았습니다(Q 지시 — 재조사 생략). scope 필드와 decision 문자열만 봤습니다.
- 결정 기록부 D2 항목 · 원장 항목 note · 철학 · 판단 리뷰 본문은 보지 않았습니다.
- 코어 v4 자체 · 시험 묶음 재실행은 하지 않았습니다. 측정 · 판정 · 보고 실행도 하지 않았습니다.
- standing-check 는 CLI 가 아니라 같은 계산을 읽기 전용으로 돌렸습니다(CLI 는 판 폴더 `standing_rules.md` 를 다시 씁니다).
- 결과 · 판정 파일 · 권위 기록 · 텔레그램 기록 · P1R04 보관 폴더 파일 내용은 정보 경계로 보지 않았습니다.
