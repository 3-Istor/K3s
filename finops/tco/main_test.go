package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func baseTCO() TCO {
	var t TCO
	t.Currency = "EUR"
	t.Power.MeasuredWatts = 1000
	t.Power.EURPerKWhTTC = 0.2
	t.Network.InternetEURPerMonth = 73
	t.Network.PlatformShare = 1
	t.Cluster.VCPU = 4
	t.Cluster.RAMGiB = 10
	t.Cluster.StorageGiB = 100
	t.Cluster.Split.CPU = 0.5
	t.Cluster.Split.RAM = 0.3
	t.Cluster.Split.Storage = 0.2
	return t
}

func TestPrices_AddsEnergyNetworkAndAmortization(t *testing.T) {
	tco := baseTCO()
	tco.Hypervisors = []Hypervisor{{Name: "n1", PurchaseEUR: 730, AmortizationMonths: 10}}

	p, err := tco.Prices()

	require.NoError(t, err)
	// 0.2 €/h energy + 0.1 €/h network + 0.1 €/h amortization
	assert.InDelta(t, 0.4, p.ClusterEURPerHour, 1e-9)
}

func TestPrices_SplitsClusterCostPerResourceUnit(t *testing.T) {
	tco := baseTCO()

	p, err := tco.Prices()

	require.NoError(t, err)
	assert.InDelta(t, 0.3*0.5/4, p.CPUPerVCPUHour, 1e-9)
	assert.InDelta(t, 0.3*0.3/10, p.RAMPerGiBHour, 1e-9)
	assert.InDelta(t, 0.3*0.2/100, p.StoragePerGiBHour, 1e-9)
}

func TestPrices_IgnoresAmortization_WhenHardwareWasFree(t *testing.T) {
	tco := baseTCO()
	tco.Hypervisors = []Hypervisor{{Name: "n1", PurchaseEUR: 0}}

	p, err := tco.Prices()

	require.NoError(t, err)
	assert.InDelta(t, 0.3, p.ClusterEURPerHour, 1e-9)
}

func TestPrices_ReturnsError_WhenInputIsInvalid(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*TCO)
	}{
		{"split does not sum to one", func(t *TCO) { t.Cluster.Split.CPU = 0.9 }},
		{"no vcpu", func(t *TCO) { t.Cluster.VCPU = 0 }},
		{"purchase without amortization", func(t *TCO) {
			t.Hypervisors = []Hypervisor{{Name: "n1", PurchaseEUR: 100}}
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tco := baseTCO()
			tt.mutate(&tco)

			_, err := tco.Prices()

			assert.Error(t, err)
		})
	}
}

func TestRun_FailsCheck_WhenGeneratedFileIsStale(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "values.yaml")
	require.NoError(t, run("../onprem-tco.yaml", out, false))
	require.NoError(t, os.WriteFile(out, []byte("stale\n"), 0o644))

	err := run("../onprem-tco.yaml", out, true)

	assert.ErrorContains(t, err, "out of date")
}

func TestRun_PassesCheck_WhenGeneratedFileIsCurrent(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "values.yaml")
	require.NoError(t, run("../onprem-tco.yaml", out, false))

	err := run("../onprem-tco.yaml", out, true)

	assert.NoError(t, err)
}

func TestPrices_AddsMarketStoragePricePerGiBHour(t *testing.T) {
	tco := baseTCO()
	tco.Cluster.Split.CPU = 0.7
	tco.Cluster.Split.RAM = 0.3
	tco.Cluster.Split.Storage = 0
	tco.Storage.EURPerGiBMonth = 7.3

	p, err := tco.Prices()

	require.NoError(t, err)
	assert.InDelta(t, 0.01, p.StoragePerGiBHour, 1e-9)
}
