package app

import (
	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/types/module"

	"github.com/cuongct220020/engram-sovereign-fsm/x/sovereignty"
)

// EngramApp extends the BaseApp of Cosmos SDK
type EngramApp struct {
	*baseapp.BaseApp

	// Declare Keepers for core modules
	// (BankKeeper, AuthKeeper, StakingKeeper... will be here)

	// Keepers for the logic of the Research Paper
	FsmKeeper         fsm.Keeper
}

// NewStriatumApp initializes the entire network
func NewEngramApp(...) *EngramApp {
	app := &EngramApp{
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