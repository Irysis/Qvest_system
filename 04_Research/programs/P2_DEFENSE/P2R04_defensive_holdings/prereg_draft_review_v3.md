# P2R04 사전등록 초안 격리 점검 v3 (v2 → v3 · 좁은 범위)

- 점검자: 격리 교차 점검(서브에이전트 · 이 라운드 설계 · 구현 비참여 · 측정 결과 없음) · 2026-10-18
- 범위(조정자 지정): v2 리뷰의 남은 필수 1(R7 판독 불가 문장) · 권고 1(판정 장치 = ③ 측정 장치) · 권고 3(등록 관문) · 비차단 문장 정합(round_verdict · files · 변경 기록 v1 권고 2 · 6 · 7)이 닫혔는가 — 재현으로만.
- 대상(md5 앞 8자리): `prereg_draft.json` v3(ed1698f0) · v2 보존본 `prereg_draft_reviewed_v2.json`(211b62d0 = v2 점검 대상과 같음) · `evaluate.R`(06a1b8d6) · `evaluate_fixture.R`(d4bc7deb) · `rehearsal/summary.json`(66099efb) · `register.R`(634aad23) · `DESIGN.md`(70b9b22b). 바뀌지 않은 것: `precheck.R`(f09ca3db) · `rehearse.R`(3aba7c41) · `notify.R` · `fingerprint.sh` · `measure*.sh` · `round_rules.R` · `specs/` 23 · 행동 카드 사본.
- **판정: ok** — 범위 안 네 항목이 문장 · 코드 · 사전등록 · DESIGN 에서 모두 닫혔다(재현 아래). 남은 필수 없음.

## 0. 정보 경계 선언

- 연 것: 위 v3 파일 · v2 보존본(필드 diff). 실행: `Rscript evaluate_fixture.R` → **53/0 · 뮤테이션 35/35** · evaluate.R R7 함수 격리 적재 재현 5건(합성 입력 · 스크래치패드만) · 핀 md5 대조(읽기만).
- 안 연 것: 어떤 results/ · 성과 파일 · 로그(P2R03 포함). 측정 · 등록 · 커밋 · 프로젝트 파일 수정(이 파일 밖) 없음.

## 1. 범위 항목 — 닫혔는가

| 항목 | v3 | 재현 · 근거 |
|---|---|---|
| v2 필수 1 — R7 판독 불가 문장 | **닫힘.** 사전등록 r7_reading(`prereg_draft.json:886` ← register.R) = "판정된 장치 = 두 구성 모두 tested ∧ ③ 측정(status ok · 짝 ≥ 2 · 비율 유한) ∧ S 증분 유한 · < 2 = 판독 불가(NA) · ≥ 2 면 검증 0 ∧ 판정된 장치 중 ③ 두 구성 과반 장치 0 ∧ 판정된 장치 S 증분 최대 < tie_eps · 판정 장치 수 · 빠진 장치 · 이유 기록" = 코드(`evaluate.R:737-766` — `r3m` `:745` · `judged` `:746` · `readable <- nb >= 2L` `:756` · `dropped` `:758`) = DESIGN §5(`DESIGN.md:120`) | **v2 재현 R5 이제 같은 답**: 장치 1개 판정 → 코드 NA('판독 불가(판정된 장치 1/4 < 2 …)') = 문장 판독 불가 · 2개 → 계산('잡음 이내' 2/4 · 빠진 장치 H3 · H4 이유 기록) |
| v2 권고 1 — 판정 장치 = ③ 측정 장치 | **닫힘(길 (a) — 코드).** ③ 미측정 구성이 하나라도 있으면 그 장치는 분모에서 빠진다 · ③ 과반 · S 증분 최대는 판정된 장치에서만 센다(`:750` · `:753`) | **v2 재현(8칸 모두 β 대조 미측정)이 이제 판독 불가 0/4**(이전 '잡음 이내 4/4') · 한 구성만 ③ 짝 < 2 → 그 장치 빠짐(이유 'ok / unmeasured(짝 < 2)') · 판정 3/4 · 판정 장치 안에 ③ 두 구성 과반 장치 → '잡음 밖' · 픽스처 48 · 뮤테이션 'R7 ③ 측정 조건 제거' 검출 |
| v2 권고 3 — 등록 관문 | **닫힘.** `register.R:375-377` — `prereg_draft_reviewed_v<DRAFT_VERSION>.json` 이 없거나 그 md5 ≠ 등록할 초안 md5 면 `--register` 거부. 초안 관문(`:254-256`)은 v3 작성 전 v2 보존본을 요구했고 그 보존본 = v2 점검 대상(211b62d0) | 코드 대조. 점검 뒤 `--draft` 를 다시 돌리면 drafted_at 이 바뀌어 md5 가 달라지므로 등록이 거부된다(의도대로) |
| 비차단 문장 정합 | **닫힘.** round_verdict(`:885`) = "'판정(판정 칸/전체 장치 칸 8 · 판정어별 칸 수)' · 예 falsified(판정 8/8 · β 짝 미측정 8)" = 코드 라벨 · files(`:890`) = 짝 평가 사본(original · common_* · rx0_beta_scaled · artifacts · rx0_artifacts) 표식 · 보는 창 = visible* 만 = 코드 표식 위치 · changes_after_review 14건(v2 필수 1 · 권고 1 · 권고 3 · 문장 정합 4건 추가) | 문장 대조 · v1 · v2 리뷰 결과와 대조 |

함께 확인한 것: v3 초안의 핀(운영 38 · 평가 8 · 사양 23 · 검사 4 — 픽스처 53/0 · 팩터 레지스트리 엔트리 7 · 행동 카드 사본 · 리허설 요약 · 스크립트 · evaluate md5)이 현재 파일과 모두 같다 · evaluate_consistency ok · 리허설 11단계 통과(evaluate 06a1b8d6 · 실행 중 불변 · R8 '장치 1개 판정 = 판독 불가' 단정 포함) · 본 실행 R7 콘솔 줄 · VIS 가 새 반환 필드(label · judged_devices · dropped · components)를 그대로 쓴다(`evaluate.R:1370` · `:1390` · `:1417-1419`) · 빠진 장치 이유 문자열에 성과 수치 · 날짜 없음(보는 창 파일 날짜 전수 검사 대상) · v2 선택 1(evaluate.R 낡은 주석 — 머리 8-9행 · 1064 · 1183-1184)도 정리됐다.

## 2. 남은 것 (비차단 · 등록을 막지 않는다)

1. **기록 번호 하나가 뒤바뀌었다**: changes_after_review[13](`prereg_draft.json` changes_after_review 마지막 항목)이 "v1 권고 … 6(전기간 사본 표식) · 7(E3 W 구성 비)"로 적었는데 v1 리뷰에서는 **권고 6 = E3 W 구성 비 · 권고 7 = 사본 표식**이다. 내용은 맞고 번호만 바뀌었다. 고치려면 초안 v4 + 다시 점검이 필요하므로(위 등록 관문) 고치지 않는 쪽을 권한다 — 정답 번호는 v1 · v2 · v3 리뷰 파일에 있다.
2. **범위 밖으로 남겨 둔 v2 비차단 항목(그대로)**: ⑩ 문장의 사양 · base_weight 조항은 등록 spec_checks + md5 핀이 보증(v2 권고 4) · C-025 'H1 대 P2R03 D1 대조 읽기'는 변경 기록에만(v2 권고 5) · 처치 방향 대체 신호일은 꼬리표뿐 — 결과 보고에서 칸마다 `registry_fallback = 0` 확인 · 평가 지문은 기록만(v2 권고 6) · `p2_defense_name` 의 `s14_measured = TRUE` 기본값(`evaluate.R:599` — 호출부는 넘긴다) · `DESIGN.md:3` 머리 상태 '격리 교차 점검 전'.

## 3. 등록 순서 메모(관문이 기계로 요구하는 것)

`--draft` 를 다시 돌리지 말고 이 초안(ed1698f0)을 그대로 `prereg_draft_reviewed_v3.json` 으로 보존 → 고정 대상(라운드 폴더 · 검사 · 운영 경로) 커밋 → `register.R --register` → 사전등록 두 사본(stage_artifacts 정본 · 라운드 prereg.json)과 등록부 커밋 → 측정(precheck 가 두 사본의 추적 · 무변경 · md5 같음과 러너 축을 단정).
