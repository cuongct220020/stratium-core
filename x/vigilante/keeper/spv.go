package keeper

import (
    babylonspv "github.com/babylonlabs-io/babylon/x/btclightclient/types"
    babylonschnorr "github.com/babylonlabs-io/babylon/crypto/schnorr"
)


func VerifyBitcoinProof(btcHeader []byte, proof []byte) bool {
    header, err := babylonspv.ParseBitcoinHeader(btcHeader)
    if err != nil {
        return false
    }
    
    return babylonschnorr.Verify(header.Hash, proof)
}