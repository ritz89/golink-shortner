#!/usr/bin/env python3
"""Create a sanitized tracked-source context; never export untracked files."""
import argparse,ast,io,json,re,subprocess,tarfile
from pathlib import Path,PurePosixPath

class RemoveCredentialDefaults(ast.NodeTransformer):
 def visit_Call(self,node):
  self.generic_visit(node)
  if isinstance(node.func,ast.Name) and node.func.id=='config' and node.args and isinstance(node.args[0],ast.Constant) and isinstance(node.args[0].value,str) and any(k in node.args[0].value.upper() for k in ['PASSWORD','SECRET','API_KEY','API_TOKEN','ACCESS_KEY']):
   for keyword in node.keywords:
    if keyword.arg=='default' and isinstance(keyword.value,ast.Constant) and isinstance(keyword.value.value,str):keyword.value=ast.Constant('')
  if isinstance(node.func,ast.Attribute) and node.func.attr=='login':
   node.args=[ast.Constant('') if isinstance(arg,ast.Constant) and isinstance(arg.value,str) else arg for arg in node.args]
  return node
 def visit_Assign(self,node):
  self.generic_visit(node)
  if isinstance(node.value,ast.Constant) and isinstance(node.value.value,str) and any(isinstance(t,ast.Name) and any(k in t.id.upper() for k in ['PASSWORD','SECRET','ACCESS_KEY','API_KEY','API_TOKEN']) for t in node.targets):node.value=ast.Constant('')
  return node

def guard_go_startup(app,name,body):
 expected={'golink':'platform/database/database.go','ticket':'platform/database/postgres.go','chat':'platform/database/postgres.go','guide':'platform/database/postgres.go','notification':'platform/database/postgres.go'}
 if expected.get(app)!=name:return body
 text=body.decode()
 if 'ONJOURNEY_SKIP_AUTO_MIGRATE' in text:raise ValueError('Source has an existing schema contract; review before replacing transform')
 anchors={'golink':('// Auto migrate models','return'),'ticket':('if err := DB.AutoMigrate(','return'),'chat':('func Migrate() {','return'),'guide':('func Migrate() error {','return nil'),'notification':('func Migrate() error {','return nil')}
 anchor,ret=anchors[app]
 if text.count(anchor)!=1 or 'import (' not in text:raise ValueError('Unrecognized startup schema entrypoint')
 guard='if os.Getenv("ONJOURNEY_SKIP_AUTO_MIGRATE") == "true" { '+ret+' }'
 if app in {'chat','guide','notification'}:text=text.replace(anchor,anchor+'\n\t'+guard)
 else:text=text.replace(anchor,guard+'\n\t'+anchor)
 if '"os"' not in text:text=text.replace('import (','import (\n\t"os"',1)
 return text.encode()

def export(repo,dest,app=None):
 archive=subprocess.check_output(['git','-C',str(repo),'archive','HEAD']);count=0
 with tarfile.open(fileobj=io.BytesIO(archive)) as source:
  for m in source:
   p=PurePosixPath(m.name);lower=m.name.lower()
   if not m.isfile() or p.is_absolute() or '..' in p.parts:continue
   if any(x in {'.git','.github','node_modules','venv','.venv','__pycache__','backups','keys','uploads','media','staticfiles'} or x.startswith('.env') for x in p.parts):continue
   if p.suffix.lower() in {'.pem','.key','.p12','.pfx','.jks','.sql','.dump','.gz','.zip','.pdf','.sqlite3','.sqlite','.db'}:continue
   if p.suffix.lower() in {'.json','.yaml','.yml','.txt'} and any(x in lower for x in ['firebase','credentials','service-account','secret']):continue
   body=guard_go_startup(app,m.name,source.extractfile(m).read())
   if body.startswith((b'\x7fELF',b'MZ',b'\xcf\xfa\xed\xfe')):continue
   if p.suffix=='.py':
    body=re.sub(rb'''((?:['"](?:password|host_password|api_token|X-API-Token)['"]\s*:\s*|\.get\(\s*['"](?:password|api_token)['"]\s*,\s*))(['"])[^'"\r\n]+\2''',lambda x:x[1]+x[2]+x[2],body)
    tree=ast.parse(body);before=ast.dump(tree);tree=RemoveCredentialDefaults().visit(tree)
    if ast.dump(tree)!=before:body=ast.unparse(tree).encode()+b'\n'
   if re.search(rb'-----BEGIN (?:[A-Z ]*PRIVATE KEY|CERTIFICATE)-----',body):
    # Legacy code bearing keys cannot be included. Runtime-only files must be
    # mounted by host configuration; build/import tests expose missing modules.
    continue
   if b'"private_key"' in body and b'"service_account"' in body:continue
   target=Path(dest)/m.name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(body);target.chmod(m.mode&0o755);count+=1
 return count
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('repository');p.add_argument('destination');p.add_argument('--app',required=True);a=p.parse_args();print(json.dumps({'source_files':export(Path(a.repository),Path(a.destination),a.app),'untracked_files_included':False}))
