# RAWDATA 상장 전 행 삭제 — RAWDATA-PRELISTING-EXCLUDE-20261116 (2026-11-16)

## 결정

- 도훈 11-16 08:3x(1계층 세션 채팅 · decision_register RAWDATA-PRELISTING-EXCLUDE-20261116 · pit.md C6 행):
  "장외랑 코넥스 데이터까지 수집할 필요없어. 상장전 이력까지 백테스팅에 활용하지마. 상장종목은 상장된 시점 이후 퀀티와이즈에 찍히는 가격데이터부터 활용하면 되고, 없는 시점은 유니버스에 제외시켜."
- 도훈 11-16 추가(같은 세션):
  - "상장 첫날에는 가격변동폭제한이 커져서 가짜수익이 아니라 진짜 수익일 수 있다"
  - "자꾸 네가 스스로 새롭게 검증하려고 하지마. 퀀티와이즈 데이터가 무조건 맞는거야"
- 그래서 **행만 지우고 값은 바꾸지 않는다**. 상장 첫날 Ret 은 저장값 그대로이고(등록부가 정한 값 포함), 수동 채움 등록부 14행도 그대로다. 새 검증 · 대조 · 사례 확인은 하지 않는다.
- 처음 요청에는 '첫날 Ret = NA · 등록부 13행 빼기'가 있었으나 같은 날 정정 요청으로 거뒀다.

## 규칙

- 종목마다 퀀티 시장구분(R100100 일별 · 외부 책 ListingMarket → `.cache/qw_ext/listing_market/market_type.parquet`)이 처음 유가증권(KS) · 코스닥(KQ)이 된 날을 상장일로 본다.
- 그보다 앞선 날짜의 RAWDATA 행을 지운다. 코스닥 → 유가증권 이전 종목은 코스닥 이력이 남는다.
- 시장구분 기간 안에 KS · KQ 가 한 번도 없는 종목(장외 · 코넥스 · 외감만)은 그 기간의 행을 지운다.
- 지우지 않는 것:
  - 시장구분 시계열이 아예 없는 종목(요약에 목록 · 이번 0종목)
  - 아직 상장일이 없는 종목 중 시장구분 파일 마지막 날보다 뒤의 행(다음 실행이 본다)
- 시장구분 파일에 KS · KQ 코드가 없으면 멈춘다(표기가 바뀌면 전부를 지울 수 있어서다).
- 도구 = `02_Infrastructure/data/rawdata_listing_cut.py`(멱등 · `--apply` 는 writer 잠금 · 리프레시 잠금 아래에서만 · 지운 행 전 열은 `.cache/listing_cut/dropped_*.parquet`).

## 집행

| 시각 | 무엇 | 누가 |
|---|---|---|
| 10:39:00 | 시장구분 적재 — 1990-01-03 ~ 2026-11-13 · 3,770종목 · 35,848,930행 · 코드 EX · K-OTC · KN · KQ · KS | 1계층 세션 `02_Infrastructure/ops/qw_login_chain.sh` ①(퀀티 재로그인 뒤) |
| 10:39:35 | 상장 전 행 삭제 — **80,851행 · 106종목**(그중 전부 지워진 종목 2) · RAWDATA 14,211,157 → 14,130,306행 · 백업 `.cache/rawdata_pre_listing_cut_20261116.parquet` | 같은 연쇄 ② — 이 도구를 writer 잠금 아래 `--apply --backup --label qw_login_chain` |
| 10:39 | 판 원장 `06_Registry/factor_db_vintage.json` 줄 RAWDATA-PRELISTING-EXCLUDE-20261116(범위 all · 진행 중) | 같은 연쇄 |
| 10:39:48 ~ | 팩터 DB 전체 재빌드(월간 · 일간 · IC → 결합용 뷰 --full → FF) — 끝나면 판 표식 셋의 completed_at 을 채운다 | 같은 연쇄 ③~⑥ |
| 11-16 | 밤 갱신 `02_Infrastructure/data/daily_refresh.sh` [1y] — universe 단계 머리 · [1z] 앞(같은 도구 `--apply --label nightly` · 리프레시 잠금 아래) | 이음매 세션 |

- 요약 = `.cache/listing_cut/summary_20261116_103935_qw_login_chain_apply.json`.
- 삭제 뒤 수동 채움 등록부 14행의 키는 모두 RAWDATA 에 남아 있다(상장 첫날 행은 지우지 않는다).

## 밤 갱신 [1y]

- 위치: universe 단계 머리이고 [1z] Size 경보 앞이다.
  - [0b'] 적재기가 창 행을 다시 붙인 뒤에 돈다.
  - 그래서 [1z] · [3] 유니버스 · [3b] BM_Ret · [6a] 팩터 빌드가 모두 지운 뒤의 RAWDATA 를 본다.
  - 시험 `08_Tests/data/test_rawdata_size_guard.R` 이 잘라 실행하는 구간('# ── [1z]' ~ 'echo "[3/7]') 밖이다.
- 지울 행이 없으면 쓰지 않는다(멱등).
- rc 가 0 이 아니면 `DR_FAILED+=("listing_cut(rc=N)")` 를 남기고 RAWDATA 는 바꾸지 않는다. 끄기 = `QVEST_DR_LISTING_CUT=0`.
- 시장구분 파일은 [1pre-ext] 가 매일 받는다. 받지 못한 밤에는 파일 마지막 날 뒤의 행을 판정하지 않고, 다음에 받은 밤에 처리한다.
- 교체 뒤 운영본에서 블록을 잘라 한 번 실행했다: 지울 행 0 · DR_FAILED 없음.

## 이음매 묶음(RAWDATA-7ROWS-CORPACTION-REQUERY-20261115)

- 범위 all 수리에 싣기로 정해져 있다(11-15 기본안 · 1계층 세션 요청 11-16).
  - 값 변경 3행: A012470 1998-07-13 · A008080 2012-01-12 · 2012-11-30
  - 고정 3행: 코스닥 → 유가증권 이전상장 첫날
  - 외감 → 유가증권 2행(A016560 · A027840)은 삭제로 첫 행이 돼서 값 판정 없이 뺐다.
- 명세 `../rawdata_seam_20260330_repair_20261113/d2_fill/pending_bundle_20261115.json` 은 삭제 뒤 RAWDATA 로 다시 만들었다(rc 0).
- 적용 = `tools/run_1116_locked.sh`. 순서는 writer 잠금 → 명세 재생성 → 등록부 +6 → `seam_repair_locked.sh --apply` 이고, 실패하면 등록부를 원래 바이트로 되돌린다.
- **결정(11-16 · 1계층 세션 · 선택지 2) — 다음 범위 all 수리로 미룬다.**
  - 연쇄의 팩터 DB 재빌드가 10:39:48 부터 돌고 있어, 지금 쓰면 재빌드 도중에 RAWDATA 가 바뀐다. 그래서 재빌드는 그대로 두고 묶음은 다음 범위 all 수리 때 쓴다.
  - 그 재빌드가 끝날 때까지(`.cache/qw_login_chain/status.json` 의 state = done) RAWDATA 를 쓰지 않는다.
  - 재빌드가 끝난 뒤 따로 쓰지도 않는다. 판 원장 줄과 팩터 수리가 한 번 더 필요해지기 때문이다.
  - 명세 `apply_when` 에 같은 결정을 적었다. 적용할 때는 `tools/run_1116_locked.sh` 를 그 수리 시작 전에 돌린다.

## 파일

- `02_Infrastructure/data/rawdata_listing_cut.py` — 상장 전 행 삭제 도구(연쇄 · 밤 [1y] 가 부른다)
- `02_Infrastructure/data/daily_refresh.sh` — [1y] 블록
- `tools/registry_1116_apply.py` — 등록부에 묶음 6행 붙이기(CRLF · 들여쓰기 2 · 다른 바이트 보존)
- `tools/run_1116_locked.sh` — 묶음 적용 순서(writer 잠금)
