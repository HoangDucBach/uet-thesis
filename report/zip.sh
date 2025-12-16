#!/bin/bash

# Script để tạo file zip cho Overleaf
# Loại bỏ các file không cần thiết (.aux, .log, .pdf, etc.)

cd "$(dirname "$0")"

ZIP_FILE="uet-thesis-overleaf.zip"

# Xóa file zip cũ nếu có
if [ -f "$ZIP_FILE" ]; then
    rm "$ZIP_FILE"
    echo "Đã xóa file zip cũ"
fi

# Tạo file zip với các file cần thiết
zip -r "$ZIP_FILE" \
    main.tex \
    chapter/ \
    cover/ \
    figures/ \
    -x "*.aux" \
    -x "*.log" \
    -x "*.pdf" \
    -x "*.fdb_latexmk" \
    -x "*.fls" \
    -x "*.out" \
    -x "*.synctex.gz" \
    -x "*.toc" \
    -x "*.lof" \
    -x "*.lot" \
    -x "*.bbl" \
    -x "*.blg" \
    -x "*.bcf" \
    -x "*.run.xml" \
    -x "*~" \
    -x "*.swp" \
    -x ".DS_Store" \
    -x "README.md" \
    -x "*.docx" \
    -x "*.sh"

echo "Đã tạo file zip: $ZIP_FILE"
echo "Kích thước: $(du -h "$ZIP_FILE" | cut -f1)"
echo ""
echo "Các file đã được đóng gói:"
unzip -l "$ZIP_FILE" | tail -n +4 | head -n -2

