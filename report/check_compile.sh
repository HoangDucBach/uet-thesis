#!/bin/bash

# Script kiểm tra lỗi compile LaTeX

cd "$(dirname "$0")"

echo "=== Kiểm tra compile LaTeX ==="
echo ""

# Xóa các file cũ
rm -f main.aux main.log main.out main.toc main.lof main.lot compile_check.log

# Compile lần 1
echo "Compile lần 1..."
pdflatex -interaction=nonstopmode main.tex > compile_check.log 2>&1

# Compile lần 2 để fix references
echo "Compile lần 2 (fix references)..."
pdflatex -interaction=nonstopmode main.tex >> compile_check.log 2>&1

# Đếm lỗi và warnings
CRITICAL_ERRORS=$(grep -c "! LaTeX Error" compile_check.log 2>/dev/null || echo "0")
WARNINGS=$(grep -c "LaTeX Warning" compile_check.log 2>/dev/null || echo "0")
OVERFULL=$(grep -c "Overfull" compile_check.log 2>/dev/null || echo "0")

echo ""
echo "📊 Kết quả:"
echo "   - Critical Errors: $CRITICAL_ERRORS"
echo "   - Warnings: $WARNINGS"
echo "   - Overfull boxes: $OVERFULL"
echo ""

if [ -f "main.pdf" ]; then
    PAGES=$(pdfinfo main.pdf 2>/dev/null | grep Pages | awk '{print $2}' || echo "?")
    SIZE=$(du -h main.pdf | cut -f1)
    echo "✅ PDF đã được tạo thành công!"
    echo "   - Số trang: $PAGES"
    echo "   - Kích thước: $SIZE"
    echo ""
    
    if [ "$CRITICAL_ERRORS" -gt "0" ]; then
        echo "⚠️  Có $CRITICAL_ERRORS lỗi nghiêm trọng (xem chi tiết bên dưới)"
        echo ""
        grep "! LaTeX Error" compile_check.log | head -10
        echo ""
        echo "... (xem thêm trong compile_check.log)"
    else
        echo "✅ Không có lỗi nghiêm trọng!"
    fi
else
    echo "❌ PDF không được tạo!"
    echo ""
    echo "Các lỗi chính:"
    grep "! LaTeX Error" compile_check.log | head -10
fi

echo ""
echo "📝 Chi tiết đầy đủ trong file: compile_check.log"
