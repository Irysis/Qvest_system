"""판 원장 항목 하나를 닫는다 — completed_at 을 채우고 note 의 '진행 중' 문장(표식 marker 부터 끝까지)을 끝난 사실로, evidence 에 재계산 요약을 더한다
(다른 바이트 보존 · LF).
argv: ledger_path entry_id completed_at(ISO · +09:00) marker done_sentence evidence_tail
- 그 항목의 재계산(진행기 요약 '성공' + 이번 달 부분 재계산 · 결합용 뷰 그 달 rc 0)을 확인한 뒤에만 부른다.
- completed_at 이 이미 차 있으면 거부(두 번 닫지 않는다) · marker 가 note 에 정확히 한 번 있어야 한다.
- 진행 중 표기 = JSON null(계약 fdv_ledger 정본 — 빈 문자열은 형식 위반으로 계약이 멈춘다) · 옛 "" 도 닫을 수는 있다.
쓴 곳: 11-14 21:4x RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114(marker '진행 중 = 팩터 DB(') · D2-XF-FILL-RESTORE-20261114(marker '수리 = ').
"""
import json, sys

path, eid, completed_at, marker, done_sentence, ev_tail = sys.argv[1:7]
raw = open(path, "rb").read()
assert b"\r\n" not in raw
txt = raw.decode("utf-8")
d = json.loads(txt)
e = [x for x in d["entries"] if x["id"] == eid]
assert len(e) == 1 and e[0]["completed_at"] in (None, ""), "항목이 없거나 이미 닫혔다"   # 진행 중 = null(정본) · "" = 11-14 D2 항목 옛 표기
assert completed_at.endswith("+09:00") and len(completed_at) == 25, completed_at
old_note, old_ev = e[0]["note"], e[0]["evidence"]
k = old_note.find(marker)
assert k > 0 and old_note.count(marker) == 1, "note 의 진행 중 문장(marker)을 못 찾았다"
new_note = old_note[:k] + done_sentence
new_ev = old_ev + " · " + ev_tail

# 필드를 문자열 그대로 바꾼다(키 순서 · 들여쓰기 · 다른 항목 보존)
for o, n in ((old_note, new_note), (old_ev, new_ev)):
    eo, en = json.dumps(o, ensure_ascii=False), json.dumps(n, ensure_ascii=False)
    assert txt.count(eo) == 1, "old string not unique"
    txt = txt.replace(eo, en)
blk_start = txt.find('"id": "%s"' % eid)
assert blk_start > 0
ca_old = '"completed_at": null' if e[0]["completed_at"] is None else '"completed_at": ""'
j = txt.find(ca_old, blk_start)
nxt = txt.find('"id": "', blk_start + 10)
assert j > 0 and (nxt < 0 or j < nxt), "completed_at 위치가 그 항목 안이 아니다"
txt = txt[:j] + '"completed_at": "%s"' % completed_at + txt[j + len(ca_old):]

d2 = json.loads(txt)
e2 = [x for x in d2["entries"] if x["id"] == eid][0]
assert e2["completed_at"] == completed_at and e2["note"] == new_note and e2["evidence"] == new_ev
assert len(d2["entries"]) == len(d["entries"])
assert [x for x in d2["entries"] if x["id"] != eid] == [x for x in d["entries"] if x["id"] != eid]
assert {k2: v for k2, v in d2.items() if k2 != "entries"} == {k2: v for k2, v in d.items() if k2 != "entries"}
open(path, "wb").write(txt.encode("utf-8"))
print("closed", eid, completed_at)
