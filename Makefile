SHELL := /bin/bash
.DEFAULT_GOAL := help

TOOLS := platform/tools

help:
	@echo "make bootstrap | fmt | lint | validate | ci"

bootstrap:
	@$(TOOLS)/bootstrap.sh

fmt:
	@$(TOOLS)/fmt.sh

lint:
	@$(TOOLS)/lint.sh

validate:
	@$(TOOLS)/validate.sh

ci: fmt lint validate
	@echo "OK ✅"
