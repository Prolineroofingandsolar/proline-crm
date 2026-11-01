"""Publish reviewed working files atomically; preserve newer remote changes.

Uses the existing gh account. Never changes the local Git index or checkout.
Run without --publish to inspect the file list and check remote overlap first.
"""
import json, pathlib, re, subprocess, sys, base64
ROOT = pathlib.Path(__file__).resolve().parents[2]
REPO = 'repos/Prolineroofingandsolar/proline-crm'
def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)
def api(path, body=None, method=None):
    command = ['gh', 'api', path]
    if body is not None:
        command += ['--method', method or 'POST', '--input', '-']
    result = subprocess.run(command, input=json.dumps(body) if body is not None else None, text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None
base = git('rev-parse', 'HEAD').decode().strip()
head = api(REPO + '/commits/main')
changes = api(REPO + f'/compare/{base}...{head["sha"]}')
remote_changed = {f['filename'] for f in changes.get('files', [])}
paths = set(git('diff', '--name-only', '-z', 'HEAD').decode().split('\0'))
paths |= set(git('ls-files', '--others', '--exclude-standard', '-z').decode().split('\0'))
paths.discard('')
# The newer main only made the same local-sign-out fix retained in this release.
for path in remote_changed & paths:
    if path != 'src/store/useStore.ts':
        raise SystemExit(f'Remote changes require merge review: {path}')
    patches = [f.get('patch', '') for f in changes['files'] if f['filename'] == path]
    assert all('signOut' in patch and 'scope:' in patch for patch in patches), 'Unexpected remote store changes'
    assert "signOut({ scope: 'local' })" in (ROOT / path).read_text(), 'Newer sign-out fix missing'
entries = []
for path in sorted(paths):
    file = ROOT / path
    if not file.is_file():
        entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
        continue
    if any(part.startswith('.env') for part in file.parts) and file.name != '.env.example':
        raise SystemExit(f'Refusing environment/credential file: {path}')
    text = file.read_text()
    if re.search(r'(?:sb_secret_|gh[pousr]_|sk-proj-)[A-Za-z0-9_-]{20,}', text):
        raise SystemExit(f'Potential secret in {path}')
    for token in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', text):
        try:
            body = token.split('.')[1]
            role = json.loads(base64.urlsafe_b64decode(body + '=' * (-len(body) % 4))).get('role')
            if role == 'service_role': raise SystemExit(f'Privileged key in {path}')
        except (ValueError, UnicodeError): pass
    entries.append({'path': path, 'mode': '100755' if file.stat().st_mode & 0o111 else '100644', 'type': 'blob', 'content': text})
print(f'{len(entries)} reviewed files; remote base {head["sha"][:12]}.')
if '--publish' not in sys.argv:
    print('\n'.join(e['path'] for e in entries))
    raise SystemExit(0)
tree = api(REPO + '/git/trees', {'base_tree': head['commit']['tree']['sha'], 'tree': entries})
user = api('user')
author = {'name': user.get('name') or user['login'], 'email': f'{user["id"]}+{user["login"]}@users.noreply.github.com'}
commit = api(REPO + '/git/commits', {'message': 'Prepare employee CRM release with secure saves and staff management', 'tree': tree['sha'], 'parents': [head['sha']], 'author': author})
current = api(REPO + '/git/ref/heads/main')
assert current['object']['sha'] == head['sha'], 'Main changed during preparation; release was not pushed'
api(REPO + '/git/refs/heads/main', {'sha': commit['sha'], 'force': False}, method='PATCH')
(ROOT / 'docs/last-published-release.json').write_text(json.dumps({'sha': commit['sha'], 'url': commit['html_url']}, indent=2) + '\n')
print('Published ' + commit['sha'])
