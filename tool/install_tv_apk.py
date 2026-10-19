#!/usr/bin/env python3
"""Verified in-place ADB install. Never uninstalls, clears data or downgrades."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PACKAGE = 'it.fabiodalez.bloomeetv'

def validate_update(package, new_code, old_code, new_certificate, old_certificate,
                    apk_abis, device_abis):
    if package != PACKAGE:
        raise ValueError('APK non appartenente a Bloomee TV')
    if new_code < old_code:
        raise ValueError('Versione inferiore: aggiornamento rifiutato')
    if old_certificate and new_certificate != old_certificate:
        raise ValueError('Firma diversa: aggiornamento rifiutato')
    if apk_abis and not set(apk_abis).intersection(device_abis):
        raise ValueError('ABI non compatibile con il dispositivo')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--backup', type=Path, help='Backup privato completo; richiede build debuggable')
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or '')
    adb = shutil.which('adb') or str(sdk / 'platform-tools/adb')
    build_tools = sorted((sdk / 'build-tools').glob('*'), key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.name)))
    if not build_tools:
        raise SystemExit('Imposta ANDROID_SDK_ROOT per aapt e apksigner')
    aapt = str(build_tools[-1] / 'aapt')
    signer = str(build_tools[-1] / 'apksigner')
    def read(command):
        return subprocess.check_output(command, text=True).strip()
    def device(*command):
        return [adb, '-s', args.serial, *command]
    def certificate(path):
        output = read([signer, 'verify', '--print-certs', str(path)])
        return re.search(r'certificate SHA-256 digest: (\S+)', output).group(1)
    metadata = read([aapt, 'dump', 'badging', str(args.apk)])
    package = re.search(r"package: name='([^']+)'", metadata).group(1)
    new_code = int(re.search(r"versionCode='(\d+)'", metadata).group(1))
    old = read(device('shell', 'dumpsys', 'package', PACKAGE))
    match = re.search(r'versionCode=(\d+)', old)
    old_code = int(match.group(1)) if match else 0
    old_certificate = None
    if old_code:
        paths = read(device('shell', 'pm', 'path', PACKAGE)).splitlines()
        base = next(path.removeprefix('package:') for path in paths if path.endswith('/base.apk'))
        with tempfile.TemporaryDirectory(prefix='bloomeetv-signature-') as directory:
            pulled = Path(directory) / 'installed.apk'
            subprocess.run(device('pull', base, str(pulled)), check=True, capture_output=True)
            old_certificate = certificate(pulled)
    abi_line = next((line for line in metadata.splitlines() if line.startswith('native-code:')), '')
    validate_update(package, new_code, old_code, certificate(args.apk), old_certificate,
                    re.findall(r"'([^']+)'", abi_line), read(device('shell', 'getprop', 'ro.product.cpu.abilist')).split(','))
    if args.backup and old_code:
        args.backup.parent.mkdir(parents=True, exist_ok=True)
        if args.backup.exists():
            raise SystemExit('Il backup esiste già; non verrà sovrascritto')
        subprocess.run(device('shell', 'am', 'force-stop', PACKAGE), check=True, capture_output=True)
        with args.backup.open('xb') as output:
            os.chmod(args.backup, 0o600)
            result = subprocess.run(device('exec-out', 'run-as', PACKAGE, 'tar', '-cf', '-', '.'), stdout=output, stderr=subprocess.PIPE)
        if result.returncode:
            args.backup.unlink(missing_ok=True)
            raise SystemExit('Backup non disponibile: installazione annullata')
    print(f'Aggiornamento verificato {old_code} → {new_code}; firma e ABI compatibili', flush=True)
    subprocess.run(device('install', '-r', '-t', str(args.apk)), check=True)

if __name__ == '__main__':
    main()
