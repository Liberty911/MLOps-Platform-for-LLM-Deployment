.PHONY: help deploy destroy status logs monitor

help:
	@echo "MLOps Platform for LLM Deployment"
	@echo ""
	@echo "Commands:"
	@echo "  deploy       - Deploy the entire platform"
	@echo "  destroy      - Destroy the platform"
	@echo "  status       - Check platform status"
	@echo "  logs         - View platform logs"
	@echo "  monitor      - Open monitoring dashboards"
	@echo "  deploy-model - Deploy a specific model"
	@echo "  test         - Run tests"

deploy:
	@echo "Deploying MLOps Platform..."
	@./scripts/setup-aws.sh
	@./scripts/deploy-platform.sh

destroy:
	@echo "Destroying MLOps Platform..."
	@cd terraform && terraform destroy -auto-approve

status:
	@echo "Platform Status:"
	@echo "================"
	@kubectl get nodes
	@echo ""
	@kubectl get pods -A

logs:
	@kubectl logs -f deployment/triton-inference-server -n model-serving

monitor:
	@echo "Opening monitoring dashboards..."
	@open http://grafana.mlops-platform.local || echo "Grafana dashboard URL: http://grafana.mlops-platform.local"
	@open http://ray-dashboard.mlops-platform.local || echo "Ray dashboard URL: http://ray-dashboard.mlops-platform.local"

deploy-model:
	@./scripts/model-deploy.sh $(MODEL)

test:
	@echo "Running tests..."
	@python -m pytest tests/ -v

# Development commands
dev-setup:
	@pip install -r requirements.txt
	@pre-commit install

lint:
	@black .
	@flake8 .
	@mypy .