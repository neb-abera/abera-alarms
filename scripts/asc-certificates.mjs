#!/usr/bin/env node
// asc-certificates.mjs: keeps the development certificates CI makes from
// piling up on the Apple developer account.
//
//   node scripts/asc-certificates.mjs list                 every certificate
//   node scripts/asc-certificates.mjs snapshot <file>      the CI ones now, by id
//   node scripts/asc-certificates.mjs clean --older-than-hours <n>
//   node scripts/asc-certificates.mjs clean --not-in <file>
//   node scripts/asc-certificates.mjs --self-test          prove the selection
//
// Automatic signing on a fresh runner makes a new Apple Development
// certificate through the App Store Connect key. On 2026-10-10 the account
// reached Apple's limit and the archive failed with "Choose a certificate to
// revoke". So the TestFlight job revokes, before it signs, the CI
// certificates older than a few hours (left by runs that stopped early), and
// after it signs, the one it made itself (not in its snapshot).
//
// Only a development certificate whose name says it was created via the API
// is ever revoked. The one Xcode made on a Mac carries a person's name and
// is never touched. Every run prints the whole list first.
//
// The key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID and
// ASC_KEY_P8 (the .p8 file's text), the same three release.sh reads.

import { sign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const API = "https://api.appstoreconnect.apple.com/v1/certificates";
const DEVELOPMENT = new Set(["DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"]);
const YEAR_MS = 365 * 24 * 3600 * 1000;

/** A development certificate made through the App Store Connect API, as CI makes them. */
export function isCiDevelopment(cert) {
  return DEVELOPMENT.has(cert.certificateType) && /created via api/i.test(`${cert.name} ${cert.displayName ?? ""}`);
}

/** When it was made: Apple issues these for one year. */
export function createdAt(cert) {
  return new Date(Date.parse(cert.expirationDate) - YEAR_MS);
}

/**
 * The CI certificates to revoke: older than `olderThanHours`, or absent from
 * `notIn` (a snapshot of ids taken before this run signed).
 */
export function toRevoke(certs, { now = new Date(), olderThanHours, notIn }) {
  return certs.filter(isCiDevelopment).filter((cert) => {
    if (notIn) return !notIn.has(cert.id);
    return now - createdAt(cert) >= olderThanHours * 3600 * 1000;
  });
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

async function call(method, url) {
  const response = await fetch(url, { method, headers: { Authorization: `Bearer ${token()}` } });
  if (!response.ok) throw new Error(`${method} ${new URL(url).pathname}: ${response.status} ${await response.text()}`);
  return response.status === 204 ? null : response.json();
}

async function certificates() {
  const list = [];
  let url = `${API}?limit=200&fields[certificates]=name,displayName,certificateType,expirationDate,platform`;
  while (url) {
    const page = await call("GET", url);
    for (const item of page.data) list.push({ id: item.id, ...item.attributes });
    url = page.links?.next;
  }
  return list;
}

function print(certs) {
  for (const cert of certs) {
    const mark = isCiDevelopment(cert) ? "ci " : "   ";
    console.log(`${mark}${cert.certificateType.padEnd(20)} ${cert.expirationDate}  ${cert.id}  ${cert.name}`);
  }
  console.log(`${certs.length} certificates, ${certs.filter(isCiDevelopment).length} made by CI`);
}

async function clean(args) {
  const certs = await certificates();
  print(certs);
  const at = args.indexOf("--older-than-hours");
  const from = args.indexOf("--not-in");
  let options;
  if (at >= 0 && Number(args[at + 1]) >= 0) options = { olderThanHours: Number(args[at + 1]) };
  else if (from >= 0 && args[from + 1]) options = { notIn: new Set(JSON.parse(readFileSync(args[from + 1], "utf8"))) };
  else throw new Error("clean needs --older-than-hours <n> or --not-in <file>");
  const doomed = toRevoke(certs, options);
  for (const cert of doomed) {
    await call("DELETE", `${API}/${cert.id}`);
    console.log(`revoked ${cert.id} ${cert.name} (made ${createdAt(cert).toISOString()})`);
  }
  console.log(`revoked ${doomed.length}`);
}

function selfTest() {
  const now = new Date("2026-10-11T12:00:00Z");
  const made = (hoursAgo) => new Date(now - hoursAgo * 3600 * 1000 + YEAR_MS).toISOString();
  const certs = [
    { id: "mac", certificateType: "DEVELOPMENT", name: "Apple Development: Neb Abera (ABC123)", expirationDate: made(48) },
    { id: "dist", certificateType: "DISTRIBUTION", name: "Apple Distribution: Created via API", expirationDate: made(48) },
    { id: "old", certificateType: "DEVELOPMENT", name: "Created via API", expirationDate: made(30) },
    { id: "ios", certificateType: "IOS_DEVELOPMENT", name: "x", displayName: "Created via API", expirationDate: made(5) },
    { id: "new", certificateType: "DEVELOPMENT", name: "Created via API", expirationDate: made(0.5) },
  ];
  const ids = (list) => list.map((cert) => cert.id).join(",");
  const cases = [
    ["older than 2 h", ids(toRevoke(certs, { now, olderThanHours: 2 })), "old,ios"],
    ["not in the snapshot", ids(toRevoke(certs, { now, notIn: new Set(["old", "ios"]) })), "new"],
    ["an empty snapshot", ids(toRevoke(certs, { now, notIn: new Set() })), "old,ios,new"],
    ["a Mac's certificate", String(isCiDevelopment(certs[0])), "false"],
    ["a distribution certificate", String(isCiDevelopment(certs[1])), "false"],
  ];
  let failed = 0;
  for (const [name, got, want] of cases) {
    const ok = got === want;
    if (!ok) failed++;
    console.log(`self-test: ${ok ? "ok" : "FAIL"}: ${name}: ${got}${ok ? "" : ` (want ${want})`}`);
  }
  if (failed) process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
try {
  if (command === "--self-test") selfTest();
  else if (command === "list") print(await certificates());
  else if (command === "snapshot" && args[0]) {
    const ids = (await certificates()).filter(isCiDevelopment).map((cert) => cert.id);
    writeFileSync(args[0], JSON.stringify(ids));
    console.log(`snapshot: ${ids.length} CI certificates`);
  } else if (command === "clean") await clean(args);
  else {
    console.error("usage: asc-certificates.mjs list | snapshot <file> | clean --older-than-hours <n> | clean --not-in <file> | --self-test");
    process.exit(2);
  }
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
