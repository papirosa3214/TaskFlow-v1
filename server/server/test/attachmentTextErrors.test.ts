// MAK-13: битый файл — человеку понятная фраза «что случилось и что делать»,
// а не «Command failed: pdftotext -layout /…/uploads/… Syntax Error…».
// Тест гоняет настоящий pdftotext (poppler), без моков: ровно та ошибка,
// которую видел владелец.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { AttachmentTextError, extractAttachmentText } from "../src/lib/attachmentText.js";

const RAW = /Command failed|Syntax Error|pdftotext|xref|trailer|ENOENT|\/tmp\//;

function hasPdftotext(): boolean {
  try {
    execFileSync("pdftotext", ["-v"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "att-err-"));
afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

describe("текст из вложения: ошибки понятны человеку", () => {
  it.skipIf(!hasPdftotext())("битый PDF → «повреждён… пересохраните», без stderr и путей", async () => {
    const file = path.join(dir, "broken.pdf");
    fs.writeFileSync(file, Buffer.from("%PDF-1.4\n\u0000\u0001 garbage, not a real pdf"));
    const error = await extractAttachmentText(file, "application/pdf").catch((e) => e);
    expect(error).toBeInstanceOf(AttachmentTextError);
    expect(error.message).toMatch(/PDF-файл повреждён/);
    expect(error.message).toMatch(/пересохраните/);
    expect(error.message).not.toMatch(RAW);
  });

  it("неподдерживаемый тип → говорим, какие подойдут", async () => {
    const file = path.join(dir, "x.bin");
    fs.writeFileSync(file, "x");
    const error = await extractAttachmentText(file, "application/octet-stream").catch((e) => e);
    expect(error).toBeInstanceOf(AttachmentTextError);
    expect(error.message).toMatch(/подойдут PDF/);
    expect(error.message).not.toMatch(/octet-stream/);
  });
});
