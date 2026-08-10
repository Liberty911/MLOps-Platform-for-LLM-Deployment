.PHONY: bootstrap deploy validate lint clean help

help:
	@echo "MLOps Platform for LLM Deployment"
	@echo ""
	@echo "Targets:"
	@echo "  bootstrap  - Add required Helm repos"
	@echo "  deploy     - Full local Kind deployment"
	@echo "  validate   - Validate cluster state"
	@echo "  clean      - Delete InferenceServices and Kind cluster"
	@echo "  lint       - Lint scripts"

bootstrap:
	bash platform/tools/bootstrap.sh

deploy:
	bash deploy.sh

validate:
	bash platform/tools/validate.sh

lint:
	bash platform/tools/lint.sh || true

clean:
	kubectl delete isvc --all --all-namespaces 2>/dev/null || true
	kind delete cluster --name mlops 2>/dev/null || true
	@echo "Cleaned."
