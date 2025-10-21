#!/bin/sh

# Test script for generate.sh functions
# Uses test_data directory for testing

# Source the functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/functions.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
print_result() {
    test_name="$1"
    passed="$2"
    message="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$passed" = "true" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "${GREEN}✓${NC} $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "${RED}✗${NC} $test_name"
        if [ ! -z "$message" ]; then
            echo "  $message"
        fi
    fi
}

# Test directory setup
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test_data"
SFC_DIR="$TEST_DIR/SFC"

echo "Running tests using test_data..."
echo ""

# Test 1: clean_name function - basic name cleaning
echo "Testing clean_name function:"
result=$(clean_name "Chrono Trigger (USA).sfc" "sfc")
expected="Chrono Trigger"
if [ "$result" = "$expected" ]; then
    print_result "clean_name removes region tags" "true"
else
    print_result "clean_name removes region tags" "false" "Expected: '$expected', Got: '$result'"
fi

# Test 2: clean_name function - removes brackets
result=$(clean_name "Super Mario World [!].sfc" "sfc")
expected="Super Mario World"
if [ "$result" = "$expected" ]; then
    print_result "clean_name removes bracket tags" "true"
else
    print_result "clean_name removes bracket tags" "false" "Expected: '$expected', Got: '$result'"
fi

# Test 3: clean_name function - replaces underscores
result=$(clean_name "Final_Fantasy_VI.sfc" "sfc")
expected="Final Fantasy VI"
if [ "$result" = "$expected" ]; then
    print_result "clean_name replaces underscores with spaces" "true"
else
    print_result "clean_name replaces underscores with spaces" "false" "Expected: '$expected', Got: '$result'"
fi

# Test 4: clean_name function - handles "The" article
result=$(clean_name "Legend of Zelda, The (USA).sfc" "sfc")
expected="The Legend of Zelda"
if [ "$result" = "$expected" ]; then
    print_result "clean_name moves 'The' article to front" "true"
else
    print_result "clean_name moves 'The' article to front" "false" "Expected: '$expected', Got: '$result'"
fi

# Test 5: clean_name function - replaces dash with colon
result=$(clean_name "Zelda - A Link to the Past.sfc" "sfc")
expected="Zelda: A Link to the Past"
if [ "$result" = "$expected" ]; then
    print_result "clean_name replaces ' - ' with ': '" "true"
else
    print_result "clean_name replaces ' - ' with ': '" "false" "Expected: '$expected', Got: '$result'"
fi

# Test 6: Full integration test - generate from test_data/SFC
echo ""
echo "Testing full generation with test_data/SFC:"

# Backup existing miyoogamelist.xml if it exists
if [ -f "$SFC_DIR/miyoogamelist.xml" ]; then
    mv "$SFC_DIR/miyoogamelist.xml" "$SFC_DIR/miyoogamelist.xml.backup"
fi

# Generate the gamelist in the actual SFC directory
cd "$SFC_DIR"
generate_miyoogamelist "$SFC_DIR" "./Imgs" "sfc"

if [ -f "$SFC_DIR/miyoogamelist.xml" ]; then
    print_result "generate_miyoogamelist creates miyoogamelist.xml in SFC directory" "true"

    # Check XML structure
    if grep -q '<?xml version="1.0"?>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "XML has correct header" "true"
    else
        print_result "XML has correct header" "false"
    fi

    if grep -q '<gameList>' "$SFC_DIR/miyoogamelist.xml" && grep -q '</gameList>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "XML has gameList tags" "true"
    else
        print_result "XML has gameList tags" "false"
    fi

    # Check for game entries (should include all .sfc files recursively: 6 root + 5 Homebrew + 2 Rom Hacks = 13)
    game_count=$(grep -c '<game>' "$SFC_DIR/miyoogamelist.xml")
    expected_count=13
    if [ "$game_count" -eq "$expected_count" ]; then
        print_result "XML contains correct number of game entries ($game_count)" "true"
    else
        print_result "XML contains correct number of game entries" "false" "Expected: $expected_count, Got: $game_count"
    fi

    # Check for specific cleaned names
    if grep -q '<name>Chrono Trigger</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Game 'Chrono Trigger' correctly cleaned" "true"
    else
        print_result "Game 'Chrono Trigger' correctly cleaned" "false"
    fi

    if grep -q '<name>Donkey Kong Country</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Game 'Donkey Kong Country' correctly cleaned" "true"
    else
        print_result "Game 'Donkey Kong Country' correctly cleaned" "false"
    fi

    if grep -q '<name>Final Fantasy VI</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Game 'Final Fantasy VI' correctly cleaned" "true"
    else
        print_result "Game 'Final Fantasy VI' correctly cleaned" "false"
    fi

    if grep -q '<name>Mega Man X</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Game 'Mega Man X' correctly cleaned" "true"
    else
        print_result "Game 'Mega Man X' correctly cleaned" "false"
    fi

    if grep -q '<name>Super Mario World</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Game 'Super Mario World' correctly cleaned" "true"
    else
        print_result "Game 'Super Mario World' correctly cleaned" "false"
    fi

    # Test The Legend of Zelda with proper article and colon
    if grep -q '<name>The Legend of Zelda: A Link to the Past</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Complex name 'The Legend of Zelda: A Link to the Past' correctly cleaned" "true"
    else
        print_result "Complex name 'The Legend of Zelda: A Link to the Past' correctly cleaned" "false"
    fi

    # Check for proper paths
    if grep -q '<path>./Chrono Trigger (USA).sfc</path>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "ROM paths are preserved correctly" "true"
    else
        print_result "ROM paths are preserved correctly" "false"
    fi

    # Check for image paths
    if grep -q '<image>./Imgs/' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Image paths are generated correctly" "true"
    else
        print_result "Image paths are generated correctly" "false"
    fi

    # Test subdirectory games
    if grep -q '<path>./Homebrew/Test Game 1.sfc</path>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Subdirectory games have correct paths (Homebrew)" "true"
    else
        print_result "Subdirectory games have correct paths (Homebrew)" "false"
    fi

    if grep -q '<name>Homebrew/Test Game 1</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Subdirectory games have namespaced names" "true"
    else
        print_result "Subdirectory games have namespaced names" "false"
    fi

    if grep -q '<image>./Imgs/Homebrew/Test Game 1.png</image>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Subdirectory games have correct image paths" "true"
    else
        print_result "Subdirectory games have correct image paths" "false"
    fi

    if grep -q '<path>./Homebrew/Demos/Demo 1.sfc</path>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Nested subdirectory games are included" "true"
    else
        print_result "Nested subdirectory games are included" "false"
    fi

    if grep -q '<name>Rom Hacks/Super Mario World: Kaizo Edition</name>' "$SFC_DIR/miyoogamelist.xml"; then
        print_result "Subdirectory games have cleaned names with paths" "true"
    else
        print_result "Subdirectory games have cleaned names with paths" "false"
    fi

    # Show the generated file
    echo ""
    echo "Generated miyoogamelist.xml:"
    echo "----------------------------"
    cat "$SFC_DIR/miyoogamelist.xml"
    echo "----------------------------"

    # Restore backup if it existed
    if [ -f "$SFC_DIR/miyoogamelist.xml.backup" ]; then
        echo ""
        echo "Note: Original miyoogamelist.xml backed up as miyoogamelist.xml.backup"
    fi

else
    print_result "generate_miyoogamelist creates miyoogamelist.xml in SFC directory" "false" "File not found"
fi

# Print summary
echo ""
echo "========================================"
echo "Test Summary:"
echo "  Total:  $TESTS_RUN"
echo "  ${GREEN}Passed: $TESTS_PASSED${NC}"
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "  ${RED}Failed: $TESTS_FAILED${NC}"
else
    echo "  Failed: $TESTS_FAILED"
fi
echo "========================================"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo "${RED}Some tests failed.${NC}"
    exit 1
fi
