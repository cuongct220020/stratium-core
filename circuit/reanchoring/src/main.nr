// circuit/reanchoring/src/main.nr

struct Header {
    prev_hash: Field,
    fsm_state: Field,        // 2: SOVEREIGN, 3: RECOVERING
    withdrawal_locked: Field, // 1: true, 0: false
    state_root: Field,
}

// Giả sử ta chứng minh một chuỗi có độ dài cố định N cho dễ dàng trong Noir
fn main(
    rt_last: pub Field,   // Root của block đã anchored cuối cùng
    rt_new: pub Field,    // Root của block đề xuất phục hồi
    headers: [Header; 4], // Ví dụ chuỗi phục hồi có 4 block
) {
    // 1. Điều kiện (a): Tính liên tục của chuỗi
    // Header đầu tiên phải trỏ về rt_last (hoặc hash của header trước đó)
    // Và các header phải nối tiếp nhau bằng Poseidon hash
    
    // Lưu ý: Poseidon2 trong Noir thường cần cấu hình tham số
    for i in 1..4 {
        let computed_prev_hash = std::hash::poseidon::bn254::hash_1([
            // Hash header trước đó
            hash_header(headers[i-1]) 
        ]);
        assert(headers[i].prev_hash == computed_prev_hash);
    }

    // 2. Điều kiện (b) & (c): Chính sách FSM và Bảo mật
    for i in 0..4 {
        // FSM State phải là SOVEREIGN (2) hoặc RECOVERING (3)
        assert(headers[i].fsm_state == 2 || headers[i].fsm_state == 3);
        // Withdrawals phải được khóa
        assert(headers[i].withdrawal_locked == 1);
    }

    // 3. Điều kiện (d): Binding root
    assert(headers[0].prev_hash == rt_last); 
    assert(headers[3].state_root == rt_new);
}

fn hash_header(h: Header) -> Field {
    std::hash::poseidon::bn254::hash_4([h.prev_hash, h.fsm_state, h.withdrawal_locked, h.state_root])
}