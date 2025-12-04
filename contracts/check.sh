#!/bin/sh

echo "🔍 Checking environment variables for flash loan test..."

check_var() {
    var_name=$1
    eval var_value=\$$var_name
    if [ -z "$var_value" ]; then
        echo "❌ Missing: $var_name"
        return 1
    else
        echo "✅ Found: $var_name = $var_value"
        return 0
    fi
}

# Check all required variables
missing_count=0

check_var "PACKAGE_ID" || missing_count=$((missing_count + 1))
check_var "FLASH_LOAN_POOL" || missing_count=$((missing_count + 1))
check_var "DEX_POOL_USDC_USDT" || missing_count=$((missing_count + 1))
check_var "COIN_FACTORY_ID" || missing_count=$((missing_count + 1))
check_var "USDC_TYPE" || missing_count=$((missing_count + 1))
check_var "USDT_TYPE" || missing_count=$((missing_count + 1))

echo ""

if [ $missing_count -eq 0 ]; then
    echo "🎉 All required variables are set!"
    echo ""
    echo "📝 PTB Command Preview:"
    echo "sui client ptb \\"
    echo "  --move-call \"$PACKAGE_ID::flash_loan_pool::borrow_flash_loan<$USDC_TYPE>\" \\"
    echo "    @$FLASH_LOAN_POOL 400000000 \\"
    echo "  --assign borrowed \\"
    echo "  --assign receipt \\"
    echo "  # ... rest of commands"
else
    echo "❌ Missing $missing_count required variables"
    echo "Please set them first:"
    echo "export PACKAGE_ID=\"your_package_id\""
    echo "export FLASH_LOAN_POOL=\"your_pool_address\""
    echo "export DEX_POOL_USDC_USDT=\"your_dex_pool\""
    echo "export COIN_FACTORY_ID=\"your_factory\""
    echo "export USDC_TYPE=\"your_usdc_type\""
    echo "export USDT_TYPE=\"your_usdt_type\""
fi