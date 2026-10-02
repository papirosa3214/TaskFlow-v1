// Извлечение ТЕКСТА из вложения — материал для локальной модели, которая
// нарезает из него задачи (просьба владельца 20.09.2026: большой текст
// приложить файлом в чат, а задачи пусть соберёт локальная модель).
//
// Кто что умеет на .110 (проверено):
//   txt / md          — читаем как есть;
//   pdf               — `pdftotext` (poppler);
//   doc/docx/odt/odf  — `libreoffice --headless --convert-to txt`.
//
// Картинки здесь НЕ распознаём: vision-модели в Ollama нет, а тащить OCR на
// сервер незачем — на телефоне их читает Apple Vision до отправки.
//
// Безопасность: имена и аргументы передаём ЧЕРЕЗ execFile (массивами), без
// shell — пользовательское имя файла в команду не подставляется. Файл берём
// ТОЛЬКО по stored_name (случайный UUID), не по присланному имени.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const execFileAsync = promisify(execFile);

/** Потолок текста, который отдаём модели: 16k-контекст, больше не влезет. */
const MAX_OUT = 24_000;

function clamp(text: string): string {
  const t = text.replace(/\u0000/g, "").trim();
  return t.length > MAX_OUT ? t.slice(0, MAX_OUT) : t;
}

/** Ошибка с текстом, который МОЖНО показать человеку: что случилось и что
 *  делать. Техническая причина (stderr pdftotext/libreoffice) — только в
 *  журнал сервера: раньше она уходила в баннер приложения как есть —
 *  «Command failed: pdftotext -layout /…/uploads/… Syntax Error…» (MAK-13). */
export class AttachmentTextError extends Error {}

function failDetail(e: unknown): string {
  const err = e as { stderr?: string; message?: string };
  return (err?.stderr || err?.message || String(e)).trim().slice(-500);
}

function isTimeout(e: unknown): boolean {
  const err = e as { killed?: boolean; signal?: string; code?: string };
  return Boolean(err?.killed || err?.signal === "SIGTERM" || err?.code === "ETIMEDOUT");
}

function isMissingProgram(e: unknown): boolean {
  return (e as { code?: string })?.code === "ENOENT";
}

const TOO_BIG =
  "Файл слишком большой — не успели прочитать его за отведённое время. " +
  "Разделите его на части поменьше и приложите заново.";
const NO_PROGRAM =
  "На сервере не установлена программа для чтения таких файлов — " +
  "передайте это администратору.";

const DOC_BROKEN =
  "Документ не открывается — возможно, он повреждён или защищён паролем. " +
  "Откройте его у себя, пересохраните и приложите заново.";

const WORD_MIME = [
  "application/msword",
  "application/vnd.openxmlformats-officedocument",
  "application/vnd.oasis.opendocument",
];

export async function extractAttachmentText(
  filePath: string,
  mime: string,
): Promise<string> {
  const m = (mime || "").toLowerCase();

  if (m === "text/plain" || m === "text/markdown") {
    return clamp(fs.readFileSync(filePath, "utf8"));
  }

  if (m === "application/pdf") {
    try {
      const { stdout } = await execFileAsync(
        "pdftotext",
        ["-layout", filePath, "-"],
        { maxBuffer: 32 * 1024 * 1024, timeout: 30_000 },
      );
      return clamp(stdout);
    } catch (e) {
      console.warn(`pdftotext не прочитал ${path.basename(filePath)}:`, failDetail(e));
      if (isTimeout(e)) throw new AttachmentTextError(TOO_BIG);
      if (isMissingProgram(e)) throw new AttachmentTextError(NO_PROGRAM);
      if (/password|encrypt/i.test(failDetail(e))) {
        throw new AttachmentTextError(
          "PDF защищён паролем — прочитать его не получается. " +
            "Снимите защиту и приложите файл заново.",
        );
      }
      throw new AttachmentTextError(
        "PDF-файл повреждён или это не совсем PDF — открыть его не получается. " +
          "Откройте файл у себя, пересохраните («Сохранить как PDF») и приложите заново.",
      );
    }
  }

  if (WORD_MIME.some((prefix) => m.startsWith(prefix))) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "att-txt-"));
    try {
      try {
        await execFileAsync(
          "soffice",
          ["--headless", "--convert-to", "txt:Text", "--outdir", dir, filePath],
          { maxBuffer: 32 * 1024 * 1024, timeout: 60_000 },
        );
      } catch (e) {
        console.warn(`libreoffice не прочитал ${path.basename(filePath)}:`, failDetail(e));
        if (isTimeout(e)) throw new AttachmentTextError(TOO_BIG);
        if (isMissingProgram(e)) throw new AttachmentTextError(NO_PROGRAM);
        throw new AttachmentTextError(DOC_BROKEN);
      }
      const base = path.basename(filePath).replace(/\.[^.]+$/, "") + ".txt";
      const out = path.join(dir, base);
      if (!fs.existsSync(out)) {
        // libreoffice молча не конвертирует битые и запароленные документы.
        console.warn(`libreoffice не создал текст для ${path.basename(filePath)}`);
        throw new AttachmentTextError(DOC_BROKEN);
      }
      return clamp(fs.readFileSync(out, "utf8"));
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  }

  throw new AttachmentTextError(
    "Из файлов такого типа текст пока не достаём — подойдут PDF, Word, " +
      "OpenDocument, TXT и Markdown.",
  );
}
