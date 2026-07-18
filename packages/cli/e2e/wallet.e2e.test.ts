import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bytesToHex } from "../src/hex";
import { nativeLibraryPath, runCommand } from "./cli";
import {
  addressOutputSchema,
  createOutputSchema,
  ethSignatureOutputSchema,
  pubkeyOutputSchema,
} from "./outputSchemas";
import { psbtForRootPublicKey } from "./psbtFixture";

const walletResetTest = process.env.MACWLT_RUN_WALLET_RESET_TESTS === "1"
  ? test
  : test.skip;

if (process.env.MACWLT_E2E !== "1") {
  describe("macwlt cli e2e", () => {
    test.skip("set MACWLT_E2E=1 or run bun run test:e2e to exercise the native wallet CLI", () => {});
  });
} else {
  describe("macwlt cli e2e", () => {
    test("creates a wallet and exports keys", () => {
      expect(existsSync(nativeLibraryPath), "run make build before bun run test:e2e").toBe(true);

      const created = createOutputSchema.parse(jsonCommand(["create", "--json"]));
      const pubkey = pubkeyOutputSchema.parse(jsonCommand(["pubkey", "m", "--json"]));

      expect(pubkey.publicKey).toBe(created.jointPublicKey);
    }, 30_000);

    test("exports bitcoin and ethereum addresses", () => {
      const bitcoinAddress = addressOutputSchema.parse(jsonCommand(["address", "m", "--type", "bitcoin", "--json"]));
      expect(bitcoinAddress.type).toBe("bitcoin");
      expect(bitcoinAddress.address).toMatch(/^bc1[0-9a-z]+$/);

      const ethereumAddress = addressOutputSchema.parse(jsonCommand(["address", "m", "--type", "ethereum", "--json"]));
      expect(ethereumAddress.type).toBe("ethereum");
      expect(ethereumAddress.address).toMatch(/^0x[0-9A-Fa-f]{40}$/);
    }, 30_000);

    test("exports FROST-backed taproot addresses", () => {
      const taprootAddress = addressOutputSchema.parse(
        jsonCommand(["address", "m/86/0/0/0/0", "--type", "bitcoin-taproot", "--json"]),
      );

      expect(taprootAddress.type).toBe("bitcoin-taproot");
      expect(taprootAddress.address).toMatch(/^bc1p[0-9a-z]+$/);
    }, 60_000);

    test("signs ethereum transaction preimages", () => {
      const ethSignature = ethSignatureOutputSchema.parse(jsonCommand(["sign-eth", "--hex", "01020304", "--json"]));
      expect(ethSignature.signature.endsWith("00") || ethSignature.signature.endsWith("01")).toBe(true);
    }, 30_000);

    test("signs root-key PSBTs", () => {
      const pubkey = pubkeyOutputSchema.parse(jsonCommand(["pubkey", "m", "--json"]));
      const psbt = psbtForRootPublicKey(pubkey.publicKey);
      const psbtPath = join(mkdtempSync(join(tmpdir(), "macwlt-cli-e2e-")), "root.psbt");
      writeFileSync(psbtPath, psbt);

      const signedPsbt = textCommand(["sign-psbt", "--in", psbtPath, "--format", "hex"]).trim();
      expect(signedPsbt).toMatch(/^[0-9a-f]+$/);
      expect(signedPsbt.length).toBeGreaterThan(bytesToHex(psbt).length);
      expect(signedPsbt).toContain(`2202${pubkey.publicKey}`);
    }, 30_000);

    walletResetTest("resets the current wallet when explicitly enabled", () => {
      expect(jsonCommand(["reset", "--yes", "--json"])).toEqual({ reset: true });
    }, 30_000);
  });
}

function jsonCommand(args: readonly string[]): unknown {
  const result = runCommand(args);
  expect(result.exitCode, result.stderr).toBe(0);
  return JSON.parse(result.stdout) as unknown;
}

function textCommand(args: readonly string[]): string {
  const result = runCommand(args);
  expect(result.exitCode, result.stderr).toBe(0);
  return result.stdout;
}
