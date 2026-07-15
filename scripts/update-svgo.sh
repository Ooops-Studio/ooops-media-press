#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVGO_VERSION="4.0.1"
ESBUILD_VERSION="0.25.10"
OUTPUT_DIR="$ROOT/Sources/OoopsMediaPress/Resources/SVGO"
WORK="$(mktemp -d /tmp/ooops-media-press-svgo.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to refresh the vendored SVGO bundle." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
npm install --prefix "$WORK" --ignore-scripts --no-audit --no-fund "svgo@$SVGO_VERSION" >/dev/null

cat >"$WORK/entry.mjs" <<'JAVASCRIPT'
import { VERSION, optimize } from "svgo/browser";

const removeExternalResources = {
  name: "ooopsRemoveExternalResources",
  fn: () => ({
    element: {
      enter: (node, parentNode) => {
        if (node.name === "foreignObject") {
          const index = parentNode.children.indexOf(node);
          if (index >= 0) parentNode.children.splice(index, 1);
          return;
        }

        for (const [name, value] of Object.entries(node.attributes)) {
          const normalizedName = name.toLowerCase();
          const normalizedValue = String(value).trim().toLowerCase();
          const safeInlineRaster = /^data:image\/(png|jpe?g|gif|webp|avif)[;,]/i.test(normalizedValue);
          if ((normalizedName === "href" || normalizedName.endsWith(":href")) &&
              !normalizedValue.startsWith("#") && !safeInlineRaster) {
            delete node.attributes[name];
          } else if (/url\(\s*["']?(https?:|file:|\/\/)/i.test(normalizedValue)) {
            delete node.attributes[name];
          }
        }

        if (node.name === "style") {
          const text = node.children.map((child) => child.value || "").join("");
          if (/@import|url\(\s*["']?(https?:|file:|\/\/)/i.test(text)) {
            const index = parentNode.children.indexOf(node);
            if (index >= 0) parentNode.children.splice(index, 1);
          }
        }
      }
    }
  })
};

function makeConfig(settings) {
  const safe = settings.preset === "safe";
  const aggressive = settings.preset === "aggressive";
  const simplifyPaths = Boolean(settings.simplifyPaths);
  const preserveAccessibility = Boolean(settings.preserveAccessibility);
  const preserveIDsAndCSS = Boolean(settings.preserveIDsAndCSS);
  const removeMetadata = Boolean(settings.removeMetadata);

  const plugins = [
    {
      name: "preset-default",
      params: {
        overrides: {
          removeDesc: preserveAccessibility || !aggressive ? false : { removeAny: true },
          removeMetadata: removeMetadata ? {} : false,
          removeEditorsNSData: removeMetadata ? {} : false,
          cleanupIds: preserveIDsAndCSS ? false : {},
          inlineStyles: preserveIDsAndCSS ? false : {},
          minifyStyles: preserveIDsAndCSS ? false : {},
          convertShapeToPath: simplifyPaths ? {} : false,
          convertPathData: simplifyPaths ? {} : false,
          mergePaths: simplifyPaths && !safe ? {} : false,
          collapseGroups: safe ? false : {},
          removeHiddenElems: safe ? false : {},
          removeUnknownsAndDefaults: aggressive ? {} : false,
          moveElemsAttrsToGroup: safe ? false : {},
          moveGroupAttrsToElems: safe ? false : {}
        }
      }
    },
    "removeScripts",
    removeExternalResources
  ];
  if (aggressive && !preserveAccessibility) plugins.splice(1, 0, "removeTitle");

  return {
    multipass: Boolean(settings.multipass),
    floatPrecision: Math.max(0, Math.min(6, Number(settings.decimalPrecision) || 0)),
    js2svg: { pretty: false },
    plugins
  };
}

globalThis.OoopsSVGO = {
  optimize(input, settingsJSON) {
    try {
      const settings = JSON.parse(settingsJSON);
      const result = optimize(input, makeConfig(settings));
      return JSON.stringify({ data: result.data, version: VERSION });
    } catch (error) {
      return JSON.stringify({ error: String(error?.message || error), version: VERSION });
    }
  }
};
JAVASCRIPT

(cd "$WORK" && npx --yes "esbuild@$ESBUILD_VERSION" entry.mjs --bundle --platform=browser --format=iife --minify --outfile="$OUTPUT_DIR/svgo.bundle.js")
cp "$WORK/node_modules/svgo/LICENSE" "$OUTPUT_DIR/LICENSE.txt"
printf '%s\n' "$SVGO_VERSION" >"$OUTPUT_DIR/VERSION"

echo "$OUTPUT_DIR/svgo.bundle.js"
