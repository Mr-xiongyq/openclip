import os
from pathlib import Path
import re
import subprocess
import sys

mode = sys.argv[1]
logs = Path(os.environ['RUNNER_TEMP']) / 'openclip-validation'
logs.mkdir(exist_ok=True)
source = Path('Sources/Core/Extensions/ExtensionManager.swift')
if mode == 'build':
    command = ['xcodebuild', '-project', 'OpenClip.xcodeproj', '-scheme', 'OpenClip', '-destination', 'platform=macOS', 'build']
elif mode == 'baseline':
    source.write_bytes(subprocess.check_output(['git', 'show', '35d53b2fba1927e049a12ac55b1576c698cb5e56:' + str(source)]))
    command = ['./scripts/test.sh', 'ExtensionUninstallOptionsTests', '--verbose']
else:
    command = ['./scripts/test.sh']

path = logs / (mode + '.log')
try:
    with path.open('w') as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=900)
    text = path.read_text()
    for line in text.splitlines():
        if mode == 'full' or any(word in line for word in ['error:', 'Executed ', 'Test Suite ', 'Test Case ', '** BUILD', '** TEST']):
            print(line)
    if mode == 'baseline':
        if result.returncode == 0 or not re.search(r"Test Suite '[^']*ExtensionUninstallOptionsTests' failed", text):
            raise SystemExit('Expected XCTest assertion failures from the original uninstall logic.')
        print('BASELINE_REGRESSION_CONFIRMED')
    elif result.returncode:
        print(text[-12000:])
        raise SystemExit(result.returncode)
finally:
    if mode == 'baseline':
        subprocess.run(['git', 'restore', str(source)], check=True)
