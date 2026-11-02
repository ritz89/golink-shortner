"""The portable image config digest, independent of Docker storage backend."""
import hashlib,json,sys,tarfile
with tarfile.open(sys.argv[1],'r:*') as archive:
 manifest=json.load(archive.extractfile('manifest.json'))
 if len(manifest)!=1:raise SystemExit('Exactly one image required')
 member=archive.getmember(manifest[0]['Config'])
 if not member.isfile() or member.size>1024**2:raise SystemExit('Invalid config')
 print(hashlib.sha256(archive.extractfile(member).read()).hexdigest())
