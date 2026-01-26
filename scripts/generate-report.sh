#!/bin/bash
# Generate deployment report from Terraform outputs

set -e

REPORT_FILE="deployment-report.txt"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Generating deployment report...${NC}"

# Get all outputs as JSON
OUTPUTS=$(terraform output -json 2>/dev/null)

if [ -z "$OUTPUTS" ] || [ "$OUTPUTS" == "{}" ]; then
    echo -e "${RED}No Terraform outputs available. Has infrastructure been deployed?${NC}"
    exit 1
fi

# Helper function to get output value
get_output() {
    echo "$OUTPUTS" | jq -r ".$1.value // \"N/A\""
}

# Generate report
cat > "$REPORT_FILE" << EOF
================================================================================
                    TERRAFORM INFRASTRUCTURE DEPLOYMENT REPORT
================================================================================
Generated: $TIMESTAMP

================================================================================
                              NETWORK INFRASTRUCTURE
================================================================================

VPC 1 ID:                  $(get_output "vpc1_id")
VPC 2 ID:                  $(get_output "vpc2_id")

================================================================================
                              FORTIGATE FIREWALLS
================================================================================

FORTIGATE 1 (VPC 1)
-------------------
  Public IP:               $(get_output "fortigate1_public_ip")
  Private IP:              $(get_output "fortigate1_private_ip")
  Management URL:          $(get_output "fortigate1_management_url")
  SSH Command:             $(get_output "ssh_to_fortigate1")

FORTIGATE 2 (VPC 2)
-------------------
  Public IP:               $(get_output "fortigate2_public_ip")
  Private IP:              $(get_output "fortigate2_private_ip")
  Management URL:          $(get_output "fortigate2_management_url")
  SSH Command:             $(get_output "ssh_to_fortigate2")

CREDENTIALS
-----------
  Username:                admin
  Password:                <FortiGate Instance ID> (retrieve from AWS Console)

================================================================================
                              UBUNTU VMs
================================================================================

Ubuntu VM 1 (VPC 1)
-------------------
  Private IP:              $(get_output "ubuntu1_private_ip")

Ubuntu VM 2 (VPC 2)
-------------------
  Private IP:              $(get_output "ubuntu2_private_ip")

CONNECTIVITY TEST
-----------------
  Command:                 $(get_output "connectivity_test_command")

EOF

# Check if Bedrock Agent is enabled
AGENT_ID=$(get_output "bedrock_agent_id")
if [ "$AGENT_ID" != "N/A" ] && [ "$AGENT_ID" != "null" ]; then
cat >> "$REPORT_FILE" << EOF
================================================================================
                              BEDROCK AI AGENT
================================================================================

Agent ID:                  $AGENT_ID
Agent Alias ID:            $(get_output "bedrock_agent_alias_id")
Terraform S3 Bucket:       $(get_output "bedrock_terraform_bucket")

USAGE INSTRUCTIONS
------------------
$(get_output "bedrock_agent_usage")

EOF
fi

# Check if Chat UI is enabled
CHAT_URL=$(get_output "chat_ui_url")
if [ "$CHAT_URL" != "N/A" ] && [ "$CHAT_URL" != "null" ]; then

# Retrieve API key from SSM
API_KEY=$(aws ssm get-parameter --name "/terraform-chat/api-key" --with-decryption --query Parameter.Value --output text --region us-east-2 2>/dev/null || echo "N/A")

cat >> "$REPORT_FILE" << EOF
================================================================================
                              CHAT UI
================================================================================

Website URL:               $CHAT_URL
API Endpoint:              $(get_output "chat_ui_api_endpoint")
API Key:                   $API_KEY
S3 Bucket:                 $(get_output "chat_ui_bucket")
CloudFront Distribution:   $(get_output "chat_ui_cloudfront_id")

CONFIGURATION
-------------
To use the Chat UI with the real Bedrock Agent (not mock mode):
1. Open the Website URL above
2. Click "Settings" in the top right
3. Enter the API Endpoint and API Key shown above
4. Click "Save"

DEPLOYMENT INSTRUCTIONS
-----------------------
$(get_output "chat_ui_deployment_instructions")

EOF
fi

# Add resource count
RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
cat >> "$REPORT_FILE" << EOF
================================================================================
                              SUMMARY
================================================================================

Total Resources Created:   $RESOURCE_COUNT

Report saved to:           $REPORT_FILE

================================================================================
EOF

# Display the report
echo ""
cat "$REPORT_FILE"

echo -e "\n${GREEN}Report saved to: ${REPORT_FILE}${NC}"
