package keeper

import (
	"cosmossdk.io/collections"
	"cosmossdk.io/core/store"
	"github.com/cosmos/cosmos-sdk/codec"
	"github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty/types"
	"github.com/iden3/go-merkletree-sql/v2"
)

type Keeper struct {
	cdc          codec.Codec
	storeService store.KVStoreService
	Schema       collections.Schema

	// State lưu trữ FSM
	FSMState   collections.Item[string]
	SafeBlocks collections.Item[uint64]
	Metrics    collections.Item[types.PeripheralMetrics]

	// SMT Tree
	Tree *merkletree.MerkleTree
}

func NewKeeper(storeService store.KVStoreService, cdc codec.Codec, smtStore merkletree.Storage) *Keeper {
	sb := collections.NewSchemaBuilder(storeService)

	k := &Keeper{
		cdc:          cdc,
		storeService: storeService,
		FSMState:     collections.NewItem(sb, collections.NewPrefix(1), "fsm_state", collections.StringValue),
		SafeBlocks:   collections.NewItem(sb, collections.NewPrefix(2), "safe_blocks", collections.Uint64Value),
		Metrics:      collections.NewItem(sb, collections.NewPrefix(3), "metrics", collections.ProtoValue[types.PeripheralMetrics](cdc)),
	}

	// Khởi tạo SMT với storage adapter được inject vào
	tree, err := merkletree.NewMerkleTree(context.Background(), smtStore, 256)
	if err != nil {
		panic(err)
	}
	k.Tree = tree

	schema, err := sb.Build()
	if err != nil {
		panic(err)
	}
	k.Schema = schema

	return k
}
