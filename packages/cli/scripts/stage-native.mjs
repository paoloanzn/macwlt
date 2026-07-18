import { execFileSync } from "node:child_process";
import {
  accessSync,
  constants,
  cpSync,
  existsSync,
  mkdirSync,
  rmSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform !== "darwin" || process.arch !== "arm64") {
  throw new Error(
    `@macwlt/cli currently publishes arm64 macOS artifacts; received ${process.platform}-${process.arch}`,
  );
}

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryDirectory = resolve(packageDirectory, "../..");
const buildDirectory = join(repositoryDirectory, "build");
const nativeDirectory = join(packageDirectory, "native");

const artifacts = [
  {
    source: join(buildDirectory, "libmacwlt.dylib"),
    destination: join(nativeDirectory, "libmacwlt.dylib"),
  },
  {
    source: join(buildDirectory, "com.macwlt.SigningService.xpc"),
    destination: join(nativeDirectory, "com.macwlt.SigningService.xpc"),
  },
];

const missingArtifacts = artifacts
  .map(({ source }) => source)
  .filter((source) => !existsSync(source));

if (missingArtifacts.length > 0) {
  throw new Error(
    `Native build artifacts are missing:\n${missingArtifacts.join("\n")}\nRun "make build" before packing.`,
  );
}

rmSync(nativeDirectory, { recursive: true, force: true });
mkdirSync(nativeDirectory, { recursive: true });

for (const artifact of artifacts) {
  cpSync(artifact.source, artifact.destination, {
    recursive: true,
    preserveTimestamps: true,
  });
}

const bundledLibrary = join(nativeDirectory, "libmacwlt.dylib");
const bundledService = join(
  nativeDirectory,
  "com.macwlt.SigningService.xpc",
);
const bundledServiceExecutable = join(
  bundledService,
  "Contents/MacOS/com.macwlt.SigningService",
);
const bundledServiceDependency = join(
  bundledService,
  "Contents/Frameworks/libsecp256k1.6.dylib",
);

const requiredBundledFiles = [
  bundledLibrary,
  join(bundledService, "Contents/Info.plist"),
  bundledServiceExecutable,
  bundledServiceDependency,
];

const missingBundledFiles = requiredBundledFiles.filter(
  (path) => !existsSync(path),
);
if (missingBundledFiles.length > 0) {
  throw new Error(
    `The staged native bundle is incomplete:\n${missingBundledFiles.join("\n")}`,
  );
}

try {
  accessSync(bundledServiceExecutable, constants.X_OK);
} catch {
  throw new Error(
    `The staged signing service is not executable: ${bundledServiceExecutable}`,
  );
}

const machOFiles = [
  bundledLibrary,
  bundledServiceExecutable,
  bundledServiceDependency,
];

for (const path of machOFiles) {
  const description = execFileSync("/usr/bin/file", ["-b", path], {
    encoding: "utf8",
  });
  if (!description.includes("arm64")) {
    throw new Error(`Expected an arm64 Mach-O artifact at ${path}: ${description}`);
  }
}

execFileSync(
  "/usr/bin/codesign",
  ["--verify", "--strict", bundledLibrary],
  { stdio: "inherit" },
);
execFileSync(
  "/usr/bin/codesign",
  [
    "--verify",
    "--deep",
    "--strict",
    bundledService,
  ],
  { stdio: "inherit" },
);

console.log(`Staged native artifacts in ${nativeDirectory}`);
