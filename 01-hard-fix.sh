#!/bin/bash
set -e

echo ">>> Surgically repairing KServe JSON configuration..."

# We use Python to natively parse and repair the embedded JSON payload to avoid regex/sed blindspots
cat << 'EOF' > fix-kserve-config.py
import json
import subprocess

# 1. Fetch current ConfigMap
raw_cm = subprocess.check_output(['kubectl', 'get', 'configmap', 'inferenceservice-config', '-n', 'kserve', '-o', 'json'])
cm = json.loads(raw_cm)

# 2. Parse the embedded JSON string for storageInitializer
storage_json_str = cm['data'].get('storageInitializer', '{}')
storage_data = json.loads(storage_json_str)

# 3. Purge all corrupted/unknown keys (like cpuModelcar)
allowed_keys = {'image', 'cpuRequest', 'cpuLimit', 'memoryRequest', 'memoryLimit'}
keys_to_delete = [k for k in storage_data.keys() if k not in allowed_keys]
for k in keys_to_delete:
    del storage_data[k]

# 4. Enforce valid Kubernetes resource limits
storage_data['cpuRequest'] = '100m'
storage_data['cpuLimit'] = '1'
storage_data['memoryRequest'] = '200Mi'
storage_data['memoryLimit'] = '1Gi'

# 5. Pack the clean JSON back into the ConfigMap object
cm['data']['storageInitializer'] = json.dumps(storage_data, indent=2)

with open('/tmp/clean-kserve-config.json', 'w') as f:
    json.dump(cm, f)
EOF

python3 fix-kserve-config.py
echo ">>> Applying clean configuration..."
kubectl apply -f /tmp/clean-kserve-config.json

echo ">>> Restarting Controller to process the clean configuration..."
kubectl rollout restart deployment kserve-controller-manager -n kserve
kubectl rollout status deployment kserve-controller-manager -n kserve --timeout=120s

echo ">>> Cleaning up..."
rm fix-kserve-config.py /tmp/clean-kserve-config.json