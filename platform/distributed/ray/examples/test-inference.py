# examples/test-inference.py
import requests
import json

# Get the service URL (update this after deployment)
SERVICE_URL = "http://llama2-7b.model-serving.svc.cluster.local:8080/v2/models/llama2-7b/infer"

payload = {
    "inputs": [
        {
            "name": "input_ids",
            "shape": [1, 10],
            "datatype": "INT64",
            "data": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        }
    ]
}

response = requests.post(SERVICE_URL, json=payload)
print(f"Status Code: {response.status_code}")
print(f"Response: {json.dumps(response.json(), indent=2)}")