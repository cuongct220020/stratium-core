package keeper

import (
    "github.com/cosmos/cosmos-sdk/codec"
    storetypes "cosmossdk.io/store/types"
)

type Keeper struct {
    cdc             codec.BinaryCodec
    storeKey        storetypes.StoreKey
	StateTree       *SovereignSMT
}

func NewKeeper(cdc codec.BinaryCodec, key storetypes.StoreKey) Keeper {

	smt, err := InitSMT(smtPath)
	if err != nil {
		panic("Not initialization SMT BadgerDB: " + err.Error())
	}

	return Keeper{
		cdc:             cdc,
		storeKey:        key,
		StateTree:       smt
	}
}