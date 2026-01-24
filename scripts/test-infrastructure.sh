#!/bin/bash
#
# Infrastructure Test Script
# Tests FortiGate VPN connectivity and cross-VPC communication
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Print functions
print_header() {
    echo ""
    echo "=============================================="
    echo "$1"
    echo "=============================================="
}

print_test() {
    echo -n "  Testing: $1... "
}

print_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}FAIL${NC}"
    echo -e "    ${RED}Error: $1${NC}"
    ((TESTS_FAILED++))
}

print_skip() {
    echo -e "${YELLOW}SKIP${NC}"
    echo -e "    ${YELLOW}Reason: $1${NC}"
}

print_info() {
    echo -e "  ${YELLOW}Info:${NC} $1"
}

# Check if terraform is available
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Error: terraform is not installed${NC}"
        exit 1
    fi
}

# Get terraform outputs
get_outputs() {
    print_header "Retrieving Terraform Outputs"

    if ! terraform output &> /dev/null; then
        echo -e "${RED}Error: Failed to get terraform outputs. Is infrastructure deployed?${NC}"
        exit 1
    fi

    FG1_PUBLIC_IP=$(terraform output -raw fortigate1_public_ip 2>/dev/null) || true
    FG2_PUBLIC_IP=$(terraform output -raw fortigate2_public_ip 2>/dev/null) || true
    UBUNTU1_IP=$(terraform output -raw ubuntu1_private_ip 2>/dev/null) || true
    UBUNTU2_IP=$(terraform output -raw ubuntu2_private_ip 2>/dev/null) || true

    echo "  FortiGate 1 Public IP: $FG1_PUBLIC_IP"
    echo "  FortiGate 2 Public IP: $FG2_PUBLIC_IP"
    echo "  Ubuntu 1 Private IP:   $UBUNTU1_IP"
    echo "  Ubuntu 2 Private IP:   $UBUNTU2_IP"
}

# Test FortiGate HTTPS accessibility
test_fortigate_https() {
    print_header "Testing FortiGate Web Console Access"

    print_test "FortiGate 1 HTTPS (port 443)"
    if curl -sk --connect-timeout 10 "https://$FG1_PUBLIC_IP" > /dev/null 2>&1; then
        print_pass
    else
        print_fail "Cannot reach https://$FG1_PUBLIC_IP"
    fi

    print_test "FortiGate 2 HTTPS (port 443)"
    if curl -sk --connect-timeout 10 "https://$FG2_PUBLIC_IP" > /dev/null 2>&1; then
        print_pass
    else
        print_fail "Cannot reach https://$FG2_PUBLIC_IP"
    fi
}

# Test FortiGate SSH accessibility
test_fortigate_ssh() {
    print_header "Testing FortiGate SSH Access"

    print_test "FortiGate 1 SSH (port 22)"
    if nc -z -w 5 "$FG1_PUBLIC_IP" 22 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG1_PUBLIC_IP:22"
    fi

    print_test "FortiGate 2 SSH (port 22)"
    if nc -z -w 5 "$FG2_PUBLIC_IP" 22 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG2_PUBLIC_IP:22"
    fi
}

# Test VPN ports
test_vpn_ports() {
    print_header "Testing VPN Ports (IKE/NAT-T)"

    print_test "FortiGate 1 IKE (UDP 500)"
    if nc -zu -w 5 "$FG1_PUBLIC_IP" 500 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG1_PUBLIC_IP:500/udp"
    fi

    print_test "FortiGate 1 NAT-T (UDP 4500)"
    if nc -zu -w 5 "$FG1_PUBLIC_IP" 4500 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG1_PUBLIC_IP:4500/udp"
    fi

    print_test "FortiGate 2 IKE (UDP 500)"
    if nc -zu -w 5 "$FG2_PUBLIC_IP" 500 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG2_PUBLIC_IP:500/udp"
    fi

    print_test "FortiGate 2 NAT-T (UDP 4500)"
    if nc -zu -w 5 "$FG2_PUBLIC_IP" 4500 2>/dev/null; then
        print_pass
    else
        print_fail "Cannot reach $FG2_PUBLIC_IP:4500/udp"
    fi
}

# Test VPN tunnel status via SSH
test_vpn_tunnel() {
    print_header "Testing VPN Tunnel Status"

    KEY_FILE="fortigate-demo-key.pem"

    if [ ! -f "$KEY_FILE" ]; then
        print_test "VPN tunnel status"
        print_skip "SSH key file not found: $KEY_FILE"
        return
    fi

    print_test "VPN tunnel on FortiGate 1"
    VPN_STATUS=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        admin@"$FG1_PUBLIC_IP" "get vpn ipsec tunnel summary" 2>/dev/null) || true

    if echo "$VPN_STATUS" | grep -q "up"; then
        print_pass
        print_info "Tunnel is UP"
    elif [ -z "$VPN_STATUS" ]; then
        print_fail "Could not connect via SSH"
    else
        print_fail "Tunnel is DOWN"
        print_info "Run 'diagnose vpn ike log filter name vpn-to-vpc2' on FortiGate for details"
    fi
}

# Test cross-VPC ping via FortiGate
test_cross_vpc_ping() {
    print_header "Testing Cross-VPC Connectivity"

    KEY_FILE="fortigate-demo-key.pem"

    if [ ! -f "$KEY_FILE" ]; then
        print_test "Cross-VPC ping"
        print_skip "SSH key file not found: $KEY_FILE"
        return
    fi

    print_test "Ping from FortiGate 1 to Ubuntu 2 ($UBUNTU2_IP)"
    PING_RESULT=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        admin@"$FG1_PUBLIC_IP" "execute ping-options repeat-count 3" 2>/dev/null && \
        ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        admin@"$FG1_PUBLIC_IP" "execute ping $UBUNTU2_IP" 2>/dev/null) || true

    if echo "$PING_RESULT" | grep -q "bytes="; then
        print_pass
    elif [ -z "$PING_RESULT" ]; then
        print_fail "Could not connect via SSH"
    else
        print_fail "Ping failed - VPN tunnel may be down"
    fi

    print_test "Ping from FortiGate 2 to Ubuntu 1 ($UBUNTU1_IP)"
    PING_RESULT=$(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        admin@"$FG2_PUBLIC_IP" "execute ping-options repeat-count 3" 2>/dev/null && \
        ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        admin@"$FG2_PUBLIC_IP" "execute ping $UBUNTU1_IP" 2>/dev/null) || true

    if echo "$PING_RESULT" | grep -q "bytes="; then
        print_pass
    elif [ -z "$PING_RESULT" ]; then
        print_fail "Could not connect via SSH"
    else
        print_fail "Ping failed - VPN tunnel may be down"
    fi
}

# Print summary
print_summary() {
    print_header "Test Summary"

    TOTAL=$((TESTS_PASSED + TESTS_FAILED))

    echo ""
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "  Total:  $TOTAL"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Check the output above for details.${NC}"
        exit 1
    fi
}

# Main
main() {
    echo ""
    echo "FortiGate VPN Infrastructure Test Suite"
    echo "========================================"

    check_terraform
    get_outputs
    test_fortigate_https
    test_fortigate_ssh
    test_vpn_ports
    test_vpn_tunnel
    test_cross_vpc_ping
    print_summary
}

main "$@"
