# P1S04 사전등록 초안 격리 변경분 점검 v2(초안 v1 → v2)

- 점검자: 격리 변경분 점검(서브에이전트 — 점검 v1 과 같은 점검자). 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(철학 정렬 · 판단 감독 몫은 판단하지 않았다). 점검 시각 2026-11-15 06:01~06:10(KST) · HEAD 시작 · 끝 모두 `6280c49ec`.
- 점검 종류: 변경분 점검 — 기준 = 초안 v1(커밋 `39e16a8f2` · 사양 7f26e14b · 초안 e8589cc4) · 범위 = v1 → v2 변경분 + 점검 v1(`prereg_draft_review_v1.md` · 32a809c0 · ok · 권고 3 · 선택 8)의 반영 여부.
- 대상(md5)
  - `round_spec.json` **3c619c281f583ad9cca5d9281a9ef8f0** · `prereg_draft.json`(draft_version 2 · cc9a58ea) · `prereg_draft.md`(3d391686) · `drafts.json`(1a46385c · v1 review = ok · 점검 파일 32a809c0 · git_head 39e16a8f2 / v2 review = null) · `tools/init_p1s04_v2.R`(825eef21 · 새 파일) · `DESIGN.md`(96170542) · `standing_rules.md`(c4580f49 — 다시 생성 · v1 과 같은 바이트라 커밋 diff 에 없다).
  - v1 과 같은 md5: `specs/P1S04_E2_C0.json`(b748062d) · `specs/P1S04_E3_RX0.json`(60a9d823) · `behavior_card_cfg_at_prereg.json`(6a2a1d21) · `tick_hold`(01a249d8) · `tools/init_p1s04.R`(eec03ff7) · 코어 v4 매니페스트 95d4a286.
  - 참고: 요청의 'prereg_draft.md md5 cc9a58ea' 는 `prereg_draft.json` 의 md5 다(md = 3d391686 · drafts.json v2 md5_md 와 같다). 파일 결함은 아니다.
- **판정: ok** — v1 → v2 변경은 진술대로 사양 문장(노출 [10] · 결론 범위 [21] · [22] 고침 · [23] · [24] 추가 · changes_after_review 2줄)과 DESIGN §2 · §5 · §6 뿐이다. 고정 블록(규칙 · 문턱 · 선택 · 시드 칸 · 입구 · 핀 · standing_cfg · 목적 · 가설 · 그 밖 노출 11줄 · 결론 범위 [1]~[20])은 바이트 동일이다. 핀 불일치 0 · 등록 조건은 감독 영수증(철학 P1 · 판단 T1)과 이 점검 기록 말고 모두 선다. 새 줄에 τ_D 뒤 성과 수치 · 등급 표기는 없다. 점검 v1 권고 3 · 선택 8 은 모두 반영됐다.
  - 권고 하나는 v2 가 새로 넣은 [23] 의 절차 문장이다. 이 문장은 점검 v1 R-1 (가)에 점검자가 적어 준 문안 그대로이고, 그 문안의 결함이다. '걸음 전에 … 사슬 판 판단 T1 이 확인한다' 의 '걸음' 쪽에는 확인자가 없다. 사양을 고치려면 초안 v3 + 변경분 점검, 사양을 두려면 DESIGN 에 뜻을 적는다. 판정에는 닿지 않고 등록을 막지 않는다.
- **건수: 필수 0 · 권고 1 · 선택 3**

## 0. 정보 경계 선언

- 경계는 점검 v1 §0 과 같다(안 연 것 목록 그대로).
- 이번에 더 연 것
  - 커밋 `6280c49ec` 의 변경 파일 7개 — 사양 · 초안(json · md) · drafts.json · DESIGN.md · 점검 v1 파일(내 파일 · md5 대조) · `tools/init_p1s04_v2.R` 전문.
  - v1 비교본: `git show 39e16a8f2:<경로>` 사본(세션 스크래치 폴더).
  - 운영(grep): `02_Infrastructure/ops/chain_tick.sh`(6-7 · 37 · 229) · `.claude/agents/superfan.md`(42 · 67).
  - P4C01 `chain_spec.json` 의 purpose 문장 · generator 키 · `tick_hold` 첫 줄(규칙 문장 · 성과 수치 없음).
- 우연 열람: 없다.
- 실행한 것: Rscript 임시 스크립트 1개(`source(v4/load.R)` 뒤 재도출 · 임시 파일 쓰기만) · Python 구조 diff 2회 · `diff` · `git diff`. 저장소 쓰기 = 이 파일 하나. `scan --dry-run` 은 이번에도 돌리지 않았다(노출 [12]).

## 1. 판정

**ok.**

- 변경분 = 진술과 같다. 사양 바이트 diff 는 줄 134(노출 [10]) · 159-166(결론 범위 [21]~[24] + changes_after_review 2줄)과 v1 의 빈 `changes_after_review` 줄 삭제뿐이다(§3-1).
- 도구 `init_p1s04_v2.R` 의 대입부(줄 15-38)를 v1 사양 사본에 적용해 `rc_json_write` 로 쓰면 md5 가 v2 디스크(3c619c28)와 같다 → v2 사양 = v1 + 도구 대입 그대로다(손 편집 없음).
- 점검 v1 항목 11개 반영 — 표 §3-2. 사양 안 5(R-1 · R-2 · S-1 · S-2 · S-4) · 사양 밖 6(R-3 · S-3 · S-5 · S-6 · S-7 · S-8).
- 핀 · 등록 조건 · 정보 경계(§3-3 · §3-4).

## 2. 지적

### 필수

없음.

### 권고

**R-A. 결론 범위 [23] 의 '이 판 통과 칸을 기저 · 블렌드 상대로 받는 사슬 판 등록 · 걸음 전에 … 사슬 판 판단 T1 이 확인한다'에서 '걸음 전' 확인자가 없다 — 점검 v1 R-1 (가) 문안(점검자 문안)의 결함**

- 주장
  - 판단 T1 은 사슬 판 등록 때 한 번이다. 사슬 판 등록은 철학 P1 · 판단 T1 영수증을 요구한다(p4.R:993-994). 판단 Superfan 은 "강화 사슬의 걸음마다는 리뷰하지 않는다 … 사슬 판 등록(T1)과 닫기(T2)만 본다"(.claude/agents/superfan.md:67 · 규약 §13-1).
  - 걸음은 무인 틱이 연다(chain_tick.sh:6 '다음 걸음 설계 … round.sh p4-step-open' · :37 허용 목록에 p4-step-open · :229). 걸음 열기의 기계 검사는 블렌드 상대에 '풀 자격'만 본다(p4.R:1143-1147). 사슬 사양에는 부품 허용 목록 키가 없다 — 부품 범위는 사슬 목적(purpose) 문장이고 생성기가 지킨다(P4C01 purpose '기계 차단 없음 · 생성기가 지킨다').
  - 그래서 사슬 판을 등록한 뒤 이 판에서 통과한 칸이 풀에 들면, 그 칸을 목적에서 막지 않은 사슬의 무인 걸음은 P2 판독 확인 없이 그 칸을 상대로 열 수 있다. 등록 때 확인(기저 · 그때 목적에 적힌 부품)은 선다(superfan.md:42 '기저 선택(사슬 판 등록 · T1)').
  - 지금 닿는 곳은 없다. 유일한 활성 사슬 P4C01 은 목적이 부품을 자체 사양 동일가중 엔진으로 묶어 이 판 칸을 쓰지 않는다. 사슬 2호부터 닿는다.
  - 덧붙여 문장 속 명령 `superfan-mark --kind pass --p2` 는 `--codes <code>` 가 필수다(standing.R:1762). 리뷰 id 를 읽는 자리는 `rc_standing_qualified` 의 superfan_pass_p2 열이다(standing.R:414-427).
- 근거: round_spec.json:161([23]) · p4.R:993-994 · 1143-1147 · chain_tick.sh:6-7 · 37 · 229 · .claude/agents/superfan.md:42 · 67 · P4C01 chain_spec.json purpose · standing.R:1762.
- 판정에는 닿지 않는다(P1 판정 · 원장 그대로 · P4 의 소비 절차). 등록을 막지 않는다.
- 고칠 것(둘 중 하나)
  - (가) 초안 v3: [23] 의 절차를 실행자가 있는 문장으로 — '이 판 통과 칸을 기저 · 부품으로 쓰는 사슬 판은 등록 때 판단 T1 이 그 칸의 철학 P2 리뷰 id(superfan-mark --codes <code> --kind pass --p2 · rc_standing_qualified 의 superfan_pass_p2)를 확인하고, 확인한 칸만 사슬 목적(purpose)의 기저 · 부품 범위로 적는다(생성기가 지킨다 · 기계 차단 없음). 사슬 판 등록 뒤 통과한 이 판 칸은 그 사슬의 부품이 아니다(새 사슬 판에서 같은 확인).' + 변경분 점검.
  - (나) 사양은 두고 DESIGN §6 에 '[23] 의 "걸음 전" = 사슬 판 등록 때 T1 이 확인해 사슬 목적에 적은 기저 · 부품 범위(무인 걸음은 그 범위 밖 이 판 칸을 쓰지 않는다 — 생성기가 지킨다)' 처럼 뜻 · 실행자를 적고, 다음 사슬 판 등록의 판단 T1 · 철학 P1 에 그 뜻을 넘긴다(판 2 점검 v2 R-3 선례 — 문장은 두고 DESIGN 에서 뜻을 정한다).

### 선택

- **S-A. DESIGN 에 v1 문구가 남았다** — §1 '판 2 는 측정 0건 · 판정 0건으로 멈췄다'(DESIGN.md:8)는 사양 노출 [10](S-1 반영 — '측정 성공 0건 · E2 시도 1회 실패 · 산출 없음')과 다르다. 머리의 '사양 생성 = `tools/init_p1s04.R`'(DESIGN.md:5)에는 v2 문장 고침 도구 `init_p1s04_v2.R` 이 없다. 사고 기록이라 판정과 무관하다. 같은 말로 맞춘다. (`init_p1s04.R:9` 의 '46/46' 은 v1 도구 실행 기록 주석이라 그대로 둬도 된다.)
- **S-B. 점검 v1 R-3 의 넷째 항목이 DESIGN §5 에 없다** — 판정 전 점검 기대값 `--expect-engine-dates 268`(판 2 DESIGN §5-4 · §5-6)은 측정 때 자료의 마지막 월말까지 다시 센 수로 넣는다(판 2 점검 v2 S-1 · 판 3 측정은 더 늦다). §5-3 · §5-4 에 한 줄. 첫 엔진 신호일 2004-07-30 은 자료 판과 무관해 그대로다.
- **S-C. [24] 가 코어 정보 경계 검사(`rc_input_issues`)에 걸린다** — 같은 칸에 '시험 창 줄'(낱말)과 '판 2 점검 v2 S-6'(항목 이름의 'S-6' 을 지표 S + 수로 읽는다)이 있다. 거짓 양성이고 등록 조건 밖이다(rc_register 는 이 검사를 부르지 않는다). 새 줄이라 깨끗이 두려면 항목 번호를 빼거나 낱말로 쓴다('판 2 점검 v2 의 선택 지적'). 'S 6' · 'S6' · '6번' 도 같은 규칙에 걸린다. 초안 v3 를 만들 때만 함께.

## 3. 확인한 것(통과 · 근거)

### 3-1. 변경분 전수 · 고정 블록

- 사양 바이트 diff(v1 7f26e14b ↔ v2 3c619c28): `134c134`(노출 [10]) · `159,160c159,166`(결론 범위 [21] · [22] 고침 + [23] · [24] 추가 + changes_after_review 블록) · `162d167`(v1 의 빈 `"changes_after_review": [],` 줄). 그 밖의 줄은 바이트 동일이다 — 고정 블록(1-133 · 135-158)과 changes_after_superfan · tests · behavior_card_cfg · pins 를 포함한다.
- JSON 대조: 고정 키 17개(schema · program · round_id · template · core_version · tau_d · purpose · hypothesis · standing · standing_cfg · cells · rules · selection · changes_after_superfan · tests · behavior_card_cfg · pins)가 v1 과 같다. 노출은 [10] 말고 11줄이 같은 위치에서 같다. 결론 범위 [1]~[20] 이 같다.
- 초안 v1 ↔ v2: draft_version · drafted_at · spec(위 변경) · spec_md5 만 다르다. pins · cells · rules_resolved · sentences · behavior_card_cfg · core 는 JSON 동일이다.
- 재생성: `rc_prereg_md(pre)` = 3d391686 = 디스크 = drafts.json v2 md5_md · `rc_standing_rules_md(spec)` = c4580f49 = 디스크(v1 과 같은 바이트) · `rc_rules_resolve` 지금 = 초안.
- 도구 재현: `init_p1s04_v2.R` 줄 15-38(사양 판독 · 위치 단정 · 대입 · changes_after_review)을 v1 사양 사본에 적용 → `rc_json_write` md5 3c619c28 = v2 디스크. 도구의 안전장치 — 등록본 있으면 멈춤(:12) · drafts = v1 하나 + ok(:14) · 줄 위치 단정(:17-18) · `rc_standing_validate`(:39). 지금은 drafts 가 둘이라 다시 돌지 않는다(한 번 쓰는 도구).

### 3-2. 점검 v1 반영 대조

| v1 항목 | v2 위치 | 판독 |
|---|---|---|
| R-1 (가) | 결론 범위 [23] · DESIGN §6 | 반영 — 사실 진술(철학 관문 · 사슬 등록 확인 = 자체 사양 행만 · 레인 칸 · 시드 = 기계 관문 없음 · 다음 코어 판 후보)은 맞다(p4.R:18-19 · 250-263 · 986-1023). 절차 문장의 '걸음 전' 확인자 없음 = R-A |
| R-2 (가) | 결론 범위 [24] · DESIGN §6 | 반영 — '코어 v3' 넷 = v4 레인 갈래 같은 동작 · [20] 괄호 = v4 에서 갈림(standing.R:1494-1533 · OOS 줄 :1520) · P2 한 줄 자동 통로 없음 → 판 2 DESIGN §5 절차(세션) 모두 맞다 |
| R-3 | 결론 범위 [22] · DESIGN §5-3 | 반영 — v4 지문(결합용 뷰) · v4 load.R · 시간 가정 다시(워커 3 · 내용 주소 캐시) · 등록 뒤 · 측정 전에 만든다. 넷째(기대값 다시 세기)는 빠짐 = S-B |
| S-1 | 노출 [10] | 반영 — '측정 성공 0건 · 판정 0건 · E2 시도 1회 실패 · 산출 없음 · 성과 값 없음'(판 2 원장 측정 줄과 맞다). 'Q 는 그 시도의 로그를 보지 않았다'는 Q 진술이라 점검자가 다시 도출할 수 없다(그 로그 형식은 학습 진행 줄이다 — engine.R:659 · 694). DESIGN §1 문구 = S-A |
| S-2 | 결론 범위 [21] · [22] | 반영 — '[3]~[20] 18 줄(앞 [1] · [2] = 코어 v4 레인 철학 줄)' · '판 3 DESIGN §5(판 2 §5 승계 · 리허설 없음)' |
| S-3 | DESIGN §2 · §5-2 | 반영 — 71 통과 · 0 실패(RELEASES v4) · O4 레인 후보 표 · scan 순서 dry-run → `--max 0`(standing.R:1243) → scan |
| S-4 | 결론 범위 [24] 끝 문장 | 반영 — [13] '같은 학습창 · 시드(자료 판은 다를 수 있다 — DNN 캐시는 입력 내용 주소)' |
| S-5 | DESIGN §5-5 | 반영 — 상설 단계만(비상설 measure · evaluate 금지) |
| S-6 | DESIGN §5-4 | 반영 — 측정 로그 torch 판 확인 · 등록과 측정 사이 venv 불변 |
| S-7 | DESIGN §5-6 | 반영 — 핀 대상 교체를 '측정 · 평가 끝난 뒤 미러 → 원자 교체'로 미룬다 |
| S-8 | DESIGN §6 | 반영 — scan_stale 갈래 모름 · 26시간 warn 가능 |

- changes_after_review 2줄은 위 반영을 사양 안 · 사양 밖으로 정확히 나눠 적었다.

### 3-3. 핀 · 등록 조건(register.R:107-145)

- `rc_pins_mismatches(pre$pins, rc_root())` = **0건**. `rc_pins_compute(spec)` = 초안 35 파일 · md5 집합이 같고 코어는 95d4a286 이다. 초안 v2 pins = 초안 v1 pins(JSON 동일)다.
- ① 점검 기록: v1 review = ok(파일 md5 32a809c0 = 지금 점검 v1 파일 · git_head 39e16a8f2). 마지막 초안 v2 의 review = null 이다. 이 점검 뒤 `round.sh <판> reviewed 2 <이 파일> ok` 가 채운다.
- ② 디스크 초안 md5 cc9a58ea = drafts.json v2 md5 · 사양 md5 3c619c28 = 초안 spec_md5 · 초안 안 spec 사본 = 디스크 사양(JSON 동일).
- ③ 칸 사양 md5 2개 = 초안 cells(v1 과 같다).
- ④ 핀 불일치 0.
- ⑤ 리허설 키 없음 → 통과. ⑥ tests [] → 통과.
- ⑦ `rc_uncommitted` = 0. 이 파일은 필터(`prereg_draft`) 안이라 막지 않는다.
- ⑧ 철학 P1 · 판단 T1 = 범위 밖.
- `rc_standing_validate(check_pin = TRUE)` 통과 · 생성 함수 핀 차이 0.

### 3-4. 정보 경계(새 줄 · 바뀐 줄)

- `rc_input_issues`(v4 util.R:209-225) 결과
  - 노출 [10] · 결론 범위 [21] · [22] · [23] · changes_after_review 2줄 = 통과.
  - [24] = 거짓 양성 하나(S-C — 항목 이름 'S-6' 과 '시험 창' 낱말이 한 칸에 있다).
  - 새 줄 전체 등급 표기(`.rc_grade_hits`) = 0.
- DESIGN.md: 등급 표기 0 · 시험 창 수치 0. 걸린 것은 결정 id 안 날짜뿐이다. `init_p1s04_v2.R`: 등급 표기 0 · 시험 창 수치 0.
- 새 줄에 τ_D 뒤 성과 수치 · 날짜는 없다. 날짜는 결정 id · 도구 주석의 것뿐이다.

## 4. 못 본 것

- 철학 P1 · 판단 T1 판독(범위 밖).
- 레인 미리보기(`scan --dry-run` — 이번에도 돌리지 않았다).
- 노출 [10] 의 'Q 는 그 시도의 로그를 보지 않았다'(진술 — 재도출 불가).
- 감시 셸 · 판정 전 점검 이식본(아직 없음 · 등록 뒤 만든다).
- 사슬 2호 이후의 사슬 목적 문장.
