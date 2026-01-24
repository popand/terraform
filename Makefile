.PHONY: init validate fmt plan apply destroy clean output refresh test

# Initialize Terraform and download providers
init:
	terraform init

# Validate configuration syntax
validate:
	terraform validate

# Format Terraform files
fmt:
	terraform fmt -recursive

# Check formatting without making changes
fmt-check:
	terraform fmt -check -recursive

# Preview infrastructure changes
plan:
	terraform plan -out=tfplan

# Apply the saved plan
apply:
	terraform apply tfplan

# Apply directly without saving plan first
apply-auto:
	terraform apply -auto-approve

# Destroy all infrastructure
destroy:
	terraform destroy

# Destroy without confirmation prompt
destroy-auto:
	terraform destroy -auto-approve

# Show current outputs
output:
	terraform output

# Refresh state from actual infrastructure
refresh:
	terraform refresh

# Clean up local files (keep state)
clean:
	rm -f tfplan
	rm -rf .terraform/providers

# Full clean (removes everything except state)
clean-all:
	rm -f tfplan
	rm -rf .terraform

# Setup: init, validate, and plan
setup: init validate plan

# Full deployment: init, validate, plan, apply
deploy: init validate plan apply

# Show current state
state:
	terraform state list

# Run infrastructure tests
test:
	./scripts/test-infrastructure.sh

# Show help
help:
	@echo "Available targets:"
	@echo "  init        - Initialize Terraform"
	@echo "  validate    - Validate configuration"
	@echo "  fmt         - Format Terraform files"
	@echo "  fmt-check   - Check formatting"
	@echo "  plan        - Create execution plan"
	@echo "  apply       - Apply saved plan"
	@echo "  apply-auto  - Apply without confirmation"
	@echo "  destroy     - Destroy infrastructure"
	@echo "  destroy-auto- Destroy without confirmation"
	@echo "  output      - Show outputs"
	@echo "  refresh     - Refresh state"
	@echo "  clean       - Remove plan file and provider cache"
	@echo "  clean-all   - Remove all Terraform local files"
	@echo "  setup       - Run init, validate, plan"
	@echo "  deploy      - Full deployment pipeline"
	@echo "  state       - List resources in state"
	@echo "  test        - Run infrastructure tests"
	@echo "  help        - Show this help"
