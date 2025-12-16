# Kịch bản Kiểm thử Hệ thống Phát hiện Rủi ro

---

## Kịch bản 1: Vòng lặp Đòn bẩy (Rủi ro Thấp)

**Mô tả:** Người dùng thực hiện chiến lược đòn bẩy: Thế chấp WETH -> Vay USDC -> Swap USDC sang WETH -> Tiếp tục thế chấp WETH.

**Input (Tình hình):**

- **Tài sản thế chấp ban đầu:** 50 WETH
- **Khoản vay:** 10,000 USDC
- **Hành động:** Vay USDC để mua thêm WETH và tái thế chấp.

**Output (Kết quả mong đợi):**

- **Điểm Rủi ro:** < 30 (An toàn)
- **Lý do:** Tỷ lệ vay trên giá trị tài sản (LTV) vẫn ở mức thấp (~2%), hành động swap không gây biến động giá lớn.

---

## Kịch bản 2: Tấn công Sandwich (Rủi ro Trung bình)

**Mô tả:** Attacker thực hiện tấn công Sandwich lên nạn nhân:

1. **Front-run:** Attacker swap lượng lớn USDC -> WETH để đẩy giá lên.
2. **Victim Trade:** Nạn nhân swap USDC -> WETH với giá cao (bị trượt giá).
3. **Back-run:** Attacker swap ngược WETH -> USDC để chốt lời.

**Input (Tình hình):**

- **Front-run:** Swap 200,000 USDC -> WETH (Attacker)
- **Victim Trade:** Swap 50,000 USDC -> WETH (Nạn nhân)
- **Back-run:** Swap 1,900 WETH -> USDC (Attacker)

**Output (Kết quả mong đợi):**

- **Điểm Rủi ro:** 30-70 (Cảnh báo)
- **Lý do:** Phát hiện biến động giá bất thường trong thời gian ngắn và mô hình giao dịch kẹp lệnh (Sandwich pattern).

---

## Kịch bản 3: Tấn công Thao túng Oracle (Nghiêm trọng)

**Mô tả:** Vector tấn công đầy đủ: Flash Loan -> Thao túng giá Oracle -> Vay với tài sản thế chấp bị thổi phồng -> Trả Flash Loan.

**Input (Tình hình):**

- **Flash Loan:** 200,000 USDC
- **Thao túng giá:** Dùng 100,000 USDC swap sang WETH để đẩy giá WETH lên cao.
- **Thế chấp:** 10 WETH (giá trị bị thổi phồng).
- **Vay:** 150,000 USDC (dựa trên giá trị ảo).
- **Trả nợ:** Hoàn trả Flash Loan từ tiền vay được.

**Output (Kết quả mong đợi):**

- **Điểm Rủi ro:** > 90 (Nghiêm trọng)
- **Lý do:** Phát hiện thao túng Oracle (giá lệch quá lớn so với thị trường), sử dụng Flash Loan để tấn công, và tỷ lệ vay bất thường so với tài sản thực.
