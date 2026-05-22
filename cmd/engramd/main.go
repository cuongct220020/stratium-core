package main

import (
    "crypto/sha256"
    "fmt"
    "github.com/celestiaorg/smt"
)

func main() {
    // 1. Khởi tạo Storage (In-memory cho prototype)
    db := smt.NewSimpleMap()
    
    // 2. Khởi tạo cây với hàm băm (Sử dụng SHA256 cho demo, hoặc Poseidon cho ZK)
    tree := smt.NewSparseMerkleTree(db, sha256.New())

    // 3. Cập nhật giá trị (Key-Value)
    key := []byte("user_1")
    val := []byte("state_anchored")
    _, err := tree.Update(key, val)
    if err != nil { panic(err) }

    // 4. Lấy Root Hash (Cái này sẽ được commit vào Blockchain State)
    root := tree.Root()
    fmt.Printf("Current Root: %x\n", root)

    // 5. Tạo bằng chứng (Proof) - Để xác thực cho các node khác
    proof, _ := tree.Prove(key)
    
    // 6. Xác thực bằng chứng
    valid := smt.VerifyProof(root, key, proof, val, sha256.New())
    fmt.Printf("Proof valid: %v\n", valid)
}