# P2R04 사전등록 초안 격리 교차 점검 v2 (v1 → v2 변경분)

- 점검자: 격리 교차 점검(서브에이전트 · 이 라운드 설계 · 구현 비참여 · 측정 결과 없음) · 2026-10-18
- 대상(md5 앞 8자리): `prereg_draft.json` v2(211b62d0) · v1 보존본 `prereg_draft_reviewed_v1.json`(79f3ff1d = v1 점검 대상과 같음) · `evaluate.R`(d7c9adb1) · `evaluate_fixture.R`(1e3a03d6) · `rehearse.R`(3aba7c41) · `rehearsal/summary.json`(dfba81a5) · `register.R`(f13e95c5) · `precheck.R`(f09ca3db) · `notify.R`(eca01a88) · `DESIGN.md`(f115c97c). 바뀌지 않은 것: `fingerprint.sh`(f7e1974a) · `measure.sh` · `measure_now*.sh` · `round_rules.R` · `notify_done.sh` · `specs/` 23 · 행동 카드 사본.
- **판정: revise(좁은 범위)** — v1 필수 6건은 문장 · 코드 · 사전등록에서 모두 닫혔다(재현 포함). 다만 v2 가 코드로 넣은 **R7 '판독 불가' 규칙이 사전등록 문장 · DESIGN · 변경 기록 · 판단 원장 어디에도 없다** — 묶일 문장과 묶일 코드가 다시 어긋났다(필수 1). **고칠 곳은 문장뿐이다**(register.R · DESIGN.md — 평가 경로 핀 밖). evaluate.R 을 건드리지 않으면 리허설 · 픽스처 기록은 그대로 유효하다.
- **건수: 필수 1 · 권고 6 · 선택 6**

## 0. 정보 경계 선언

- 연 것: 위 v2 파일 전부 · v1 보존본(필드 diff) · 판단 원장 `q_judgment_ledger.json` 의 C-20261018-028 · 029 응답 줄 · `matched_controls.R`(통제 상태 값 · 라벨 어휘 줄) · `_lib/detached_env.sh`(PATH 줄) · git 추적 상태(P2R03 사전등록 두 사본)
- **안 연 것**: 어떤 results/ · evaluation_full · full/ · 칸 json · 로그 · 차트(P2R03 포함). 시험 창 · 전기간 성과 수치를 본 것 없음.
- 실행한 것(쓰기 = 스크래치패드 · R 임시 폴더뿐): `Rscript evaluate_fixture.R` → **52/0 · 뮤테이션 34/34** · v1 재현 R1~R4 를 v2 함수로 재실행(+ R5 · R7) · `Rscript precheck.R --dry`(results/ 미작성 확인) · precheck 대조 함수 양성 대조 2건(러너 축 · 커밋 확인). 측정 · 등록 · 커밋 · 프로젝트 파일 수정(이 파일 밖) 없음.

## 1. v1 필수 6건 — 닫혔는가(재현)

| v1 필수 | v2 상태 | 재현 · 근거 |
|---|---|---|
| 1 ⑭ 분해 문턱 | **닫힘** — 문장(`prereg_draft.json:882` · DESIGN `:110` · §0c `:9`) = 코드(`evaluate.R:499` `sv - sr > 0`) = "깊은 위기마다 변형 − RX0 > 0(엄격 · 문턱 없음) 과반 · 짝 ≥ 2". crisis_improve_min 을 쓰지 않는다. 조정자 결정('> tol' 대신 '> 0')은 changes_after_review[0] 에 기록 · 판단 원장 C-028 수용 문구("RX0 보다 개선")와 같은 뜻 | **R1(v1 재료 그대로) → 3/4 통과 = 문장 결과** · 동률(차 0) = 개선 아님(2/4 미달) · 픽스처 27 경계(+0.001 = 개선) · 뮤테이션 '> → >='와 '0.03 재도입'이 둘 다 죽는다 |
| 2 tested ⑥ | **닫힘** — ⑥ 목록에서 ⑭ 제거 + "⑭ 결손은 미시험이 아니다 — ⑭ 미측정(판정됨 · 통과 불가)"(`:871`) = 코드(유한 검사 `inp` 에 ⑭ 없음 `:1171-1172`) | 문장 대조 |
| 3 ⑭ 미측정 판정어 | **닫힘** — `selection_unmeasured`(`:59` · `:593`) · 결론 이름 보류(`:599-606` — ③ · ④ NA · ⑤ 수준 NA · ⑭ 미측정) · MC8 라벨이 확정 4종 밖(insufficient · 없음 · 모르는 값)이거나 통제 상태 ≠ ok = 미측정(`:482-486`) · 호출부가 새 인자 모두 전달(`:1186-1187` · `:1255-1260`) · notify.R 어휘 · 픽스처 29 | **R2** 분해 필드 결손 → selection_unmeasured · '방어 이름 보류(⑭ 선택 귀속 미측정)' · insufficient = 미측정 · 통제 상태 no_crises = 미측정 · **R2b** 측정됨 · 미통과(size_defense) → 그대로 size_or_exposure_defense · **R3** ③ NA → '방어 이름 보류(③ · ④ β 짝 미측정)' · 리허설 R2(실제 패킷 · 공통 창 · k 0.9)에서 ⑭ 가 '측정됨'으로 읽혀 size_or_exposure_defense — 새 '측정됨' 경로가 실패킷에서 동작한다(통제 상태 정상값 = "ok" — `matched_controls.R:409`) |
| 4 진단 칸 지문 | **닫힘** — vintage_group · diagnostics · failure_semantics(`:873` · `:887` · `:889`) = 코드(`evaluate.R:1318-1338` — 판정 칸 불일치 = 전체 중단 · 진단 칸 = 그 칸만 미시험) | 문장 대조 |
| 5 러너 축 | **닫힘(v1 이 허용한 최소판)** — precheck 본 대조 · 건식이 reinforce_program.json fixed_axes.{n_max, commission_bps} = 23칸 사양 값(하나로 같아야 함)을 단정 · precheck.json 기록(`precheck.R:66-82` · `:178` · `:187`) · 사전등록 precheck 문장(`:1622`) | 건식: **일치(n_max 25/25 · commission 15/15)** · 양성 대조: 사양 20bps → '러너 축 … 15 ≠ 사양 20 — 워커가 다른 값으로 잰다' · 칸마다 n_max 다름 → '칸마다 다르거나 없다(25/20)' |
| 6 DESIGN 낡은 문장 | **닫힘** — §2(`:58`) · §4(`:88` · E3 W 구성 차이 문장 포함) · §10(`:159` · 혼합 몫 유도 = mix_plan · spec_checks) | 문장 대조 · 남은 것 = 머리 상태 줄(선택 3) · §5 R7 문장(필수 1) |

v1 권고 중 반영 확인: 권고 2(라운드 라벨 판정어별 칸 수 — 재현 R4 `falsified(판정 8/8 · β 짝 미측정 8)`) · 권고 3(R7 판정 장치 수 — 필수 1 참고) · 권고 5(사전등록 커밋 확인 — 아래 §4) · 권고 6(E3 W 구성 비 1:1 → 4:3 기록 · `:686-691`) · 권고 7(보는 창 밖 사본 표식 — `:79-87` · `:122` · `:145` · `:1094` · `:1141`) · 권고 8(결론 범위 8 · selection_attribution) · 권고 11(data_note · 결론 범위 9) · 선택 3(vintage_group 에 IC 월간 이력) · 선택 4(머리 주석 7행).

## 2. 남은 필수

### 필수 1 — R7 '판독 불가' 규칙이 코드에만 있다 (묶일 문장 · DESIGN · 변경 기록 · 원장 정의와 다르다)

- 코드: `evaluate.R:731-753`(`:746-747`) — `readable <- nb >= 2L`(nb = 두 구성 모두 S 증분이 유한한 장치 수) · `res <- if (!readable) NA else c1 && c2 && c3`.
- 문장: `prereg_draft.json:886`(← `register.R:509`) "R7 판독 … 라운드 '잡음 이내' = 검증 0 ∧ 두 구성에서 ③ 비율 > 0.5 인 장치 0 ∧ S 증분(두 구성 평균) 최대 < tie_eps" — 판독 불가 조건이 없다. `DESIGN.md:120`(§5) 도 같다. changes_after_review 10건에 이 변경이 없다(DESIGN §0c `:16` 에만 한 줄). 판단 원장 C-20261018-029 의 수용 변경(12:38)도 3조건 정의 그대로다.
- 재현 R5(evaluate.R 함수 그대로): 장치 1개만 두 구성 판정(S 증분 +0.001 · ③ 0.25) → 코드 = **NA('판독 불가(두 구성 판정 장치 1/4 < 2)')** · 문장대로 = **참('잡음 이내')**(검증 0 ∧ ③ 과반 장치 0 ∧ 0.001 < 0.02). 같은 평가 결과에서 프로그램 예산 R7(연속 K회 잡음 이내 → 종료 검토)의 입력이 갈린다.
- 왜 필수: v1 필수 1 · 2 · 4 와 같은 종류다 — 사전등록 문장과 사전등록 md5 로 묶인 코드가 다른 것을 말하면 등록 뒤에는 어느 쪽도 고칠 수 없다(R2).
- 고칠 방법(문장만 · evaluate.R 무변경 → 리허설 · 픽스처 유효): `register.R:509` r7_reading 에 "두 구성 모두 판정된 장치(두 칸 S 증분 유한)가 2개 미만이면 판독 불가(NA — 부분 판정으로 예산을 소모하지 않는다 · 2 = 다른 규칙의 '짝 ≥ 2' 관례) · 판정 장치 수/4 를 함께 적는다"를 넣는다 → `DESIGN.md:120` 같은 문장 → changes_after_review 에 'v1 권고 3 R7 판독 불가(evaluate.R p2_noise_reading)' 항목 → 판단 원장 C-029 에 응답 한 줄(정의 보강). 같은 문장에서 권고 1(③ 미측정 장치의 처리)을 정하면 R7 정의가 한 번에 닫힌다. 초안 v3 재작성(`DRAFT_VERSION` 3 · `prereg_draft_reviewed_v2.json` 보존 — register.R 의 초안 관문 `:254-256` 이 요구한다).

## 3. 권고 (비차단 — 필수 1 의 같은 재작성에서)

1. **R7 의 '판정 장치'가 ③ 측정 여부를 보지 않는다**(v1 부터 있던 경로 · v2 가 세운 '부분 판정으로 예산을 소모하지 않는다' 원칙과 같은 자리). `judged_both` = 두 칸 S 증분 유한뿐(`evaluate.R:740`)이고, c2(③ 과반 장치 0)는 ③ 비율 NA 를 '과반 아님'으로 접는다(`:739` — `p2_maj(NA)` = 거짓). 재현: 8칸이 모두 β 대조 미측정(③ NA)이고 S 증분이 작으면 **R7 = '잡음 이내'(판정 4/4)**. 두 길 중 하나 — (a) 판정 장치 = 두 칸 tested ∧ ③ status ok(evaluate.R 변경 · 픽스처 · 리허설 재실행) (b) 문장만 — r7_reading 에 "③ 미측정 장치는 '③ 과반 아님'으로 센다(판독 불가로 세지 않는다)"를 명시. (b) 면 결정이 문장에 드러난다.
2. **같은 재작성에서 문장을 코드에 맞출 셋**: round_verdict(`:885` — 라벨에 판정어별 칸 수가 붙는다 · `evaluate.R:610-631` · 재현 R4) · files(`:890` — 보는 창 밖 사본 표식 · "보는 창 리뷰어 열람 가능 = evaluation_visible.json · `<code>/visible/` · `<code>/{original,common_*}/visible*/` 뿐 · `<code>/{original,common_*}/` 의 artifacts · rx0_artifacts · rx0_beta_scaled = 전기간 사본") · changes_after_review 에 v1 권고 2 · 6 · 7 항목(코드는 바뀌었는데 변경 기록 10건에 없다 — DESIGN §0c `:16` 에만).
3. **등록 관문이 '점검받은 판 = 등록할 판'을 보지 않는다.** `register.R:374` `if (!length(REVIEWED))` 는 보존본이 하나라도 있으면 통과한다 — 지금도 `prereg_draft_reviewed_v1.json` 만으로 v2 를 등록할 수 있다(v2 점검 결과와 무관). register 모드에 "`prereg_draft_reviewed_v<draft_version>.json` 존재 ∧ 그 md5 = `prereg_draft.json` md5" 단정 두 줄. register.R 은 평가 경로 핀 밖이라 언제든 고칠 수 있다(라운드 폴더 커밋 대상).
4. **v1 권고 1 그대로** — ⑩ 문장(`:879`)의 '사양 = RX0 + 장치 팩터 r 회 · base_weight = 혼합 몫 유도값' 조항은 evaluate.R 이 아니라 등록 spec_checks + 사양 md5 핀이 보증한다(판정 칸 혼합 가중 대조 없음 · `evaluate.R:1069-1076` 은 진단 칸만). 결과는 같으니 문장에 "(등록 시 spec_checks 단정 · 사양 md5 핀)"을 적는다.
5. **v1 권고 10 그대로** — 'H1 대 P2R03 D1 대조 읽기'는 changes_after_superfan 의 C-025 항목(`:1696-1698`)에만 있고 rules.record · evaluate.R 에 없다. record 에 넣거나 '세션 보고 단계'로 고친다.
6. **v1 권고 4 · 9 그대로(비차단)** — 처치 방향 대체 신호일은 꼬리표뿐이다(설계 노트는 2005-01 ~ 만 쟀다 — 결과 보고에서 칸마다 `construction.factor_direction.registry_fallback = 0` 확인 · SUMMARY 에 없다) · 평가 지문 ≠ 측정 지문은 기록만 한다(`evaluate.R:1323`).

## 4. 선택

1. evaluate.R 낡은 주석: `:8-9` '⑭ … tol 이상 개선' · `:1064` '사양(변형 = RX0 + 장치 팩터 하나)' · `:1183-1184` '⑭ … tol 이상 개선'. 동작과 무관하다 — evaluate.R 을 다시 고칠 때만(고치면 md5 → 픽스처 · 리허설 재실행).
2. `p2_defense_name(…, s14_measured = TRUE)`(`:599`)는 빠뜨리면 미측정을 측정으로 읽는 열린 기본값이다 — 호출부는 넘긴다(`:1256`). evaluate.R 을 고칠 때 기본값을 FALSE 로.
3. `DESIGN.md:3` 머리 상태 "격리 교차 점검 전" → v1 반영 · v2 점검. §8 결론 범위는 1~7 만 있다(사전등록은 1~9 · 2번 '⑭ 미측정 → 이름 보류') — DESIGN 이 '정본 = 사전등록'이라 적어 두어 비차단.
4. `mc8_label_required_evidence`(사전등록 final_selection_rule ← `round_rules.R:46-48`)는 insufficient 를 '통과 불가'로만 적는다 — '⑭ 미측정(통과 불가)'과 모순은 아니다. round_rules.R 은 평가 경로 핀이자 리허설 기록 md5 라 그대로 둬도 된다.
5. 러너 축은 측정 직전(precheck)만 본다 — 측정 중 변경까지 막으려면 fingerprint.sh equality 에 두 키 값 한 줄(묶음 지문 → 재측정). fingerprint.sh 는 평가 경로 핀.
6. selection_attribution · failure_semantics 의 '오류'를 "MC8 통제 상태(controls.status) ≠ ok — no_holdings · no_windows · no_basket · no_crises · not_applicable_long_short"로 적으면 코드(`evaluate.R:485`)와 낱말까지 같아진다.

## 5. 새 불일치 · 누출 · 실패 의미 점검 — 확인한 것(결함 없음)

- **정보 경계**: 새 표식은 results/<code>/ 아래 사본 폴더(common_*/{., artifacts, rx0_artifacts} · {original, common_*}/rx0_beta_scaled · 그 상위)에만 쓴다 — 측정 산출물 폴더는 건드리지 않고(`p2_beta_scaled_copy` · `p2_trim_artifacts` 는 산출물을 읽기만) · visible* 패킷 폴더엔 표식이 없다(리허설 단정). `.dp_read` · `ta_resolve_artifact` 는 .txt 를 읽지 않는다. 새 출력(R7 label · 판정어별 칸 수 · 구성 비 1:1/4:3 · SUMMARY selection_status · selection_decomp_ok · precheck.json runner_axes · prereg_commit)에 성과 수치 · τ_D 이후 날짜 없음. `p2_visible_only` · `dp_scan_dates` · 칸 평가 콘솔 줄(보는 창 값) 불변. 알림 = evaluation_visible.json 만.
- **PIT · 측정 기계**: 셀 엔진 · 워커 · 측정 절차 · 지문 · 사양 · 행동 카드 사본 불변. v2 초안의 핀(운영 38 · 평가 8 · 사양 23 · 검사 4 · 팩터 레지스트리 엔트리 7 · 비중 카탈로그 1 · 행동 카드 사본 · 리허설 요약 · 스크립트 · evaluate md5)이 현재 파일과 모두 같다(직접 md5). evaluate_consistency ok.
- **⑭ 판정부**: 통제 상태 정상값 "ok"(`matched_controls.R:409` — ok 가 아니면 그 전에 반환) · 확정 라벨 4종 = 계약 어휘(`:437-439`) · 판정어 순서 — ③ 미통과는 ⑭ 와 무관하게 exposure_only · ③ ∧ ④ 통과 ∧ ⑭ 미측정 = selection_unmeasured · 측정됨 미통과 = size_or_exposure_defense · 통과 판정(`p2_cell_pass`) 불변.
- **precheck 커밋 확인**(`precheck.R:83-99`): 양성 대조 — P2R03 사전등록 두 사본(추적 · 깨끗 · md5 41f4a9b4 같음) = 통과 · 미추적 파일 = 'git 미추적' + '작업 트리 변경(??)'으로 걸림 · `status --porcelain` 이라 색인만 올리고 커밋 안 한 사본('A')도 걸린다. 두 경로 모두 git 무시 목록 밖(`check-ignore` rc 1) · 분리 실행 환경 PATH 에 git(/mingw64/bin · 상속 PATH) — 측정 런처에서도 돈다. 등록부(research_programs.json)는 대조하지 않는다(다른 라운드 쓰기로 측정이 막히지 않게 — 적절).
- **실패 의미**: 칸 평가 · 판정 1칸 안전 호출 · 기록 계산 안전 호출 · 진단 칸 지문 = 그 칸만 — v1 그대로. 미측정 꼬리표가 '통과'로 읽히는 경로 없음(`isTRUE` · 픽스처 28) · 미측정이 기전 이름으로 접히는 경로는 닫혔다(R2 · R3) · 남은 반대 방향 = R7(필수 1 · 권고 1).
- **검사**: 픽스처 52/0 · 뮤테이션 34/34 재현(새 분기 — 엄격 > 0 · 0.03 재도입 · insufficient 를 측정으로 · selection_unmeasured 분기 제거 · ③④ NA 보류 제거 · R7 판독 불가 제거 · 표식 제거 — 모두 검출) · 리허설 11단계 통과(evaluate d7c9adb1 · 실행 중 불변 · 708초) · 건식 precheck 통과(results/ 미작성).
