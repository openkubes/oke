package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"

	"github.com/k3s-io/k3s/pkg/configfilearg"
	"github.com/k3s-io/k3s/pkg/kubectl"
	"github.com/openkubes/oke/pkg/cli/cmds"
	"github.com/sirupsen/logrus"
	"github.com/urfave/cli/v2"
)

func main() {
	// kubectl symlink support
	if filepath.Base(os.Args[0]) == "kubectl" {
		kubectl.Main()
		return
	}

	app := cmds.NewApp()
	app.Commands = []*cli.Command{
		cmds.NewServerCommand(),
		cmds.NewAgentCommand(),
		cmds.NewEtcdSnapshotCommand(),
		cmds.NewCertCommand(),
		cmds.NewSecretsEncryptCommand(),
		cmds.NewTokenCommand(),
		cmds.NewCompletionCommand(),
	}
	if err := app.Run(configfilearg.MustParse(os.Args)); err != nil && !errors.Is(err, context.Canceled) {
		logrus.Fatalf("Error: %v", err)
	}
}
