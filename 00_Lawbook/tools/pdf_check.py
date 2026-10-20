"""인쇄용 PDF 생성 뒤 검사 — ① 표 쪽 나눔(갈린 표 = 다음 쪽에 머리 행이 반복된다) ② 내장 글꼴 이름(대체 글꼴 유무) ③ 글꼴 정체(글자 폭).
사용: python pdf_check.py <out.pdf> <expect.json>
  expect = {"tables": [머리 행 문자열 …], "fonts_allowed": [부분 문자열 …], "font_files": [기대 글꼴 파일 경로 …](선택)}
출력: JSON 1줄 — split(갈린 표 머리 → 초과 횟수) · missing(검출 못 한 표) · fonts · bad_fonts · font_identity · ok. 종료 코드 0 = ok.

③ 글꼴 정체(10-20 추가): 이름이 아니라 글자 폭으로 본다.
  - 브라우저는 사용권이 제한된 글꼴이나 대체 글꼴을 이름 없는 Type3 글리프로 넣는다. 그래서 ② 이름 검사는 이것을 그냥 지나간다.
  - 10-20 실측: 현대하모니 적재 실패 → Noto Sans KR 로 인쇄됐는데 bad_fonts 가 비어 있었다.
  - 본문 글자(한글 음절 · 영문 · 숫자)의 폭(글자 상자 폭 ÷ 글자 크기)을 기대 글꼴 파일의 advance 와 대조한다.
  - 0.02em 넘게 어긋난 글자가 5% 를 넘으면 실패.
"""
import sys, json, re
from collections import Counter
import pymupdf

pdf, exp_path = sys.argv[1], sys.argv[2]
exp = json.load(open(exp_path, encoding="utf-8"))
norm = lambda t: re.sub(r"\s+", "", t or "")
doc = pymupdf.open(pdf)
found = []
for pno, page in enumerate(doc, start=1):
    for t in page.find_tables().tables:
        rows = t.extract()
        if rows:
            found.append((pno, norm("".join(c or "" for c in rows[0]))))
ce = Counter(norm(s) for s in exp["tables"])
cf = Counter(sig for _, sig in found if sig in ce)
split = {k[:40]: cf[k] - ce[k] for k in ce if cf.get(k, 0) > ce[k]}
missing = {k[:40]: ce[k] - cf.get(k, 0) for k in ce if cf.get(k, 0) < ce[k]}
fonts = sorted({f[3] for p in doc for f in p.get_fonts()})
bad_fonts = [f for f in fonts if f and not any(a in f for a in exp.get("fonts_allowed", []))]

identity = {"checked": 0, "mismatch": 0, "samples": [], "ok": None}
files = exp.get("font_files") or []
if files:
    ref = [pymupdf.Font(fontfile=f) for f in files]
    for page in doc:
        for b in page.get_text("rawdict")["blocks"]:
            for ln in b.get("lines", []):
                for s in ln["spans"]:
                    if "Consolas" in (s.get("font") or ""):  # 코드 · 경로 = 고정폭 허용(서식 규칙)
                        continue
                    size = s["size"] or 0
                    for ch in s["chars"]:
                        c = ch["c"]
                        if not size or not (("가" <= c <= "힣") or (c.isascii() and c.isalnum())):
                            continue
                        w = (ch["bbox"][2] - ch["bbox"][0]) / size
                        want = [r.glyph_advance(ord(c)) for r in ref]
                        identity["checked"] += 1
                        if min(abs(w - e) for e in want) > 0.02:
                            identity["mismatch"] += 1
                            if len(identity["samples"]) < 6:
                                identity["samples"].append("%s:%.3f≠%.3f" % (c, w, want[0]))
    identity["ok"] = identity["checked"] > 0 and identity["mismatch"] <= 0.05 * identity["checked"]

ok = not split and not bad_fonts and identity["ok"] is not False
print(json.dumps({"pages": doc.page_count, "tables_expected": sum(ce.values()), "tables_found": sum(cf.values()),
                  "split": split, "missing": missing, "fonts": fonts, "bad_fonts": bad_fonts,
                  "font_identity": identity, "ok": ok}, ensure_ascii=False))
sys.exit(0 if ok else 1)
