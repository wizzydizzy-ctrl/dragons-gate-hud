import hashlib, json, subprocess, sys, tempfile, unittest, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
class BuildTest(unittest.TestCase):
    def test_build_emits_verified_owned_package(self):
        with tempfile.TemporaryDirectory() as td:
            subprocess.run([sys.executable,str(ROOT/'scripts/build.py'),'--output',td,'--owner','ricwall','--repository','dragons-gate-hud'],check=True)
            package=Path(td)/'DragonsGateHUD.mpackage'; manifest=json.loads((Path(td)/'manifest.json').read_text())
            self.assertEqual(manifest['package'],'DragonsGateHUD')
            self.assertEqual(manifest['sha256'],hashlib.sha256(package.read_bytes()).hexdigest())
            with zipfile.ZipFile(package) as z:
                names=z.namelist(); self.assertEqual(names,['DragonsGateHUD.xml'])
                xml=z.read(names[0]).decode(); self.assertIn('<name>DragonsGateHUD</name>',xml); self.assertIn('DGHUD.start',xml)
                self.assertIn('package.preload[&quot;layout&quot;]',xml)
if __name__=='__main__': unittest.main()
