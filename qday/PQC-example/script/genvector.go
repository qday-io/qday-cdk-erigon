//go:build pqcgen

// Command genvector generates an ML-DSA-65 payload and writes it to `.env`
// for Verify.s.sol (Foundry loads qday/example/.env automatically).
//
//	go run -tags pqcgen ./qday/example/script/genvector.go
package main

import (
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/qday-io/qday-pqc-sdk/pqc"
)

const (
	algMLDSA65    uint64 = 2
	pqcAlgNameLen        = 8
	pqcMLDSA65Pk         = 1952
	pqcMLDSA65Sig        = 3309

	defaultPqcVerify = "0x610178dA211FEF7D417bC0e6FeD39F05609AD788"
)

func main() {
	msg := []byte("qday pqcVerify")
	if v := os.Getenv("MESSAGE_TEXT"); v != "" {
		msg = []byte(v)
	}

	signer, err := pqc.Generate(pqc.AlgMLDSA65)
	if err != nil {
		log.Fatalf("generate: %v", err)
	}
	defer signer.Clean()

	sig, err := signer.Sign(msg)
	if err != nil {
		log.Fatalf("sign: %v", err)
	}
	pk := signer.PublicKey()
	if len(pk) != pqcMLDSA65Pk || len(sig) != pqcMLDSA65Sig {
		log.Fatalf("unexpected sizes: pk=%d sig=%d", len(pk), len(sig))
	}

	raw := make([]byte, pqcAlgNameLen+len(pk)+len(sig)+len(msg))
	binary.BigEndian.PutUint64(raw[:pqcAlgNameLen], algMLDSA65)
	copy(raw[pqcAlgNameLen:], pk)
	copy(raw[pqcAlgNameLen+len(pk):], sig)
	copy(raw[pqcAlgNameLen+len(pk)+len(sig):], msg)

	path, err := envFilePath()
	if err != nil {
		log.Fatalf("env path: %v", err)
	}
	vals := loadEnv(path)
	if _, ok := vals["PQC_VERIFY"]; !ok {
		vals["PQC_VERIFY"] = envOr("PQC_VERIFY", defaultPqcVerify)
	}
	vals["ALG"] = fmt.Sprintf("%d", algMLDSA65)
	vals["PUBKEY"] = "0x" + hex.EncodeToString(pk)
	vals["SIGNATURE"] = "0x" + hex.EncodeToString(sig)
	vals["MESSAGE"] = "0x" + hex.EncodeToString(msg)
	vals["INPUT"] = "0x" + hex.EncodeToString(raw)

	if err := writeEnv(path, vals); err != nil {
		log.Fatalf("write %s: %v", path, err)
	}
	fmt.Printf("wrote %s\n", path)
	fmt.Printf("ALG=%s PQC_VERIFY=%s\n", vals["ALG"], vals["PQC_VERIFY"])
	fmt.Printf("PUBKEY bytes=%d SIGNATURE bytes=%d MESSAGE bytes=%d\n", len(pk), len(sig), len(msg))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envFilePath() (string, error) {
	if p := os.Getenv("ENV_FILE"); p != "" {
		return p, nil
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for _, dir := range []string{cwd, filepath.Join(cwd, "qday", "example")} {
		if _, err := os.Stat(filepath.Join(dir, "foundry.toml")); err == nil {
			return filepath.Join(dir, ".env"), nil
		}
	}
	return filepath.Join(cwd, ".env"), nil
}

func loadEnv(path string) map[string]string {
	vals := make(map[string]string)
	data, err := os.ReadFile(path)
	if err != nil {
		return vals
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		vals[strings.TrimSpace(k)] = strings.TrimSpace(v)
	}
	return vals
}

func writeEnv(path string, vals map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	order := []string{"PQC_VERIFY", "ALG", "PUBKEY", "SIGNATURE", "MESSAGE", "INPUT"}
	seen := make(map[string]bool, len(order))
	var b strings.Builder
	for _, k := range order {
		fmt.Fprintf(&b, "%s=%s\n", k, vals[k])
		seen[k] = true
	}
	for k, v := range vals {
		if seen[k] {
			continue
		}
		fmt.Fprintf(&b, "%s=%s\n", k, v)
	}
	return os.WriteFile(path, []byte(b.String()), 0o600)
}
