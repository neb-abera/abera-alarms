#!/usr/bin/env node
// asc-capabilities.mjs: puts the capabilities the app's entitlements need on
// its App ID, before the release signs it.
//
//   node scripts/asc-capabilities.mjs ensure <bundle id> <CAPABILITY>...
//   node scripts/asc-capabilities.mjs --self-test
//
// Automatic signing with the App Store Connect key builds a profile from the
// App ID's capabilities. On 2026-11-15 the App Group was not on the App ID,
// the profile "doesn't match the entitlements file", and Neb added it at
// developer.apple.com by hand. HealthKit came next (2026-11-21), so the
// release adds what is missing through the API first. A capability already
// there is left alone. Nothing is ever removed.
//
// The key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID and
// ASC_KEY_P8, the same three release.sh reads.

import { sign } from "node:crypto";

const API = "https://api.appstoreconnect.apple.com/v1";

/** The App ID whose identifier is exactly `identifier`: the API's filter also matches longer ones. */
export function exactBundle(page, identifier) {
  return page.data.find((item) => item.attributes.identifier === identifier) ?? null;
}

/** The capability types `wanted` that the App ID lacks. */
export function missing(page, bundle, wanted) {
  const ids = new Set((bundle.relationships?.bundleIdCapabilities?.data ?? []).map((ref) => ref.id));
  const have = new Set(
    (page.included ?? [])
      .filter((item) => item.type === "bundleIdCapabilities" && ids.has(item.id))
      .map((item) => item.attributes.capabilityType),
  );
  return wanted.filter((type) => !have.has(type));
}

function token() {
  const { ASC_KEY_ID: kid, ASC_ISSUER_ID: iss, ASC_KEY_P8: p8 } = process.env;
  if (!kid || !iss || !p8) throw new Error("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 are required");
  const part = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${part({ alg: "ES256", kid, typ: "JWT" })}.${part({ iss, iat: now, exp: now + 600, aud: "appstoreconnect-v1" })}`;
  const signature = sign("sha256", Buffer.from(unsigned), { key: p8, dsaEncoding: "ieee-p1363" });
  return `${unsigned}.${signature.toString("base64url")}`;
}

async function call(method, path, body) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error(`${method} ${path.split("?")[0]}: ${response.status} ${await response.text()}`);
  return response.status === 204 ? null : response.json();
}

async function ensure(identifier, wanted) {
  const page = await call(
    "GET",
    `/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&include=bundleIdCapabilities&limit=200&limit[bundleIdCapabilities]=50`,
  );
  const bundle = exactBundle(page, identifier);
  if (!bundle) throw new Error(`no App ID ${identifier}`);
  const add = missing(page, bundle, wanted);
  console.log(`${identifier}: wanted ${wanted.join(", ")}; adding ${add.length ? add.join(", ") : "nothing"}`);
  for (const capabilityType of add) {
    await call("POST", "/bundleIdCapabilities", {
      data: {
        type: "bundleIdCapabilities",
        attributes: { capabilityType },
        relationships: { bundleId: { data: { type: "bundleIds", id: bundle.id } } },
      },
    });
    console.log(`${identifier}: added ${capabilityType}`);
  }
}

function selfTest() {
  const page = {
    data: [
      { id: "W", attributes: { identifier: "tech.abera.alarms.widget" }, relationships: {} },
      {
        id: "A",
        attributes: { identifier: "tech.abera.alarms" },
        relationships: { bundleIdCapabilities: { data: [{ id: "c1" }, { id: "c2" }] } },
      },
    ],
    included: [
      { type: "bundleIdCapabilities", id: "c1", attributes: { capabilityType: "APP_GROUPS" } },
      { type: "bundleIdCapabilities", id: "c2", attributes: { capabilityType: "PUSH_NOTIFICATIONS" } },
      { type: "bundleIdCapabilities", id: "c9", attributes: { capabilityType: "HEALTHKIT" } },
    ],
  };
  const cases = [
    ["the exact App ID, not the widget's", exactBundle(page, "tech.abera.alarms")?.id, "A"],
    ["no App ID for an unknown identifier", exactBundle(page, "tech.abera.other"), null],
    ["HealthKit is missing", missing(page, exactBundle(page, "tech.abera.alarms"), ["HEALTHKIT", "APP_GROUPS"]).join(), "HEALTHKIT"],
    ["another App ID's capability does not count", missing(page, exactBundle(page, "tech.abera.alarms.widget"), ["HEALTHKIT"]).join(), "HEALTHKIT"],
    ["nothing to add when all are there", missing(page, exactBundle(page, "tech.abera.alarms"), ["APP_GROUPS"]).join(), ""],
  ];
  let failed = false;
  for (const [name, got, want] of cases) {
    const ok = got === want;
    failed ||= !ok;
    console.log(`self-test: ${ok ? "ok" : "FAIL"}: ${name}: ${got}${ok ? "" : ` (want ${want})`}`);
  }
  if (failed) process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
try {
  if (command === "--self-test") selfTest();
  else if (command === "ensure" && args.length >= 2) await ensure(args[0], args.slice(1));
  else {
    console.error("usage: asc-capabilities.mjs ensure <bundle id> <CAPABILITY>... | --self-test");
    process.exit(2);
  }
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
