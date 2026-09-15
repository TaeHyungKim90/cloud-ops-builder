.PHONY: trivy-image

TRIVY_IMAGE ?= nexus.sk-inc.com:8081/cr/cloud-ops-builder:v1.2.0

trivy-image:
	-@echo "-> $@"
	python3 scripts/trivy_image_summary.py $(TRIVY_IMAGE)
