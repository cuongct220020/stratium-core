package main

import (
	"os"

	svrcmd "github.com/cosmos/cosmos-sdk/server/cmd"
	"github.com/engram-network/striatum-core/app"
)

func main() {
	// Initialize the root command for the Striatum node
	rootCmd, _ := svrcmd.NewRootCmd(
		"stratiumd",
		"Engram Protocol Node (Striatum)",
		app.DefaultNodeHome,
		app.DefaultNodeHome,
		app.NewStriatumApp, // Call the App-Chain initializer
	)

	// Execute the command and handle errors if any
	if err := svrcmd.Execute(rootCmd, "STRAT", app.DefaultNodeHome); err != nil {
		os.Exit(1)
	}
}
