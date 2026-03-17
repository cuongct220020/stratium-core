package app

import (
	"github.com/cosmos/cosmos-sdk/baseapp"
	"github.com/cosmos/cosmos-sdk/types/module"

	// Import custom modules from the paper
	"github.com/engram-network/striatum-core/x/babylon_mock"
	"github.com/engram-network/striatum-core/x/fsm"
)

// StriatumApp extends the BaseApp of Cosmos SDK
type StriatumApp struct {
	*baseapp.BaseApp

	// Declare Keepers for core modules
	// (BankKeeper, AuthKeeper, StakingKeeper... will be here)

	// Keepers for the logic of the Research Paper
	BabylonMockKeeper babylon_mock.Keeper
	FsmKeeper         fsm.Keeper
}

// NewStriatumApp initializes the entire network
func NewStriatumApp(...) *StriatumApp {
	app := &StriatumApp{
		BaseApp: baseapp.NewBaseApp(...),
	}

	// 1. Initialize Keepers (Modules)
	app.BabylonMockKeeper = babylon_mock.NewKeeper(...)
	// Note: FSM Keeper takes BabylonMock as input to measure H_anchor
	app.FsmKeeper = fsm.NewKeeper(app.BabylonMockKeeper, ...)

	// 2. Register modules into the Basic Manager of Cosmos
	// 3. Register BeginBlocker functions (important to activate FSM Sensors every block) [3, 4]
	// app.ModuleManager.SetOrderBeginBlockers(fsm.ModuleName, ...)

	return app
}
