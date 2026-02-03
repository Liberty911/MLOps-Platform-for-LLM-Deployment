import requests
import json
from typing import Dict, List
import time

class LLMInferenceClient:
    def __init__(self, base_url: str = "http://llama2-7b.model-serving.svc.cluster.local:8080"):
        self.base_url = base_url
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer ${API_KEY}"
        }
    
    def generate(self, 
                 prompt: str, 
                 max_tokens: int = 100,
                 temperature: float = 0.7,
                 top_p: float = 0.9) -> Dict:
        """Generate text using LLM"""
        
        payload = {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens": max_tokens,
                "temperature": temperature,
                "top_p": top_p,
                "do_sample": True,
                "return_full_text": False
            }
        }
        
        try:
            start_time = time.time()
            response = requests.post(
                f"{self.base_url}/v2/models/llama2_7b/infer",
                headers=self.headers,
                json=payload,
                timeout=30
            )
            response.raise_for_status()
            
            inference_time = time.time() - start_time
            
            result = response.json()
            
            return {
                "text": result["generated_text"],
                "inference_time": inference_time,
                "model": "llama2-7b",
                "tokens_generated": len(result["generated_text"].split())
            }
            
        except requests.exceptions.RequestException as e:
            raise Exception(f"Inference request failed: {e}")
    
    def batch_generate(self, prompts: List[str], **kwargs) -> List[Dict]:
        """Generate text for multiple prompts in batch"""
        
        payload = {
            "inputs": prompts,
            "parameters": kwargs
        }
        
        response = requests.post(
            f"{self.base_url}/v2/models/llama2_7b/infer",
            headers=self.headers,
            json=payload
        )
        
        response.raise_for_status()
        return response.json()

if __name__ == "__main__":
    # Example usage
    client = LLMInferenceClient()
    
    prompt = "Explain the concept of machine learning in simple terms:"
    
    result = client.generate(prompt, max_tokens=150)
    
    print(f"Generated text: {result['text']}")
    print(f"Inference time: {result['inference_time']:.2f}s")
    print(f"Tokens generated: {result['tokens_generated']}")