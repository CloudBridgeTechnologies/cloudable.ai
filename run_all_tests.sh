#!/bin/bash
# Comprehensive Test Runner for Cloudable.AI

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Set test report directory and file
REPORT_DIR="/tmp/cloudable_test_reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/test_report_${TIMESTAMP}.html"
LOG_DIR="${REPORT_DIR}/logs_${TIMESTAMP}"

# Create directories for reports and logs
mkdir -p ${REPORT_DIR}
mkdir -p ${LOG_DIR}

# Function to run a test and capture its output and status
run_test() {
    local test_name=$1
    local test_script=$2
    local log_file="${LOG_DIR}/${test_name// /_}.log"
    
    echo -e "\n${YELLOW}Running test: ${test_name}${NC}"
    
    # Run the test script and capture output
    start_time=$(date +%s)
    ${test_script} > ${log_file} 2>&1
    status=$?
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Print test result
    if [ ${status} -eq 0 ]; then
        echo -e "${GREEN}✓ Test passed${NC} (${duration} seconds)"
    else
        echo -e "${RED}✗ Test failed${NC} (${duration} seconds)"
    fi
    
    # Return test information
    echo "${test_name}|${status}|${duration}|${log_file}"
}

# Start generating HTML report
cat > ${REPORT_FILE} << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Cloudable.AI Test Report - ${TIMESTAMP}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            color: #333;
            line-height: 1.6;
        }
        h1, h2, h3 {
            color: #0066cc;
        }
        .header {
            background-color: #f8f9fa;
            padding: 20px;
            margin-bottom: 20px;
            border-radius: 5px;
            border-left: 5px solid #0066cc;
        }
        .summary {
            display: flex;
            justify-content: space-between;
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .summary-item {
            text-align: center;
            flex: 1;
        }
        .summary-item h3 {
            margin: 0 0 10px 0;
        }
        .summary-value {
            font-size: 24px;
            font-weight: bold;
        }
        .passed { color: #2ecc71; }
        .failed { color: #e74c3c; }
        .total { color: #3498db; }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 12px 15px;
            border-bottom: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f8f9fa;
            font-weight: bold;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .status-passed {
            color: #2ecc71;
            font-weight: bold;
        }
        .status-failed {
            color: #e74c3c;
            font-weight: bold;
        }
        .details {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin-top: 10px;
            overflow: auto;
            max-height: 300px;
            white-space: pre-wrap;
            font-family: monospace;
            font-size: 14px;
            display: none;
        }
        .toggle-button {
            background-color: #0066cc;
            color: white;
            border: none;
            padding: 5px 10px;
            cursor: pointer;
            border-radius: 3px;
        }
        .toggle-button:hover {
            background-color: #004c99;
        }
        .footer {
            margin-top: 30px;
            text-align: center;
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Cloudable.AI Test Report</h1>
        <p><strong>Date:</strong> $(date +"%Y-%m-%d %H:%M:%S")</p>
        <p><strong>Environment:</strong> $(hostname)</p>
        <p><strong>AWS Region:</strong> $(aws configure get region)</p>
    </div>
    
    <div class="summary" id="summary">
        <!-- Will be filled dynamically -->
    </div>
    
    <h2>Test Results</h2>
    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>Test Name</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Details</th>
            </tr>
        </thead>
        <tbody>
EOF

echo -e "${BLUE}==================================================${NC}"
echo -e "${BOLD}${BLUE}    CLOUDABLE.AI COMPREHENSIVE TEST SUITE     ${NC}${BOLD}"
echo -e "${BLUE}==================================================${NC}"

# List of tests to run with their descriptions
declare -a TEST_NAMES
declare -a TEST_SCRIPTS

TEST_NAMES[0]="Standard E2E Test"
TEST_SCRIPTS[0]="./e2e_rds_pgvector_test.sh"

TEST_NAMES[1]="Multi-tenant Test"
TEST_SCRIPTS[1]="./qa_test_multitenant.sh"

TEST_NAMES[2]="Vector Search Test"
TEST_SCRIPTS[2]="./qa_test_vector_search.sh"

TEST_NAMES[3]="Edge Cases Test"
TEST_SCRIPTS[3]="./qa_test_edge_cases.sh"

# Initialize counters
TOTAL=0
PASSED=0
FAILED=0

# Run each test and capture results
for i in "${!TEST_NAMES[@]}"; do
    test_name="${TEST_NAMES[$i]}"
    test_script="${TEST_SCRIPTS[$i]}"
    result=$(run_test "$test_name" "$test_script")
    
    # Parse test result
    IFS='|' read -r name status duration log_file <<< "$result"
    
    # Update counters
    ((TOTAL++))
    if [ "$status" = "0" ]; then
        ((PASSED++))
        status_class="passed"
        status_text="Passed"
    else
        ((FAILED++))
        status_class="failed"
        status_text="Failed"
    fi
    
    # Get log content
    log_content=$(cat ${log_file})
    
    # Add test result to HTML report
    cat >> ${REPORT_FILE} << EOF
        <tr>
            <td>${TOTAL}</td>
            <td>${name}</td>
            <td class="status-${status_class}">${status_text}</td>
            <td>${duration} seconds</td>
            <td>
                <button class="toggle-button" onclick="toggleDetails('details-${TOTAL}')">Show/Hide</button>
                <div id="details-${TOTAL}" class="details">
${log_content}
                </div>
            </td>
        </tr>
EOF
done

# Calculate success percentage
if [ $TOTAL -gt 0 ]; then
    SUCCESS_PERCENT=$((PASSED * 100 / TOTAL))
else
    SUCCESS_PERCENT=0
fi

# Finish generating the HTML report
cat >> ${REPORT_FILE} << EOF
        </tbody>
    </table>
    
    <div class="footer">
        <p>Generated by Cloudable.AI Test Runner on $(date +"%Y-%m-%d %H:%M:%S")</p>
    </div>
    
    <script>
        // Add summary data
        document.getElementById("summary").innerHTML = \`
            <div class="summary-item">
                <h3>Total Tests</h3>
                <div class="summary-value total">${TOTAL}</div>
            </div>
            <div class="summary-item">
                <h3>Passed</h3>
                <div class="summary-value passed">${PASSED}</div>
            </div>
            <div class="summary-item">
                <h3>Failed</h3>
                <div class="summary-value failed">${FAILED}</div>
            </div>
            <div class="summary-item">
                <h3>Success Rate</h3>
                <div class="summary-value">${SUCCESS_PERCENT}%</div>
            </div>
        \`;
        
        // Function to toggle test details
        function toggleDetails(id) {
            var element = document.getElementById(id);
            if (element.style.display === "block") {
                element.style.display = "none";
            } else {
                element.style.display = "block";
            }
        }
    </script>
</body>
</html>
EOF

# Print summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}                 TEST SUMMARY                     ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Total tests:   ${TOTAL}"
echo -e "${GREEN}Tests passed:  ${PASSED}${NC}"
if [ ${FAILED} -gt 0 ]; then
    echo -e "${RED}Tests failed:  ${FAILED}${NC}"
fi

echo -e "Success rate:  ${SUCCESS_PERCENT}%"
echo -e "\nDetailed report: ${REPORT_FILE}"
echo -e "Test logs: ${LOG_DIR}"
echo -e "${BLUE}==================================================${NC}"

# Open the report in browser if on Mac
if [[ "$OSTYPE" == "darwin"* ]]; then
    open ${REPORT_FILE}
fi

# Exit with appropriate status code
if [ ${FAILED} -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Review the detailed report.${NC}"
    exit 1
fi
