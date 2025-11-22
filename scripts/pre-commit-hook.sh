#!/usr/bin/env bash
#
# Pre-commit hook to prevent accidental commit of secrets
# This hook checks for common secret patterns before allowing a commit
#

# Don't exit on error for pattern matching
set +e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Running pre-commit security checks..."

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}✅ No files to check${NC}"
    exit 0
fi

FOUND_ISSUES=0

# Check 1: Forbidden files
echo "  → Checking for forbidden files..."
FORBIDDEN_PATTERNS=(
    '\.env$'
    '\.pem$'
    '\.key$'
    '_id_rsa'
    '_id_ed25519'
    '_id_ecdsa'
    '\.p12$'
    '\.pfx$'
)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    matches=$(echo "$STAGED_FILES" | grep -E "$pattern" || true)
    if [ -n "$matches" ]; then
        echo -e "${RED}❌ BLOCKED: Forbidden file(s) detected:${NC}"
        echo "$matches" | sed 's/^/     /'
        FOUND_ISSUES=1
    fi
done

# Check 2: Scan for secrets in file contents
echo "  → Scanning for secrets in file contents..."

check_pattern() {
    local content="$1"
    local pattern="$2"
    local desc="$3"
    local file="$4"

    matches=$(echo "$content" | grep -E "$pattern" || true)
    if [ -n "$matches" ]; then
        # Exclude placeholders
        if ! echo "$matches" | grep -qE '(\.\.\.\.+|example|placeholder|your-.*-here|XXXX|redacted|template)'; then
            echo -e "${RED}❌ BLOCKED: $desc found in $file${NC}"
            echo "$matches" | head -3 | sed 's/^/     /'
            return 1
        fi
    fi
    return 0
}

for file in $STAGED_FILES; do
    # Skip binary files
    if [ -f "$file" ] && file "$file" | grep -q text; then
        CONTENT=$(git show ":$file" 2>/dev/null || true)

        if [ -n "$CONTENT" ]; then
            # Check for Google OAuth secrets
            if ! check_pattern "$CONTENT" "GOCSPX-[A-Za-z0-9_-]+" "Google OAuth Client Secret" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for Google Client IDs
            if ! check_pattern "$CONTENT" "[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com" "Google OAuth Client ID" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for AWS keys
            if ! check_pattern "$CONTENT" "AKIA[0-9A-Z]{16}" "AWS Access Key" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for GitHub tokens
            if ! check_pattern "$CONTENT" "ghp_[0-9a-zA-Z]{36}" "GitHub Personal Access Token" "$file"; then
                FOUND_ISSUES=1
            fi

            if ! check_pattern "$CONTENT" "gho_[0-9a-zA-Z]{36}" "GitHub OAuth Token" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for OpenAI keys
            if ! check_pattern "$CONTENT" "sk-[a-zA-Z0-9]{48}" "OpenAI API Key" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for Slack tokens
            if ! check_pattern "$CONTENT" "xox[baprs]-[0-9a-zA-Z-]+" "Slack Token" "$file"; then
                FOUND_ISSUES=1
            fi

            # Check for private keys (simple check)
            if echo "$CONTENT" | grep -q "BEGIN.*PRIVATE KEY"; then
                if ! echo "$CONTENT" | grep "BEGIN.*PRIVATE KEY" | grep -qE '(example|placeholder|template)'; then
                    echo -e "${RED}❌ BLOCKED: Private Key found in $file${NC}"
                    FOUND_ISSUES=1
                fi
            fi
        fi
    fi
done

# Check 3: Ensure YAML configs use environment variables for secrets
echo "  → Checking config files use environment variables..."
for file in $STAGED_FILES; do
    if [[ "$file" =~ \.(yaml|yml)$ ]] && [ -f "$file" ]; then
        CONTENT=$(git show ":$file" 2>/dev/null || true)

        # Check for hardcoded OAuth credentials
        if echo "$CONTENT" | grep -E 'client(Id|Secret)' | grep -qv '\$\{'; then
            # Make sure they're not using placeholders
            if ! echo "$CONTENT" | grep -E 'client(Id|Secret)' | grep -qE '(\.\.\.+|example|your-)'; then
                echo -e "${YELLOW}⚠️  WARNING: $file may contain hardcoded OAuth credentials${NC}"
                echo -e "${YELLOW}   Consider using: \${GOOGLE_CLIENT_ID} and \${GOOGLE_CLIENT_SECRET}${NC}"
                echo "$CONTENT" | grep -E 'client(Id|Secret)' | head -2 | sed 's/^/     /'
                FOUND_ISSUES=1
            fi
        fi
    fi
done

# Final verdict
if [ $FOUND_ISSUES -eq 1 ]; then
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  COMMIT BLOCKED: Security issues detected                 ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Possible actions:"
    echo "  1. Remove the secrets and use environment variables instead"
    echo "  2. Update .gitignore to exclude sensitive files"
    echo "  3. If this is a false positive, bypass with:"
    echo "     git commit --no-verify"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ All security checks passed!${NC}"
exit 0
