"""인쇄용 PDF 생성 뒤 검사 — ① 표 쪽 나눔(갈린 표 = 다음 쪽에 머리 행이 반복된다) ② 내장 글꼴(대체 글꼴 유무).
사용: python pdf_check.py <out.pdf> <expect.json>   (expect = {"tables": [머리 행 문자열 …], "fonts_allowed": [부분 문자열 …]})
출력: JSON 1줄 — split(갈린 표 머리 → 초과 횟수) · missing(검출 못 한 표) · fonts · bad_fonts · ok. 종료 코드 0 = ok."""
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
ok = not split and not bad_fonts
print(json.dumps({"pages": doc.page_count, "tables_expected": sum(ce.values()), "tables_found": sum(cf.values()),
                  "split": split, "missing": missing, "fonts": fonts, "bad_fonts": bad_fonts, "ok": ok}, ensure_ascii=False))
sys.exit(0 if ok else 1)
