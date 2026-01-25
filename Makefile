.PHONY: init validate fmt plan apply destroy clean output refresh test \
	plan-agent plan-full apply-agent apply-full deploy-agent deploy-full \
	destroy-agent destroy-full build-ui clean-ui report

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

# Preview infrastructure changes (base infrastructure only)
plan:
	terraform plan -out=tfplan

# Preview with Bedrock Agent enabled
plan-agent:
	terraform plan -var="enable_bedrock_agent=true" -out=tfplan

# Preview full deployment (agent + chat UI)
plan-full:
	terraform plan -var="enable_bedrock_agent=true" -var="enable_chat_ui=true" -out=tfplan

# Apply the saved plan
apply:
	terraform apply tfplan
	@./scripts/generate-report.sh

# Apply with Bedrock Agent enabled
apply-agent:
	terraform apply -var="enable_bedrock_agent=true" -auto-approve
	@./scripts/generate-report.sh

# Apply full deployment (agent + chat UI)
apply-full: build-ui
	terraform apply -var="enable_bedrock_agent=true" -var="enable_chat_ui=true" -auto-approve
	@./scripts/generate-report.sh

# Apply directly without saving plan first
apply-auto:
	terraform apply -auto-approve
	@./scripts/generate-report.sh

# Destroy all infrastructure (base only)
destroy:
	terraform destroy

# Destroy with Bedrock Agent
destroy-agent:
	terraform destroy -var="enable_bedrock_agent=true"

# Destroy full deployment (agent + chat UI)
destroy-full:
	terraform destroy -var="enable_bedrock_agent=true" -var="enable_chat_ui=true"

# Destroy without confirmation prompt
destroy-auto:
	terraform destroy -auto-approve

# Destroy agent deployment without confirmation
destroy-agent-auto:
	terraform destroy -var="enable_bedrock_agent=true" -auto-approve

# Destroy full deployment without confirmation
destroy-full-auto:
	terraform destroy -var="enable_bedrock_agent=true" -var="enable_chat_ui=true" -auto-approve

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

# Clean Chat UI build artifacts
clean-ui:
	rm -rf chat-ui/dist
	rm -rf chat-ui/node_modules/.vite

# Build Chat UI React application
build-ui:
	cd chat-ui && npm install && npm run build

# Setup: init, validate, and plan
setup: init validate plan

# Full deployment: init, validate, plan, apply (base infrastructure)
deploy: init validate plan apply

# Deploy with Bedrock Agent
deploy-agent: init validate plan-agent apply

# Deploy full stack (infrastructure + agent + chat UI)
deploy-full: init validate build-ui plan-full apply

# Show current state
state:
	terraform state list

# Run infrastructure tests
test:
	./scripts/test-infrastructure.sh

# Generate deployment report
report:
	@./scripts/generate-report.sh

# Start Chat UI development server (mock mode)
dev-ui:
	cd chat-ui && npm install && npm run dev

# Show help
help:
	@echo "Available targets:"
	@echo ""
	@echo "  Initialization:"
	@echo "    init          - Initialize Terraform"
	@echo "    validate      - Validate configuration"
	@echo "    fmt           - Format Terraform files"
	@echo "    fmt-check     - Check formatting"
	@echo ""
	@echo "  Planning:"
	@echo "    plan          - Plan base infrastructure"
	@echo "    plan-agent    - Plan with Bedrock Agent"
	@echo "    plan-full     - Plan full stack (agent + chat UI)"
	@echo ""
	@echo "  Deployment:"
	@echo "    apply         - Apply saved plan"
	@echo "    apply-auto    - Apply without confirmation"
	@echo "    apply-agent   - Deploy with Bedrock Agent"
	@echo "    apply-full    - Deploy full stack (builds UI first)"
	@echo "    deploy        - Full pipeline (base infrastructure)"
	@echo "    deploy-agent  - Full pipeline with Bedrock Agent"
	@echo "    deploy-full   - Full pipeline (agent + chat UI)"
	@echo ""
	@echo "  Destruction:"
	@echo "    destroy       - Destroy base infrastructure"
	@echo "    destroy-agent - Destroy with Bedrock Agent"
	@echo "    destroy-full  - Destroy full stack"
	@echo "    destroy-auto  - Destroy without confirmation"
	@echo "    destroy-agent-auto - Destroy agent without confirmation"
	@echo "    destroy-full-auto  - Destroy full stack without confirmation"
	@echo ""
	@echo "  Chat UI:"
	@echo "    build-ui      - Build React chat application"
	@echo "    dev-ui        - Start local dev server (mock mode)"
	@echo "    clean-ui      - Remove UI build artifacts"
	@echo ""
	@echo "  Utilities:"
	@echo "    output        - Show outputs"
	@echo "    refresh       - Refresh state"
	@echo "    state         - List resources in state"
	@echo "    report        - Generate deployment report"
	@echo "    clean         - Remove plan file and provider cache"
	@echo "    clean-all     - Remove all Terraform local files"
	@echo "    setup         - Run init, validate, plan"
	@echo "    test          - Run infrastructure tests"
	@echo "    help          - Show this help"
