package sovereign

import (
	"context"
	"fmt"

	"github.com/ledgerwatch/erigon-lib/kv"
	"github.com/ledgerwatch/erigon/eth/ethconfig"
	"github.com/ledgerwatch/erigon/eth/stagedsync/stages"
	"github.com/ledgerwatch/erigon/zk/hermez_db"
	"github.com/ledgerwatch/log/v3"
)

// BootstrapForkHistoryTx seeds fork history using an open write transaction.
func BootstrapForkHistoryTx(tx kv.RwTx, cfg *ethconfig.Zk) error {
	if cfg == nil || !cfg.SkipL1Sync || cfg.InitialForkId == 0 {
		return nil
	}

	hdb := hermez_db.NewHermezDb(tx)

	forkId, _, err := hdb.GetLatestForkHistory()
	if err != nil {
		return fmt.Errorf("GetLatestForkHistory: %w", err)
	}
	if forkId > 0 {
		return nil
	}

	if err := hdb.WriteRollupType(1, cfg.InitialForkId); err != nil {
		return fmt.Errorf("WriteRollupType: %w", err)
	}
	if err := hdb.WriteNewForkHistory(cfg.InitialForkId, 0); err != nil {
		return fmt.Errorf("WriteNewForkHistory: %w", err)
	}
	if err := stages.SaveStageProgress(tx, stages.ForkId, cfg.InitialForkId); err != nil {
		return fmt.Errorf("SaveStageProgress ForkId: %w", err)
	}

	log.Info("Bootstrapped sovereign fork history", "forkId", cfg.InitialForkId)
	return nil
}

// BootstrapForkHistory seeds fork history for standalone sovereign chains that do not sync from L1.
func BootstrapForkHistory(ctx context.Context, db kv.RwDB, cfg *ethconfig.Zk) error {
	if cfg == nil || !cfg.SkipL1Sync || cfg.InitialForkId == 0 {
		return nil
	}

	return db.Update(ctx, func(tx kv.RwTx) error {
		return BootstrapForkHistoryTx(tx, cfg)
	})
}
