package app

import (
	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/types/module"

	"github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty"
	"github.com/cuongct220020/engram-sovereign-fsm/x/da"
	"github.com/cuongct220020/engram-sovereign-fsm/x/vigilante"
)

// StriatumApp extends the BaseApp of Cosmos SDK
type StriatumApp struct {
	*baseapp.BaseApp

	// Declare Keepers for core modules
	// (BankKeeper, AuthKeeper, StakingKeeper... will be here)

	// Keepers for the logic of the Research Paper
	FsmKeeper         fsm.Keeper
}

// NewStriatumApp initializes the entire network
func NewStriatumApp(...) *StriatumApp {
	app := &StriatumApp{
		BaseApp: baseapp.NewBaseApp(...),
	}

	// 1. Initialize Keepers (Modules)
	smtPath := filepath.Join(cast.ToString(appOpts.Get("home")), "data", "sovereign_smt")

	app.SovereigntyKeeper = sovereigntykeeper.NewKeeper(
		appCodec,
		keys[sovereigntytypes.StoreKey],
		app.DAKeeper,
		app.VigilanteKeeper,
		smtPath,
	)

	// 2. Register modules into the Basic Manager of Cosmos
	// 3. Register BeginBlocker functions (important to activate FSM Sensors every block) [3, 4]
	// app.ModuleManager.SetOrderBeginBlockers(fsm.ModuleName, ...)

	return app
}



// app/app.go
func VerifyVoteExtensionHandler(daKeeper da.Keeper, vigKeeper vigilante.Keeper) sdk.VerifyVoteExtensionHandler {
    return func(ctx sdk.Context, req abci.RequestVerifyVoteExtension) (abci.ResponseVerifyVoteExtension, error) {
        var ext types.EngramVoteExtension
        if err := ext.Unmarshal(req.VoteExtension); err != nil {
            return abci.ResponseVerifyVoteExtension{Status: abci.VerifyVoteExtensionStatus_REJECT}, nil
        }

        // Route to DA Module for cryptographic validation
        if !daKeeper.VerifyCelestiaProof(ctx, ext.DaHeight, ext.DaCommitment, ext.CelestiaProof) {
            return abci.ResponseVerifyVoteExtension{Status: abci.VerifyVoteExtensionStatus_REJECT}, nil
        }

        // Route to Vigilante Module for SPV validation
        if !vigKeeper.VerifyBitcoinProof(ctx, ext.HSubmitted, ext.HAnchored, ext.BtcHeader, ext.BabylonProof) {
            return abci.ResponseVerifyVoteExtension{Status: abci.VerifyVoteExtensionStatus_REJECT}, nil
        }

        return abci.ResponseVerifyVoteExtension{Status: abci.VerifyVoteExtensionStatus_ACCEPT}, nil
    }
}
