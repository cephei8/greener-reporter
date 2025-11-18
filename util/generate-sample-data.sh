#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$GREENER_INGRESS_ENDPOINT" ]; then
    echo -e "${RED}Error: GREENER_INGRESS_ENDPOINT environment variable is not set${NC}"
    exit 1
fi

if [ -z "$GREENER_INGRESS_API_KEY" ]; then
    echo -e "${RED}Error: GREENER_INGRESS_API_KEY environment variable is not set${NC}"
    exit 1
fi

ENDPOINT="$GREENER_INGRESS_ENDPOINT"
API_KEY="$GREENER_INGRESS_API_KEY"

echo -e "${GREEN}Generating sample test data...${NC}"
echo "Endpoint: $ENDPOINT"
echo ""

run_cli() {
    ./target/debug/greener-reporter-cli --endpoint "$ENDPOINT" --api-key "$API_KEY" "$@"
}

VERSIONS=("1.0.0" "1.0.1" "1.1.0" "2.0.0" "2.1.0")
TARGETS=("linux-x64" "linux-arm64" "win-x64" "darwin-x64" "darwin-arm64")

SUITES="AuthenticationTests DatabaseTests APITests IntegrationTests"

get_tests_for_suite() {
    case "$1" in
        AuthenticationTests)
            echo "test_login_success test_login_invalid_password test_login_missing_credentials test_logout test_session_timeout"
            ;;
        DatabaseTests)
            echo "test_connection_pool test_query_users test_insert_record test_update_record test_delete_record test_transaction_rollback"
            ;;
        APITests)
            echo "test_get_user test_create_user test_update_user test_delete_user test_list_users test_pagination"
            ;;
        IntegrationTests)
            echo "test_end_to_end_flow test_payment_processing test_email_notification test_webhook_delivery"
            ;;
    esac
}

TOTAL_SESSIONS=$((${#VERSIONS[@]} * ${#TARGETS[@]}))
CURRENT=0

for VERSION in "${VERSIONS[@]}"; do
    for TARGET in "${TARGETS[@]}"; do
        CURRENT=$((CURRENT + 1))
        echo -e "${YELLOW}[$CURRENT/$TOTAL_SESSIONS] Generating session for version=$VERSION, target=$TARGET${NC}"

        SESSION_OUTPUT=$(run_cli create session \
            --label "version=$VERSION" \
            --label "target=$TARGET" \
            --label "env=ci" \
            --baggage '{"runner":"github-actions","build":"automated","branch":"main"}')

        SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if [ -z "$SESSION_ID" ]; then
            echo "Error: Could not extract session ID"
            exit 1
        fi

        echo "  Session ID: $SESSION_ID"

        TEST_COUNT=0
        for SUITE in $SUITES; do
            TESTS=$(get_tests_for_suite "$SUITE")

            for TEST in $TESTS; do
                TEST_COUNT=$((TEST_COUNT + 1))

                STATUS="pass"
                OUTPUT=""

                if [ "$TEST" = "test_login_invalid_password" ]; then
                    STATUS="pass"
                    OUTPUT="AssertionError: Invalid credentials rejected as expected"
                elif [ "$TEST" = "test_session_timeout" ] && [ "$VERSION" = "1.0.0" ]; then
                    STATUS="fail"
                    OUTPUT="AssertionError: Session did not timeout after 30 minutes\n  Expected: SessionExpired\n  Got: ActiveSession"
                elif [ "$TEST" = "test_transaction_rollback" ] && [ "$TARGET" = "win-x64" ]; then
                    STATUS="fail"
                    OUTPUT="DatabaseError: Rollback failed - transaction already committed\n  at connection.rollback() line 42"
                elif [ "$TEST" = "test_webhook_delivery" ] && [ "$VERSION" = "1.0.1" ]; then
                    STATUS="skip"
                    OUTPUT="Skipped: Webhook service not available in this version"
                elif [ "$TEST" = "test_email_notification" ] && [ "$TARGET" = "darwin-arm64" ] && [ "$VERSION" = "1.0.0" ]; then
                    STATUS="fail"
                    OUTPUT="TimeoutError: Email service did not respond within 5s\n  Service: smtp.example.com:587"
                elif [ "$TEST" = "test_delete_record" ] && [ "$VERSION" = "1.1.0" ]; then
                    STATUS="skip"
                    OUTPUT="Skipped: Delete operation disabled in this version for testing"
                elif [ "$TEST" = "test_payment_processing" ] && [ "$TARGET" = "linux-arm64" ]; then
                    STATUS="fail"
                    OUTPUT="PaymentError: SSL certificate verification failed\n  Expected: valid certificate\n  Got: self-signed certificate"
                fi

                SUITE_LOWER=$(echo "$SUITE" | tr '[:upper:]' '[:lower:]')

                run_cli create testcase \
                    --session-id "$SESSION_ID" \
                    --name "$TEST" \
                    --classname "$SUITE" \
                    --testsuite "$SUITE" \
                    --file "tests/${SUITE_LOWER}.py" \
                    --status "$STATUS" \
                    --output "$OUTPUT" > /dev/null
            done
        done

        echo "  Created $TEST_COUNT test cases"
        echo ""
    done
done

echo -e "${GREEN}Sample data generation complete${NC}"
echo ""
echo "Summary:"
echo "  Sessions created: $TOTAL_SESSIONS"
echo "  Versions: ${VERSIONS[*]}"
echo "  Targets: ${TARGETS[*]}"
