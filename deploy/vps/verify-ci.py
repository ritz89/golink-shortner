"""Require successful test workflows for the exact release source revision."""
import json,os,subprocess,sys
repo,sha=sys.argv[1:3];required=json.loads(os.environ.get('REQUIRED_WORKFLOWS','[]'))
if not isinstance(required,list) or not required or any(not isinstance(x,str) or not x for x in required):raise SystemExit('VPS_REQUIRED_WORKFLOWS must name the mandatory test workflows')
runs=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/actions/runs?head_sha={sha}&per_page=100'],text=True))['workflow_runs']
for name in required:
 matches=[r for r in runs if r['name']==name and r['head_sha']==sha and r['event'] in ['push','pull_request','workflow_dispatch']]
 if not matches:raise SystemExit('Missing source test workflow: '+name)
 latest=max(matches,key=lambda r:r['id'])
 if latest['status']!='completed' or latest['conclusion']!='success':raise SystemExit('Source tests not successful: '+name)
print('Required source CI passed for '+sha)
