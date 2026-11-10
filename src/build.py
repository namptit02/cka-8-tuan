import re, json, sys, markdown

def md(s):
    return markdown.markdown(s.strip(), extensions=['fenced_code', 'tables'])

def lesson_html(body):
    parts, out, n = re.split(r'^:::ex\s*$', body, flags=re.M), [], 0
    out.append(md(parts[0]))
    for p in parts[1:]:
        q, rest = re.split(r'^:::sol\s*$', p, maxsplit=1, flags=re.M)
        a, tail = re.split(r'^:::end\s*$', rest, maxsplit=1, flags=re.M)
        n += 1
        out.append(f'<div class="ex"><div class="exh">Bài tập {n}</div>{md(q)}'
                   f'<details><summary>Xem lời giải</summary>{md(a)}</details></div>')
        if tail.strip():
            out.append(md(tail))
    return ''.join(out), n

lessons = []
for w in range(1, 9):
    src = open(f'src/lessons/w{w}.md', encoding='utf-8').read()
    for chunk in re.split(r'^# L: ', src, flags=re.M)[1:]:
        title, body = chunk.split('\n', 1)
        html, n = lesson_html(body)
        lessons.append({'w': w, 't': title.strip(), 'h': html, 'n': n})

page = open('src/template.html', encoding='utf-8').read()
data = json.dumps(lessons, ensure_ascii=False).replace('</', '<\\/')
page = page.replace('/*LESSONS*/', 'const LESSONS=' + data + ';')
open('index.html', 'w', encoding='utf-8').write(page)
print(len(lessons), 'lessons,', sum(l['n'] for l in lessons), 'exercises')
for w in range(1, 9):
    print(w, sum(1 for l in lessons if l['w'] == w), sum(l['n'] for l in lessons if l['w'] == w))
